@echo off
setlocal EnableDelayedExpansion

:: Display header
echo ==================================================
echo Setting up Posting Server...
echo ==================================================

:: Function to check if a command exists
:command_exists
if "%~1"=="" (
    echo ❌ Error: No command specified for command_exists.
    pause
    exit /b 1
)
echo Checking for %~1...
where %~1 >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo ✅ %~1 is found.
    exit /b 0
) else (
    echo ❌ %~1 is not found.
    exit /b 1
)

:: Function to install Chocolatey
:install_choco
echo 📦 Installing Chocolatey...
powershell -NoProfile -ExecutionPolicy Bypass -Command "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))"
if %ERRORLEVEL% neq 0 (
    echo ❌ Failed to install Chocolatey.
    pause
    exit /b 1
)
exit /b 0

:: Function to install Node.js
:install_nodejs
echo 📦 Installing Node.js...
choco install nodejs-lts -y
if %ERRORLEVEL% neq 0 (
    echo ❌ Failed to install Node.js.
    pause
    exit /b 1
)
exit /b 0

:: Function to install Git
:install_git
echo 📦 Installing Git...
choco install git -y
if %ERRORLEVEL% neq 0 (
    echo ❌ Failed to install Git.
    pause
    exit /b 1
)
exit /b 0

:: Check and install Chocolatey if not present
call :command_exists choco
if %ERRORLEVEL% neq 0 (
    echo ❌ Chocolatey is not installed.
    call :install_choco
)
echo ✅ Chocolatey is installed.

:: Check and install Node.js if not present
call :command_exists node
if %ERRORLEVEL% neq 0 (
    echo ❌ Node.js is not installed.
    call :install_nodejs
)
echo ✅ Node.js is installed.

:: Check and install Git if not present
call :command_exists git
if %ERRORLEVEL% neq 0 (
    echo ❌ Git is not installed.
    call :install_git
)
echo ✅ Git is installed.

:: Check for PM2, install if missing
call :command_exists pm2
if %ERRORLEVEL% neq 0 (
    echo 📦 Installing PM2 globally...
    npm install -g pm2
    if %ERRORLEVEL% neq 0 (
        echo ❌ Failed to install PM2.
        pause
        exit /b 1
    )
)
echo ✅ PM2 is installed.

:: Remove existing posting_server directory if it exists
if exist posting_server (
    echo 🗑️ Removing existing posting_server directory...
    rmdir /s /q posting_server
    if %ERRORLEVEL% neq 0 (
        echo ❌ Failed to remove posting_server directory.
        pause
        exit /b 1
    )
)

:: Create logs directory
if not exist logs (
    echo 📁 Creating logs directory...
    mkdir logs
    if %ERRORLEVEL% neq 0 (
        echo ❌ Failed to create logs directory.
        pause
        exit /b 1
    )
)

:: Clone the repository to a temporary directory
echo ⬇️ Downloading posting_server from GitHub...
set "TEMP_DIR=%TEMP%\server-monitor-tool-%RANDOM%"
git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git "%TEMP_DIR%"
if %ERRORLEVEL% neq 0 (
    echo ❌ Failed to clone repository.
    rmdir /s /q "%TEMP_DIR%" >nul 2>&1
    pause
    exit /b 1
)

:: Copy posting_server folder
echo 📂 Copying posting_server folder...
xcopy /E /I /Y "%TEMP_DIR%\posting_server" posting_server
if %ERRORLEVEL% neq 0 (
    echo ❌ Failed to copy posting_server folder.
    rmdir /s /q "%TEMP_DIR%" >nul 2>&1
    pause
    exit /b 1
)

:: Clean up temporary directory
rmdir /s /q "%TEMP_DIR%"
if %ERRORLEVEL% neq 0 (
    echo ⚠️ Warning: Failed to clean up temporary directory.
)

:: Navigate to posting_server directory
cd posting_server
if %ERRORLEVEL% neq 0 (
    echo ❌ Failed to navigate to posting_server directory.
    pause
    exit /b 1
)

:: Install dependencies
echo 📦 Installing posting server dependencies...
npm install
if %ERRORLEVEL% neq 0 (
    echo ❌ Failed to install dependencies.
    pause
    exit /b 1
)

:: Set permissions (Windows equivalent: ensure files are writable)
echo 🔒 Setting up permissions...
icacls . /grant "%USERNAME%:F" /T >nul 2>&1
icacls ..\logs /grant "%USERNAME%:F" /T >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ⚠️ Warning: Failed to set permissions. Continuing...
)

:: Start the server with PM2
echo 🚀 Starting posting server with PM2...
pm2 start server.js --name "posting-server" --log ..\logs\posting-server.log
if %ERRORLEVEL% neq 0 (
    echo ❌ Failed to start server with PM2.
    pause
    exit /b 1
)

:: Save PM2 process list
pm2 save
if %ERRORLEVEL% neq 0 (
    echo ⚠️ Warning: Failed to save PM2 process list.
)

:: Setup PM2 to start on system boot
echo 🔧 Setting up PM2 to start on system boot...
pm2 startup
if %ERRORLEVEL% neq 0 (
    echo ⚠️ Warning: Failed to set up PM2 for system boot.
)

:: Display success message
echo.
echo ✅ Server started and configured to run on system boot!
echo 📁 Downloaded complete posting server with all folders:
echo    - config/
echo    - models/
echo    - utils/
echo    - server.js
echo    - package.json
echo.
echo To manage the server, use these PM2 commands:
echo   - pm2 status              # Check server status
echo   - pm2 logs                # View all logs
echo   - pm2 logs posting-server # View posting server logs
echo   - pm2 stop all           # Stop the server
echo   - pm2 restart all        # Restart the server
echo.

endlocal
pause