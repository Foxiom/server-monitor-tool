# PowerShell equivalent of run.sh with Windows-specific PM2 startup handling
# Requires PowerShell 5.0+ and Administrator privileges for some operations

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to clean up on error
function Cleanup {
    Write-Host "❌ An error occurred. Cleaning up..." -ForegroundColor Red
    if (Test-Path "posting_server") {
        Remove-Item -Path "posting_server" -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($script:TempDir -and (Test-Path $script:TempDir)) {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    exit 1
}

# Function to check if a command exists
function Test-Command {
    param([string]$Command)
    try {
        Get-Command $Command -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

# Function to install Node.js
function Install-NodeJS {
    Write-Host "📦 Installing Node.js..." -ForegroundColor Yellow
    
    # Check if Chocolatey is installed
    if (Test-Command "choco") {
        Write-Host "Using Chocolatey to install Node.js..." -ForegroundColor Green
        choco install nodejs -y
    }
    # Check if Scoop is installed
    elseif (Test-Command "scoop") {
        Write-Host "Using Scoop to install Node.js..." -ForegroundColor Green
        scoop install nodejs
    }
    # Check if winget is available
    elseif (Test-Command "winget") {
        Write-Host "Using winget to install Node.js..." -ForegroundColor Green
        winget install OpenJS.NodeJS
    }
    else {
        Write-Host "❌ No package manager found. Please install Node.js manually from https://nodejs.org/" -ForegroundColor Red
        Write-Host "Or install a package manager like Chocolatey: https://chocolatey.org/install" -ForegroundColor Yellow
        exit 1
    }
    
    # Refresh environment variables
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# Function to install Git
function Install-Git {
    Write-Host "📦 Installing Git..." -ForegroundColor Yellow
    
    # Check if Chocolatey is installed
    if (Test-Command "choco") {
        Write-Host "Using Chocolatey to install Git..." -ForegroundColor Green
        choco install git -y
    }
    # Check if Scoop is installed
    elseif (Test-Command "scoop") {
        Write-Host "Using Scoop to install Git..." -ForegroundColor Green
        scoop install git
    }
    # Check if winget is available
    elseif (Test-Command "winget") {
        Write-Host "Using winget to install Git..." -ForegroundColor Green
        winget install Git.Git
    }
    else {
        Write-Host "❌ No package manager found. Please install Git manually from https://git-scm.com/" -ForegroundColor Red
        exit 1
    }
    
    # Refresh environment variables
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# Function to create Windows Task Scheduler entry for PM2
function Set-PM2StartupTask {
    Write-Host "🔧 Setting up PM2 to start on system boot using Task Scheduler..." -ForegroundColor Yellow
    
    if (-not (Test-Administrator)) {
        Write-Host "⚠️ Administrator privileges required for Task Scheduler setup." -ForegroundColor Yellow
        Write-Host "Please run this script as Administrator or manually set up PM2 startup." -ForegroundColor Yellow
        return
    }
    
    try {
        # Get current user and node/pm2 paths
        $currentUser = $env:USERNAME
        $nodePath = (Get-Command node).Source
        $pm2Path = (Get-Command pm2).Source
        $currentDir = Get-Location
        
        # Create a batch file to run PM2 resurrect
        $batchContent = @"
@echo off
cd /d "$currentDir"
"$nodePath" "$pm2Path" resurrect
"@
        $batchPath = Join-Path $currentDir "pm2-startup.bat"
        Set-Content -Path $batchPath -Value $batchContent -Encoding ASCII
        
        # Create the scheduled task
        $action = New-ScheduledTaskAction -Execute $batchPath
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        # Register the task
        $taskName = "PM2-PostingServer-Startup"
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        
        Write-Host "✅ Task Scheduler entry '$taskName' created successfully." -ForegroundColor Green
        Write-Host "PM2 will now automatically start your processes on system boot." -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️ Failed to create Task Scheduler entry: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "You can manually run 'pm2 save' and 'pm2 resurrect' after system restart." -ForegroundColor Yellow
    }
}

# Set up error handling
trap { Cleanup }

try {
    Write-Host "🚀 Starting Windows setup for posting server..." -ForegroundColor Cyan
    
    # Check and install Node.js if not present
    if (-not (Test-Command "node")) {
        Write-Host "❌ Node.js is not installed." -ForegroundColor Red
        Install-NodeJS
    }
    
    # Check and install Git if not present
    if (-not (Test-Command "git")) {
        Write-Host "❌ Git is not installed." -ForegroundColor Red
        Install-Git
    }
    
    # Check if PM2 is installed, if not install it globally
    if (-not (Test-Command "pm2")) {
        Write-Host "📦 Installing PM2 globally..." -ForegroundColor Yellow
        npm install -g pm2
    }
    
    # Remove existing posting_server directory if it exists
    if (Test-Path "posting_server") {
        Write-Host "🗑️ Removing existing posting_server directory..." -ForegroundColor Yellow
        Remove-Item -Path "posting_server" -Recurse -Force
    }
    
    # Create logs directory if it doesn't exist
    if (-not (Test-Path "logs")) {
        New-Item -ItemType Directory -Path "logs" | Out-Null
    }
    
    # Setup posting server
    Write-Host "🔧 Setting up posting server..." -ForegroundColor Yellow
    
    # Clone the repository to a temporary directory
    Write-Host "⬇️ Downloading complete posting server from GitHub..." -ForegroundColor Cyan
    $script:TempDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_.FullName }
    git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git $script:TempDir.FullName
    
    # Copy only the posting_server folder to our target location
    Copy-Item -Path (Join-Path $script:TempDir.FullName "posting_server") -Destination "." -Recurse
    
    # Clean up temporary directory
    Remove-Item -Path $script:TempDir -Recurse -Force
    
    # Navigate to posting_server directory
    Set-Location "posting_server"
    
    # Install posting server dependencies
    Write-Host "📦 Installing posting server dependencies..." -ForegroundColor Yellow
    npm install
    
    # Set posting server permissions (Windows equivalent)
    Write-Host "🔒 Setting up permissions..." -ForegroundColor Yellow
    # Note: Windows handles permissions differently, but we can set basic attributes
    
    # Start the server using PM2 with exponential backoff restart
    Write-Host "🚀 Starting posting server with PM2..." -ForegroundColor Green
    pm2 start server.js --name "posting-server" --log "../logs/posting-server.log" --exp-backoff-restart-delay=100
    
    # Save PM2 process list
    Write-Host "💾 Saving PM2 process list..." -ForegroundColor Yellow
    pm2 save
    
    # Setup PM2 to start on system boot (Windows-specific approach)
    Set-PM2StartupTask
    
    # Verify if the server is running
    Write-Host "🔍 Verifying server status..." -ForegroundColor Yellow
    $pm2Status = pm2 jlist | ConvertFrom-Json
    $postingServer = $pm2Status | Where-Object { $_.name -eq "posting-server" }
    
    if ($postingServer -and $postingServer.pm2_env.status -eq "online") {
        Write-Host "✅ Posting server is running!" -ForegroundColor Green
    }
    else {
        Write-Host "⚠️ Posting server is not running. Attempting to restart..." -ForegroundColor Yellow
        pm2 restart posting-server
        Start-Sleep -Seconds 3
        
        $pm2StatusRetry = pm2 jlist | ConvertFrom-Json
        $postingServerRetry = $pm2StatusRetry | Where-Object { $_.name -eq "posting-server" }
        
        if ($postingServerRetry -and $postingServerRetry.pm2_env.status -eq "online") {
            Write-Host "✅ Posting server restarted successfully!" -ForegroundColor Green
        }
        else {
            Write-Host "❌ Failed to start posting server. Please check logs with 'pm2 logs posting-server'." -ForegroundColor Red
            exit 1
        }
    }
    
    # Optional: Install PM2 log rotation module
    Write-Host "🔧 Setting up PM2 log rotation..." -ForegroundColor Yellow
    pm2 install pm2-logrotate
    pm2 set pm2-logrotate:max_size 10M
    pm2 set pm2-logrotate:compress true
    
    # Return to parent directory
    Set-Location ".."
    
    Write-Host "" -ForegroundColor White
    Write-Host "✅ Server started and configured to run on system boot!" -ForegroundColor Green
    Write-Host "📁 Downloaded complete posting server with all folders:" -ForegroundColor Cyan
    Write-Host "   - config/" -ForegroundColor White
    Write-Host "   - models/" -ForegroundColor White
    Write-Host "   - utils/" -ForegroundColor White
    Write-Host "   - server.js" -ForegroundColor White
    Write-Host "   - package.json" -ForegroundColor White
    Write-Host "" -ForegroundColor White
    Write-Host "To manage the server, use these PM2 commands:" -ForegroundColor Cyan
    Write-Host "  - pm2 status              # Check server status" -ForegroundColor White
    Write-Host "  - pm2 logs                # View all logs" -ForegroundColor White
    Write-Host "  - pm2 logs posting-server # View posting server logs" -ForegroundColor White
    Write-Host "  - pm2 stop all           # Stop the server" -ForegroundColor White
    Write-Host "  - pm2 restart all        # Restart the server" -ForegroundColor White
    Write-Host "  - pm2 delete posting-server # Remove the server from PM2" -ForegroundColor White
    Write-Host "" -ForegroundColor White
    Write-Host "Windows-specific notes:" -ForegroundColor Yellow
    Write-Host "  - PM2 startup is handled via Windows Task Scheduler" -ForegroundColor White
    Write-Host "  - Task name: 'PM2-PostingServer-Startup'" -ForegroundColor White
    Write-Host "  - To manually manage startup: taskschd.msc" -ForegroundColor White
    Write-Host "  - Alternative: Use 'pm2-windows-service' for Windows Service integration" -ForegroundColor White
}
catch {
    Write-Host "❌ Script execution failed: $($_.Exception.Message)" -ForegroundColor Red
    Cleanup
}