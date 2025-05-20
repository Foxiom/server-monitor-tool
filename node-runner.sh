#!/bin/bash

# Exit on error
set -e

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
  echo "❌ Node.js is not installed. Please install Node.js first."
  exit 1
fi

# Create app directory
mkdir -p monitor-tool && cd monitor-tool

# Download server.js
echo "⬇️ Downloading server.js..."
curl -o server.js https://raw.githubusercontent.com/your-username/your-repo-name/main/server.js

# Download package.json (optional)
if curl --output package.json --silent --head --fail https://raw.githubusercontent.com/your-username/your-repo-name/main/package.json; then
  echo "⬇️ Downloading package.json..."
  curl -o package.json https://raw.githubusercontent.com/your-username/your-repo-name/main/package.json
  echo "📦 Installing dependencies..."
  npm install
fi

# Run the server
echo "🚀 Starting server..."
node server.js
