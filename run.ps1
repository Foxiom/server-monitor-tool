# Exit on error
$ErrorActionPreference = "Stop"

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

# Function to install Node.js
function Install-NodeJs {
    Write-Host "📦 Installing Node.js..."
    if (-not (Command-Exists winget)) {
        Write-Host "❌ Winget is required to install Node.js. Please install winget first."
        exit 1
    }
    winget install OpenJS.NodeJS --version 18
}

# Function to install Git
function Install-Git {
    Write-Host "📦 Installing Git..."
    if (-not (Command-Exists winget)) {
        Write-Host "❌ Winget is required to install Git. Please install winget first."
        exit 1
    }
    winget install Git.Git
}

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

# Check if PM2 is installed, if not install it globally
if (-not (Command-Exists pm2)) {
    Write-Host "📦 Installing PM2 globally..."
    npm install -g pm2
}

# Remove existing posting_server directory if it exists
if (Test-Path "posting_server") {
    Write-Host "🗑️  Removing existing posting_server directory..."
    Remove-Item -Recurse -Force "posting_server"
}

# Create logs directory if it doesn't exist
New-Item -ItemType Directory -Force -Path "logs"

# Setup posting server
Write-Host "🔧 Setting up posting server..."

# Clone the repository to a temporary directory
Write-Host "⬇️ Downloading complete posting server from GitHub..."
$env:TEMP_DIR = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
New-Item -ItemType Directory -Path $env:TEMP_DIR
git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git $env:TEMP_DIR

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
icacls "." /grant "Everyone:(OI)(CI)F"
icacls *.js /grant "Everyone:R"
icacls *.json /grant "Everyone:R"
icacls ".." /grant "Everyone:(OI)(CI)F"
icacls "..\logs" /grant "Everyone:(OI)(CI)F"

# Install PM2 as a Windows service using pm2-installer
Write-Host "🔧 Setting up PM2 as a Windows service..."
$pm2InstallerDir = "pm2-installer"
if (Test-Path $pm2InstallerDir) {
    Remove-Item -Recurse -Force $pm2InstallerDir
}
Write-Host "⬇️ Downloading pm2-installer..."
git clone --depth 1 https://github.com/jessety/pm2-installer.git $pm2InstallerDir
Set-Location $pm2InstallerDir
npm run configure
npm run configure-policy
npm run setup
Set-Location ..

# Start the server using PM2 with exponential backoff restart
Write-Host "🚀 Starting posting server with PM2..."
pm2 start server.js --name "posting-server" --log ..\logs\posting-server.log --exp-backoff-restart-delay=100

# Save PM2 process list
Write-Host "💾 Saving PM2 process list..."
pm2 save

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
pm2 set pm2-logrotate:compress $true

Write-Host "✅ Server started and configured to run on system boot!"
Write-Host "📁 Downloaded complete posting server with all folders:"
Write-Host "   - config/"
Write-Host "   - models/"
Write-Host "   - utils/"
Write-Host "   - server.js"
Write-Host "   - package.json"
Write-Host ""
Write-Host "To manage the server, use these PM2 commands:"
Write-Host "  - pm2 status              # Check server status"
Write-Host "  - pm2 logs                # View all logs"
Write-Host "  - pm2 logs posting-server # View posting server logs"
Write-Host "  - pm2 stop all           # Stop the server"
Write-Host "  - pm2 restart all        # Restart the server"
Write-Host "  - pm2 delete posting-server # Remove the server from PM2"