# PowerShell script for setting up posting server on Windows
# Requires PowerShell 5.0 or later

param(
    [switch]$Force = $false
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to clean up on error
function Cleanup {
    Write-Host "❌ An error occurred. Cleaning up..." -ForegroundColor Red
    if (Test-Path "posting_server") {
        Remove-Item -Recurse -Force "posting_server" -ErrorAction SilentlyContinue
    }
    if ($script:TEMP_DIR -and (Test-Path $script:TEMP_DIR)) {
        Remove-Item -Recurse -Force $script:TEMP_DIR -ErrorAction SilentlyContinue
    }
    exit 1
}

# Set up error handling
trap { Cleanup }

# Function to check if a command exists
function Test-Command {
    param($CommandName)
    $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
}

# Function to install Node.js
function Install-NodeJS {
    Write-Host "📦 Installing Node.js..." -ForegroundColor Yellow
    
    # Check if Chocolatey is available
    if (Test-Command choco) {
        choco install nodejs -y
    } elseif (Test-Command winget) {
        winget install OpenJS.NodeJS
    } else {
        Write-Host "❌ Please install Node.js manually from https://nodejs.org/" -ForegroundColor Red
        Write-Host "   Or install Chocolatey/winget package manager first" -ForegroundColor Yellow
        exit 1
    }
    
    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
}

# Function to install Git
function Install-Git {
    Write-Host "📦 Installing Git..." -ForegroundColor Yellow
    
    # Check if Chocolatey is available
    if (Test-Command choco) {
        choco install git -y
    } elseif (Test-Command winget) {
        winget install Git.Git
    } else {
        Write-Host "❌ Please install Git manually from https://git-scm.com/" -ForegroundColor Red
        Write-Host "   Or install Chocolatey/winget package manager first" -ForegroundColor Yellow
        exit 1
    }
    
    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
}

# Function to create scheduled task for PM2 resurrection
function Create-PM2StartupTask {
    Write-Host "🔧 Setting up PM2 to start on system boot using Task Scheduler..." -ForegroundColor Yellow
    
    # Get PM2 and Node paths
    $nodePath = (Get-Command node).Source
    $pm2Path = (Get-Command pm2).Source
    
    # Create a batch file that will run PM2 resurrect
    $batchContent = @"
@echo off
timeout /t 30 /nobreak >nul
cd /d "$PWD"
"$nodePath" "$pm2Path" resurrect
"$nodePath" "$pm2Path" save
"@
    
    $batchFilePath = Join-Path $PWD "pm2-startup.bat"
    $batchContent | Out-File -FilePath $batchFilePath -Encoding ASCII
    
    # Create the scheduled task
    $taskName = "PM2-AutoStart"
    $taskDescription = "Automatically start PM2 processes on system startup"
    
    # Remove existing task if it exists
    try {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}
    
    # Create new scheduled task
    $action = New-ScheduledTaskAction -Execute $batchFilePath
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = "PT1M"  # 1 minute delay after startup
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
    
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description $taskDescription
    
    Write-Host "✅ Scheduled task '$taskName' created successfully!" -ForegroundColor Green
    Write-Host "   Batch file created at: $batchFilePath" -ForegroundColor Cyan
}

# Main script execution
Write-Host "🚀 Starting Windows Posting Server Setup..." -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Green

# Check and install Node.js if not present
if (-not (Test-Command node)) {
    Write-Host "❌ Node.js is not installed." -ForegroundColor Red
    Install-NodeJS
    Start-Sleep -Seconds 2
}

# Verify Node.js installation
if (-not (Test-Command node)) {
    Write-Host "❌ Node.js installation failed or PATH not updated. Please restart PowerShell and try again." -ForegroundColor Red
    exit 1
}

# Check and install Git if not present
if (-not (Test-Command git)) {
    Write-Host "❌ Git is not installed." -ForegroundColor Red
    Install-Git
    Start-Sleep -Seconds 2
}

# Verify Git installation
if (-not (Test-Command git)) {
    Write-Host "❌ Git installation failed or PATH not updated. Please restart PowerShell and try again." -ForegroundColor Red
    exit 1
}

# Check if PM2 is installed, if not install it globally
if (-not (Test-Command pm2)) {
    Write-Host "📦 Installing PM2 globally..." -ForegroundColor Yellow
    npm install -g pm2
}

# Remove existing posting_server directory if it exists
if (Test-Path "posting_server") {
    Write-Host "🗑️  Removing existing posting_server directory..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force "posting_server"
}

# Create logs directory if it doesn't exist
if (-not (Test-Path "logs")) {
    New-Item -ItemType Directory -Path "logs" | Out-Null
}

# Setup posting server
Write-Host "🔧 Setting up posting server..." -ForegroundColor Yellow

# Clone the repository to a temporary directory
Write-Host "⬇️ Downloading complete posting server from GitHub..." -ForegroundColor Yellow
$script:TEMP_DIR = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ }
git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git $script:TEMP_DIR

# Copy only the posting_server folder to our target location
Copy-Item -Recurse -Path (Join-Path $script:TEMP_DIR "posting_server") -Destination "."

# Clean up temporary directory
Remove-Item -Recurse -Force $script:TEMP_DIR

# Navigate to posting_server directory
Set-Location "posting_server"

# Install posting server dependencies
Write-Host "📦 Installing posting server dependencies..." -ForegroundColor Yellow
npm install

# Set posting server permissions (Windows equivalent)
Write-Host "🔒 Setting up permissions..." -ForegroundColor Yellow
# In Windows, we mainly need to ensure the logs directory is accessible
if (-not (Test-Path "../logs")) {
    New-Item -ItemType Directory -Path "../logs" | Out-Null
}

# Start the server using PM2 with exponential backoff restart
Write-Host "🚀 Starting posting server with PM2..." -ForegroundColor Yellow
pm2 start server.js --name "posting-server" --log ../logs/posting-server.log --exp-backoff-restart-delay=100

# Save PM2 process list
Write-Host "💾 Saving PM2 process list..." -ForegroundColor Yellow
pm2 save

# Go back to parent directory for scheduled task creation
Set-Location ".."

# Setup Task Scheduler for PM2 startup
Create-PM2StartupTask

# Verify if the server is running
Write-Host "🔍 Verifying server status..." -ForegroundColor Yellow
$pm2Status = pm2 list | Out-String

if ($pm2Status -match "posting-server.*online") {
    Write-Host "✅ Posting server is running!" -ForegroundColor Green
} else {
    Write-Host "⚠️ Posting server is not running. Attempting to restart..." -ForegroundColor Yellow
    pm2 restart posting-server
    Start-Sleep -Seconds 3
    $pm2Status = pm2 list | Out-String
    
    if ($pm2Status -match "posting-server.*online") {
        Write-Host "✅ Posting server restarted successfully!" -ForegroundColor Green
    } else {
        Write-Host "❌ Failed to start posting server. Please check logs with 'pm2 logs posting-server'." -ForegroundColor Red
        exit 1
    }
}

# Optional: Install PM2 log rotation module
Write-Host "🔧 Setting up PM2 log rotation..." -ForegroundColor Yellow
pm2 install pm2-logrotate
pm2 set pm2-logrotate:max_size 10M
pm2 set pm2-logrotate:compress true

Write-Host "" -ForegroundColor Green
Write-Host "✅ Server started and configured to run on system boot!" -ForegroundColor Green
Write-Host "📁 Downloaded complete posting server with all folders:" -ForegroundColor Cyan
Write-Host "   - config/" -ForegroundColor Cyan
Write-Host "   - models/" -ForegroundColor Cyan
Write-Host "   - utils/" -ForegroundColor Cyan
Write-Host "   - server.js" -ForegroundColor Cyan
Write-Host "   - package.json" -ForegroundColor Cyan
Write-Host "" -ForegroundColor Green
Write-Host "📋 Scheduled Task Information:" -ForegroundColor Cyan
Write-Host "   - Task Name: PM2-AutoStart" -ForegroundColor Cyan
Write-Host "   - Delay: 1 minute after system startup" -ForegroundColor Cyan
Write-Host "   - Batch file: pm2-startup.bat" -ForegroundColor Cyan
Write-Host "" -ForegroundColor Green
Write-Host "🛠️ To manage the server, use these PM2 commands:" -ForegroundColor Yellow
Write-Host "   pm2 status                # Check server status" -ForegroundColor White
Write-Host "   pm2 logs                  # View all logs" -ForegroundColor White
Write-Host "   pm2 logs posting-server   # View posting server logs" -ForegroundColor White
Write-Host "   pm2 stop all             # Stop the server" -ForegroundColor White
Write-Host "   pm2 restart all          # Restart the server" -ForegroundColor White
Write-Host "   pm2 delete posting-server # Remove the server from PM2" -ForegroundColor White
Write-Host "" -ForegroundColor Green
Write-Host "🔧 To manage the scheduled task:" -ForegroundColor Yellow
Write-Host "   Get-ScheduledTask -TaskName 'PM2-AutoStart'  # Check task status" -ForegroundColor White
Write-Host "   Start-ScheduledTask -TaskName 'PM2-AutoStart'  # Manually run task" -ForegroundColor White
Write-Host "   Unregister-ScheduledTask -TaskName 'PM2-AutoStart'  # Remove task" -ForegroundColor White

Write-Host "" -ForegroundColor Green
Write-Host "🎉 Setup completed successfully!" -ForegroundColor Green