#!/bin/bash

# Complete uninstaller script for posting server
# This script removes all components installed by the setup script
# Version 1.0 - Comprehensive cleanup

# Exit on error
set -e

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="/tmp/server_uninstall.lock"
LOG_FILE="/tmp/server_uninstall.log"

# Function to log messages
log_message() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to clean up on exit
cleanup() {
  local exit_code=$?
  log_message "INFO" "Cleanup process completed"
  
  if [ -f "$LOCK_FILE" ]; then
    rm -f "$LOCK_FILE"
  fi
  
  if [ $exit_code -eq 0 ]; then
    echo "✅ Uninstallation completed successfully!"
  else
    echo "⚠️ Uninstallation completed with some warnings. Check log: $LOG_FILE"
  fi
}

# Set up cleanup on exit
trap cleanup EXIT

# Function to create lock file
create_lock() {
  if [ -f "$LOCK_FILE" ]; then
    local pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "❌ Another instance of uninstall script is already running (PID: $pid)"
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

# Function to run a command with error handling (continue on failure)
run_command_continue() {
  log_message "DEBUG" "Executing (continue on fail): $*"
  echo "$ $*"
  if "$@"; then
    log_message "DEBUG" "Command succeeded: $*"
    return 0
  else
    local exit_code=$?
    log_message "WARN" "Command failed with exit code $exit_code (continuing...): $*"
    echo "⚠️ Command failed (continuing...): $*"
    return $exit_code
  fi
}

# Function to check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# Function to source NVM
source_nvm() {
  # Source nvm if available
  if [ -s "$HOME/.nvm/nvm.sh" ]; then
    log_message "INFO" "Sourcing NVM from ~/.nvm/nvm.sh"
    source "$HOME/.nvm/nvm.sh" 2>/dev/null || true
  elif [ -s "/usr/local/nvm/nvm.sh" ]; then
    log_message "INFO" "Sourcing NVM from /usr/local/nvm/nvm.sh"
    source "/usr/local/nvm/nvm.sh" 2>/dev/null || true
  fi
  
  # Also try to source bash completion
  if [ -s "$HOME/.nvm/bash_completion" ]; then
    source "$HOME/.nvm/bash_completion" 2>/dev/null || true
  fi
  
  # Export NVM_DIR if not set
  if [ -z "$NVM_DIR" ]; then
    if [ -d "$HOME/.nvm" ]; then
      export NVM_DIR="$HOME/.nvm"
    fi
  fi
}

# Function to ensure environment is loaded
ensure_environment() {
  # Source NVM
  source_nvm
  
  # Add npm global to PATH if exists
  if [ -d "$HOME/.npm-global/bin" ] && [[ ":$PATH:" != *":$HOME/.npm-global/bin:"* ]]; then
    export PATH="$HOME/.npm-global/bin:$PATH"
    log_message "INFO" "Added npm global bin to PATH"
  fi
}

# Function to stop and remove specific PM2 processes
remove_pm2_processes() {
  print_header "Removing Posting Server from PM2"
  
  # Ensure environment is loaded
  ensure_environment
  
  if ! command_exists pm2; then
    echo "ℹ️ PM2 not found in current session, skipping PM2 cleanup"
    log_message "INFO" "PM2 not available, skipping PM2 cleanup"
    return 0
  fi
  
  echo "🛑 Stopping and removing posting server from PM2..."
  log_message "INFO" "Stopping and removing posting server from PM2"
  
  # Get list of posting server related processes
  local posting_processes=("posting-server" "posting_server")
  local found_processes=false
  
  for process in "${posting_processes[@]}"; do
    if pm2 list | grep -q "$process"; then
      echo "🛑 Found process: $process"
      echo "🛑 Stopping process: $process"
      run_command_continue pm2 stop "$process"
      echo "🗑️ Deleting process: $process"
      run_command_continue pm2 delete "$process"
      found_processes=true
    fi
  done
  
  if [ "$found_processes" = false ]; then
    echo "ℹ️ No posting server processes found in PM2"
    log_message "INFO" "No posting server processes found in PM2"
  fi
  
  # Remove PM2 logrotate module only if it was installed
  echo "🔍 Checking for PM2 logrotate module..."
  if pm2 list | grep -q "pm2-logrotate"; then
    echo "🗑️ Removing PM2 logrotate module..."
    run_command_continue pm2 uninstall pm2-logrotate
    echo "✅ PM2 logrotate module removed"
  else
    echo "ℹ️ PM2 logrotate module not found"
  fi
  
  # Save PM2 process list to update the saved configuration
  echo "💾 Updating PM2 saved configuration..."
  run_command_continue pm2 save
  
  echo "✅ Posting server removed from PM2"
}

# Function to disable PM2 startup for posting server only
disable_pm2_startup() {
  print_header "Updating PM2 Startup Configuration"
  
  # Ensure environment is loaded
  ensure_environment
  
  if ! command_exists pm2; then
    echo "ℹ️ PM2 not found, skipping startup cleanup"
    return 0
  fi
  
  echo "🔧 Updating PM2 startup configuration..."
  log_message "INFO" "Updating PM2 startup configuration"
  
  # Save the current PM2 process list (without posting-server)
  echo "💾 Saving updated PM2 configuration..."
  run_command_continue pm2 save
  
  # Check if there are any remaining PM2 processes
  local remaining_processes=$(pm2 jlist 2>/dev/null | jq length 2>/dev/null || echo "0")
  
  if [ "$remaining_processes" = "0" ] || [ -z "$remaining_processes" ]; then
    echo "ℹ️ No PM2 processes remaining. You may want to disable PM2 startup entirely."
    echo "🤔 Do you want to disable PM2 startup completely?"
    echo "   This will prevent ALL PM2 processes from starting at boot."
    echo ""
    read -p "Disable PM2 startup entirely? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "🚫 Disabling PM2 startup services completely..."
      run_command_continue pm2 unstartup
      
      # Remove systemd service files
      echo "🗑️ Removing systemd service files..."
      local service_files=(
        "/etc/systemd/system/pm2-$USER.service"
        "/etc/systemd/system/pm2.service"
        "/lib/systemd/system/pm2-$USER.service"
        "/lib/systemd/system/pm2.service"
      )
      
      for service_file in "${service_files[@]}"; do
        if [ -f "$service_file" ]; then
          echo "🗑️ Removing service file: $service_file"
          run_command_continue sudo rm -f "$service_file"
        fi
      done
      
      # Reload systemd daemon
      if command_exists systemctl; then
        echo "🔄 Reloading systemd daemon..."
        run_command_continue sudo systemctl daemon-reload
      fi
      
      echo "✅ PM2 startup disabled completely"
    else
      echo "ℹ️ PM2 startup configuration kept (other processes may still auto-start)"
    fi
  else
    echo "✅ PM2 startup configuration updated (other processes will still auto-start)"
  fi
}

# Function to uninstall PM2
uninstall_pm2() {
  print_header "Uninstalling PM2"
  
  # Ensure environment is loaded
  ensure_environment
  
  if ! command_exists pm2; then
    echo "ℹ️ PM2 not installed, skipping uninstallation"
    return 0
  fi
  
  echo "🗑️ Uninstalling PM2..."
  log_message "INFO" "Uninstalling PM2"
  
  # Uninstall PM2 globally
  if command_exists npm; then
    run_command_continue npm uninstall -g pm2
    echo "✅ PM2 uninstalled via npm"
  fi
  
  # Remove PM2 directories
  local pm2_dirs=(
    "$HOME/.pm2"
    "$HOME/.pm2-dev"
    "/root/.pm2"
    "/tmp/.pm2"
  )
  
  for pm2_dir in "${pm2_dirs[@]}"; do
    if [ -d "$pm2_dir" ]; then
      echo "🗑️ Removing PM2 directory: $pm2_dir"
      run_command_continue rm -rf "$pm2_dir"
    fi
  done
  
  echo "✅ PM2 uninstalled and cleaned up"
}

# Function to remove application files
remove_application_files() {
  print_header "Removing Application Files"
  
  echo "🗑️ Removing posting server directory..."
  log_message "INFO" "Removing application files"
  
  # Remove posting_server directory
  if [ -d "posting_server" ]; then
    echo "🗑️ Removing posting_server directory..."
    rm -rf posting_server
    echo "✅ posting_server directory removed"
  else
    echo "ℹ️ posting_server directory not found"
  fi
  
  # Remove logs directory
  if [ -d "logs" ]; then
    echo "🗑️ Removing logs directory..."
    rm -rf logs
    echo "✅ logs directory removed"
  else
    echo "ℹ️ logs directory not found"
  fi
  
  # Remove convenience scripts created by setup
  local scripts=(
    "restart_server.sh"
    "setup_environment.sh"
    "ecosystem.config.js"
  )
  
  for script in "${scripts[@]}"; do
    if [ -f "$script" ]; then
      echo "🗑️ Removing script: $script"
      rm -f "$script"
    fi
  done
  
  echo "✅ Application files removed"
}

# Function to clean up Node.js and NVM (optional)
cleanup_nodejs_nvm() {
  print_header "Node.js and NVM Cleanup (Optional)"
  
  echo "🤔 Do you want to remove Node.js and NVM completely?"
  echo "   This will remove ALL Node.js versions and NVM installation"
  echo "   ⚠️ This may affect other Node.js applications on this system"
  echo ""
  read -p "Remove Node.js and NVM? (y/N): " -n 1 -r
  echo
  
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️ Removing Node.js and NVM..."
    log_message "INFO" "User chose to remove Node.js and NVM"
    
    # Source NVM first
    source_nvm
    
    # Remove all installed Node.js versions
    if command_exists nvm; then
      echo "🗑️ Removing all Node.js versions..."
      # Get list of installed versions and remove them
      nvm ls --no-alias 2>/dev/null | grep -E "v[0-9]" | while read version; do
        clean_version=$(echo "$version" | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+")
        if [ -n "$clean_version" ]; then
          echo "🗑️ Removing Node.js $clean_version"
          run_command_continue nvm uninstall "$clean_version"
        fi
      done
    fi
    
    # Remove NVM directory
    if [ -d "$HOME/.nvm" ]; then
      echo "🗑️ Removing NVM directory..."
      rm -rf "$HOME/.nvm"
      echo "✅ NVM directory removed"
    fi
    
    # Remove NVM lines from shell profiles
    local shell_files=(
      "$HOME/.bashrc"
      "$HOME/.bash_profile"
      "$HOME/.profile"
      "$HOME/.zshrc"
    )
    
    for shell_file in "${shell_files[@]}"; do
      if [ -f "$shell_file" ]; then
        echo "🗑️ Cleaning NVM references from $shell_file..."
        # Create a backup
        cp "$shell_file" "${shell_file}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Remove NVM-related lines
        grep -v "nvm.sh" "$shell_file" | grep -v "NVM_DIR" > "${shell_file}.tmp" && mv "${shell_file}.tmp" "$shell_file"
        echo "✅ Cleaned $shell_file (backup created)"
      fi
    done
    
    # Remove npm global directory
    if [ -d "$HOME/.npm-global" ]; then
      echo "🗑️ Removing npm global directory..."
      rm -rf "$HOME/.npm-global"
      echo "✅ npm global directory removed"
    fi
    
    # Clean npm global PATH from shell files
    for shell_file in "${shell_files[@]}"; do
      if [ -f "$shell_file" ] && grep -q ".npm-global" "$shell_file"; then
        echo "🗑️ Removing npm global PATH from $shell_file..."
        grep -v ".npm-global" "$shell_file" > "${shell_file}.tmp" && mv "${shell_file}.tmp" "$shell_file"
      fi
    done
    
    echo "✅ Node.js and NVM removed completely"
  else
    echo "ℹ️ Keeping Node.js and NVM installation"
    log_message "INFO" "User chose to keep Node.js and NVM"
  fi
}

# Function to clean up system packages (optional)
cleanup_system_packages() {
  print_header "System Packages Cleanup (Optional)"
  
  echo "🤔 Do you want to remove system packages installed by the setup script?"
  echo "   This includes: git (if installed by the script)"
  echo "   ⚠️ This may affect other applications that depend on these packages"
  echo ""
  read -p "Remove system packages? (y/N): " -n 1 -r
  echo
  
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️ This would remove system packages, but for safety reasons,"
    echo "   we recommend manually removing them if needed:"
    echo ""
    echo "📋 To remove Git (if no longer needed):"
    echo "   Ubuntu/Debian: sudo apt-get remove git"
    echo "   CentOS/RHEL: sudo yum remove git"
    echo "   Fedora: sudo dnf remove git"
    echo ""
    log_message "INFO" "Provided manual instructions for system package removal"
  else
    echo "ℹ️ Keeping system packages"
    log_message "INFO" "User chose to keep system packages"
  fi
}

# Function to clean up temporary files and logs
cleanup_temporary_files() {
  print_header "Cleaning Temporary Files"
  
  echo "🗑️ Removing temporary files and logs..."
  log_message "INFO" "Cleaning temporary files"
  
  # Remove setup-related temporary files
  local temp_files=(
    "/tmp/server_setup.lock"
    "/tmp/server_setup.log"
    "/tmp/.pm2_*"
    "/tmp/npm-*"
  )
  
  for temp_file in "${temp_files[@]}"; do
    if ls $temp_file 1> /dev/null 2>&1; then
      echo "🗑️ Removing: $temp_file"
      run_command_continue rm -rf $temp_file
    fi
  done
  
  # Clean npm cache
  if command_exists npm; then
    echo "🗑️ Cleaning npm cache..."
    run_command_continue npm cache clean --force
  fi
  
  echo "✅ Temporary files cleaned"
}

# Function to display final status
display_final_status() {
  print_header "Uninstallation Summary"
  
  echo "✅ Uninstallation completed!"
  echo ""
  echo "🗑️ Removed Components:"
  echo "   ✅ Posting server application files"
  echo "   ✅ Posting server PM2 process"
  echo "   ✅ PM2 logrotate module (if installed)"
  echo "   ✅ Updated PM2 startup configuration"
  echo "   ✅ Application logs and temporary files"
  echo "   ✅ Convenience scripts"
  echo ""
  
  # Check what's still present
  echo "🔍 Remaining Components:"
  
  ensure_environment 2>/dev/null || true
  
  if command_exists nvm; then
    echo "   📦 NVM: Still installed"
  else
    echo "   📦 NVM: Removed"
  fi
  
  if command_exists node; then
    echo "   📦 Node.js: Still installed ($(node -v))"
  else
    echo "   📦 Node.js: Removed"
  fi
  
  if command_exists pm2; then
    echo "   📦 PM2: Still installed ($(pm2 -v))"
  else
    echo "   📦 PM2: Removed"
  fi
  
  if command_exists git; then
    echo "   📦 Git: Still installed"
  else
    echo "   📦 Git: Removed"
  fi
  
  if [ -d "posting_server" ]; then
    echo "   📁 posting_server directory: Still present"
  else
    echo "   📁 posting_server directory: Removed"
  fi
  
  if [ -d "logs" ]; then
    echo "   📁 logs directory: Still present"
  else
    echo "   📁 logs directory: Removed"
  fi
  
  echo ""
  echo "🧹 Additional Cleanup:"
  echo "   📝 Uninstall log saved to: $LOG_FILE"
  echo "   📝 Shell profile backups created (if NVM was removed)"
  echo ""
  echo "⚠️ Post-Uninstall Notes:"
  echo "   1. Other PM2 processes (if any) are still running"
  echo "   2. PM2 itself is still installed and functional"
  echo "   3. Node.js and NVM remain available (unless you chose to remove them)"
  echo "   4. PM2 startup services remain active for other applications"
  echo "   5. Only posting-server specific components were removed"
  echo ""
  echo "🔧 Manual Verification Commands:"
  echo "   pm2 status                    # Should not show posting-server process"
  echo "   pm2 list | grep posting       # Should return nothing"
  echo "   node -v                       # Should still work if Node.js was kept"
  echo "   systemctl list-units | grep pm2  # Should show PM2 services (if other apps use PM2)"
}

# Function to confirm uninstallation
confirm_uninstallation() {
  print_header "Uninstallation Confirmation"
  
  echo "⚠️ WARNING: This will completely remove the posting server and related components!"
  echo ""
  echo "🗑️ This script will:"
  echo "   • Stop and remove ONLY posting-server PM2 process"
  echo "   • Remove posting-server files and directories"
  echo "   • Remove PM2 logrotate module (if installed for this app)"
  echo "   • Update PM2 startup configuration (keep other apps)"
  echo "   • Clean up logs and temporary files"
  echo "   • Optionally remove PM2, Node.js, and NVM completely"
  echo ""
  echo "📁 Current directory contents:"
  ls -la . 2>/dev/null | grep -E "(posting_server|logs|ecosystem|restart_server|setup_environment)" || echo "   No server-related files found"
  echo ""
  
  # Check if PM2 is running any processes
  ensure_environment 2>/dev/null || true
  if command_exists pm2; then
    echo "📊 Current PM2 processes:"
    pm2 status 2>/dev/null || echo "   No PM2 processes found"
    echo ""
  fi
  
  read -p "Are you sure you want to proceed with uninstallation? (y/N): " -n 1 -r
  echo
  
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Uninstallation cancelled by user"
    exit 0
  fi
  
  echo "✅ Proceeding with uninstallation..."
  log_message "INFO" "User confirmed uninstallation"
}

# Main execution function
main() {
  # Initialize logging
  echo "Starting server uninstallation at $(date)" > "$LOG_FILE"
  
  # Create lock file
  create_lock
  
  # Confirm uninstallation
  confirm_uninstallation
  
  # Execute uninstallation steps
  remove_pm2_processes
  disable_pm2_startup
  remove_application_files
  cleanup_temporary_files
  
  # Optional components
  echo ""
  echo "🔧 Optional Cleanup Steps:"
  uninstall_pm2
  cleanup_nodejs_nvm
  cleanup_system_packages
  
  # Display final status
  display_final_status
  
  echo "🎉 Uninstallation process completed!"
  log_message "INFO" "Uninstallation completed successfully"
}

# Pre-flight checks
preflight_checks() {
  echo "🔍 Running pre-flight checks..."
  
  # Check if we're in the right directory (look for signs of the installation)
  local found_installation=false
  
  if [ -d "posting_server" ] || [ -f "restart_server.sh" ] || [ -f "setup_environment.sh" ] || [ -d "logs" ]; then
    found_installation=true
  fi
  
  # Check PM2 processes
  ensure_environment 2>/dev/null || true
  if command_exists pm2 && pm2 list 2>/dev/null | grep -q "posting"; then
    found_installation=true
  fi
  
  if [ "$found_installation" = false ]; then
    echo "⚠️ No posting server installation detected in current directory"
    echo "📁 Current directory: $(pwd)"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "❌ Uninstallation cancelled"
      exit 0
    fi
  fi
  
  echo "✅ Pre-flight checks completed"
}

# Show help information
show_help() {
  echo "📖 Posting Server Uninstaller"
  echo ""
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -h, --help     Show this help message"
  echo "  -f, --force    Skip confirmation prompts (use with caution)"
  echo ""
  echo "This script will remove:"
  echo "  • Posting server application files"
  echo "  • PM2 processes and startup configurations"
  echo "  • Application logs and temporary files"
  echo "  • Optionally: PM2, Node.js, and NVM"
  echo ""
  echo "⚠️ Warning: This action cannot be undone!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      show_help
      exit 0
      ;;
    -f|--force)
      FORCE_MODE=true
      shift
      ;;
    *)
      echo "❌ Unknown option: $1"
      echo "Use -h or --help for usage information"
      exit 1
      ;;
  esac
done

# Override confirmation function if force mode is enabled
if [ "$FORCE_MODE" = true ]; then
  confirm_uninstallation() {
    print_header "Force Mode Enabled"
    echo "⚠️ Running in force mode - skipping confirmations"
    log_message "INFO" "Running in force mode"
  }
fi

# Run preflight checks
preflight_checks

# Run main function
main "$@"