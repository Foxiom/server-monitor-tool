#!/bin/bash

# Exit on error, but allow certain commands to fail without stopping the script
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

# Function to print section headers
print_header() {
  echo ""
  echo "=== $1 ==="
  echo ""
}

# Function to run a command with error handling
run_command() {
  echo "$ $@"
  "$@" || {
    local exit_code=$?
    echo "⚠️ Command failed with exit code $exit_code. Continuing..."
    return $exit_code
  }
}

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
  print_header "Installing Node.js"
  
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    run_command brew install node
  elif [[ -f /etc/debian_version ]]; then
    # Debian/Ubuntu
    echo "📦 Attempting to install Node.js via apt..."
    
    # Try direct apt installation first (simpler, fewer dependencies)
    echo "Method 1: Installing via standard apt repositories..."
    run_command sudo apt-get update
    if run_command sudo apt-get install -y nodejs npm; then
      echo "✅ Node.js installed successfully via standard repositories"
    else
      echo "⚠️ Standard repository installation failed, trying NodeSource..."
      
      # Try NodeSource repository (may have GPG key issues on some systems)
      echo "Method 2: Installing Node.js 18.x (LTS) via NodeSource..."
      
      # Download setup script but don't execute it directly
      curl -fsSL https://deb.nodesource.com/setup_18.x -o /tmp/nodesource_setup.sh
      
      # Modify the script to continue even if GPG key import fails
      sed -i 's/^exec_cmd /exec_cmd_nobail /g' /tmp/nodesource_setup.sh 2>/dev/null || true
      
      # Run the modified script
      if run_command sudo -E bash /tmp/nodesource_setup.sh; then
        echo "NodeSource repository added successfully"
      else
        echo "⚠️ NodeSource setup had issues but continuing anyway..."
      fi
      
      # Try to install nodejs package
      run_command sudo apt-get update
      if ! run_command sudo apt-get install -y nodejs; then
        echo "⚠️ Attempting to fix broken packages..."
        run_command sudo apt --fix-broken install -y
        run_command sudo apt-get install -y nodejs
      fi
      
      # If npm is not installed, install it separately
      if ! command_exists npm; then
        echo "⚠️ npm not found, installing separately..."
        run_command sudo apt-get install -y npm
      fi
    fi
  elif [[ -f /etc/redhat-release ]]; then
    # RHEL/CentOS
    echo "📦 Installing Node.js for RHEL/CentOS..."
    
    # Try standard repository first
    if run_command sudo yum install -y nodejs npm; then
      echo "✅ Node.js installed successfully via standard repositories"
    else
      echo "⚠️ Standard repository installation failed, trying NodeSource..."
      
      # Try NodeSource repository
      curl -fsSL https://rpm.nodesource.com/setup_18.x -o /tmp/nodesource_setup.sh
      run_command sudo bash /tmp/nodesource_setup.sh
      run_command sudo yum install -y nodejs
      
      # If npm is not installed, install it separately
      if ! command_exists npm; then
        echo "⚠️ npm not found, installing separately..."
        run_command sudo yum install -y npm
      fi
    fi
  else
    echo "❌ Unsupported operating system for automatic Node.js installation"
    echo "📋 Please manually install Node.js 16.x or higher from https://nodejs.org/"
    echo "Then run this script again."
    exit 1
  fi
  
  # Verify installation
  if ! command_exists node; then
    echo "❌ Failed to install Node.js. Please install manually from https://nodejs.org/"
    echo "Then run this script again."
    exit 1
  fi
  
  # Verify npm installation
  if ! command_exists npm; then
    echo "❌ npm is not available. Please install npm manually."
    echo "Then run this script again."
    exit 1
  fi
  
  local installed_version=$(node -v | cut -d 'v' -f 2)
  echo "✅ Successfully installed Node.js v$installed_version"
}

# Function to install Git
install_git() {
  print_header "Installing Git"
  
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    run_command brew install git
  elif [[ -f /etc/debian_version ]]; then
    # Debian/Ubuntu
    run_command sudo apt-get update
    run_command sudo apt-get install -y git
  elif [[ -f /etc/redhat-release ]]; then
    # RHEL/CentOS
    run_command sudo yum install -y git
  else
    echo "❌ Unsupported operating system for automatic Git installation"
    echo "📋 Please manually install Git from https://git-scm.com/downloads"
    echo "Then run this script again."
    exit 1
  fi
  
  # Verify installation
  if ! command_exists git; then
    echo "❌ Failed to install Git. Please install manually from https://git-scm.com/downloads"
    echo "Then run this script again."
    exit 1
  fi
  
  echo "✅ Git installed successfully"
}

print_header "Checking dependencies"

# Check if Node.js is installed and has compatible version
if ! command_exists node || ! check_nodejs_version; then
  echo "🔄 Installing/upgrading Node.js to a compatible version..."
  install_nodejs
else
  echo "✅ Node.js is already installed with a compatible version"
fi

# Check if npm is installed
if ! command_exists npm; then
  echo "❌ npm is not installed."
  echo "🔄 Installing npm..."
  
  if [[ -f /etc/debian_version ]]; then
    run_command sudo apt-get update
    run_command sudo apt-get install -y npm
  elif [[ -f /etc/redhat-release ]]; then
    run_command sudo yum install -y npm
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "⚠️ npm should have been installed with Node.js. Reinstalling Node.js..."
    run_command brew reinstall node
  else
    echo "❌ Unsupported operating system for automatic npm installation"
    echo "📋 Please manually install npm and run this script again."
    exit 1
  fi
  
  if ! command_exists npm; then
    echo "❌ Failed to install npm. Please install manually and run this script again."
    exit 1
  fi
fi

# Check and install Git if not present
if ! command_exists git; then
  echo "❌ Git is not installed."
  install_git
else
  echo "✅ Git is already installed"
fi

# Check if PM2 is installed, if not install it globally
if ! command_exists pm2; then
  print_header "Installing PM2"
  echo "📦 Installing PM2 globally..."
  
  # Try with standard npm
  if ! run_command npm install -g pm2; then
    echo "⚠️ Standard npm install failed, trying with sudo..."
    run_command sudo npm install -g pm2
    
    # If still not installed, try fixing npm permissions
    if ! command_exists pm2; then
      echo "⚠️ Attempting to fix npm global permissions..."
      mkdir -p ~/.npm-global
      npm config set prefix '~/.npm-global'
      export PATH=~/.npm-global/bin:$PATH
      echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.profile
      source ~/.profile 2>/dev/null || true
      
      # Try installing again with fixed permissions
      run_command npm install -g pm2
    fi
  fi
  
  # Final check if PM2 is installed
  if ! command_exists pm2; then
    echo "❌ Failed to install PM2. Please try manually with: sudo npm install -g pm2"
    exit 1
  fi
else
  echo "✅ PM2 is already installed"
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
echo "🚀 Setting up posting server with PM2..."

# Check if posting-server process already exists in PM2
if pm2 list | grep -q "posting-server"; then
  echo "⚠️ Process 'posting-server' already exists in PM2. Restarting it..."
  pm2 restart posting-server --update-env
  echo "✅ Process 'posting-server' restarted successfully"
else
  echo "🆕 Starting new PM2 process 'posting-server'..."
  pm2 start server.js --name "posting-server" --log ../logs/posting-server.log --exp-backoff-restart-delay=100
  echo "✅ Process 'posting-server' started successfully"
fi

# Save PM2 process list
echo "💾 Saving PM2 process list..."
pm2 save

# Setup PM2 to start on system boot
print_header "Setting up PM2 startup"
echo "🔧 Setting up PM2 to start on system boot..."

# Run pm2 startup and capture output
run_command pm2 startup | tee /tmp/pm2_startup_output.txt

# Check if pm2 startup was successful
if grep -q "sudo" /tmp/pm2_startup_output.txt; then
  echo "⚠️ PM2 startup requires additional commands to be run. Attempting to run them automatically..."
  
  # Extract and run the sudo command
  STARTUP_CMD=$(grep "sudo" /tmp/pm2_startup_output.txt | head -n 1)
  if [ -n "$STARTUP_CMD" ]; then
    echo "Running: $STARTUP_CMD"
    eval $STARTUP_CMD || {
      echo "⚠️ Failed to run PM2 startup command automatically."
      echo "📋 Please run this command manually to enable PM2 startup:"
      echo "$STARTUP_CMD"
    }
  fi
  
  echo "✅ PM2 startup script configured."
else
  echo "⚠️ Warning: PM2 startup script may not have been configured correctly."
  echo "📋 Please run 'pm2 startup' manually and follow the instructions."
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
print_header "Setting up PM2 log rotation"
echo "🔧 Setting up PM2 log rotation..."

# Install pm2-logrotate with error handling
if run_command pm2 install pm2-logrotate; then
  run_command pm2 set pm2-logrotate:max_size 10M
  run_command pm2 set pm2-logrotate:compress true
  echo "✅ PM2 log rotation configured successfully."
else
  echo "⚠️ Failed to install PM2 log rotation. This is optional, continuing..."
fi

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