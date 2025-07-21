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

# Define PM2 path (adjust based on installation location)
$pm2Path = "C:\Users\Administrator\AppData\Roaming\npm\pm2"

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
& $pm2Path start server.js --name "posting-server" --log ..\logs\posting-server.log --exp-backoff-restart-delay=100

# Save PM2 process list
Write-Host "💾 Saving PM2 process list..."
& $pm2Path save

# Go back to parent directory for task scheduler setup
Set-Location ..

# Setup PM2 to start on system boot (Windows approach)
Write-Host "🔧 Setting up PM2 to start on system boot..."
try {
    # Try the standard pm2 startup command first (will fail on Windows but we handle it)
    $startupOutput = & $pm2Path startup 2>&1
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
        Write-Host "📋 To complete the setup:" -ForegroundColor Cyan
        Write-Host "   1. Run PowerShell as Administrator"
        Write-Host "   2. Navigate to this directory: $(Get-Location)"
        Write-Host "   3. Run the following command:"
        Write-Host "      .\fix-pm2-task.ps1"
        Write-Host ""
        Write-Host "   Or manually create the task:"
        Write-Host "      - Open Task Scheduler (taskschd.msc)"
        Write-Host "      - Create Basic Task: 'PM2 Auto Start'"
        Write-Host "      - Trigger: 'When the computer starts' (with 3-minute delay)"
        Write-Host "      - Action: 'Start a program'"
        Write-Host "      - Program: 'cmd.exe'"
        Write-Host "      - Arguments: '/c `"$(Join-Path (Get-Location) 'pm2-startup.bat')`"'"
        Write-Host "      - Start in: '$(Get-Location)'"
        Write-Host "      - Check 'Run with highest privileges'"
        
        # Create the helper script for later use
        $helperScriptContent = @"
# Helper script to fix PM2 Task Scheduler - Run as Administrator
# Exit on error
`$ErrorActionPreference = "Stop"

# Check if running as Administrator
`$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not `$isAdmin) {
    Write-Host "❌ This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Please right-click PowerShell and select 'Run as Administrator', then run this script again."
    exit 1
}

Write-Host "🔧 Setting up PM2 Task Scheduler..."

# Get current directory
`$currentDir = Get-Location

# Verify posting_server directory exists
if (-not (Test-Path "posting_server")) {
    Write-Host "❌ posting_server directory not found in current location: `$currentDir"
    exit 1
}

# Task details
`$taskName = "PM2 Auto Start"
`$taskDescription = "Automatically start PM2 processes on system boot"
`$pm2Path = "C:\Users\Administrator\AppData\Roaming\npm\pm2"

# Remove existing task if it exists
try {
    `$existingTask = Get-ScheduledTask -TaskName `$taskName -ErrorAction SilentlyContinue
    if (`$existingTask) {
        Write-Host "🗑️ Removing existing PM2 Auto Start task..."
        Unregister-ScheduledTask -TaskName `$taskName -Confirm:`$false
    }
} catch {
    Write-Host "ℹ️ No existing task found to remove."
}

# Create startup batch file
`$batchFilePath = Join-Path `$currentDir "pm2-startup.bat"
`$batchContent = @'
@echo off
echo Starting PM2 Auto Start script...
echo Current directory: %CD%
echo Target directory: $currentDir

REM Change to the correct directory
cd /d "$currentDir"
echo Changed to: %CD%

REM Set NODE_PATH and npm prefix
set NODE_PATH=%APPDATA%\npm\node_modules
call npm config set prefix %APPDATA%\npm

REM Add npm global bin to PATH
set PATH=%APPDATA%\npm;%PATH%

REM Create logs directory if it doesn't exist
if not exist "logs" mkdir logs

REM Log the attempt
echo %DATE% %TIME% - Starting PM2 Auto Start >> logs\startup.log

REM Try to resurrect saved processes
echo Attempting to resurrect PM2 processes...
call "$pm2Path" resurrect >> logs\startup.log 2>&1

REM Wait a moment and check if resurrection was successful
timeout /t 5 /nobreak > nul
call "$pm2Path" list | findstr "posting-server.*online" > nul

if %ERRORLEVEL% NEQ 0 (
    echo PM2 resurrect failed or posting-server not found, starting manually...
    echo %DATE% %TIME% - PM2 resurrect failed, starting manually >> logs\startup.log
    
    REM Start the posting server manually
    call "$pm2Path" start posting_server\server.js --name "posting-server" --log logs\posting-server.log --exp-backoff-restart-delay=100 >> logs\startup.log 2>&1
    
    REM Save the configuration
    call "$pm2Path" save >> logs\startup.log 2>&1
    
    echo %DATE% %TIME% - Manual start completed >> logs\startup.log
) else (
    echo %DATE% %TIME% - PM2 resurrect successful >> logs\startup.log
)

REM Final status check
echo Final PM2 status:
call "$pm2Path" list >> logs\startup.log 2>&1

echo %DATE% %TIME% - PM2 startup script completed >> logs\startup.log
'@

Set-Content -Path `$batchFilePath -Value `$batchContent -Encoding ASCII
Write-Host "✅ Created startup batch file at: `$batchFilePath"

try {
    # Create the scheduled task
    `$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c ```"`$batchFilePath```"" -WorkingDirectory `$currentDir
    
    # Set trigger with delay
    `$trigger = New-ScheduledTaskTrigger -AtStartup
    `$trigger.Delay = "PT3M"  # 3 minute delay
    
    # Set principal - using SYSTEM for better reliability
    `$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    # Configure settings
    `$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5) -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    
    # Create and register the task
    `$task = New-ScheduledTask -Action `$action -Trigger `$trigger -Principal `$principal -Settings `$settings -Description `$taskDescription
    Register-ScheduledTask -TaskName `$taskName -InputObject `$task | Out-Null
    
    Write-Host "✅ Successfully created '`$taskName' scheduled task!"
    Write-Host "📋 Task will run at startup with 3-minute delay using SYSTEM account"
    Write-Host "🧪 Test the task: Right-click 'PM2 Auto Start' in Task Scheduler and select 'Run'"
    Write-Host "📊 Check logs at: `$(Join-Path `$currentDir 'logs\startup.log')"
    
} catch {
    Write-Host "❌ Failed to create scheduled task: `$(`$_.Exception.Message)" -ForegroundColor Red
}

Write-Host "✅ PM2 Task Scheduler setup completed!"
"@
        
        Set-Content -Path "fix-pm2-task.ps1" -Value $helperScriptContent -Encoding UTF8
        Write-Host "💾 Created helper script: fix-pm2-task.ps1"
        
    } else {
        # Running as Administrator - proceed with task creation
        try {
            # Get current directory
            $currentDir = Get-Location
            
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
            
            # Create a robust batch file for PM2 startup
            $batchFilePath = Join-Path $currentDir "pm2-startup.bat"
            $batchContent = @"
@echo off
echo Starting PM2 Auto Start script...
echo Current directory: %CD%
echo Target directory: $currentDir

REM Change to the correct directory
cd /d "$currentDir"
echo Changed to: %CD%

REM Set NODE_PATH and npm prefix
set NODE_PATH=%APPDATA%\npm\node_modules
call npm config set prefix %APPDATA%\npm

REM Add npm global bin to PATH
set PATH=%APPDATA%\npm;%PATH%

REM Create logs directory if it doesn't exist
if not exist "logs" mkdir logs

REM Log the attempt
echo %DATE% %TIME% - Starting PM2 Auto Start >> logs\startup.log

REM Try to resurrect saved processes
echo Attempting to resurrect PM2 processes...
call "$pm2Path" resurrect >> logs\startup.log 2>&1

REM Wait a moment and check if resurrection was successful
timeout /t 5 /nobreak > nul
call "$pm2Path" list | findstr "posting-server.*online" > nul

if %ERRORLEVEL% NEQ 0 (
    echo PM2 resurrect failed or posting-server not found, starting manually...
    echo %DATE% %TIME% - PM2 resurrect failed, starting manually >> logs\startup.log
    
    REM Start the posting server manually
    call "$pm2Path" start posting_server\server.js --name "posting-server" --log logs\posting-server.log --exp-backoff-restart-delay=100 >> logs\startup.log 2>&1
    
    REM Save the configuration
    call "$pm2Path" save >> logs\startup.log 2>&1
    
    echo %DATE% %TIME% - Manual start completed >> logs\startup.log
) else (
    echo %DATE% %TIME% - PM2 resurrect successful >> logs\startup.log
)

REM Final status check
echo Final PM2 status:
call "$pm2Path" list >> logs\startup.log 2>&1

echo %DATE% %TIME% - PM2 startup script completed >> logs\startup.log
"@
            
            Set-Content -Path $batchFilePath -Value $batchContent -Encoding ASCII
            Write-Host "✅ Created startup batch file at: $batchFilePath"
            
            # Create the scheduled task using cmd.exe to run the batch file
            $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$batchFilePath`"" -WorkingDirectory $currentDir
            
            # Set trigger to run at startup with a 3-minute delay
            $trigger = New-ScheduledTaskTrigger -AtStartup
            $trigger.Delay = "PT3M"  # 3 minute delay
            
            # Set principal to run with highest privileges as SYSTEM
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            
            # Configure settings for maximum reliability
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5) -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
            
            # Create and register the task
            $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $taskDescription
            Register-ScheduledTask -TaskName $taskName -InputObject $task | Out-Null
            
            Write-Host "✅ Successfully created '$taskName' scheduled task!"
            Write-Host "📋 Task configured to run at startup with 3-minute delay using SYSTEM account"
            Write-Host "🧪 Test the task manually: Right-click 'PM2 Auto Start' in Task Scheduler and select 'Run'"
            Write-Host "📊 Startup logs will be written to: $(Join-Path $currentDir 'logs\startup.log')"
            
        } catch {
            Write-Host "❌ Failed to create scheduled task: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "📋 You can manually create the task using the instructions above."
        }
    }
}

# Navigate back to posting_server directory for final verification
Set-Location posting_server

# Verify if the server is running
Write-Host "🔍 Verifying server status..."
$pm2Status = & $pm2Path list | Select-String "posting-server.*online"
if ($pm2Status) {
    Write-Host "✅ Posting server is running!"
} else {
    Write-Host "⚠️ Posting server is not running. Attempting to restart..."
    & $pm2Path restart posting-server
    $pm2Status = & $pm2Path list | Select-String "posting-server.*online"
    if ($pm2Status) {
        Write-Host "✅ Posting server restarted successfully!"
    } else {
        Write-Host "❌ Failed to start posting server. Please check logs with '& $pm2Path logs posting-server'."
        exit 1
    }
}

# Optional: Install PM2 log rotation module
Write-Host "🔧 Setting up PM2 log rotation..."
& $pm2Path install pm2-logrotate
& $pm2Path set pm2-logrotate:max_size 10M
& $pm2Path set pm2-logrotate:compress true

# Go back to parent directory for final output
Set-Location ..

Write-Host ""
Write-Host "✅ Server setup completed successfully!"
Write-Host "📁 Downloaded complete posting server with all folders:"
Write-Host "   - config/"
Write-Host "   - models/"
Write-Host "   - utils/"
Write-Host "   - server.js"
Write-Host "   - package.json"
Write-Host ""
Write-Host "📋 Files created in this directory:"
Write-Host "   - posting_server/ (main server directory)"
Write-Host "   - logs/ (log files)"
Write-Host "   - pm2-startup.bat (startup script)"
if (Test-Path "fix-pm2-task.ps1") {
    Write-Host "   - fix-pm2-task.ps1 (helper script for admin setup)"
}
Write-Host ""
Write-Host "🔧 PM2 Management Commands:"
Write-Host "   & $pm2Path status              # Check server status"
Write-Host "   & $pm2Path logs                # View all logs"
Write-Host "   & $pm2Path logs posting-server # View posting server logs"
Write-Host "   & $pm2Path stop all           # Stop the server"
Write-Host "   & $pm2Path restart all        # Restart the server"
Write-Host "   & $pm2Path delete posting-server # Remove the server from PM2"
Write-Host "   & $pm2Path save               # Save current process list"
Write-Host "   & $pm2Path resurrect          # Restore saved processes"
Write-Host ""
Write-Host "🚀 Auto-start Setup:"
if (Test-Path "fix-pm2-task.ps1") {
    Write-Host "   Run as Administrator: .\fix-pm2-task.ps1"
} else {
    Write-Host "   Task Scheduler configured - server will start automatically on boot"
}
Write-Host "   Startup logs: .\logs\startup.log"
Write-Host ""
Write-Host "🧪 Testing:"
Write-Host "   - Restart your computer to test auto-start"
Write-Host "   - Or manually run the task in Task Scheduler"
Write-Host "   - Check .\logs\startup.log for startup details"