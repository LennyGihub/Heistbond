@echo off
setlocal
rem ===================================================================
rem  Roblox Studio MCP bridge
rem  Lets a CLOUD Claude session use the Studio MCP running on this PC.
rem  Studio MCP (stdio)  ->  supergateway (HTTP, needs a key)  ->  ngrok (https)
rem  Close the two windows it opens to switch the bridge off.
rem ===================================================================

rem 1) Your free static ngrok domain (ngrok dashboard -> Domains)
set "NGROK_DOMAIN=skinny-wages-stopped.ngrok-free.dev"
set "PORT=8765"
set "KEYFILE=%USERPROFILE%\roblox-mcp-bridge-key.txt"
set "HELPER=%USERPROFILE%\roblox-studio-mcp.cmd"

rem Node.js is needed for the gateway
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js is missing. Run:  winget install OpenJS.NodeJS.LTS
  echo Then close this window and start the bridge again.
  pause
  exit /b 1
)

rem 2) Secret key the cloud session must send. Created once, kept on this PC.
if not exist "%KEYFILE%" (
  powershell -NoProfile -Command "$b=New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); [IO.File]::WriteAllText($env:KEYFILE, ([Convert]::ToBase64String($b) -replace '[+/=]',''))"
  echo New bridge key created: %KEYFILE%
)

rem 3) Helper that starts Studio's MCP from its own folder (same as Studio's
rem    "cd /d %LOCALAPPDATA%\Roblox && .\mcp.bat", without the && that npx splits)
> "%HELPER%" echo @echo off
>> "%HELPER%" echo cd /d "%%LOCALAPPDATA%%\Roblox"
>> "%HELPER%" echo call mcp.bat

rem 4) Studio MCP -> local HTTP endpoint on 127.0.0.1 (only reachable through ngrok)
rem    mcp-gateway.js runs ONE Studio MCP shared by every Claude session (supergateway
rem    --stateful started one per session, and they kept stealing Studio's connection)
start "Roblox MCP gateway" cmd /k "set PORT=%PORT%&& set KEYFILE=%KEYFILE%&& set HELPER=%HELPER%&& node "%~dp0mcp-gateway.js""

rem 4b) Image relay: lets Studio upload images from the public game-art repo via localhost
start "Image relay" cmd /k node "%~dp0image-relay.js"

rem 5) Public https address for the cloud session
start "ngrok tunnel" cmd /k ngrok http %PORT% --domain=%NGROK_DOMAIN%

echo.
echo Bridge starting. Cloud sessions connect to: https://%NGROK_DOMAIN%/mcp
echo Keep Roblox Studio open with "MCP Ready". Close the two new windows to stop.
pause
