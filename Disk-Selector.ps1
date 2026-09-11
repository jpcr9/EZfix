# Disk-Selector.ps1
<#
    Disk-Selector.ps1
    Disk selection and online/offline module (Windows)

    Why it exists: to analyze an affected OS disk without booting it,
    you connect it as a data disk to a healthy machine and bring it
    online to read it. The real risk is picking the wrong disk and
    taking the healthy system's own disk offline instead.

    THIS SCRIPT'S SAFETY RULES (these are not optional - they're in the
    code, not just on screen):
      1. The disk containing the currently running operating system can
         NEVER be selected to go offline - the code blocks this even if
         someone tries to force it by passing its number directly.
      2. Before changing any disk's state, exactly what is about to
         happen is shown and explicit confirmation is required. This
         uses PowerShell's native pattern for risky actions:
         SupportsShouldProcess, which automatically gives you -WhatIf
         (show what it would do, without doing it) and -Confirm (ask
         before acting). This isn't something we invented - it's how
         Microsoft expects cmdlets that change system state to be
         written.

    Requires PowerShell running as Administrator (changing disk state
    requires elevated permissions).
#>

#Requires -Modules Storage
#Requires -RunAsAdministrator

function Get-OSDiskNumber {
    # The "system" disk is the one holding the partition the boot drive
    # (usually C:) lives on. We resolve this dynamically instead of
    # assuming "disk 0", because it isn't always disk 0.
    $systemDriveLetter = $env:SystemDrive.TrimEnd(':')
    $partition = Get-Partition -DriveLetter $systemDriveLetter -ErrorAction Stop
    if ($null -eq $partition.DiskNumber) { throw 'Cannot identify the running Windows disk. No disk changes are allowed.' }
    $partition.DiskNumber
}

function Show-DiskInventory {
    $osDiskNumber = Get-OSDiskNumber
    $disks = Get-Disk -ErrorAction Stop | Sort-Object Number

    Write-Host "=== DETECTED DISKS ===" -ForegroundColor Cyan
    Write-Host ""

    foreach ($disk in $disks) {
        $sizeGB = [math]::Round($disk.Size / 1GB, 1)
        $label = "[{0}] {1} - {2} GB - " -f $disk.Number, $disk.FriendlyName, $sizeGB

        # Drive letter(s), if any. Get-Partition still enumerates the
        # partition table on an offline disk, but DriveLetter comes back
        # empty for it (no mounted volume on a disk that's offline) -
        # that's expected, not an error, hence -ErrorAction SilentlyContinue
        # and the "no drive letter" fallback below.
        $driveLetters = (Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveLetter } |
            ForEach-Object { "$($_.DriveLetter):" }) -join ', '
        if (-not $driveLetters) { $driveLetters = 'no drive letter' }

        if ($disk.Number -eq $osDiskNumber) {
            Write-Host $label -NoNewline
            Write-Host "ONLINE" -ForegroundColor Blue -NoNewline
            Write-Host " ($driveLetters, system disk - not selectable)"
        }
        else {
            $statusText = ($disk.OperationalStatus -join ', ').ToUpper()
            $statusColor = if ($disk.OperationalStatus -eq 'Online') { 'Green' } else { 'Red' }
            Write-Host $label -NoNewline
            Write-Host $statusText -ForegroundColor $statusColor -NoNewline
            Write-Host " ($driveLetters)"
        }
    }
    Write-Host ""

    return [pscustomobject]@{
        OSDiskNumber = $osDiskNumber
        Disks        = $disks
    }
}

function Set-DataDiskState {
    # ConfirmImpact = 'High' is what makes PowerShell ask Y/N
    # automatically. Without this, SupportsShouldProcess by itself does
    # NOT ask anything unless you pass -Confirm by hand - ShouldProcess
    # silently returns $true and the action runs straight away. This is
    # the exact cause of the bug you found: -WhatIf worked because it's
    # a separate, explicit check, but the real run didn't ask because
    # the default impact level is 'Medium' and PowerShell's
    # $ConfirmPreference is 'High' - Medium doesn't reach the threshold
    # to prompt on its own.
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [int]$DiskNumber,

        [Parameter(Mandatory)]
        [ValidateSet('Online', 'Offline')]
        [string]$TargetState
    )

    $inventory = Show-DiskInventory

    # Rule 1 in code, not just on screen: if someone passes the system
    # disk's number, it's blocked here, no matter how that value got in.
    if ($DiskNumber -eq $inventory.OSDiskNumber) {
        Write-Host "BLOCKED: disk $DiskNumber is the currently running operating system's disk. It cannot be modified." -ForegroundColor Red
        return
    }

    $disk = $inventory.Disks | Where-Object { $_.Number -eq $DiskNumber }
    if (-not $disk) {
        Write-Host "There is no disk numbered $DiskNumber." -ForegroundColor Red
        return
    }

    if ($disk.IsBoot -or $disk.IsSystem) { throw 'The host boot/system disk cannot be modified.' }
    $sizeGB = [math]::Round($disk.Size / 1GB, 1)
    $isOfflineTarget = ($TargetState -eq 'Offline')

    # ShouldProcess asks "do you really want to do this" with the exact
    # detail of which disk and which action - and with -WhatIf you can
    # try it without anything actually happening. Run it with -WhatIf
    # first to see the message before running it for real.
    $target = "Disk $DiskNumber ($($disk.FriendlyName), $sizeGB GB)"
    if ($PSCmdlet.ShouldProcess($target, "Set to $TargetState")) {
        Set-Disk -Number $DiskNumber -IsOffline:$isOfflineTarget -ErrorAction Stop
        Write-Host "Disk $DiskNumber is now $($TargetState.ToUpper())." -ForegroundColor Green
    }
}

<#
    USAGE EXAMPLES (run these by hand, one at a time, to understand the flow):

    Show-DiskInventory
        Just lists the disks with their status color. Changes nothing.

    Set-DataDiskState -DiskNumber 1 -TargetState Offline -WhatIf
        Shows exactly what it would do, without actually doing it.

    Set-DataDiskState -DiskNumber 1 -TargetState Offline
        Asks for confirmation (y/n) and, if you accept, takes the disk offline.
#>

