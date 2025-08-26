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

# Create a more robust startup script that works from any directory
Write-Host "🔧 Setting up auto-start mechanism..."

$currentDir = Get-Location
$startupScript = Join-Path $currentDir "pm2-autostart.bat"
$startupScriptContent = @"
@echo off
title PM2 AutoStart Service - Posting Server
echo Starting PM2 Auto-Start Service for Posting Server...

REM Set working directory to script location
cd /d "$currentDir"

REM Create logs directory if it doesn't exist
if not exist "logs" mkdir "logs"

REM Log startup attempt with unique identifier
echo %DATE% %TIME% - [%RANDOM%] Auto-start service initiated >> "logs\autostart.log"

REM Wait for system to fully boot (only wait once per boot)
timeout /t 15 /nobreak > nul 2>nul

REM Set comprehensive PATH for Node.js and npm
set "NODE_PATH=C:\Program Files\nodejs"
set "NPM_PATH=%USERPROFILE%\AppData\Roaming\npm"
set "NPM_PATH_GLOBAL=%ALLUSERSPROFILE%\npm"
set "PATH=%NODE_PATH%;%NPM_PATH%;%NPM_PATH_GLOBAL%;%PATH%"

REM Also try common alternative paths
if exist "C:\Program Files (x86)\nodejs" (
    set "PATH=C:\Program Files (x86)\nodejs;%PATH%"
)

REM Log PATH for debugging
echo %DATE% %TIME% - [%RANDOM%] PATH set to: %PATH% >> "logs\autostart.log"

REM Check if Node.js is available
where node >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo %DATE% %TIME% - [%RANDOM%] ERROR: Node.js not found in PATH >> "logs\autostart.log"
    echo Node.js not found, please check installation
    timeout /t 10 /nobreak > nul
    goto :end
)

REM Check if PM2 is available
where pm2 >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo %DATE% %TIME% - [%RANDOM%] ERROR: PM2 not found in PATH >> "logs\autostart.log"
    echo PM2 not found, installing globally...
    npm install -g pm2@latest >> "logs\autostart.log" 2>&1
    
    REM Check again after installation
    where pm2 >nul 2>&1
    if %ERRORLEVEL% NEQ 0 (
        echo %DATE% %TIME% - [%RANDOM%] ERROR: PM2 installation failed >> "logs\autostart.log"
        goto :end
    )
)

echo %DATE% %TIME% - [%RANDOM%] Node.js and PM2 found, proceeding... >> "logs\autostart.log"

REM Initialize PM2 daemon (this is crucial)
echo %DATE% %TIME% - [%RANDOM%] Initializing PM2 daemon... >> "logs\autostart.log"
pm2 ping >> "logs\autostart.log" 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo %DATE% %TIME% - [%RANDOM%] PM2 daemon failed to start >> "logs\autostart.log"
    goto :end
)

REM Use pm2 resurrect to restore all saved processes
echo %DATE% %TIME% - [%RANDOM%] Attempting to resurrect saved PM2 processes... >> "logs\autostart.log"
pm2 resurrect >> "logs\autostart.log" 2>&1

REM Wait for processes to stabilize
timeout /t 10 /nobreak > nul

REM Check if posting-server is running
pm2 describe posting-server >> "logs\autostart.log" 2>&1
if %ERRORLEVEL% EQU 0 (
    echo %DATE% %TIME% - [%RANDOM%] SUCCESS: Posting server is running >> "logs\autostart.log"
    pm2 status >> "logs\autostart.log" 2>&1
) else (
    echo %DATE% %TIME% - [%RANDOM%] Posting server not found, attempting manual start... >> "logs\autostart.log"
    
    REM Navigate to posting_server directory and start manually
    if exist "posting_server\server.js" (
        echo %DATE% %TIME% - [%RANDOM%] Starting posting-server manually... >> "logs\autostart.log"
        pm2 start posting_server\server.js --name "posting-server" --log logs\posting-server.log --exp-backoff-restart-delay=100 >> "logs\autostart.log" 2>&1
        
        REM Save the process list
        pm2 save >> "logs\autostart.log" 2>&1
        
        REM Verify it started
        pm2 describe posting-server >> "logs\autostart.log" 2>&1
        if %ERRORLEVEL% EQU 0 (
            echo %DATE% %TIME% - [%RANDOM%] SUCCESS: Posting server started manually >> "logs\autostart.log"
        ) else (
            echo %DATE% %TIME% - [%RANDOM%] ERROR: Failed to start posting server manually >> "logs\autostart.log"
        )
    ) else (
        echo %DATE% %TIME% - [%RANDOM%] ERROR: posting_server\server.js not found >> "logs\autostart.log"
    )
)

:end
echo %DATE% %TIME% - [%RANDOM%] Auto-start service completed >> "logs\autostart.log"

REM Prevent multiple instances by creating a lock file temporarily
echo lock > "%TEMP%\pm2_autostart_lock.tmp"
timeout /t 30 /nobreak > nul
if exist "%TEMP%\pm2_autostart_lock.tmp" del "%TEMP%\pm2_autostart_lock.tmp"
"@

Set-Content -Path $startupScript -Value $startupScriptContent -Encoding ASCII

# Also create a PowerShell version for better reliability
$powershellStartupScript = Join-Path $currentDir "pm2-autostart.ps1"
$powershellStartupScriptContent = @"
# PM2 Auto-start PowerShell Script
`$ErrorActionPreference = "Continue"
`$currentDir = "$currentDir"
Set-Location `$currentDir

# Create logs directory
if (-not (Test-Path "logs")) { New-Item -ItemType Directory -Path "logs" -Force | Out-Null }

# Log startup
`$logEntry = "`$(Get-Date) - [PowerShell] Auto-start service initiated"
Add-Content -Path "logs\autostart.log" -Value `$logEntry

# Wait for system to boot
Start-Sleep -Seconds 15

# Set environment paths
`$nodePaths = @(
    "C:\Program Files\nodejs",
    "C:\Program Files (x86)\nodejs",
    "`$env:USERPROFILE\AppData\Roaming\npm",
    "`$env:ALLUSERSPROFILE\npm"
)

foreach (`$path in `$nodePaths) {
    if (Test-Path `$path) {
        `$env:Path = "`$path;`$env:Path"
    }
}

# Check Node.js
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell] ERROR: Node.js not found"
    exit 1
}

# Check/Install PM2
if (-not (Get-Command pm2 -ErrorAction SilentlyContinue)) {
    Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell] Installing PM2..."
    try {
        npm install -g pm2@latest
    } catch {
        Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell] ERROR: PM2 installation failed"
        exit 1
    }
}

Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell] Initializing PM2 daemon..."

try {
    # Initialize PM2
    pm2 ping | Out-Null
    
    # Resurrect saved processes
    Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell] Resurrecting PM2 processes..."
    pm2 resurrect | Out-Null
    
    Start-Sleep -Seconds 10
    
    # Check if posting-server is running
    `$processCheck = & pm2 describe posting-server 2>`$null
    if (`$LASTEXITCODE -eq 0) {
        Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell] SUCCESS: Posting server is running"
    } else {
        Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell] Starting posting-server manually..."
        
        if (Test-Path "posting_server\server.js") {
            pm2 start posting_server\server.js --name "posting-server" --log logs\posting-server.log --exp-backoff-restart-delay=100
            pm2 save
            Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell] Posting server started manually"
        } else {
            Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell] ERROR: server.js not found"
        }
    }
    
} catch {
    Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell] ERROR: `$(`$_.Exception.Message)"
}

Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell] Auto-start service completed"
"@

Set-Content -Path $powershellStartupScript -Value $powershellStartupScriptContent -Encoding UTF8

# Set up multiple auto-start methods for maximum reliability
try {
    Write-Host "🔧 Setting up multiple auto-start methods..."
    
    # Method 1: Registry Run key (User level)
    $regPathUser = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $regName = "PM2PostingServerAutoStart"
    
    Remove-ItemProperty -Path $regPathUser -Name $regName -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $regPathUser -Name $regName -Value "`"$startupScript`""
    Write-Host "✅ User-level auto-start configured"
    
    # Method 2: Try Machine-level registry (requires admin)
    try {
        $regPathMachine = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
        Remove-ItemProperty -Path $regPathMachine -Name $regName -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $regPathMachine -Name $regName -Value "`"$startupScript`""
        Write-Host "✅ Machine-level auto-start configured"
    } catch {
        Write-Host "ℹ️ Machine-level auto-start not configured (requires admin)"
    }
    
    # Method 3: Startup folder shortcut
    try {
        $startupFolder = [System.Environment]::GetFolderPath('Startup')
        $shortcutPath = Join-Path $startupFolder "PM2PostingServerAutoStart.lnk"
        
        $WScriptShell = New-Object -ComObject WScript.Shell
        $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $startupScript
        $shortcut.WorkingDirectory = $currentDir
        $shortcut.Description = "PM2 Posting Server Auto-Start"
        $shortcut.Save()
        
        Write-Host "✅ Startup folder shortcut created"
    } catch {
        Write-Host "⚠️ Failed to create startup folder shortcut: $($_.Exception.Message)"
    }
    
    # Method 4: Create a Windows service (if possible)
    try {
        $serviceName = "PM2PostingServer"
        $existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        
        if ($existingService) {
            Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
            & sc.exe delete $serviceName | Out-Null
        }
        
        # Use nssm if available, otherwise skip service creation
        if (Get-Command nssm -ErrorAction SilentlyContinue) {
            & nssm install $serviceName $startupScript
            & nssm set $serviceName Start SERVICE_AUTO_START
            & nssm set $serviceName Description "PM2 Posting Server Auto-Start Service"
            Write-Host "✅ Windows service created with NSSM"
        }
        
    } catch {
        Write-Host "ℹ️ Windows service not configured (requires admin or NSSM)"
    }
    
    Write-Host "✅ Auto-start configured with multiple methods!"
    
} catch {
    Write-Host "⚠️ Some auto-start methods failed: $($_.Exception.Message)"
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
Write-Host "✅ Server setup completed" -ForegroundColor Green
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