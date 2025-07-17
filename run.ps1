# Simplified PM2 Setup Script for Windows PowerShell
# Exit on error
$ErrorActionPreference = "Stop"

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
        Write-Host "✅ Chocolatey already installed" -ForegroundColor Green
    }
    choco install git -y
    
    # Refresh environment variables
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

Write-Host "🚀 Starting Simplified PM2 Posting Server Setup..." -ForegroundColor Cyan

# Check and install Node.js if not present
if (!(Test-Command "node")) {
    Write-Host "❌ Node.js is not installed." -ForegroundColor Red
    Install-NodeJS
} else {
    $nodeVersion = & node --version
    Write-Host "✅ Node.js is installed: $nodeVersion" -ForegroundColor Green
}

# Check and install Git if not present
if (!(Test-Command "git")) {
    Write-Host "❌ Git is not installed." -ForegroundColor Red
    Install-Git
} else {
    $gitVersion = & git --version
    Write-Host "✅ Git is installed: $gitVersion" -ForegroundColor Green
}

# Install PM2 if not present
if (!(Test-Command "pm2")) {
    Write-Host "📦 Installing PM2 globally..." -ForegroundColor Yellow
    npm install -g pm2
} else {
    $pm2Version = & pm2 --version
    Write-Host "✅ PM2 is installed: $pm2Version" -ForegroundColor Green
}

# Stop any existing posting-server processes
Write-Host "🛑 Stopping any existing posting-server processes..." -ForegroundColor Yellow
try {
    pm2 delete posting-server 2>$null
} catch {
    # Ignore error if process doesn't exist
}

# Remove existing posting_server directory if it exists
if (Test-Path "posting_server") {
    Write-Host "🗑️  Removing existing posting_server directory..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force "posting_server"
}

# Create logs directory
if (!(Test-Path "logs")) {
    New-Item -ItemType Directory -Path "logs" | Out-Null
}

# Setup posting server
Write-Host "🔧 Setting up posting server..." -ForegroundColor Blue

# Clone the repository to a temporary directory (shallow clone for efficiency)
Write-Host "⬇️ Downloading complete posting server from GitHub..." -ForegroundColor Cyan
$TempDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ }
git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git $TempDir.FullName

# Copy only the posting_server folder to our target location
Copy-Item -Recurse -Path (Join-Path $TempDir.FullName "posting_server") -Destination "."

# Clean up temporary directory
Remove-Item -Recurse -Force $TempDir

# Navigate to posting_server directory and install dependencies
Set-Location "posting_server"
Write-Host "📦 Installing posting server dependencies..." -ForegroundColor Yellow
npm install
Set-Location ".."

# Set posting server permissions (Windows equivalent)
Write-Host "🔒 Setting up permissions..." -ForegroundColor Yellow
Get-ChildItem -Path "posting_server" -Recurse | ForEach-Object {
    if (!$_.PSIsContainer) {
        # File - ensure it's not read-only
        $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
    }
}

# Start the server using PM2 with simple configuration
Write-Host "🚀 Starting posting server with PM2..." -ForegroundColor Green
pm2 start posting_server/server.js `
    --name "posting-server" `
    --log "logs/posting-server.log" `
    --error "logs/posting-server-error.log" `
    --out "logs/posting-server-out.log" `
    --max-memory-restart 500M `
    --time `
    --restart-delay 2000

# Save PM2 process list
Write-Host "💾 Saving PM2 process list..." -ForegroundColor Yellow
pm2 save

# Setup PM2 to start on system boot
Write-Host "🔧 Setting up PM2 startup..." -ForegroundColor Yellow
pm2 startup

Write-Host ""
Write-Host "🎉 ==================================" -ForegroundColor Green
Write-Host "✅ SERVER INSTALLATION COMPLETE!" -ForegroundColor Green
Write-Host "==================================" -ForegroundColor Green
Write-Host ""

Write-Host "📁 Downloaded complete posting server with all folders:" -ForegroundColor Cyan
Write-Host "   - config/" -ForegroundColor White
Write-Host "   - models/" -ForegroundColor White
Write-Host "   - utils/" -ForegroundColor White
Write-Host "   - server.js" -ForegroundColor White
Write-Host "   - package.json" -ForegroundColor White
Write-Host ""

Write-Host "🔧 Auto-restart features:" -ForegroundColor Yellow
Write-Host "   ✅ PM2 automatic restarts on crashes" -ForegroundColor Green
Write-Host "   ✅ Memory-based restarts (500MB limit)" -ForegroundColor Green
Write-Host "   ✅ Boot startup configured" -ForegroundColor Green
Write-Host "   ✅ Process monitoring enabled" -ForegroundColor Green
Write-Host ""

Write-Host "📋 Management Commands:" -ForegroundColor Yellow
Write-Host "   pm2 status                    # Check server status" -ForegroundColor White
Write-Host "   pm2 logs posting-server       # View server logs" -ForegroundColor White
Write-Host "   pm2 restart posting-server    # Restart server" -ForegroundColor White
Write-Host "   pm2 stop posting-server       # Stop server" -ForegroundColor White
Write-Host "   pm2 delete posting-server     # Remove server from PM2" -ForegroundColor White
Write-Host "   pm2 monit                     # Real-time monitoring" -ForegroundColor White
Write-Host ""

Write-Host "📊 Log Files:" -ForegroundColor Yellow
Write-Host "   - Combined logs: logs/posting-server.log" -ForegroundColor White
Write-Host "   - Error logs: logs/posting-server-error.log" -ForegroundColor White
Write-Host "   - Output logs: logs/posting-server-out.log" -ForegroundColor White
Write-Host ""

Write-Host "🚀 Your server is now running with PM2 auto-restart!" -ForegroundColor Green
Write-Host "💡 The server will automatically restart on crashes and start on boot." -ForegroundColor Blue
Write-Host ""

Write-Host "🔍 Current server status:" -ForegroundColor Cyan
pm2 status