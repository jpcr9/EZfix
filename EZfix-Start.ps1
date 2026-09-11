#Requires -Version 5.1
param([switch]$SkipDesktopShortcut)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
function New-EZfixDesktopShortcut {
    param([string]$DesktopPath,[string]$StartPath)
    $shortcutPath = Join-Path $DesktopPath 'EZfix.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    if ((Test-Path -LiteralPath $shortcutPath) -and $shortcut.Description -ne 'EZfix - IT support diagnostics') { return }
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shortcut.Arguments = '-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $StartPath
    $shortcut.WorkingDirectory = Split-Path -Parent $StartPath
    $shortcut.Description = 'EZfix - IT support diagnostics'
    $shortcut.IconLocation = "$($shortcut.TargetPath),0"
    $shortcut.Save()
}
function Find-EZfixPowerShell {
    $candidates = @()
    if ($env:ProgramW6432) { $candidates += Join-Path $env:ProgramW6432 'PowerShell\7\pwsh.exe' }
    $candidates += Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    $candidates += @(Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate) {
            if ([Diagnostics.FileVersionInfo]::GetVersionInfo($candidate).FileMajorPart -ge 7) { return $candidate }
        }
    }
    return $null
}
try {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'EZfix-Launcher.ps1'))) { throw 'Extract the entire ZIP before starting EZfix.' }
    # Run before elevation so the shortcut belongs to the person who opened EZfix.
    if (-not $SkipDesktopShortcut) {
        try { New-EZfixDesktopShortcut -DesktopPath ([Environment]::GetFolderPath('Desktop')) -StartPath $PSCommandPath }
        catch { [Windows.Forms.MessageBox]::Show('The desktop shortcut could not be created. You can still open EZfix using Launch-EZfix.bat.','EZfix','OK','Information') | Out-Null }

    }
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) {
        Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -SkipDesktopShortcut' -f $PSCommandPath) -ErrorAction Stop
        exit
    }
    $pwsh = Find-EZfixPowerShell
    if (-not $pwsh) {
        $answer = [Windows.Forms.MessageBox]::Show('EZfix needs PowerShell 7. Download and install it from Microsoft now? Internet access is required. Installation may take several minutes.', 'EZfix - First-time setup', 'YesNo', 'Question')
        if ($answer -ne 'Yes') { exit }
        $setupFolder = Join-Path ([IO.Path]::GetTempPath()) ('EZfix-setup-' + [guid]::NewGuid().ToString('N'))
        New-Item -Path $setupFolder -ItemType Directory | Out-Null
        $progress = New-Object Windows.Forms.Form
        $progress.Text = 'EZfix - Installing PowerShell 7'
        $progress.ClientSize = New-Object Drawing.Size(440,100)
        $progress.StartPosition = 'CenterScreen'
        $progress.ControlBox = $false
        $label = New-Object Windows.Forms.Label
        $label.Text = 'Installing PowerShell 7. Please wait...'
        $label.SetBounds(20,20,400,25)
        $bar = New-Object Windows.Forms.ProgressBar
        $bar.Style = 'Marquee'
        $bar.SetBounds(20,55,400,20)
        $progress.Controls.AddRange(@($label,$bar))
        $progress.Show()
        [Windows.Forms.Application]::DoEvents()
        try {
            $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
            if ($winget) {
                try {
                $installer = Start-Process -FilePath $winget.Source -WindowStyle Hidden -PassThru -ArgumentList 'install --id Microsoft.PowerShell -e --silent --accept-source-agreements --accept-package-agreements --disable-interactivity' -RedirectStandardOutput (Join-Path $setupFolder 'winget-out.txt') -RedirectStandardError (Join-Path $setupFolder 'winget-error.txt')
                while (-not $installer.HasExited) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 150 }
                $pwsh = Find-EZfixPowerShell
                } catch { $_ | Out-File (Join-Path $setupFolder 'winget-start-error.txt') }
            }
            if (-not $pwsh) {
                $label.Text = 'Using the Microsoft download installer. Please wait...'
                $progress.Refresh()
                $worker = Join-Path $PSScriptRoot 'EZfix-InstallPowerShell.ps1'
                $installer = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -WindowStyle Hidden -PassThru -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -DownloadFolder "{1}"' -f $worker,$setupFolder) -RedirectStandardOutput (Join-Path $setupFolder 'installer-out.txt') -RedirectStandardError (Join-Path $setupFolder 'installer-error.txt')
                while (-not $installer.HasExited) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 150 }
                $pwsh = Find-EZfixPowerShell

            }
            if (-not $pwsh) { throw "PowerShell 7 was not found after installation. Install it from https://aka.ms/PSWindows and try again. Setup logs: $setupFolder" }
        } finally { $progress.Close(); $progress.Dispose() }
    }
    $launcher = Join-Path $PSScriptRoot 'EZfix-Launcher.ps1'
    if (-not (Test-Path -LiteralPath $launcher)) { throw 'EZfix-Launcher.ps1 is missing. Extract the entire ZIP into one folder.' }
    Start-Process -FilePath $pwsh -WindowStyle Hidden -ArgumentList ('-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $launcher) -ErrorAction Stop
} catch {
    [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'EZfix could not start', 'OK', 'Error') | Out-Null
    exit 1
}



