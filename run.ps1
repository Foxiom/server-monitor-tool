# Exit on error
$ErrorActionPreference = "Stop"

# Self-elevation to ensure admin privileges for all methods
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Relaunching as Administrator for full functionality..."
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

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

# Enhanced auto-start configuration function
function Set-MultipleAutoStartMethods {
    param(
        [string]$CurrentDirectory,
        [string]$StartupScript,
        [string]$PowerShellScript
    )
    
    Write-Host "🔧 Setting up comprehensive auto-start methods..."
    $successCount = 0
    $totalMethods = 0
    
    # Method 1: Registry Run key (User level)
    try {
        $totalMethods++
        Write-Host "📝 Setting up Registry Run key (User)..."
        $regPathUser = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        $regName = "PM2PostingServerAutoStart"
        
        Remove-ItemProperty -Path $regPathUser -Name $regName -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $regPathUser -Name $regName -Value "`"$StartupScript`""
        Write-Host "✅ User-level registry auto-start configured"
        $successCount++
    } catch {
        Write-Host "❌ User-level registry method failed: $($_.Exception.Message)"
    }
    
    # Method 2: Registry Run key (Machine level)
    try {
        $totalMethods++
        Write-Host "📝 Setting up Registry Run key (Machine)..."
        $regPathMachine = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
        $regName = "PM2PostingServerAutoStart"
        
        Remove-ItemProperty -Path $regPathMachine -Name $regName -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $regPathMachine -Name $regName -Value "`"$StartupScript`""
        Write-Host "✅ Machine-level registry auto-start configured"
        $successCount++
    } catch {
        Write-Host "ℹ️ Machine-level registry not configured (requires admin): $($_.Exception.Message)"
    }
    
    # Method 3: Startup folder shortcut
    try {
        $totalMethods++
        Write-Host "📝 Creating startup folder shortcut..."
        $startupFolder = [System.Environment]::GetFolderPath('Startup')
        $shortcutPath = Join-Path $startupFolder "PM2PostingServerAutoStart.lnk"
        
        # Remove existing shortcut
        if (Test-Path $shortcutPath) {
            Remove-Item $shortcutPath -Force
        }
        
        $WScriptShell = New-Object -ComObject WScript.Shell
        $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $StartupScript
        $shortcut.WorkingDirectory = $CurrentDirectory
        $shortcut.Description = "PM2 Posting Server Auto-Start"
        $shortcut.WindowStyle = 7  # Minimized
        $shortcut.Save()
        
        # Release COM object
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WScriptShell) | Out-Null
        
        Write-Host "✅ Startup folder shortcut created"
        $successCount++
    } catch {
        Write-Host "❌ Startup folder shortcut failed: $($_.Exception.Message)"
    }
    
    # Method 4: Windows Task Scheduler (Multiple triggers)
    try {
        $totalMethods++
        Write-Host "📝 Setting up Windows Task Scheduler..."
        
        $taskName = "PM2PostingServerAutoStart"
        $taskDescription = "Auto-start PM2 Posting Server on system events"
        
        # Remove existing task
        try {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        } catch {}
        
        # Create multiple triggers for better reliability
        $triggers = @()
        
        # Trigger 1: At startup
        $trigger1 = New-ScheduledTaskTrigger -AtStartup
        $trigger1.Delay = "PT2M"  # 2-minute delay
        $triggers += $trigger1
        
        # Trigger 2: At logon of any user
        $trigger2 = New-ScheduledTaskTrigger -AtLogOn
        $trigger2.Delay = "PT1M"  # 1-minute delay
        $triggers += $trigger2
        
        # Trigger 3: Daily at 12:01 AM (fallback)
        $trigger3 = New-ScheduledTaskTrigger -Daily -At "12:01AM"
        $triggers += $trigger3
        
        # Create action with both batch and PowerShell fallbacks
        $action1 = New-ScheduledTaskAction -Execute $StartupScript
        $action2 = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PowerShellScript`""
        
        # Task settings for reliability
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false
        $settings.ExecutionTimeLimit = "PT10M"  # 10-minute timeout
        $settings.RestartCount = 3
        $settings.RestartInterval = "PT5M"
        $settings.MultipleInstances = "IgnoreNew"
        
        # Create principal (run with highest privileges if possible)
        try {
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
        } catch {
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Limited
        }
        
        # Register the task
        Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Trigger $triggers -Action $action1 -Settings $settings -Principal $principal -Force | Out-Null
        
        # Verify task creation
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            Write-Host "✅ Windows Task Scheduler configured with multiple triggers"
            $successCount++
        } else {
            throw "Task creation verification failed"
        }
        
    } catch {
        Write-Host "❌ Task Scheduler setup failed: $($_.Exception.Message)"
    }
    
    # Method 5: WMI Event Subscription (Advanced)
    try {
        $totalMethods++
        Write-Host "📝 Setting up WMI Event Subscription..."
        
        $eventName = "PM2PostingServerWMIEvent"
        
        # Remove existing WMI events
        Get-WmiObject -Namespace "root\subscription" -Class "__EventFilter" | Where-Object { $_.Name -eq $eventName } | Remove-WmiObject -ErrorAction SilentlyContinue
        Get-WmiObject -Namespace "root\subscription" -Class "CommandLineEventConsumer" | Where-Object { $_.Name -eq $eventName } | Remove-WmiObject -ErrorAction SilentlyContinue
        Get-WmiObject -Namespace "root\subscription" -Class "__FilterToConsumerBinding" | Where-Object { $_.Filter -match $eventName } | Remove-WmiObject -ErrorAction SilentlyContinue
        
        # Create WMI event filter for explorer.exe start (on user logon)
        $filter = Set-WmiInstance -Namespace "root\subscription" -Class "__EventFilter" -Arguments @{
            Name = $eventName
            EventNamespace = "root\cimv2"
            QueryLanguage = "WQL"
            Query = "SELECT * FROM Win32_ProcessStartTrace WHERE ProcessName = 'explorer.exe'"
        }
        
        # Create WMI event consumer
        $consumer = Set-WmiInstance -Namespace "root\subscription" -Class "CommandLineEventConsumer" -Arguments @{
            Name = $eventName
            CommandLineTemplate = $StartupScript
        }
        
        # Bind filter to consumer
        Set-WmiInstance -Namespace "root\subscription" -Class "__FilterToConsumerBinding" -Arguments @{
            Filter = $filter
            Consumer = $consumer
        } | Out-Null
        
        Write-Host "✅ WMI Event Subscription configured"
        $successCount++
    } catch {
        Write-Host "❌ WMI Event Subscription failed: $($_.Exception.Message)"
    }
    
    # Method 6: Windows Service (using PowerShell primary, with fallbacks)
    try {
        $totalMethods++
        Write-Host "📝 Setting up Windows Service..."
        
        $serviceName = "PM2PostingServer"
        $serviceDisplayName = "PM2 Posting Server Auto-Start"
        $serviceDescription = "Automatically starts and manages PM2 Posting Server"
        
        # Stop and remove existing service
        $existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($existingService) {
            Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            & sc.exe delete $serviceName | Out-Null
            Start-Sleep -Seconds 2
        }
        
        # Create service wrapper script (PowerShell-based)
        $serviceWrapperScript = Join-Path $CurrentDirectory "service-wrapper.ps1"
        $serviceWrapperContent = @"
# Service Wrapper for PM2 Posting Server
while (`$true) {
    try {
        Set-Location "$CurrentDirectory"
        Add-Content -Path "logs\service-wrapper.log" -Value "`$(Get-Date) - Checking PM2 status..."
        `$describe = & pm2 describe posting-server 2>`$null
        if (`$LASTEXITCODE -ne 0) {
            Add-Content -Path "logs\service-wrapper.log" -Value "`$(Get-Date) - Posting server not running, starting..."
            & "$StartupScript"
        } else {
            Add-Content -Path "logs\service-wrapper.log" -Value "`$(Get-Date) - Posting server is running"
        }
    } catch {
        Add-Content -Path "logs\service-wrapper.log" -Value "`$(Get-Date) - Error: `$(`$_.Exception.Message)"
    }
    Start-Sleep -Seconds 300
}
"@
        
        Set-Content -Path $serviceWrapperScript -Value $serviceWrapperContent -Encoding UTF8
        
        # Try to create service with different methods
        # Method 6a: Try with nssm if available
        if (Get-Command nssm -ErrorAction SilentlyContinue) {
            & nssm install $serviceName "powershell.exe"
            & nssm set $serviceName AppParameters "-NoProfile -ExecutionPolicy Bypass -File `"$serviceWrapperScript`""
            & nssm set $serviceName AppDirectory $CurrentDirectory
            & nssm set $serviceName Start SERVICE_AUTO_START
            & nssm set $serviceName Description $serviceDescription
            & nssm set $serviceName DisplayName $serviceDisplayName
            & nssm start $serviceName
            Write-Host "✅ Windows service created with NSSM"
            $successCount++
        } else {
            # Method 6b: Use PowerShell New-Service
            try {
                New-Service -Name $serviceName -BinaryPathName "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$serviceWrapperScript`"" -StartupType Automatic -DisplayName $serviceDisplayName -Description $serviceDescription -ErrorAction Stop
                Start-Service -Name $serviceName -ErrorAction Stop
                Write-Host "✅ Windows service created with PowerShell"
                $successCount++
            } catch {
                Write-Host "❌ PowerShell service creation failed: $($_.Exception.Message)"
                # Method 6c: Fallback to sc.exe
                try {
                    $result = & sc.exe create $serviceName binPath= "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$serviceWrapperScript`"" start= auto DisplayName= $serviceDisplayName
                    if ($LASTEXITCODE -eq 0) {
                        & sc.exe description $serviceName $serviceDescription
                        & sc.exe start $serviceName
                        Write-Host "✅ Windows service created with sc.exe fallback"
                        $successCount++
                    } else {
                        throw "sc.exe failed with exit code $LASTEXITCODE"
                    }
                } catch {
                    Write-Host "❌ sc.exe service creation failed: $($_.Exception.Message)"
                }
            }
        }
        
    } catch {
        Write-Host "❌ Windows Service setup failed: $($_.Exception.Message)"
    }
    
    # Method 7: Group Policy Logon Script (if possible)
    try {
        $totalMethods++
        Write-Host "📝 Setting up Group Policy method..."
        
        $gpoPath = "$env:WINDIR\System32\GroupPolicy\User\Scripts\Logon"
        if (Test-Path $gpoPath) {
            $gpoScript = Join-Path $gpoPath "pm2-autostart.bat"
            Copy-Item $StartupScript $gpoScript -Force
            Write-Host "✅ Group Policy logon script configured"
            $successCount++
        } else {
            Write-Host "ℹ️ Group Policy path not accessible"
        }
    } catch {
        Write-Host "❌ Group Policy method failed: $($_.Exception.Message)"
    }
    
    # Method 8: Create a persistent PowerShell background job
    try {
        $totalMethods++
        Write-Host "📝 Setting up PowerShell background monitoring..."
        
        $monitorScript = Join-Path $CurrentDirectory "pm2-monitor.ps1"
        $monitorContent = @"
# PM2 Background Monitor
while (`$true) {
    try {
        Set-Location "$CurrentDirectory"
        
        # Check if PM2 process exists
        `$pm2Process = Get-Process -Name "PM2 God Daemon" -ErrorAction SilentlyContinue
        if (-not `$pm2Process) {
            # Start the main script
            & "$PowerShellScript"
        } else {
            # Check if posting-server is running
            `$processCheck = & pm2 describe posting-server 2>`$null
            if (`$LASTEXITCODE -ne 0) {
                # Restart posting-server
                & pm2 start posting_server\server.js --name "posting-server" --log logs\posting-server.log --exp-backoff-restart-delay=100
                & pm2 save
            }
        }
    } catch {
        # Silently continue on errors
    }
    
    # Wait 10 minutes before next check
    Start-Sleep -Seconds 600
}
"@
        
        Set-Content -Path $monitorScript -Value $monitorContent -Encoding UTF8
        
        # Add this to startup as well
        $regPathUser = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $regPathUser -Name "PM2PostingServerMonitor" -Value "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$monitorScript`""
        
        Write-Host "✅ PowerShell background monitor configured"
        $successCount++
    } catch {
        Write-Host "❌ PowerShell background monitor failed: $($_.Exception.Message)"
    }
    
    # Summary
    Write-Host ""
    Write-Host "📊 Auto-start Configuration Summary:" -ForegroundColor Cyan
    Write-Host "   Successfully configured: $successCount out of $totalMethods methods"
    
    if ($successCount -ge 3) {
        Write-Host "✅ Excellent! Multiple auto-start methods configured." -ForegroundColor Green
        Write-Host "   Your PM2 server should start reliably on most systems." -ForegroundColor Green
    } elseif ($successCount -ge 1) {
        Write-Host "⚠️ Some auto-start methods configured." -ForegroundColor Yellow
        Write-Host "   The server should start, but consider running as administrator for more methods." -ForegroundColor Yellow
    } else {
        Write-Host "❌ No auto-start methods could be configured." -ForegroundColor Red
        Write-Host "   You may need to start the server manually or run with administrator privileges." -ForegroundColor Red
    }
    
    return $successCount
}

# Function to create comprehensive startup scripts
function New-EnhancedStartupScripts {
    param([string]$CurrentDirectory)
    
    # Create the main batch startup script with enhanced logic
    $startupScript = Join-Path $CurrentDirectory "pm2-autostart.bat"
    $startupScriptContent = @"
@echo off
title PM2 AutoStart Service - Posting Server Enhanced
echo Starting PM2 Auto-Start Service for Posting Server (Enhanced)...

REM Create a lock to prevent multiple instances
set LOCKFILE=%TEMP%\pm2_autostart.lock
if exist "%LOCKFILE%" (
    echo Another instance is running, exiting...
    exit /b 0
)
echo lock > "%LOCKFILE%"

REM Set working directory to script location
cd /d "$CurrentDirectory"

REM Create logs directory if it doesn't exist
if not exist "logs" mkdir "logs"

REM Log startup attempt with unique identifier and system info
echo %DATE% %TIME% - [Enhanced-%RANDOM%] Auto-start service initiated on %COMPUTERNAME% >> "logs\autostart.log"
echo %DATE% %TIME% - [Enhanced-%RANDOM%] Windows Version: %OS% >> "logs\autostart.log"
echo %DATE% %TIME% - [Enhanced-%RANDOM%] User: %USERNAME% >> "logs\autostart.log"

REM Wait for system to fully boot (adaptive wait based on system)
echo %DATE% %TIME% - [Enhanced-%RANDOM%] Waiting for system stabilization... >> "logs\autostart.log"
if "%SESSIONNAME%"=="Console" (
    timeout /t 30 /nobreak > nul 2>nul
) else (
    timeout /t 15 /nobreak > nul 2>nul
)

REM Set comprehensive PATH for Node.js and npm (check multiple locations)
set "NODE_PATHS=C:\Program Files\nodejs;C:\Program Files (x86)\nodejs;%ProgramFiles%\nodejs;%ProgramFiles(x86)%\nodejs"
set "NPM_PATHS=%USERPROFILE%\AppData\Roaming\npm;%ALLUSERSPROFILE%\npm;%APPDATA%\npm"
set "CHOCOLATEY_PATH=%ProgramData%\chocolatey\bin"
set "PATH=%NODE_PATHS%;%NPM_PATHS%;%CHOCOLATEY_PATH%;%PATH%"

REM Also check registry for Node.js path
for /f "tokens=2*" %%a in ('reg query "HKLM\SOFTWARE\Node.js" /v InstallPath 2^>nul') do set "PATH=%%b;%PATH%"
for /f "tokens=2*" %%a in ('reg query "HKLM\SOFTWARE\WOW6432Node\Node.js" /v InstallPath 2^>nul') do set "PATH=%%b;%PATH%"

REM Log final PATH for debugging
echo %DATE% %TIME% - [Enhanced-%RANDOM%] Final PATH: %PATH% >> "logs\autostart.log"

REM Enhanced Node.js detection with multiple attempts
set NODE_FOUND=0
for %%i in (1 2 3) do (
    echo %DATE% %TIME% - [Enhanced-%RANDOM%] Node.js detection attempt %%i... >> "logs\autostart.log"
    where node >nul 2>&1
    if !ERRORLEVEL! EQU 0 (
        set NODE_FOUND=1
        goto :node_found
    )
    timeout /t 5 /nobreak > nul
)

:node_found
if %NODE_FOUND% EQU 0 (
    echo %DATE% %TIME% - [Enhanced-%RANDOM%] ERROR: Node.js not found after multiple attempts >> "logs\autostart.log"
    echo Node.js not found, attempting installation...
    
    REM Try to install Node.js via Chocolatey if available
    where choco >nul 2>&1
    if !ERRORLEVEL! EQU 0 (
        echo Installing Node.js via Chocolatey...
        choco install nodejs-lts -y >> "logs\autostart.log" 2>&1
        refreshenv
        set "PATH=%PATH%;C:\Program Files\nodejs"
    )
    
    REM Final check
    where node >nul 2>&1
    if !ERRORLEVEL! NEQ 0 (
        echo %DATE% %TIME% - [Enhanced-%RANDOM%] FATAL: Node.js installation failed >> "logs\autostart.log"
        goto :cleanup_exit
    )
)

REM Get Node.js version for logging
for /f %%i in ('node --version 2^>nul') do set NODE_VERSION=%%i
echo %DATE% %TIME% - [Enhanced-%RANDOM%] Node.js %NODE_VERSION% found >> "logs\autostart.log"

REM Enhanced PM2 detection and installation
set PM2_FOUND=0
for %%i in (1 2 3) do (
    echo %DATE% %TIME% - [Enhanced-%RANDOM%] PM2 detection attempt %%i... >> "logs\autostart.log"
    where pm2 >nul 2>&1
    if !ERRORLEVEL! EQU 0 (
        set PM2_FOUND=1
        goto :pm2_found
    )
    
    REM Try to install PM2
    echo %DATE% %TIME% - [Enhanced-%RANDOM%] Installing PM2 attempt %%i... >> "logs\autostart.log"
    npm install -g pm2@latest >> "logs\autostart.log" 2>&1
    timeout /t 10 /nobreak > nul
)

:pm2_found
if %PM2_FOUND% EQU 0 (
    echo %DATE% %TIME% - [Enhanced-%RANDOM%] FATAL: PM2 not available after installation attempts >> "logs\autostart.log"
    goto :cleanup_exit
)

REM Get PM2 version for logging
for /f %%i in ('pm2 --version 2^>nul') do set PM2_VERSION=%%i
echo %DATE% %TIME% - [Enhanced-%RANDOM%] PM2 %PM2_VERSION% found >> "logs\autostart.log"

echo %DATE% %TIME% - [Enhanced-%RANDOM%] Node.js and PM2 ready, proceeding... >> "logs\autostart.log"

REM Initialize PM2 daemon with retries
set PM2_INIT_SUCCESS=0
for %%i in (1 2 3 4 5) do (
    echo %DATE% %TIME% - [Enhanced-%RANDOM%] PM2 daemon initialization attempt %%i... >> "logs\autostart.log"
    pm2 ping >> "logs\autostart.log" 2>&1
    if !ERRORLEVEL! EQU 0 (
        set PM2_INIT_SUCCESS=1
        goto :pm2_init_done
    )
    
    REM Kill any stuck PM2 processes and try again
    taskkill /f /im "PM2*" /t >nul 2>&1
    timeout /t 10 /nobreak > nul
)

:pm2_init_done
if %PM2_INIT_SUCCESS% EQU 0 (
    echo %DATE% %TIME% - [Enhanced-%RANDOM%] FATAL: PM2 daemon failed to start after retries >> "logs\autostart.log"
    goto :cleanup_exit
)

REM Multi-method PM2 process restoration
echo %DATE% %TIME% - [Enhanced-%RANDOM%] Attempting PM2 process restoration... >> "logs\autostart.log"

REM Method 1: pm2 resurrect
pm2 resurrect >> "logs\autostart.log" 2>&1
timeout /t 15 /nobreak > nul

REM Method 2: Check if posting-server exists, if not start manually
pm2 describe posting-server >> "logs\autostart.log" 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo %DATE% %TIME% - [Enhanced-%RANDOM%] posting-server not found, starting manually... >> "logs\autostart.log"
    
    if exist "posting_server\server.js" (
        echo %DATE% %TIME% - [Enhanced-%RANDOM%] Starting posting-server from server.js... >> "logs\autostart.log"
        pm2 start posting_server\server.js --name "posting-server" --log logs\posting-server.log --exp-backoff-restart-delay=100 >> "logs\autostart.log" 2>&1
        
        REM Save the process list
        pm2 save >> "logs\autostart.log" 2>&1
        timeout /t 5 /nobreak > nul
    ) else (
        echo %DATE% %TIME% - [Enhanced-%RANDOM%] ERROR: posting_server\server.js not found >> "logs\autostart.log"
        goto :cleanup_exit
    )
)

REM Final verification with detailed status
echo %DATE% %TIME% - [Enhanced-%RANDOM%] Final verification... >> "logs\autostart.log"
pm2 describe posting-server >> "logs\autostart.log" 2>&1
if %ERRORLEVEL% EQU 0 (
    echo %DATE% %TIME% - [Enhanced-%RANDOM%] SUCCESS: Posting server is running >> "logs\autostart.log"
    pm2 status >> "logs\autostart.log" 2>&1
) else (
    echo %DATE% %TIME% - [Enhanced-%RANDOM%] WARNING: Final verification failed >> "logs\autostart.log"
    pm2 status >> "logs\autostart.log" 2>&1
)

:cleanup_exit
REM Cleanup lock file
if exist "%LOCKFILE%" del "%LOCKFILE%"

echo %DATE% %TIME% - [Enhanced-%RANDOM%] Auto-start service completed >> "logs\autostart.log"

REM Keep window open briefly if run manually
if "%1" NEQ "/silent" (
    timeout /t 10 /nobreak > nul
)

exit /b 0
"@

    Set-Content -Path $startupScript -Value $startupScriptContent -Encoding ASCII

    # Create enhanced PowerShell startup script
    $powershellStartupScript = Join-Path $CurrentDirectory "pm2-autostart.ps1"
    $powershellStartupScriptContent = @"
# Enhanced PM2 Auto-start PowerShell Script
param([switch]`$Silent)

`$ErrorActionPreference = "Continue"
`$currentDir = "$CurrentDirectory"

# Prevent multiple instances
`$lockFile = Join-Path `$env:TEMP "pm2_autostart_ps.lock"
if (Test-Path `$lockFile) {
    Write-Host "Another PowerShell instance is running, exiting..."
    exit 0
}
Set-Content -Path `$lockFile -Value "lock"

try {
    Set-Location `$currentDir

    # Create logs directory
    if (-not (Test-Path "logs")) { 
        New-Item -ItemType Directory -Path "logs" -Force | Out-Null 
    }

    # Enhanced logging with system information
    `$logEntry = "`$(Get-Date) - [PowerShell-Enhanced] Auto-start service initiated on `$env:COMPUTERNAME by `$env:USERNAME"
    Add-Content -Path "logs\autostart.log" -Value `$logEntry

    # Adaptive wait based on system state
    `$waitTime = if (`$env:SESSIONNAME -eq "Console") { 30 } else { 15 }
    Write-Host "Waiting `$waitTime seconds for system stabilization..."
    Start-Sleep -Seconds `$waitTime

    # Enhanced PATH setup with registry checking
    `$nodePaths = @(
        "C:\Program Files\nodejs",
        "C:\Program Files (x86)\nodejs",
        "`$env:ProgramFiles\nodejs",
        "`${env:ProgramFiles(x86)}\nodejs",
        "`$env:USERPROFILE\AppData\Roaming\npm",
        "`$env:ALLUSERSPROFILE\npm",
        "`$env:APPDATA\npm",
        "`$env:ProgramData\chocolatey\bin"
    )

    # Add registry-based Node.js paths
    try {
        `$nodeRegPath = Get-ItemProperty -Path "HKLM:\SOFTWARE\Node.js" -Name "InstallPath" -ErrorAction SilentlyContinue
        if (`$nodeRegPath) { `$nodePaths += `$nodeRegPath.InstallPath }
        
        `$nodeRegPathWow = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Node.js" -Name "InstallPath" -ErrorAction SilentlyContinue
        if (`$nodeRegPathWow) { `$nodePaths += `$nodeRegPathWow.InstallPath }
    } catch {}

    foreach (`$path in `$nodePaths) {
        if (Test-Path `$path) {
            `$env:Path = "`$path;`$env:Path"
        }
    }

    Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] Final PATH configured"

    # Enhanced Node.js detection with multiple attempts
    `$nodeFound = `$false
    for (`$i = 1; `$i -le 3; `$i++) {
        Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] Node.js detection attempt `$i"
        
        if (Get-Command node -ErrorAction SilentlyContinue) {
            `$nodeFound = `$true
            `$nodeVersion = & node --version
            Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] Node.js `$nodeVersion found"
            break
        }
        
        Start-Sleep -Seconds 5
    }

    if (-not `$nodeFound) {
        Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] ERROR: Node.js not found after multiple attempts"
        
        # Try to install via Chocolatey if available
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] Installing Node.js via Chocolatey"
            try {
                choco install nodejs-lts -y
                # Refresh environment
                `$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            } catch {}
        }
        
        # Final check
        if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
            Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] FATAL: Node.js installation failed"
            throw "Node.js not available"
        }
    }

    # Enhanced PM2 detection and installation
    `$pm2Found = `$false
    for (`$i = 1; `$i -le 3; `$i++) {
        Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] PM2 detection attempt `$i"
        
        if (Get-Command pm2 -ErrorAction SilentlyContinue) {
            `$pm2Found = `$true
            `$pm2Version = & pm2 --version
            Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] PM2 `$pm2Version found"
            break
        }
        
        # Try to install PM2
        Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] Installing PM2 attempt `$i"
        try {
            npm install -g pm2@latest
            Start-Sleep -Seconds 10
        } catch {
            Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] PM2 installation attempt `$i failed"
        }
    }

    if (-not `$pm2Found) {
        Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] FATAL: PM2 not available after installation attempts"
        throw "PM2 not available"
    }

    Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] Node.js and PM2 ready, proceeding..."

    # Initialize PM2 daemon with retries
    `$pm2InitSuccess = `$false
    for (`$i = 1; `$i -le 5; `$i++) {
        Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] PM2 daemon initialization attempt `$i"
        
        try {
            pm2 ping | Out-Null
            `$pm2InitSuccess = `$true
            break
        } catch {
            # Kill any stuck PM2 processes and try again
            Get-Process -Name "*PM2*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 10
        }
    }

    if (-not `$pm2InitSuccess) {
        Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] FATAL: PM2 daemon failed to start after retries"
        throw "PM2 daemon initialization failed"
    }

    # Multi-method PM2 process restoration
    Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] Attempting PM2 process restoration..."

    try {
        # Method 1: pm2 resurrect
        pm2 resurrect | Out-Null
        Start-Sleep -Seconds 15

        # Method 2: Check if posting-server exists, if not start manually  
        `$processCheck = & pm2 describe posting-server 2>`$null
        if (`$LASTEXITCODE -ne 0) {
            Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] posting-server not found, starting manually..."
            
            if (Test-Path "posting_server\server.js") {
                Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] Starting posting-server from server.js..."
                pm2 start posting_server\server.js --name "posting-server" --log logs\posting-server.log --exp-backoff-restart-delay=100
                pm2 save
                Start-Sleep -Seconds 5
            } else {
                Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] ERROR: posting_server\server.js not found"
                throw "Server file not found"
            }
        }

        # Final verification
        Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] Final verification..."
        `$finalCheck = & pm2 describe posting-server 2>`$null
        if (`$LASTEXITCODE -eq 0) {
            Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] SUCCESS: Posting server is running"
            if (-not `$Silent) {
                pm2 status
            }
        } else {
            Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] WARNING: Final verification failed"
        }

    } catch {
        Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] ERROR during process restoration: `$(`$_.Exception.Message)"
    }

} catch {
    Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] FATAL ERROR: `$(`$_.Exception.Message)"
} finally {
    # Cleanup lock file
    if (Test-Path `$lockFile) {
        Remove-Item `$lockFile -Force -ErrorAction SilentlyContinue
    }
}

Add-Content -Path "logs\autostart.log" -Value "`$(Get-Date) - [PowerShell-Enhanced] Auto-start service completed"
"@

    Set-Content -Path $powershellStartupScript -Value $powershellStartupScriptContent -Encoding UTF8

    return @{
        BatchScript = $startupScript
        PowerShellScript = $powershellStartupScript
    }
}

# Create enhanced startup scripts
Write-Host "🔧 Creating enhanced startup scripts..."
$currentDir = Get-Location
$scripts = New-EnhancedStartupScripts -CurrentDirectory $currentDir.Path

# Set up multiple auto-start methods
$successfulMethods = Set-MultipleAutoStartMethods -CurrentDirectory $currentDir.Path -StartupScript $scripts.BatchScript -PowerShellScript $scripts.PowerShellScript

# Create additional fallback methods for older systems
Write-Host "🔧 Setting up additional fallback methods for older systems..."

try {
    # Method 9: Create a Windows Script Host (WSH) launcher for maximum compatibility
    $wshScript = Join-Path $currentDir "pm2-launcher.vbs"
    $wshContent = @"
Dim objShell, currentDir
Set objShell = CreateObject("WScript.Shell")
currentDir = "$($currentDir.Path)"

' Change to the correct directory
objShell.CurrentDirectory = currentDir

' Log the launch attempt
Dim fso, logFile
Set fso = CreateObject("Scripting.FileSystemObject")
If Not fso.FolderExists(currentDir & "\logs") Then
    fso.CreateFolder(currentDir & "\logs")
End If

Set logFile = fso.OpenTextFile(currentDir & "\logs\autostart.log", 8, True)
logFile.WriteLine Now & " - [VBS] WSH launcher initiated"
logFile.Close

' Run the batch script silently
objShell.Run """" & currentDir & "\pm2-autostart.bat"" /silent", 0, False

Set objShell = Nothing
Set fso = Nothing
"@
    
    Set-Content -Path $wshScript -Value $wshContent -Encoding ASCII
    
    # Add WSH script to startup
    $regPathUser = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Set-ItemProperty -Path $regPathUser -Name "PM2PostingServerWSH" -Value "wscript.exe `"$wshScript`""
    
    Write-Host "✅ WSH launcher created for maximum compatibility"
    
} catch {
    Write-Host "❌ WSH launcher setup failed: $($_.Exception.Message)"
}

try {
    # Method 10: Create a Windows Batch file in the All Users Startup folder
    $allUsersStartup = [Environment]::GetFolderPath("CommonStartup")
    if (Test-Path $allUsersStartup) {
        $allUsersScript = Join-Path $allUsersStartup "PM2PostingServerAutoStart.bat"
        $allUsersContent = @"
@echo off
cd /d "$($currentDir.Path)"
call "$($scripts.BatchScript)" /silent
"@
        Set-Content -Path $allUsersScript -Value $allUsersContent -Encoding ASCII
        Write-Host "✅ All Users startup script created"
    }
} catch {
    Write-Host "ℹ️ All Users startup folder not accessible (requires admin)"
}

try {
    # Method 11: Create a logon script via registry for older Windows versions
    $logonScriptPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
    
    # Check if the registry path exists (older Windows versions)
    if (Test-Path $logonScriptPath) {
        Set-ItemProperty -Path $logonScriptPath -Name "Shell" -Value "explorer.exe,$($scripts.BatchScript)" -ErrorAction SilentlyContinue
        Write-Host "✅ Legacy logon script configured"
    }
} catch {
    Write-Host "ℹ️ Legacy logon script not configured"
}

# Create a comprehensive health check script
$healthCheckScript = Join-Path $currentDir "pm2-health-check.ps1"
$healthCheckContent = @"
# PM2 Health Check and Recovery Script
param([switch]`$Fix, [switch]`$Verbose)

`$currentDir = "$($currentDir.Path)"
Set-Location `$currentDir

function Write-Log {
    param([string]`$Message, [string]`$Level = "INFO")
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    `$logMessage = "`$timestamp - [`$Level] `$Message"
    
    if (`$Verbose -or `$Level -eq "ERROR") {
        Write-Host `$logMessage -ForegroundColor (`$Level -eq "ERROR" ? "Red" : "Green")
    }
    
    if (-not (Test-Path "logs")) { New-Item -ItemType Directory -Path "logs" -Force | Out-Null }
    Add-Content -Path "logs\health-check.log" -Value `$logMessage
}

Write-Log "Starting PM2 health check..."

# Check 1: Node.js availability
try {
    `$nodeVersion = & node --version 2>`$null
    if (`$nodeVersion) {
        Write-Log "Node.js `$nodeVersion - OK"
    } else {
        throw "Node.js not responding"
    }
} catch {
    Write-Log "Node.js - FAILED: `$(`$_.Exception.Message)" "ERROR"
    if (`$Fix) {
        Write-Log "Attempting to fix Node.js PATH..."
        # Add Node.js paths
        `$env:Path += ";C:\Program Files\nodejs;C:\Program Files (x86)\nodejs"
    }
}

# Check 2: PM2 availability  
try {
    `$pm2Version = & pm2 --version 2>`$null
    if (`$pm2Version) {
        Write-Log "PM2 `$pm2Version - OK"
    } else {
        throw "PM2 not responding"
    }
} catch {
    Write-Log "PM2 - FAILED: `$(`$_.Exception.Message)" "ERROR"
    if (`$Fix) {
        Write-Log "Attempting to reinstall PM2..."
        npm install -g pm2@latest
    }
}

# Check 3: PM2 daemon status
try {
    pm2 ping | Out-Null 2>&1
    if (`$LASTEXITCODE -eq 0) {
        Write-Log "PM2 daemon - OK"
    } else {
        throw "PM2 daemon not responding"
    }
} catch {
    Write-Log "PM2 daemon - FAILED" "ERROR"
    if (`$Fix) {
        Write-Log "Attempting to restart PM2 daemon..."
        pm2 kill 2>`$null
        Start-Sleep 5
        pm2 ping
    }
}

# Check 4: posting-server status
try {
    `$processStatus = & pm2 describe posting-server 2>`$null
    if (`$LASTEXITCODE -eq 0) {
        Write-Log "posting-server process - OK"
        
        # Get detailed status
        `$statusOutput = & pm2 jlist | ConvertFrom-Json
        `$postingServer = `$statusOutput | Where-Object { `$_.name -eq "posting-server" }
        
        if (`$postingServer) {
            Write-Log "posting-server status: `$(`$postingServer.pm2_env.status)"
            Write-Log "posting-server uptime: `$(`$postingServer.pm2_env.pm_uptime)"
            Write-Log "posting-server restarts: `$(`$postingServer.pm2_env.restart_time)"
        }
        
    } else {
        throw "posting-server not found in PM2"
    }
} catch {
    Write-Log "posting-server - FAILED: `$(`$_.Exception.Message)" "ERROR"
    if (`$Fix) {
        Write-Log "Attempting to start posting-server..."
        if (Test-Path "posting_server\server.js") {
            pm2 start posting_server\server.js --name "posting-server" --log logs\posting-server.log
            pm2 save
        } else {
            Write-Log "Server file not found!" "ERROR"
        }
    }
}

# Check 5: Auto-start methods verification
Write-Log "Checking auto-start methods..."

`$autoStartMethods = @(
    @{ Name = "Registry (User)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"; Key = "PM2PostingServerAutoStart" },
    @{ Name = "Registry (Machine)"; Path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"; Key = "PM2PostingServerAutoStart" },
    @{ Name = "Startup Folder"; Path = [Environment]::GetFolderPath('Startup') + "\PM2PostingServerAutoStart.lnk"; Key = `$null },
    @{ Name = "Task Scheduler"; Path = `$null; Key = "PM2PostingServerAutoStart" }
)

foreach (`$method in `$autoStartMethods) {
    try {
        `$exists = `$false
        
        if (`$method.Path -and `$method.Path.StartsWith("HK")) {
            # Registry check
            `$regValue = Get-ItemProperty -Path `$method.Path -Name `$method.Key -ErrorAction SilentlyContinue
            `$exists = `$regValue -ne `$null
        } elseif (`$method.Path) {
            # File system check
            `$exists = Test-Path `$method.Path
        } elseif (`$method.Key -eq "PM2PostingServerAutoStart") {
            # Task scheduler check
            `$task = Get-ScheduledTask -TaskName `$method.Key -ErrorAction SilentlyContinue
            `$exists = `$task -ne `$null
        }
        
        if (`$exists) {
            Write-Log "`$(`$method.Name) - OK"
        } else {
            Write-Log "`$(`$method.Name) - NOT CONFIGURED" "ERROR"
        }
        
    } catch {
        Write-Log "`$(`$method.Name) - CHECK FAILED: `$(`$_.Exception.Message)" "ERROR"
    }
}

Write-Log "Health check completed"

# Summary
if (`$Fix) {
    Write-Log "Fix mode was enabled - attempted repairs where needed"
    Write-Log "Run the health check again to verify fixes"
} else {
    Write-Log "Run with -Fix parameter to attempt automatic repairs"
    Write-Log "Run with -Verbose parameter for detailed output"
}
"@

Set-Content -Path $healthCheckScript -Value $healthCheckContent -Encoding UTF8

Write-Host ""
Write-Host "✅ Enhanced auto-start setup completed!" -ForegroundColor Green
Write-Host ""
Write-Host "🔧 New Tools Available:" -ForegroundColor Yellow
Write-Host "   .\pm2-health-check.ps1          # Check system health"
Write-Host "   .\pm2-health-check.ps1 -Fix     # Check and attempt repairs"
Write-Host "   .\pm2-health-check.ps1 -Verbose # Detailed output"
Write-Host ""
Write-Host "📊 Auto-start Methods Configured:" -ForegroundColor Cyan
Write-Host "   1. Registry Run Keys (User & Machine level)"
Write-Host "   2. Startup Folder Shortcuts"
Write-Host "   3. Windows Task Scheduler (multiple triggers)"
Write-Host "   4. WMI Event Subscriptions"
Write-Host "   5. Windows Services (if NSSM available)"
Write-Host "   6. Group Policy Scripts (if accessible)"
Write-Host "   7. PowerShell Background Monitor"
Write-Host "   8. WSH Launcher (maximum compatibility)"
Write-Host "   9. All Users Startup (if admin)"
Write-Host "  10. Legacy Logon Scripts"
Write-Host ""
Write-Host "💡 For Maximum Reliability:" -ForegroundColor Green
Write-Host "   - Run this script as Administrator for more methods"
Write-Host "   - Consider installing NSSM for Windows Service support"
Write-Host "   - Use the health check tool to monitor system status"
Write-Host ""

if ($successfulMethods -ge 3) {
    Write-Host "🎉 Excellent setup! Your server should start reliably on most systems." -ForegroundColor Green
} elseif ($successfulMethods -ge 1) {
    Write-Host "⚠️ Good setup, but consider running as administrator for more reliability." -ForegroundColor Yellow  
} else {
    Write-Host "❌ Limited setup. Run as administrator or check system requirements." -ForegroundColor Red
}