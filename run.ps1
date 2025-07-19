# Exit on error
$ErrorActionPreference = "Stop"

# Function to clean up on error
function Cleanup {
    if (Test-Path "posting_server") {
        Write-Host "❌ An error occurred. Cleaning up..."
        Remove-Item -Recurse -Force "posting_server" -ErrorAction SilentlyContinue
    }
    if ($env:TEMP_DIR -and (Test-Path $env:TEMP_DIR)) {
        Remove-Item -Recurse -Force $env:TEMP_DIR -ErrorAction SilentlyContinue
    }
    exit 1
}

# Set up error handling
$Global:ErrorActionPreference = "Stop"
trap { Cleanup }

# Function to check if a command exists
function Command-Exists {
    param ($command)
    return Get-Command $command -ErrorAction SilentlyContinue
}

# Function to install Node.js
function Install-NodeJs {
    Write-Host "📦 Installing Node.js..."
    if (-not (Command-Exists winget)) {
        Write-Host "❌ Winget is required to install Node.js. Please install winget first."
        exit 1
    }
    winget install OpenJS.NodeJS --version 18
}

# Function to install Git
function Install-Git {
    Write-Host "📦 Installing Git..."
    if (-not (Command-Exists winget)) {
        Write-Host "❌ Winget is required to install Git. Please install winget first."
        exit 1
    }
    winget install Git.Git
}

# Check and install Node.js if not present
if (-not (Command-Exists node)) {
    Write-Host "❌ Node.js is not installed."
    Install-NodeJs
}

# Check and install Git if not present
if (-not (Command-Exists git)) {
    Write-Host "❌ Git is not installed."
    Install-Git
}

# Check if PM2 is installed, if not install it globally
if (-not (Command-Exists pm2)) {
    Write-Host "📦 Installing PM2 globally..."
    npm install -g pm2
}

# Remove existing posting_server directory if it exists
if (Test-Path "posting_server") {
    Write-Host "🗑️  Removing existing posting_server directory..."
    Remove-Item -Recurse -Force "posting_server"
}

# Create logs directory if it doesn't exist
New-Item -ItemType Directory -Force -Path "logs"

# Setup posting server
Write-Host "🔧 Setting up posting server..."

# Clone the repository to a temporary directory (shallow clone for efficiency)
Write-Host "⬇️ Downloading complete posting server from GitHub..."
$env:TEMP_DIR = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
New-Item -ItemType Directory -Path $env:TEMP_DIR
git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git $env:TEMP_DIR

# Copy only the posting_server folder to our target location
Copy-Item -Recurse "$env:TEMP_DIR\posting_server" -Destination "."

# Clean up temporary directory
Remove-Item -Recurse -Force $env:TEMP_DIR
$env:TEMP_DIR = $null

# Navigate to posting_server directory
Set-Location posting_server

# Install posting server dependencies
Write-Host "📦 Installing posting server dependencies..."
npm install

# Set posting server permissions
Write-Host "🔒 Setting up permissions..."
icacls "." /grant "Everyone:(OI)(CI)F" /Q
Get-ChildItem -Filter "*.js" | ForEach-Object { icacls $_.Name /grant "Everyone:R" /Q }
Get-ChildItem -Filter "*.json" | ForEach-Object { icacls $_.Name /grant "Everyone:R" /Q }
Get-ChildItem -Directory | ForEach-Object { icacls $_.Name /grant "Everyone:(OI)(CI)F" /Q }
icacls "..\logs" /grant "Everyone:(OI)(CI)F" /Q

# Start the server using PM2 with exponential backoff restart
Write-Host "🚀 Starting posting server with PM2..."
pm2 start server.js --name "posting-server" --log ..\logs\posting-server.log --exp-backoff-restart-delay=100

# Save PM2 process list
Write-Host "💾 Saving PM2 process list..."
pm2 save

# Setup PM2 to start on system boot (Windows approach)
Write-Host "🔧 Setting up PM2 to start on system boot..."
try {
    # Try the standard pm2 startup command first (will fail on Windows but we handle it)
    $startupOutput = pm2 startup 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ PM2 startup script configured successfully."
    } else {
        throw "PM2 startup failed"
    }
} catch {
    Write-Host "⚠️ Standard PM2 startup not supported on Windows. Setting up Task Scheduler..."
    
    # Check if running as Administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    
    if (-not $isAdmin) {
        Write-Host "⚠️ Administrator privileges required for Task Scheduler setup." -ForegroundColor Yellow
        Write-Host "📋 Manual setup instructions:" -ForegroundColor Cyan
        Write-Host "   1. Run PowerShell as Administrator"
        Write-Host "   2. Re-run this script, or manually create Task Scheduler entry:"
        Write-Host "      - Open Task Scheduler"
        Write-Host "      - Create Basic Task: 'PM2 Auto Start'"
        Write-Host "      - Trigger: 'When the computer starts'"
        Write-Host "      - Action: 'Start a program'"
        Write-Host "      - Program: 'pm2'"
        Write-Host "      - Arguments: 'resurrect'"
        Write-Host "      - Check 'Run with highest privileges'"
    } else {
        try {
            # Get PM2 executable path
            $pm2Path = (Get-Command pm2).Source
            Write-Host "✅ Found PM2 at: $pm2Path"
            
            # Get current user
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            
            # Task details
            $taskName = "PM2 Auto Start"
            $taskDescription = "Automatically start PM2 processes on system boot"
            
            # Remove existing task if it exists
            try {
                $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                if ($existingTask) {
                    Write-Host "🗑️ Removing existing PM2 Auto Start task..."
                    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
                }
            } catch {
                # Task doesn't exist, continue
            }
            
            # Create the scheduled task with full path to PM2 and delay to ensure network is ready
            $action = New-ScheduledTaskAction -Execute $pm2Path -Argument "resurrect"
            
            # Add a 60-second delay to ensure network and services are ready
            $trigger = New-ScheduledTaskTrigger -AtStartup
            $trigger.Delay = 'PT1M' # 1 minute delay after startup
            
            # Use SYSTEM account for more reliable startup
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            
            # Configure advanced settings
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
                -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
            
            $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $taskDescription
            Register-ScheduledTask -TaskName $taskName -InputObject $task | Out-Null
            
            Write-Host "✅ Successfully created '$taskName' scheduled task!"
            Write-Host "📋 Task configured to run 'pm2 resurrect' at system startup with highest privileges"
            
        } catch {
            Write-Host "❌ Failed to create scheduled task: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "📋 Please manually create the task using Task Scheduler:" -ForegroundColor Yellow
            Write-Host "   - Task Name: PM2 Auto Start"
            Write-Host "   - Trigger: At startup"
            Write-Host "   - Action: pm2 resurrect"
            Write-Host "   - Run with highest privileges"
        }
    }
}

# Verify if the server is running
Write-Host "🔍 Verifying server status..."
$pm2Status = pm2 list | Select-String "posting-server.*online"
if ($pm2Status) {
    Write-Host "✅ Posting server is running!"
} else {
    Write-Host "⚠️ Posting server is not running. Attempting to restart..."
    pm2 restart posting-server
    $pm2Status = pm2 list | Select-String "posting-server.*online"
    if ($pm2Status) {
        Write-Host "✅ Posting server restarted successfully!"
    } else {
        Write-Host "❌ Failed to start posting server. Please check logs with 'pm2 logs posting-server'."
        exit 1
    }
}

# Optional: Install PM2 log rotation module
Write-Host "🔧 Setting up PM2 log rotation..."
pm2 install pm2-logrotate
pm2 set pm2-logrotate:max_size 10M
pm2 set pm2-logrotate:compress true

Write-Host "✅ Server started and configured!"
Write-Host "📁 Downloaded complete posting server with all folders:"
Write-Host "   - config/"
Write-Host "   - models/"
Write-Host "   - utils/"
Write-Host "   - server.js"
Write-Host "   - package.json"
Write-Host ""
Write-Host "To manage the server, use these PM2 commands:"
Write-Host "  - pm2 status              # Check server status"
Write-Host "  - pm2 logs                # View all logs"
Write-Host "  - pm2 logs posting-server # View posting server logs"
Write-Host "  - pm2 stop all           # Stop the server"
Write-Host "  - pm2 restart all        # Restart the server"
Write-Host "  - pm2 delete posting-server # Remove the server from PM2"
Write-Host "  - pm2 save               # Save current process list"
Write-Host "  - pm2 resurrect          # Restore saved processes"