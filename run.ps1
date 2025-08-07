# Exit on error
$ErrorActionPreference = "Stop"

# Function to perform aggressive cleanup
function Remove-PostingServerCompletely {
    param([string]$DirectoryPath = "posting_server")
    
    Write-Host "🧹 Starting aggressive cleanup of $DirectoryPath..."
    
    # Step 1: Kill all Node.js processes
    Write-Host "🛑 Killing all Node.js processes..."
    try {
        Get-Process -Name "node" -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "  Killing Node.js process: $($_.Id)"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
    } catch {
        Write-Host "⚠️ Some Node.js processes could not be killed: $($_.Exception.Message)"
    }
    
    # Step 2: Stop only posting-server PM2 process (preserve others)
    if (Get-Command pm2 -ErrorAction SilentlyContinue) {
        Write-Host "🛑 Stopping posting-server PM2 process only..."
        try {
            # Check if posting-server exists and remove only it
            $postingServerExists = & pm2 describe posting-server 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Deleting posting-server PM2 process..."
                pm2 delete posting-server 2>$null | Out-Null
                pm2 save 2>$null | Out-Null  # Save updated process list
                Write-Host "✅ posting-server PM2 process removed"
            } else {
                Write-Host "ℹ️ No posting-server PM2 process found"
            }
            
            Start-Sleep -Seconds 2
        } catch {
            Write-Host "⚠️ PM2 cleanup encountered errors: $($_.Exception.Message)"
            # Only as absolute last resort, kill PM2 daemon
            Write-Host "⚠️ Trying nuclear option as last resort..."
            try {
                pm2 kill 2>$null | Out-Null
                Write-Host "⚠️ PM2 daemon killed - other PM2 apps will need manual restart"
            } catch {}
        }
    }
    
    # Step 3: Kill processes using the directory
    if (Test-Path $DirectoryPath) {
        Write-Host "🔍 Finding processes using the directory..."
        
        # Try to use handle.exe if available
        try {
            if (Get-Command handle.exe -ErrorAction SilentlyContinue) {
                $handles = & handle.exe $DirectoryPath 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $handles | ForEach-Object {
                        if ($_ -match "pid:\s*(\d+)") {
                            $handlePid = $matches[1]
                            try {
                                Write-Host "  Killing process $handlePid with handle to $DirectoryPath"
                                Stop-Process -Id $handlePid -Force -ErrorAction SilentlyContinue
                            } catch {}
                        }
                    }
                }
            }
        } catch {}
        
        # Alternative: Kill any process with the directory in its path
        try {
            Get-Process | Where-Object { 
                try { 
                    $_.Path -and $_.Path -like "*$DirectoryPath*" 
                } catch { 
                    $false 
                }
            } | ForEach-Object {
                Write-Host "  Killing process with path containing $DirectoryPath : $($_.Id)"
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
        
        Start-Sleep -Seconds 3
    }
    
    # Step 4: Aggressive directory removal
    if (Test-Path $DirectoryPath) {
        Write-Host "🗑️ Attempting to remove directory: $DirectoryPath"
        
        try {
            # Take ownership
            Write-Host "  Taking ownership..."
            takeown /F $DirectoryPath /R /D Y 2>$null | Out-Null
            icacls $DirectoryPath /grant "$($env:USERNAME):F" /T /Q 2>$null | Out-Null
            
            # Method 1: PowerShell Remove-Item
            Write-Host "  Trying PowerShell Remove-Item..."
            Remove-Item -Recurse -Force $DirectoryPath -ErrorAction Stop
            Write-Host "✅ Directory removed successfully"
            return $true
            
        } catch {
            Write-Host "⚠️ PowerShell removal failed: $($_.Exception.Message)"
            
            # Method 2: CMD rd command
            try {
                Write-Host "  Trying CMD rd command..."
                cmd /c "rd /s /q `"$DirectoryPath`"" 2>$null
                if (-not (Test-Path $DirectoryPath)) {
                    Write-Host "✅ Directory removed with CMD"
                    return $true
                }
            } catch {}
            
            # Method 3: Robocopy nuclear option
            try {
                Write-Host "  Using robocopy nuclear option..."
                $emptyDir = Join-Path $env:TEMP "empty_$(Get-Random)"
                New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
                
                robocopy $emptyDir $DirectoryPath /MIR /R:0 /W:0 2>$null | Out-Null
                Remove-Item -Recurse -Force $DirectoryPath -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $emptyDir -ErrorAction SilentlyContinue
                
                if (-not (Test-Path $DirectoryPath)) {
                    Write-Host "✅ Directory removed with robocopy"
                    return $true
                }
            } catch {}
            
            Write-Host "❌ All removal methods failed"
            return $false
        }
    } else {
        Write-Host "ℹ️ Directory $DirectoryPath does not exist"
        return $true
    }
}

# Function to clean up on error (now defined globally)
function Invoke-ErrorCleanup {
    Write-Host "🧹 Starting error cleanup process..."
    
    try {
        # Go back to parent directory if we're in posting_server
        $currentPath = Get-Location
        if ($currentPath.Path -like "*posting_server*") {
            Write-Host "📂 Navigating back to parent directory..."
            Set-Location ..
        }
        
        # Remove posting_server directory
        Remove-PostingServerCompletely -DirectoryPath "posting_server" | Out-Null
        
        # Clean up temp directory if it exists
        if ($env:TEMP_DIR -and (Test-Path $env:TEMP_DIR)) {
            Write-Host "🗑️ Removing temporary directory..."
            Remove-Item -Recurse -Force $env:TEMP_DIR -ErrorAction SilentlyContinue
        }
        
        Write-Host "✅ Error cleanup completed"
    } catch {
        Write-Host "⚠️ Error cleanup encountered issues: $($_.Exception.Message)"
    }
    
    Write-Host "❌ Script execution failed. Check the error messages above for details."
    exit 1
}

# Set up error handling with proper function reference
trap { Invoke-ErrorCleanup }

Write-Host "🔍 Performing initial cleanup check..."

# Perform aggressive cleanup if directory exists
if (Test-Path "posting_server") {
    Write-Host "⚠️ Found existing posting_server directory. Performing aggressive cleanup..."
    
    $cleanupSuccess = Remove-PostingServerCompletely -DirectoryPath "posting_server"
    
    if (-not $cleanupSuccess) {
        Write-Host "❌ Could not remove existing posting_server directory" -ForegroundColor Red
        Write-Host "🔧 Manual steps required:" -ForegroundColor Yellow
        Write-Host "   1. Open Task Manager and kill any Node.js processes" -ForegroundColor Yellow
        Write-Host "   2. Run 'pm2 kill' to stop all PM2 processes" -ForegroundColor Yellow
        Write-Host "   3. Restart your computer if necessary" -ForegroundColor Yellow
        Write-Host "   4. Manually delete the posting_server folder" -ForegroundColor Yellow
        Write-Host "❌ Please resolve manually and re-run the script" -ForegroundColor Red
        exit 1
    }
}

# Configure TLS 1.2 for compatibility with all Windows versions
Write-Host "🔒 Configuring TLS 1.2 for secure connections..."
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host "✅ TLS 1.2 configured successfully"
} catch {
    Write-Host "⚠️ Failed to configure TLS 1.2: $($_.Exception.Message)"
    Write-Host "⚠️ This may cause issues with secure downloads. Continuing anyway..."
}

# Function to check if a command exists
function Test-CommandExists {
    param ($command)
    return Get-Command $command -ErrorAction SilentlyContinue
}

# Function to check if Chocolatey is installed
function Test-Chocolatey {
    return (Test-CommandExists choco)
}

# Function to install Chocolatey
function Install-Chocolatey {
    Write-Host "📦 Installing Chocolatey..."
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "✅ Chocolatey installed successfully"
    } catch {
        Write-Host "❌ Failed to install Chocolatey: $($_.Exception.Message)"
        throw
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

# Function to install Node.js using Chocolatey
function Install-NodeJs {
    Write-Host "📦 Installing Node.js LTS using Chocolatey..."
    try {
        choco install nodejs-lts -y
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "✅ Node.js LTS installed successfully"
    } catch {
        Write-Host "❌ Failed to install Node.js: $($_.Exception.Message)"
        throw
    }
}

# Function to install Git using Chocolatey
function Install-Git {
    Write-Host "📦 Installing Git using Chocolatey..."
    try {
        choco install git -y
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Host "✅ Git installed successfully"
    } catch {
        Write-Host "❌ Failed to install Git: $($_.Exception.Message)"
        throw
    }
}

# Ensure Chocolatey is installed
Ensure-Chocolatey

# Check and install Node.js if not present or if version is incompatible
$nodeInstalled = $false
if (Test-CommandExists node) {
    try {
        $nodeVersion = & node --version
        Write-Host "📋 Current Node.js version: $nodeVersion"
        
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
if (-not (Test-CommandExists git)) {
    Write-Host "❌ Git is not installed."
    Install-Git
}

# Install/Update PM2
Write-Host "📦 Installing/updating PM2..."
try {
    npm install -g pm2@latest
    Write-Host "✅ PM2 installed/updated successfully"
} catch {
    Write-Host "❌ Failed to install PM2: $($_.Exception.Message)"
    throw
}

# Create logs directory if it doesn't exist
New-Item -ItemType Directory -Force -Path "logs" | Out-Null

# Setup posting server
Write-Host "🔧 Setting up posting server..."

# Clone the repository to a temporary directory
Write-Host "⬇️ Downloading posting server from GitHub..."
$env:TEMP_DIR = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
New-Item -ItemType Directory -Path $env:TEMP_DIR | Out-Null

# Ensure TLS 1.2 is set before Git operations
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Try multiple download methods
$maxAttempts = 3
$attempt = 1
$downloadSuccess = $false

while (-not $downloadSuccess -and $attempt -le $maxAttempts) {
    Write-Host "Attempt $attempt of $maxAttempts to download repository..."
    
    try {
        if ($attempt -eq 1) {
            # Try Git clone first
            git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git $env:TEMP_DIR
        } else {
            # Try direct ZIP download
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
        }
        
        $downloadSuccess = $true
        Write-Host "✅ Repository downloaded successfully"
        
    } catch {
        Write-Host "⚠️ Download attempt $attempt failed: $($_.Exception.Message)"
        if ($attempt -eq $maxAttempts) {
            throw "Failed to download repository after $maxAttempts attempts"
        }
    }
    $attempt++
}

# Copy posting_server folder
Write-Host "📁 Copying posting_server folder..."
if (-not (Test-Path "$env:TEMP_DIR\posting_server")) {
    Write-Host "❌ Error: posting_server folder not found in downloaded repository"
    throw "posting_server folder not found"
}

Copy-Item -Recurse "$env:TEMP_DIR\posting_server" -Destination "." -Force
Write-Host "✅ posting_server folder copied successfully"

# Clean up temporary directory
Write-Host "🧹 Cleaning up temporary files..."
Remove-Item -Recurse -Force $env:TEMP_DIR -ErrorAction SilentlyContinue
$env:TEMP_DIR = $null

# Navigate to posting_server directory
Write-Host "📂 Navigating to posting_server directory..."
Set-Location posting_server

# Install dependencies
Write-Host "📦 Installing posting server dependencies..."
if (Test-Path "node_modules") {
    Remove-Item -Path "node_modules" -Recurse -Force
}

npm install --no-optional --no-audit
Write-Host "✅ Dependencies installed successfully"

# Set permissions
Write-Host "🔒 Setting up permissions..."
icacls "." /grant "Everyone:(OI)(CI)F" /Q | Out-Null
Get-ChildItem -Filter "*.js" | ForEach-Object { icacls $_.Name /grant "Everyone:R" /Q | Out-Null }
Get-ChildItem -Filter "*.json" | ForEach-Object { icacls $_.Name /grant "Everyone:R" /Q | Out-Null }
Get-ChildItem -Directory | ForEach-Object { icacls $_.Name /grant "Everyone:(OI)(CI)F" /Q | Out-Null }
icacls "..\logs" /grant "Everyone:(OI)(CI)F" /Q | Out-Null

# Start the server using PM2
Write-Host "🚀 Starting posting server with PM2..."

try {
    # Initialize PM2
    pm2 ping | Out-Null
    
    # Start the server
    pm2 start server.js --name "posting-server" --log ..\logs\posting-server.log --exp-backoff-restart-delay=100
    Write-Host "✅ Posting server started successfully"
    
    # Save PM2 process list
    pm2 save | Out-Null
    
} catch {
    Write-Host "❌ Failed to start server with PM2: $($_.Exception.Message)"
    pm2 status
    pm2 logs --lines 10
    throw
}

# Go back to parent directory
Set-Location ..

# Create startup script
Write-Host "🔧 Setting up auto-start mechanism..."
$currentDir = Get-Location
$startupScript = Join-Path $currentDir "pm2-autostart.bat"
$startupScriptContent = @"
@echo off
title PM2 AutoStart Service - Posting Server
echo Starting PM2 Auto-Start Service for Posting Server...

cd /d "$currentDir"

if not exist "logs" mkdir "logs"
echo %DATE% %TIME% - Auto-start service initiated >> "logs\autostart.log"

timeout /t 15 /nobreak > nul

set PATH=%PATH%;C:\Program Files\nodejs;%USERPROFILE%\AppData\Roaming\npm

where pm2 >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo %DATE% %TIME% - PM2 not found in PATH >> "logs\autostart.log"
    echo PM2 not found, please check installation
    timeout /t 10 /nobreak > nul
    goto :end
)

pm2 ping >nul 2>&1

pm2 describe posting-server >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo %DATE% %TIME% - Posting server exists, restarting >> "logs\autostart.log"
    pm2 restart posting-server >> "logs\autostart.log" 2>&1
) else (
    echo %DATE% %TIME% - Starting posting server >> "logs\autostart.log"
    if exist "posting_server\server.js" (
        pm2 start posting_server\server.js --name "posting-server" --log logs\posting-server.log --exp-backoff-restart-delay=100 >> "logs\autostart.log" 2>&1
    ) else (
        echo %DATE% %TIME% - ERROR: posting_server\server.js not found >> "logs\autostart.log"
        goto :end
    )
)

timeout /t 5 /nobreak > nul
pm2 save >> "logs\autostart.log" 2>&1

:end
echo %DATE% %TIME% - Auto-start service completed >> "logs\autostart.log"
"@

Set-Content -Path $startupScript -Value $startupScriptContent -Encoding ASCII

# Set up registry auto-start
try {
    Write-Host "🔧 Setting up auto-start registry entry..."
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $regName = "PM2PostingServerAutoStart"
    
    Remove-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $regPath -Name $regName -Value "`"$startupScript`""
    
    Write-Host "✅ Auto-start configured successfully!"
} catch {
    Write-Host "⚠️ Failed to configure auto-start: $($_.Exception.Message)"
}

# Final verification
Set-Location posting_server
Write-Host "🔍 Verifying server status..."

try {
    $processCheck = & pm2 describe posting-server 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Posting server is running!" -ForegroundColor Green
        pm2 status posting-server
    } else {
        Write-Host "⚠️ Server verification failed. Check with 'pm2 status'"
    }
} catch {
    Write-Host "⚠️ Error checking server status: $($_.Exception.Message)"
}

Set-Location ..

Write-Host ""
Write-Host "✅ Server setup completed!" -ForegroundColor Green
Write-Host ""
Write-Host "🔧 Useful Commands:" -ForegroundColor Yellow
Write-Host "   pm2 status                     # Check all PM2 processes"
Write-Host "   pm2 describe posting-server    # Detailed server info"
Write-Host "   pm2 logs posting-server        # View server logs"
Write-Host "   pm2 restart posting-server     # Restart server"
Write-Host "   pm2 delete posting-server      # Remove server"
Write-Host ""
Write-Host "📊 Log files:" -ForegroundColor Cyan
Write-Host "   - Auto-start: .\logs\autostart.log"
Write-Host "   - Server: .\logs\posting-server.log"
Write-Host ""
Write-Host "🎉 Setup complete! Server will auto-start on boot." -ForegroundColor Green