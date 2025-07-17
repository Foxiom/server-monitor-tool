#!/bin/bash

# Simplified PM2 Setup Script for Linux/macOS
# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    printf "${2}${1}${NC}\n"
}

# Function to clean up on error
cleanup() {
    if [ -d "posting_server" ]; then
        print_color "❌ An error occurred. Cleaning up..." $RED
        rm -rf posting_server
    fi
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    exit 1
}

# Set up error handling
trap cleanup ERR

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to install Node.js
install_nodejs() {
    print_color "📦 Installing Node.js..." $YELLOW
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command_exists brew; then
            brew install node
        else
            print_color "❌ Please install Homebrew first or install Node.js manually" $RED
            exit 1
        fi
    elif [[ -f /etc/debian_version ]]; then
        # Debian/Ubuntu
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt-get install -y nodejs
    elif [[ -f /etc/redhat-release ]]; then
        # RHEL/CentOS/AlmaLinux
        curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
        sudo yum install -y nodejs
    else
        print_color "❌ Unsupported operating system. Please install Node.js manually" $RED
        exit 1
    fi
}

# Function to install Git
install_git() {
    print_color "📦 Installing Git..." $YELLOW
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command_exists brew; then
            brew install git
        else
            print_color "❌ Please install Homebrew first or install Git manually" $RED
            exit 1
        fi
    elif [[ -f /etc/debian_version ]]; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y git
    elif [[ -f /etc/redhat-release ]]; then
        # RHEL/CentOS/AlmaLinux
        sudo yum install -y git
    else
        print_color "❌ Unsupported operating system. Please install Git manually" $RED
        exit 1
    fi
}

print_color "🚀 Starting Simplified PM2 Posting Server Setup..." $CYAN

# Check and install Node.js if not present
if ! command_exists node; then
    print_color "❌ Node.js is not installed." $RED
    install_nodejs
else
    print_color "✅ Node.js is installed: $(node --version)" $GREEN
fi

# Check and install Git if not present
if ! command_exists git; then
    print_color "❌ Git is not installed." $RED
    install_git
else
    print_color "✅ Git is installed: $(git --version)" $GREEN
fi

# Install PM2 if not present
if ! command_exists pm2; then
    print_color "📦 Installing PM2 globally..." $YELLOW
    npm install -g pm2
else
    print_color "✅ PM2 is installed: $(pm2 --version)" $GREEN
fi

# Stop any existing posting-server processes
print_color "🛑 Stopping any existing posting-server processes..." $YELLOW
pm2 delete posting-server 2>/dev/null || true

# Remove existing posting_server directory if it exists
if [ -d "posting_server" ]; then
    print_color "🗑️  Removing existing posting_server directory..." $YELLOW
    rm -rf posting_server
fi

# Create logs directory
mkdir -p logs

# Setup posting server
print_color "🔧 Setting up posting server..." $BLUE

# Clone the repository to a temporary directory (shallow clone for efficiency)
print_color "⬇️ Downloading complete posting server from GitHub..." $CYAN
TEMP_DIR=$(mktemp -d)
git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git "$TEMP_DIR"

# Copy only the posting_server folder to our target location
cp -r "$TEMP_DIR/posting_server" .

# Clean up temporary directory
rm -rf "$TEMP_DIR"

# Navigate to posting_server directory and install dependencies
cd posting_server
print_color "📦 Installing posting server dependencies..." $YELLOW
npm install
cd ..

# Set posting server permissions
print_color "🔒 Setting up permissions..." $YELLOW
chmod -R 755 posting_server
chmod 755 logs

# Start the server using PM2 with simple configuration
print_color "🚀 Starting posting server with PM2..." $GREEN
pm2 start posting_server/server.js \
    --name "posting-server" \
    --log "logs/posting-server.log" \
    --error "logs/posting-server-error.log" \
    --out "logs/posting-server-out.log" \
    --max-memory-restart 500M \
    --time \
    --restart-delay 2000

# Save PM2 process list
print_color "💾 Saving PM2 process list..." $YELLOW
pm2 save

# Setup PM2 to start on system boot
print_color "🔧 Setting up PM2 startup..." $YELLOW
pm2 startup

print_color "" $NC
print_color "🎉 ==================================" $GREEN
print_color "✅ SERVER INSTALLATION COMPLETE!" $GREEN
print_color "==================================" $GREEN
print_color "" $NC

print_color "📁 Downloaded complete posting server with all folders:" $CYAN
print_color "   - config/" $WHITE
print_color "   - models/" $WHITE
print_color "   - utils/" $WHITE
print_color "   - server.js" $WHITE
print_color "   - package.json" $WHITE
print_color "" $NC

print_color "🔧 Auto-restart features:" $YELLOW
print_color "   ✅ PM2 automatic restarts on crashes" $GREEN
print_color "   ✅ Memory-based restarts (500MB limit)" $GREEN
print_color "   ✅ Boot startup configured" $GREEN
print_color "   ✅ Process monitoring enabled" $GREEN
print_color "" $NC

print_color "📋 Management Commands:" $YELLOW
print_color "   pm2 status                    # Check server status" $WHITE
print_color "   pm2 logs posting-server       # View server logs" $WHITE
print_color "   pm2 restart posting-server    # Restart server" $WHITE
print_color "   pm2 stop posting-server       # Stop server" $WHITE
print_color "   pm2 delete posting-server     # Remove server from PM2" $WHITE
print_color "   pm2 monit                     # Real-time monitoring" $WHITE
print_color "" $NC

print_color "📊 Log Files:" $YELLOW
print_color "   - Combined logs: logs/posting-server.log" $WHITE
print_color "   - Error logs: logs/posting-server-error.log" $WHITE
print_color "   - Output logs: logs/posting-server-out.log" $WHITE
print_color "" $NC

print_color "🚀 Your server is now running with PM2 auto-restart!" $GREEN
print_color "💡 The server will automatically restart on crashes and start on boot." $BLUE
print_color "" $NC

print_color "🔍 Current server status:" $CYAN
pm2 status