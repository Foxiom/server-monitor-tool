# PowerShell Script for Setting up Posting Server with Windows Service
# Exit on error
$ErrorActionPreference = "Stop"

# Set working directory to user profile
Set-Location -Path $env:USERPROFILE

# Function to clean up on error
function Cleanup {
    if (Test-Path "posting_server") {
        Write-Host "❌ An error occurred. Cleaning up..." -ForegroundColor Red
        Remove-Item -Recurse -Force "posting_server" -ErrorAction SilentlyContinue
    }
    if ($null -ne $TempDir -and (Test-Path $TempDir)) {
        Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
    }
    exit 1
}

# Enhanced cleanup function that handles running processes and services
function Enhanced-Cleanup {
    Write-Host "🔄 Performing enhanced cleanup..." -ForegroundColor Yellow
    
    # Stop and remove Windows service first
    try {
        Write-Host "🛑 Stopping existing PM2PostingServer service..." -ForegroundColor Yellow
        $service = Get-Service -Name "PM2PostingServer" -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -eq "Running") {
                Stop-Service -Name "PM2PostingServer" -Force
                Start-Sleep -Seconds 5
            }
            # Remove the service using sc.exe
            & sc.exe delete "PM2PostingServer" 2>$null
            Start-Sleep -Seconds 3
        }
    }
    catch {
        Write-Host "⚠️ Service cleanup warning: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Stop PM2 processes
    try {
        Write-Host "🛑 Stopping existing PM2 processes..." -ForegroundColor Yellow
        pm2 stop posting-server 2>$null
        pm2 delete posting-server 2>$null
        Start-Sleep -Seconds 3
    }
    catch {
        Write-Host "⚠️ PM2 cleanup warning: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Force stop any Node.js processes that might be locking the directory
    try {
        Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "*posting_server*" } | Stop-Process -Force
        Start-Sleep -Seconds 2
    }
    catch {
        Write-Host "⚠️ Process cleanup warning: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    # Remove the directory with multiple attempts
    if (Test-Path "posting_server") {
        Write-Host "🗑️ Removing existing posting_server directory..." -ForegroundColor Yellow
        
        $attempts = 0
        $maxAttempts = 5
        
        while ((Test-Path "posting_server") -and ($attempts -lt $maxAttempts)) {
            try {
                Remove-Item -Recurse -Force "posting_server" -ErrorAction Stop
                Write-Host "✅ Directory removed successfully!" -ForegroundColor Green
                break
            }
            catch {
                $attempts++
                Write-Host "⚠️ Attempt $attempts failed: $($_.Exception.Message)" -ForegroundColor Yellow
                
                if ($attempts -lt $maxAttempts) {
                    Write-Host "🔄 Retrying in 3 seconds..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 3
                }
                else {
                    Write-Host "❌ Failed to remove directory after $maxAttempts attempts" -ForegroundColor Red
                    Write-Host "💡 Try running PowerShell as Administrator or manually remove the directory" -ForegroundColor Cyan
                    throw "Directory removal failed"
                }
            }
        }
    }
}

# Set up error handling
trap { Cleanup }

# Function to check if a command exists
function Test-Command {
    param($Command)
    try {
        Get-Command $Command -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

# Function to install Chocolatey
function Install-Chocolatey {
    Write-Host "📦 Installing Chocolatey..." -ForegroundColor Yellow
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    
    # Refresh environment variables
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# Function to install Node.js
function Install-NodeJS {
    Write-Host "📦 Installing Node.js..." -ForegroundColor Yellow
    if (!(Test-Command "choco")) {
        Install-Chocolatey
    }
    choco install nodejs-lts -y
    
    # Refresh environment variables
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# Function to install Git
function Install-Git {
    Write-Host "📦 Installing Git..." -ForegroundColor Yellow
    if (!(Test-Command "choco")) {
        Install-Chocolatey
    } else {
        Write-Host "✅ Chocolatey already installed" -ForegroundColor Yellow
    }
    choco install git -y
    
    # Refresh environment variables
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# Function to install NSSM (Non-Sucking Service Manager) for better service handling
function Install-NSSM {
    Write-Host "📦 Installing NSSM (Non-Sucking Service Manager)..." -ForegroundColor Yellow
    
    if (!(Test-Command "choco")) {
        Install-Chocolatey
    }
    
    try {
        choco install nssm -y
        
        # Refresh environment variables
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        $env:Path = "$machinePath;$userPath"
        
        # Verify installation
        if (Test-Command "nssm") {
            Write-Host "✅ NSSM installed successfully!" -ForegroundColor Green
            return $true
        } else {
            Write-Host "⚠️ NSSM installation verification failed" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "❌ Failed to install NSSM: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to create and install Windows Service for PM2 Posting Server using NSSM
function Setup-PM2WindowsService {
    Write-Host "🔧 Setting up PM2 Posting Server Windows Service..." -ForegroundColor Yellow
    
    try {
        # Check if running as administrator
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $isAdmin) {
            Write-Host "⚠️ Warning: Not running as Administrator. Service installation may fail." -ForegroundColor Yellow
            Write-Host "💡 For best results, run PowerShell as Administrator." -ForegroundColor Cyan
        }
        
        # Install NSSM if not available
        if (!(Test-Command "nssm")) {
            Write-Host "📦 NSSM not found, installing..." -ForegroundColor Yellow
            $nssmInstalled = Install-NSSM
            if (-not $nssmInstalled) {
                Write-Host "❌ Failed to install NSSM. Falling back to basic service creation." -ForegroundColor Red
                return Setup-PM2BasicWindowsService
            }
        } else {
            Write-Host "✅ NSSM already installed" -ForegroundColor Green
        }
        
        # Get current user info and paths
        $CurrentUser = $env:USERNAME
        $CurrentDomain = $env:USERDOMAIN
        $PostingServerPath = Join-Path $env:USERPROFILE "posting_server"
        $LogDir = Join-Path $env:USERPROFILE "logs"
        $LogPath = Join-Path $LogDir "pm2-service.log"
        $StdoutLogPath = Join-Path $LogDir "pm2-service-stdout.log"
        $StderrLogPath = Join-Path $LogDir "pm2-service-stderr.log"
        $PM2Home = Join-Path $env:USERPROFILE ".pm2"
        $ServiceName = "PM2PostingServer"
        $ServiceDisplayName = "PM2 Posting Server"
        $ServiceDescription = "PM2 Posting Server - Auto-starts posting server application on system boot"
        
        # Ensure PM2_HOME directory exists
        if (!(Test-Path $PM2Home)) {
            New-Item -ItemType Directory -Path $PM2Home -Force | Out-Null
        }
        
        # Set PM2_HOME environment variable persistently
        [System.Environment]::SetEnvironmentVariable("PM2_HOME", $PM2Home, [System.EnvironmentVariableTarget]::Machine)
        [System.Environment]::SetEnvironmentVariable("PM2_HOME", $PM2Home, [System.EnvironmentVariableTarget]::User)
        $env:PM2_HOME = $PM2Home
        
        # Create logs directory if it doesn't exist
        $LogDir = Split-Path $LogPath -Parent
        if (!(Test-Path $LogDir)) {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        }
        
        # Create batch wrapper script (more reliable for services than PowerShell)
        $BatchScript = @"
@echo off
REM PM2 Posting Server Service Batch Wrapper
setlocal EnableExtensions EnableDelayedExpansion

REM Set PM2_HOME environment variable
set PM2_HOME=$PM2Home

REM Create a function for safe logging to avoid file locking issues
:log_message
set "msg=%~1"
REM Use a more reliable method to get date and time
for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set dt=%%a
set "year=%dt:~0,4%"
set "month=%dt:~4,2%"
set "day=%dt:~6,2%"
set "hour=%dt:~8,2%"
set "minute=%dt:~10,2%"
set "second=%dt:~12,2%"
set "timestamp=%year%-%month%-%day% %hour%:%minute%:%second%"
echo [%timestamp%] %msg%>> "$LogPath" 2>nul
goto :eof

REM Log startup
call :log_message "==================================="
call :log_message "PM2 Posting Server Service Started"
call :log_message "Current User: %USERNAME%"
call :log_message "PM2 Home: %PM2_HOME%"
call :log_message "Working Directory: $PostingServerPath"

REM Change to posting server directory
cd /d "$PostingServerPath"
if %errorlevel% neq 0 (
    call :log_message "ERROR: Failed to change directory"
    exit /b 1
)

REM Wait for system to stabilize
timeout /t 30 /nobreak >nul
call :log_message "System stabilization wait completed"

REM Load environment PATH
for /f "tokens=2*" %%i in ('reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "MachinePath=%%j"
for /f "tokens=2*" %%i in ('reg query "HKEY_CURRENT_USER\Environment" /v Path 2^>nul') do set "UserPath=%%j"
set "PATH=%MachinePath%;%UserPath%"

REM Check if PM2 is available
pm2 -v >nul 2>&1
if %errorlevel% neq 0 (
    call :log_message "ERROR: PM2 not found in PATH"
    exit /b 1
)

REM Get PM2 version
for /f "delims=" %%i in ('pm2 -v 2^>^&1') do set pm2version=%%i
call :log_message "PM2 version: %pm2version%"

REM Enhanced PM2 resurrection and startup logic for server monitoring
REM First, clean up any orphaned PM2 processes
call :log_message "Cleaning up any orphaned PM2 processes..."
pm2 kill >nul 2>&1
timeout /t 5 /nobreak >nul

REM Initialize PM2 daemon
call :log_message "Initializing PM2 daemon..."
pm2 ping >nul 2>&1
if %errorlevel% neq 0 (
    call :log_message "PM2 daemon not responding, force starting..."
    pm2 start ecosystem.config.js >nul 2>&1
    timeout /t 5 /nobreak >nul
)

REM Check if PM2 dump file exists and try to resurrect
if exist "%PM2_HOME%\dump.pm2" (
    call :log_message "PM2 dump file found, attempting resurrect..."
    pm2 resurrect >nul 2>&1
    timeout /t 15 /nobreak >nul
    call :log_message "PM2 resurrect completed"
) else (
    call :log_message "No PM2 dump file found, will start fresh"
)

REM Check if posting-server is running after resurrection
pm2 list --no-colors > "%TEMP%\pm2list.txt" 2>&1
findstr "posting-server.*online" "%TEMP%\pm2list.txt" >nul
if %errorlevel% neq 0 (
    call :log_message "Posting server not running, starting manually..."
    
    REM Stop any existing posting-server instances first
    pm2 stop posting-server >nul 2>&1
    pm2 delete posting-server >nul 2>&1
    timeout /t 3 /nobreak >nul
    
    REM Start fresh posting-server instance
    pm2 start server.js --name "posting-server" --log "../logs/posting-server.log" --exp-backoff-restart-delay=100 --max-restarts=10 --min-uptime=10s >nul 2>&1
    if %errorlevel% equ 0 (
        call :log_message "Posting server started successfully"
        pm2 save >nul 2>&1
        call :log_message "PM2 configuration saved"
    ) else (
        call :log_message "ERROR: Failed to start posting server"
    )
) else (
    call :log_message "Posting server already running after resurrection"
)

REM Enable PM2 startup for future reboots
call :log_message "Configuring PM2 startup for future reboots..."
pm2 startup >nul 2>&1
pm2 save >nul 2>&1

call :log_message "PM2 Posting Server Service initialization completed"
call :log_message "==================================="

REM Keep the service running - enhanced monitoring for server monitoring tool
:monitor_loop
timeout /t 60 /nobreak >nul

REM Check if PM2 daemon is still alive
pm2 ping >nul 2>&1
if %errorlevel% neq 0 (
    call :log_message "WARNING: PM2 daemon not responding, reinitializing..."
    pm2 kill >nul 2>&1
    timeout /t 5 /nobreak >nul
    pm2 resurrect >nul 2>&1
    timeout /t 10 /nobreak >nul
)

REM Check if posting-server process is still running
pm2 list --no-colors > "%TEMP%\pm2status.txt" 2>&1
findstr "posting-server.*online" "%TEMP%\pm2status.txt" >nul
if %errorlevel% neq 0 (
    call :log_message "WARNING: Posting server not online, attempting recovery..."
    
    REM Try restart first
    pm2 restart posting-server >nul 2>&1
    timeout /t 10 /nobreak >nul
    
    REM Verify restart worked
    pm2 list --no-colors > "%TEMP%\pm2restart_check.txt" 2>&1
    findstr "posting-server.*online" "%TEMP%\pm2restart_check.txt" >nul
    if %errorlevel% neq 0 (
        call :log_message "Restart failed, attempting fresh start..."
        pm2 stop posting-server >nul 2>&1
        pm2 delete posting-server >nul 2>&1
        timeout /t 3 /nobreak >nul
        pm2 start server.js --name "posting-server" --log "../logs/posting-server.log" --exp-backoff-restart-delay=100 --max-restarts=10 --min-uptime=10s >nul 2>&1
        pm2 save >nul 2>&1
        call :log_message "Fresh posting server instance started"
    ) else (
        call :log_message "Posting server restart successful"
    )
    pm2 save >nul 2>&1
) else (
    REM Server is running, log periodic health check
    if defined last_health_log (
        REM Only log health status every 10 minutes to avoid log spam
        set /a health_counter+=1
        if !health_counter! geq 10 (
            call :log_message "Health check: Posting server running normally"
            set health_counter=0
        )
    ) else (
        call :log_message "Health check: Posting server running normally"
        set health_counter=0
    )
    set last_health_log=1
)

goto monitor_loop
"@
        
        # Save the batch script
        $BatchScriptPath = Join-Path $env:USERPROFILE "pm2_posting_server_service.bat"
        $BatchScript | Out-File -FilePath $BatchScriptPath -Encoding ASCII
        
        Write-Host "📝 Service batch script created at: $BatchScriptPath" -ForegroundColor Cyan
        
        # Remove existing service if it exists
        try {
            $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if ($existingService) {
                Write-Host "🗑️ Removing existing service..." -ForegroundColor Yellow
                if ($existingService.Status -eq "Running") {
                    & nssm stop $ServiceName
                    Start-Sleep -Seconds 5
                }
                & nssm remove $ServiceName confirm | Out-Null
                Start-Sleep -Seconds 3
            }
        }
        catch {
            Write-Host "⚠️ Warning during existing service cleanup: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        
        # Create the Windows service using NSSM
        Write-Host "🔧 Creating Windows service with NSSM..." -ForegroundColor Yellow
        
        # Install the service
        $installResult = & nssm install $ServiceName $BatchScriptPath 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Failed to create service with NSSM: $installResult" -ForegroundColor Red
            return $false
        }
        
        # Configure service parameters
        & nssm set $ServiceName DisplayName $ServiceDisplayName | Out-Null
        & nssm set $ServiceName Description $ServiceDescription | Out-Null
        & nssm set $ServiceName Start SERVICE_AUTO_START | Out-Null
        & nssm set $ServiceName AppDirectory $PostingServerPath | Out-Null
        
        # Separate stdout and stderr to avoid file locking conflicts
        & nssm set $ServiceName AppStdout $StdoutLogPath | Out-Null
        & nssm set $ServiceName AppStderr $StderrLogPath | Out-Null
        & nssm set $ServiceName AppStdoutCreationDisposition 4 | Out-Null
        & nssm set $ServiceName AppStderrCreationDisposition 4 | Out-Null
        
        # Configure log rotation to prevent large files
        & nssm set $ServiceName AppRotateFiles 1 | Out-Null
        & nssm set $ServiceName AppRotateOnline 1 | Out-Null
        & nssm set $ServiceName AppRotateSeconds 86400 | Out-Null  # Daily rotation
        & nssm set $ServiceName AppRotateBytes 10485760 | Out-Null  # 10MB max size
        
        # Set service to restart on failure
        & nssm set $ServiceName AppExit Default Restart | Out-Null
        & nssm set $ServiceName AppRestartDelay 5000 | Out-Null  # 5 second delay
        & nssm set $ServiceName AppThrottle 10000 | Out-Null     # 10 second throttle
        
        Write-Host "✅ Windows service created successfully with NSSM!" -ForegroundColor Green
        
        # Start the service
        Write-Host "🚀 Starting PM2 Posting Server service..." -ForegroundColor Yellow
        try {
            & nssm start $ServiceName
            Start-Sleep -Seconds 10
            
            # Verify service is running
            $service = Get-Service -Name $ServiceName
            if ($service.Status -eq "Running") {
                Write-Host "✅ Service started successfully!" -ForegroundColor Green
            } else {
                Write-Host "⚠️ Service created but not running. Status: $($service.Status)" -ForegroundColor Yellow
                Write-Host "💡 Check service log at: $LogPath" -ForegroundColor Cyan
            }
        }
        catch {
            Write-Host "⚠️ Service created but failed to start: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "💡 You can start it manually using: nssm start $ServiceName" -ForegroundColor Cyan
        }
        
        # Display service information
        Write-Host ""
        Write-Host "📋 Service Details:" -ForegroundColor Cyan
        Write-Host "   Service Name: $ServiceName" -ForegroundColor White
        Write-Host "   Display Name: $ServiceDisplayName" -ForegroundColor White
        Write-Host "   Startup Type: Automatic" -ForegroundColor White
        Write-Host "   Service Script: $BatchScriptPath" -ForegroundColor White
        Write-Host "   Batch Script Log: $LogPath" -ForegroundColor White
        Write-Host "   Service Stdout Log: $StdoutLogPath" -ForegroundColor White
        Write-Host "   Service Stderr Log: $StderrLogPath" -ForegroundColor White
        Write-Host "   Service Manager: NSSM" -ForegroundColor White
        Write-Host ""
        Write-Host "🔧 Service Management Commands:" -ForegroundColor Yellow
        Write-Host "   nssm start $ServiceName          # Start the service" -ForegroundColor White
        Write-Host "   nssm stop $ServiceName           # Stop the service" -ForegroundColor White
        Write-Host "   nssm restart $ServiceName        # Restart the service" -ForegroundColor White
        Write-Host "   nssm status $ServiceName         # Check service status" -ForegroundColor White
        Write-Host "   nssm remove $ServiceName confirm # Remove the service" -ForegroundColor White
        Write-Host "   Get-Service -Name $ServiceName   # Check Windows service status" -ForegroundColor White
        
        return $true
    }
    catch {
        Write-Host "❌ Failed to setup Windows service: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "💡 Make sure you're running PowerShell as Administrator" -ForegroundColor Cyan
        return $false
    }
}

# Fallback function for basic Windows Service creation (without NSSM)
function Setup-PM2BasicWindowsService {
    Write-Host "🔧 Setting up basic Windows Service (fallback method)..." -ForegroundColor Yellow
    
    # Get paths
    $PostingServerPath = Join-Path $env:USERPROFILE "posting_server"
    $LogPath = Join-Path $env:USERPROFILE "logs\pm2-service.log"
    $PM2Home = Join-Path $env:USERPROFILE ".pm2"
    $ServiceName = "PM2PostingServer"
    $ServiceDisplayName = "PM2 Posting Server"
    $ServiceDescription = "PM2 Posting Server - Auto-starts posting server application on system boot"
    
    # Create a simple batch wrapper
    $SimpleBatchScript = @"
@echo off
set PM2_HOME=$PM2Home
cd /d "$PostingServerPath"
echo [%date% %time%] Starting PM2 Posting Server Service >> "$LogPath"
timeout /t 30 /nobreak >nul
pm2 resurrect >> "$LogPath" 2>&1
pm2 list >> "$LogPath" 2>&1
:loop
timeout /t 300 /nobreak >nul
pm2 list > nul 2>&1
if %errorlevel% neq 0 (
    echo [%date% %time%] PM2 process check failed, restarting... >> "$LogPath"
    pm2 restart all >> "$LogPath" 2>&1
)
goto loop
"@
    
    $SimpleBatchScriptPath = Join-Path $env:USERPROFILE "pm2_posting_server_simple.bat"
    $SimpleBatchScript | Out-File -FilePath $SimpleBatchScriptPath -Encoding ASCII
    
    try {
        # Remove existing service
        $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($existingService) {
            if ($existingService.Status -eq "Running") {
                Stop-Service -Name $ServiceName -Force
            }
            & sc.exe delete $ServiceName | Out-Null
            Start-Sleep -Seconds 3
        }
        
        # Create basic service
        $createResult = & sc.exe create $ServiceName binPath= $SimpleBatchScriptPath DisplayName= $ServiceDisplayName start= auto
        
        if ($LASTEXITCODE -eq 0) {
            & sc.exe description $ServiceName $ServiceDescription | Out-Null
            Write-Host "✅ Basic Windows service created successfully!" -ForegroundColor Green
            return $true
        } else {
            Write-Host "❌ Failed to create basic service: $createResult" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "❌ Basic service creation failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Check and install Node.js if not present
if (!(Test-Command "node")) {
    Write-Host "❌ Node.js is not installed." -ForegroundColor Red
    Install-NodeJS
}

# Check and install Git if not present
if (!(Test-Command "git")) {
    Write-Host "❌ Git is not installed." -ForegroundColor Red
    Install-Git
}

# Check if PM2 is installed, if not install it globally
if (!(Test-Command "pm2")) {
    Write-Host "📦 Installing PM2 globally..." -ForegroundColor Yellow
    npm install -g pm2
}

# Set PM2_HOME environment variable persistently for the machine and current user
$PM2Home = Join-Path $env:USERPROFILE ".pm2"
[System.Environment]::SetEnvironmentVariable("PM2_HOME", $PM2Home, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable("PM2_HOME", $PM2Home, [System.EnvironmentVariableTarget]::User)
$env:PM2_HOME = $PM2Home

# Ensure PM2_HOME directory exists
if (!(Test-Path $PM2Home)) {
    New-Item -ItemType Directory -Path $PM2Home -Force | Out-Null
}

# Use Enhanced-Cleanup instead of the simple directory removal
if (Test-Path "posting_server") {
    Enhanced-Cleanup
}

# Create logs directory if it doesn't exist
if (!(Test-Path "logs")) {
    Write-Host "📁 Creating logs directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path "logs" | Out-Null
}

# Setup posting server
Write-Host "🔧 Setting up posting server..." -ForegroundColor Green

# Clone the repository to a temporary directory (shallow clone for efficiency)
Write-Host "⬇️ Downloading complete posting server from GitHub..." -ForegroundColor Cyan
$TempDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ }
git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git $TempDir.FullName

# Copy only the posting_server folder to our target location
Copy-Item -Recurse -Path (Join-Path $TempDir.FullName "posting_server") -Destination "."

# Clean up temporary directory
Remove-Item -Recurse -Force $TempDir

# Navigate to posting_server directory
Set-Location "posting_server"

# Install posting server dependencies
Write-Host "📦 Installing posting server dependencies..." -ForegroundColor Yellow
npm install

# Set posting server permissions (Windows equivalent)
Write-Host "🔒 Setting up permissions..." -ForegroundColor Yellow
Get-ChildItem -Recurse | ForEach-Object {
    if ($_.PSIsContainer) {
        # Directory - no special action needed on Windows
    } else {
        # File - ensure it's not read-only
        $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
    }
}
# Ensure logs directory is writable
$logsPath = Join-Path (Get-Location).Path "../logs"
(Get-Item $logsPath).Attributes = (Get-Item $logsPath).Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)

# Start the server using PM2 with exponential backoff restart
Write-Host "🚀 Starting posting server with PM2..." -ForegroundColor Green
pm2 start server.js --name "posting-server" --log "../logs/posting-server.log" --exp-backoff-restart-delay=100

# Save PM2 process list
Write-Host "💾 Startup PM2 process list..." -ForegroundColor Yellow
pm2 startup

Write-Host "💾 Saving PM2 process list..." -ForegroundColor Yellow
pm2 save

# Setup PM2 to start on system boot (same approach as Linux script)
Write-Host "🔧 Setting up PM2 to start on system boot..." -ForegroundColor Yellow
try {
    # Use PM2's built-in startup command for Windows
    $startupOutput = pm2 startup 2>&1 | Out-String
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ PM2 startup script configured successfully." -ForegroundColor Green
        
        # Check if startup output contains Windows-specific instructions
        if ($startupOutput -match "copy.*paste.*command") {
            Write-Host "💡 PM2 startup configured. The startup script will handle auto-start on boot." -ForegroundColor Cyan
        }
        
        $serviceSetupSuccess = $true
    } else {
        Write-Host "⚠️ Warning: PM2 startup script may not have been configured correctly." -ForegroundColor Yellow
        Write-Host "💡 You can manually configure it later with 'pm2 startup'" -ForegroundColor Cyan
        $serviceSetupSuccess = $false
    }
} catch {
    Write-Host "⚠️ Warning: Failed to configure PM2 startup: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "💡 You can manually configure it later with 'pm2 startup'" -ForegroundColor Cyan
    $serviceSetupSuccess = $false
}

if ($serviceSetupSuccess) {
    Write-Host "✅ Windows Service configured successfully!" -ForegroundColor Green
} else {
    Write-Host "⚠️ Warning: Windows Service setup failed. Server will need to be started manually after reboot." -ForegroundColor Yellow
    Write-Host "💡 Try running this script as Administrator for service installation." -ForegroundColor Cyan
}

# Verify if the server is running
Write-Host "🔍 Verifying server status..." -ForegroundColor Yellow
$pm2Status = pm2 list | Out-String
if ($pm2Status -match "posting-server.*online") {
    Write-Host "✅ Posting server is running!" -ForegroundColor Green
} else {
    Write-Host "⚠️ Posting server is not running. Attempting to restart..." -ForegroundColor Yellow
    pm2 restart posting-server
    $pm2Status = pm2 list | Out-String
    if ($pm2Status -match "posting-server.*online") {
        Write-Host "✅ Posting server restarted successfully!" -ForegroundColor Green
    } else {
        Write-Host "❌ Failed to start posting server. Please check logs with 'pm2 logs posting-server'." -ForegroundColor Red
        exit 1
    }
}

# Install PM2 log rotation module
Write-Host "🔧 Setting up PM2 log rotation..." -ForegroundColor Yellow
pm2 install pm2-logrotate
$currentConfig = pm2 conf | Out-String
if ($currentConfig -notmatch "max_size.*10M") {
    pm2 set pm2-logrotate:max_size 10M
    pm2 set pm2-logrotate:retain 30
    pm2 set pm2-logrotate:compress true
    pm2 set pm2-logrotate:dateFormat YYYY-MM-DD_HH-mm-ss
    pm2 set pm2-logrotate:workerInterval 30
    pm2 set pm2-logrotate:rotateInterval "0 0 * * *"
    pm2 set pm2-logrotate:rotateModule true
} else {
    Write-Host "✅ PM2 log rotation settings already configured." -ForegroundColor Green
}

Write-Host ""
Write-Host "✅ Server started and configured to run on system boot!" -ForegroundColor Green
Write-Host "📁 Downloaded complete posting server with all folders:" -ForegroundColor Cyan
Write-Host "   - config/" -ForegroundColor White
Write-Host "   - models/" -ForegroundColor White
Write-Host "   - utils/" -ForegroundColor White
Write-Host "   - server.js" -ForegroundColor White
Write-Host "   - package.json" -ForegroundColor White
Write-Host ""
Write-Host "🔧 PM2 Auto-Start Information:" -ForegroundColor Yellow
Write-Host "   - PM2 processes will auto-start on system boot via 'pm2 startup'" -ForegroundColor White
Write-Host "   - PM2 startup script configured for Windows" -ForegroundColor White
Write-Host "   - Process list saved with 'pm2 save' for resurrection after reboot" -ForegroundColor White
Write-Host "   - No additional Windows service installation required" -ForegroundColor White
Write-Host "   - PM2 logs: Use 'pm2 logs' command to view application logs" -ForegroundColor White
Write-Host ""
Write-Host "To manage the PM2 server, use these commands:" -ForegroundColor Yellow
Write-Host "  - pm2 status              # Check server status" -ForegroundColor White
Write-Host "  - pm2 logs                # View all logs" -ForegroundColor White
Write-Host "  - pm2 logs posting-server # View posting server logs" -ForegroundColor White
Write-Host "  - pm2 stop all           # Stop the server" -ForegroundColor White
Write-Host "  - pm2 restart all        # Restart the server" -ForegroundColor White
Write-Host "  - pm2 delete posting-server # Remove the server from PM2" -ForegroundColor White
Write-Host ""
Write-Host "To manage PM2 auto-startup:" -ForegroundColor Yellow
Write-Host "  - pm2 startup                       # Configure PM2 to start on boot" -ForegroundColor White
Write-Host "  - pm2 save                          # Save current PM2 process list" -ForegroundColor White
Write-Host "  - pm2 resurrect                     # Restore saved PM2 processes" -ForegroundColor White
Write-Host "  - pm2 unstartup                     # Remove PM2 from startup (if needed)" -ForegroundColor White
Write-Host "  - pm2 startup --help                # View startup command options" -ForegroundColor White
Write-Host ""
Write-Host "To test auto-startup after reboot/power loss:" -ForegroundColor Cyan
Write-Host "  1. Restart your computer or simulate power loss" -ForegroundColor White
Write-Host "  2. Wait for system to fully boot" -ForegroundColor White
Write-Host "  3. Check PM2 service: 'Get-Service -Name PM2'" -ForegroundColor White
Write-Host "  4. Check posting server: 'pm2 status'" -ForegroundColor White
Write-Host "  5. Verify server monitoring is working" -ForegroundColor White