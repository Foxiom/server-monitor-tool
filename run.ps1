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

# Enhanced PM2 installation with global-style for system-wide access
Write-Host "🔧 Installing PM2 globally for all users (including SYSTEM account)..." -ForegroundColor Green
try {
    # Install PM2 globally with global-style flag for system-wide access
    npm install -g pm2 --global-style --silent
    
    # Verify PM2 installation
    $pm2Version = npm list -g pm2 --depth=0 2>$null
    if ($pm2Version -match "pm2@") {
        Write-Host "✅ PM2 installed globally successfully!" -ForegroundColor Green
    } else {
        throw "PM2 installation verification failed"
    }
    
    # Get the global npm modules path
    $globalNodeModules = npm root -g 2>$null
    $globalNpmBin = npm bin -g 2>$null
    
    Write-Host "📍 Global PM2 installed at: $globalNpmBin" -ForegroundColor Cyan
    
    # Set environment variable for current session
    $env:PATH += ";$globalNpmBin"
    
} catch {
    Write-Host "❌ Failed to install PM2 globally: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "⚠️  Falling back to user-specific installation..." -ForegroundColor Yellow
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

# Go back to parent directory for task scheduler setup
Set-Location ..

# Setup PM2 to start on system boot (Windows approach) - ENHANCED VERSION
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
        
        # Create the enhanced helper script for later use
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

Write-Host "🔧 Setting up PM2 Task Scheduler with enhanced global path support..."

# Get current directory
`$currentDir = Get-Location

# Verify posting_server directory exists
if (-not (Test-Path "posting_server")) {
    Write-Host "❌ posting_server directory not found in current location: `$currentDir"
    exit 1
}

# Task details
`$taskName = "PM2 Auto Start"
`$taskDescription = "Automatically start PM2 processes on system boot with global path support"

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

# Create enhanced startup batch file with robust PM2 path detection
`$batchFilePath = Join-Path `$currentDir "pm2-startup.bat"
`$batchContent = @'
@echo off
setlocal enabledelayedexpansion

REM Set log file location
set LOG_FILE=logs\startup.log

REM Create logs directory if it doesn't exist
if not exist "logs" mkdir "logs"

echo %DATE% %TIME% - Starting PM2 Auto Start >> "%LOG_FILE%"

REM Change to the correct directory
cd /d "$currentDir"
echo %DATE% %TIME% - Changed to directory: %CD% >> "%LOG_FILE%"

REM Add multiple potential npm paths to ensure PM2 is found
set PATH=%PATH%;%ProgramFiles%\nodejs;%APPDATA%\npm;%ProgramFiles%\nodejs\node_modules\.bin

REM Also try common global installation paths
set PATH=%PATH%;C:\Users\Administrator\AppData\Roaming\npm
set PATH=%PATH%;%ALLUSERSPROFILE%\npm
set PATH=%PATH%;%ProgramData%\npm

REM Set NODE_PATH for module resolution
set NODE_PATH=%APPDATA%\npm\node_modules;%ProgramFiles%\nodejs\node_modules

echo %DATE% %TIME% - Updated PATH: %PATH% >> "%LOG_FILE%"

REM Try to find PM2 executable in multiple ways
set PM2_CMD=
echo %DATE% %TIME% - Searching for PM2 executable... >> "%LOG_FILE%"

REM Method 1: Try standard where command
for %%i in (pm2.cmd pm2 pm2.exe) do (
    where %%i >nul 2>&1
    if !ERRORLEVEL! == 0 (
        set PM2_CMD=%%i
        echo %DATE% %TIME% - Found PM2 using where: %%i >> "%LOG_FILE%"
        goto :found_pm2
    )
)

REM Method 2: Try common installation paths
set SEARCH_PATHS=%APPDATA%\npm\pm2.cmd;C:\Users\Administrator\AppData\Roaming\npm\pm2.cmd;%ProgramFiles%\nodejs\pm2.cmd;%ProgramFiles%\nodejs\node_modules\.bin\pm2.cmd;%ProgramData%\npm\pm2.cmd

for %%p in (%SEARCH_PATHS%) do (
    if exist "%%p" (
        set PM2_CMD=%%p
        echo %DATE% %TIME% - Found PM2 at: %%p >> "%LOG_FILE%"
        goto :found_pm2
    )
)

REM Method 3: Try using npm to find global bin directory
for /f "tokens=*" %%i in ('npm bin -g 2^>nul') do (
    if exist "%%i\pm2.cmd" (
        set PM2_CMD=%%i\pm2.cmd
        echo %DATE% %TIME% - Found PM2 using npm bin -g: %%i\pm2.cmd >> "%LOG_FILE%"
        goto :found_pm2
    )
)

:found_pm2
if not defined PM2_CMD (
    echo %DATE% %TIME% - ERROR: PM2 not found in any expected location >> "%LOG_FILE%"
    echo %DATE% %TIME% - Searched paths: %SEARCH_PATHS% >> "%LOG_FILE%"
    goto :end
)

echo %DATE% %TIME% - Using PM2 at: !PM2_CMD! >> "%LOG_FILE%"

REM Test PM2 command
"!PM2_CMD!" --version >> "%LOG_FILE%" 2>&1
if !ERRORLEVEL! neq 0 (
    echo %DATE% %TIME% - ERROR: PM2 command test failed >> "%LOG_FILE%"
    goto :end
)

REM Try to resurrect saved processes first
echo %DATE% %TIME% - Attempting PM2 resurrect >> "%LOG_FILE%"
"!PM2_CMD!" resurrect >> "%LOG_FILE%" 2>&1

REM Wait a moment for processes to start
timeout /t 10 /nobreak > nul

REM Check if posting-server is running
"!PM2_CMD!" list | findstr "posting-server" | findstr "online" >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo %DATE% %TIME% - Posting server not running, starting manually >> "%LOG_FILE%"
    "!PM2_CMD!" start "posting_server\server.js" --name "posting-server" --log "logs\posting-server.log" --exp-backoff-restart-delay=100 >> "%LOG_FILE%" 2>&1
    if !ERRORLEVEL! == 0 (
        echo %DATE% %TIME% - Posting server started successfully >> "%LOG_FILE%"
    ) else (
        echo %DATE% %TIME% - Failed to start posting server >> "%LOG_FILE%"
    )
) else (
    echo %DATE% %TIME% - Posting server is already running >> "%LOG_FILE%"
)

REM Save the current process list
echo %DATE% %TIME% - Saving PM2 process list >> "%LOG_FILE%"
"!PM2_CMD!" save >> "%LOG_FILE%" 2>&1

REM Show final status
echo %DATE% %TIME% - Final PM2 status: >> "%LOG_FILE%"
"!PM2_CMD!" status >> "%LOG_FILE%" 2>&1

:end
echo %DATE% %TIME% - PM2 startup script completed >> "%LOG_FILE%"
'@

Set-Content -Path `$batchFilePath -Value `$batchContent -Encoding ASCII
Write-Host "✅ Created enhanced startup batch file at: `$batchFilePath"

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
    Write-Host "📋 Task configured to run at startup with 3-minute delay using SYSTEM account"
    Write-Host "🧪 Test the task: Right-click 'PM2 Auto Start' in Task Scheduler and select 'Run'"
    Write-Host "📊 Startup logs will be written to: `$(Join-Path `$currentDir 'logs\startup.log')"
    
} catch {
    Write-Host "❌ Failed to create scheduled task: `$(`$_.Exception.Message)" -ForegroundColor Red
}

Write-Host "✅ PM2 Task Scheduler setup completed with enhanced path detection!"
"@
        
        Set-Content -Path "fix-pm2-task.ps1" -Value $helperScriptContent -Encoding UTF8
        Write-Host "💾 Created enhanced helper script: fix-pm2-task.ps1"
        
    } else {
        # Running as Administrator - proceed with enhanced task creation
        try {
            # Get current directory
            $currentDir = Get-Location
            
            # Task details
            $taskName = "PM2 Auto Start"
            $taskDescription = "Automatically start PM2 processes on system boot with global path support"
            
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
            
            # Create enhanced batch file for PM2 startup with robust path detection
            $batchFilePath = Join-Path $currentDir "pm2-startup.bat"
            $batchContent = @"
@echo off
setlocal enabledelayedexpansion

REM Set log file location
set LOG_FILE=logs\startup.log

REM Create logs directory if it doesn't exist
if not exist "logs" mkdir "logs"

echo %DATE% %TIME% - Starting PM2 Auto Start >> "%LOG_FILE%"

REM Change to the correct directory
cd /d "$currentDir"
echo %DATE% %TIME% - Changed to directory: %CD% >> "%LOG_FILE%"

REM Add multiple potential npm paths to ensure PM2 is found
set PATH=%PATH%;%ProgramFiles%\nodejs;%APPDATA%\npm;%ProgramFiles%\nodejs\node_modules\.bin

REM Also try common global installation paths
set PATH=%PATH%;C:\Users\Administrator\AppData\Roaming\npm
set PATH=%PATH%;%ALLUSERSPROFILE%\npm
set PATH=%PATH%;%ProgramData%\npm

REM Set NODE_PATH for module resolution
set NODE_PATH=%APPDATA%\npm\node_modules;%ProgramFiles%\nodejs\node_modules

echo %DATE% %TIME% - Updated PATH: %PATH% >> "%LOG_FILE%"

REM Try to find PM2 executable in multiple ways
set PM2_CMD=
echo %DATE% %TIME% - Searching for PM2 executable... >> "%LOG_FILE%"

REM Method 1: Try standard where command
for %%i in (pm2.cmd pm2 pm2.exe) do (
    where %%i >nul 2>&1
    if !ERRORLEVEL! == 0 (
        set PM2_CMD=%%i
        echo %DATE% %TIME% - Found PM2 using where: %%i >> "%LOG_FILE%"
        goto :found_pm2
    )
)

REM Method 2: Try common installation paths
set SEARCH_PATHS=%APPDATA%\npm\pm2.cmd;C:\Users\Administrator\AppData\Roaming\npm\pm2.cmd;%ProgramFiles%\nodejs\pm2.cmd;%ProgramFiles%\nodejs\node_modules\.bin\pm2.cmd;%ProgramData%\npm\pm2.cmd

for %%p in (%SEARCH_PATHS%) do (
    if exist "%%p" (
        set PM2_CMD=%%p
        echo %DATE% %TIME% - Found PM2 at: %%p >> "%LOG_FILE%"
        goto :found_pm2
    )
)

REM Method 3: Try using npm to find global bin directory
for /f "tokens=*" %%i in ('npm bin -g 2^>nul') do (
    if exist "%%i\pm2.cmd" (
        set PM2_CMD=%%i\pm2.cmd
        echo %DATE% %TIME% - Found PM2 using npm bin -g: %%i\pm2.cmd >> "%LOG_FILE%"
        goto :found_pm2
    )
)

:found_pm2
if not defined PM2_CMD (
    echo %DATE% %TIME% - ERROR: PM2 not found in any expected location >> "%LOG_FILE%"
    echo %DATE% %TIME% - Searched paths: %SEARCH_PATHS% >> "%LOG_FILE%"
    goto :end
)

echo %DATE% %TIME% - Using PM2 at: !PM2_CMD! >> "%LOG_FILE%"

REM Test PM2 command
"!PM2_CMD!" --version >> "%LOG_FILE%" 2>&1
if !ERRORLEVEL! neq 0 (
    echo %DATE% %TIME% - ERROR: PM2 command test failed >> "%LOG_FILE%"
    goto :end
)

REM Try to resurrect saved processes first
echo %DATE% %TIME% - Attempting PM2 resurrect >> "%LOG_FILE%"
"!PM2_CMD!" resurrect >> "%LOG_FILE%" 2>&1

REM Wait a moment for processes to start
timeout /t 10 /nobreak > nul

REM Check if posting-server is running
"!PM2_CMD!" list | findstr "posting-server" | findstr "online" >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo %DATE% %TIME% - Posting server not running, starting manually >> "%LOG_FILE%"
    "!PM2_CMD!" start "posting_server\server.js" --name "posting-server" --log "logs\posting-server.log" --exp-backoff-restart-delay=100 >> "%LOG_FILE%" 2>&1
    if !ERRORLEVEL! == 0 (
        echo %DATE% %TIME% - Posting server started successfully >> "%LOG_FILE%"
    else (
        echo %DATE% %TIME% - Failed to start posting server >> "%LOG_FILE%"
    )
) else (
    echo %DATE% %TIME% - Posting server is already running >> "%LOG_FILE%"
)

REM Save the current process list
echo %DATE% %TIME% - Saving PM2 process list >> "%LOG_FILE%"
"!PM2_CMD!" save >> "%LOG_FILE%" 2>&1

REM Show final status
echo %DATE% %TIME% - Final PM2 status: >> "%LOG_FILE%"
"!PM2_CMD!" status >> "%LOG_FILE%" 2>&1

:end
echo %DATE% %TIME% - PM2 startup script completed >> "%LOG_FILE%"
"@
            
            Set-Content -Path $batchFilePath -Value $batchContent -Encoding ASCII
            Write-Host "✅ Created enhanced startup batch file at: $batchFilePath"
            
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
            
            Write-Host "✅ Successfully created '$taskName' scheduled task with enhanced path detection!"
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
try {
    pm2 install pm2-logrotate
    pm2 set pm2-logrotate:max_size 10M
    pm2 set pm2-logrotate:retain 30
    pm2 set pm2-logrotate:compress true
    pm2 set pm2-logrotate:dateFormat YYYY-MM-DD_HH-mm-ss
    pm2 set pm2-logrotate:workerInterval 30
    pm2 set pm2-logrotate:rotateInterval "0 0 * * *"
    pm2 set pm2-logrotate:rotateModule true
    Write-Host "✅ PM2 log rotation configured successfully!"
} catch {
    Write-Host "⚠️ PM2 log rotation setup failed, but server is still running."
}

# Go back to parent directory for final output
Set-Location ..

Write-Host ""
Write-Host "✅ Server setup completed successfully with enhanced global PM2 support!"
Write-Host "🔧 PM2 Installation Details:"
Write-Host "   - PM2 installed globally with --global-style flag"
Write-Host "   - System-wide access enabled for SYSTEM account"
Write-Host "   - Enhanced path detection in startup scripts"
Write-Host ""
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
Write-Host "   - pm2-startup.bat (enhanced startup script)"
if (Test-Path "fix-pm2-task.ps1") {
    Write-Host "   - fix-pm2-task.ps1 (enhanced helper script for admin setup)"
}
Write-Host ""
Write-Host "🔧 PM2 Management Commands:"
Write-Host "   pm2 status              # Check server status"
Write-Host "   pm2 logs                # View all logs"
Write-Host "   pm2 logs posting-server # View posting server logs"
Write-Host "   pm2 stop all           # Stop the server"
Write-Host "   pm2 restart all        # Restart the server"
Write-Host "   pm2 delete posting-server # Remove the server from PM2"
Write-Host "   pm2 save               # Save current process list"
Write-Host "   pm2 resurrect          # Restore saved processes"
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
Write-Host ""
Write-Host "🔍 Troubleshooting:"
Write-Host "   - If PM2 is not found, check: npm bin -g"
Write-Host "   - Verify global installation: npm list -g pm2"
Write-Host "   - Check PATH includes: $(npm bin -g 2>$null)"