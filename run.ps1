# PowerShell Script for Setting up Posting Server
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

# Function to setup PM2 Windows startup using Task Scheduler - FIXED VERSION
function Setup-PM2WindowsStartup {
    Write-Host "🔧 Setting up PM2 Windows startup with proper user context..." -ForegroundColor Yellow
    
    try {
        # Get current user info
        $CurrentUser = $env:USERNAME
        $CurrentDomain = $env:USERDOMAIN
        $PostingServerPath = Join-Path $env:USERPROFILE "posting_server"
        $LogPath = Join-Path $env:USERPROFILE "logs\pm2-startup.log"
        $PM2Home = Join-Path $env:USERPROFILE ".pm2"
        
        # Ensure PM2_HOME directory exists
        if (!(Test-Path $PM2Home)) {
            New-Item -ItemType Directory -Path $PM2Home -Force | Out-Null
        }
        
        # Set PM2_HOME environment variable persistently for the user
        [System.Environment]::SetEnvironmentVariable("PM2_HOME", $PM2Home, [System.EnvironmentVariableTarget]::User)
        $env:PM2_HOME = $PM2Home
        
        # Create logs directory if it doesn't exist
        $LogDir = Split-Path $LogPath -Parent
        if (!(Test-Path $LogDir)) {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        }
        
        # Create improved startup script with explicit PM2 home and environment
        $StartupScript = @"
# PM2 Startup Script for Posting Server - Fixed Version
# Set PM2 home directory explicitly
`$env:PM2_HOME = "$PM2Home"

# Log startup attempt
Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ==================================="
Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] PM2 Startup Script Started"
Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Current User: \`$env:USERNAME"
Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] PM2 Home: \`$env:PM2_HOME"
Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] System uptime: \`$(Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object -ExpandProperty LastBootUpTime)"

# Change to posting server directory
Set-Location "$PostingServerPath"
Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Changed to directory: \`$(Get-Location)"

# Wait a bit for system to stabilize
Start-Sleep -Seconds 10

# Check if PM2 dump file exists
`$dumpFile = Join-Path "$PM2Home" "dump.pm2"
if (Test-Path `$dumpFile) {
    Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] PM2 dump file found: `$dumpFile"
} else {
    Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] PM2 dump file NOT found: `$dumpFile"
}

# Start PM2 resurrect
Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting PM2 resurrect..."
try {
    `$resurrectOutput = pm2 resurrect 2>&1
    Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] PM2 resurrect output: `$resurrectOutput"
} catch {
    Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] PM2 resurrect failed: `$_"
}

# Wait for processes to start
Start-Sleep -Seconds 10

# Check PM2 status
Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] PM2 status after resurrect:"
try {
    `$pm2List = pm2 list 2>&1
    Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] `$pm2List"
} catch {
    Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] PM2 list failed: `$_"
}

# If no processes found, try to start the server manually
if (`$pm2List -match "0 processes") {
    Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] No processes found, starting server manually..."
    try {
        pm2 start server.js --name "posting-server" --log "../logs/posting-server.log" --exp-backoff-restart-delay=100
        pm2 save
        Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Server started manually and saved"
    } catch {
        Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Manual server start failed: `$_"
    }
}

Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] PM2 startup script completed"
Add-Content -Path "$LogPath" -Value "[\`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ==================================="
"@
        
        # Save the startup script
        $ScriptPath = Join-Path $env:USERPROFILE "pm2_posting_server_startup.ps1"
        $StartupScript | Out-File -FilePath $ScriptPath -Encoding UTF8
        
        # Create scheduled task to run as current user
        $TaskName = "PM2 Posting Server Startup"
        $TaskDescription = "Start PM2 posting server on system boot"
        
        # Delete existing task if it exists
        try {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        }
        catch {
            # Task doesn't exist, continue
        }
        
        # Create new task with current user context
        $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""
        $Trigger = New-ScheduledTaskTrigger -AtStartup
        $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
        
        # Use current user instead of SYSTEM
        $Principal = New-ScheduledTaskPrincipal -UserId "$CurrentDomain\$CurrentUser" -LogonType Interactive -RunLevel Highest
        
        Register-ScheduledTask -TaskName $TaskName -Description $TaskDescription -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal
        
        Write-Host "✅ Windows Task Scheduler setup completed with user context!" -ForegroundColor Green
        Write-Host "📋 Task name: $TaskName" -ForegroundColor Cyan
        Write-Host "📋 Running as: $CurrentDomain\$CurrentUser" -ForegroundColor Cyan
        Write-Host "📋 Script location: $ScriptPath" -ForegroundColor Cyan
        Write-Host "📋 Startup log: $LogPath" -ForegroundColor Cyan
        
        return $true
    }
    catch {
        Write-Host "⚠️ Failed to setup Windows Task Scheduler: $($_.Exception.Message)" -ForegroundColor Yellow
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

# Set PM2_HOME environment variable persistently for the user
$PM2Home = Join-Path $env:USERPROFILE ".pm2"
[System.Environment]::SetEnvironmentVariable("PM2_HOME", $PM2Home, [System.EnvironmentVariableTarget]::User)
$env:PM2_HOME = $PM2Home

# Ensure PM2_HOME directory exists
if (!(Test-Path $PM2Home)) {
    New-Item -ItemType Directory -Path $PM2Home -Force | Out-Null
}

# Remove existing posting_server directory if it exists
if (Test-Path "posting_server") {
    Write-Host "🗑️ Removing existing posting_server directory..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force "posting_server"
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

# Setup PM2 to start on system boot - Windows compatible version
Write-Host "🔧 Setting up PM2 to start on system boot..." -ForegroundColor Yellow
try {
    $startupOutput = pm2 startup 2>&1
    if ($startupOutput -match "Init system not found" -or $startupOutput -match "error") {
        Write-Host "⚠️ Standard PM2 startup not supported on Windows. Using Windows Task Scheduler instead..." -ForegroundColor Yellow
        
        # Use our Windows-specific startup method
        $setupSuccess = Setup-PM2WindowsStartup
        
        if ($setupSuccess) {
            Write-Host "✅ PM2 startup configured successfully using Windows Task Scheduler!" -ForegroundColor Green
        } else {
            Write-Host "⚠️ Warning: PM2 startup setup failed. Server will need to be started manually after reboot." -ForegroundColor Yellow
        }
    } else {
        Write-Host "✅ PM2 startup configured successfully!" -ForegroundColor Green
    }
}
catch {
    Write-Host "⚠️ PM2 startup failed. Setting up Windows Task Scheduler instead..." -ForegroundColor Yellow
    $setupSuccess = Setup-PM2WindowsStartup
    
    if (!$setupSuccess) {
        Write-Host "⚠️ Warning: PM2 startup setup failed. Server will need to be started manually after reboot." -ForegroundColor Yellow
    }
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

Write-Host "✅ Server started and configured to run on system boot!" -ForegroundColor Green
Write-Host "📁 Downloaded complete posting server with all folders:" -ForegroundColor Cyan
Write-Host "   - config/" -ForegroundColor White
Write-Host "   - models/" -ForegroundColor White
Write-Host "   - utils/" -ForegroundColor White
Write-Host "   - server.js" -ForegroundColor White
Write-Host "   - package.json" -ForegroundColor White
Write-Host ""
Write-Host "🔧 Windows Startup Information:" -ForegroundColor Yellow
Write-Host "   - PM2 processes will auto-start on system boot via Windows Task Scheduler" -ForegroundColor White
Write-Host "   - Task name: 'PM2 Posting Server Startup'" -ForegroundColor White
Write-Host "   - Task runs as: $env:USERDOMAIN\$env:USERNAME (your user account)" -ForegroundColor White
Write-Host "   - You can view/manage the task in Windows Task Scheduler" -ForegroundColor White
Write-Host "   - Startup log: logs\pm2-startup.log" -ForegroundColor White
Write-Host ""
Write-Host "To manage the server, use these PM2 commands:" -ForegroundColor Yellow
Write-Host "  - pm2 status              # Check server status" -ForegroundColor White
Write-Host "  - pm2 logs                # View all logs" -ForegroundColor White
Write-Host "  - pm2 logs posting-server # View posting server logs" -ForegroundColor White
Write-Host "  - pm2 stop all           # Stop the server" -ForegroundColor White
Write-Host "  - pm2 restart all        # Restart the server" -ForegroundColor White
Write-Host "  - pm2 delete posting-server # Remove the server from PM2" -ForegroundColor White
Write-Host ""
Write-Host "To test auto-startup:" -ForegroundColor Cyan
Write-Host "  1. Restart your computer" -ForegroundColor White
Write-Host "  2. Check with 'pm2 status' after boot" -ForegroundColor White
Write-Host "  3. Check startup log at 'logs\pm2-startup.log'" -ForegroundColor White