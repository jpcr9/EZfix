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

function Get-EZfixPerformanceCaptureStatus {
    <#
        Reports whether a performance capture is currently running, and
        since when - read-only, used to detect a capture left running
        from a previous session (e.g. EZfix was closed without clicking
        Stop). The marker file is the only place this state lives -
        logman itself runs independently of EZfix's own process, so
        this is how a later session finds a capture a previous one
        started.
    #>
    [CmdletBinding()]
    param()

    $markerPath = Join-Path ([System.IO.Path]::GetTempPath()) 'EZfixPerfCapture.json'
    if (-not (Test-Path -LiteralPath $markerPath)) {
        return [pscustomobject]@{ Running = $false; StartTime = $null }
    }
    try {
        $state = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
        return [pscustomobject]@{ Running = $true; StartTime = [datetime]$state.StartTime }
    }
    catch {
        return [pscustomobject]@{ Running = $false; StartTime = $null }
    }
}

function Start-EZfixPerformanceCapture {
    <#
        Starts a Windows-native Data Collector Set (via logman)
        sampling CPU, memory and disk every 5 seconds, running until
        Stop-EZfixPerformanceCapture is called - open-ended, for
        catching a problem while it's actually happening rather than a
        single point-in-time reading.

        Deliberately built on logman/relog rather than a custom timer -
        reliable background sampling is something Windows already does
        well; EZfix's job here is just starting it, stopping it, and
        turning the result into a report alongside the logs from the
        same window (see Stop-EZfixPerformanceCapture).
    #>
    [CmdletBinding()]
    param()

    if (-not $IsWindows) {
        throw 'Performance capture uses logman, which is Windows-only.'
    }

    $markerPath = Join-Path ([System.IO.Path]::GetTempPath()) 'EZfixPerfCapture.json'
    if (Test-Path -LiteralPath $markerPath) {
        $existing = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
        throw "A capture is already running (started $($existing.StartTime)). Stop it first."
    }

    $collectorName = 'EZfixPerfCapture'
    $captureFolder = Join-Path ([System.IO.Path]::GetTempPath()) ('EZfixPerfCapture_' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $captureFolder -ItemType Directory -Force | Out-Null
    $blgPath = Join-Path $captureFolder 'counters.blg'

    # Same three areas as the single-snapshot check above (CPU, memory,
    # disk) - this isn't a different feature, just the same questions
    # answered over time instead of at one instant.
    $counters = @(
        '\Processor(_Total)\% Processor Time'
        '\Memory\Available MBytes'
        '\PhysicalDisk(_Total)\% Disk Time'
        '\PhysicalDisk(_Total)\Avg. Disk Queue Length'
    )

    $createResult = & logman create counter $collectorName -c $counters -si 5 -o $blgPath -f bin -ow 2>&1
    if ($LASTEXITCODE -ne 0) { throw "logman create failed: $createResult" }

    $startResult = & logman start $collectorName 2>&1
    if ($LASTEXITCODE -ne 0) {
        & logman delete $collectorName 2>&1 | Out-Null
        throw "logman start failed: $startResult"
    }

    $startTime = Get-Date
    [pscustomobject]@{
        CollectorName = $collectorName
        CaptureFolder = $captureFolder
        BlgPath       = $blgPath
        StartTime     = $startTime
    } | ConvertTo-Json | Set-Content -Path $markerPath -Encoding UTF8

    Write-Host "Performance capture started at $startTime. Sampling CPU, memory and disk every 5 seconds." -ForegroundColor Green
    Write-Host "Reproduce the problem now if you can, then run Stop-EZfixPerformanceCapture." -ForegroundColor Green
}

function Stop-EZfixPerformanceCapture {
    <#
        Stops the capture started by Start-EZfixPerformanceCapture,
        converts the counter log to CSV, pulls System/Application
        Critical/Error events from the exact same time window, and
        writes both into one report folder - a correlated view of what
        the machine was doing and what it logged, for the same stretch
        of time.
    #>
    [CmdletBinding()]
    param()

    if (-not $IsWindows) {
        throw 'Performance capture uses logman, which is Windows-only.'
    }

    $markerPath = Join-Path ([System.IO.Path]::GetTempPath()) 'EZfixPerfCapture.json'
    if (-not (Test-Path -LiteralPath $markerPath)) {
        throw 'No performance capture appears to be running. Start one first with Start-EZfixPerformanceCapture.'
    }
    $state = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
    $startTime = [datetime]$state.StartTime
    $endTime = Get-Date

    $stopResult = & logman stop $state.CollectorName 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "WARNING: logman stop reported: $stopResult" -ForegroundColor Red }

    # logman can append its own versioning suffix to the file name given
    # at creation time (e.g. counters_000001.blg instead of
    # counters.blg, depending on Windows version) - rather than assume
    # the exact name, look for whatever .blg file actually landed in
    # the capture folder.
    $actualBlgFile = Get-ChildItem -LiteralPath $state.CaptureFolder -Filter '*.blg' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    $reportFolder = New-EZfixReportFolder
    $csvPath = Join-Path $reportFolder 'performance-capture.csv'

    if (-not $actualBlgFile) {
        Write-Host "Could not find a counter log file in $($state.CaptureFolder) - no performance-capture.csv will be produced this time." -ForegroundColor Red
    }
    else {
        $relogResult = & relog $actualBlgFile.FullName -f CSV -o $csvPath -y 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Could not convert the counter log to CSV - $relogResult" -ForegroundColor Red
        }
        else {
            $minutes = [math]::Round(($endTime - $startTime).TotalMinutes, 1)
            Write-Host "OK: performance counters saved to performance-capture.csv ($minutes minutes captured)" -ForegroundColor Green
        }
    }

    & logman delete $state.CollectorName 2>&1 | Out-Null
    Remove-Item -LiteralPath $state.CaptureFolder -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "--- Logs during the same window ($startTime to $endTime) ---" -ForegroundColor Yellow
    foreach ($logName in @('System','Application')) {
        try {
            $events = Get-WinEvent -FilterHashtable @{ LogName = $logName; Level = 1, 2; StartTime = $startTime; EndTime = $endTime } -ErrorAction Stop
            $outFile = Join-Path $reportFolder "$logName-during-capture.csv"
            $events | Select-Object TimeCreated, LevelDisplayName, ProviderName, Id, Message |
                Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8
            Write-Host "OK: $($events.Count) Critical/Error events saved from $logName during the capture window" -ForegroundColor Green
        }
        catch {
            if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
                Write-Host "No Critical/Error events in $logName during the capture window - a good sign." -ForegroundColor DarkGray
            }
            else {
                Write-Host "Could not read ${logName}: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    Write-Host ""
    Write-Host "Report folder: $reportFolder" -ForegroundColor Cyan
}
