#Requires -Version 5.1
param([Parameter(Mandatory)][string]$DownloadFolder)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$installerPath = Join-Path $DownloadFolder 'install-powershell.ps1'
Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/install-powershell.ps1' -OutFile $installerPath
& $installerPath -UseMSI -Quiet
