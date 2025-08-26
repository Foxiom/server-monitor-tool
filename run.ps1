# Exit on error
$ErrorActionPreference = "Stop"

# Function to perform aggressive cleanup
function Remove-PostingServerCompletely {
    param([string]$DirectoryPath = "posting_server")
    
    Write-Host "🧹 Starting aggressive cleanup of $DirectoryPath..."
    
    # Step 1: Kill all Node.js processes
    Write-Host "🛑 Killing all Node.js processes..."
    try {
        Get-Process -Name "node" -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "  Killing Node.js process: $($_.Id)"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
    }
    catch {
        Write-Host "⚠️ Some Node.js processes could not be killed: $($_.Exception.Message)"
    }
    
    # Step 2: Stop only posting-server PM2 process (preserve others)
    if (Get-Command pm2 -ErrorAction SilentlyContinue) {
        Write-Host "🛑 Stopping posting-server PM2 process only..."
        try {
            # Check if posting-server exists and remove only it
            $postingServerExists = & pm2 describe posting-server 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Deleting posting-server PM2 process..."
                pm2 delete posting-server 2>$null | Out-Null
                pm2 save 2>$null | Out-Null  # Save updated process list
                Write-Host "✅ posting-server PM2 process removed"
            }
            else {
                Write-Host "ℹ️ No posting-server PM2 process found"
            }
            
            Start-Sleep -Seconds 2
        }
        catch {
            Write-Host "⚠️ PM2 cleanup encountered errors: $($_.Exception.Message)"
            # Only as absolute last resort, kill PM2 daemon
            Write-Host "⚠️ Trying nuclear option as last resort..."
            try {
                pm2 kill 2>$null | Out-Null
                Write-Host "⚠️ PM2 daemon killed - other PM2 apps will need manual restart"
            }
            catch {}
        }
    }
    
    # Step 3: Kill processes using the directory
    if (Test-Path $DirectoryPath) {
        Write-Host "🔍 Finding processes using the directory..."
        
        # Try to use handle.exe if available
        try {
            if (Get-Command handle.exe -ErrorAction SilentlyContinue) {
                $handles = & handle.exe $DirectoryPath 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $handles | ForEach-Object {
                        if ($_ -match "pid:\s*(\d+)") {
                            $handlePid = $matches[1]
                            try {
                                Write-Host "  Killing process $handlePid with handle to $DirectoryPath"
                                Stop-Process -Id $handlePid -Force -ErrorAction SilentlyContinue
                            }
                            catch {}
                        }
                    }
                }
            }
        }
        catch {}
        
        # Alternative: Kill any process with the directory in its path
        try {
            Get-Process | Where-Object { 
                try { 
                    $_.Path -and $_.Path -like "*$DirectoryPath*" 
                }
                catch { 
                    $false 
                }
            } | ForEach-Object {
                Write-Host "  Killing process with path containing $DirectoryPath : $($_.Id)"
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
        }
        catch {}
        
        Start-Sleep -Seconds 3
    }
    
    # Step 4: Aggressive directory removal
    if (Test-Path $DirectoryPath) {
        Write-Host "🗑️ Attempting to remove directory: $DirectoryPath"
        
        try {
            # Take ownership
            Write-Host "  Taking ownership..."
            takeown /F $DirectoryPath /R /D Y 2>$null | Out-Null
            icacls $DirectoryPath /grant "$($env:USERNAME):F" /T /Q 2>$null | Out-Null
            
            # Method 1: PowerShell Remove-Item
            Write-Host "  Trying PowerShell Remove-Item..."
            Remove-Item -Recurse -Force $DirectoryPath -ErrorAction Stop
            Write-Host "✅ Directory removed successfully"
            return $true
            
        }
        catch {
            Write-Host "⚠️ PowerShell removal failed: $($_.Exception.Message)"
            
            # Method 2: CMD rd command
            try {
                Write-Host "  Trying CMD rd command..."
                cmd /c "rd /s /q `"$DirectoryPath`"" 2>$null
                if (-not (Test-Path $DirectoryPath)) {
                    Write-Host "✅ Directory removed with CMD"
                    return $true
                }
            }
            catch {}
            
            # Method 3: Robocopy nuclear option
            try {
                Write-Host "  Using robocopy nuclear option..."
                $emptyDir = Join-Path $env:TEMP "empty_$(Get-Random)"
                New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
                
                robocopy $emptyDir $DirectoryPath /MIR /R:0 /W:0 2>$null | Out-Null
                Remove-Item -Recurse -Force $DirectoryPath -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $emptyDir -ErrorAction SilentlyContinue
                
                if (-not (Test-Path $DirectoryPath)) {
                    Write-Host "✅ Directory removed with robocopy"
                    return $true
                }
            }
            catch {}
            
            Write-Host "❌ All removal methods failed"
            return $false
        }
    }
    else {
        Write-Host "ℹ️ Directory $DirectoryPath does not exist"
        return $true
    }
}

# Function to clean up on error (now defined globally)
function Invoke-ErrorCleanup {
    Write-Host "🧹 Starting error cleanup process..."
    
    try {
        # Go back to parent directory if we're in posting_server
        $currentPath = Get-Location
        if ($currentPath.Path -like "*posting_server*") {
            Write-Host "📂 Navigating back to parent directory..."
            Set-Location ..
        }
        
        # Remove posting_server directory
        Remove-PostingServerCompletely -DirectoryPath "posting_server" | Out-Null
        
        # Clean up temp directory if it exists
        if ($env:TEMP_DIR -and (Test-Path $env:TEMP_DIR)) {
            Write-Host "🗑️ Removing temporary directory..."
            Remove-Item -Recurse -Force $env:TEMP_DIR -ErrorAction SilentlyContinue
        }
        
        Write-Host "✅ Error cleanup completed"
    }
    catch {
        Write-Host "⚠️ Error cleanup encountered issues: $($_.Exception.Message)"
    }
    
    Write-Host "❌ Script execution failed. Check the error messages above for details."
    exit 1
}

# Set up error handling with proper function reference
trap { Invoke-ErrorCleanup }

Write-Host "🔍 Performing initial cleanup check..."

# Perform aggressive cleanup if directory exists
if (Test-Path "posting_server") {
    Write-Host "⚠️ Found existing posting_server directory. Performing aggressive cleanup..."
    
    $cleanupSuccess = Remove-PostingServerCompletely -DirectoryPath "posting_server"
    
    if (-not $cleanupSuccess) {
        Write-Host "❌ Could not remove existing posting_server directory" -ForegroundColor Red
        Write-Host "🔧 Manual steps required:" -ForegroundColor Yellow
        Write-Host "   1. Open Task Manager and kill any Node.js processes" -ForegroundColor Yellow
        Write-Host "   2. Run 'pm2 kill' to stop all PM2 processes" -ForegroundColor Yellow
        Write-Host "   3. Restart your computer if necessary" -ForegroundColor Yellow
        Write-Host "   4. Manually delete the posting_server folder" -ForegroundColor Yellow
        Write-Host "❌ Please resolve manually and re-run the script" -ForegroundColor Red
        exit 1
    }
}

# Configure TLS 1.2 for compatibility with all Windows versions
Write-Host "🔒 Configuring TLS 1.2 for secure connections..."
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host "✅ TLS 1.2 configured successfully"
}
catch {
    Write-Host "⚠️ Failed to configure TLS 1.2: $($_.Exception.Message)"
    Write-Host "⚠️ This may cause issues with secure downloads. Continuing anyway..."
}

# Function to check if a command exists
function Test-CommandExists {
    param ($command)
    return Get-Command $command -ErrorAction SilentlyContinue
}

# Function to check if Chocolatey is installed
function Test-Chocolatey {
    return (Test-CommandExists choco)
}

# Function to install Chocolatey
function Install-Chocolatey {
    Write-Host "📦 Installing Chocolatey..."
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Write-Host "✅ Chocolatey installed successfully"
    }
    catch {
        Write-Host "❌ Failed to install Chocolatey: $($_.Exception.Message)"
        throw
    }
}

# Function to ensure Chocolatey is available
function Ensure-Chocolatey {
    if (-not (Test-Chocolatey)) {
        Write-Host "❌ Chocolatey is not installed. Installing now..."
        Install-Chocolatey
    }
    else {
        Write-Host "✅ Chocolatey is already installed"
    }
}

# Function to install Node.js using Chocolatey
function Install-NodeJs {
    Write-Host "📦 Installing Node.js LTS using Chocolatey..."
    try {
        choco install nodejs-lts -y
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Write-Host "✅ Node.js LTS installed successfully"
    }
    catch {
        Write-Host "❌ Failed to install Node.js: $($_.Exception.Message)"
        throw
    }
}

# Function to install Git using Chocolatey
function Install-Git {
    Write-Host "📦 Installing Git using Chocolatey..."
    try {
        choco install git -y
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Write-Host "✅ Git installed successfully"
    }
    catch {
        Write-Host "❌ Failed to install Git: $($_.Exception.Message)"
        throw
    }
}

# Function to check if running as administrator
function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to restart script with administrator privileges
function Start-AsAdministrator {
    param([string]$ScriptPath)
    
    Write-Host "🔐 Restarting script with administrator privileges..."
    try {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs -Wait
        exit 0
    }
    catch {
        Write-Host "❌ Failed to restart with admin privileges: $($_.Exception.Message)"
        return $false
    }
}

# Ensure Chocolatey is installed
Ensure-Chocolatey

# Check and install Node.js if not present or if version is incompatible
$nodeInstalled = $false
if (Test-CommandExists node) {
    try {
        $nodeVersion = & node --version
        Write-Host "📋 Current Node.js version: $nodeVersion"
        
        $versionNumber = [int]($nodeVersion -replace 'v(\d+).*', '$1')
        if ($versionNumber -ge 14) {
            $nodeInstalled = $true
            Write-Host "✅ Node.js version is compatible"
        }
        else {
            Write-Host "⚠️ Node.js version is too old, updating..."
        }
    }
    catch {
        Write-Host "⚠️ Could not determine Node.js version, reinstalling..."
    }
}

if (-not $nodeInstalled) {
    Write-Host "❌ Node.js is not installed or incompatible."
    Install-NodeJs
}

# Check and install Git if not present
if (-not (Test-CommandExists git)) {
    Write-Host "❌ Git is not installed."
    Install-Git
}

# Install/Update PM2
Write-Host "📦 Installing/updating PM2..."
try {
    npm install -g pm2@latest
    Write-Host "✅ PM2 installed/updated successfully"
}
catch {
    Write-Host "❌ Failed to install PM2: $($_.Exception.Message)"
    throw
}

# Create logs directory if it doesn't exist
New-Item -ItemType Directory -Force -Path "logs" | Out-Null

# Setup posting server
Write-Host "🔧 Setting up posting server..."

# Clone the repository to a temporary directory
Write-Host "⬇️ Downloading posting server from GitHub..."
$env:TEMP_DIR = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
New-Item -ItemType Directory -Path $env:TEMP_DIR | Out-Null

# Ensure TLS 1.2 is set before Git operations
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Try multiple download methods
$maxAttempts = 3
$attempt = 1
$downloadSuccess = $false

while (-not $downloadSuccess -and $attempt -le $maxAttempts) {
    Write-Host "Attempt $attempt of $maxAttempts to download repository..."
    
    try {
        if ($attempt -eq 1) {
            # Try Git clone first
            git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git $env:TEMP_DIR
        }
        else {
            # Try direct ZIP download
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
        }
        
        $downloadSuccess = $true
        Write-Host "✅ Repository downloaded successfully"
        
    }
    catch {
        Write-Host "⚠️ Download attempt $attempt failed: $($_.Exception.Message)"
        if ($attempt -eq $maxAttempts) {
            throw "Failed to download repository after $maxAttempts attempts"
        }
    }
    $attempt++
}

# Copy posting_server folder
Write-Host "📁 Copying posting_server folder..."
if (-not (Test-Path "$env:TEMP_DIR\posting_server")) {
    Write-Host "❌ Error: posting_server folder not found in downloaded repository"
    throw "posting_server folder not found"
}

Copy-Item -Recurse "$env:TEMP_DIR\posting_server" -Destination "." -Force
Write-Host "✅ posting_server folder copied successfully"

# Clean up temporary directory
Write-Host "🧹 Cleaning up temporary files..."
Remove-Item -Recurse -Force $env:TEMP_DIR -ErrorAction SilentlyContinue
$env:TEMP_DIR = $null

# Navigate to posting_server directory
Write-Host "📂 Navigating to posting_server directory..."
Set-Location posting_server

# Install dependencies
Write-Host "📦 Installing posting server dependencies..."
if (Test-Path "node_modules") {
    Remove-Item -Path "node_modules" -Recurse -Force
}

npm install --no-optional --no-audit
Write-Host "✅ Dependencies installed successfully"

# Set permissions
Write-Host "🔒 Setting up permissions..."
icacls "." /grant "Everyone:(OI)(CI)F" /Q | Out-Null
Get-ChildItem -Filter "*.js" | ForEach-Object { icacls $_.Name /grant "Everyone:R" /Q | Out-Null }
Get-ChildItem -Filter "*.json" | ForEach-Object { icacls $_.Name /grant "Everyone:R" /Q | Out-Null }
Get-ChildItem -Directory | ForEach-Object { icacls $_.Name /grant "Everyone:(OI)(CI)F" /Q | Out-Null }
icacls "..\logs" /grant "Everyone:(OI)(CI)F" /Q | Out-Null

# Start the server using PM2
Write-Host "🚀 Starting posting server with PM2..."

try {
    # Initialize PM2
    pm2 ping | Out-Null
    
    # Start the server
    pm2 start server.js --name "posting-server" --log ..\logs\posting-server.log --exp-backoff-restart-delay=100
    Write-Host "✅ Posting server started successfully"
    
    # Save PM2 process list
    pm2 save | Out-Null
    
}
catch {
    Write-Host "❌ Failed to start server with PM2: $($_.Exception.Message)"
    pm2 status
    pm2 logs --lines 10
    throw
}

# Go back to parent directory
Set-Location ..

# Create enhanced startup scripts with multiple approaches
Write-Host "🔧 Setting up comprehensive auto-start mechanism..."

$currentDir = Get-Location

# Create batch startup script with enhanced error handling
$startupScript = Join-Path $currentDir "pm2-autostart.bat"
$startupScriptContent = @"
@echo off
title PM2 AutoStart Service - Posting Server
echo Starting PM2 Auto-Start Service for Posting Server...

REM Create unique session ID to prevent multiple instances
set "SESSION_ID=%RANDOM%_%TIME:~-2%"
echo %DATE% %TIME% - [BAT-%SESSION_ID%] Auto-start service initiated

REM Set working directory to script location
cd /d "$currentDir"

REM Create logs directory if it doesn't exist
if not exist "logs" mkdir "logs"

REM Check for existing lock file to prevent multiple instances
if exist "%TEMP%\pm2_autostart_lock.tmp" (
    echo %DATE% %TIME% - [BAT-%SESSION_ID%] Another instance is running, exiting >> "logs\autostart.log"
    timeout /t 5 /nobreak > nul
    exit /b 0
)

REM Create lock file
echo %SESSION_ID% > "%TEMP%\pm2_autostart_lock.tmp"

REM Wait for system to fully boot with progressive delays
echo %DATE% %TIME% - [BAT-%SESSION_ID%] Waiting for system to stabilize... >> "logs\autostart.log"
timeout /t 30 /nobreak > nul 2>nul

REM Set comprehensive PATH for Node.js and npm with multiple potential locations
set "PATH_BACKUP=%PATH%"
set "NODE_PATHS=C:\Program Files\nodejs;C:\Program Files (x86)\nodejs;%USERPROFILE%\AppData\Roaming\npm;%ALLUSERSPROFILE%\npm;%PROGRAMFILES%\nodejs;%PROGRAMFILES(X86)%\nodejs"
set "PATH=%NODE_PATHS%;%PATH%"

REM Refresh environment variables from registry
for /f "tokens=2*" %%i in ('reg query "HKCU\Environment" /v PATH 2^>nul') do set "USER_PATH=%%j"
for /f "tokens=2*" %%i in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH 2^>nul') do set "SYSTEM_PATH=%%j"
if defined USER_PATH set "PATH=%PATH%;%USER_PATH%"
if defined SYSTEM_PATH set "PATH=%PATH%;%SYSTEM_PATH%"

echo %DATE% %TIME% - [BAT-%SESSION_ID%] PATH configured: %PATH% >> "logs\autostart.log"

REM Multiple attempts to find and verify Node.js
set "NODE_FOUND=0"
for /f %%i in ('where node 2^>nul') do (
    echo %DATE% %TIME% - [BAT-%SESSION_ID%] Found Node.js at: %%i >> "logs\autostart.log"
    %%i --version >> "logs\autostart.log" 2>&1
    if !ERRORLEVEL! EQU 0 set "NODE_FOUND=1"
)

if %NODE_FOUND% EQU 0 (
    echo %DATE% %TIME% - [BAT-%SESSION_ID%] ERROR: Node.js not found or not working >> "logs\autostart.log"
    goto :cleanup_and_exit
)

REM Multiple attempts to find and verify PM2
set "PM2_FOUND=0"
for /f %%i in ('where pm2 2^>nul') do (
    echo %DATE% %TIME% - [BAT-%SESSION_ID%] Found PM2 at: %%i >> "logs\autostart.log"
    %%i --version >> "logs\autostart.log" 2>&1
    if !ERRORLEVEL! EQU 0 set "PM2_FOUND=1"
)

if %PM2_FOUND% EQU 0 (
    echo %DATE% %TIME% - [BAT-%SESSION_ID%] PM2 not found, attempting installation... >> "logs\autostart.log"
    npm install -g pm2@latest >> "logs\autostart.log" 2>&1
    
    REM Refresh PATH after installation
    set "PATH=%NODE_PATHS%;%PATH%"
    for /f %%i in ('where pm2 2^>nul') do (
        echo %DATE% %TIME% - [BAT-%SESSION_ID%] PM2 installed at: %%i >> "logs\autostart.log"
        set "PM2_FOUND=1"
    )
    
    if !PM2_FOUND! EQU 0 (
        echo %DATE% %TIME% - [BAT-%SESSION_ID%] ERROR: PM2 installation failed >> "logs\autostart.log"
        goto :cleanup_and_exit
    )
)

echo %DATE% %TIME% - [BAT-%SESSION_ID%] Node.js and PM2 verified successfully >> "logs\autostart.log"

REM Initialize PM2 daemon with retry mechanism
set "PM2_INIT_ATTEMPTS=0"
:init_pm2
set /a PM2_INIT_ATTEMPTS+=1
echo %DATE% %TIME% - [BAT-%SESSION_ID%] Initializing PM2 daemon (attempt %PM2_INIT_ATTEMPTS%)... >> "logs\autostart.log"

pm2 ping >> "logs\autostart.log" 2>&1
if %ERRORLEVEL% EQU 0 (
    echo %DATE% %TIME% - [BAT-%SESSION_ID%] PM2 daemon initialized successfully >> "logs\autostart.log"
) else (
    if %PM2_INIT_ATTEMPTS% LSS 3 (
        echo %DATE% %TIME% - [BAT-%SESSION_ID%] PM2 daemon init failed, retrying in 10 seconds... >> "logs\autostart.log"
        timeout /t 10 /nobreak > nul
        goto :init_pm2
    ) else (
        echo %DATE% %TIME% - [BAT-%SESSION_ID%] ERROR: PM2 daemon failed to start after multiple attempts >> "logs\autostart.log"
        goto :cleanup_and_exit
    )
)

REM Attempt to resurrect saved processes
echo %DATE% %TIME% - [BAT-%SESSION_ID%] Attempting to resurrect saved PM2 processes... >> "logs\autostart.log"
pm2 resurrect >> "logs\autostart.log" 2>&1

REM Wait for processes to stabilize
timeout /t 15 /nobreak > nul

REM Check if posting-server is running with multiple verification attempts
set "SERVER_CHECK_ATTEMPTS=0"
:check_server
set /a SERVER_CHECK_ATTEMPTS+=1
echo %DATE% %TIME% - [BAT-%SESSION_ID%] Checking posting-server status (attempt %SERVER_CHECK_ATTEMPTS%)... >> "logs\autostart.log"

pm2 describe posting-server >> "logs\autostart.log" 2>&1
if %ERRORLEVEL% EQU 0 (
    pm2 status posting-server >> "logs\autostart.log" 2>&1
    echo %DATE% %TIME% - [BAT-%SESSION_ID%] SUCCESS: Posting server is running >> "logs\autostart.log"
    goto :success
) else (
    if %SERVER_CHECK_ATTEMPTS% LSS 3 (
        echo %DATE% %TIME% - [BAT-%SESSION_ID%] Posting server not found, attempting manual start... >> "logs\autostart.log"
        
        REM Navigate to posting_server directory and start manually
        if exist "posting_server\server.js" (
            echo %DATE% %TIME% - [BAT-%SESSION_ID%] Starting posting-server manually... >> "logs\autostart.log"
            pm2 start posting_server\server.js --name "posting-server" --log logs\posting-server.log --exp-backoff-restart-delay=100 >> "logs\autostart.log" 2>&1
            
            REM Save the process list
            pm2 save >> "logs\autostart.log" 2>&1
            
            REM Wait and check again
            timeout /t 10 /nobreak > nul
            goto :check_server
        ) else (
            echo %DATE% %TIME% - [BAT-%SESSION_ID%] ERROR: posting_server\server.js not found >> "logs\autostart.log"
            goto :cleanup_and_exit
        )
    ) else (
        echo %DATE% %TIME% - [BAT-%SESSION_ID%] ERROR: Failed to start posting server after multiple attempts >> "logs\autostart.log"
        goto :cleanup_and_exit
    )
)

:success
echo %DATE% %TIME% - [BAT-%SESSION_ID%] Auto-start service completed successfully >> "logs\autostart.log"
pm2 status >> "logs\autostart.log" 2>&1
goto :cleanup_and_exit

:cleanup_and_exit
REM Clean up lock file
if exist "%TEMP%\pm2_autostart_lock.tmp" del "%TEMP%\pm2_autostart_lock.tmp"
echo %DATE% %TIME% - [BAT-%SESSION_ID%] Auto-start service finished >> "logs\autostart.log"
exit /b 0
"@

Set-Content -Path $startupScript -Value $startupScriptContent -Encoding ASCII

# Create enhanced PowerShell startup script with privilege escalation
$powershellStartupScript = Join-Path $currentDir "pm2-autostart.ps1"
$powershellStartupScriptContent = @"
# Enhanced PM2 Auto-start PowerShell Script with Comprehensive Error Handling
param([switch]`$AsAdmin, [switch]`$Force)

`$ErrorActionPreference = "Continue"
`$currentDir = "$currentDir"
`$sessionId = Get-Random
`$logPrefix = "[PS-`$sessionId]"

# Function to write log entries
function Write-LogEntry {
    param([string]`$Message, [string]`$Level = "INFO")
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    `$logEntry = "`$timestamp - `$logPrefix [`$Level] `$Message"
    try {
        Add-Content -Path "logs\autostart.log" -Value `$logEntry -ErrorAction SilentlyContinue
    } catch {}
    Write-Host `$logEntry
}

# Function to check if running as administrator
function Test-Administrator {
    try {
        `$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return `$currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return `$false
    }
}

# Function to restart with admin privileges if needed
function Start-WithAdminPrivileges {
    if (-not (Test-Administrator)) {
        Write-LogEntry "Attempting to restart with administrator privileges..." "WARN"
        try {
            `$scriptPath = `$MyInvocation.MyCommand.Path
            `$arguments = "-NoProfile -ExecutionPolicy Bypass -File `"`$scriptPath`" -AsAdmin"
            if (`$Force) { `$arguments += " -Force" }
            
            Start-Process -FilePath "powershell.exe" -ArgumentList `$arguments -Verb RunAs -WindowStyle Hidden
            Write-LogEntry "Restarted with admin privileges" "INFO"
            exit 0
        } catch {
            Write-LogEntry "Failed to restart with admin privileges: `$(`$_.Exception.Message)" "ERROR"
            return `$false
        }
    }
    return `$true
}

# Set working directory
try {
    Set-Location `$currentDir
    Write-LogEntry "Set working directory to: `$currentDir" "INFO"
} catch {
    Write-LogEntry "Failed to set working directory: `$(`$_.Exception.Message)" "ERROR"
    exit 1
}

# Create logs directory
try {
    if (-not (Test-Path "logs")) { 
        New-Item -ItemType Directory -Path "logs" -Force | Out-Null 
        Write-LogEntry "Created logs directory" "INFO"
    }
} catch {
    Write-LogEntry "Failed to create logs directory: `$(`$_.Exception.Message)" "ERROR"
}

Write-LogEntry "Auto-start service initiated" "INFO"

# Check for existing lock file to prevent multiple instances
`$lockFile = "`$env:TEMP\pm2_autostart_ps_lock.tmp"
if ((Test-Path `$lockFile) -and -not `$Force) {
    `$lockContent = Get-Content `$lockFile -ErrorAction SilentlyContinue
    Write-LogEntry "Another PowerShell instance is running (Lock: `$lockContent), exiting" "WARN"
    exit 0
}

# Create lock file
try {
    Set-Content -Path `$lockFile -Value `$sessionId
    Write-LogEntry "Created lock file with session ID: `$sessionId" "INFO"
} catch {
    Write-LogEntry "Failed to create lock file: `$(`$_.Exception.Message)" "WARN"
}

# Try to get admin privileges if not already admin
if (-not `$AsAdmin -and -not (Test-Administrator)) {
    Start-WithAdminPrivileges
}

# Wait for system to stabilize with progress indication
Write-LogEntry "Waiting for system to stabilize..." "INFO"
for (`$i = 1; `$i -le 30; `$i++) {
    Start-Sleep -Seconds 1
    if (`$i -eq 15) { Write-LogEntry "System stabilization 50% complete..." "INFO" }
}
Write-LogEntry "System stabilization complete" "INFO"

# Set comprehensive environment paths
Write-LogEntry "Configuring environment paths..." "INFO"
`$nodePaths = @(
    "C:\Program Files\nodejs",
    "C:\Program Files (x86)\nodejs",
    "`$env:USERPROFILE\AppData\Roaming\npm",
    "`$env:ALLUSERSPROFILE\npm",
    "`$env:PROGRAMFILES\nodejs",
    "`$env:PROGRAMFILES(X86)\nodejs",
    "C:\tools\nodejs"
)

# Add all potential Node.js paths to environment
foreach (`$path in `$nodePaths) {
    if (Test-Path `$path) {
        `$env:Path = "`$path;`$env:Path"
        Write-LogEntry "Added path: `$path" "INFO"
    }
}

# Refresh environment variables from registry
try {
    `$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    `$systemPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if (`$userPath) { `$env:Path += ";`$userPath" }
    if (`$systemPath) { `$env:Path += ";`$systemPath" }
    Write-LogEntry "Environment paths refreshed from registry" "INFO"
} catch {
    Write-LogEntry "Failed to refresh environment paths: `$(`$_.Exception.Message)" "WARN"
}

Write-LogEntry "Final PATH: `$env:Path" "DEBUG"

# Verify Node.js availability with multiple attempts
Write-LogEntry "Verifying Node.js availability..." "INFO"
`$nodeFound = `$false
`$nodeAttempts = 0

do {
    `$nodeAttempts++
    try {
        `$nodeVersion = & node --version 2>&1
        if (`$LASTEXITCODE -eq 0) {
            `$nodeFound = `$true
            Write-LogEntry "Node.js found - Version: `$nodeVersion" "INFO"
        } else {
            Write-LogEntry "Node.js command failed with exit code: `$LASTEXITCODE" "WARN"
        }
    } catch {
        Write-LogEntry "Node.js check attempt `$nodeAttempts failed: `$(`$_.Exception.Message)" "WARN"
        if (`$nodeAttempts -lt 3) {
            Write-LogEntry "Retrying Node.js detection in 5 seconds..." "INFO"
            Start-Sleep -Seconds 5
        }
    }
} while (-not `$nodeFound -and `$nodeAttempts -lt 3)

if (-not `$nodeFound) {
    Write-LogEntry "ERROR: Node.js not found after multiple attempts" "ERROR"
    goto :cleanup
}

# Verify/Install PM2 with enhanced error handling
Write-LogEntry "Verifying PM2 availability..." "INFO"
`$pm2Found = `$false
`$pm2Attempts = 0

do {
    `$pm2Attempts++
    try {
        `$pm2Version = & pm2 --version 2>&1
        if (`$LASTEXITCODE -eq 0) {
            `$pm2Found = `$true
            Write-LogEntry "PM2 found - Version: `$pm2Version" "INFO"
        } else {
            Write-LogEntry "PM2 command failed, attempting installation..." "WARN"
            & npm install -g pm2@latest 2>&1 | Out-String | ForEach-Object { Write-LogEntry `$_ "INFO" }
            
            # Refresh PATH after installation
            `$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
            
            # Try again
            `$pm2Version = & pm2 --version 2>&1
            if (`$LASTEXITCODE -eq 0) {
                `$pm2Found = `$true
                Write-LogEntry "PM2 installed successfully - Version: `$pm2Version" "INFO"
            }
        }
    } catch {
        Write-LogEntry "PM2 check/install attempt `$pm2Attempts failed: `$(`$_.Exception.Message)" "WARN"
        if (`$pm2Attempts -lt 3) {
            Write-LogEntry "Retrying PM2 setup in 10 seconds..." "INFO"
            Start-Sleep -Seconds 10
        }
    }
} while (-not `$pm2Found -and `$pm2Attempts -lt 3)

if (-not `$pm2Found) {
    Write-LogEntry "ERROR: PM2 setup failed after multiple attempts" "ERROR"
    goto :cleanup
}

Write-LogEntry "Node.js and PM2 verified successfully" "INFO"

# Initialize PM2 daemon with retry mechanism
Write-LogEntry "Initializing PM2 daemon..." "INFO"
`$pm2InitAttempts = 0
`$pm2Initialized = `$false

do {
    `$pm2InitAttempts++
    try {
        Write-LogEntry "PM2 daemon initialization attempt `$pm2InitAttempts..." "INFO"
        `$pingResult = & pm2 ping 2>&1
        
        if (`$LASTEXITCODE -eq 0) {
            `$pm2Initialized = `$true
            Write-LogEntry "PM2 daemon initialized successfully" "INFO"
        } else {
            Write-LogEntry "PM2 ping failed: `$pingResult" "WARN"
            if (`$pm2InitAttempts -lt 3) {
                Write-LogEntry "Retrying PM2 daemon init in 10 seconds..." "INFO"
                Start-Sleep -Seconds 10
            }
        }
    } catch {
        Write-LogEntry "PM2 daemon init attempt `$pm2InitAttempts failed: `$(`$_.Exception.Message)" "WARN"
        if (`$pm2InitAttempts -lt 3) {
            Start-Sleep -Seconds 10
        }
    }
} while (-not `$pm2Initialized -and `$pm2InitAttempts -lt 3)

if (-not `$pm2Initialized) {
    Write-LogEntry "ERROR: PM2 daemon failed to initialize after multiple attempts" "ERROR"
    goto :cleanup
}

# Attempt to resurrect saved processes
Write-LogEntry "Attempting to resurrect saved PM2 processes..." "INFO"
try {
    `$resurrectResult = & pm2 resurrect 2>&1
    Write-LogEntry "PM2 resurrect result: `$resurrectResult" "INFO"
} catch {
    Write-LogEntry "PM2 resurrect failed: `$(`$_.Exception.Message)" "WARN"
}

# Wait for processes to stabilize
Write-LogEntry "Waiting for processes to stabilize..." "INFO"
Start-Sleep -Seconds 15

# Enhanced server verification and startup
Write-LogEntry "Verifying posting-server status..." "INFO"
`$serverCheckAttempts = 0
`$serverRunning = `$false

do {
    `$serverCheckAttempts++
    try {
        Write-LogEntry "Server status check attempt `$serverCheckAttempts..." "INFO"
        `$describeResult = & pm2 describe posting-server 2>&1
        
        if (`$LASTEXITCODE -eq 0) {
            `$serverRunning = `$true
            Write-LogEntry "SUCCESS: Posting server is running" "INFO"
            `$statusResult = & pm2 status posting-server 2>&1
            Write-LogEntry "Server status: `$statusResult" "INFO"
        } else {
            Write-LogEntry "Posting server not found, attempting manual start..." "WARN"
            
            if (Test-Path "posting_server\server.js") {
                Write-LogEntry "Starting posting-server manually..." "INFO"
                `$startResult = & pm2 start posting_server\server.js --name "posting-server" --log logs\posting-server.log --exp-backoff-restart-delay=100 2>&1
                Write-LogEntry "PM2 start result: `$startResult" "INFO"
                
                # Save the process list
                `$saveResult = & pm2 save 2>&1
                Write-LogEntry "PM2 save result: `$saveResult" "INFO"
                
                # Wait and check again
                Start-Sleep -Seconds 10
            } else {
                Write-LogEntry "ERROR: posting_server\server.js not found" "ERROR"
                break
            }
        }
    } catch {
        Write-LogEntry "Server check attempt `$serverCheckAttempts failed: `$(`$_.Exception.Message)" "WARN"
        if (`$serverCheckAttempts -lt 3) {
            Start-Sleep -Seconds 10
        }
    }
} while (-not `$serverRunning -and `$serverCheckAttempts -lt 3)

if (`$serverRunning) {
    Write-LogEntry "Auto-start service completed successfully" "INFO"
    try {
        `$finalStatus = & pm2 status 2>&1
        Write-LogEntry "Final PM2 status: `$finalStatus" "INFO"
    } catch {}
} else {
    Write-LogEntry "ERROR: Failed to start posting server after multiple attempts" "ERROR"
}

:cleanup
# Clean up lock file
try {
    if (Test-Path `$lockFile) {
        Remove-Item -Path `$lockFile -Force
        Write-LogEntry "Cleaned up lock file" "INFO"
    }
} catch {
    Write-LogEntry "Failed to clean up lock file: `$(`$_.Exception.Message)" "WARN"
}

Write-LogEntry "Auto-start service finished" "INFO"
"@

Set-Content -Path $powershellStartupScript -Value $powershellStartupScriptContent -Encoding UTF8

# Create a hybrid startup script that tries both approaches
$hybridStartupScript = Join-Path $currentDir "pm2-autostart-hybrid.bat"
$hybridStartupScriptContent = @"
@echo off
title PM2 Hybrid AutoStart Service
echo Starting PM2 Hybrid Auto-Start Service...

REM Set working directory
cd /d "$currentDir"

REM Create logs directory
if not exist "logs" mkdir "logs"

echo %DATE% %TIME% - [HYBRID] Starting hybrid auto-start service >> "logs\autostart.log"

REM First, try PowerShell approach with admin privileges
echo %DATE% %TIME% - [HYBRID] Attempting PowerShell approach... >> "logs\autostart.log"
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "pm2-autostart.ps1" -AsAdmin >> "logs\autostart.log" 2>&1

REM Wait a bit for PowerShell to complete
timeout /t 20 /nobreak > nul

REM Check if server is running
pm2 describe posting-server > nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo %DATE% %TIME% - [HYBRID] SUCCESS: PowerShell approach worked >> "logs\autostart.log"
    goto :end
)

REM If PowerShell failed, try batch approach
echo %DATE% %TIME% - [HYBRID] PowerShell failed, trying batch approach... >> "logs\autostart.log"
call "pm2-autostart.bat" >> "logs\autostart.log" 2>&1

REM Final verification
pm2 describe posting-server > nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo %DATE% %TIME% - [HYBRID] SUCCESS: Batch approach worked >> "logs\autostart.log"
) else (
    echo %DATE% %TIME% - [HYBRID] ERROR: Both approaches failed >> "logs\autostart.log"
)

:end
echo %DATE% %TIME% - [HYBRID] Hybrid auto-start service completed >> "logs\autostart.log"
"@

Set-Content -Path $hybridStartupScript -Value $hybridStartupScriptContent -Encoding ASCII

# Create a Windows Service wrapper using PowerShell
$serviceScript = Join-Path $currentDir "pm2-service.ps1"
$serviceScriptContent = @"
# PM2 Windows Service Wrapper
param([string]`$Action = "start")

`$serviceName = "PM2PostingServer"
`$serviceDisplayName = "PM2 Posting Server Auto-Start"
`$serviceDescription = "Automatically starts and manages the PM2 posting server"
`$currentDir = "$currentDir"
`$startupScript = Join-Path `$currentDir "pm2-autostart-hybrid.bat"

function Install-PM2Service {
    try {
        Write-Host "Installing PM2 Windows Service..."
        
        # Create service using New-Service
        `$serviceParams = @{
            Name = `$serviceName
            DisplayName = `$serviceDisplayName
            Description = `$serviceDescription
            BinaryPathName = "cmd.exe /c `"" + `$startupScript + "`""
            StartupType = "Automatic"
        }
        
        New-Service @serviceParams -ErrorAction Stop
        Write-Host "✅ Service installed successfully"
        
        # Start the service
        Start-Service -Name `$serviceName
        Write-Host "✅ Service started successfully"
        
    } catch {
        Write-Host "❌ Failed to install service: `$(`$_.Exception.Message)"
        
        # Try alternative method with sc.exe
        try {
            Write-Host "Trying alternative service installation..."
            & sc.exe create `$serviceName binPath= "cmd.exe /c ```"`$startupScript```"" start= auto DisplayName= "`$serviceDisplayName"
            & sc.exe description `$serviceName "`$serviceDescription"
            & sc.exe start `$serviceName
            Write-Host "✅ Service installed with sc.exe"
        } catch {
            Write-Host "❌ Alternative service installation also failed: `$(`$_.Exception.Message)"
        }
    }
}

function Remove-PM2Service {
    try {
        Write-Host "Removing PM2 Windows Service..."
        
        `$service = Get-Service -Name `$serviceName -ErrorAction SilentlyContinue
        if (`$service) {
            Stop-Service -Name `$serviceName -Force -ErrorAction SilentlyContinue
            Remove-Service -Name `$serviceName
            Write-Host "✅ Service removed successfully"
        } else {
            Write-Host "ℹ️ Service not found"
        }
        
    } catch {
        Write-Host "❌ Failed to remove service: `$(`$_.Exception.Message)"
        
        # Try with sc.exe
        try {
            & sc.exe stop `$serviceName
            & sc.exe delete `$serviceName
            Write-Host "✅ Service removed with sc.exe"
        } catch {
            Write-Host "❌ Alternative service removal also failed"
        }
    }
}

switch (`$Action.ToLower()) {
    "install" { Install-PM2Service }
    "remove" { Remove-PM2Service }
    "start" { Start-Service -Name `$serviceName -ErrorAction SilentlyContinue }
    "stop" { Stop-Service -Name `$serviceName -ErrorAction SilentlyContinue }
    default { Write-Host "Usage: pm2-service.ps1 [install|remove|start|stop]" }
}
"@

Set-Content -Path $serviceScript -Value $serviceScriptContent -Encoding UTF8

# Set up comprehensive auto-start with all methods
try {
    Write-Host "🔧 Setting up comprehensive auto-start methods..."
    
    # Method 1: Registry Run key (User level)
    $regPathUser = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $regName = "PM2PostingServerAutoStart"
    
    Remove-ItemProperty -Path $regPathUser -Name $regName -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $regPathUser -Name $regName -Value "`"$hybridStartupScript`""
    Write-Host "✅ User-level registry auto-start configured"
    
    # Method 2: Try Machine-level registry (requires admin)
    try {
        $regPathMachine = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
        Remove-ItemProperty -Path $regPathMachine -Name $regName -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $regPathMachine -Name $regName -Value "`"$hybridStartupScript`""
        Write-Host "✅ Machine-level registry auto-start configured"
    }
    catch {
        Write-Host "ℹ️ Machine-level registry auto-start not configured (requires admin)"
    }
    
    # Method 3: Startup folder shortcuts (both user and all users)
    try {
        # User startup folder
        $userStartupFolder = [System.Environment]::GetFolderPath('Startup')
        $userShortcutPath = Join-Path $userStartupFolder "PM2PostingServerAutoStart.lnk"
        
        $WScriptShell = New-Object -ComObject WScript.Shell
        $shortcut = $WScriptShell.CreateShortcut($userShortcutPath)
        $shortcut.TargetPath = $hybridStartupScript
        $shortcut.WorkingDirectory = $currentDir
        $shortcut.Description = "PM2 Posting Server Auto-Start"
        $shortcut.WindowStyle = 7  # Minimized
        $shortcut.Save()
        
        Write-Host "✅ User startup folder shortcut created"
        
        # Try all users startup folder (requires admin)
        try {
            $allUsersStartup = [System.Environment]::GetFolderPath('CommonStartup')
            $allUsersShortcutPath = Join-Path $allUsersStartup "PM2PostingServerAutoStart.lnk"
            
            $shortcut2 = $WScriptShell.CreateShortcut($allUsersShortcutPath)
            $shortcut2.TargetPath = $hybridStartupScript
            $shortcut2.WorkingDirectory = $currentDir
            $shortcut2.Description = "PM2 Posting Server Auto-Start (All Users)"
            $shortcut2.WindowStyle = 7  # Minimized
            $shortcut2.Save()
            
            Write-Host "✅ All users startup folder shortcut created"
        }
        catch {
            Write-Host "ℹ️ All users startup shortcut not created (requires admin)"
        }
        
    }
    catch {
        Write-Host "⚠️ Failed to create startup folder shortcuts: $($_.Exception.Message)"
    }
    
    # Method 4: Scheduled Task
    try {
        Write-Host "🕒 Setting up scheduled task auto-start..."
        
        $taskName = "PM2PostingServerAutoStart"
        
        # Remove existing task
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        
        # Create new task
        $action = New-ScheduledTaskAction -Execute $hybridStartupScript -WorkingDirectory $currentDir
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        $task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Auto-start PM2 Posting Server on system boot"
        
        Register-ScheduledTask -TaskName $taskName -InputObject $task
        Write-Host "✅ Scheduled task created successfully"
        
    }
    catch {
        Write-Host "⚠️ Failed to create scheduled task: $($_.Exception.Message)"
        
        # Try alternative schtasks command
        try {
            $schtasksCmd = "schtasks /create /tn `"PM2PostingServerAutoStart`" /tr `"$hybridStartupScript`" /sc onstart /ru SYSTEM /rl HIGHEST /f"
            Invoke-Expression $schtasksCmd
            Write-Host "✅ Scheduled task created with schtasks"
        }
        catch {
            Write-Host "⚠️ Alternative scheduled task creation also failed"
        }
    }
    
    # Method 5: Windows Service (if running as admin)
    if (Test-Administrator) {
        try {
            Write-Host "🔧 Setting up Windows Service..."
            & PowerShell -ExecutionPolicy Bypass -File $serviceScript -Action install
        }
        catch {
            Write-Host "⚠️ Windows Service setup failed: $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "ℹ️ Windows Service not configured (requires admin privileges)"
        Write-Host "   Run 'PowerShell -ExecutionPolicy Bypass -File pm2-service.ps1 -Action install' as admin to set up service"
    }
    
    Write-Host "✅ Comprehensive auto-start configured with multiple methods!"
    
}
catch {
    Write-Host "⚠️ Some auto-start methods failed: $($_.Exception.Message)"
}

# Create a diagnostic script for troubleshooting
$diagnosticScript = Join-Path $currentDir "pm2-diagnostic.ps1"
$diagnosticScriptContent = @"
# PM2 Diagnostic Script
Write-Host "🔍 PM2 Posting Server Diagnostic Report" -ForegroundColor Cyan
Write-Host "=" * 50

Write-Host "`n📋 System Information:" -ForegroundColor Yellow
Write-Host "OS: `$(Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption)"
Write-Host "PowerShell Version: `$(`$PSVersionTable.PSVersion)"
Write-Host "Current User: `$env:USERNAME"
Write-Host "Is Admin: `$(Test-Administrator)"

Write-Host "`n📂 Directory Status:" -ForegroundColor Yellow
Write-Host "Current Directory: `$(Get-Location)"
Write-Host "Posting Server Exists: `$(Test-Path 'posting_server\server.js')"
Write-Host "Logs Directory Exists: `$(Test-Path 'logs')"

Write-Host "`n🔧 Node.js Status:" -ForegroundColor Yellow
try {
    `$nodeVersion = & node --version 2>&1
    Write-Host "Node.js Version: `$nodeVersion"
    Write-Host "Node.js Path: `$(Get-Command node -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)"
} catch {
    Write-Host "❌ Node.js not found or not working"
}

Write-Host "`n📦 PM2 Status:" -ForegroundColor Yellow
try {
    `$pm2Version = & pm2 --version 2>&1
    Write-Host "PM2 Version: `$pm2Version"
    Write-Host "PM2 Path: `$(Get-Command pm2 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)"
    
    Write-Host "`nPM2 Processes:"
    & pm2 status 2>&1
    
    Write-Host "`nPM2 Posting Server Details:"
    & pm2 describe posting-server 2>&1
    
} catch {
    Write-Host "❌ PM2 not found or not working"
}

Write-Host "`n🚀 Auto-Start Status:" -ForegroundColor Yellow
# Check registry entries
try {
    `$userReg = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "PM2PostingServerAutoStart" -ErrorAction SilentlyContinue
    Write-Host "User Registry Entry: `$(if (`$userReg) { 'Configured' } else { 'Not Found' })"
} catch {}

try {
    `$machineReg = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "PM2PostingServerAutoStart" -ErrorAction SilentlyContinue
    Write-Host "Machine Registry Entry: `$(if (`$machineReg) { 'Configured' } else { 'Not Found' })"
} catch {}

# Check startup folder
`$userStartup = Join-Path ([Environment]::GetFolderPath('Startup')) "PM2PostingServerAutoStart.lnk"
Write-Host "User Startup Shortcut: `$(if (Test-Path `$userStartup) { 'Exists' } else { 'Not Found' })"

# Check scheduled task
try {
    `$task = Get-ScheduledTask -TaskName "PM2PostingServerAutoStart" -ErrorAction SilentlyContinue
    Write-Host "Scheduled Task: `$(if (`$task) { 'Configured' } else { 'Not Found' })"
} catch {}

# Check Windows Service
try {
    `$service = Get-Service -Name "PM2PostingServer" -ErrorAction SilentlyContinue
    Write-Host "Windows Service: `$(if (`$service) { `$service.Status } else { 'Not Found' })"
} catch {}

Write-Host "`n📄 Recent Logs:" -ForegroundColor Yellow
if (Test-Path "logs\autostart.log") {
    Write-Host "Last 10 auto-start log entries:"
    Get-Content "logs\autostart.log" -Tail 10
} else {
    Write-Host "❌ Auto-start log not found"
}

if (Test-Path "logs\posting-server.log") {
    Write-Host "`nLast 5 server log entries:"
    Get-Content "logs\posting-server.log" -Tail 5
} else {
    Write-Host "❌ Server log not found"
}

Write-Host "`n🔍 Environment Variables:" -ForegroundColor Yellow
Write-Host "PATH contains Node.js: `$(`$env:Path -like '*nodejs*')"
Write-Host "PATH contains npm: `$(`$env:Path -like '*npm*')"

Write-Host "`n=" * 50
Write-Host "🔍 Diagnostic Report Complete" -ForegroundColor Cyan
"@

Set-Content -Path $diagnosticScript -Value $diagnosticScriptContent -Encoding UTF8

# Final verification
Set-Location posting_server
Write-Host "🔍 Verifying server status..."

try {
    $processCheck = & pm2 describe posting-server 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Posting server is running!" -ForegroundColor Green
        pm2 status posting-server
    }
    else {
        Write-Host "⚠️ Server verification failed. Check with 'pm2 status'"
    }
}
catch {
    Write-Host "⚠️ Error checking server status: $($_.Exception.Message)"
}

Set-Location ..

Write-Host ""
Write-Host "✅ Enhanced server setup completed!" -ForegroundColor Green
Write-Host ""
Write-Host "🔧 Available Scripts:" -ForegroundColor Yellow
Write-Host "   .\pm2-autostart-hybrid.bat      # Hybrid startup script (recommended)"
Write-Host "   .\pm2-autostart.ps1             # PowerShell startup script"
Write-Host "   .\pm2-autostart.bat             # Batch startup script"
Write-Host "   .\pm2-service.ps1               # Windows service management"
Write-Host "   .\pm2-diagnostic.ps1            # Diagnostic and troubleshooting"
Write-Host ""
Write-Host "🔧 Useful Commands:" -ForegroundColor Yellow
Write-Host "   pm2 status                      # Check all PM2 processes"
Write-Host "   pm2 describe posting-server     # Detailed server info"
Write-Host "   pm2 logs posting-server         # View server logs"
Write-Host "   pm2 restart posting-server      # Restart server"
Write-Host "   pm2 delete posting-server       # Remove server"
Write-Host ""
Write-Host "🛠️ Troubleshooting:" -ForegroundColor Cyan
Write-Host "   PowerShell -ExecutionPolicy Bypass -File pm2-diagnostic.ps1"
Write-Host ""
Write-Host "📊 Log files:" -ForegroundColor Cyan
Write-Host "   - Auto-start: .\logs\autostart.log"
Write-Host "   - Server: .\logs\posting-server.log"
Write-Host ""
Write-Host "🎉 Setup complete with multiple failsafe auto-start methods!" -ForegroundColor Green
Write-Host "   The server will now auto-start using multiple approaches for maximum reliability." -ForegroundColor Green