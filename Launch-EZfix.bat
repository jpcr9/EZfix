@echo off
setlocal enabledelayedexpansion
REM Launch-EZfix.bat
REM Double-click this file to start EZfix. No PowerShell knowledge needed.
REM If PowerShell 7 isn't installed yet, this installs it automatically -
REM no need to visit a website or download anything by hand first.
REM Windows may show one or two security prompts along the way (see the
REM README's "Windows security warnings" section) - click Yes/Allow/Run
REM anyway on those; they're expected, not a sign anything is wrong.

set "PWSH_EXE=pwsh"

where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 goto :run

REM Also check the default install folder directly. This matters right
REM after the auto-install below: this window's PATH was loaded when it
REM opened and won't pick up a brand new pwsh on PATH until it's closed
REM and reopened, so "where pwsh" would still fail even on a successful
REM install if we only checked PATH.
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    set "PWSH_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
    goto :run
)

echo PowerShell 7 was not found on this computer - EZfix needs it to run.
echo Installing it now automatically, this can take a minute or two...
echo.

where winget >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    winget install --id Microsoft.PowerShell -e --accept-source-agreements --accept-package-agreements
) else (
    echo winget is not available on this computer - downloading PowerShell 7 directly instead...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "& { $(irm https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet"
)

if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    set "PWSH_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
    echo.
    echo PowerShell 7 installed successfully.
    echo.
    goto :run
)

echo.
echo The automatic install did not finish successfully.
echo Please install PowerShell 7 by hand from https://aka.ms/PSWindows, then double-click this file again.
pause
exit /b 1

:run
"%PWSH_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0EZfix-Launcher.ps1"