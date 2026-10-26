@echo off
setlocal enableextensions enabledelayedexpansion

REM ========= CONFIGURATION =========
REM app.dart
set "DART_FILE=%~dp0..\..\lib\app\app.dart"
REM Outputs
set "AGENT_PAYLOAD_DIR=%~dp0OCSInventory-Agent-Setup\payload\OCSInventory-Agent"
set "AGENT_OUT_NAME=ocsinventory-agent.exe"

REM OCSInventory Service solution path
set "SERVICE_SOLUTION=%~dp0OCSInventory-Service\OCSInventory-Service.csproj"
set "CONFIG=Release"
set "PLATFORM=Any CPU"

REM Release version, set to the tag by .github/workflows/release.yml
set "DOTNET_VERSION_ARG="
set "DART_VERSION_ARG="
if defined APP_VERSION (
  set "DOTNET_VERSION_ARG=-p:Version=%APP_VERSION%"
  set "DART_VERSION_ARG=-DAPP_VERSION=%APP_VERSION%"
)

REM ========= BUILDS =========
echo ========================================================
echo === [1/2] Service build (dotnet) - %CONFIG% ^| %PLATFORM% ===
echo ========================================================
echo Solution: "%SERVICE_SOLUTION%"
echo Clean solution...
call dotnet clean "%SERVICE_SOLUTION%" -c %CONFIG% -p:Platform="%PLATFORM%"
if errorlevel 1 (
  echo [ERROR] Clean failure
  exit /b 31
)
echo Publish solution...
dotnet publish "%SERVICE_SOLUTION%" -c %CONFIG% -p:Platform="%PLATFORM%" -maxcpucount -f net9.0 -r win-x64 --self-contained true -p:PublishSingleFile=true %DOTNET_VERSION_ARG%
if errorlevel 1 (
  echo [ERROR] dotnet publish failed
  exit /b 3
)

echo ================================
echo === [2/2] Agent build (dart) ===
echo ================================
for /f "delims=" %%i in ('where dart 2^>nul') do set "DART_CMD=%%i"
if not defined DART_CMD set "DART_CMD=dart"
if not exist "%AGENT_PAYLOAD_DIR%" mkdir "%AGENT_PAYLOAD_DIR%" 2>nul

echo %DART_CMD% compile exe %DART_VERSION_ARG% "%DART_FILE%" -o "%AGENT_PAYLOAD_DIR%\%AGENT_OUT_NAME%"
call "%DART_CMD%" compile exe %DART_VERSION_ARG% "%DART_FILE%" -o "%AGENT_PAYLOAD_DIR%\%AGENT_OUT_NAME%"
if errorlevel 1 (
  echo [ERROR] dart compilation failed
  exit /b 2
)
echo [OK] Agent : "%AGENT_PAYLOAD_DIR%\%AGENT_OUT_NAME%"

echo ================
echo === Finished ===
echo ================
endlocal
exit /b 0
