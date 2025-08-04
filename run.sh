#!/bin/bash

# Enhanced cross-platform server setup script
# Compatible with all major Linux distributions

# Exit on error, but allow certain commands to fail without stopping the script
set -e

# Global variables
REQUIRED_NODE_MAJOR=18
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR=""
LOCK_FILE="/tmp/server_setup.lock"

# Function to clean up on error or exit
cleanup() {
  local exit_code=$?
  if [ -f "$LOCK_FILE" ]; then
    rm -f "$LOCK_FILE"
  fi
  if [ -d "posting_server" ] && [ $exit_code -ne 0 ]; then
    echo "❌ An error occurred. Cleaning up..."
    rm -rf posting_server
  fi
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
  if [ $exit_code -ne 0 ]; then
    echo "❌ Script failed with exit code $exit_code"
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
}

# Function to run a command with error handling
run_command() {
  echo "$ $*"
  if "$@"; then
    return 0
  else
    local exit_code=$?
    echo "⚠️ Command failed with exit code $exit_code: $*"
    return $exit_code
  fi
}

# Function to run a command and continue on failure
run_command_continue() {
  echo "$ $*"
  if "$@"; then
    return 0
  else
    local exit_code=$?
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

# Function to wait for package manager lock
wait_for_package_manager() {
  local distro="$1"
  local max_wait=300  # 5 minutes
  local wait_time=0
  
  case "$distro" in
    debian)
      while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        if [ $wait_time -ge $max_wait ]; then
          echo "❌ Timeout waiting for package manager lock. Please try again later."
          return 1
        fi
        echo "⏳ Waiting for package manager lock to be released... ($wait_time/${max_wait}s)"
        sleep 10
        wait_time=$((wait_time + 10))
      done
      ;;
    redhat)
      while pgrep -f "yum|dnf" >/dev/null 2>&1; do
        if [ $wait_time -ge $max_wait ]; then
          echo "❌ Timeout waiting for package manager. Please try again later."
          return 1
        fi
        echo "⏳ Waiting for package manager to be available... ($wait_time/${max_wait}s)"
        sleep 10
        wait_time=$((wait_time + 10))
      done
      ;;
  esac
  return 0
}

# Function to kill conflicting package manager processes
kill_package_manager_processes() {
  local distro="$1"
  
  echo "🔄 Checking for conflicting package manager processes..."
  
  case "$distro" in
    debian)
      # Kill any hanging apt processes
      sudo pkill -f "apt-get|aptd|dpkg" 2>/dev/null || true
      sleep 2
      
      # Remove lock files if they exist
      sudo rm -f /var/lib/dpkg/lock-frontend 2>/dev/null || true
      sudo rm -f /var/lib/dpkg/lock 2>/dev/null || true
      sudo rm -f /var/lib/apt/lists/lock 2>/dev/null || true
      sudo rm -f /var/cache/apt/archives/lock 2>/dev/null || true
      
      # Reconfigure dpkg if interrupted
      sudo dpkg --configure -a 2>/dev/null || true
      ;;
    redhat)
      sudo pkill -f "yum|dnf" 2>/dev/null || true
      sleep 2
      ;;
  esac
}

# Function to update package repositories
update_repositories() {
  local distro="$1"
  
  print_header "Updating Package Repositories"
  
  wait_for_package_manager "$distro"
  
  case "$distro" in
    debian)
      kill_package_manager_processes "$distro"
      run_command sudo apt-get clean
      run_command sudo apt-get update
      ;;
    redhat)
      if command_exists dnf; then
        run_command sudo dnf clean all
        run_command sudo dnf makecache
      else
        run_command sudo yum clean all
        run_command sudo yum makecache
      fi
      ;;
    suse)
      run_command sudo zypper refresh
      ;;
    arch)
      run_command sudo pacman -Sy
      ;;
    alpine)
      run_command sudo apk update
      ;;
  esac
}

# Function to check Node.js version
check_nodejs_version() {
  if command_exists node; then
    local current_version=$(node -v | cut -d 'v' -f 2)
    local current_major=$(echo $current_version | cut -d '.' -f 1)
    
    if [[ $current_major -lt $REQUIRED_NODE_MAJOR ]]; then
      echo "⚠️ Node.js version $current_version is too old. Required: v${REQUIRED_NODE_MAJOR}.0.0 or higher."
      return 1
    else
      echo "✅ Node.js version $current_version is compatible."
      return 0
    fi
  else
    echo "❌ Node.js is not installed."
    return 1
  fi
}

# Function to remove old Node.js installation
remove_old_nodejs() {
  local distro="$1"
  
  echo "🗑️ Removing old Node.js installation..."
  
  case "$distro" in
    debian)
      run_command_continue sudo apt-get remove -y nodejs npm
      run_command_continue sudo apt-get autoremove -y
      ;;
    redhat)
      if command_exists dnf; then
        run_command_continue sudo dnf remove -y nodejs npm
      else
        run_command_continue sudo yum remove -y nodejs npm
      fi
      ;;
    suse)
      run_command_continue sudo zypper remove -y nodejs npm
      ;;
    arch)
      run_command_continue sudo pacman -Rs nodejs npm
      ;;
    alpine)
      run_command_continue sudo apk del nodejs npm
      ;;
  esac
  
  # Remove NodeSource repository if it exists
  if [ -f /etc/apt/sources.list.d/nodesource.list ]; then
    sudo rm -f /etc/apt/sources.list.d/nodesource.list
  fi
  
  # Clear npm cache and remove global packages
  if [ -d ~/.npm ]; then
    rm -rf ~/.npm
  fi
  
  # Remove global node_modules
  if [ -d /usr/local/lib/node_modules ]; then
    sudo rm -rf /usr/local/lib/node_modules
  fi
}

# Function to install Node.js using NodeSource
install_nodejs_nodesource() {
  local distro="$1"
  
  echo "📦 Installing Node.js ${REQUIRED_NODE_MAJOR}.x via NodeSource..."
  
  case "$distro" in
    debian)
      # Download and run NodeSource setup script
      curl -fsSL https://deb.nodesource.com/setup_${REQUIRED_NODE_MAJOR}.x | sudo -E bash -
      wait_for_package_manager "$distro"
      run_command sudo apt-get install -y nodejs
      ;;
    redhat)
      curl -fsSL https://rpm.nodesource.com/setup_${REQUIRED_NODE_MAJOR}.x | sudo bash -
      if command_exists dnf; then
        run_command sudo dnf install -y nodejs
      else
        run_command sudo yum install -y nodejs
      fi
      ;;
    *)
      echo "❌ NodeSource installation not supported for this distribution"
      return 1
      ;;
  esac
}

# Function to install Node.js using package manager
install_nodejs_package_manager() {
  local distro="$1"
  
  echo "📦 Installing Node.js via system package manager..."
  
  case "$distro" in
    debian)
      wait_for_package_manager "$distro"
      run_command sudo apt-get install -y nodejs npm
      ;;
    redhat)
      if command_exists dnf; then
        run_command sudo dnf install -y nodejs npm
      else
        run_command sudo yum install -y nodejs npm
      fi
      ;;
    suse)
      run_command sudo zypper install -y nodejs npm
      ;;
    arch)
      run_command sudo pacman -S nodejs npm
      ;;
    alpine)
      run_command sudo apk add nodejs npm
      ;;
    macos)
      if command_exists brew; then
        run_command brew install node
      else
        echo "❌ Homebrew not found. Please install Node.js manually from https://nodejs.org/"
        return 1
      fi
      ;;
    *)
      echo "❌ Unsupported distribution for automatic Node.js installation"
      return 1
      ;;
  esac
}

# Function to install Node.js
install_nodejs() {
  local distro="$1"
  
  print_header "Installing Node.js ${REQUIRED_NODE_MAJOR}.x"
  
  # Remove old Node.js if it exists
  if command_exists node; then
    remove_old_nodejs "$distro"
  fi
  
  # Try NodeSource first (provides latest versions)
  if [[ "$distro" == "debian" || "$distro" == "redhat" ]]; then
    if install_nodejs_nodesource "$distro"; then
      echo "✅ Node.js installed successfully via NodeSource"
    else
      echo "⚠️ NodeSource installation failed, trying package manager..."
      install_nodejs_package_manager "$distro"
    fi
  else
    install_nodejs_package_manager "$distro"
  fi
  
  # Verify installation
  if ! command_exists node || ! command_exists npm; then
    echo "❌ Failed to install Node.js. Please install manually from https://nodejs.org/"
    exit 1
  fi
  
  # Check version again
  if ! check_nodejs_version; then
    echo "❌ Installed Node.js version is still incompatible"
    exit 1
  fi
  
  local installed_version=$(node -v)
  echo "✅ Successfully installed Node.js $installed_version"
}

# Function to install Git
install_git() {
  local distro="$1"
  
  print_header "Installing Git"
  
  case "$distro" in
    debian)
      wait_for_package_manager "$distro"
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
      run_command sudo pacman -S git
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
      echo "❌ Unsupported distribution for automatic Git installation"
      return 1
      ;;
  esac
  
  if ! command_exists git; then
    echo "❌ Failed to install Git"
    exit 1
  fi
  
  echo "✅ Git installed successfully"
}

# Function to install PM2
install_pm2() {
  print_header "Installing PM2"
  
  echo "📦 Installing PM2 globally..."
  
  # Set npm configuration to avoid permission issues
  npm config set fund false 2>/dev/null || true
  npm config set audit false 2>/dev/null || true
  
  # Try installing PM2 with different methods
  if npm install -g pm2; then
    echo "✅ PM2 installed successfully"
  elif sudo npm install -g pm2; then
    echo "✅ PM2 installed successfully with sudo"
  else
    echo "⚠️ Standard installation failed, trying alternative method..."
    
    # Create npm global directory if it doesn't exist
    mkdir -p ~/.npm-global
    npm config set prefix '~/.npm-global'
    
    # Add to PATH
    export PATH=~/.npm-global/bin:$PATH
    echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc
    
    # Try installing again
    if npm install -g pm2; then
      echo "✅ PM2 installed successfully with custom prefix"
    else
      echo "❌ Failed to install PM2"
      exit 1
    fi
  fi
  
  # Verify PM2 installation
  if ! command_exists pm2; then
    echo "❌ PM2 installation verification failed"
    exit 1
  fi
  
  echo "✅ PM2 is ready"
}

# Function to setup posting server
setup_posting_server() {
  print_header "Setting up Posting Server"
  
  # Remove existing posting_server directory if it exists
  if [ -d "posting_server" ]; then
    echo "🗑️ Removing existing posting_server directory..."
    rm -rf posting_server
  fi
  
  # Create logs directory if it doesn't exist
  mkdir -p logs
  
  # Clone the repository to a temporary directory
  echo "⬇️ Downloading posting server from GitHub..."
  TEMP_DIR=$(mktemp -d)
  
  if ! git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git "$TEMP_DIR"; then
    echo "❌ Failed to clone repository"
    exit 1
  fi
  
  # Copy only the posting_server folder to our target location
  if [ ! -d "$TEMP_DIR/posting_server" ]; then
    echo "❌ posting_server directory not found in repository"
    exit 1
  fi
  
  cp -r "$TEMP_DIR/posting_server" .
  
  # Navigate to posting_server directory
  cd posting_server
  
  # Install dependencies with better error handling
  echo "📦 Installing posting server dependencies..."
  
  # Clear npm cache first
  npm cache clean --force 2>/dev/null || true
  
  # Install with specific options to handle version conflicts
  if ! npm install --legacy-peer-deps; then
    echo "⚠️ Standard install failed, trying with force flag..."
    if ! npm install --force; then
      echo "⚠️ Forced install failed, trying to fix dependencies..."
      npm audit fix --force 2>/dev/null || true
      npm install --legacy-peer-deps --no-optional
    fi
  fi
  
  # Set permissions
  echo "🔒 Setting up permissions..."
  chmod 755 .
  find . -type f -name "*.js" -exec chmod 644 {} \; 2>/dev/null || true
  find . -type f -name "*.json" -exec chmod 644 {} \; 2>/dev/null || true
  find . -type d -exec chmod 755 {} \; 2>/dev/null || true
  chmod 755 ../logs
  
  echo "✅ Posting server setup completed"
}

# Function to start server with PM2
start_server_pm2() {
  print_header "Starting Server with PM2"
  
  # Stop any existing process
  if pm2 list | grep -q "posting-server"; then
    echo "⚠️ Stopping existing posting-server process..."
    pm2 stop posting-server 2>/dev/null || true
    pm2 delete posting-server 2>/dev/null || true
  fi
  
  # Start the server
  echo "🚀 Starting posting server with PM2..."
  
  if ! pm2 start server.js --name "posting-server" --log "../logs/posting-server.log" --exp-backoff-restart-delay=100; then
    echo "❌ Failed to start server with PM2"
    exit 1
  fi
  
  # Save PM2 process list
  echo "💾 Saving PM2 process list..."
  pm2 save
  
  # Verify server is running
  sleep 3
  if pm2 list | grep -q "posting-server.*online"; then
    echo "✅ Posting server is running successfully!"
  else
    echo "❌ Server failed to start properly"
    echo "📋 Check logs with: pm2 logs posting-server"
    exit 1
  fi
}

# Function to setup PM2 startup
setup_pm2_startup() {
  print_header "Setting up PM2 Startup"
  
  echo "🔧 Configuring PM2 to start on system boot..."
  
  # Generate startup script
  local startup_output=$(pm2 startup 2>&1)
  echo "$startup_output"
  
  # Extract and run the sudo command if present
  local startup_cmd=$(echo "$startup_output" | grep -E "sudo.*pm2.*startup" | head -n 1)
  
  if [ -n "$startup_cmd" ]; then
    echo "🔧 Running startup command: $startup_cmd"
    if eval "$startup_cmd"; then
      echo "✅ PM2 startup script configured successfully"
    else
      echo "⚠️ Failed to run PM2 startup command automatically"
      echo "📋 Please run this command manually:"
      echo "$startup_cmd"
    fi
  else
    echo "ℹ️ PM2 startup may already be configured or no sudo command needed"
  fi
}

# Function to setup log rotation
setup_log_rotation() {
  print_header "Setting up Log Rotation"
  
  echo "🔧 Installing PM2 log rotation module..."
  
  if pm2 install pm2-logrotate; then
    # Configure log rotation
    pm2 set pm2-logrotate:max_size 10M
    pm2 set pm2-logrotate:compress true
    pm2 set pm2-logrotate:retain 7
    echo "✅ PM2 log rotation configured successfully"
  else
    echo "⚠️ Failed to install PM2 log rotation (optional feature)"
  fi
}

# Function to display final status
display_final_status() {
  print_header "Installation Complete"
  
  echo "✅ Server installation completed successfully!"
  echo ""
  echo "📁 Posting server structure:"
  echo "   - config/"
  echo "   - models/"
  echo "   - utils/"
  echo "   - server.js"
  echo "   - package.json"
  echo ""
  echo "🎛️ PM2 Management Commands:"
  echo "   pm2 status                # Check server status"
  echo "   pm2 logs                  # View all logs"
  echo "   pm2 logs posting-server   # View posting server logs"
  echo "   pm2 restart posting-server # Restart the server"
  echo "   pm2 stop posting-server   # Stop the server"
  echo "   pm2 delete posting-server # Remove from PM2"
  echo ""
  echo "📊 Current Status:"
  pm2 status
}

# Main execution
main() {
  # Create lock file
  create_lock
  
  print_header "Cross-Platform Server Setup Script"
  echo "🐧 Detected OS: $OSTYPE"
  
  # Detect distribution
  local distro=$(detect_distro)
  echo "📦 Distribution: $distro"
  
  if [ "$distro" = "unknown" ]; then
    echo "⚠️ Unknown Linux distribution detected"
    echo "📋 This script supports: Ubuntu, Debian, CentOS, RHEL, Fedora, openSUSE, Arch Linux, Alpine Linux"
    echo "🔄 Attempting to continue with generic commands..."
  fi
  
  # Update repositories
  update_repositories "$distro"
  
  # Check and install dependencies
  print_header "Checking Dependencies"
  
  # Check Node.js
  if ! command_exists node || ! check_nodejs_version; then
    install_nodejs "$distro"
  else
    echo "✅ Node.js is already installed with compatible version"
  fi
  
  # Check npm
  if ! command_exists npm; then
    echo "❌ npm is not available after Node.js installation"
    exit 1
  else
    echo "✅ npm is available"
  fi
  
  # Check Git
  if ! command_exists git; then
    install_git "$distro"
  else
    echo "✅ Git is already installed"
  fi
  
  # Check and install PM2
  if ! command_exists pm2; then
    install_pm2
  else
    echo "✅ PM2 is already installed"
  fi
  
  # Setup posting server
  setup_posting_server
  
  # Start server with PM2
  start_server_pm2
  
  # Setup PM2 startup (optional)
  setup_pm2_startup
  
  # Setup log rotation (optional)
  setup_log_rotation
  
  # Display final status
  display_final_status
  
  echo ""
  echo "🎉 Setup completed successfully!"
  echo "🌐 Your posting server is now running and will auto-start on system boot."
}

# Check if running as root (not recommended for some operations)
if [ "$EUID" -eq 0 ]; then
  echo "⚠️ Running as root detected. Some npm operations work better with a regular user."
  echo "🔄 Consider running this script as a regular user with sudo privileges."
  read -p "Continue anyway? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Run main function
main "$@"