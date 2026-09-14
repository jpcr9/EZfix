<#
    EZfix-Cleanup.ps1
    EZfix temp files/cache cleanup module (TS mode - fast, saves
    nothing to disk).

    Deliberately scoped: cleans ONLY user temp, system temp, and (on
    Windows) the Recycle Bin - the "safe" places to clean without real
    risk. "Free up temp space" was already on the list of allowed
    auto-fixes since the project's scope boundary was first defined.
    It doesn't touch browser cache, doesn't touch cookies, doesn't
    delete anything outside these folders - that would be expanding the
    scope without that having been decided.

    Uses the same confirmation pattern as Disk-Selector.ps1
    (SupportsShouldProcess + ConfirmImpact 'High'):
      Start-EZfixCleanup -WhatIf   -> real dry-run mode: reports what it
                                       would delete, without deleting
                                       anything.
      Start-EZfixCleanup           -> asks Y/N before deleting, once
                                       per folder (and again for the
                                       Recycle Bin).
#>

# Same compatibility patch as the other cross-platform modules.
if (-not (Test-Path Variable:IsWindows)) {
    $IsWindows = $env:OS -eq 'Windows_NT'
    $IsLinux   = -not $IsWindows
}

function Start-EZfixCleanup {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param()

    Write-Host "=== EZFIX CLEANUP ===" -ForegroundColor Cyan
    Write-Host "Computer: $([System.Net.Dns]::GetHostName())"
    Write-Host "Date:  $(Get-Date)"
    Write-Host ""

    $targets = @()
    if ($IsWindows) {
        $targets += [pscustomobject]@{ Name = 'User temporary files'; Path = $env:TEMP }
        $targets += [pscustomobject]@{ Name = 'System temporary files'; Path = (Join-Path $env:WINDIR 'Temp') }
    }
    else {
        $targets += [pscustomobject]@{ Name = 'System temporary files (/tmp)'; Path = '/tmp' }
    }

    $cutoff = (Get-Date).AddDays(-7)
    $moduleRoots = @(Get-Module | Where-Object ModuleBase | ForEach-Object { $_.ModuleBase.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar })
    $totalFreedMB = 0

    foreach ($target in $targets) {
        Write-Host "--- $($target.Name): $($target.Path) ---" -ForegroundColor Yellow

        if (-not (Test-Path $target.Path)) {
            Write-Host "This path does not exist on this computer." -ForegroundColor DarkGray
            Write-Host ""
            continue
        }

        $files = @(Get-ChildItem -LiteralPath $target.Path -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object {
            $_.LastWriteTime -lt $cutoff -and $_.CreationTime -lt $cutoff -and
            $_.FullName -notmatch '(?i)[\\/](remoteIpMoProxy|tmp_[^\\/]*|EZfix[^\\/]*)([\\/]|$)' -and
            $_.Extension -notin '.ps1xml','.psm1','.psd1','.ps1' -and
            -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
        })
        $count = $files.Count
        $sizeMB = if ($count -gt 0) { [math]::Round((($files | Measure-Object -Property Length -Sum).Sum) / 1MB, 1) } else { 0 }

        if ($count -eq 0) {
            Write-Host "No eligible old temporary files. Recent files and PowerShell runtime files are preserved." -ForegroundColor Green
            Write-Host ""
            continue
        }

        Write-Host "$count files, $sizeMB MB"

        if ($PSCmdlet.ShouldProcess("$($target.Name) ($count files, $sizeMB MB)", "Delete temporary files")) {
            $deleted = 0
            $deletedBytes = 0
            $locked = 0
            foreach ($file in $files) {
                $activeModuleFile = $false
                foreach ($moduleRoot in $moduleRoots) {
                    if ($file.FullName.StartsWith($moduleRoot,[StringComparison]::OrdinalIgnoreCase)) { $activeModuleFile=$true; break }
                }
                if ($activeModuleFile) { continue }
                try {
                    $fileSize = $file.Length
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                    $deleted++
                    $deletedBytes += $fileSize
                }
                catch {
                    $locked++
                }
            }
            $deletedMB = [math]::Round($deletedBytes / 1MB, 1)
            $totalFreedMB += $deletedMB
            Write-Host "Deleted: $deleted files ($deletedMB MB freed)." -ForegroundColor Green
            if ($locked -gt 0) {
                Write-Host "$locked file(s) could not be deleted (in use or access denied) - skipped." -ForegroundColor DarkGray
            }
        }
        Write-Host ""
    }

    # Recycle Bin - Windows only. We don't calculate its size beforehand
    # (reliably reading the Recycle Bin's contents is more work than
    # this module is worth) - it just reports that it was emptied.
    if ($IsWindows) {
        Write-Host "--- Recycle Bin ---" -ForegroundColor Yellow
        if ($PSCmdlet.ShouldProcess("Recycle Bin", "Empty")) {
            try {
                Clear-RecycleBin -Force -ErrorAction Stop
                Write-Host "OK: Recycle Bin emptied." -ForegroundColor Green
            }
            catch {
                Write-Host "Could not empty the Recycle Bin - $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        Write-Host ""
    }

    Write-Host "=== END OF CLEANUP - $totalFreedMB MB freed from temporary files ===" -ForegroundColor Cyan
}

<#
    USAGE:
        . .\EZfix-Cleanup.ps1

        Start-EZfixCleanup -WhatIf
            Dry-run mode: reports how much it would delete, without deleting anything.

        Start-EZfixCleanup
            Asks for confirmation (y/n) per folder, and deletes if you accept.
#>
