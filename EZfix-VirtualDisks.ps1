# Uses the built-in Windows Storage module; the Hyper-V module is not required.
# Only images attached by this EZfix session can be detached through these helpers.
$script:EZfixMountedImages = @{}

function Open-EZfixVhd {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$ImagePath)
    if ([IO.Path]::GetExtension($ImagePath) -notin @('.vhd','.vhdx')) { throw 'Select a .vhd or .vhdx file.' }
    if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) { throw 'The selected image file does not exist.' }
    $path = (Get-Item -LiteralPath $ImagePath -ErrorAction Stop).FullName
    $image = Get-DiskImage -ImagePath $path -ErrorAction Stop
    if ($image.Attached) { throw 'This image is already attached. Its existing connection has not been changed. Use Detect Disks to see it, or detach it in Windows before opening it here read-only.' }
    if (-not $PSCmdlet.ShouldProcess($path,'Attach VHD/VHDX read-only')) { return }
    Mount-DiskImage -ImagePath $path -Access ReadOnly -PassThru -ErrorAction Stop | Out-Null
    try {
        $disks = @(Get-DiskImage -ImagePath $path -ErrorAction Stop | Get-Disk -ErrorAction Stop)
        if ($disks.Count -ne 1 -or -not $disks[0].IsReadOnly -or $disks[0].IsBoot -or $disks[0].IsSystem) { throw 'Windows did not expose one read-only data disk.' }
        $disk = $disks[0]
        $script:EZfixMountedImages[$path] = $disk.Number
        $letters = @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | ForEach-Object { [string]$_.DriveLetter })
        $windowsLetters = @($letters | Where-Object { Test-Path -LiteralPath "${_}:\Windows\System32" })
        return [pscustomobject]@{ImagePath=$path;DiskNumber=$disk.Number;IsReadOnly=$true;WindowsDriveLetter=$(if ($windowsLetters.Count -eq 1) {$windowsLetters[0]} else {$null});DriveLetters=($letters -join ', ')}
    }
    catch {
        # This call attached the image; undo the incomplete operation.
        try { Dismount-DiskImage -ImagePath $path -ErrorAction Stop } catch { Write-Warning "Could not undo the attachment of $path. Detach it through Windows Disk Management." }
        $script:EZfixMountedImages.Remove($path)
        throw
    }
}

function Close-EZfixVhd {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$ImagePath)
    if (-not $script:EZfixMountedImages.ContainsKey($ImagePath)) { throw 'This image was not attached by this EZfix session. Its connection will not be changed.' }
    $image = Get-DiskImage -ImagePath $ImagePath -ErrorAction Stop
    if (-not $image.Attached) { $script:EZfixMountedImages.Remove($ImagePath); return }
    $disks = @($image | Get-Disk -ErrorAction Stop)
    $live = (Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction Stop).DiskNumber
    if ($null -eq $live -or $disks.Count -ne 1 -or $disks[0].Number -ne $script:EZfixMountedImages[$ImagePath] -or $disks[0].Number -eq $live -or $disks[0].IsBoot -or $disks[0].IsSystem -or -not $disks[0].IsReadOnly) { throw 'Disk identity or read-only state changed. Detachment has been blocked.' }
    if ($PSCmdlet.ShouldProcess($ImagePath,'Detach VHD/VHDX (keep the file)')) {
        Dismount-DiskImage -ImagePath $ImagePath -ErrorAction Stop
        $script:EZfixMountedImages.Remove($ImagePath)
    }
}
