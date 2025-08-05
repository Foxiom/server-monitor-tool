#!/bin/bash

# Enhanced cross-platform server setup script
# Compatible with all major Linux distributions
# Version 2.1 - Added NVM support for Node.js installation
# This version uses NVM to avoid dependency conflicts

# Exit on error, but allow certain commands to fail without stopping the script
set -e

# Global variables
REQUIRED_NODE_MAJOR=18
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR=""
LOCK_FILE="/tmp/server_setup.lock"
LOG_FILE="/tmp/server_setup.log"
NVM_VERSION="v0.39.7"  # Latest stable NVM version

# Function to log messages
log_message() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to clean up on error or exit
cleanup() {
  local exit_code=$?
  log_message "INFO" "Starting cleanup process..."
  
  if [ -f "$LOCK_FILE" ]; then
    rm -f "$LOCK_FILE"
  fi
  
  if [ -d "posting_server" ] && [ $exit_code -ne 0 ]; then
    log_message "WARN" "Cleaning up failed installation..."
    rm -rf posting_server
  fi
  
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
  
  if [ $exit_code -ne 0 ]; then
    log_message "ERROR" "Script failed with exit code $exit_code"
    echo "❌ Installation failed. Check log file: $LOG_FILE"
    exit $exit_code
  fi
}

# Set up cleanup on exit and error
trap cleanup EXIT ERR INT TERM

# Function to create lock file
create_lock() {
  if [ -f "$LOCK_FILE" ]; then
    local pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "❌ Another instance of this script is already running (PID: $pid)"
      exit 1
    else
      echo "🗑️ Removing stale lock file"
      rm -f "$LOCK_FILE"
    fi
  fi
  echo $$ > "$LOCK_FILE"
}

# Function to print section headers
print_header() {
  echo ""
  echo "============================================"
  echo "=== $1"
  echo "============================================"
  echo ""
  log_message "INFO" "Starting: $1"
}

# Function to run a command with error handling
run_command() {
  log_message "DEBUG" "Executing: $*"
  echo "$ $*"
  if "$@"; then
    log_message "DEBUG" "Command succeeded: $*"
    return 0
  else
    local exit_code=$?
    log_message "ERROR" "Command failed with exit code $exit_code: $*"
    echo "⚠️ Command failed with exit code $exit_code: $*"
    return $exit_code
  fi
}

# Function to run a command and continue on failure
run_command_continue() {
  log_message "DEBUG" "Executing (continue on fail): $*"
  echo "$ $*"
  if "$@"; then
    log_message "DEBUG" "Command succeeded: $*"
    return 0
  else
    local exit_code=$?
    log_message "WARN" "Command failed with exit code $exit_code (continuing...): $*"
    echo "⚠️ Command failed with exit code $exit_code (continuing...): $*"
    return $exit_code
  fi
}

# Function to check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# Function to detect the Linux distribution
detect_distro() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macos"
  elif [ -f /etc/os-release ]; then
    # Use ID from os-release for better detection
    local distro=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    case "$distro" in
      ubuntu|debian|linuxmint|pop|elementary)
        echo "debian"
        ;;
      fedora|rhel|centos|rocky|almalinux|ol)
        echo "redhat"
        ;;
      opensuse*|sles)
        echo "suse"
        ;;
      arch|manjaro|endeavouros)
        echo "arch"
        ;;
      alpine)
        echo "alpine"
        ;;
      *)
        # Fallback to checking specific files
        if [ -f /etc/debian_version ]; then
          echo "debian"
        elif [ -f /etc/redhat-release ]; then
          echo "redhat"
        elif [ -f /etc/alpine-release ]; then
          echo "alpine"
        else
          echo "unknown"
        fi
        ;;
    esac
  else
    echo "unknown"
  fi
}

# Enhanced function to resolve package manager locks
resolve_package_lock() {
  local distro="$1"
  local max_attempts=3
  local attempt=1
  
  while [ $attempt -le $max_attempts ]; do
    log_message "INFO" "Attempt $attempt/$max_attempts to resolve package manager locks"
    
    case "$distro" in
      debian)
        # Kill any hanging processes
        sudo pkill -f "apt-get|apt|aptd|dpkg|unattended-upgrade" 2>/dev/null || true
        sleep 3
        
        # Remove lock files
        sudo rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
        sudo rm -f /var/lib/dpkg/lock 2>/dev/null || true
        sudo rm -f /var/lib/apt/lists/lock 2>/dev/null || true
        sudo rm -f /var/cache/apt/archives/lock 2>/dev/null || true
        
        # Fix interrupted installations
        sudo dpkg --configure -a 2>/dev/null || true
        
        # Check if locks are clear
        if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && \
           ! fuser /var/lib/dpkg/lock >/dev/null 2>&1 && \
           ! fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
          log_message "INFO" "Package manager locks resolved"
          return 0
        fi
        ;;
      redhat)
        sudo pkill -f "yum|dnf" 2>/dev/null || true
        sleep 3
        
        if ! pgrep -f "yum|dnf" >/dev/null 2>&1; then
          log_message "INFO" "Package manager locks resolved"
          return 0
        fi
        ;;
    esac
    
    if [ $attempt -eq $max_attempts ]; then
      log_message "ERROR" "Failed to resolve package manager locks after $max_attempts attempts"
      echo "❌ Unable to resolve package manager locks. Please:"
      echo "   1. Reboot the system, or"
      echo "   2. Manually stop any package manager processes"
      return 1
    fi
    
    attempt=$((attempt + 1))
    sleep 10
  done
}

# Function to update package repositories with retry logic
update_repositories() {
  local distro="$1"
  local max_retries=3
  local retry=1
  
  print_header "Updating Package Repositories"
  
  # Resolve any existing locks first
  if ! resolve_package_lock "$distro"; then
    return 1
  fi
  
  while [ $retry -le $max_retries ]; do
    log_message "INFO" "Package repository update attempt $retry/$max_retries"
    
    case "$distro" in
      debian)
        if run_command_continue sudo apt-get clean && \
           run_command sudo apt-get update; then
          log_message "INFO" "Package repositories updated successfully"
          return 0
        fi
        ;;
      redhat)
        if command_exists dnf; then
          if run_command_continue sudo dnf clean all && \
             run_command sudo dnf makecache; then
            log_message "INFO" "Package repositories updated successfully"
            return 0
          fi
        else
          if run_command_continue sudo yum clean all && \
             run_command sudo yum makecache; then
            log_message "INFO" "Package repositories updated successfully"
            return 0
          fi
        fi
        ;;
      suse)
        if run_command sudo zypper refresh; then
          return 0
        fi
        ;;
      arch)
        if run_command sudo pacman -Sy; then
          return 0
        fi
        ;;
      alpine)
        if run_command sudo apk update; then
          return 0
        fi
        ;;
    esac
    
    if [ $retry -eq $max_retries ]; then
      log_message "ERROR" "Failed to update package repositories after $max_retries attempts"
      echo "⚠️ Package repository update failed. Continuing anyway..."
      return 0  # Don't fail the entire script
    fi
    
    retry=$((retry + 1))
    sleep 5
  done
}

# Function to source NVM
source_nvm() {
  # Source nvm if available
  if [ -s "$HOME/.nvm/nvm.sh" ]; then
    log_message "INFO" "Sourcing NVM from ~/.nvm/nvm.sh"
    source "$HOME/.nvm/nvm.sh"
  elif [ -s "/usr/local/nvm/nvm.sh" ]; then
    log_message "INFO" "Sourcing NVM from /usr/local/nvm/nvm.sh"
    source "/usr/local/nvm/nvm.sh"
  fi
  
  # Also try to source bash completion
  if [ -s "$HOME/.nvm/bash_completion" ]; then
    source "$HOME/.nvm/bash_completion"
  fi
  
  # Export NVM_DIR if not set
  if [ -z "$NVM_DIR" ]; then
    if [ -d "$HOME/.nvm" ]; then
      export NVM_DIR="$HOME/.nvm"
    fi
  fi
}

# Function to install NVM
install_nvm() {
  print_header "Installing NVM (Node Version Manager)"
  
  log_message "INFO" "Installing NVM version $NVM_VERSION"
  echo "📦 Installing NVM (Node Version Manager) $NVM_VERSION..."
  
  # Remove existing NVM installation if it exists
  if [ -d "$HOME/.nvm" ]; then
    log_message "INFO" "Removing existing NVM installation"
    echo "🗑️ Removing existing NVM installation..."
    rm -rf "$HOME/.nvm"
  fi
  
  # Install NVM using the official install script
  if curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" | bash; then
    log_message "INFO" "NVM installation script completed"
    echo "✅ NVM installation script completed"
  else
    log_message "ERROR" "Failed to install NVM"
    echo "❌ Failed to install NVM"
    exit 1
  fi
  
  # Source NVM immediately
  export NVM_DIR="$HOME/.nvm"
  source_nvm
  
  # Verify NVM installation
  if command_exists nvm; then
    local nvm_version=$(nvm --version)
    log_message "INFO" "NVM $nvm_version installed successfully"
    echo "✅ NVM $nvm_version installed successfully"
  else
    log_message "ERROR" "NVM installation verification failed"
    echo "❌ NVM installation verification failed"
    exit 1
  fi
}

# Function to check Node.js version
check_nodejs_version() {
  if command_exists node; then
    local current_version=$(node -v | cut -d 'v' -f 2)
    local current_major=$(echo $current_version | cut -d '.' -f 1)
    
    if [[ $current_major -lt $REQUIRED_NODE_MAJOR ]]; then
      log_message "WARN" "Node.js version $current_version is too old. Required: v${REQUIRED_NODE_MAJOR}.0.0+"
      echo "⚠️ Node.js version $current_version is too old. Required: v${REQUIRED_NODE_MAJOR}.0.0 or higher."
      return 1
    else
      log_message "INFO" "Node.js version $current_version is compatible"
      echo "✅ Node.js version $current_version is compatible."
      return 0
    fi
  else
    log_message "WARN" "Node.js is not installed"
    echo "❌ Node.js is not installed."
    return 1
  fi
}

# Function to install Node.js using NVM
install_nodejs_nvm() {
  print_header "Installing Node.js ${REQUIRED_NODE_MAJOR}.x using NVM"
  
  # Make sure NVM is sourced
  source_nvm
  
  # Verify NVM is available
  if ! command_exists nvm; then
    log_message "ERROR" "NVM is not available"
    echo "❌ NVM is not available"
    exit 1
  fi
  
  log_message "INFO" "Installing Node.js ${REQUIRED_NODE_MAJOR}.x using NVM"
  echo "📦 Installing Node.js ${REQUIRED_NODE_MAJOR}.x using NVM..."
  
  # Install the latest LTS version of the required major version
  if nvm install ${REQUIRED_NODE_MAJOR} --lts; then
    log_message "INFO" "Node.js installation completed"
    echo "✅ Node.js installation completed"
  else
    log_message "ERROR" "Failed to install Node.js with NVM"
    echo "❌ Failed to install Node.js with NVM"
    exit 1
  fi
  
  # Use the installed version
  if nvm use ${REQUIRED_NODE_MAJOR}; then
    log_message "INFO" "Switched to Node.js ${REQUIRED_NODE_MAJOR}.x"
    echo "✅ Switched to Node.js ${REQUIRED_NODE_MAJOR}.x"
  else
    log_message "ERROR" "Failed to switch to Node.js ${REQUIRED_NODE_MAJOR}.x"
    echo "❌ Failed to switch to Node.js ${REQUIRED_NODE_MAJOR}.x"
    exit 1
  fi
  
  # Set as default
  if nvm alias default ${REQUIRED_NODE_MAJOR}; then
    log_message "INFO" "Set Node.js ${REQUIRED_NODE_MAJOR}.x as default"
    echo "✅ Set Node.js ${REQUIRED_NODE_MAJOR}.x as default"
  else
    log_message "WARN" "Failed to set Node.js ${REQUIRED_NODE_MAJOR}.x as default"
    echo "⚠️ Failed to set Node.js ${REQUIRED_NODE_MAJOR}.x as default"
  fi
  
  # Verify installation
  if ! command_exists node || ! command_exists npm; then
    log_message "ERROR" "Node.js or npm not available after installation"
    echo "❌ Node.js or npm not available after installation"
    exit 1
  fi
  
  # Check version
  if ! check_nodejs_version; then
    log_message "ERROR" "Installed Node.js version is still incompatible"
    echo "❌ Installed Node.js version is still incompatible"
    exit 1
  fi
  
  local installed_version=$(node -v)
  local npm_version=$(npm -v)
  log_message "INFO" "Successfully installed Node.js $installed_version with npm $npm_version"
  echo "✅ Successfully installed Node.js $installed_version with npm $npm_version"
}

# Function to ensure Node.js is available in current session
ensure_nodejs_available() {
  # Source NVM to make sure Node.js is available
  source_nvm
  
  # If Node.js is not available, try to use the default version
  if ! command_exists node; then
    log_message "INFO" "Node.js not in PATH, trying to load default version"
    echo "🔄 Loading Node.js..."
    
    # Try to use default version
    if command_exists nvm; then
      nvm use default 2>/dev/null || nvm use ${REQUIRED_NODE_MAJOR} 2>/dev/null || true
    fi
  fi
  
  # Final check
  if ! command_exists node || ! command_exists npm; then
    log_message "ERROR" "Node.js or npm still not available"
    echo "❌ Node.js or npm still not available"
    echo "🔧 Please run: source ~/.bashrc && nvm use default"
    exit 1
  fi
}

# Function to install Node.js (main function)
install_nodejs() {
  # Check if Node.js is already installed and compatible
  if command_exists node && check_nodejs_version; then
    log_message "INFO" "Compatible Node.js already installed"
    echo "✅ Node.js is already installed with compatible version"
    return 0
  fi
  
  # Check if NVM is installed
  source_nvm
  if ! command_exists nvm; then
    install_nvm
    source_nvm
  else
    local nvm_version=$(nvm --version)
    log_message "INFO" "NVM $nvm_version is already installed"
    echo "✅ NVM $nvm_version is already installed"
  fi
  
  # Install Node.js using NVM
  install_nodejs_nvm
  
  # Ensure Node.js is available in current session
  ensure_nodejs_available
}

# Function to install Git
install_git() {
  local distro="$1"
  
  print_header "Installing Git"
  
  case "$distro" in
    debian)
      resolve_package_lock "$distro"
      run_command sudo apt-get install -y git
      ;;
    redhat)
      if command_exists dnf; then
        run_command sudo dnf install -y git
      else
        run_command sudo yum install -y git
      fi
      ;;
    suse)
      run_command sudo zypper install -y git
      ;;
    arch)
      run_command sudo pacman -S git --noconfirm
      ;;
    alpine)
      run_command sudo apk add git
      ;;
    macos)
      if command_exists brew; then
        run_command brew install git
      else
        echo "ℹ️ Git should be available via Xcode Command Line Tools"
        run_command xcode-select --install
      fi
      ;;
    *)
      log_message "ERROR" "Unsupported distribution for automatic Git installation"
      echo "❌ Unsupported distribution for automatic Git installation"
      return 1
      ;;
  esac
  
  if ! command_exists git; then
    log_message "ERROR" "Failed to install Git"
    echo "❌ Failed to install Git"
    exit 1
  fi
  
  log_message "INFO" "Git installed successfully"
  echo "✅ Git installed successfully"
}

# Enhanced PM2 installation with better error handling
install_pm2() {
  print_header "Installing PM2"
  
  # Ensure Node.js is available
  ensure_nodejs_available
  
  log_message "INFO" "Installing PM2 globally"
  echo "📦 Installing PM2 globally..."
  
  # Set npm configuration to avoid issues
  npm config set fund false 2>/dev/null || true
  npm config set audit false 2>/dev/null || true
  npm config set update-notifier false 2>/dev/null || true
  
  # Function to try different installation methods
  try_pm2_install() {
    local methods=("npm install -g pm2" "npm install -g pm2 --unsafe-perm")
    
    for method in "${methods[@]}"; do
      log_message "INFO" "Trying PM2 installation with: $method"
      echo "🔄 Trying: $method"
      
      if eval "$method"; then
        log_message "INFO" "PM2 installed successfully with: $method"
        echo "✅ PM2 installed successfully"
        return 0
      else
        log_message "WARN" "PM2 installation failed with: $method"
        echo "⚠️ Installation method failed: $method"
      fi
    done
    
    return 1
  }
  
  # Try standard installation methods first
  if try_pm2_install; then
    # Verify installation
    if command_exists pm2; then
      log_message "INFO" "PM2 installation verified"
      echo "✅ PM2 is ready"
      return 0
    fi
  fi
  
  # If standard methods fail, try alternative approach
  log_message "WARN" "Standard installation failed, trying alternative method"
  echo "⚠️ Standard installation failed, trying alternative method..."
  
  # Create npm global directory if it doesn't exist
  mkdir -p ~/.npm-global
  npm config set prefix '~/.npm-global'
  
  # Add to PATH temporarily and permanently
  export PATH=~/.npm-global/bin:$PATH
  
  # Add to bashrc if not already there
  if ! grep -q "~/.npm-global/bin" ~/.bashrc 2>/dev/null; then
    echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc
    log_message "INFO" "Added npm global bin to PATH in ~/.bashrc"
  fi
  
  # Try installing again with custom prefix
  if npm install -g pm2; then
    log_message "INFO" "PM2 installed successfully with custom prefix"
    echo "✅ PM2 installed successfully with custom prefix"
  else
    log_message "ERROR" "Failed to install PM2 with all methods"
    echo "❌ Failed to install PM2"
    exit 1
  fi
  
  # Final verification
  if ! command_exists pm2; then
    log_message "ERROR" "PM2 installation verification failed"
    echo "❌ PM2 installation verification failed"
    exit 1
  fi
  
  log_message "INFO" "PM2 is ready"
  echo "✅ PM2 is ready"
}

# Function to setup posting server
setup_posting_server() {
  print_header "Setting up Posting Server"
  
  # Ensure Node.js is available
  ensure_nodejs_available
  
  # Remove existing posting_server directory if it exists
  if [ -d "posting_server" ]; then
    log_message "INFO" "Removing existing posting_server directory"
    echo "🗑️ Removing existing posting_server directory..."
    rm -rf posting_server
  fi
  
  # Create logs directory if it doesn't exist
  mkdir -p logs
  
  # Clone the repository to a temporary directory
  log_message "INFO" "Downloading posting server from GitHub"
  echo "⬇️ Downloading posting server from GitHub..."
  TEMP_DIR=$(mktemp -d)
  
  if ! git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git "$TEMP_DIR"; then
    log_message "ERROR" "Failed to clone repository"
    echo "❌ Failed to clone repository"
    exit 1
  fi
  
  # Copy only the posting_server folder to our target location
  if [ ! -d "$TEMP_DIR/posting_server" ]; then
    log_message "ERROR" "posting_server directory not found in repository"
    echo "❌ posting_server directory not found in repository"
    exit 1
  fi
  
  cp -r "$TEMP_DIR/posting_server" .
  
  # Navigate to posting_server directory
  cd posting_server
  
  # Install dependencies with better error handling
  log_message "INFO" "Installing posting server dependencies"
  echo "📦 Installing posting server dependencies..."
  
  # Clear npm cache first
  npm cache clean --force 2>/dev/null || true
  
  # Try different installation strategies
  local install_success=false
  local install_methods=(
    "npm install"
    "npm install --legacy-peer-deps"
    "npm install --force"
    "npm install --legacy-peer-deps --no-optional"
  )
  
  for method in "${install_methods[@]}"; do
    log_message "INFO" "Trying npm install with: $method"
    echo "🔄 Trying: $method"
    
    if eval "$method"; then
      log_message "INFO" "Dependencies installed successfully with: $method"
      echo "✅ Dependencies installed successfully"
      install_success=true
      break
    else
      log_message "WARN" "Install method failed: $method"
      echo "⚠️ Install method failed: $method"
    fi
  done
  
  if [ "$install_success" = false ]; then
    log_message "ERROR" "Failed to install dependencies with all methods"
    echo "❌ Failed to install dependencies"
    exit 1
  fi
  
  # Verify that server.js exists
  if [ ! -f "server.js" ]; then
    log_message "ERROR" "server.js not found in posting_server directory"
    echo "❌ server.js not found in posting_server directory"
    exit 1
  fi
  
  # Set permissions
  log_message "INFO" "Setting up permissions"
  echo "🔒 Setting up permissions..."
  chmod 755 .
  find . -type f -name "*.js" -exec chmod 644 {} \; 2>/dev/null || true
  find . -type f -name "*.json" -exec chmod 644 {} \; 2>/dev/null || true
  find . -type d -exec chmod 755 {} \; 2>/dev/null || true
  chmod 755 ../logs
  
  log_message "INFO" "Posting server setup completed"
  echo "✅ Posting server setup completed"
}

# Enhanced function to start server with PM2
start_server_pm2() {
  print_header "Starting Server with PM2"
  
  # Ensure Node.js and PM2 are available
  ensure_nodejs_available
  
  # Stop any existing process
  if pm2 list | grep -q "posting-server"; then
    log_message "INFO" "Stopping existing posting-server process"
    echo "⚠️ Stopping existing posting-server process..."
    pm2 stop posting-server 2>/dev/null || true
    pm2 delete posting-server 2>/dev/null || true
  fi
  
  # Start the server with enhanced configuration
  log_message "INFO" "Starting posting server with PM2"
  echo "🚀 Starting posting server with PM2..."
  
  # Create PM2 ecosystem file for better configuration
  cat > ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: 'posting-server',
    script: 'server.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production'
    },
    error_file: '../logs/posting-server-error.log',
    out_file: '../logs/posting-server-out.log',
    log_file: '../logs/posting-server.log',
    time: true,
    exp_backoff_restart_delay: 100,
    max_restarts: 10,
    min_uptime: '10s'
  }]
}
EOF
  
  # Start using ecosystem file
  if pm2 start ecosystem.config.js; then
    log_message "INFO" "PM2 start command executed successfully"
    echo "✅ PM2 start command executed successfully"
  else
    log_message "ERROR" "Failed to start server with PM2"
    echo "❌ Failed to start server with PM2"
    
    # Try fallback method
    log_message "INFO" "Trying fallback PM2 start method"
    echo "🔄 Trying fallback method..."
    if pm2 start server.js --name "posting-server" --log "../logs/posting-server.log" --exp-backoff-restart-delay=100; then
      log_message "INFO" "Server started with fallback method"
      echo "✅ Server started with fallback method"
    else
      log_message "ERROR" "All PM2 start methods failed"
      echo "❌ All PM2 start methods failed"
      exit 1
    fi
  fi
  
  # Save PM2 process list
  log_message "INFO" "Saving PM2 process list"
  echo "💾 Saving PM2 process list..."
  pm2 save
  
  # Wait a bit longer for server to start
  echo "⏳ Waiting for server to initialize..."
  sleep 10
  
  # Verify server is running with multiple checks
  local max_checks=6
  local check=1
  local server_running=false
  
  while [ $check -le $max_checks ]; do
    log_message "INFO" "Server status check $check/$max_checks"
    echo "🔍 Checking server status ($check/$max_checks)..."
    
    if pm2 list | grep -q "posting-server.*online"; then
      log_message "INFO" "Server is running successfully"
      echo "✅ Posting server is running successfully!"
      server_running=true
      break
    fi
    
    # If not online, try to restart
    if [ $check -le 3 ]; then
      log_message "WARN" "Server not online, attempting restart"
      echo "⚠️ Server not online, attempting restart..."
      pm2 restart posting-server 2>/dev/null || true
    fi
    
    check=$((check + 1))
    sleep 5
  done
  
  if [ "$server_running" = false ]; then
    log_message "ERROR" "Server failed to start properly after all attempts"
    echo "❌ Server failed to start properly"
    echo "📋 Check logs with: pm2 logs posting-server"
    echo "📋 Manual restart: pm2 restart posting-server"
    
    # Show current PM2 status for debugging
    echo ""
    echo "📊 Current PM2 Status:"
    pm2 list
    
    # Don't exit here, continue with setup but warn user
    echo "⚠️ You may need to manually restart the server later"
  fi
}

# Function to setup PM2 startup
setup_pm2_startup() {
  print_header "Setting up PM2 Startup"
  
  log_message "INFO" "Configuring PM2 to start on system boot"
  echo "🔧 Configuring PM2 to start on system boot..."
  
  # Generate startup script
  local startup_output=$(pm2 startup 2>&1)
  echo "$startup_output"
  
  # Extract and run the sudo command if present
  local startup_cmd=$(echo "$startup_output" | grep -E "sudo.*pm2.*startup" | head -n 1)
  
  if [ -n "$startup_cmd" ]; then
    log_message "INFO" "Running startup command: $startup_cmd"
    echo "🔧 Running startup command: $startup_cmd"
    if eval "$startup_cmd"; then
      log_message "INFO" "PM2 startup script configured successfully"
      echo "✅ PM2 startup script configured successfully"
    else
      log_message "WARN" "Failed to run PM2 startup command automatically"
      echo "⚠️ Failed to run PM2 startup command automatically"
      echo "📋 Please run this command manually:"
      echo "$startup_cmd"
    fi
  else
    log_message "INFO" "PM2 startup may already be configured or no sudo command needed"
    echo "ℹ️ PM2 startup may already be configured or no sudo command needed"
  fi
}

# Function to setup log rotation
setup_log_rotation() {
  print_header "Setting up Log Rotation"
  
  log_message "INFO" "Installing and configuring PM2 log rotation"
  echo "🔧 Installing PM2 log rotation module..."
  
  if pm2 install pm2-logrotate; then
    # Configure log rotation
    pm2 set pm2-logrotate:max_size 10M
    pm2 set pm2-logrotate:compress true
    pm2 set pm2-logrotate:retain 7
    log_message "INFO" "PM2 log rotation configured successfully"
    echo "✅ PM2 log rotation configured successfully"
  else
    log_message "WARN" "Failed to install PM2 log rotation (optional feature)"
    echo "⚠️ Failed to install PM2 log rotation (optional feature)"
  fi
}

# Function to create environment setup script
create_environment_script() {
  log_message "INFO" "Creating environment setup script"
  echo "📄 Creating environment setup script..."
  
  cat > setup_environment.sh << 'EOF'
#!/bin/bash
# Environment setup script for posting server
# Run this script if Node.js or PM2 are not available in your session

echo "🔧 Setting up Node.js environment..."

# Source NVM
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  source "$HOME/.nvm/nvm.sh"
  echo "✅ NVM sourced from ~/.nvm/nvm.sh"
elif [ -s "/usr/local/nvm/nvm.sh" ]; then
  source "/usr/local/nvm/nvm.sh"
  echo "✅ NVM sourced from /usr/local/nvm/nvm.sh"
else
  echo "❌ NVM not found"
  exit 1
fi

# Source bash completion
if [ -s "$HOME/.nvm/bash_completion" ]; then
  source "$HOME/.nvm/bash_completion"
fi

# Set NVM_DIR if not set
if [ -z "$NVM_DIR" ]; then
  if [ -d "$HOME/.nvm" ]; then
    export NVM_DIR="$HOME/.nvm"
  fi
fi

# Use the default Node.js version
if command -v nvm >/dev/null 2>&1; then
  nvm use default 2>/dev/null || nvm use 18 2>/dev/null || true
  echo "✅ Node.js version: $(node -v 2>/dev/null || echo 'Not available')"
  echo "✅ npm version: $(npm -v 2>/dev/null || echo 'Not available')"
  echo "✅ PM2 available: $(command -v pm2 >/dev/null 2>&1 && echo 'Yes' || echo 'No')"
else
  echo "❌ NVM command not found"
  exit 1
fi

# Add npm global bin to PATH if not already there
if [ -d "$HOME/.npm-global/bin" ] && [[ ":$PATH:" != *":$HOME/.npm-global/bin:"* ]]; then
  export PATH="$HOME/.npm-global/bin:$PATH"
  echo "✅ Added npm global bin to PATH"
fi

echo "🎉 Environment setup complete!"
echo "📋 You can now use: node, npm, pm2"
EOF
  
  chmod +x setup_environment.sh
  echo "✅ Created setup_environment.sh for environment management"
}

# Function to display final status
display_final_status() {
  print_header "Installation Complete"
  
  echo "✅ Server installation completed successfully!"
  echo ""
  echo "🔧 Node.js Installation Method: NVM (Node Version Manager)"
  echo "   - This avoids dependency conflicts with system packages"
  echo "   - Node.js version: $(node -v 2>/dev/null || echo 'Not in current PATH')"
  echo "   - npm version: $(npm -v 2>/dev/null || echo 'Not in current PATH')"
  echo ""
  echo "📁 Posting server structure:"
  echo "   - config/"
  echo "   - models/"
  echo "   - utils/"
  echo "   - server.js"
  echo "   - package.json"
  echo "   - ecosystem.config.js"
  echo ""
  echo "🎛️ PM2 Management Commands:"
  echo "   pm2 status                # Check server status"
  echo "   pm2 logs                  # View all logs"
  echo "   pm2 logs posting-server   # View posting server logs"
  echo "   pm2 restart posting-server # Restart the server"
  echo "   pm2 stop posting-server   # Stop the server"
  echo "   pm2 delete posting-server # Remove from PM2"
  echo "   pm2 monit                 # Monitor server resources"
  echo ""
  echo "🔧 Environment Management:"
  echo "   source ~/.bashrc          # Reload shell environment"
  echo "   ./setup_environment.sh    # Setup Node.js environment in current session"
  echo "   nvm use default           # Switch to default Node.js version"
  echo "   nvm list                  # List installed Node.js versions"
  echo ""
  echo "🔧 Troubleshooting Commands:"
  echo "   pm2 flush                 # Clear all logs"
  echo "   pm2 reload posting-server # Graceful reload"
  echo "   pm2 reset posting-server  # Reset restart counters"
  echo "   source ~/.nvm/nvm.sh      # Manually source NVM"
  echo ""
  echo "📊 Current Status:"
  
  # Ensure environment is loaded for status check
  source_nvm
  ensure_nodejs_available 2>/dev/null || true
  
  if command_exists pm2; then
    pm2 status
  else
    echo "   ⚠️ PM2 not available in current session"
    echo "   🔧 Run: source ~/.bashrc or ./setup_environment.sh"
  fi
  
  # Additional health checks
  echo ""
  echo "🏥 Health Check:"
  if command_exists pm2 && pm2 list | grep -q "posting-server.*online"; then
    echo "   ✅ Server Status: ONLINE"
  elif command_exists pm2 && pm2 list | grep -q "posting-server.*stopped"; then
    echo "   ⚠️ Server Status: STOPPED (run 'pm2 restart posting-server')"
  elif command_exists pm2; then
    echo "   ❌ Server Status: NOT FOUND"
  else
    echo "   ⚠️ Server Status: UNKNOWN (PM2 not available in current session)"
  fi
  
  if [ -f "posting_server/server.js" ]; then
    echo "   ✅ Server Files: Present"
  else
    echo "   ❌ Server Files: Missing"
  fi
  
  if [ -d "logs" ]; then
    echo "   ✅ Log Directory: Present"
  else
    echo "   ❌ Log Directory: Missing"
  fi
  
  if command_exists nvm; then
    echo "   ✅ NVM: Available"
  else
    echo "   ⚠️ NVM: Not available in current session"
  fi
  
  if command_exists node; then
    echo "   ✅ Node.js: $(node -v)"
  else
    echo "   ⚠️ Node.js: Not available in current session"
  fi
  
  echo ""
  echo "📝 Log Files Location:"
  echo "   - Application logs: logs/posting-server.log"
  echo "   - Error logs: logs/posting-server-error.log"
  echo "   - Output logs: logs/posting-server-out.log"
  echo "   - Setup log: $LOG_FILE"
  echo ""
  echo "⚠️ IMPORTANT: If Node.js/PM2 commands don't work:"
  echo "   1. Run: source ~/.bashrc"
  echo "   2. Or run: ./setup_environment.sh"
  echo "   3. Or open a new terminal session"
}

# Function to perform post-installation checks
post_installation_checks() {
  print_header "Post-Installation Checks"
  
  local issues_found=false
  
  # Source environment for checks
  source_nvm 2>/dev/null || true
  
  # Check NVM
  if command_exists nvm; then
    echo "✅ NVM: $(nvm --version)"
  else
    echo "❌ NVM: Not properly installed"
    issues_found=true
  fi
  
  # Check Node.js
  if command_exists node && check_nodejs_version 2>/dev/null; then
    echo "✅ Node.js: $(node -v)"
  else
    echo "⚠️ Node.js: Not available in current session (may need to source environment)"
  fi
  
  # Check npm
  if command_exists npm; then
    echo "✅ npm: $(npm -v)"
  else
    echo "⚠️ npm: Not available in current session"
  fi
  
  # Check PM2
  if command_exists pm2; then
    echo "✅ PM2: $(pm2 -v)"
  else
    echo "⚠️ PM2: Not available in current session"
  fi
  
  # Check Git
  if command_exists git; then
    echo "✅ Git: $(git --version | cut -d' ' -f3)"
  else
    echo "❌ Git: Not properly installed"
    issues_found=true
  fi
  
  # Check server files
  if [ -f "posting_server/server.js" ]; then
    echo "✅ Server files: Present"
  else
    echo "❌ Server files: Missing"
    issues_found=true
  fi
  
  # Check server status (if PM2 is available)
  sleep 2
  if command_exists pm2; then
    if pm2 list | grep -q "posting-server"; then
      if pm2 list | grep -q "posting-server.*online"; then
        echo "✅ Server status: Online"
      else
        echo "⚠️ Server status: Not online (may need restart)"
      fi
    else
      echo "❌ Server status: Not found in PM2"
      issues_found=true
    fi
  else
    echo "⚠️ Server status: Cannot check (PM2 not in current session)"
  fi
  
  if [ "$issues_found" = true ]; then
    echo ""
    echo "⚠️ Some issues were detected. Check the items marked with ❌"
    echo "📋 Most environment issues can be resolved by:"
    echo "   1. Opening a new terminal session, or"
    echo "   2. Running: source ~/.bashrc"
    echo "   3. Running: ./setup_environment.sh"
  else
    echo ""
    echo "🎉 All critical components are properly installed!"
    echo "ℹ️ If commands are not available, restart your terminal or source the environment"
  fi
}

# Function to create a restart script for user convenience
create_restart_script() {
  log_message "INFO" "Creating restart script for user convenience"
  
  cat > restart_server.sh << 'EOF'
#!/bin/bash
echo "🔄 Restarting posting server..."

# Source NVM environment
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  source "$HOME/.nvm/nvm.sh"
fi

# Use default Node.js version
if command -v nvm >/dev/null 2>&1; then
  nvm use default 2>/dev/null || nvm use 18 2>/dev/null || true
fi

# Add npm global to PATH if exists
if [ -d "$HOME/.npm-global/bin" ]; then
  export PATH="$HOME/.npm-global/bin:$PATH"
fi

# Check if PM2 is available
if ! command -v pm2 >/dev/null 2>&1; then
  echo "❌ PM2 not found. Please run: source ~/.bashrc or ./setup_environment.sh"
  exit 1
fi

# Restart the server
pm2 restart posting-server
echo "⏳ Waiting for server to start..."
sleep 5
pm2 status
echo "✅ Restart completed!"
EOF
  
  chmod +x restart_server.sh
  echo "📄 Created restart_server.sh for easy server management"
}

# Enhanced main execution function
main() {
  # Initialize logging
  echo "Starting server setup at $(date)" > "$LOG_FILE"
  
  # Create lock file
  create_lock
  
  print_header "Enhanced Cross-Platform Server Setup Script v2.1 (NVM Edition)"
  echo "🐧 Detected OS: $OSTYPE"
  echo "🚀 This version uses NVM to avoid dependency conflicts!"
  
  # Detect distribution
  local distro=$(detect_distro)
  echo "📦 Distribution: $distro"
  log_message "INFO" "Detected distribution: $distro"
  
  if [ "$distro" = "unknown" ]; then
    log_message "WARN" "Unknown Linux distribution detected"
    echo "⚠️ Unknown Linux distribution detected"
    echo "📋 This script supports: Ubuntu, Debian, CentOS, RHEL, Fedora, openSUSE, Arch Linux, Alpine Linux"
    echo "🔄 Attempting to continue with generic commands..."
    
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
  
  # Update repositories (needed for Git and other tools)
  update_repositories "$distro"
  
  # Check and install dependencies
  print_header "Checking Dependencies"
  
  # Check Git first (needed for cloning repository)
  if ! command_exists git; then
    install_git "$distro"
  else
    echo "✅ Git is already installed"
    log_message "INFO" "Git already installed"
  fi
  
  # Install Node.js using NVM (this handles both NVM and Node.js installation)
  install_nodejs
  
  # Check and install PM2
  if ! command_exists pm2; then
    install_pm2
  else
    echo "✅ PM2 is already installed"
    log_message "INFO" "PM2 already installed"
  fi
  
  # Setup posting server
  setup_posting_server
  
  # Start server with PM2
  start_server_pm2
  
  # Setup PM2 startup (optional)
  setup_pm2_startup
  
  # Setup log rotation (optional)
  setup_log_rotation
  
  # Create convenience scripts
  create_restart_script
  create_environment_script
  
  # Perform post-installation checks
  post_installation_checks
  
  # Display final status
  display_final_status
  
  echo ""
  echo "🎉 Setup completed successfully!"
  echo "🌐 Your posting server is now running with Node.js managed by NVM."
  echo "📝 Setup log saved to: $LOG_FILE"
  echo ""
  echo "🚀 Quick Start Commands:"
  echo "   ./restart_server.sh       # Restart the server easily"
  echo "   ./setup_environment.sh    # Setup environment in current session"
  echo "   source ~/.bashrc          # Reload shell environment"
  echo "   pm2 monit                 # Monitor server performance"
  echo "   tail -f logs/*.log        # Watch live logs"
  echo ""
  echo "💡 If commands don't work immediately:"
  echo "   1. Open a new terminal session, or"
  echo "   2. Run: source ~/.bashrc"
  echo "   3. Run: ./setup_environment.sh"
  
  log_message "INFO" "Setup completed successfully"
}

# Pre-flight checks
preflight_checks() {
  # Check if running as root (not recommended for some operations)
  if [ "$EUID" -eq 0 ]; then
    echo "⚠️ Running as root detected."
    echo "🔄 NVM installation works better with a regular user."
    echo "💡 Consider running this script as a regular user with sudo privileges."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
  
  # Check internet connectivity
  if ! ping -c 1 google.com &> /dev/null && ! ping -c 1 8.8.8.8 &> /dev/null; then
    echo "❌ No internet connectivity detected. This script requires internet access."
    echo "📋 Please check your network connection and try again."
    exit 1
  fi
  
  # Check available disk space (require at least 1GB)
  local available_space=$(df . | tail -1 | awk '{print $4}')
  if [ "$available_space" -lt 1048576 ]; then  # 1GB in KB
    echo "⚠️ Less than 1GB of disk space available. The installation may fail."
    echo "📊 Available space: $(df -h . | tail -1 | awk '{print $4}')"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
  
  # Check if curl is available
  if ! command_exists curl; then
    echo "❌ curl is required but not installed. Please install curl first."
    echo "📋 Install curl with:"
    echo "   Ubuntu/Debian: sudo apt-get install curl"
    echo "   CentOS/RHEL: sudo yum install curl"
    echo "   Fedora: sudo dnf install curl"
    exit 1
  fi
  
  echo "✅ Pre-flight checks passed!"
}

# Run preflight checks
preflight_checks

# Run main function
main "$@"