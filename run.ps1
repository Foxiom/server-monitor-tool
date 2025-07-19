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
        pm2 stop all 2>$null
        pm2 delete all 2>$null
        pm2 kill 2>$null
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
    ch catálogo install nodejs-lts -y
    
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
    }
    choco install git -y
    
    # Refresh environment variables
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# Function to install NSSM (Non-Sucking Service Manager)
function Install-NSSM {
    Write-Host "📦 Installing NSSM..." -ForegroundColor Yellow
    if (!(Test-Command "choco")) {
        Install-Chocolatey
    }
    choco install nssm -y
    
    # Refresh environment variables
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
    
    if (Test-Command "nssm") {
        Write-Host "✅ NSSM installed successfully!" -ForegroundColor Green
        return $true
    }
    Write-Host "⚠️ NSSM installation verification failed" -ForegroundColor Yellow
    return $false
}

# Function to create and install Windows Service for PM2 Posting Server using NSSM
function Setup-PM2WindowsService {
    Write-Host "🔧 Setting up PM2 Posting Server Windows Service..." -ForegroundColor Yellow
    
    try {
        # Check if running as administrator
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Host "❌ This script must be run as Administrator to create a Windows Service." -ForegroundColor Red
            Write-Host "💡 Right-click PowerShell and select 'Run as Administrator'." -ForegroundColor Cyan
            return $false
        }
        
        # Install NSSM if not available
        if (!(Test-Command "nssm")) {
            Write-Host "📦 NSSM not found, installing..." -ForegroundColor Yellow
            $nssmInstalled = Install-NSSM
            if (-not $nssmInstalled) {
                Write-Host "❌ Failed to install NSSM. Cannot create service." -ForegroundColor Red
                return $false
            }
        }
        
        # Get paths
        $PostingServerPath = Join-Path $env:USERPROFILE "posting_server"
        $LogDir = Join-Path $env:USERPROFILE "logs"
        $LogPath = Join-Path $LogDir "pm2-service.log"
        $StdoutLogPath = Join-Path $LogDir "pm2-service-stdout.log"
        $StderrLogPath = Join-Path $LogDir "pm2-service-stderr.log"
        $PM2Home = Join-Path $env:USERPROFILE ".pm2"
        $ServiceName = "PM2PostingServer"
        $ServiceDisplayName = "PM2 Posting Server"
        $ServiceDescription = "PM2 Posting Server - Auto-starts server-monitor-tool on system boot"
        
        # Ensure PM2_HOME directory exists
        if (!(Test-Path $PM2Home)) {
            New-Item -ItemType Directory -Path $PM2Home -Force | Out-Null
        }
        
        # Set PM2_HOME environment variable persistently
        [System.Environment]::SetEnvironmentVariable("PM2_HOME", $PM2Home, [System.EnvironmentVariableTarget]::Machine)
        [System.Environment]::SetEnvironmentVariable("PM2_HOME", $PM2Home, [System.EnvironmentVariableTarget]::User)
        $env:PM2_HOME = $PM2Home
        
        # Create logs directory
        if (!(Test-Path $LogDir)) {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        }
        
        # Create simplified batch wrapper script for the service
        $BatchScript = @"
@echo off
REM PM2 Posting Server Service Batch Wrapper
setlocal EnableExtensions EnableDelayedExpansion

set PM2_HOME=$PM2Home
set "PATH=%PATH%;%ProgramFiles%\nodejs"

REM Log startup
echo [%date% %time%] Starting PM2 Posting Server Service >> "$LogPath"
cd /d "$PostingServerPath"
if %errorlevel% neq 0 (
    echo [%date% %time%] ERROR: Failed to change to $PostingServerPath >> "$LogPath"
    exit /b 1
)

REM Wait for system to stabilize
timeout /t 30 /nobreak >nul
echo [%date% %time%] System stabilization wait completed >> "$LogPath"

REM Initialize PM2 and resurrect processes
pm2 kill >nul 2>&1
timeout /t 5 /nobreak >nul
echo [%date% %time%] Initializing PM2 daemon... >> "$LogPath"
pm2 ping >nul 2>&1
if %errorlevel% neq 0 (
    echo [%date% %time%] PM2 daemon not responding, starting... >> "$LogPath"
    pm2 resurrect >> "$LogPath" 2>&1
    if %errorlevel% neq 0 (
        echo [%date% %time%] ERROR: PM2 resurrection failed, starting fresh... >> "$LogPath"
        pm2 start server.js --name "posting-server" --log "../logs/posting-server.log" --exp-backoff-restart-delay=100 --max-restarts=10 --min-uptime=10s >> "$LogPath" 2>&1
    )
) else (
    echo [%date% %time%] PM2 daemon running, resurrecting processes... >> "$LogPath"
    pm2 resurrect >> "$LogPath" 2>&1
)

REM Save PM2 process list
pm2 save >> "$LogPath" 2>&1
echo [%date% %time%] PM2 process list saved >> "$LogPath"

REM Monitor loop to ensure PM2 stays running
:monitor_loop
timeout /t 60 /nobreak >nul
pm2 list --no-colors > "%TEMP%\pm2status.txt" 2>&1
findstr "posting-server.*online" "%TEMP%\pm2status.txt" >nul
if %errorlevel% neq 0 (
    echo [%date% %time%] WARNING: Posting server not online, attempting recovery... >> "$LogPath"
    pm2 restart posting-server >> "$LogPath" 2>&1
    timeout /t 10 /nobreak >nul
    pm2 list --no-colors > "%TEMP%\pm2restart_check.txt" 2>&1
    findstr "posting-server.*online" "%TEMP%\pm2restart_check.txt" >nul
    if %errorlevel% neq 0 (
        echo [%date% %time%] ERROR: Restart failed, starting fresh... >> "$LogPath"
        pm2 stop posting-server >nul 2>&1
        pm2 delete posting-server >nul 2>&1
        pm2 start server.js --name "posting-server" --log "../logs/posting-server.log" --exp-backoff-restart-delay=100 --max-restarts=10 --min-uptime=10s >> "$LogPath" 2>&1
        pm2 save >> "$LogPath" 2>&1
    )
)
goto monitor_loop
"@

        # Save the batch script
        $BatchScriptPath = Join-Path $env:USERPROFILE "pm2_posting_server_service.bat"
        $BatchScript | Out-File -FilePath $BatchScriptPath -Encoding ASCII
        Write-Host "📝 Service batch script created at: $BatchScriptPath" -ForegroundColor Cyan
        
        # Remove existing service
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
        & nssm set $ServiceName AppStdout $StdoutLogPath | Out-Null
        & nssm set $ServiceName AppStderr $StderrLogPath | Out-Null
        & nssm set $ServiceName AppRotateFiles 1 | Out-Null
        & nssm set $ServiceName AppRotateOnline 1 | Out-Null
        & nssm set $ServiceName AppRotateSeconds 86400 | Out-Null
        & nssm set $ServiceName AppRotateBytes 10485760 | Out-Null
        
        # Configure service to run as LocalSystem (default) with access to desktop
        & nssm set $ServiceName ObjectName LocalSystem | Out-Null
        & nssm set $ServiceName Type SERVICE_WIN32_OWN_PROCESS | Out-Null
        
        # Set restart policy
        & nssm set $ServiceName AppExit Default Restart | Out-Null
        & nssm set $ServiceName AppRestartDelay 5000 | Out-Null
        
        Write-Host "✅ Windows service created successfully with NSSM!" -ForegroundColor Green
        
        # Start the service
        Write-Host "🚀 Starting PM2 Posting Server service..." -ForegroundColor Yellow
        try {
            & nssm start $ServiceName
            Start-Sleep -Seconds 10
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
        Write-Host "   Service Log: $LogPath" -ForegroundColor White
        Write-Host "   Service Stdout Log: $StdoutLogPath" -ForegroundColor White
        Write-Host "   Service Stderr Log: $StderrLogPath" -ForegroundColor White
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

# Check and install Node.js
if (!(Test-Command "node")) {
    Write-Host "❌ Node.js is not installed." -ForegroundColor Red
    Install-NodeJS
}

# Check and install Git
if (!(Test-Command "git")) {
    Write-Host "❌ Git is not installed." -ForegroundColor Red
    Install-Git
}

# Check and install PM2
if (!(Test-Command "pm2")) {
    Write-Host "📦 Installing PM2 globally..." -ForegroundColor Yellow
    npm install -g pm2
}

# Set PM2_HOME environment variable
$PM2Home = Join-Path $env:USERPROFILE ".pm2"
[System.Environment]::SetEnvironmentVariable("PM2_HOME", $PM2Home, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable("PM2_HOME", $PM2Home, [System.EnvironmentVariableTarget]::User)
$env:PM2_HOME = $PM2Home

# Ensure PM2_HOME directory exists
if (!(Test-Path $PM2Home)) {
    New-Item -ItemType Directory -Path $PM2Home -Force | Out-Null
}

# Perform enhanced cleanup
if (Test-Path "posting_server") {
    Enhanced-Cleanup
}

# Create logs directory
if (!(Test-Path "logs")) {
    Write-Host "📁 Creating logs directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path "logs" | Out-Null
}

# Setup posting server
Write-Host "🔧 Setting up posting server..." -ForegroundColor Green
$TempDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ }
Write-Host "⬇️ Downloading server-monitor-tool from GitHub..." -ForegroundColor Cyan
git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git $TempDir.FullName
Copy-Item -Recurse -Path (Join-Path $TempDir.FullName "posting_server") -Destination "."
Remove-Item -Recurse -Force $TempDir
Set-Location "posting_server"

# Install dependencies
Write-Host "📦 Installing posting server dependencies..." -ForegroundColor Yellow
npm install

# Set permissions
Write-Host "🔒 Setting up permissions..." -ForegroundColor Yellow
Get-ChildItem -Recurse | ForEach-Object {
    if (!$_.PSIsContainer) {
        $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
    }
}
$logsPath = Join-Path (Get-Location).Path "../logs"
(Get-Item $logsPath).Attributes = (Get-Item $logsPath).Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)

# Start the server with PM2
Write-Host "🚀 Starting posting server with PM2..." -ForegroundColor Green
pm2 start server.js --name "posting-server" --log "../logs/posting-server.log" --exp-backoff-restart-delay=100 --max-restarts=10 --min-uptime=10s
pm2 save

# Setup Windows Service
Write-Host "🔧 Setting up Windows Service for PM2 auto-start..." -ForegroundColor Yellow
$serviceSetupSuccess = Setup-PM2WindowsService

if ($serviceSetupSuccess) {
    Write-Host "✅ Windows Service configured successfully!" -ForegroundColor Green
} else {
    Write-Host "⚠️ Windows Service setup failed. Server will need manual start after reboot." -ForegroundColor Yellow
    Write-Host "💡 Run PowerShell as Administrator and try again." -ForegroundColor Cyan
}

# Verify server status
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
        Write-Host "❌ Failed to start posting server. Check logs with 'pm2 logs posting-server'." -ForegroundColor Red
        exit 1
    }
}

# Setup PM2 log rotation
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
}

Write-Host ""
Write-Host "✅ Server started and configured to run on system boot!" -ForegroundColor Green
Write-Host "📁 Server-monitor-tool installed with folders:" -ForegroundColor Cyan
Write-Host "   - config/" -ForegroundColor White
Write-Host "   - models/" -ForegroundColor White
Write-Host "   - utils/" -ForegroundColor White
Write-Host "   - server.js" -ForegroundColor White
Write-Host "   - package.json" -ForegroundColor White
Write-Host ""
Write-Host "🔧 Windows Service Information:" -ForegroundColor Yellow
Write-Host "   - Service Name: PM2PostingServer" -ForegroundColor White
Write-Host "   - Auto-starts on system boot" -ForegroundColor White
Write-Host "   - Service Log: logs\pm2-service.log" -ForegroundColor White
Write-Host ""
Write-Host "🔧 PM2 Management Commands:" -ForegroundColor Yellow
Write-Host "   pm2 status              # Check server status" -ForegroundColor White
Write-Host "   pm2 logs                # View all logs" -ForegroundColor White
Write-Host "   pm2 logs posting-server # View server logs" -ForegroundColor White
Write-Host "   pm2 stop all           # Stop the server" -ForegroundColor White
Write-Host "   pm2 restart all        # Restart the server" -ForegroundColor White
Write-Host ""
Write-Host "🔧 Service Management Commands:" -ForegroundColor Yellow
Write-Host "   Get-Service -Name PM2PostingServer   # Check service status" -ForegroundColor White
Write-Host "   Start-Service -Name PM2PostingServer # Start the service" -ForegroundColor White
Write-Host "   Stop-Service -Name PM2PostingServer  # Stop the service" -ForegroundColor White
Write-Host ""
Write-Host "To test auto-start:" -ForegroundColor Cyan
Write-Host "   1. Restart your computer" -ForegroundColor White
Write-Host "   2. Run 'Get-Service -Name PM2PostingServer' to verify service" -ForegroundColor White
Write-Host "   3. Run 'pm2 status' to verify server" -ForegroundColor White
Write-Host "   4. Check logs at 'logs\pm2-service.log'" -ForegroundColor White