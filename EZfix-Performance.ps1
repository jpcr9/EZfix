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

    Write-Host "=== EZFIX PERFORMANCE ===" -ForegroundColor Cyan
    Write-Host "Computer: $([System.Net.Dns]::GetHostName())"
    Write-Host "Date:  $(Get-Date)"
    Write-Host ""

    # 1. CPU. Windows tiene un "% de uso ahora mismo" directo (LoadPercentage).
    # Linux no mide CPU igual - el estandar ahi es el load average (cuantos
    # procesos en promedio estan esperando CPU en el ultimo minuto). No son
    # el mismo numero ni se pueden comparar 1 a 1, pero los dos responden
    # la misma pregunta de fondo: "esta la CPU saturada ahora mismo?".
    Write-Host "--- 1. CPU ---" -ForegroundColor Yellow

    if ($IsWindows) {
        $cpuLoad = (Get-CimInstance Win32_Processor -ErrorAction Stop | Measure-Object -Property LoadPercentage -Average).Average
        if ($null -eq $cpuLoad) { throw 'Windows did not return CPU usage data.' }
        Write-Host "Current CPU usage: $cpuLoad%"
        if ($cpuLoad -ge 85) {
            Write-Host "WARNING: CPU is heavily loaded ($cpuLoad%)." -ForegroundColor Red
        }
    }
    else {
        $loadAvg = (Get-Content /proc/loadavg) -split '\s+'
        $cores = [int](nproc)
        Write-Host "Load average (1 min): $($loadAvg[0])  |  Cores: $cores"
        if ([double]$loadAvg[0] -gt $cores) {
            Write-Host "WARNING: load average exceeds the number of cores - CPU is saturated." -ForegroundColor Red
        }
    }
    Write-Host ""

    # 2. Memoria - aca si el concepto es identico en los dos sistemas
    # (cuanta memoria total hay, cuanta esta libre), solo cambia de donde
    # se lee el dato: WMI/CIM en Windows, /proc/meminfo en Linux.
    Write-Host "--- 2. Memory ---" -ForegroundColor Yellow

    if ($IsWindows) {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        if (-not $os.TotalVisibleMemorySize) { throw 'Windows did not return a valid memory total.' }
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
    Write-Host "Total: $totalGB GB  |  Available: $freeGB GB  |  Usage: $usedPct%"
    if ($usedPct -ge 90) {
        Write-Host "WARNING: memory is nearly exhausted ($usedPct%)." -ForegroundColor Red
    }
    Write-Host ""

    # 3. Disco. Get-PSDrive es nativo de PowerShell y corre igual en Windows
    # y Linux (letras de unidad vs. puntos de montaje) - no hace falta
    # branch por sistema operativo aca.
    Write-Host "--- 3. Disk ---" -ForegroundColor Yellow

    Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 } | ForEach-Object {
        $usedGB  = [math]::Round($_.Used / 1GB, 1)
        $freeGB  = [math]::Round($_.Free / 1GB, 1)
        $totalGB = $usedGB + $freeGB
        $pct     = if ($totalGB -gt 0) { [math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }
        $color   = if ($pct -ge 90) { 'Red' } else { 'Green' }
        Write-Host "$($_.Name): $usedGB GB used of $totalGB GB ($pct%)" -ForegroundColor $color
    }
    Write-Host ""

    # 4. Top 5 procesos por CPU. Get-Process tambien es nativo y cross-platform -
    # otra vez, no hace falta branch. Se imprime con Write-Host en vez de
    # Format-Table porque Format-Table depende de como cada terminal maneja
    # el formato de salida - Write-Host con texto armado a mano es mas
    # confiable y se ve igual en cualquier lado.
    Write-Host "--- 4. Top 5 processes (cumulative CPU time) ---" -ForegroundColor Yellow

    $topProcesses = Get-Process |
        Where-Object { $null -ne $_.CPU } |
        Sort-Object CPU -Descending |
        Select-Object -First 5

    foreach ($proc in $topProcesses) {
        $memMB = [math]::Round($proc.WorkingSet / 1MB, 1)
        $cpuTime = [math]::Round($proc.CPU, 1)
        Write-Host ("{0,-25} PID={1,-8} CPU={2,8}s  RAM={3,8} MB" -f $proc.ProcessName, $proc.Id, $cpuTime, $memMB)
    }
    Write-Host ""

    Write-Host '--- 5. Top 5 processes by RAM (working set) ---'
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 | ForEach-Object {
        Write-Host "$($_.ProcessName) | PID: $($_.Id) | RAM: $([math]::Round($_.WorkingSet64/1MB,1)) MB"
    }
    if ($IsWindows) {
        Write-Host '--- 6. Disk activity snapshot ---'
        try {
            $activity=@(Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction Stop | Where-Object Name -ne '_Total')
            if (-not $activity) { Write-Warning 'Disk activity counters unavailable.' }
            foreach ($disk in $activity) {
                Write-Host "$($disk.Name) | Read: $([math]::Round($disk.DiskReadBytesPersec/1MB,2)) MB/s | Write: $([math]::Round($disk.DiskWriteBytesPersec/1MB,2)) MB/s | Current queue: $($disk.CurrentDiskQueueLength)"
            }
        } catch { Write-Warning "Disk activity unavailable: $($_.Exception.Message)" }
        Write-Host '--- 7. Page file usage ---'
        try {
            $pages=@(Get-CimInstance Win32_PageFileUsage -ErrorAction Stop)
            if (-not $pages) { Write-Host 'No page file usage reported.' }
            foreach ($page in $pages) {
                Write-Host "$($page.Name) | Allocated: $($page.AllocatedBaseSize) MB | Current use: $($page.CurrentUsage) MB | Peak use: $($page.PeakUsage) MB"
            }
        } catch { Write-Warning "Page file information unavailable: $($_.Exception.Message)" }
    }
    Write-Host 'These are snapshots. Cumulative process CPU time is not current CPU percentage; working sets can include shared memory. Repeat during the slowdown to compare.'
    Write-Host "=== END OF PERFORMANCE DIAGNOSTICS ===" -ForegroundColor Cyan
}

<#
    USO:
        . .\EZfix-Performance.ps1
        Start-EZfixPerformance
#>

