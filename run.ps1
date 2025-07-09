# Exit on error
$ErrorActionPreference = "Stop"

# Function to clean up on error
function Cleanup {
    if (Test-Path "posting_server") {
        Write-Host "❌ An error occurred. Cleaning up..."
        Remove-Item -Path "posting_server" -Recurse -Force
    }
    if ($null -ne $env:TEMP_DIR -and (Test-Path $env:TEMP_DIR)) {
        Remove-Item -Path $env:TEMP_DIR -Recurse -Force
    }
    exit 1
}

# Set up error handling
trap { 
    Write-Host "❌ Error: $_"
    Cleanup
}

# Function to check if a command exists
function Command-Exists {
    param ($Command)
    return [bool](Get-Command -Name $Command -ErrorAction SilentlyContinue)
}

# Function to install Node.js
function Install-NodeJs {
    Write-Host "📦 Installing Node.js..."
    winget install -e --id OpenJS.NodeJS.LTS --source winget
    # Refresh environment to include new Node.js path
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# Function to install Git
function Install-Git {
    Write-Host "📦 Installing Git..."
    winget install -e --id Git.Git --source winget
    # Refresh environment to include new Git path
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# Display header
Write-Host "=================================================="
Write-Host "Setting up Posting Server"
Write-Host "=================================================="

# Check and install Node.js if not present
if (-not (Command-Exists "node")) {
    Write-Host "❌ Node.js is not installed."
    Install-NodeJs
}
Write-Host "✅ Node.js is installed."

# Check and install Git if not present
if (-not (Command-Exists "git")) {
    Write-Host "❌ Git is not installed."
    Install-Git
}
Write-Host "✅ Git is installed."

# Check if PM2 is installed, if not install it globally
if (-not (Command-Exists "pm2")) {
    Write-Host "📦 Installing PM2 globally..."
    npm install -g pm2
}
Write-Host "✅ PM2 is installed."

# Remove existing posting_server directory if it exists
if (Test-Path "posting_server") {
    Write-Host "🗑️ Removing existing posting_server directory..."
    Remove-Item -Path "posting_server" -Recurse -Force
}

# Create logs directory if it doesn't exist
if (-not (Test-Path "logs")) {
    Write-Host "📁 Creating logs directory..."
    New-Item -ItemType Directory -Path "logs" | Out-Null
}

# Setup posting server
Write-Host "🔧 Setting up posting server..."

# Clone the repository to a temporary directory (shallow clone for efficiency)
Write-Host "⬇️ Downloading complete posting server from GitHub..."
$env:TEMP_DIR = Join-Path $env:TEMP "server-monitor-tool-$([guid]::NewGuid().ToString())"
git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git $env:TEMP_DIR

# Copy only the posting_server folder to the current location
Write-Host "📂 Copying posting_server folder..."
Copy-Item -Path "$env:TEMP_DIR\posting_server" -Destination "posting_server" -Recurse -Force

# Clean up temporary directory
Remove-Item -Path $env:TEMP_DIR -Recurse -Force
$env:TEMP_DIR = $null

# Navigate to posting_server directory
Set-Location -Path "posting_server"

# Install posting server dependencies
Write-Host "📦 Installing posting server dependencies..."
npm install

# Set permissions (Windows equivalent: grant full control to current user)
Write-Host "🔒 Setting up permissions..."
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
icacls . /grant "$($currentUser):F" /T | Out-Null
icacls ..\logs /grant "$($currentUser):F" /T | Out-Null

# Start the server using PM2
Write-Host "🚀 Starting posting server with PM2..."
pm2 start server.js --name "posting-server" --log ..\logs\posting-server.log

# Save PM2 process list
pm2 save

# Setup PM2 to start on system boot
Write-Host "🔧 Setting up PM2 to start on system boot..."
pm2 startup

Write-Host ""
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
Write-Host ""

# Pause to allow user to see the output
Read-Host -Prompt "Press Enter to exit"