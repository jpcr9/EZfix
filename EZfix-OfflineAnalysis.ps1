# EZfix-OfflineAnalysis.ps1
<#
    EZfix-OfflineAnalysis.ps1
    EZfix's final module: analysis of an OS disk offline, mounted as a
    data disk (Scoping mode - creates a report folder, fixes nothing,
    only collects evidence).

    This is the project's "anchor" module - the "rescue machine"
    scenario talked about since day 1: a disk with a Windows install
    that won't boot, mounted as a DATA disk on a healthy machine (via
    Disk-Selector) so it can be read without booting it.

    Why it doesn't auto-fix anything: modifying an OS disk that isn't
    yours, without having booted it, is too risky to leave automatic -
    one badly written value can make the disk completely unbootable.
    This module ONLY reads and reports.

    Requires: the disk must already be ONLINE and have a drive letter
    assigned (use Disk-Selector.ps1 first - Show-DiskInventory /
    Set-DataDiskState). If Windows didn't assign a letter on its own,
    assign one by hand in Disk Management (right-click the partition >
    Change Drive Letter).

    Requires PowerShell as Administrator (needed to load the offline
    registry hive, and to temporarily mount the EFI System Partition
    for the BCD check on UEFI disks - see step 4 below).
#>

#Requires -RunAsAdministrator
#Requires -Modules Storage

function Start-EZfixOfflineAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string]$DriveLetter
    )

    $root = "$($DriveLetter):\"
    $windowsPath = Join-Path $root 'Windows'

    if (-not (Test-Path $windowsPath)) {
        Write-Host "No Windows folder was found at $root - check that this is the correct drive letter and that the disk is online." -ForegroundColor Red
        return
    }

    $targetDiskNumber = (Get-Partition -DriveLetter $DriveLetter -ErrorAction Stop).DiskNumber
    $liveDiskNumber = (Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction Stop).DiskNumber
    if ($null -eq $targetDiskNumber -or $null -eq $liveDiskNumber) { throw 'Cannot identify the target and live system disks safely.' }
    if ($targetDiskNumber -eq $liveDiskNumber) { throw 'Offline Analysis cannot target the running Windows disk. Select a secondary disk.' }
    $reportFolder = New-EZfixReportFolder

    Write-Host "=== EZFIX OFFLINE DISK ANALYSIS ===" -ForegroundColor Cyan
    Write-Host "Disk analyzed: $root"
    Write-Host "Report folder: $reportFolder"
    Write-Host ""

    # 1. Installed Windows version - via file version, this does NOT
    # require loading any registry hive. ntoskrnl.exe exists on any
    # Windows install and its file version matches the operating
    # system's build.
    Write-Host "--- 1. Windows version (via file version) ---" -ForegroundColor Yellow
    $kernelPath = Join-Path $windowsPath 'System32\ntoskrnl.exe'
    if (Test-Path $kernelPath) {
        $fileVersion = (Get-Item $kernelPath).VersionInfo.FileVersion
        Write-Host "OK: ntoskrnl.exe version $fileVersion" -ForegroundColor Green
        "ntoskrnl.exe version: $fileVersion" | Out-File (Join-Path $reportFolder 'windows-version.txt')
    }
    else {
        Write-Host "ntoskrnl.exe was not found - this does not look like a valid Windows install." -ForegroundColor Red
    }
    Write-Host ""

    # 2. Computer name - this DOES require reading the registry, so we
    # load the SYSTEM hive offline. This is the same pattern any
    # technician uses to analyze a disk that won't boot.
    #
    # WATCH THIS DETAIL: the active "ControlSet" is not always
    # ControlSet001 - Windows keeps several (ControlSet001, 002, etc.)
    # and stores which one is active in the "Select\Current" key.
    # Blindly assuming ControlSet001 can read old or wrong configuration.
    Write-Host "--- 2. Computer name (offline registry - SYSTEM hive) ---" -ForegroundColor Yellow

    $hiveName = 'EZfixTempHive_' + [guid]::NewGuid().ToString('N')
    $systemHivePath = Join-Path $windowsPath 'System32\config\SYSTEM'
    $hiveLoaded = $false

    if (-not (Test-Path $systemHivePath)) {
        Write-Host "The SYSTEM hive was not found at $systemHivePath" -ForegroundColor Red
    }
    else {
        try {
            $copyFolder=Join-Path $reportFolder 'registry-working-copy'
            New-Item -Path $copyFolder -ItemType Directory -Force | Out-Null
            foreach ($name in @('SYSTEM','SYSTEM.LOG1','SYSTEM.LOG2')) {
                $source=Join-Path (Split-Path $systemHivePath) $name
                if (Test-Path -LiteralPath $source) {
                    $destination=Join-Path $copyFolder $name
                    Copy-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
                    (Get-Item -LiteralPath $destination).IsReadOnly=$false
                }
            }
            $localHive=Join-Path $copyFolder 'SYSTEM'
            $loadResult = & reg.exe load "HKLM\$hiveName" "$localHive" 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "reg.exe load failed: $loadResult"
            }
            $hiveLoaded = $true

            $currentControlSet = (Get-ItemProperty "HKLM:\$hiveName\Select" -Name Current).Current
            $controlSetName = "ControlSet{0:D3}" -f $currentControlSet
            $computerNamePath = "HKLM:\$hiveName\$controlSetName\Control\ComputerName\ComputerName"
            $computerName = (Get-ItemProperty -Path $computerNamePath -Name ComputerName -ErrorAction Stop).ComputerName

            Write-Host "OK: computer name = $computerName (using $controlSetName, the real active one)" -ForegroundColor Green
            "Computer name (offline): $computerName" | Out-File (Join-Path $reportFolder 'offline-registry.txt')
        }
        catch {
            Write-Host "Could not read the hive - $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "The source was not loaded directly. A local working copy is used for registry inspection." -ForegroundColor DarkGray
        }
        finally {
            # CRITICAL: the hive must be unloaded no matter what, or it
            # stays locked until this analysis machine is rebooted. .NET
            # can leave the handle open even after you're "done" reading
            # - forcing garbage collection before unloading is the
            # standard trick to avoid a "the process cannot access the
            # file" error on reg unload.
            if ($hiveLoaded) {
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                Start-Sleep -Milliseconds 500
                & reg.exe unload "HKLM\$hiveName" | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Hive unloaded successfully." -ForegroundColor DarkGray
                }
                else {
                    Write-Host "WARNING: could not cleanly unload the hive - it may stay locked until this analysis machine is rebooted." -ForegroundColor Red
                }
            }
        }
    }
    Write-Host ""

    # 3. Offline Event Logs - this does NOT require loading any hive.
    # Get-WinEvent can read an .evtx file directly from any path with
    # -Path, from whichever disk, booted or not.
    Write-Host "--- 3. Offline event logs (System and Application) ---" -ForegroundColor Yellow

    $logsPath = Join-Path $windowsPath 'System32\winevt\Logs'
    foreach ($logFile in @('System.evtx', 'Application.evtx')) {
        $fullLogPath = Join-Path $logsPath $logFile
        if (-not (Test-Path $fullLogPath)) {
            Write-Host "$logFile was not found at $logsPath" -ForegroundColor Red
            continue
        }
        try {
            $events = Get-WinEvent -FilterHashtable @{ Path = $fullLogPath; Level = 1, 2 } -MaxEvents 50 -ErrorAction Stop
            $outFile = Join-Path $reportFolder "offline-$logFile-errors.csv"
            $events | Select-Object TimeCreated, LevelDisplayName, ProviderName, Id, Message |
                Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8
            Write-Host "OK: $($events.Count) Critical/Error events saved from $logFile" -ForegroundColor Green
        }
        catch {
            if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
                Write-Host "No Critical/Error events in $logFile - a good sign." -ForegroundColor DarkGray
            }
            else {
                Write-Host "Could not read $logFile - $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    Write-Host ""

    # 4. BCD (boot configuration). Two different layouts to handle:
    #    - Legacy BIOS/MBR: the BCD lives inside the Windows partition
    #      itself, at Boot\BCD - the path already mounted here as $root.
    #    - Modern UEFI (the common case today): the BCD instead lives on
    #      the disk's separate EFI System Partition, not the Windows
    #      partition - $root\Boot\BCD genuinely won't exist there. That
    #      partition is FAT32 but deliberately left hidden (no drive
    #      letter) by Windows, so reading it means temporarily giving it
    #      a letter, reading the BCD, then removing the letter again to
    #      leave the partition exactly as it was.
    Write-Host "--- 4. BCD (boot configuration) ---" -ForegroundColor Yellow

    $bcdPath = Join-Path $root 'Boot\BCD'
    $bcdFound = $false

    if (Test-Path $bcdPath) {
        Write-Host "Found BCD at $bcdPath (BIOS/MBR-style layout with a merged System Reserved partition)." -ForegroundColor Green
        try {
            $bcdOutput = & bcdedit /store $bcdPath /enum 2>&1
            if ($LASTEXITCODE -ne 0) { throw "bcdedit failed: $bcdOutput" }; $bcdOutput | Out-File (Join-Path $reportFolder 'bcd-enum.txt')
            Write-Host "OK: boot configuration exported to bcd-enum.txt" -ForegroundColor Green
            $bcdFound = $true
        }
        catch {
            Write-Host "The file was found but could not be read with bcdedit - $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    if (-not $bcdFound) {
        Write-Host "No BCD at $bcdPath - normal on a modern UEFI disk. Checking its EFI System Partition instead..." -ForegroundColor DarkGray

        try {
            $targetDiskNumber = (Get-Partition -DriveLetter $DriveLetter -ErrorAction Stop).DiskNumber

            # Best-effort safety check: skip touching the EFI partition
            # of the disk currently running THIS Windows session - this
            # module is meant for a genuinely offline/foreign disk (see
            # the hive-loading note above), and there's no good reason to
            # add or remove access paths on the live system disk's
            # hidden EFI partition. Only checked if Get-OSDiskNumber
            # happens to already be loaded (Disk-Selector.ps1) - this
            # module does not require it as a hard dependency.
            $isLiveOSDisk = $false
            if (Get-Command Get-OSDiskNumber -ErrorAction SilentlyContinue) {
                $isLiveOSDisk = ($targetDiskNumber -eq (Get-OSDiskNumber))
            }

            if ($isLiveOSDisk) {
                Write-Host "Disk $targetDiskNumber is this machine's own running system disk - skipping the EFI partition check as a precaution (this module is meant for a genuinely offline disk)." -ForegroundColor DarkGray
            }
            else {
                $efiPartition = Get-Partition -DiskNumber $targetDiskNumber -ErrorAction Stop |
                    Where-Object { $_.Type -eq 'System' } |
                    Select-Object -First 1

                if (-not $efiPartition) {
                    Write-Host "No EFI System Partition found on disk $targetDiskNumber either - this disk may use a layout this module doesn't recognize." -ForegroundColor DarkGray
                }
                else {
                    # DriveLetter is the null character (not $null) when
                    # unassigned - same falsy check used elsewhere in EZfix.
                    $assignedTempLetter = $false
                    $efiLetter = $efiPartition.DriveLetter

                    if (-not $efiLetter) {
                        Add-PartitionAccessPath -DiskNumber $targetDiskNumber -PartitionNumber $efiPartition.PartitionNumber -AssignDriveLetter -ErrorAction Stop
                        $efiPartition = Get-Partition -DiskNumber $targetDiskNumber -PartitionNumber $efiPartition.PartitionNumber
                        $efiLetter = $efiPartition.DriveLetter
                        $assignedTempLetter = $true
                    }

                    try {
                        if (-not $efiLetter) {
                            Write-Host "Could not assign a temporary drive letter to the EFI System Partition." -ForegroundColor Red
                        }
                        else {
                            $efiBcdPath = "$($efiLetter):\EFI\Microsoft\Boot\BCD"
                            if (Test-Path $efiBcdPath) {
                                Write-Host "Found BCD at $efiBcdPath (UEFI layout, EFI System Partition temporarily mounted as $($efiLetter):)." -ForegroundColor Green
                                $bcdOutput = & bcdedit /store $efiBcdPath /enum 2>&1
                                if ($LASTEXITCODE -ne 0) { throw "bcdedit failed: $bcdOutput" }; $bcdOutput | Out-File (Join-Path $reportFolder 'bcd-enum.txt')
                                Write-Host "OK: boot configuration exported to bcd-enum.txt" -ForegroundColor Green
                            }
                            else {
                                Write-Host "The EFI System Partition ($($efiLetter):) doesn't have a BCD at the expected path - unusual, worth a manual look." -ForegroundColor Red
                            }
                        }
                    }
                    finally {
                        # Restore the EFI partition to its normal hidden
                        # state - ONLY remove the letter if we're the ones
                        # who assigned it; leave it alone if it already
                        # had one before we got here.
                        if ($assignedTempLetter -and $efiLetter) {
                            Remove-PartitionAccessPath -DiskNumber $targetDiskNumber -PartitionNumber $efiPartition.PartitionNumber -AccessPath "$($efiLetter):\" -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
        }
        catch {
            Write-Host "Could not check the EFI System Partition - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host ""

    Write-Host "=== END OF ANALYSIS ===" -ForegroundColor Cyan
    Write-Host "Evidence saved to: $reportFolder" -ForegroundColor Green
}

<#
    USAGE (run PowerShell as Administrator):
        . .\EZfix-Common.ps1
        . .\EZfix-OfflineAnalysis.ps1
        Start-EZfixOfflineAnalysis -DriveLetter D

    Before this: the data disk must be ONLINE (Disk-Selector.ps1) and
    have a drive letter assigned.
#>

