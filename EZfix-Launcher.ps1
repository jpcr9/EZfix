<#
    EZfix-Launcher.ps1
    One-click entry point for non-technical users.

    You normally don't run this file directly - double-click
    Launch-EZfix.bat instead, which runs this with PowerShell 7 (pwsh)
    for you. This file:

      1. Checks if it's running as Administrator. If not, it relaunches
         itself elevated (Windows will show the standard "Do you want
         to allow this app to make changes to your device?" prompt -
         click Yes) and closes the non-elevated copy.
      2. Dot-sources EZfix-Interface.ps1 from the same folder and opens
         the panel.

    This file adds no EZfix functionality of its own - it only makes the
    existing interface launchable with a double-click instead of typing
    PowerShell commands by hand.
#>

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    $scriptPath = $MyInvocation.MyCommand.Path
    $pwshPath = (Get-Process -Id $PID).Path
    Start-Process -FilePath $pwshPath -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}

$interfacePath = Join-Path $PSScriptRoot 'EZfix-Interface.ps1'
if (-not (Test-Path $interfacePath)) {
    Write-Host "EZfix-Interface.ps1 was not found in this folder. Make sure all the EZfix files were extracted together, in the same folder as this one." -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
}

. $interfacePath
Start-EZfixInterface