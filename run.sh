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

# Run the server
echo "🚀 Starting server..."
node server.js
