#!/bin/bash

# Exit on error
set -e

# Function to clean up on error
cleanup() {
  if [ -d "monitor-tool" ]; then
    echo "❌ An error occurred. Cleaning up..."
    rm -rf monitor-tool
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

# Check and install Node.js if not present
if ! command_exists node; then
  echo "❌ Node.js is not installed."
  install_nodejs
fi

# Check if PM2 is installed, if not install it globally
if ! command_exists pm2; then
  echo "📦 Installing PM2 globally..."
  npm install -g pm2
fi

# Remove existing monitor-tool directory if it exists
if [ -d "monitor-tool" ]; then
  echo "🗑️  Removing existing monitor-tool directory..."
  rm -rf monitor-tool
fi

# Create app directory
mkdir -p monitor-tool && cd monitor-tool

# Add timestamp to prevent caching
TIMESTAMP=$(date +%s)

# Common headers for curl to prevent caching
CURL_HEADERS=(
  "Cache-Control: no-cache, no-store, must-revalidate"
  "Pragma: no-cache"
  "Expires: 0"
)

# Download server.js
echo "⬇️ Downloading server.js..."
curl -H "${CURL_HEADERS[0]}" -H "${CURL_HEADERS[1]}" -H "${CURL_HEADERS[2]}" \
     -o server.js "https://raw.githubusercontent.com/Foxiom/server-monitor-tool/main/server.js?t=$TIMESTAMP"

# Download package.json
echo "⬇️ Downloading package.json..."
curl -H "${CURL_HEADERS[0]}" -H "${CURL_HEADERS[1]}" -H "${CURL_HEADERS[2]}" \
     -o package.json "https://raw.githubusercontent.com/Foxiom/server-monitor-tool/main/package.json?t=$TIMESTAMP"

# Install dependencies
echo "📦 Installing dependencies..."
npm install

# Create logs directory if it doesn't exist
mkdir -p ../logs

# Set appropriate permissions
echo "🔒 Setting up permissions..."
# Set directory permissions
chmod 755 ../logs
chmod 755 .
# Set file permissions
chmod 644 server.js
chmod 644 package.json
chmod 644 package-lock.json 2>/dev/null || true
# Set node_modules permissions
chmod -R 755 node_modules

# Start the server using PM2
echo "🚀 Starting server with PM2..."
pm2 start server.js --name "server-monitor" --log ../logs/server.log

# Save PM2 process list
pm2 save

# Setup PM2 to start on system boot
echo "🔧 Setting up PM2 to start on system boot..."
pm2 startup

echo "✅ Server started and configured to run on system boot!"
echo "To manage the server, use these PM2 commands:"
echo "  - pm2 status          # Check server status"
echo "  - pm2 logs           # View logs"
echo "  - pm2 stop all       # Stop the server"
echo "  - pm2 restart all    # Restart the server"
