@echo off
setlocal enabledelayedexpansion

:: Enable command extensions
setlocal EnableExtensions

:: Function to check if a command exists
where node >nul 2>nul
if %errorlevel% neq 0 (
    echo ❌ Node.js is not installed.
    echo Please install Node.js from https://nodejs.org/
    echo After installation, restart this script.
    pause
    exit /b 1
)

where git >nul 2>nul
if %errorlevel% neq 0 (
    echo ❌ Git is not installed.
    echo Please install Git from https://git-scm.com/
    echo After installation, restart this script.
    pause
    exit /b 1
)

:: Check if PM2 is installed, if not install it globally
where pm2 >nul 2>nul
if %errorlevel% neq 0 (
    echo 📦 Installing PM2 globally...
    call npm install -g pm2
    if %errorlevel% neq 0 (
        echo ❌ Failed to install PM2
        pause
        exit /b 1
    )
)

:: Remove existing posting_server directory if it exists
if exist "posting_server" (
    echo 🗑️  Removing existing posting_server directory...
    rmdir /s /q posting_server
)

:: Create logs directory if it doesn't exist
if not exist "logs" (
    mkdir logs
)

:: Setup posting server
echo 🔧 Setting up posting server...

:: Create temporary directory
set "TEMP_DIR=%TEMP%\posting_server_temp_%RANDOM%"
mkdir "%TEMP_DIR%"

:: Clone the repository to temporary directory (shallow clone for efficiency)
echo ⬇️ Downloading complete posting server from GitHub...
git clone --depth 1 https://github.com/Foxiom/server-monitor-tool.git "%TEMP_DIR%"
if %errorlevel% neq 0 (
    echo ❌ Failed to clone repository
    rmdir /s /q "%TEMP_DIR%"
    pause
    exit /b 1
)

:: Copy only the posting_server folder to our target location
xcopy "%TEMP_DIR%\posting_server" "posting_server\" /E /I /H /Y
if %errorlevel% neq 0 (
    echo ❌ Failed to copy posting_server directory
    rmdir /s /q "%TEMP_DIR%"
    pause
    exit /b 1
)

:: Clean up temporary directory
rmdir /s /q "%TEMP_DIR%"

:: Navigate to posting_server directory
cd posting_server

:: Install posting server dependencies
echo 📦 Installing posting server dependencies...
call npm install
if %errorlevel% neq 0 (
    echo ❌ Failed to install dependencies
    cd ..
    pause
    exit /b 1
)

:: Start the server using PM2
echo 🚀 Starting posting server with PM2...
call pm2 start server.js --name "posting-server" --log ../logs/posting-server.log
if %errorlevel% neq 0 (
    echo ❌ Failed to start server with PM2
    cd ..
    pause
    exit /b 1
)

:: Save PM2 process list
call pm2 save

:: Setup PM2 to start on system boot (Windows service)
echo 🔧 Setting up PM2 to start on system boot...
call pm2-windows-startup install
if %errorlevel% neq 0 (
    echo ⚠️  PM2 Windows startup setup failed. You may need to install pm2-windows-startup manually:
    echo    npm install -g pm2-windows-startup
    echo    pm2-windows-startup install
)

:: Go back to original directory
cd ..

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
echo Press any key to exit...
pause >nul