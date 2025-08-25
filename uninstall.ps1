# Exit on error
$ErrorActionPreference = "Stop"

Write-Host "🗑️ Starting Complete Posting Server Uninstall Process..." -ForegroundColor Yellow
Write-Host ""

# Function to perform safe cleanup
function Remove-PostingServerSafely {
    param([string]$DirectoryPath = "posting_server")
    
    Write-Host "🧹 Safely removing $DirectoryPath..."
    
    # Step 1: Stop only posting-server PM2 process
    if (Get-Command pm2 -ErrorAction SilentlyContinue) {
        Write-Host "🛑 Stopping posting-server PM2 process..."
        try {
            # Check if posting-server exists
            $postingServerExists = & pm2 describe posting-server 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Stopping posting-server process..."
                pm2 stop posting-server 2>$null | Out-Null
                Write-Host "  Deleting posting-server from PM2..."
                pm2 delete posting-server 2>$null | Out-Null
                pm2 save 2>$null | Out-Null  # Save updated process list
                Write-Host "✅ posting-server PM2 process removed successfully"
            }
            else {
                Write-Host "ℹ️ No posting-server PM2 process found"
            }
        }
        catch {
            Write-Host "⚠️ Error removing PM2 process: $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "ℹ️ PM2 not found - skipping PM2 cleanup"
    }
    
    # Step 2: Find and kill only Node.js processes running from posting_server directory
    if (Test-Path $DirectoryPath) {
        Write-Host "🔍 Finding Node.js processes specific to posting_server..."
        
        try {
            Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object {
                try {
                    $processPath = $_.Path
                    if ($processPath) {
                        $processDir = Split-Path -Parent $processPath
                        $currentDir = Get-Location
                        $postingServerPath = Join-Path $currentDir $DirectoryPath
                        
                        # Check if process is running from our posting_server directory
                        return $processPath -like "*$DirectoryPath*" -or 
                        $processDir -like "*$DirectoryPath*" -or
                        (Test-Path $postingServerPath) -and ($processDir -eq $postingServerPath)
                    }
                    return $false
                }
                catch {
                    return $false
                }
            } | ForEach-Object {
                Write-Host "  Killing posting_server Node.js process: $($_.Id)"
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
            
            Start-Sleep -Seconds 2
        }
        catch {
            Write-Host "⚠️ Error checking Node.js processes: $($_.Exception.Message)"
        }
    }
    
    # Step 3: Remove directory
    if (Test-Path $DirectoryPath) {
        Write-Host "🗑️ Removing directory: $DirectoryPath"
        
        try {
            # Take ownership
            Write-Host "  Taking ownership..."
            takeown /F $DirectoryPath /R /D Y 2>$null | Out-Null
            icacls $DirectoryPath /grant "$($env:USERNAME):F" /T /Q 2>$null | Out-Null
            
            # Remove with PowerShell
            Remove-Item -Recurse -Force $DirectoryPath -ErrorAction Stop
            Write-Host "✅ Directory removed successfully"
            return $true
            
        }
        catch {
            Write-Host "⚠️ PowerShell removal failed: $($_.Exception.Message)"
            
            # Try CMD rd command
            try {
                Write-Host "  Trying CMD rd command..."
                cmd /c "rd /s /q `"$DirectoryPath`"" 2>$null
                if (-not (Test-Path $DirectoryPath)) {
                    Write-Host "✅ Directory removed with CMD"
                    return $true
                }
            }
            catch {}
            
            # Try Robocopy nuclear option
            try {
                Write-Host "  Using robocopy method..."
                $emptyDir = Join-Path $env:TEMP "empty_$(Get-Random)"
                New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
                
                robocopy $emptyDir $DirectoryPath /MIR /R:0 /W:0 2>$null | Out-Null
                Remove-Item -Recurse -Force $DirectoryPath -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $emptyDir -ErrorAction SilentlyContinue
                
                if (-not (Test-Path $DirectoryPath)) {
                    Write-Host "✅ Directory removed with robocopy"
                    return $true
                }
            }
            catch {}
            
            Write-Host "❌ Could not remove directory completely" -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Host "ℹ️ Directory $DirectoryPath does not exist"
        return $true
    }
}

# Enhanced function to remove ALL auto-start configurations
function Remove-AutoStartConfigurations {
    Write-Host "🔧 Removing ALL auto-start configurations..."
    
    $regName = "PM2PostingServerAutoStart"
    $removedCount = 0
    
    # Remove from User Registry
    try {
        $regPathUser = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        $userReg = Get-ItemProperty -Path $regPathUser -Name $regName -ErrorAction SilentlyContinue
        if ($userReg) {
            Remove-ItemProperty -Path $regPathUser -Name $regName -ErrorAction Stop
            Write-Host "✅ Removed user-level registry auto-start"
            $removedCount++
        }
    }
    catch {
        Write-Host "ℹ️ No user-level registry entry found"
    }
    
    # Remove from Machine Registry (if exists and accessible)
    try {
        $regPathMachine = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
        $machineReg = Get-ItemProperty -Path $regPathMachine -Name $regName -ErrorAction SilentlyContinue
        if ($machineReg) {
            Remove-ItemProperty -Path $regPathMachine -Name $regName -ErrorAction Stop
            Write-Host "✅ Removed machine-level registry auto-start"
            $removedCount++
        }
    }
    catch {
        Write-Host "ℹ️ No machine-level registry entry found or access denied"
    }
    
    # Remove User Startup Folder Shortcut
    try {
        $startupFolder = [System.Environment]::GetFolderPath('Startup')
        $shortcutPath = Join-Path $startupFolder "PM2PostingServerAutoStart.lnk"
        
        if (Test-Path $shortcutPath) {
            Remove-Item -Path $shortcutPath -Force -ErrorAction Stop
            Write-Host "✅ Removed user startup folder shortcut"
            $removedCount++
        }
    }
    catch {
        Write-Host "ℹ️ No user startup folder shortcut found"
    }
    
    # Remove All Users Startup Folder Shortcut (NEW)
    try {
        $allUsersStartup = [System.Environment]::GetFolderPath('CommonStartup')
        $allUsersShortcutPath = Join-Path $allUsersStartup "PM2PostingServerAutoStart.lnk"
        
        if (Test-Path $allUsersShortcutPath) {
            Remove-Item -Path $allUsersShortcutPath -Force -ErrorAction Stop
            Write-Host "✅ Removed all users startup folder shortcut"
            $removedCount++
        }
    }
    catch {
        Write-Host "ℹ️ No all users startup folder shortcut found or access denied"
    }
    
    # Remove Scheduled Task (NEW)
    try {
        $taskName = "PM2PostingServerAutoStart"
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        
        if ($task) {
            Write-Host "🕒 Removing scheduled task..."
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
            Write-Host "✅ Removed scheduled task: $taskName"
            $removedCount++
        }
    }
    catch {
        Write-Host "ℹ️ No scheduled task found or couldn't remove"
        
        # Try alternative with schtasks.exe
        try {
            & schtasks /delete /tn "PM2PostingServerAutoStart" /f 2>$null
            Write-Host "✅ Removed scheduled task with schtasks"
            $removedCount++
        }
        catch {}
    }
    
    # Remove Windows Service (Enhanced)
    try {
        $serviceName = "PM2PostingServer"
        $existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        
        if ($existingService) {
            Write-Host "🛑 Stopping and removing Windows service..."
            Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
            
            # Try multiple removal methods
            $serviceRemoved = $false
            
            # Method 1: Remove-Service (PowerShell 6+)
            try {
                Remove-Service -Name $serviceName -ErrorAction Stop
                $serviceRemoved = $true
                Write-Host "✅ Removed Windows service with Remove-Service"
            }
            catch {
                # Method 2: sc.exe
                try {
                    & sc.exe delete $serviceName | Out-Null
                    $serviceRemoved = $true
                    Write-Host "✅ Removed Windows service with sc.exe"
                }
                catch {
                    # Method 3: NSSM (if available)
                    if (Get-Command nssm -ErrorAction SilentlyContinue) {
                        & nssm remove $serviceName confirm | Out-Null
                        $serviceRemoved = $true
                        Write-Host "✅ Removed Windows service with NSSM"
                    }
                }
            }
            
            if ($serviceRemoved) {
                $removedCount++
            }
        }
    }
    catch {
        Write-Host "ℹ️ No Windows service found or couldn't remove"
    }
    
    # Remove ALL startup script files (ENHANCED)
    $currentDir = Get-Location
    $startupFiles = @(
        "pm2-autostart.bat",
        "pm2-autostart.ps1", 
        "pm2-autostart-hybrid.bat",  # NEW
        "pm2-service.ps1",           # NEW
        "pm2-diagnostic.ps1"         # NEW
    )
    
    foreach ($fileName in $startupFiles) {
        $filePath = Join-Path $currentDir $fileName
        if (Test-Path $filePath) {
            try {
                Remove-Item -Path $filePath -Force -ErrorAction Stop
                Write-Host "✅ Removed startup script: $fileName"
                $removedCount++
            }
            catch {
                Write-Host "⚠️ Could not remove startup script: $fileName"
            }
        }
    }
    
    Write-Host "📊 Removed $removedCount auto-start configuration(s)"
}

# Function to remove logs directory
function Remove-LogsDirectory {
    Write-Host "📁 Removing logs directory..."
    
    if (Test-Path "logs") {
        try {
            # Check if logs directory contains only our log files or is safe to remove
            $logFiles = Get-ChildItem -Path "logs" -File
            $ourLogFiles = @("posting-server.log", "autostart.log")
            $safeToRemove = $true
            
            # Check if there are non-posting-server related logs
            foreach ($logFile in $logFiles) {
                if ($logFile.Name -notin $ourLogFiles -and 
                    $logFile.Name -notlike "*posting*" -and 
                    $logFile.Name -notlike "*autostart*") {
                    $safeToRemove = $false
                    break
                }
            }
            
            if ($safeToRemove) {
                Remove-Item -Path "logs" -Recurse -Force -ErrorAction Stop
                Write-Host "✅ Logs directory removed completely"
            }
            else {
                # Only remove our specific log files
                foreach ($ourLog in $ourLogFiles) {
                    $logPath = Join-Path "logs" $ourLog
                    if (Test-Path $logPath) {
                        Remove-Item -Path $logPath -Force -ErrorAction SilentlyContinue
                        Write-Host "✅ Removed log file: $ourLog"
                    }
                }
                Write-Host "ℹ️ Preserved logs directory (contains other log files)"
            }
            
        }
        catch {
            Write-Host "⚠️ Error removing logs directory: $($_.Exception.Message)"
            
            # Try to remove specific log files
            $logFiles = @("posting-server.log", "autostart.log")
            foreach ($logFile in $logFiles) {
                $logPath = Join-Path "logs" $logFile
                if (Test-Path $logPath) {
                    Remove-Item -Path $logPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    else {
        Write-Host "ℹ️ Logs directory does not exist"
    }
}

# NEW: Function to clean up temporary/lock files
function Remove-TempFiles {
    Write-Host "🧹 Cleaning up temporary files..."
    
    $tempFiles = @(
        "$env:TEMP\pm2_autostart_lock.tmp",
        "$env:TEMP\pm2_autostart_ps_lock.tmp"
    )
    
    foreach ($tempFile in $tempFiles) {
        if (Test-Path $tempFile) {
            try {
                Remove-Item -Path $tempFile -Force -ErrorAction Stop
                Write-Host "✅ Removed temp file: $(Split-Path -Leaf $tempFile)"
            }
            catch {
                Write-Host "⚠️ Could not remove temp file: $(Split-Path -Leaf $tempFile)"
            }
        }
    }
}

# Main uninstall process
Write-Host "Starting complete uninstall process..." -ForegroundColor Cyan

# Step 1: Remove posting server directory and PM2 process
Write-Host ""
Write-Host "1️⃣ Removing posting server and PM2 process..."
$serverRemoved = Remove-PostingServerSafely -DirectoryPath "posting_server"

# Step 2: Remove ALL auto-start configurations (Enhanced)
Write-Host ""
Write-Host "2️⃣ Removing ALL auto-start configurations..."
Remove-AutoStartConfigurations

# Step 3: Remove logs directory
Write-Host ""
Write-Host "3️⃣ Removing logs directory..."
Remove-LogsDirectory

# Step 4: Clean up temporary files (NEW)
Write-Host ""
Write-Host "4️⃣ Cleaning up temporary files..."
Remove-TempFiles

# Step 5: Final comprehensive verification
Write-Host ""
Write-Host "5️⃣ Final comprehensive verification..."

# Check if PM2 still has posting-server process
if (Get-Command pm2 -ErrorAction SilentlyContinue) {
    try {
        $processCheck = & pm2 describe posting-server 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "⚠️ Warning: posting-server process still exists in PM2" -ForegroundColor Yellow
            Write-Host "   Run 'pm2 delete posting-server' manually if needed"
        }
        else {
            Write-Host "✅ posting-server process successfully removed from PM2"
        }
        
        # Show remaining PM2 processes
        Write-Host ""
        Write-Host "📊 Remaining PM2 processes:"
        pm2 status
        
    }
    catch {
        Write-Host "ℹ️ Could not verify PM2 status"
    }
}

# Comprehensive check for remaining items
$remainingItems = @()
if (Test-Path "posting_server") { $remainingItems += "posting_server directory" }

# Check all potential startup script files
$startupScripts = @("pm2-autostart.bat", "pm2-autostart.ps1", "pm2-autostart-hybrid.bat", "pm2-service.ps1", "pm2-diagnostic.ps1")
foreach ($script in $startupScripts) {
    if (Test-Path $script) { $remainingItems += $script }
}

# Check logs
if (Test-Path "logs") { 
    $logFiles = Get-ChildItem -Path "logs" -File | Where-Object { 
        $_.Name -like "*posting*" -or $_.Name -like "*autostart*" 
    }
    if ($logFiles.Count -gt 0) { $remainingItems += "posting server log files" }
}

# Check scheduled task
try {
    $task = Get-ScheduledTask -TaskName "PM2PostingServerAutoStart" -ErrorAction SilentlyContinue
    if ($task) { $remainingItems += "scheduled task" }
}
catch {}

# Check Windows service
try {
    $service = Get-Service -Name "PM2PostingServer" -ErrorAction SilentlyContinue
    if ($service) { $remainingItems += "Windows service" }
}
catch {}

Write-Host ""
if ($remainingItems.Count -eq 0) {
    Write-Host "🎉 Complete uninstall successful!" -ForegroundColor Green
    Write-Host "   ALL posting server components have been removed."
}
else {
    Write-Host "⚠️ Uninstall completed with some remaining items:" -ForegroundColor Yellow
    foreach ($item in $remainingItems) {
        Write-Host "   - $item" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "💡 Manual cleanup may be required for remaining items." -ForegroundColor Cyan
}

Write-Host ""
Write-Host "📋 What was removed:" -ForegroundColor Cyan
Write-Host "   ✅ posting-server PM2 process (other PM2 processes preserved)"
Write-Host "   ✅ posting_server directory and all contents"
Write-Host "   ✅ ALL auto-start registry entries (user + machine level)"
Write-Host "   ✅ ALL startup folder shortcuts (user + all users)"
Write-Host "   ✅ Scheduled task (PM2PostingServerAutoStart)"
Write-Host "   ✅ Windows service (PM2PostingServer)"
Write-Host "   ✅ ALL auto-start script files (5 different scripts)"
Write-Host "   ✅ Log files (posting-server.log, autostart.log)"
Write-Host "   ✅ Temporary/lock files"
Write-Host ""
Write-Host "📋 What was preserved:" -ForegroundColor Green
Write-Host "   ✅ Node.js installation"
Write-Host "   ✅ PM2 installation and other PM2 processes"
Write-Host "   ✅ Git installation"
Write-Host "   ✅ Chocolatey installation"
Write-Host "   ✅ Other log files (if any existed)"
Write-Host ""

# Ask if user wants to see PM2 status
if (Get-Command pm2 -ErrorAction SilentlyContinue) {
    Write-Host "💡 To view remaining PM2 processes, run: pm2 status" -ForegroundColor Cyan
    Write-Host "💡 To completely remove PM2 (all processes), run: npm uninstall -g pm2" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "🗑️ Complete Posting Server uninstall process finished!" -ForegroundColor Green