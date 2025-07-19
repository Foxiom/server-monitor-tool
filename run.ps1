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

# Function to create and install Windows Service for PM2 Posting Server
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
        
        # Get current user info and paths
        $CurrentUser = $env:USERNAME
        $CurrentDomain = $env:USERDOMAIN
        $PostingServerPath = Join-Path $env:USERPROFILE "posting_server"
        $LogPath = Join-Path $env:USERPROFILE "logs\pm2-service.log"
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
        
        # Create service wrapper script
        $ServiceScript = @"
# PM2 Posting Server Service Wrapper Script
# Set PM2 home directory explicitly
`$env:PM2_HOME = "$PM2Home"

# Set up logging function
function Write-ServiceLog {
    param([string]`$Message)
    Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] `$Message"
}

# Log service startup
Write-ServiceLog "==================================="
Write-ServiceLog "PM2 Posting Server Service Started"
Write-ServiceLog "Current User: \`$env:USERNAME"
Write-ServiceLog "PM2 Home: \`$env:PM2_HOME"
Write-ServiceLog "Working Directory: $PostingServerPath"

# Change to posting server directory
try {
    Set-Location "$PostingServerPath"
    Write-ServiceLog "Changed to directory: \`$(Get-Location)"
}
catch {
    Write-ServiceLog "ERROR: Failed to change directory: \`$_"
    exit 1
}

# Ensure environment path is loaded
`$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

# Wait for system to stabilize
Start-Sleep -Seconds 30
Write-ServiceLog "System stabilization wait completed"

# Check if PM2 is available
try {
    `$pm2Version = pm2 -v 2>&1
    Write-ServiceLog "PM2 version: `$pm2Version"
}
catch {
    Write-ServiceLog "ERROR: PM2 not found: \`$_"
    exit 1
}

# Check if PM2 dump file exists and try to resurrect
`$dumpFile = Join-Path "$PM2Home" "dump.pm2"
if (Test-Path `$dumpFile) {
    Write-ServiceLog "PM2 dump file found, attempting resurrect..."
    try {
        `$resurrectOutput = pm2 resurrect 2>&1
        Write-ServiceLog "PM2 resurrect output: `$resurrectOutput"
        Start-Sleep -Seconds 10
    }
    catch {
        Write-ServiceLog "PM2 resurrect failed: \`$_"
    }
}
else {
    Write-ServiceLog "No PM2 dump file found"
}

# Check if posting-server is running
`$pm2List = pm2 list --no-colors 2>&1
Write-ServiceLog "PM2 list output: `$pm2List"

if (`$pm2List -notmatch "posting-server.*online") {
    Write-ServiceLog "Posting server not running, starting manually..."
    try {
        pm2 start server.js --name "posting-server" --log "../logs/posting-server.log" --exp-backoff-restart-delay=100
        pm2 save
        Write-ServiceLog "Posting server started and saved"
        
        # Verify it started
        `$verifyList = pm2 list --no-colors 2>&1
        Write-ServiceLog "Verification - PM2 list: `$verifyList"
    }
    catch {
        Write-ServiceLog "ERROR: Failed to start posting server: \`$_"
        exit 1
    }
}
else {
    Write-ServiceLog "Posting server already running"
}

Write-ServiceLog "PM2 Posting Server Service initialization completed successfully"
Write-ServiceLog "==================================="

# Keep the service running - monitor PM2 processes
while (`$true) {
    try {
        Start-Sleep -Seconds 60
        `$status = pm2 list --no-colors 2>&1
        
        # Check if posting-server process is still running
        if (`$status -notmatch "posting-server.*online") {
            Write-ServiceLog "WARNING: Posting server not online, attempting restart..."
            pm2 restart posting-server 2>&1
            pm2 save
        }
    }
    catch {
        Write-ServiceLog "ERROR in monitoring loop: \`$_"
        Start-Sleep -Seconds 60
    }
}
"@
        
        # Save the service script
        $ServiceScriptPath = Join-Path $env:USERPROFILE "pm2_posting_server_service.ps1"
        $ServiceScript | Out-File -FilePath $ServiceScriptPath -Encoding UTF8
        
        Write-Host "📝 Service script created at: $ServiceScriptPath" -ForegroundColor Cyan
        
        # Remove existing service if it exists
        try {
            $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if ($existingService) {
                Write-Host "🗑️ Removing existing service..." -ForegroundColor Yellow
                if ($existingService.Status -eq "Running") {
                    Stop-Service -Name $ServiceName -Force
                    Start-Sleep -Seconds 5
                }
                & sc.exe delete $ServiceName | Out-Null
                Start-Sleep -Seconds 3
            }
        }
        catch {
            Write-Host "⚠️ Warning during existing service cleanup: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        
        # Create the Windows service using sc.exe
        Write-Host "🔧 Creating Windows service..." -ForegroundColor Yellow
        
        # Build the service command
        $ServiceCommand = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ServiceScriptPath`""
        
        # Create service
        $createResult = & sc.exe create $ServiceName binPath= $ServiceCommand DisplayName= $ServiceDisplayName start= auto
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Failed to create service: $createResult" -ForegroundColor Red
            return $false
        }
        
        # Set service description
        & sc.exe description $ServiceName $ServiceDescription | Out-Null
        
        # Configure service recovery options
        & sc.exe failure $ServiceName reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
        
        # Set service to run as Local System (for broader permissions)
        # Note: You can change this to run as a specific user if needed
        & sc.exe config $ServiceName obj= "LocalSystem" | Out-Null
        
        Write-Host "✅ Windows service created successfully!" -ForegroundColor Green
        
        # Start the service
        Write-Host "🚀 Starting PM2 Posting Server service..." -ForegroundColor Yellow
        try {
            Start-Service -Name $ServiceName
            Start-Sleep -Seconds 5
            
            # Verify service is running
            $service = Get-Service -Name $ServiceName
            if ($service.Status -eq "Running") {
                Write-Host "✅ Service started successfully!" -ForegroundColor Green
            } else {
                Write-Host "⚠️ Service created but not running. Status: $($service.Status)" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "⚠️ Service created but failed to start: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "💡 You can start it manually using: Start-Service -Name $ServiceName" -ForegroundColor Cyan
        }
        
        # Display service information
        Write-Host ""
        Write-Host "📋 Service Details:" -ForegroundColor Cyan
        Write-Host "   Service Name: $ServiceName" -ForegroundColor White
        Write-Host "   Display Name: $ServiceDisplayName" -ForegroundColor White
        Write-Host "   Startup Type: Automatic" -ForegroundColor White
        Write-Host "   Service Script: $ServiceScriptPath" -ForegroundColor White
        Write-Host "   Service Log: $LogPath" -ForegroundColor White
        Write-Host ""
        Write-Host "🔧 Service Management Commands:" -ForegroundColor Yellow
        Write-Host "   Start-Service -Name $ServiceName        # Start the service" -ForegroundColor White
        Write-Host "   Stop-Service -Name $ServiceName         # Stop the service" -ForegroundColor White
        Write-Host "   Restart-Service -Name $ServiceName      # Restart the service" -ForegroundColor White
        Write-Host "   Get-Service -Name $ServiceName          # Check service status" -ForegroundColor White
        Write-Host "   sc.exe delete $ServiceName              # Remove the service (as Administrator)" -ForegroundColor White
        
        return $true
    }
    catch {
        Write-Host "❌ Failed to setup Windows service: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "💡 Make sure you're running PowerShell as Administrator" -ForegroundColor Cyan
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
Write-Host "💾 Saving PM2 process list..." -ForegroundColor Yellow
pm2 save

# Setup Windows Service for PM2 auto-startup
Write-Host "🔧 Setting up Windows Service for PM2 auto-startup..." -ForegroundColor Yellow
$serviceSetupSuccess = Setup-PM2WindowsService

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
Write-Host "🔧 Windows Service Information:" -ForegroundColor Yellow
Write-Host "   - PM2 processes will auto-start on system boot via Windows Service" -ForegroundColor White
Write-Host "   - Service name: 'PM2PostingServer'" -ForegroundColor White
Write-Host "   - Service runs as: LocalSystem (with elevated privileges)" -ForegroundColor White
Write-Host "   - You can view/manage the service in Windows Services (services.msc)" -ForegroundColor White
Write-Host "   - Service log: logs\pm2-service.log" -ForegroundColor White
Write-Host ""
Write-Host "To manage the PM2 server, use these commands:" -ForegroundColor Yellow
Write-Host "  - pm2 status              # Check server status" -ForegroundColor White
Write-Host "  - pm2 logs                # View all logs" -ForegroundColor White
Write-Host "  - pm2 logs posting-server # View posting server logs" -ForegroundColor White
Write-Host "  - pm2 stop all           # Stop the server" -ForegroundColor White
Write-Host "  - pm2 restart all        # Restart the server" -ForegroundColor White
Write-Host "  - pm2 delete posting-server # Remove the server from PM2" -ForegroundColor White
Write-Host ""
Write-Host "To manage the Windows Service:" -ForegroundColor Yellow
Write-Host "  - Get-Service -Name PM2PostingServer    # Check service status" -ForegroundColor White
Write-Host "  - Start-Service -Name PM2PostingServer  # Start the service" -ForegroundColor White
Write-Host "  - Stop-Service -Name PM2PostingServer   # Stop the service" -ForegroundColor White
Write-Host "  - Restart-Service -Name PM2PostingServer # Restart the service" -ForegroundColor White
Write-Host "  - services.msc                          # Open Windows Services GUI" -ForegroundColor White
Write-Host ""
Write-Host "To test auto-startup:" -ForegroundColor Cyan
Write-Host "  1. Restart your computer" -ForegroundColor White
Write-Host "  2. Check with 'Get-Service -Name PM2PostingServer'" -ForegroundColor White
Write-Host "  3. Check with 'pm2 status' after boot" -ForegroundColor White
Write-Host "  4. Check service log at 'logs\pm2-service.log'" -ForegroundColor White