# PowerShell Script for Setting up Posting Server
# Exit on error
$ErrorActionPreference = "Stop"

# Function to clean up on error
function Cleanup {
    if (Test-Path "posting_server") {
        Write-Host "X An error occurred. Cleaning up..." -ForegroundColor Red
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
    Write-Host "Installing Chocolatey..." -ForegroundColor Yellow
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
    Write-Host "Installing Node.js..." -ForegroundColor Yellow
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
    Write-Host "Installing Git..." -ForegroundColor Yellow
    if (!(Test-Command "choco")) {
        Install-Chocolatey
    }else{
        Write-Host "choco installed" -ForegroundColor Yellow
    }
    choco install git -y
    
    # Refresh environment variables
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# Check and install Node.js if not present
if (!(Test-Command "node")) {
    Write-Host "Node.js is not installed." -ForegroundColor Red
    Install-NodeJS
}

# Check and install Git if not present
if (!(Test-Command "git")) {
    Write-Host "Git is not installed." -ForegroundColor Red
    Install-Git
}

# Check if PM2 is installed, if not install it globally
if (!(Test-Command "pm2")) {
    Write-Host "Installing PM2 globally..." -ForegroundColor Yellow
    npm install -g pm2
}

# Remove existing posting_server directory if it exists
if (Test-Path "posting_server") {
    Write-Host "Removing existing posting_server directory..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force "posting_server"
}

# Create logs directory if it doesn't exist
if (!(Test-Path "logs")) {
    New-Item -ItemType Directory -Path "logs" | Out-Null
}

# Setup posting server
Write-Host "Setting up posting server..." -ForegroundColor Green

# Clone the repository to a temporary directory (shallow clone for efficiency)
Write-Host "Downloading complete posting server from GitHub..." -ForegroundColor Cyan
$TempDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ }
git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git $TempDir.FullName

# Copy only the posting_server folder to our target location
Copy-Item -Recurse -Path (Join-Path $TempDir.FullName "posting_server") -Destination "."

# Clean up temporary directory
Remove-Item -Recurse -Force $TempDir

# Navigate to posting_server directory
Set-Location "posting_server"

# Install posting server dependencies
Write-Host "Installing posting server dependencies..." -ForegroundColor Yellow
npm install

# Set posting server permissions (Windows equivalent)
Write-Host "Setting up permissions..." -ForegroundColor Yellow
Get-ChildItem -Recurse | ForEach-Object {
    if ($_.PSIsContainer) {
        # Directory - no special action needed on Windows
    } else {
        # File - ensure it's not read-only
        $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
    }
}

# Start the server using PM2
Write-Host "Starting posting server with PM2..." -ForegroundColor Green
pm2 start server.js --name "posting-server" --log "../logs/posting-server.log"

# Save PM2 process list
pm2 save

# Setup PM2 to start on system boot
Write-Host "Setting up PM2 to start on system boot..." -ForegroundColor Yellow
pm2 startup

Write-Host "Server started and configured to run on system boot!" -ForegroundColor Green
Write-Host "Downloaded complete posting server with all folders:" -ForegroundColor Cyan
Write-Host "   - config/" -ForegroundColor White
Write-Host "   - models/" -ForegroundColor White
Write-Host "   - utils/" -ForegroundColor White
Write-Host "   - server.js" -ForegroundColor White
Write-Host "   - package.json" -ForegroundColor White
Write-Host ""
Write-Host "To manage the server, use these PM2 commands:" -ForegroundColor Yellow
Write-Host "  - pm2 status              # Check server status" -ForegroundColor White
Write-Host "  - pm2 logs                # View all logs" -ForegroundColor White
Write-Host "  - pm2 logs posting-server # View posting server logs" -ForegroundColor White
Write-Host "  - pm2 stop all           # Stop the server" -ForegroundColor White
Write-Host "  - pm2 restart all        # Restart the server" -ForegroundColor White