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

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
  echo "❌ Node.js is not installed. Please install Node.js first."
  exit 1
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

# Download server.js
echo "⬇️ Downloading server.js..."
curl -H "Cache-Control: no-cache" -o server.js "https://raw.githubusercontent.com/Foxiom/server-monitor-tool/main/server.js?t=$TIMESTAMP"

# Download package.json (optional)
if curl -H "Cache-Control: no-cache" --output package.json --silent --head --fail "https://raw.githubusercontent.com/Foxiom/server-monitor-tool/main/package.json?t=$TIMESTAMP"; then
  echo "⬇️ Downloading package.json..."
  curl -H "Cache-Control: no-cache" -o package.json "https://raw.githubusercontent.com/Foxiom/server-monitor-tool/main/package.json?t=$TIMESTAMP"
  echo "📦 Installing dependencies..."
  npm install
fi

# Run the server
echo "🚀 Starting server..."
node server.js
