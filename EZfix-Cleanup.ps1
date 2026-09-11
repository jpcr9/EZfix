<#
    EZfix-Cleanup.ps1
    Modulo de limpieza de temporales/cache de EZfix (modo TS - rapido,
    no persiste nada).

    Alcance a proposito: limpia SOLO temporales de usuario, temporales
    del sistema, y (en Windows) la papelera de reciclaje - los lugares
    "seguros" de limpiar sin riesgo real. "Liberar espacio de temporales"
    ya estaba en la lista de arreglos automaticos permitidos desde que
    se definio el limite de alcance del proyecto. No toca cache de
    navegador, no toca cookies, no borra nada fuera de estas carpetas -
    eso seria expandir el alcance sin que se haya decidido asi.

    Usa el mismo patron de confirmacion que Disk-Selector.ps1
    (SupportsShouldProcess + ConfirmImpact 'High'):
      Start-EZfixCleanup -WhatIf   -> modo dry-run real: dice que borraria,
                                       sin borrar nada.
      Start-EZfixCleanup           -> pregunta Y/N antes de borrar,
                                       una vez por carpeta (y otra vez
                                       para la papelera).
#>

# Mismo parche de compatibilidad que los demas modulos cross-platform.
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

    # Recycle Bin - solo Windows. No calculamos el tamano antes
    # (leer el contenido de la papelera de forma confiable es mas trabajo
    # del que vale la pena para este modulo) - se reporta solo que se vacio.
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
    USO:
        . .\EZfix-Cleanup.ps1

        Start-EZfixCleanup -WhatIf
            Modo dry-run: dice cuanto borraria, sin borrar nada.

        Start-EZfixCleanup
            Pregunta confirmacion (s/n) por carpeta, y si aceptas, borra.
#>

