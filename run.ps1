# PowerShell script to set up a posting server on Windows

# Exit on error
$ErrorActionPreference = "Stop"

# Function to clean up on error
function Cleanup {
    param($TempDir)
    if (Test-Path "posting_server") {
        Write-Host "❌ An error occurred. Cleaning up..."
        Remove-Item -Path "posting_server" -Recurse -Force
    }
    if ($TempDir -and (Test-Path $TempDir)) {
        Remove-Item -Path $TempDir -Recurse -Force
    }
    exit 1
}

# Set up error handling
$global:LASTEXITCODE = 0
try {
    # Function to check if a command exists
    function Command-Exists {
        param($Command)
        return (Get-Command $Command -ErrorAction SilentlyContinue) -ne $null
    }

    # Function to install Node.js
    function Install-NodeJS {
        Write-Host "📦 Installing Node.js..."
        try {
            # Download and install Node.js LTS (18.x equivalent)
            $nodeInstaller = "node-v18.20.4-x64.msi"
            $nodeUrl = "https://nodejs.org/dist/v18.20.4/$nodeInstaller"
            $outputPath = "$env:TEMP\$nodeInstaller"
            Invoke-WebRequest -Uri $nodeUrl -OutFile $outputPath
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $outputPath /quiet" -Wait
            Remove-Item $outputPath
            # Refresh environment variables
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        }
        catch {
            Write-Host "❌ Failed to install Node.js"
            Cleanup
        }
    }

    # Function to install Git
    function Install-Git {
        Write-Host "📦 Installing Git..."
        try {
            $gitInstaller = "Git-2.46.0-64-bit.exe"
            $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.46.0.windows.1/$gitInstaller"
            $outputPath = "$env:TEMP\$gitInstaller"
            Invoke-WebRequest -Uri $gitUrl -OutFile $outputPath
            Start-Process -FilePath $outputPath -ArgumentList "/VERYSILENT /NORESTART" -Wait
            Remove-Item $outputPath
            # Refresh environment variables
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        }
        catch {
            Write-Host "❌ Failed to install Git"
            Cleanup
        }
    }

    # Check and install Node.js if not present
    if (-not (Command-Exists "node")) {
        Write-Host "❌ Node.js is not installed."
        Install-NodeJS
    }

    # Check and install Git if not present
    if (-not (Command-Exists "git")) {
        Write-Host "❌ Git is not installed."
        Install-Git
    }

    # Check if PM2 is installed, if not install it globally
    if (-not (Command-Exists "pm2")) {
        Write-Host "📦 Installing PM2 globally..."
        npm install -g pm2
    }

    # Remove existing posting_server directory if it exists
    if (Test-Path "posting_server") {
        Write-Host "🗑️ Removing existing posting_server directory..."
        Remove-Item -Path "posting_server" -Recurse -Force
    }

    # Create logs directory if it doesn't exist
    if (-not (Test-Path "logs")) {
        New-Item -ItemType Directory -Path "logs" | Out-Null
    }

    # Setup posting server
    Write-Host "🔧 Setting up posting server..."

    # Clone the repository to a temporary directory (shallow clone for efficiency)
    Write-Host "⬇️ Downloading complete posting server from GitHub..."
    $TempDir = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
    New-Item -ItemType Directory -Path $TempDir | Out-Null
    try {
        git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git $TempDir
    }
    catch {
        Write-Host "❌ Failed to clone repository"
        Cleanup -TempDir $TempDir
    }

    # Copy only the posting_server folder to the target location
    Copy-Item -Path "$TempDir\posting_server" -Destination "." -Recurse

    # Clean up temporary directory
    Remove-Item -Path $TempDir -Recurse -Force

    # Navigate to posting_server directory
    Set-Location -Path "posting_server"

    # Install posting server dependencies
    Write-Host "📦 Installing posting server dependencies..."
    npm install

    # Set posting server permissions
    Write-Host "🔒 Setting up permissions..."
    icacls "." /grant "Everyone:F" /T
    icacls "..\logs" /grant "Everyone:F" /T

    # Start the server using PM2 with exponential backoff restart
    Write-Host "🚀 Starting posting server with PM2..."
    pm2 start server.js --name "posting-server" --log "..\logs\posting-server.log" --exp-backoff-restart-delay=100

    # Save PM2 process list
    Write-Host "💾 Saving PM2 process list..."
    pm2 save

    # Setup Task Scheduler to run PM2 resurrect on system boot
    Write-Host "🔧 Setting up Task Scheduler to start PM2 on system boot..."
    $pm2Path = (Get-Command pm2).Source
    $nodePath = (Get-Command node).Source
    $actionScript = @"
cd /d `"$PSScriptRoot\posting_server`"
& `"$nodePath`" `"$pm2Path`" resurrect
"@
    $actionScriptPath = Join-Path $PSScriptRoot "start_pm2.ps1"
    Set-Content -Path $actionScriptPath -Value $actionScript

    $taskName = "PM2_Startup"
    $taskDescription = "Runs PM2 resurrect to start posting server on system boot"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$actionScriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

    # Add a delay to ensure system stability (30 seconds)
    Start-Sleep -Seconds 30
    & "$nodePath" "$pm2Path" resurrect

    # Verify if the server is running
    Write-Host "🔍 Verifying server status..."
    $pm2Status = pm2 list | Out-String
    if ($pm2Status -match "posting-server.*online") {
        Write-Host "✅ Posting server is running!"
    }
    else {
        Write-Host "⚠️ Posting server is not running. Attempting to restart..."
        pm2 restart posting-server
        Start-Sleep -Seconds 5
        $pm2Status = pm2 list | Out-String
        if ($pm2Status -match "posting-server.*online") {
            Write-Host "✅ Posting server restarted successfully!"
        }
        else {
            Write-Host "❌ Failed to start posting server. Please check logs with 'pm2 logs posting-server'."
            Cleanup
        }
    }

    # Optional: Install PM2 log rotation module
    Write-Host "🔧 Setting up PM2 log rotation..."
    pm2 install pm2-logrotate
    pm2 set pm2-logrotate:max_size 10M
    pm2 set pm2-logrotate:compress $true

    Write-Host "✅ Server started and configured to run on system boot!"
    Write-Host "📁 Downloaded complete posting server with all folders:"
    Write-Host "   - config/"
    Write-Host "   - models/"
    Write-Host "   - utils/"
    Write-Host "   - server.js"
    Write-Host "   - package.json"
    Write-Host ""
    Write-Host "To manage the server, use these PM2 commands:"
    Write-Host "  - pm2 status              # Check server status"
    Write-Host "  - pm2 logs                # View all logs"
    Write-Host "  - pm2 logs posting-server # View posting server logs"
    Write-Host "  - pm2 stop all           # Stop the server"
    Write-Host "  - pm2 restart all        # Restart the server"
    Write-Host "  - pm2 delete posting-server # Remove the server from PM2"
}
catch {
    Cleanup -TempDir $TempDir
}