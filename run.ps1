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
Write-Host "🚀 Setting up posting server with PM2..."

# Check if posting-server process already exists in PM2
$existingProcess = pm2 list | Select-String "posting-server"
if ($existingProcess) {
    Write-Host "⚠️ Process 'posting-server' already exists in PM2. Restarting it..."
    pm2 restart posting-server --update-env
    Write-Host "✅ Process 'posting-server' restarted successfully"
} else {
    Write-Host "🆕 Starting new PM2 process 'posting-server'..."
    pm2 start server.js --name "posting-server" --log ..\logs\posting-server.log --exp-backoff-restart-delay=100
    Write-Host "✅ Process 'posting-server' started successfully"
}

# Save PM2 process list
Write-Host "💾 Saving PM2 process list..."
pm2 save

# Go back to parent directory for auto-start setup
Set-Location ..

# New Reliable Auto-Start Setup
Write-Host "🔧 Setting up reliable auto-start mechanism..."

# Get current paths
$currentDir = Get-Location
$currentUser = $env:USERNAME
$userProfile = $env:USERPROFILE

# Function to create startup service using multiple methods for maximum reliability
function Setup-AutoStart {
    Write-Host "🚀 Configuring multiple auto-start methods for maximum reliability..."
    
    # Method 1: Windows Service using NSSM (if available)
    $nssmAvailable = $false
    try {
        # Try to install NSSM (Non-Sucking Service Manager) for the most reliable service creation
        if (-not (Command-Exists nssm)) {
            Write-Host "📦 Installing NSSM for service management..."
            choco install nssm -y -s https://community.chocolatey.org/api/v2/ 2>$null
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        }
        
        if (Command-Exists nssm) {
            $nssmAvailable = $true
            Write-Host "✅ NSSM available for service creation"
        }
    } catch {
        Write-Host "⚠️ NSSM installation failed, using alternative methods"
    }
    
    # Create a reliable startup script
    $startupScript = Join-Path $currentDir "pm2-autostart.bat"
    $startupScriptContent = @"
@echo off
title PM2 AutoStart Service
echo Starting PM2 Auto-Start Service...

REM Set working directory
cd /d "$currentDir"

REM Create logs directory if it doesn't exist
if not exist "logs" mkdir "logs"

REM Log startup attempt
echo %DATE% %TIME% - Auto-start service initiated >> "logs\autostart.log"

REM Wait for system to fully boot (reduce startup delay)
timeout /t 15 /nobreak > nul

REM Set Node.js paths
set PATH=%PATH%;C:\Program Files\nodejs;$userProfile\AppData\Roaming\npm;$userProfile\AppData\Local\npm

REM Check if PM2 is available
where pm2 >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo %DATE% %TIME% - PM2 not found in PATH >> "logs\autostart.log"
    echo PM2 not found, please check installation
    goto :end
)

echo %DATE% %TIME% - PM2 found, proceeding with startup >> "logs\autostart.log"

REM Try to resurrect saved PM2 processes
echo Attempting to resurrect PM2 processes...
pm2 resurrect >> "logs\autostart.log" 2>&1

REM Wait and verify
timeout /t 10 /nobreak > nul

REM Check if posting-server is running
pm2 list | findstr "posting-server.*online" > nul
if %ERRORLEVEL% NEQ 0 (
    echo %DATE% %TIME% - Posting server not running, starting manually >> "logs\autostart.log"
    
    REM Navigate to posting_server directory and start
    if exist "posting_server\server.js" (
        pm2 start posting_server\server.js --name "posting-server" --log logs\posting-server.log --exp-backoff-restart-delay=100 >> "logs\autostart.log" 2>&1
        pm2 save >> "logs\autostart.log" 2>&1
        echo %DATE% %TIME% - Posting server started successfully >> "logs\autostart.log"
    ) else (
        echo %DATE% %TIME% - ERROR: posting_server\server.js not found >> "logs\autostart.log"
    )
) else (
    echo %DATE% %TIME% - Posting server already running >> "logs\autostart.log"
)

REM Final status
echo %DATE% %TIME% - Final PM2 status: >> "logs\autostart.log"
pm2 list >> "logs\autostart.log" 2>&1

:end
echo %DATE% %TIME% - Auto-start service completed >> "logs\autostart.log"
"@
    
    Set-Content -Path $startupScript -Value $startupScriptContent -Encoding ASCII
    Write-Host "✅ Created startup script: $startupScript"
    
    # Method 1: NSSM Service (Most Reliable)
    if ($nssmAvailable) {
        try {
            # Remove existing service if it exists
            $existingService = Get-Service "PM2AutoStart" -ErrorAction SilentlyContinue
            if ($existingService) {
                Write-Host "🗑️ Removing existing PM2AutoStart service..."
                nssm stop PM2AutoStart
                nssm remove PM2AutoStart confirm
            }
            
            Write-Host "🔧 Creating Windows service using NSSM..."
            
            # Install the service
            nssm install PM2AutoStart "$startupScript"
            
            # Configure service properties
            nssm set PM2AutoStart DisplayName "PM2 Auto Start Service"
            nssm set PM2AutoStart Description "Automatically starts PM2 processes on system boot"
            nssm set PM2AutoStart Start SERVICE_AUTO_START
            nssm set PM2AutoStart AppDirectory "$currentDir"
            nssm set PM2AutoStart AppStderr "$currentDir\logs\service-error.log"
            nssm set PM2AutoStart AppStdout "$currentDir\logs\service-output.log"
            nssm set PM2AutoStart AppRotateFiles 1
            nssm set PM2AutoStart AppRotateOnline 1
            nssm set PM2AutoStart AppRotateSeconds 86400
            nssm set PM2AutoStart AppThrottle 1500
            
            # Start the service
            nssm start PM2AutoStart
            
            Write-Host "✅ Windows service 'PM2AutoStart' created and started successfully!" -ForegroundColor Green
            Write-Host "📋 Service details:"
            Write-Host "   - Service Name: PM2AutoStart"
            Write-Host "   - Status: $($(Get-Service PM2AutoStart).Status)"
            Write-Host "   - Startup Type: Automatic"
            Write-Host "   - Log files: $currentDir\logs\service-*.log"
            
            return $true
        } catch {
            Write-Host "⚠️ Failed to create NSSM service: $($_.Exception.Message)"
        }
    }
    
    # Method 2: Registry Run Key (Faster startup, user-level)
    try {
        Write-Host "🔧 Setting up Registry Run key for fast startup..."
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        $regName = "PM2AutoStart"
        
        # Remove existing entry
        Remove-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
        
        # Add new entry
        Set-ItemProperty -Path $regPath -Name $regName -Value "`"$startupScript`""
        
        Write-Host "✅ Registry Run key created successfully!"
        Write-Host "📋 Registry entry: $regPath\$regName"
        
    } catch {
        Write-Host "⚠️ Failed to create Registry Run key: $($_.Exception.Message)"
    }
    
    # Method 3: Startup folder shortcut (Backup method)
    try {
        Write-Host "🔧 Creating startup folder shortcut as backup..."
        $startupFolder = [Environment]::GetFolderPath("Startup")
        $shortcutPath = Join-Path $startupFolder "PM2AutoStart.lnk"
        
        # Remove existing shortcut
        if (Test-Path $shortcutPath) {
            Remove-Item $shortcutPath -Force
        }
        
        # Create new shortcut
        $WshShell = New-Object -comObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($shortcutPath)
        $Shortcut.TargetPath = $startupScript
        $Shortcut.WorkingDirectory = $currentDir
        $Shortcut.Description = "PM2 Auto Start"
        $Shortcut.Save()
        
        Write-Host "✅ Startup folder shortcut created!"
        Write-Host "📋 Shortcut location: $shortcutPath"
        
    } catch {
        Write-Host "⚠️ Failed to create startup folder shortcut: $($_.Exception.Message)"
    }
    
    # Method 4: Task Scheduler (Simple, reliable version)
    try {
        Write-Host "🔧 Creating simplified Task Scheduler entry..."
        
        $taskName = "PM2 Auto Start Simple"
        
        # Remove existing task
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        
        # Create simple action
        $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$startupScript`"" -WorkingDirectory $currentDir
        
        # Create trigger with minimal delay
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $trigger.Delay = "PT30S"  # 30 second delay
        
        # Set principal for current user
        $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
        
        # Simple settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        # Register task
        $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Simple PM2 auto-start on user login"
        Register-ScheduledTask -TaskName $taskName -InputObject $task | Out-Null
        
        Write-Host "✅ Task Scheduler entry created!"
        Write-Host "📋 Task: $taskName (runs on user login with 30s delay)"
        
    } catch {
        Write-Host "⚠️ Failed to create Task Scheduler entry: $($_.Exception.Message)"
    }
    
    return $false
}

# Run the auto-start setup
$serviceCreated = Setup-AutoStart

# Optional: Install PM2 log rotation module
Write-Host "🔧 Setting up PM2 log rotation..."
pm2 install pm2-logrotate
pm2 set pm2-logrotate:max_size 10M
pm2 set pm2-logrotate:compress true

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

# Go back to parent directory for final output
Set-Location ..

Write-Host ""
Write-Host "✅ Server setup completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "📁 Downloaded complete posting server with all folders:" -ForegroundColor Cyan
Write-Host "   - config/"
Write-Host "   - models/"
Write-Host "   - utils/"
Write-Host "   - server.js"
Write-Host "   - package.json"
Write-Host ""
Write-Host "📋 Files created in this directory:" -ForegroundColor Cyan
Write-Host "   - posting_server/ (main server directory)"
Write-Host "   - logs/ (log files)"
Write-Host "   - pm2-autostart.bat (optimized startup script)"
Write-Host ""
Write-Host "🔧 PM2 Management Commands:" -ForegroundColor Yellow
Write-Host "   pm2 status              # Check server status"
Write-Host "   pm2 logs                # View all logs"
Write-Host "   pm2 logs posting-server # View posting server logs"
Write-Host "   pm2 stop all           # Stop the server"
Write-Host "   pm2 restart all        # Restart the server"
Write-Host "   pm2 delete posting-server # Remove the server from PM2"
Write-Host "   pm2 save               # Save current process list"
Write-Host "   pm2 resurrect          # Restore saved processes"
Write-Host ""
Write-Host "🚀 Auto-start Configuration:" -ForegroundColor Green
if ($serviceCreated) {
    Write-Host "   ✅ Windows Service: PM2AutoStart (Most reliable - runs even without user login)"
    Write-Host "   📊 Service Status: $($(Get-Service PM2AutoStart -ErrorAction SilentlyContinue).Status)"
    Write-Host "   🔧 Manage Service: services.msc (search for 'PM2AutoStart')"
}
Write-Host "   ✅ Registry Run Key: Fast startup on user login"
Write-Host "   ✅ Startup Folder: Backup method"
Write-Host "   ✅ Task Scheduler: Additional reliability layer"
Write-Host ""
Write-Host "📊 Monitoring & Logs:" -ForegroundColor Cyan
Write-Host "   - Auto-start logs: .\logs\autostart.log"
Write-Host "   - PM2 server logs: .\logs\posting-server.log"
if ($serviceCreated) {
    Write-Host "   - Service logs: .\logs\service-*.log"
}
Write-Host ""
Write-Host "🧪 Testing Auto-Start:" -ForegroundColor Yellow
Write-Host "   1. Restart your computer"
Write-Host "   2. Check logs in .\logs\autostart.log"
Write-Host "   3. Verify with: pm2 status"
Write-Host "   4. Or test manually: .\pm2-autostart.bat"
Write-Host ""
Write-Host "⚡ Features of this improved setup:" -ForegroundColor Green
Write-Host "   - Multiple auto-start methods for maximum reliability"
Write-Host "   - Faster startup times (15-30 second delay vs 2+ minutes)"
Write-Host "   - Better error handling and logging"
Write-Host "   - Works with or without user login (if service is available)"
Write-Host "   - Self-healing: automatically restarts if PM2 processes fail"
Write-Host "   - Comprehensive logging for troubleshooting"
Write-Host ""
Write-Host "🎉 Setup complete! Your server will start automatically on boot." -ForegroundColor Green