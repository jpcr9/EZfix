#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
try {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList ('-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath) -Verb RunAs -WindowStyle Hidden -ErrorAction Stop
        exit
    }
    foreach ($file in @('EZfix-Interface.ps1','EZfix-Common.ps1','Disk-Selector.ps1','EZfix-OfflineAnalysis.ps1','EZfix-Performance.ps1','EZfix-Cleanup.ps1','EZfix-RDP.ps1','EZfix-Connectivity.ps1','EZfix-SystemTools.ps1','EZfix-VirtualDisks.ps1','EZfix-VhdFinder.ps1','EZfix-FindVirtualDisks.ps1','EZfix-CategoryScoping.ps1','Network-Diagnostics.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file))) { throw "$file is missing. Extract the entire ZIP into one folder." }
    }
    $missingModules = @('Storage','NetSecurity','NetTCPIP','DnsClient','Microsoft.PowerShell.LocalAccounts' | Where-Object { -not (Get-Module -ListAvailable -Name $_) })
    if ($missingModules.Count -gt 0) {
        [Windows.Forms.MessageBox]::Show("Some Windows components are unavailable: $($missingModules -join ', '). Features that need them may not work. PowerShell installation is handled automatically at startup.", 'EZfix - Component check', 'OK', 'Warning') | Out-Null
    }
    . (Join-Path $PSScriptRoot 'EZfix-Interface.ps1')
    Start-EZfixInterface
} catch {
    [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'EZfix could not open', 'OK', 'Error') | Out-Null
    exit 1
}



