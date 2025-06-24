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

# Function to install Node.js
install_nodejs() {
  echo "📦 Installing Node.js..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    brew install node
  elif [[ -f /etc/debian_version ]]; then
    # Debian/Ubuntu
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
  elif [[ -f /etc/redhat-release ]]; then
    # RHEL/CentOS
    curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
    sudo yum install -y nodejs
  else
    echo "❌ Unsupported operating system for automatic Node.js installation"
    exit 1
  fi
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

# Check and install Node.js if not present
if ! command_exists node; then
  echo "❌ Node.js is not installed."
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

# Start the server using PM2
echo "🚀 Starting posting server with PM2..."
pm2 start server.js --name "posting-server" --log ../logs/posting-server.log

# Save PM2 process list
pm2 save

# Setup PM2 to start on system boot
echo "🔧 Setting up PM2 to start on system boot..."
pm2 startup

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