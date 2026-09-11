# Read-only tools for the running Windows computer.
function Start-EZfixSystemOverview {
    [CmdletBinding()]
    param()

    Write-Host '=== THIS PC: SYSTEM OVERVIEW ==='
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $processors = @(Get-CimInstance Win32_Processor -ErrorAction Stop)
    $uptime = (Get-Date) - $os.LastBootUpTime
    Write-Host "Computer: $($computer.Name)"
    Write-Host "Model: $($computer.Manufacturer) $($computer.Model)"
    Write-Host "Windows: $($os.Caption) | Version: $($os.Version) | Build: $($os.BuildNumber)"
    Write-Host "Architecture: $($os.OSArchitecture)"
    Write-Host ("Uptime: {0} days, {1} hours, {2} minutes" -f $uptime.Days,$uptime.Hours,$uptime.Minutes)
    foreach ($processor in $processors) {
        Write-Host "CPU: $($processor.Name.Trim()) | Cores: $($processor.NumberOfCores) | Logical processors: $($processor.NumberOfLogicalProcessors)"
    }
    Write-Host ("Installed RAM: {0:N1} GB | Available memory: {1:N1} GB" -f ($computer.TotalPhysicalMemory / 1GB),($os.FreePhysicalMemory / 1MB))
    Write-Host ''
    Write-Host '--- Graphics adapters ---'
    try {
        $gpus=@(Get-CimInstance Win32_VideoController -ErrorAction Stop)
        foreach($gpu in $gpus) {
            $memory='Not reported'
            # Resolve the driver key for this exact PnP adapter, not by display name.
            try {
                if($gpu.PNPDeviceID) {
                    $driver=(Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Enum\$($gpu.PNPDeviceID)" -Name Driver -ErrorAction Stop).Driver
                    $bytes=(Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driver" -Name 'HardwareInformation.qwMemorySize' -ErrorAction Stop).'HardwareInformation.qwMemorySize'
                    if($bytes -is [byte[]] -and $bytes.Length -eq 8){$bytes=[BitConverter]::ToUInt64($bytes,0)}
                    if($null -ne $bytes -and [uint64]$bytes -gt 0){$memory=('{0:N1} GB (64-bit driver report)' -f ([uint64]$bytes / 1GB))}
                }
            } catch { }
            if($memory -eq 'Not reported' -and $gpu.AdapterRAM -gt 0) {
                $memory=('{0:N1} GB (legacy WMI report; may be inaccurate, especially above 4 GB)' -f ($gpu.AdapterRAM / 1GB))
            }
            Write-Host "GPU: $($gpu.Name) | Adapter memory: $memory"
            Write-Host "Driver: $($gpu.DriverVersion) | Driver date: $($gpu.DriverDate) | Status: $($gpu.Status)"
            if($gpu.CurrentHorizontalResolution -gt 0){Write-Host "Display mode: $($gpu.CurrentHorizontalResolution)x$($gpu.CurrentVerticalResolution) at $($gpu.CurrentRefreshRate) Hz"}
        }
        if(-not $gpus){Write-Host 'No graphics adapters were reported.'}
        Write-Host 'Integrated GPUs may share system RAM; adapter memory is not a measurement of currently available graphics memory.'
    } catch {Write-Warning "GPU information unavailable: $($_.Exception.Message)"}
    Write-Host ''
    Write-Host '--- Firmware and memory modules ---'
    try {
        $bios=Get-CimInstance Win32_BIOS -ErrorAction Stop
        Write-Host "BIOS: $($bios.Manufacturer) | Version: $($bios.SMBIOSBIOSVersion) | Released: $($bios.ReleaseDate)"
    } catch {Write-Warning "BIOS information unavailable: $($_.Exception.Message)"}
    try {
        foreach($module in Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop) {
            Write-Host ("RAM module: {0} | {1:N1} GB | Configured clock: {2} MHz | Manufacturer: {3} | Part: {4}" -f $module.DeviceLocator,($module.Capacity / 1GB),$module.ConfiguredClockSpeed,$module.Manufacturer,([string]$module.PartNumber).Trim())
        }
    } catch {Write-Warning "Memory module information unavailable: $($_.Exception.Message)"}
    Write-Host ''
    Write-Host '--- Local fixed drives ---'
    $drives = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop)
    foreach ($drive in $drives) {
        if ($drive.Size -gt 0) {
            Write-Host ("{0} {1} | Available: {2:N1} GB of {3:N1} GB ({4:N1}% free)" -f $drive.DeviceID,$drive.VolumeName,($drive.FreeSpace / 1GB),($drive.Size / 1GB),(100 * $drive.FreeSpace / $drive.Size))
        }
        else { Write-Host "$($drive.DeviceID) | Capacity unavailable (the volume may be locked)." }
    }
    if (-not $drives) { Write-Host 'No local fixed drives were reported.' }
    Write-Host '=== END OF SYSTEM OVERVIEW ==='
}

function Start-EZfixRecentErrors {
    [CmdletBinding()]
    param()

    $since = (Get-Date).AddHours(-24)
    Write-Host '=== THIS PC: RECENT ERRORS ==='
    Write-Host "System and Application logs since $($since.ToString('yyyy-MM-dd HH:mm:ss')) (local time)."
    Write-Host 'Up to 50 newest Critical/Error events. An event alone does not identify the cause of a problem.'
    $events = @()
    $failedLogs = @()
    foreach ($logName in @('System','Application')) {
        try {
            $events += @(Get-WinEvent -FilterHashtable @{LogName=$logName;Level=1,2;StartTime=$since} -MaxEvents 50 -ErrorAction Stop)
        }
        catch {
            if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
                Write-Host "$logName : no matching events in the last 24 hours."
            }
            else {
                $failedLogs += $logName
                Write-Warning "Could not read $logName : $($_.Exception.Message)"
            }
        }
    }
    $recent = @($events | Sort-Object TimeCreated -Descending | Select-Object -First 50)
    foreach ($event in $recent) {
        Write-Host ''
        Write-Host ("[{0:yyyy-MM-dd HH:mm:ss}] {1} | {2} | Event ID {3}" -f $event.TimeCreated,$event.LogName,$event.ProviderName,$event.Id)
        $message = $event.Message
        if ([string]::IsNullOrWhiteSpace($message)) { $message = 'The event message is unavailable. Use the source and Event ID to investigate.' }
        Write-Host $message
    }
    if ($failedLogs.Count -gt 0) { Write-Warning "Results are incomplete: could not read $($failedLogs -join ', ')." }
    elseif ($recent.Count -eq 0) { Write-Host 'No Critical/Error events found in either log during this period.' }
    Write-Host "Displayed: $($recent.Count) events. Use Collect Evidence if you need CSV files."
    Write-Host '=== END OF RECENT ERRORS ==='
}

function Get-EZfixSecondaryEventPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z]$')][string]$DriveLetter)
    $target = (Get-Partition -DriveLetter $DriveLetter -ErrorAction Stop).DiskNumber
    $live = (Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction Stop).DiskNumber
    if ($null -eq $target -or $null -eq $live) { throw 'Cannot identify the target and running Windows disks.' }
    if ($target -eq $live) { throw 'This is the running Windows disk. Use Collect Evidence under This PC instead.' }
    $path = "${DriveLetter}:\Windows\System32\winevt\Logs"
    if (-not (Test-Path -LiteralPath $path)) { throw "No Windows event log folder found at $path. Check the drive letter in Offline Analysis." }
    return $path
}

