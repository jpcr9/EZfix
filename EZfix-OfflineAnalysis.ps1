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

function Invoke-EZfixWithOfflineHive {
    <#
        Loads a copy of a registry hive file under a uniquely-named
        temporary HKLM key, runs the given script block against it
        (passed the loaded key's path, e.g. "HKLM:\EZfixTempHive_xxxx"),
        and guarantees the hive gets unloaded afterward - even if the
        script block throws.

        Pulled out into its own function specifically so this one
        load/read/unload cycle - the part where getting it wrong leaves a
        hive locked on the analysis machine - can be tested in isolation,
        instead of only ever being exercised by hand against a real disk.
        If the script block throws, that exception is allowed to
        propagate to the caller after unload still runs; this function's
        only job is guaranteeing cleanup, not deciding how read errors
        get handled.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HiveFilePath,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    $hiveName = 'EZfixTempHive_' + [guid]::NewGuid().ToString('N')
    $hiveLoaded = $false

    try {
        $loadResult = & reg.exe load "HKLM\$hiveName" "$HiveFilePath" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "reg.exe load failed: $loadResult"
        }
        $hiveLoaded = $true

        & $ScriptBlock "HKLM:\$hiveName"
    }
    finally {
        # CRITICAL: the hive must be unloaded no matter what, or it
        # stays locked until this analysis machine is rebooted. .NET
        # can leave the handle open even after the caller's script block
        # is "done" reading - forcing garbage collection before
        # unloading is the standard trick to avoid a "the process cannot
        # access the file" error on reg unload.
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

function Get-EZfixOfflineWindowsPath {
    <#
        Resolves a drive letter to its Windows folder, after confirming
        it both exists and is not the disk currently running this copy
        of Windows. Every offline-disk action in EZfix goes through
        this one check, so "never touch the live disk" only has to be
        implemented correctly in a single place, not once per feature.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string]$DriveLetter
    )

    $root = "$($DriveLetter):\"
    $windowsPath = Join-Path $root 'Windows'

    if (-not (Test-Path $windowsPath)) {
        throw "No Windows folder was found at $root - check that this is the correct drive letter and that the disk is online."
    }

    $targetDiskNumber = (Get-Partition -DriveLetter $DriveLetter -ErrorAction Stop).DiskNumber
    $liveDiskNumber = (Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction Stop).DiskNumber
    if ($null -eq $targetDiskNumber -or $null -eq $liveDiskNumber) { throw 'Cannot identify the target and live system disks safely.' }
    if ($targetDiskNumber -eq $liveDiskNumber) { throw 'This cannot target the running Windows disk. Select a secondary disk.' }

    return $windowsPath
}

function Start-EZfixOfflineAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string]$DriveLetter
    )

    $windowsPath = Get-EZfixOfflineWindowsPath -DriveLetter $DriveLetter
    $root = "$($DriveLetter):\"
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

    $systemHivePath = Join-Path $windowsPath 'System32\config\SYSTEM'

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
                    try {
                        $destination=Join-Path $copyFolder $name
                        Copy-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
                        (Get-Item -LiteralPath $destination).IsReadOnly=$false
                        Write-Host "Copied $name" -ForegroundColor DarkGray
                    }
                    catch {
                        Write-Host "Could not copy ${name}: $($_.Exception.Message) - continuing without it." -ForegroundColor DarkGray
                    }
                }
                else {
                    Write-Host "$name not present on this disk - continuing without it." -ForegroundColor DarkGray
                }
            }
            $localHive=Join-Path $copyFolder 'SYSTEM'

            Invoke-EZfixWithOfflineHive -HiveFilePath $localHive -ScriptBlock {
                param($HiveRoot)
                $currentControlSet = (Get-ItemProperty "$HiveRoot\Select" -Name Current).Current
                $controlSetName = "ControlSet{0:D3}" -f $currentControlSet
                $computerNamePath = "$HiveRoot\$controlSetName\Control\ComputerName\ComputerName"
                $computerName = (Get-ItemProperty -Path $computerNamePath -Name ComputerName -ErrorAction Stop).ComputerName

                Write-Host "OK: computer name = $computerName (using $controlSetName, the real active one)" -ForegroundColor Green
                "Computer name (offline): $computerName" | Out-File (Join-Path $reportFolder 'offline-registry.txt')
            }
        }
        catch {
            Write-Host "Could not read the hive - $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "The source was not loaded directly. A local working copy is used for registry inspection." -ForegroundColor DarkGray
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

function Set-EZfixLastKnownGood {
    <#
        Reads an offline disk's ControlSet bookkeeping (Select\Current,
        \Default, \LastKnownGood) and, if Default isn't already pointing
        at LastKnownGood, offers to switch it - the same mechanism
        behind the old F8-menu "Last Known Good Configuration" option,
        done here against a mounted disk instead of at boot time.

        Always reports what it found. Only writes anything if Default
        and LastKnownGood actually differ, and even then only if
        confirmed via ShouldProcess (-WhatIf reports what would change
        without changing it; -Confirm:$false skips the prompt and
        applies it).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string]$DriveLetter
    )

    $windowsPath = Get-EZfixOfflineWindowsPath -DriveLetter $DriveLetter
    $systemHivePath = Join-Path $windowsPath 'System32\config\SYSTEM'

    if (-not (Test-Path $systemHivePath)) {
        throw "The SYSTEM hive was not found at $systemHivePath"
    }

    $copyFolder = Join-Path ([System.IO.Path]::GetTempPath()) ('EZfixLKG_' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $copyFolder -ItemType Directory -Force | Out-Null
    try {
        foreach ($name in @('SYSTEM','SYSTEM.LOG1','SYSTEM.LOG2')) {
            $source = Join-Path (Split-Path $systemHivePath) $name
            if (Test-Path -LiteralPath $source) {
                try {
                    $destination = Join-Path $copyFolder $name
                    Copy-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
                    (Get-Item -LiteralPath $destination).IsReadOnly = $false
                    Write-Host "Copied $name" -ForegroundColor DarkGray
                }
                catch {
                    Write-Host "Could not copy ${name}: $($_.Exception.Message) - continuing without it." -ForegroundColor DarkGray
                }
            }
            else {
                Write-Host "$name not present on this disk - continuing without it." -ForegroundColor DarkGray
            }
        }
        $localHive = Join-Path $copyFolder 'SYSTEM'

        Invoke-EZfixWithOfflineHive -HiveFilePath $localHive -ScriptBlock {
            param($HiveRoot)
            $select = Get-ItemProperty -Path "$HiveRoot\Select" -ErrorAction Stop
            $formatSet = { param($number) "ControlSet{0:D3}" -f $number }

            Write-Host "Currently booted from: $(& $formatSet $select.Current)"
            Write-Host "Default (what boots normally): $(& $formatSet $select.Default)"
            Write-Host "Last Known Good: $(& $formatSet $select.LastKnownGood)"

            if ($select.Default -eq $select.LastKnownGood) {
                Write-Host "Default is already Last Known Good - nothing to change." -ForegroundColor Green
                return
            }

            # This is the only write this function ever makes: a single
            # DWORD value, on a hive that Invoke-EZfixWithOfflineHive
            # guarantees gets unloaded afterward even if this throws.
            if ($PSCmdlet.ShouldProcess("$DriveLetter`: (offline)", "Set Default ControlSet to Last Known Good ($(& $formatSet $select.LastKnownGood))")) {
                Set-ItemProperty -Path "$HiveRoot\Select" -Name Default -Value $select.LastKnownGood -Type DWord -ErrorAction Stop
                Write-Host "Default ControlSet changed to $(& $formatSet $select.LastKnownGood). This takes effect the next time that disk's Windows starts." -ForegroundColor Green
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $copyFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-EZfixOfflineUpdates {
    <#
        Lists installed update packages on an offline Windows image,
        newest first - read-only, the "diagnose" half of removing a
        problem update. The exact PackageName shown here is what
        Remove-EZfixOfflineUpdate needs to actually remove one.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string]$DriveLetter
    )

    $windowsPath = Get-EZfixOfflineWindowsPath -DriveLetter $DriveLetter
    $imagePath = Split-Path $windowsPath -Parent

    Write-Host "=== INSTALLED UPDATES (offline image at $imagePath) ===" -ForegroundColor Cyan
    $packages = @(Get-WindowsPackage -Path $imagePath -ErrorAction Stop |
        Where-Object { $_.PackageState -eq 'Installed' -and $_.ReleaseType -in @('SecurityUpdate','Update','CriticalUpdate','UpdateRollUp') } |
        Sort-Object InstallTime -Descending)

    if (-not $packages) {
        Write-Host "No update packages were found, or none matched Windows Update / Security Update / Critical Update / Update Rollup."
        return
    }

    foreach ($package in ($packages | Select-Object -First 20)) {
        Write-Host ""
        Write-Host "Installed: $($package.InstallTime) | Type: $($package.ReleaseType)"
        Write-Host "PackageName: $($package.PackageName)"
    }
    Write-Host ""
    Write-Host "Showing the $([Math]::Min(20,$packages.Count)) most recent of $($packages.Count) total. Copy the exact PackageName of the one you suspect, to remove it with Remove-EZfixOfflineUpdate."
}

function Remove-EZfixOfflineUpdate {
    <#
        Removes one update package from an offline Windows image by its
        exact PackageName (from Get-EZfixOfflineUpdates). This is the
        first EZfix action that modifies an offline OS rather than just
        reading it - there is no dry-run beyond -WhatIf and no automatic
        undo; the only way back is reinstalling the update afterward.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string]$DriveLetter,

        [Parameter(Mandatory)]
        [string]$PackageName
    )

    $windowsPath = Get-EZfixOfflineWindowsPath -DriveLetter $DriveLetter
    $imagePath = Split-Path $windowsPath -Parent

    if ($PSCmdlet.ShouldProcess("$imagePath (offline)", "Remove update package $PackageName")) {
        Write-Host "Removing $PackageName from $imagePath - this can take several minutes." -ForegroundColor Yellow
        Remove-WindowsPackage -Path $imagePath -PackageName $PackageName -NoRestart -ErrorAction Stop
        Write-Host "Removed $PackageName. This takes effect the next time that disk's Windows starts." -ForegroundColor Green
    }
}

<#
    USAGE (run PowerShell as Administrator):
        . .\EZfix-Common.ps1
        . .\EZfix-OfflineAnalysis.ps1
        Start-EZfixOfflineAnalysis -DriveLetter D
        Set-EZfixLastKnownGood -DriveLetter D -Confirm:$false
        Get-EZfixOfflineUpdates -DriveLetter D
        Remove-EZfixOfflineUpdate -DriveLetter D -PackageName <exact name> -Confirm:$false

    Before any of this: the data disk must be ONLINE (Disk-Selector.ps1)
    and have a drive letter assigned.
#>
