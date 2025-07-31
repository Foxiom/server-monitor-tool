# Exit on error
$ErrorActionPreference = "Stop"

# Configure TLS 1.2 for compatibility with all Windows versions
Write-Host "🔒 Configuring TLS 1.2 for secure connections..."
try {
    # Force TLS 1.2 for all web requests
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host "✅ TLS 1.2 configured successfully"
} catch {
    Write-Host "⚠️ Failed to configure TLS 1.2: $($_.Exception.Message)"
    Write-Host "⚠️ This may cause issues with secure downloads. Continuing anyway..."
}

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

# Function to check if Chocolatey is installed
function Test-Chocolatey {
    return (Command-Exists choco)
}

# Function to install Chocolatey
function Install-Chocolatey {
    Write-Host "📦 Installing Chocolatey..."
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        # Force TLS 1.2 explicitly for Chocolatey installation
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "✅ Chocolatey installed successfully"
    } catch {
        Write-Host "❌ Failed to install Chocolatey: $($_.Exception.Message)"
        exit 1
    }
}

# Function to ensure Chocolatey is available
function Ensure-Chocolatey {
    if (-not (Test-Chocolatey)) {
        Write-Host "❌ Chocolatey is not installed. Installing now..."
        Install-Chocolatey
    } else {
        Write-Host "✅ Chocolatey is already installed"
    }
}

# Function to install Node.js using Chocolatey (latest stable version)
function Install-NodeJs {
    Write-Host "📦 Installing the latest stable Node.js using Chocolatey..."
    try {
        choco install nodejs -y -s https://community.chocolatey.org/api/v2/
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "✅ Node.js installed successfully"
    } catch {
        Write-Host "❌ Failed to install Node.js: $($_.Exception.Message)"
        exit 1
    }
}

# Function to install Git using Chocolatey (latest stable version)
function Install-Git {
    Write-Host "📦 Installing the latest stable Git using Chocolatey..."
    try {
        choco install git -y -s https://community.chocolatey.org/api/v2/
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "✅ Git installed successfully"
    } catch {
        Write-Host "❌ Failed to install Git: $($_.Exception.Message)"
        exit 1
    }
}

# Ensure Chocolatey is installed
Ensure-Chocolatey

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

# Check if PM2 is installed, if not install it globally using the latest version
if (-not (Command-Exists pm2)) {
    Write-Host "📦 Installing the latest stable PM2 globally..."
    npm install -g pm2@latest
}

# Remove existing posting_server directory if it exists, at any cost
if (Test-Path "posting_server") {
    Write-Host "🗑️  Forcibly removing existing posting_server directory..."
    try {
        # Stop any PM2 processes that might be using the directory
        if (Command-Exists pm2) {
            pm2 kill -s
        }

        # Kill any Node.js processes that might be using the directory
        Get-Process | Where-Object { $_.Path -like "*\posting_server\*" } | Stop-Process -Force -ErrorAction SilentlyContinue

        # Take ownership of the directory and its contents
        takeown /F "posting_server" /R /D Y
        icacls "posting_server" /grant "$($env:USERNAME):F" /T

        # Forcefully remove the directory, ignoring errors
        Remove-Item -Recurse -Force "posting_server" -ErrorAction SilentlyContinue

        # Use cmd to attempt deletion if PowerShell fails
        if (Test-Path "posting_server") {
            cmd /c "rd /s /q posting_server"
        }

        # Verify removal
        if (-not (Test-Path "posting_server")) {
            Write-Host "✅ Successfully removed posting_server directory."
        } else {
            Write-Host "⚠️ Unable to remove posting_server directory. Manual intervention required." -ForegroundColor Yellow
            Write-Host "📋 Manual steps:"
            Write-Host "   1. Boot into Safe Mode"
            Write-Host "   2. Delete the 'posting_server' folder from C:\Users\Administrator"
            Write-Host "   3. Rerun the script"
        }
    } catch {
        Write-Host "❌ Error during removal: $_" -ForegroundColor Red
        Write-Host "⚠️ Attempting final deletion with elevated cmd..."
        if (Test-Path "posting_server") {
            Start-Process cmd -ArgumentList "/c rd /s /q posting_server" -Verb RunAs -Wait -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path "posting_server")) {
            Write-Host "✅ Forced removal successful after retry."
        } else {
            Write-Host "❌ Failed to remove posting_server directory. Manual deletion required." -ForegroundColor Red
        }
    }
}

# Create logs directory if it doesn't exist
New-Item -ItemType Directory -Force -Path "logs"

# Setup posting server
Write-Host "🔧 Setting up posting server..."

# Clone the repository to a temporary directory (shallow clone for efficiency)
Write-Host "⬇️ Downloading complete posting server from GitHub..."
$env:TEMP_DIR = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
New-Item -ItemType Directory -Path $env:TEMP_DIR

# Ensure TLS 1.2 is set before Git operations
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Try Git clone with multiple attempts and fallback methods
$maxAttempts = 3
$attempt = 1
$cloneSuccess = $false

while (-not $cloneSuccess -and $attempt -le $maxAttempts) {
    Write-Host "Attempt $attempt of $maxAttempts to clone repository..."
    
    try {
        # First try standard git clone
        git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git $env:TEMP_DIR
        $cloneSuccess = $true
        Write-Host "✅ Repository cloned successfully"
    } catch {
        if ($attempt -lt $maxAttempts) {
            Write-Host "⚠️ Clone failed: $($_.Exception.Message). Retrying with alternate method..."
            
            # On failure, try with different git config
            if ($attempt -eq 1) {
                # Try disabling SSL verification (only as fallback)
                git config --global http.sslVerify false
            } elseif ($attempt -eq 2) {
                # Try with PowerShell direct download as last resort
                try {
                    $zipUrl = "https://github.com/Foxiom/server-monitor-tool/archive/main.zip"
                    $zipPath = "$env:TEMP\server-monitor-tool.zip"
                    
                    Write-Host "Attempting direct download from $zipUrl"
                    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
                    
                    # Extract ZIP file
                    Write-Host "Extracting ZIP file..."
                    Expand-Archive -Path $zipPath -DestinationPath $env:TEMP -Force
                    
                    # Copy contents to temp directory
                    Copy-Item -Path "$env:TEMP\server-monitor-tool-main\*" -Destination $env:TEMP_DIR -Recurse -Force
                    
                    # Clean up
                    Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path "$env:TEMP\server-monitor-tool-main" -Recurse -Force -ErrorAction SilentlyContinue
                    
                    $cloneSuccess = $true
                    Write-Host "✅ Repository downloaded successfully via direct download"
                    break
                } catch {
                    Write-Host "⚠️ Direct download failed: $($_.Exception.Message)"
                }
            }
        } else {
            Write-Host "❌ Failed to clone repository after $maxAttempts attempts: $($_.Exception.Message)" -ForegroundColor Red
            Cleanup
        }
    }
    $attempt++
}

# Reset git config if we changed it
git config --global http.sslVerify true

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

# Setup PM2 to start on system boot (Windows approach) - Updated for SYSTEM account
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
        Write-Host "      - Trigger: 'When the computer starts' (with 2-minute delay)"
        Write-Host "      - Action: 'Start a program'"
        Write-Host "      - Program: 'cmd.exe'"
        Write-Host "      - Arguments: '/c `"$(Join-Path (Get-Location) 'pm2-startup.bat')`"'"
        Write-Host "      - Start in: 'C:\Users\Administrator'"
        Write-Host "      - Run as: 'SYSTEM' (no password needed)"
        Write-Host "      - Check 'Run with highest privileges'"
        Write-Host "      - Check 'Run whether user is logged on or not'"
        
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

Write-Host "🔧 Setting up PM2 Task Scheduler to run as SYSTEM without password..."

# Use Administrator path where PM2 is installed
`$administratorDir = "C:\Users\Administrator"

# Verify the Administrator directory exists
if (-not (Test-Path `$administratorDir)) {
    Write-Host "❌ Administrator directory not found at: `$administratorDir"
    Write-Host "Please verify the correct Administrator user directory path."
    exit 1
}

# Get current directory for posting_server
`$currentDir = Get-Location

# Verify posting_server directory exists
if (-not (Test-Path "posting_server")) {
    Write-Host "❌ posting_server directory not found in current location: `$currentDir"
    exit 1
}

# Task details
`$taskName = "PM2 Auto Start"
`$taskDescription = "Automatically start PM2 processes on system boot (runs as SYSTEM without user login)"

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

# Create startup batch file with Administrator paths for PM2
`$batchFilePath = Join-Path `$currentDir "pm2-startup.bat"
`$batchContent = @'
@echo off
echo Starting PM2 Auto Start script...
echo Current directory: %CD%
echo Target directory: $currentDir
echo Administrator directory: $administratorDir

REM Create logs directory if it doesn't exist
if not exist "$currentDir\logs" mkdir "$currentDir\logs"

REM Log the attempt
echo %DATE% %TIME% - Starting PM2 Auto Start as SYSTEM >> "$currentDir\logs\startup.log"
echo %DATE% %TIME% - Working directory: %CD% >> "$currentDir\logs\startup.log"
echo %DATE% %TIME% - User: %USERNAME% >> "$currentDir\logs\startup.log"
echo %DATE% %TIME% - Current Path: %PATH% >> "$currentDir\logs\startup.log"

REM Change to Administrator directory to access PM2 installation
cd /d "$administratorDir"
echo %DATE% %TIME% - Changed to Administrator directory: %CD% >> "$currentDir\logs\startup.log"

REM Set up Node.js and npm paths for Administrator user
set NODE_PATH=$administratorDir\AppData\Roaming\npm\node_modules
set PATH=$administratorDir\AppData\Roaming\npm;%PATH%
echo %DATE% %TIME% - Updated PATH with Administrator npm: %PATH% >> "$currentDir\logs\startup.log"

REM Verify PM2 is available
where pm2 >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo %DATE% %TIME% - PM2 not found in Administrator npm path >> "$currentDir\logs\startup.log"
    REM Try global npm modules path
    set PATH=$administratorDir\AppData\Roaming\npm;$administratorDir\AppData\Local\npm;C:\Program Files\nodejs;%PATH%
    where pm2 >nul 2>&1
    if %ERRORLEVEL% NEQ 0 (
        echo %DATE% %TIME% - PM2 still not found after path updates >> "$currentDir\logs\startup.log"
        goto :end
    )
)

echo %DATE% %TIME% - PM2 found, proceeding with startup >> "$currentDir\logs\startup.log"

REM Change to the project directory
cd /d "$currentDir"
echo %DATE% %TIME% - Changed to project directory: %CD% >> "$currentDir\logs\startup.log"

REM Try to resurrect saved processes first
echo Attempting to resurrect PM2 processes...
echo %DATE% %TIME% - Attempting PM2 resurrect >> "$currentDir\logs\startup.log"
call pm2 resurrect >> "$currentDir\logs\startup.log" 2>&1

REM Wait a moment and check if resurrection was successful
timeout /t 10 /nobreak > nul

REM Check if posting-server is running
call pm2 list 2>nul | findstr "posting-server.*online" > nul
if %ERRORLEVEL% NEQ 0 (
    echo PM2 resurrect failed or posting-server not found, starting manually...
    echo %DATE% %TIME% - PM2 resurrect failed, starting manually >> "$currentDir\logs\startup.log"
    
    REM Start the posting server manually
    if exist "posting_server\server.js" (
        echo %DATE% %TIME% - Starting posting-server manually >> "$currentDir\logs\startup.log"
        call pm2 start posting_server\server.js --name "posting-server" --log logs\posting-server.log --exp-backoff-restart-delay=100 >> "$currentDir\logs\startup.log" 2>&1
        
        REM Save the configuration
        call pm2 save >> "$currentDir\logs\startup.log" 2>&1
        echo %DATE% %TIME% - Manual start and save completed >> "$currentDir\logs\startup.log"
    ) else (
        echo %DATE% %TIME% - ERROR: posting_server\server.js not found >> "$currentDir\logs\startup.log"
    )
) else (
    echo %DATE% %TIME% - PM2 resurrect successful >> "$currentDir\logs\startup.log"
)

REM Final status check
echo Final PM2 status:
call pm2 list >> "$currentDir\logs\startup.log" 2>&1

:end
echo %DATE% %TIME% - PM2 startup script completed >> "$currentDir\logs\startup.log"
'@

Set-Content -Path `$batchFilePath -Value `$batchContent -Encoding ASCII
Write-Host "✅ Created startup batch file at: `$batchFilePath"

try {
    # Create the scheduled task action - working directory set to Administrator path for PM2 access
    `$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c ```"`$batchFilePath```"" -WorkingDirectory `$administratorDir
    
    # Set trigger to run at startup with a 2-minute delay
    `$trigger = New-ScheduledTaskTrigger -AtStartup
    `$trigger.Delay = "PT2M"  # 2 minute delay
    
    # Set principal to run as SYSTEM (no password required, runs whether user logged in or not)
    `$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    # Configure settings for maximum reliability
    `$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5) -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
    
    # Create and register the task
    `$task = New-ScheduledTask -Action `$action -Trigger `$trigger -Principal `$principal -Settings `$settings -Description `$taskDescription
    Register-ScheduledTask -TaskName `$taskName -InputObject `$task | Out-Null
    
    Write-Host "✅ Successfully created '`$taskName' scheduled task!" -ForegroundColor Green
    Write-Host "📋 Task configured to:" -ForegroundColor Cyan
    Write-Host "   - Run at startup with 2-minute delay"
    Write-Host "   - Run as SYSTEM (no password required)"
    Write-Host "   - Run whether user is logged on or not"
    Write-Host "   - Working directory: `$administratorDir (where PM2 is installed)"
    Write-Host "   - Target directory: `$currentDir (where posting_server is located)"
    Write-Host "   - Restart up to 3 times if it fails"
    Write-Host ""
    Write-Host "🧪 Test the task manually:"
    Write-Host "   1. Open Task Scheduler (taskschd.msc)"
    Write-Host "   2. Find 'PM2 Auto Start' task"
    Write-Host "   3. Right-click and select 'Run'"
    Write-Host ""
    Write-Host "📊 Check logs at: `$(Join-Path `$currentDir 'logs\startup.log')"
    
    # Try to run the task immediately to test
    Write-Host ""
    Write-Host "🚀 Testing the task now..."
    Start-ScheduledTask -TaskName `$taskName
    Start-Sleep -Seconds 8
    
    # Check if the task ran successfully
    `$taskInfo = Get-ScheduledTask -TaskName `$taskName
    `$taskResult = Get-ScheduledTaskInfo -TaskName `$taskName
    
    Write-Host "📊 Task Status: `$(`$taskResult.LastTaskResult)" -ForegroundColor `$(if(`$taskResult.LastTaskResult -eq 0) {"Green"} else {"Yellow"})
    Write-Host "📊 Last Run Time: `$(`$taskResult.LastRunTime)"
    
    if (Test-Path "`$currentDir\logs\startup.log") {
        Write-Host ""
        Write-Host "📋 Recent startup log entries:" -ForegroundColor Cyan
        Get-Content "`$currentDir\logs\startup.log" -Tail 10
    }
    
} catch {
    Write-Host "❌ Failed to create scheduled task: `$(`$_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "🔧 Alternative: Create task manually with these settings:"
    Write-Host "   Task Name: PM2 Auto Start"
    Write-Host "   User Account: SYSTEM"
    Write-Host "   Run whether user is logged on or not: ✓"
    Write-Host "   Run with highest privileges: ✓"
    Write-Host "   Trigger: At startup (2 minute delay)"
    Write-Host "   Action: cmd.exe /c ```"`$batchFilePath```""
    Write-Host "   Start in: `$administratorDir"
}

Write-Host ""
Write-Host "✅ PM2 Task Scheduler setup completed!"
Write-Host "🔄 Restart your computer to test the auto-start functionality"
"@
        
        Set-Content -Path "fix-pm2-task.ps1" -Value $helperScriptContent -Encoding UTF8
        Write-Host "💾 Created helper script: fix-pm2-task.ps1"
        
    } else {
        # Running as Administrator - proceed with task creation using SYSTEM account
        try {
            # Use Administrator path where PM2 is installed
            $administratorDir = "C:\Users\Administrator"
            
            # Verify the Administrator directory exists
            if (-not (Test-Path $administratorDir)) {
                Write-Host "❌ Administrator directory not found at: $administratorDir"
                Write-Host "Please verify the correct Administrator user directory path."
                throw "Administrator directory not found"
            }
            
            # Get current directory for posting_server
            $currentDir = Get-Location
            
            # Task details
            $taskName = "PM2 Auto Start"
            $taskDescription = "Automatically start PM2 processes on system boot (runs as SYSTEM without user login)"
            
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
            
            # Create a robust batch file for PM2 startup with Administrator paths
            $batchFilePath = Join-Path $currentDir "pm2-startup.bat"
            $batchContent = @"
@echo off
echo Starting PM2 Auto Start script...
echo Current directory: %CD%
echo Target directory: $currentDir
echo Administrator directory: $administratorDir

REM Create logs directory if it doesn't exist
if not exist "$currentDir\logs" mkdir "$currentDir\logs"

REM Log the attempt
echo %DATE% %TIME% - Starting PM2 Auto Start as SYSTEM >> "$currentDir\logs\startup.log"
echo %DATE% %TIME% - Working directory: %CD% >> "$currentDir\logs\startup.log"
echo %DATE% %TIME% - User: %USERNAME% >> "$currentDir\logs\startup.log"
echo %DATE% %TIME% - Current Path: %PATH% >> "$currentDir\logs\startup.log"

REM Change to Administrator directory to access PM2 installation
cd /d "$administratorDir"
echo %DATE% %TIME% - Changed to Administrator directory: %CD% >> "$currentDir\logs\startup.log"

REM Set up Node.js and npm paths for Administrator user
set NODE_PATH=$administratorDir\AppData\Roaming\npm\node_modules
set PATH=$administratorDir\AppData\Roaming\npm;%PATH%
echo %DATE% %TIME% - Updated PATH with Administrator npm: %PATH% >> "$currentDir\logs\startup.log"

REM Verify PM2 is available
where pm2 >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo %DATE% %TIME% - PM2 not found in Administrator npm path >> "$currentDir\logs\startup.log"
    REM Try global npm modules path
    set PATH=$administratorDir\AppData\Roaming\npm;$administratorDir\AppData\Local\npm;C:\Program Files\nodejs;%PATH%
    where pm2 >nul 2>&1
    if %ERRORLEVEL% NEQ 0 (
        echo %DATE% %TIME% - PM2 still not found after path updates >> "$currentDir\logs\startup.log"
        goto :end
    )
)

echo %DATE% %TIME% - PM2 found, proceeding with startup >> "$currentDir\logs\startup.log"

REM Change to the project directory
cd /d "$currentDir"
echo %DATE% %TIME% - Changed to project directory: %CD% >> "$currentDir\logs\startup.log"

REM Try to resurrect saved processes first
echo Attempting to resurrect PM2 processes...
echo %DATE% %TIME% - Attempting PM2 resurrect >> "$currentDir\logs\startup.log"
call pm2 resurrect >> "$currentDir\logs\startup.log" 2>&1

REM Wait a moment and check if resurrection was successful
timeout /t 10 /nobreak > nul

REM Check if posting-server is running
call pm2 list 2>nul | findstr "posting-server.*online" > nul
if %ERRORLEVEL% NEQ 0 (
    echo PM2 resurrect failed or posting-server not found, starting manually...
    echo %DATE% %TIME% - PM2 resurrect failed, starting manually >> "$currentDir\logs\startup.log"
    
    REM Start the posting server manually
    if exist "posting_server\server.js" (
        echo %DATE% %TIME% - Starting posting-server manually >> "$currentDir\logs\startup.log"
        call pm2 start posting_server\server.js --name "posting-server" --log logs\posting-server.log --exp-backoff-restart-delay=100 >> "$currentDir\logs\startup.log" 2>&1
        
        REM Save the configuration
        call pm2 save >> "$currentDir\logs\startup.log" 2>&1
        echo %DATE% %TIME% - Manual start and save completed >> "$currentDir\logs\startup.log"
    ) else (
        echo %DATE% %TIME% - ERROR: posting_server\server.js not found >> "$currentDir\logs\startup.log"
    )
) else (
    echo %DATE% %TIME% - PM2 resurrect successful >> "$currentDir\logs\startup.log"
)

REM Final status check
echo Final PM2 status:
call pm2 list >> "$currentDir\logs\startup.log" 2>&1

:end
echo %DATE% %TIME% - PM2 startup script completed >> "$currentDir\logs\startup.log"
"@
            
            Set-Content -Path $batchFilePath -Value $batchContent -Encoding ASCII
            Write-Host "✅ Created startup batch file at: $batchFilePath"
            
            # Create the scheduled task using SYSTEM account with Administrator working directory for PM2 access
            $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$batchFilePath`"" -WorkingDirectory $administratorDir
            
            # Set trigger to run at startup with a 2-minute delay
            $trigger = New-ScheduledTaskTrigger -AtStartup
            $trigger.Delay = "PT2M"  # 2 minute delay
            
            # Set principal to run as SYSTEM (no password required, runs whether user logged in or not)
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            
            # Configure settings for maximum reliability
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5) -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
            
            # Create and register the task
            $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $taskDescription
            Register-ScheduledTask -TaskName $taskName -InputObject $task | Out-Null
            
            Write-Host "✅ Successfully created '$taskName' scheduled task!" -ForegroundColor Green
            Write-Host "📋 Task configured to:" -ForegroundColor Cyan
            Write-Host "   - Run at startup with 2-minute delay"
            Write-Host "   - Run as SYSTEM (no password required)"
            Write-Host "   - Run whether user is logged on or not"
            Write-Host "   - Working directory: $administratorDir (where PM2 is installed)"
            Write-Host "   - Target directory: $currentDir (where posting_server is located)"
            Write-Host "   - Restart up to 3 times if it fails"
            Write-Host ""
            Write-Host "🧪 Test the task manually:"
            Write-Host "   1. Open Task Scheduler (taskschd.msc)"
            Write-Host "   2. Find 'PM2 Auto Start' task"
            Write-Host "   3. Right-click and select 'Run'"
            Write-Host ""
            Write-Host "📊 Check logs at: $(Join-Path $currentDir 'logs\startup.log')"
            
            # Try to run the task immediately to test
            Write-Host ""
            Write-Host "🚀 Testing the task now..."
            Start-ScheduledTask -TaskName $taskName
            Start-Sleep -Seconds 8
            
            # Check if the task ran successfully
            $taskInfo = Get-ScheduledTask -TaskName $taskName
            $taskResult = Get-ScheduledTaskInfo -TaskName $taskName
            
            Write-Host "📊 Task Status: $($taskResult.LastTaskResult)" -ForegroundColor $(if($taskResult.LastTaskResult -eq 0) {"Green"} else {"Yellow"})
            Write-Host "📊 Last Run Time: $($taskResult.LastRunTime)"
            
            if (Test-Path "$currentDir\logs\startup.log") {
                Write-Host ""
                Write-Host "📋 Recent startup log entries:" -ForegroundColor Cyan
                Get-Content "$currentDir\logs\startup.log" -Tail 10
            }
            
        } catch {
            Write-Host "❌ Failed to create scheduled task: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "🔧 Alternative: Create task manually with these settings:"
            Write-Host "   Task Name: PM2 Auto Start"
            Write-Host "   User Account: SYSTEM"
            Write-Host "   Run whether user is logged on or not: ✓"
            Write-Host "   Run with highest privileges: ✓"
            Write-Host "   Trigger: At startup (2 minute delay)"
            Write-Host "   Action: cmd.exe /c `"$batchFilePath`""
            Write-Host "   Start in: $administratorDir"
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
pm2 install pm2-logrotate
pm2 set pm2-logrotate:max_size 10M
pm2 set pm2-logrotate:compress true

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
    Write-Host "   Task Scheduler configured - server will start automatically on boot as SYSTEM"
}
Write-Host "   Startup logs: .\logs\startup.log"
Write-Host "   PM2 location: C:\Users\Administrator\AppData\Roaming\npm (accessed via SYSTEM account)"
Write-Host ""
Write-Host "🧪 Testing:"
Write-Host "   - Restart your computer to test auto-start"
Write-Host "   - Or manually run the task in Task Scheduler"
Write-Host "   - Check .\logs\startup.log for startup details"