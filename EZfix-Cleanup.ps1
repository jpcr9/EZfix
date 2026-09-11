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

    Write-Host "=== EZFIX LIMPIEZA ===" -ForegroundColor Cyan
    Write-Host "Equipo: $([System.Net.Dns]::GetHostName())"
    Write-Host "Fecha:  $(Get-Date)"
    Write-Host ""

    $targets = @()
    if ($IsWindows) {
        $targets += [pscustomobject]@{ Name = 'Temp de usuario'; Path = $env:TEMP }
        $targets += [pscustomobject]@{ Name = 'Temp del sistema'; Path = (Join-Path $env:WINDIR 'Temp') }
    }
    else {
        $targets += [pscustomobject]@{ Name = 'Temp del sistema (/tmp)'; Path = '/tmp' }
    }

    $totalFreedMB = 0

    foreach ($target in $targets) {
        Write-Host "--- $($target.Name): $($target.Path) ---" -ForegroundColor Yellow

        if (-not (Test-Path $target.Path)) {
            Write-Host "No existe esta ruta en este equipo." -ForegroundColor DarkGray
            Write-Host ""
            continue
        }

        $files = Get-ChildItem -Path $target.Path -File -Recurse -Force -ErrorAction SilentlyContinue
        $count = $files.Count
        $sizeMB = if ($count -gt 0) { [math]::Round((($files | Measure-Object -Property Length -Sum).Sum) / 1MB, 1) } else { 0 }

        if ($count -eq 0) {
            Write-Host "OK: ya esta limpio, nada que borrar." -ForegroundColor Green
            Write-Host ""
            continue
        }

        Write-Host "$count archivos, $sizeMB MB"

        if ($PSCmdlet.ShouldProcess("$($target.Name) ($count archivos, $sizeMB MB)", "Eliminar archivos temporales")) {
            $deleted = 0
            $deletedBytes = 0
            $locked = 0
            foreach ($file in $files) {
                try {
                    $fileSize = $file.Length
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                    $deleted++
                    $deletedBytes += $fileSize
                }
                catch {
                    $locked++
                }
            }
            $deletedMB = [math]::Round($deletedBytes / 1MB, 1)
            $totalFreedMB += $deletedMB
            Write-Host "Borrados: $deleted archivos ($deletedMB MB liberados)." -ForegroundColor Green
            if ($locked -gt 0) {
                Write-Host "$locked archivo(s) no se pudieron borrar (en uso o sin permiso) - normal, se omiten." -ForegroundColor DarkGray
            }
        }
        Write-Host ""
    }

    # Papelera de reciclaje - solo Windows. No calculamos el tamano antes
    # (leer el contenido de la papelera de forma confiable es mas trabajo
    # del que vale la pena para este modulo) - se reporta solo que se vacio.
    if ($IsWindows) {
        Write-Host "--- Papelera de reciclaje ---" -ForegroundColor Yellow
        if ($PSCmdlet.ShouldProcess("Papelera de reciclaje", "Vaciar")) {
            try {
                Clear-RecycleBin -Force -ErrorAction Stop
                Write-Host "OK: papelera vaciada." -ForegroundColor Green
            }
            catch {
                Write-Host "No se pudo vaciar la papelera - $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        Write-Host ""
    }

    Write-Host "=== FIN DE LA LIMPIEZA - $totalFreedMB MB liberados en total (temporales) ===" -ForegroundColor Cyan
}

<#
    USO:
        . .\EZfix-Cleanup.ps1

        Start-EZfixCleanup -WhatIf
            Modo dry-run: dice cuanto borraria, sin borrar nada.

        Start-EZfixCleanup
            Pregunta confirmacion (s/n) por carpeta, y si aceptas, borra.
#>