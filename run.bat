@echo off
setlocal enabledelayedexpansion

:: Check if Node.js is installed
where node >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo ❌ Node.js is not installed. Please install Node.js first.
    exit /b 1
)

:: Check if PM2 is installed, if not install it globally
where pm2 >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo 📦 Installing PM2 globally...
    call npm install -g pm2
)

:: Remove existing monitor-tool directory if it exists
if exist "monitor-tool" (
    echo 🗑️  Removing existing monitor-tool directory...
    rmdir /s /q monitor-tool
)

:: Create app directory
mkdir monitor-tool
cd monitor-tool

:: Add timestamp to prevent caching
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set TIMESTAMP=%datetime:~0,14%

:: Download server.js
echo ⬇️ Downloading server.js...
curl -H "Cache-Control: no-cache, no-store, must-revalidate" -H "Pragma: no-cache" -H "Expires: 0" ^
     -o server.js "https://raw.githubusercontent.com/Foxiom/server-monitor-tool/main/server.js?t=%TIMESTAMP%"

:: Download package.json
echo ⬇️ Downloading package.json...
curl -H "Cache-Control: no-cache, no-store, must-revalidate" -H "Pragma: no-cache" -H "Expires: 0" ^
     -o package.json "https://raw.githubusercontent.com/Foxiom/server-monitor-tool/main/package.json?t=%TIMESTAMP%"

:: Install dependencies
echo 📦 Installing dependencies...
call npm install

:: Create logs directory if it doesn't exist
cd ..
if not exist "logs" mkdir logs
cd monitor-tool

:: Set appropriate permissions
echo 🔒 Setting up permissions...
:: Grant full control to current user
icacls "..\logs" /grant "%USERNAME%:(OI)(CI)F" /T
icacls "." /grant "%USERNAME%:(OI)(CI)F" /T
icacls "server.js" /grant "%USERNAME%:F"
icacls "package.json" /grant "%USERNAME%:F"
if exist "package-lock.json" icacls "package-lock.json" /grant "%USERNAME%:F"
icacls "node_modules" /grant "%USERNAME%:(OI)(CI)F" /T

:: Start the server using PM2
echo 🚀 Starting server with PM2...
call pm2 start server.js --name "server-monitor" --log ../logs/server.log

:: Save PM2 process list
call pm2 save

:: Setup PM2 to start on system boot
echo 🔧 Setting up PM2 to start on system boot...
call pm2 startup

echo ✅ Server started and configured to run on system boot!
echo To manage the server, use these PM2 commands:
echo   - pm2 status          # Check server status
echo   - pm2 logs           # View logs
echo   - pm2 stop all       # Stop the server
echo   - pm2 restart all    # Restart the server 