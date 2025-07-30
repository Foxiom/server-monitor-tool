#!/bin/bash

# Exit on error
set -e

# Function to clean up on error
cleanup() {
  if [ -d "posting_server" ]; then
    echo "❌ An error occurred. Cleaning up..."
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

# Function to check Node.js version
check_nodejs_version() {
  # Required Node.js version for PM2
  local required_major=16
  
  if command_exists node; then
    local current_version=$(node -v | cut -d 'v' -f 2)
    local current_major=$(echo $current_version | cut -d '.' -f 1)
    
    if [[ $current_major -lt $required_major ]]; then
      echo "⚠️ Node.js version $current_version is too old. PM2 requires v${required_major}.0.0 or higher."
      return 1
    else
      echo "✅ Node.js version $current_version is compatible with PM2."
      return 0
    fi
  else
    echo "❌ Node.js is not installed."
    return 1
  fi
}

# Function to install Node.js
install_nodejs() {
  echo "📦 Installing Node.js..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    brew install node
  elif [[ -f /etc/debian_version ]]; then
    # Debian/Ubuntu
    echo "📦 Installing Node.js 18.x (LTS) via NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
  elif [[ -f /etc/redhat-release ]]; then
    # RHEL/CentOS
    echo "📦 Installing Node.js 18.x (LTS) via NodeSource..."
    curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
    sudo yum install -y nodejs
  else
    echo "❌ Unsupported operating system for automatic Node.js installation"
    echo "📋 Please manually install Node.js 16.x or higher from https://nodejs.org/"
    exit 1
  fi
  
  # Verify installation
  if ! command_exists node; then
    echo "❌ Failed to install Node.js. Please install manually."
    exit 1
  fi
  
  local installed_version=$(node -v | cut -d 'v' -f 2)
  echo "✅ Successfully installed Node.js v$installed_version"
}

# Function to install Git
install_git() {
  echo "📦 Installing Git..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    brew install git
  elif [[ -f /etc/debian_version ]]; then
    # Debian/Ubuntu
    sudo apt-get update
    sudo apt-get install -y git
  elif [[ -f /etc/redhat-release ]]; then
    # RHEL/CentOS
    sudo yum install -y git
  else
    echo "❌ Unsupported operating system for automatic Git installation"
    exit 1
  fi
}

# Check if Node.js is installed and has compatible version
if ! command_exists node || ! check_nodejs_version; then
  echo "🔄 Installing/upgrading Node.js to a compatible version..."
  install_nodejs
fi

# Check and install Git if not present
if ! command_exists git; then
  echo "❌ Git is not installed."
  install_git
fi

# Check if PM2 is installed, if not install it globally
if ! command_exists pm2; then
  echo "📦 Installing PM2 globally..."
  npm install -g pm2
fi

# Remove existing posting_server directory if it exists
if [ -d "posting_server" ]; then
  echo "🗑️  Removing existing posting_server directory..."
  rm -rf posting_server
fi

# Create logs directory if it doesn't exist
mkdir -p logs

# Setup posting server
echo "🔧 Setting up posting server..."

# Clone the repository to a temporary directory (shallow clone for efficiency)
echo "⬇️ Downloading complete posting server from GitHub..."
TEMP_DIR=$(mktemp -d)
git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git "$TEMP_DIR"

# Copy only the posting_server folder to our target location
cp -r "$TEMP_DIR/posting_server" .

# Clean up temporary directory
rm -rf "$TEMP_DIR"

# Navigate to posting_server directory
cd posting_server

# Install posting server dependencies
echo "📦 Installing posting server dependencies..."
npm install

# Set posting server permissions
echo "🔒 Setting up permissions..."
chmod 755 .
find . -type f -name "*.js" -exec chmod 644 {} \;
find . -type f -name "*.json" -exec chmod 644 {} \;
find . -type d -exec chmod 755 {} \;
chmod 755 ../logs

# Start the server using PM2 with exponential backoff restart
echo "🚀 Starting posting server with PM2..."
pm2 start server.js --name "posting-server" --log ../logs/posting-server.log --exp-backoff-restart-delay=100

# Save PM2 process list
echo "💾 Saving PM2 process list..."
pm2 save

# Setup PM2 to start on system boot
echo "🔧 Setting up PM2 to start on system boot..."
pm2 startup | tee /tmp/pm2_startup_output.txt

# Check if pm2 startup was successful
if grep -q "sudo systemctl enable pm2" /tmp/pm2_startup_output.txt; then
  echo "✅ PM2 startup script configured successfully."
else
  echo "⚠️ Warning: PM2 startup script may not have been configured correctly. Please check manually with 'pm2 startup'."
fi
rm -f /tmp/pm2_startup_output.txt

# Verify if the server is running
echo "🔍 Verifying server status..."
if pm2 list | grep -q "posting-server.*online"; then
  echo "✅ Posting server is running!"
else
  echo "⚠️ Posting server is not running. Attempting to restart..."
  pm2 restart posting-server
  if pm2 list | grep -q "posting-server.*online"; then
    echo "✅ Posting server restarted successfully!"
  else
    echo "❌ Failed to start posting server. Please check logs with 'pm2 logs posting-server'."
    exit 1
  fi
fi

# Optional: Install PM2 log rotation module
echo "🔧 Setting up PM2 log rotation..."
pm2 install pm2-logrotate
pm2 set pm2-logrotate:max_size 10M
pm2 set pm2-logrotate:compress true

echo "✅ Server started and configured to run on system boot!"
echo "📁 Downloaded complete posting server with all folders:"
echo "   - config/"
echo "   - models/"
echo "   - utils/"
echo "   - server.js"
echo "   - package.json"
echo ""
echo "To manage the server, use these PM2 commands:"
echo "  - pm2 status              # Check server status"
echo "  - pm2 logs                # View all logs"
echo "  - pm2 logs posting-server # View posting server logs"
echo "  - pm2 stop all           # Stop the server"
echo "  - pm2 restart all        # Restart the server"
echo "  - pm2 delete posting-server # Remove the server from PM2"