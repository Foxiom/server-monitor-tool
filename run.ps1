# Exit on error
$ErrorActionPreference = "Stop"

# Configure TLS 1.2 for compatibility with all Windows versions
Write-Host "🔒 Configuring TLS 1.2 for secure connections..."
try {
    # Force TLS 1.2 for all web requests
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host "✅ TLS 1.2 configured successfully"
} catch {
    Write-Host "⚠️ Failed to configure TLS 1.2: $($_.Exception.Message)"
    Write-Host "⚠️ This may cause issues with secure downloads. Continuing anyway..."
}

# Function to clean up on error
function Cleanup {
    if (Test-Path "posting_server") {
        Write-Host "❌ An error occurred. Cleaning up..."
        Remove-Item -Recurse -Force "posting_server" -ErrorAction SilentlyContinue
    }
    if ($env:TEMP_DIR -and (Test-Path $env:TEMP_DIR)) {
        Remove-Item -Recurse -Force $env:TEMP_DIR -ErrorAction SilentlyContinue
    }
    exit 1
}

# Set up error handling
$Global:ErrorActionPreference = "Stop"
trap { Cleanup }

# Function to check if a command exists
function Command-Exists {
    param ($command)
    return Get-Command $command -ErrorAction SilentlyContinue
}

# Function to check if Chocolatey is installed
function Test-Chocolatey {
    return (Command-Exists choco)
}

# Function to install Chocolatey
function Install-Chocolatey {
    Write-Host "📦 Installing Chocolatey..."
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        # Force TLS 1.2 explicitly for Chocolatey installation
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "✅ Chocolatey installed successfully"
    } catch {
        Write-Host "❌ Failed to install Chocolatey: $($_.Exception.Message)"
        exit 1
    }
}

# Function to ensure Chocolatey is available
function Ensure-Chocolatey {
    if (-not (Test-Chocolatey)) {
        Write-Host "❌ Chocolatey is not installed. Installing now..."
        Install-Chocolatey
    } else {
        Write-Host "✅ Chocolatey is already installed"
    }
}

# Function to install Node.js using Chocolatey (LTS version for stability)
function Install-NodeJs {
    Write-Host "📦 Installing Node.js LTS using Chocolatey..."
    try {
        # Install specific LTS version for better PM2 compatibility
        choco install nodejs-lts -y -s https://community.chocolatey.org/api/v2/
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "✅ Node.js LTS installed successfully"
    } catch {
        Write-Host "❌ Failed to install Node.js: $($_.Exception.Message)"
        exit 1
    }
}

# Function to install Git using Chocolatey (latest stable version)
function Install-Git {
    Write-Host "📦 Installing the latest stable Git using Chocolatey..."
    try {
        choco install git -y -s https://community.chocolatey.org/api/v2/
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "✅ Git installed successfully"
    } catch {
        Write-Host "❌ Failed to install Git: $($_.Exception.Message)"
        exit 1
    }
}

# Function to safely manage posting-server PM2 process only
function Manage-PostingServerProcess {
    Write-Host "🔧 Managing posting-server PM2 process..."
    
    if (-not (Command-Exists pm2)) {
        Write-Host "📦 Installing PM2..."
        try {
            npm install -g pm2@latest
            Write-Host "✅ PM2 installed successfully"
            
            # Verify PM2 installation
            $pm2Version = & pm2 --version
            Write-Host "📋 PM2 version: $pm2Version"
        } catch {
            Write-Host "❌ Failed to install PM2: $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "✅ PM2 is already installed"
        $pm2Version = & pm2 --version
        Write-Host "📋 PM2 version: $pm2Version"
    }
    
    try {
        # Initialize PM2 daemon if needed
        pm2 ping | Out-Null
        
        # Check if posting-server process exists and remove it safely
        Write-Host "🔍 Checking for existing posting-server process..."
        $existingProcess = $null
        
        # Use pm2 describe to check if process exists (safer than jlist)
        try {
            $processInfo = & pm2 describe posting-server 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "⚠️ Found existing posting-server process. Stopping and removing it..."
                pm2 delete posting-server
                Write-Host "✅ Existing posting-server process removed"
            } else {
                Write-Host "ℹ️ No existing posting-server process found"
            }
        } catch {
            Write-Host "ℹ️ No existing posting-server process found"
        }
        
    } catch {
        Write-Host "⚠️ Error managing PM2 processes: $($_.Exception.Message)"
        Write-Host "ℹ️ Continuing with fresh PM2 setup..."
    }
}

# Ensure Chocolatey is installed
Ensure-Chocolatey

# Check and install Node.js if not present or if version is incompatible
$nodeInstalled = $false
if (Command-Exists node) {
    try {
        $nodeVersion = & node --version
        Write-Host "📋 Current Node.js version: $nodeVersion"
        
        # Check if it's a supported version (v14+)
        $versionNumber = [int]($nodeVersion -replace 'v(\d+).*', '$1')
        if ($versionNumber -ge 14) {
            $nodeInstalled = $true
            Write-Host "✅ Node.js version is compatible"
        } else {
            Write-Host "⚠️ Node.js version is too old, updating..."
        }
    } catch {
        Write-Host "⚠️ Could not determine Node.js version, reinstalling..."
    }
}

if (-not $nodeInstalled) {
    Write-Host "❌ Node.js is not installed or incompatible."
    Install-NodeJs
}

# Check and install Git if not present
if (-not (Command-Exists git)) {
    Write-Host "❌ Git is not installed."
    Install-Git
}

# Safely manage posting-server PM2 process only
Manage-PostingServerProcess

# Remove existing posting_server directory if it exists, at any cost
if (Test-Path "posting_server") {
    Write-Host "🗑️  Forcibly removing existing posting_server directory..."
    try {
        # Stop only posting-server PM2 process if it exists
        if (Command-Exists pm2) {
            try {
                pm2 delete posting-server 2>$null
            } catch {
                # Ignore errors if process doesn't exist
            }
        }

        # Kill any Node.js processes that might be using the directory
        Get-Process | Where-Object { $_.Path -like "*\posting_server\*" } | Stop-Process -Force -ErrorAction SilentlyContinue

        # Take ownership of the directory and its contents
        takeown /F "posting_server" /R /D Y
        icacls "posting_server" /grant "$($env:USERNAME):F" /T

        # Forcefully remove the directory, ignoring errors
        Remove-Item -Recurse -Force "posting_server" -ErrorAction SilentlyContinue

        # Use cmd to attempt deletion if PowerShell fails
        if (Test-Path "posting_server") {
            cmd /c "rd /s /q posting_server"
        }

        # Verify removal
        if (-not (Test-Path "posting_server")) {
            Write-Host "✅ Successfully removed posting_server directory."
        } else {
            Write-Host "⚠️ Unable to remove posting_server directory. Manual intervention required." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "❌ Error during removal: $_" -ForegroundColor Red
    }
}

# Create logs directory if it doesn't exist
New-Item -ItemType Directory -Force -Path "logs"

# Setup posting server
Write-Host "🔧 Setting up posting server..."

# Clone the repository to a temporary directory (shallow clone for efficiency)
Write-Host "⬇️ Downloading complete posting server from GitHub..."
$env:TEMP_DIR = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
New-Item -ItemType Directory -Path $env:TEMP_DIR

# Ensure TLS 1.2 is set before Git operations
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Try Git clone with multiple attempts and fallback methods
$maxAttempts = 3
$attempt = 1
$cloneSuccess = $false

while (-not $cloneSuccess -and $attempt -le $maxAttempts) {
    Write-Host "Attempt $attempt of $maxAttempts to clone repository..."
    
    try {
        # First try standard git clone
        git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git $env:TEMP_DIR
        $cloneSuccess = $true
        Write-Host "✅ Repository cloned successfully"
    } catch {
        if ($attempt -lt $maxAttempts) {
            Write-Host "⚠️ Clone failed: $($_.Exception.Message). Retrying with alternate method..."
            
            # On failure, try with different git config
            if ($attempt -eq 2) {
                # Try with PowerShell direct download as last resort
                try {
                    $zipUrl = "https://github.com/Foxiom/server-monitor-tool/archive/main.zip"
                    $zipPath = "$env:TEMP\server-monitor-tool.zip"
                    
                    Write-Host "Attempting direct download from $zipUrl"
                    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
                    
                    # Extract ZIP file
                    Write-Host "Extracting ZIP file..."
                    Expand-Archive -Path $zipPath -DestinationPath $env:TEMP -Force
                    
                    # Copy contents to temp directory
                    Copy-Item -Path "$env:TEMP\server-monitor-tool-main\*" -Destination $env:TEMP_DIR -Recurse -Force
                    
                    # Clean up
                    Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path "$env:TEMP\server-monitor-tool-main" -Recurse -Force -ErrorAction SilentlyContinue
                    
                    $cloneSuccess = $true
                    Write-Host "✅ Repository downloaded successfully via direct download"
                    break
                } catch {
                    Write-Host "⚠️ Direct download failed: $($_.Exception.Message)"
                }
            }
        } else {
            Write-Host "❌ Failed to clone repository after $maxAttempts attempts: $($_.Exception.Message)" -ForegroundColor Red
            Cleanup
        }
    }
    $attempt++
}

# Copy only the posting_server folder to our target location
Copy-Item -Recurse "$env:TEMP_DIR\posting_server" -Destination "."

# Clean up temporary directory
Remove-Item -Recurse -Force $env:TEMP_DIR
$env:TEMP_DIR = $null

# Navigate to posting_server directory
Set-Location posting_server

# Install posting server dependencies with clean install
Write-Host "📦 Installing posting server dependencies..."
try {
    # Clear any existing node_modules
    if (Test-Path "node_modules") {
        Remove-Item -Path "node_modules" -Recurse -Force
    }
    
    # Install dependencies
    npm install --no-optional --no-audit
    Write-Host "✅ Dependencies installed successfully"
} catch {
    Write-Host "❌ Failed to install dependencies: $($_.Exception.Message)"
    exit 1
}

# Set posting server permissions
Write-Host "🔒 Setting up permissions..."
icacls "." /grant "Everyone:(OI)(CI)F" /Q
Get-ChildItem -Filter "*.js" | ForEach-Object { icacls $_.Name /grant "Everyone:R" /Q }
Get-ChildItem -Filter "*.json" | ForEach-Object { icacls $_.Name /grant "Everyone:R" /Q }
Get-ChildItem -Directory | ForEach-Object { icacls $_.Name /grant "Everyone:(OI)(CI)F" /Q }
icacls "..\logs" /grant "Everyone:(OI)(CI)F" /Q

# Start the server using PM2 with better error handling
Write-Host "🚀 Setting up posting server with PM2..."

try {
    # Initialize PM2 if needed
    pm2 ping | Out-Null
    
    Write-Host "🆕 Starting new PM2 process 'posting-server'..."
    pm2 start server.js --name "posting-server" --log ..\logs\posting-server.log --exp-backoff-restart-delay=100
    Write-Host "✅ Process 'posting-server' started successfully"

    # Save PM2 process list (only saves current user processes)
    Write-Host "💾 Saving PM2 process list..."
    pm2 save
    
} catch {
    Write-Host "❌ Failed to start server with PM2: $($_.Exception.Message)"
    Write-Host "🔍 Trying to diagnose the issue..."
    
    # Show PM2 logs for debugging
    Write-Host "📋 PM2 Status:"
    pm2 status
    
    Write-Host "📋 Recent PM2 logs:"
    pm2 logs --lines 10
    
    exit 1
}

# Go back to parent directory for auto-start setup
Set-Location ..

# Create a more robust startup script
Write-Host "🔧 Setting up auto-start mechanism..."

$currentDir = Get-Location
$startupScript = Join-Path $currentDir "pm2-autostart.bat"
$startupScriptContent = @"
@echo off
title PM2 AutoStart Service - Posting Server
echo Starting PM2 Auto-Start Service for Posting Server...

REM Set working directory
cd /d "$currentDir"

REM Create logs directory if it doesn't exist
if not exist "logs" mkdir "logs"

REM Log startup attempt
echo %DATE% %TIME% - Auto-start service initiated >> "logs\autostart.log"

REM Wait for system to fully boot
timeout /t 15 /nobreak > nul

REM Set Node.js paths explicitly
set PATH=%PATH%;C:\Program Files\nodejs;%USERPROFILE%\AppData\Roaming\npm

REM Check if PM2 is available
where pm2 >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo %DATE% %TIME% - PM2 not found in PATH >> "logs\autostart.log"
    echo PM2 not found, please check installation
    timeout /t 10 /nobreak > nul
    goto :end
)

echo %DATE% %TIME% - PM2 found, proceeding with startup >> "logs\autostart.log"

REM Initialize PM2 daemon
pm2 ping >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo %DATE% %TIME% - PM2 daemon not responding, attempting restart >> "logs\autostart.log"
)

REM Check if posting-server is already running
pm2 describe posting-server >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo %DATE% %TIME% - Posting server already exists, restarting >> "logs\autostart.log"
    pm2 restart posting-server >> "logs\autostart.log" 2>&1
) else (
    echo %DATE% %TIME% - Posting server not found, starting fresh >> "logs\autostart.log"
    
    REM Navigate to posting_server directory and start
    if exist "posting_server\server.js" (
        pm2 start posting_server\server.js --name "posting-server" --log logs\posting-server.log --exp-backoff-restart-delay=100 >> "logs\autostart.log" 2>&1
        echo %DATE% %TIME% - Posting server started successfully >> "logs\autostart.log"
    ) else (
        echo %DATE% %TIME% - ERROR: posting_server\server.js not found >> "logs\autostart.log"
        goto :end
    )
)

REM Wait for process to stabilize
timeout /t 5 /nobreak > nul

REM Save PM2 configuration
pm2 save >> "logs\autostart.log" 2>&1

REM Final status check
pm2 describe posting-server >> "logs\autostart.log" 2>&1
if %ERRORLEVEL% EQU 0 (
    echo %DATE% %TIME% - Posting server auto-start completed successfully >> "logs\autostart.log"
) else (
    echo %DATE% %TIME% - WARNING: Posting server may not be running properly >> "logs\autostart.log"
)

:end
echo %DATE% %TIME% - Auto-start service completed >> "logs\autostart.log"
"@

Set-Content -Path $startupScript -Value $startupScriptContent -Encoding ASCII

# Set up registry run key for auto-start
try {
    Write-Host "🔧 Setting up auto-start registry entry..."
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $regName = "PM2PostingServerAutoStart"
    
    # Remove existing entry
    Remove-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
    
    # Add new entry
    Set-ItemProperty -Path $regPath -Name $regName -Value "`"$startupScript`""
    
    Write-Host "✅ Auto-start configured successfully!"
} catch {
    Write-Host "⚠️ Failed to configure auto-start: $($_.Exception.Message)"
}

# Navigate back to posting_server directory for final verification
Set-Location posting_server

# Verify if the server is running using safer method
Write-Host "🔍 Verifying server status..."
try {
    # Use pm2 describe instead of jlist to avoid JSON parsing issues
    $processCheck = & pm2 describe posting-server 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Posting server is running!" -ForegroundColor Green
        
        # Get basic status info using pm2 status
        Write-Host "📋 Server status:"
        pm2 status posting-server
    } else {
        Write-Host "⚠️ Posting server is not running. Attempting to start..."
        pm2 start server.js --name "posting-server" --log ..\logs\posting-server.log
        Start-Sleep -Seconds 5
        
        $processCheck = & pm2 describe posting-server 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Posting server started successfully!"
            pm2 status posting-server
        } else {
            Write-Host "❌ Failed to start posting server. Check logs with 'pm2 logs posting-server'." -ForegroundColor Red
        }
    }
} catch {
    Write-Host "❌ Error checking server status: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "ℹ️ Try running 'pm2 status' manually to check PM2 processes"
}

# Go back to parent directory for final output
Set-Location ..

Write-Host ""
Write-Host "✅ Server setup completed!" -ForegroundColor Green
Write-Host ""
Write-Host "🔧 Troubleshooting Commands:" -ForegroundColor Yellow
Write-Host "   pm2 status                     # Check all PM2 processes"
Write-Host "   pm2 describe posting-server    # Detailed info for posting-server"
Write-Host "   pm2 logs posting-server        # View server logs"
Write-Host "   pm2 restart posting-server     # Restart only posting-server"
Write-Host "   pm2 delete posting-server      # Remove only posting-server"
Write-Host "   node --version                 # Check Node.js version"
Write-Host "   pm2 --version                  # Check PM2 version"
Write-Host ""
Write-Host "📊 Log files:" -ForegroundColor Cyan
Write-Host "   - Auto-start: .\logs\autostart.log"
Write-Host "   - Server: .\logs\posting-server.log"
Write-Host ""
Write-Host "🎉 Setup complete! Only posting-server will auto-start on boot." -ForegroundColor Green
Write-Host "ℹ️ Other PM2 applications remain unaffected." -ForegroundColor Cyan