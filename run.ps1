# PowerShell equivalent of run.sh with Windows-specific PM2 startup handling
# Requires PowerShell 5.0+ and Administrator privileges for some operations

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to clean up on error
function Cleanup {
    Write-Host "❌ An error occurred. Cleaning up..." -ForegroundColor Red
    if (Test-Path "posting_server") {
        Remove-Item -Path "posting_server" -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($script:TempDir -and (Test-Path $script:TempDir)) {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    exit 1
}

# Function to check if a command exists
function Test-Command {
    param([string]$Command)
    try {
        Get-Command $Command -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

# Function to install Node.js
function Install-NodeJS {
    Write-Host "📦 Installing Node.js..." -ForegroundColor Yellow
    
    # Check if Chocolatey is installed
    if (Test-Command "choco") {
        Write-Host "Using Chocolatey to install Node.js..." -ForegroundColor Green
        choco install nodejs -y
    }
    # Check if Scoop is installed
    elseif (Test-Command "scoop") {
        Write-Host "Using Scoop to install Node.js..." -ForegroundColor Green
        scoop install nodejs
    }
    # Check if winget is available
    elseif (Test-Command "winget") {
        Write-Host "Using winget to install Node.js..." -ForegroundColor Green
        winget install OpenJS.NodeJS
    }
    else {
        Write-Host "❌ No package manager found. Please install Node.js manually from https://nodejs.org/" -ForegroundColor Red
        Write-Host "Or install a package manager like Chocolatey: https://chocolatey.org/install" -ForegroundColor Yellow
        exit 1
    }
    
    # Refresh environment variables
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# Function to install Git
function Install-Git {
    Write-Host "📦 Installing Git..." -ForegroundColor Yellow
    
    # Check if Chocolatey is installed
    if (Test-Command "choco") {
        Write-Host "Using Chocolatey to install Git..." -ForegroundColor Green
        choco install git -y
    }
    # Check if Scoop is installed
    elseif (Test-Command "scoop") {
        Write-Host "Using Scoop to install Git..." -ForegroundColor Green
        scoop install git
    }
    # Check if winget is available
    elseif (Test-Command "winget") {
        Write-Host "Using winget to install Git..." -ForegroundColor Green
        winget install Git.Git
    }
    else {
        Write-Host "❌ No package manager found. Please install Git manually from https://git-scm.com/" -ForegroundColor Red
        exit 1
    }
    
    # Refresh environment variables
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# Function to install PM2 as a Windows Service using pm2-installer
function Install-PM2Service {
    Write-Host "🔧 Setting up PM2 as a Windows Service using pm2-installer..." -ForegroundColor Yellow
    
    if (-not (Test-Administrator)) {
        Write-Host "⚠️ Administrator privileges required for PM2 service installation." -ForegroundColor Yellow
        Write-Host "Please run this script as Administrator to install PM2 as a service." -ForegroundColor Yellow
        Write-Host "Falling back to basic PM2 save..." -ForegroundColor Yellow
        return
    }
    
    try {
        Write-Host "⬇️ Downloading pm2-installer..." -ForegroundColor Cyan
        
        # Download pm2-installer
        $pm2InstallerPath = Join-Path (Get-Location) "pm2-installer-main"
        if (Test-Path $pm2InstallerPath) {
            Remove-Item $pm2InstallerPath -Recurse -Force
        }
        
        # Download and extract pm2-installer
        $installerZip = Join-Path (Get-Location) "pm2-installer.zip"
        Invoke-WebRequest -Uri "https://github.com/jessety/pm2-installer/archive/main.zip" -OutFile $installerZip -UseBasicParsing
        Expand-Archive -Path $installerZip -DestinationPath (Get-Location) -Force
        Remove-Item $installerZip -Force
        
        # Navigate to pm2-installer directory
        Push-Location $pm2InstallerPath
        
        Write-Host "🔧 Configuring npm for service installation..." -ForegroundColor Yellow
        
        # Configure npm and PowerShell policy
        try {
            & npm run configure 2>&1 | Out-Host
            & npm run configure-policy 2>&1 | Out-Host
        }
        catch {
            Write-Host "⚠️ NPM configuration completed with warnings, proceeding..." -ForegroundColor Yellow
        }
        
        Write-Host "🚀 Installing PM2 as Windows Service..." -ForegroundColor Green
        
        # Install PM2 service
        & npm run setup 2>&1 | Out-Host
        
        Write-Host "✅ PM2 installed as Windows Service successfully!" -ForegroundColor Green
        Write-Host "PM2 will now run as a service and persist across reboots." -ForegroundColor Green
        
        # Return to original directory
        Pop-Location
        
        # Clean up installer directory
        Remove-Item $pm2InstallerPath -Recurse -Force -ErrorAction SilentlyContinue
        
        return $true
        
    }
    catch {
        Write-Host "⚠️ Failed to install PM2 service: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Falling back to basic PM2 save. You may need to manually start PM2 after reboot." -ForegroundColor Yellow
        
        # Clean up on error
        if (Get-Location | Select-String "pm2-installer") {
            Pop-Location -ErrorAction SilentlyContinue
        }
        Remove-Item $pm2InstallerPath -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $installerZip -Force -ErrorAction SilentlyContinue
        
        return $false
    }
}

# Function to check PM2 status without JSON parsing
function Test-PM2ProcessRunning {
    param([string]$ProcessName)
    try {
        $pm2Output = & pm2 list 2>&1
        if ($pm2Output -match "$ProcessName.*online") {
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

# Set up error handling
trap { Cleanup }

try {
    Write-Host "🚀 Starting Windows setup for posting server..." -ForegroundColor Cyan
    
    # Check and install Node.js if not present
    if (-not (Test-Command "node")) {
        Write-Host "❌ Node.js is not installed." -ForegroundColor Red
        Install-NodeJS
    }
    
    # Check and install Git if not present
    if (-not (Test-Command "git")) {
        Write-Host "❌ Git is not installed." -ForegroundColor Red
        Install-Git
    }
    
    # Check if PM2 is installed, if not install it globally
    if (-not (Test-Command "pm2")) {
        Write-Host "📦 Installing PM2 globally..." -ForegroundColor Yellow
        npm install -g pm2
    }
    
    # Remove existing posting_server directory if it exists
    if (Test-Path "posting_server") {
        Write-Host "🗑️ Removing existing posting_server directory..." -ForegroundColor Yellow
        Remove-Item -Path "posting_server" -Recurse -Force
    }
    
    # Create logs directory if it doesn't exist
    if (-not (Test-Path "logs")) {
        New-Item -ItemType Directory -Path "logs" | Out-Null
    }
    
    # Setup posting server
    Write-Host "🔧 Setting up posting server..." -ForegroundColor Yellow
    
    # Clone the repository to a temporary directory
    Write-Host "⬇️ Downloading complete posting server from GitHub..." -ForegroundColor Cyan
    $script:TempDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_.FullName }
    git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git $script:TempDir.FullName
    
    # Copy only the posting_server folder to our target location
    Copy-Item -Path (Join-Path $script:TempDir.FullName "posting_server") -Destination "." -Recurse
    
    # Clean up temporary directory
    Remove-Item -Path $script:TempDir -Recurse -Force
    
    # Navigate to posting_server directory
    Set-Location "posting_server"
    
    # Install posting server dependencies
    Write-Host "📦 Installing posting server dependencies..." -ForegroundColor Yellow
    npm install
    
    # Set posting server permissions (Windows equivalent)
    Write-Host "🔒 Setting up permissions..." -ForegroundColor Yellow
    # Note: Windows handles permissions differently, but we can set basic attributes
    
    # Start the server using PM2 with exponential backoff restart
    Write-Host "🚀 Starting posting server with PM2..." -ForegroundColor Green
    pm2 start server.js --name "posting-server" --log "../logs/posting-server.log" --exp-backoff-restart-delay=100
    
    # Save PM2 process list
    Write-Host "💾 Saving PM2 process list..." -ForegroundColor Yellow
    pm2 save
    
    # Setup PM2 to start on system boot using pm2-installer (Windows Service approach)
    $serviceInstalled = Install-PM2Service
    
    # Verify if the server is running using our custom function
    Write-Host "🔍 Verifying server status..." -ForegroundColor Yellow
    
    if (Test-PM2ProcessRunning "posting-server") {
        Write-Host "✅ Posting server is running!" -ForegroundColor Green
    }
    else {
        Write-Host "⚠️ Posting server is not running. Attempting to restart..." -ForegroundColor Yellow
        pm2 restart posting-server
        Start-Sleep -Seconds 3
        
        if (Test-PM2ProcessRunning "posting-server") {
            Write-Host "✅ Posting server restarted successfully!" -ForegroundColor Green
        }
        else {
            Write-Host "❌ Failed to start posting server. Please check logs with 'pm2 logs posting-server'." -ForegroundColor Red
            exit 1
        }
    }
    
    # Optional: Install PM2 log rotation module
    Write-Host "🔧 Setting up PM2 log rotation..." -ForegroundColor Yellow
    try {
        pm2 install pm2-logrotate
        pm2 set pm2-logrotate:max_size 10M
        pm2 set pm2-logrotate:compress true
    }
    catch {
        Write-Host "⚠️ PM2 log rotation setup failed, but this won't affect the server operation." -ForegroundColor Yellow
    }
    
    # Return to parent directory
    Set-Location ".."
    
    Write-Host "" -ForegroundColor White
    Write-Host "✅ Server started and configured to run on system boot!" -ForegroundColor Green
    Write-Host "📁 Downloaded complete posting server with all folders:" -ForegroundColor Cyan
    Write-Host "   - config/" -ForegroundColor White
    Write-Host "   - models/" -ForegroundColor White
    Write-Host "   - utils/" -ForegroundColor White
    Write-Host "   - server.js" -ForegroundColor White
    Write-Host "   - package.json" -ForegroundColor White
    Write-Host "" -ForegroundColor White
    Write-Host "To manage the server, use these PM2 commands:" -ForegroundColor Cyan
    Write-Host "  - pm2 status              # Check server status" -ForegroundColor White
    Write-Host "  - pm2 logs                # View all logs" -ForegroundColor White
    Write-Host "  - pm2 logs posting-server # View posting server logs" -ForegroundColor White
    Write-Host "  - pm2 stop all           # Stop the server" -ForegroundColor White
    Write-Host "  - pm2 restart all        # Restart the server" -ForegroundColor White
    Write-Host "  - pm2 delete posting-server # Remove the server from PM2" -ForegroundColor White
    Write-Host "" -ForegroundColor White
    
    if ($serviceInstalled) {
        Write-Host "Windows Service Integration:" -ForegroundColor Green
        Write-Host "  ✅ PM2 installed as Windows Service (Local Service user)" -ForegroundColor White
        Write-Host "  ✅ Automatic startup on system boot (no user login required)" -ForegroundColor White
        Write-Host "  ✅ Persists across reboots and user sessions" -ForegroundColor White
        Write-Host "  - Use 'services.msc' to manage the PM2 Windows Service" -ForegroundColor White
        Write-Host "  - PM2 commands require Administrator privileges" -ForegroundColor White
    } else {
        Write-Host "Startup Configuration:" -ForegroundColor Yellow
        Write-Host "  ⚠️ PM2 service installation failed or was skipped" -ForegroundColor White
        Write-Host "  - You may need to manually start PM2 after system reboot" -ForegroundColor White
        Write-Host "  - Run 'pm2 resurrect' after reboot to restore processes" -ForegroundColor White
        Write-Host "  - Consider running this script as Administrator for service installation" -ForegroundColor White
    }
}
catch {
    Write-Host "❌ Script execution failed: $($_.Exception.Message)" -ForegroundColor Red
    Cleanup
}