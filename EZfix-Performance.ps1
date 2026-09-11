<#
    EZfix-Performance.ps1
    Modulo de rendimiento de EZfix (modo TS - rapido, no persiste nada).

    Alcance a proposito, nada mas: CPU, memoria, disco, y los 5 procesos
    que mas consumen. No hace historial, no alarmas configurables, no
    umbrales ajustables. Si esto no alcanza para explicar el problema,
    el paso siguiente es Scoping (guardar evidencia para investigar mas
    a fondo) - no hacer este modulo mas grande.
#>

# Compat: $IsWindows/$IsLinux son variables automaticas de pwsh (PowerShell 7+).
# En Windows PowerShell 5.1 (lo que hay instalado en esta maquina todavia,
# ver Network-Diagnostics.ps1) esas variables no existen - si no estan
# definidas, las armamos nosotros mismos aca. Asi este modulo corre igual
# sin necesidad de instalar pwsh primero, y de paso el mismo truco
# resuelve el pendiente que tenia Network-Diagnostics.ps1.
if (-not (Test-Path Variable:IsWindows)) {
    $IsWindows = $env:OS -eq 'Windows_NT'
    $IsLinux   = -not $IsWindows
}

function Start-EZfixPerformance {
    [CmdletBinding()]
    param()

    Write-Host "=== EZFIX RENDIMIENTO ===" -ForegroundColor Cyan
    Write-Host "Equipo: $([System.Net.Dns]::GetHostName())"
    Write-Host "Fecha:  $(Get-Date)"
    Write-Host ""

    # 1. CPU. Windows tiene un "% de uso ahora mismo" directo (LoadPercentage).
    # Linux no mide CPU igual - el estandar ahi es el load average (cuantos
    # procesos en promedio estan esperando CPU en el ultimo minuto). No son
    # el mismo numero ni se pueden comparar 1 a 1, pero los dos responden
    # la misma pregunta de fondo: "esta la CPU saturada ahora mismo?".
    Write-Host "--- 1. CPU ---" -ForegroundColor Yellow

    if ($IsWindows) {
        $cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        Write-Host "Uso de CPU actual: $cpuLoad%"
        if ($cpuLoad -ge 85) {
            Write-Host "ALERTA: CPU muy cargada ($cpuLoad%)." -ForegroundColor Red
        }
    }
    else {
        $loadAvg = (Get-Content /proc/loadavg) -split '\s+'
        $cores = [int](nproc)
        Write-Host "Load average (1 min): $($loadAvg[0])  |  Nucleos: $cores"
        if ([double]$loadAvg[0] -gt $cores) {
            Write-Host "ALERTA: load average por encima del numero de nucleos - CPU saturada." -ForegroundColor Red
        }
    }
    Write-Host ""

    # 2. Memoria - aca si el concepto es identico en los dos sistemas
    # (cuanta memoria total hay, cuanta esta libre), solo cambia de donde
    # se lee el dato: WMI/CIM en Windows, /proc/meminfo en Linux.
    Write-Host "--- 2. Memoria ---" -ForegroundColor Yellow

    if ($IsWindows) {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $freeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $usedPct = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)
    }
    else {
        $meminfo = Get-Content /proc/meminfo
        $totalKB = [double](($meminfo | Select-String '^MemTotal:').ToString() -replace '\D', '')
        $availKB = [double](($meminfo | Select-String '^MemAvailable:').ToString() -replace '\D', '')
        $totalGB = [math]::Round($totalKB / 1MB, 1)
        $freeGB  = [math]::Round($availKB / 1MB, 1)
        $usedPct = [math]::Round((($totalKB - $availKB) / $totalKB) * 100, 1)
    }
    Write-Host "Total: $totalGB GB  |  Libre: $freeGB GB  |  Uso: $usedPct%"
    if ($usedPct -ge 90) {
        Write-Host "ALERTA: memoria casi agotada ($usedPct%)." -ForegroundColor Red
    }
    Write-Host ""

    # 3. Disco. Get-PSDrive es nativo de PowerShell y corre igual en Windows
    # y Linux (letras de unidad vs. puntos de montaje) - no hace falta
    # branch por sistema operativo aca.
    Write-Host "--- 3. Disco ---" -ForegroundColor Yellow

    Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 } | ForEach-Object {
        $usedGB  = [math]::Round($_.Used / 1GB, 1)
        $freeGB  = [math]::Round($_.Free / 1GB, 1)
        $totalGB = $usedGB + $freeGB
        $pct     = if ($totalGB -gt 0) { [math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }
        $color   = if ($pct -ge 90) { 'Red' } else { 'Green' }
        Write-Host "$($_.Name): $usedGB GB usados de $totalGB GB ($pct%)" -ForegroundColor $color
    }
    Write-Host ""

    # 4. Top 5 procesos por CPU. Get-Process tambien es nativo y cross-platform -
    # otra vez, no hace falta branch. Se imprime con Write-Host en vez de
    # Format-Table porque Format-Table depende de como cada terminal maneja
    # el formato de salida - Write-Host con texto armado a mano es mas
    # confiable y se ve igual en cualquier lado.
    Write-Host "--- 4. Top 5 procesos (CPU) ---" -ForegroundColor Yellow

    $topProcesses = Get-Process |
        Where-Object { $null -ne $_.CPU } |
        Sort-Object CPU -Descending |
        Select-Object -First 5

    foreach ($proc in $topProcesses) {
        $memMB = [math]::Round($proc.WorkingSet / 1MB, 1)
        $cpuTime = [math]::Round($proc.CPU, 1)
        Write-Host ("{0,-25} PID={1,-8} CPU={2,8}s  MemRAM={3,8} MB" -f $proc.ProcessName, $proc.Id, $cpuTime, $memMB)
    }
    Write-Host ""

    Write-Host "=== FIN DEL DIAGNOSTICO DE RENDIMIENTO ===" -ForegroundColor Cyan
}

<#
    USO:
        . .\EZfix-Performance.ps1
        Start-EZfixPerformance
#>