<#
    EZfix-Scoping.ps1
    Modo Scoping de EZfix (version 1, acotada a proposito).

    Diferencia con los modulos de TS (red, rendimiento): esos son rapidos,
    no guardan nada, resuelven lo del dia a dia. Scoping es el paso
    deliberado que se activa cuando el TS basico no alcanzo - crea carpeta
    y empieza a juntar evidencia para investigar mas a fondo despues.

    Que hace esta version 1: crea la carpeta de reporte (via
    New-EZfixReportFolder) y saca los eventos de Error/Warning mas
    recientes de los logs System y Application, filtrados, guardados ahi
    en CSV.

    Que NO hace todavia (fase 2, a proposito no incluido ahora):
    correlacionar eventos entre logs por cercania de tiempo, ni detectar
    si estamos parados en el disco vivo del sistema o en un disco de
    datos que se esta reparando. Eso viene despues, una vez que esto ya
    este funcionando y probado.
#>

# Asegura que la funcion compartida (New-EZfixReportFolder) este cargada.
if (-not (Get-Command New-EZfixReportFolder -ErrorAction SilentlyContinue)) {
    $commonPath = Join-Path $PSScriptRoot "EZfix-Common.ps1"
    if (Test-Path $commonPath) {
        . $commonPath
    }
    else {
        Write-Host "No se encontro EZfix-Common.ps1 en la misma carpeta. Cargalo primero con:  . .\EZfix-Common.ps1" -ForegroundColor Red
        return
    }
}

function Start-EZfixScoping {
    [CmdletBinding()]
    param(
        # Cuantos eventos como maximo traer por log - limite simple para
        # no llenar el CSV de miles de lineas viejas sin valor.
        [int]$MaxEventsPerLog = 50
    )

    $reportFolder = New-EZfixReportFolder

    Write-Host "=== EZFIX SCOPING ===" -ForegroundColor Cyan
    Write-Host "Carpeta de reporte: $reportFolder"
    Write-Host ""

    # Level en el Event Log de Windows: 1 = Critical, 2 = Error, 3 = Warning.
    # Pedimos solo Error y Warning - Info no interesa para esto.
    $logsToCheck = @('System', 'Application')

    foreach ($logName in $logsToCheck) {
        Write-Host "--- Recolectando $logName (Error/Warning) ---" -ForegroundColor Yellow

        try {
            $events = Get-WinEvent -FilterHashtable @{
                LogName = $logName
                Level   = 2, 3
            } -MaxEvents $MaxEventsPerLog -ErrorAction Stop

            $outFile = Join-Path $reportFolder "$logName-errors-warnings.csv"
            $events |
                Select-Object TimeCreated, LevelDisplayName, ProviderName, Id, Message |
                Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8

            Write-Host "OK: $($events.Count) eventos guardados en $outFile" -ForegroundColor Green
        }
        catch {
            # Get-WinEvent lanza un error (no devuelve vacio) cuando no hay
            # eventos que hagan match con el filtro - eso no es una falla,
            # es buena noticia (nada raro reciente en ese log).
            if ($_.Exception.Message -match "No events were found") {
                Write-Host "Sin eventos de Error/Warning recientes en $logName - buena senal." -ForegroundColor DarkGray
            }
            else {
                Write-Host "No se pudo leer $logName : $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        Write-Host ""
    }

    Write-Host "=== SCOPING TERMINADO ===" -ForegroundColor Cyan
    Write-Host "Evidencia guardada en: $reportFolder" -ForegroundColor Green

    return $reportFolder
}

<#
    USO:
        . .\EZfix-Common.ps1
        . .\EZfix-Scoping.ps1
        Start-EZfixScoping
#>
