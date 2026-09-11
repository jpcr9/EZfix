param([string]$OutputFolder)

function Find-EZfixVhdFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$OutputFolder,[string[]]$RootPaths)
    $null = New-Item -Path $OutputFolder -ItemType Directory -Force
    if (-not $RootPaths) {
        $RootPaths = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -in @('Fixed','Removable') } | ForEach-Object { $_.RootDirectory.FullName })
    }
    $status = [ordered]@{Roots=@($RootPaths);Directories=0;Found=0;SkippedDirectories=0;SkippedLinks=0;Finished=$false;Cancelled=$false;Error=$null}
    $resultsPath = Join-Path $OutputFolder 'results.jsonl'
    [IO.File]::WriteAllText($resultsPath,'')
    $queue = [Collections.Generic.Queue[string]]::new()
    foreach ($root in $RootPaths) { $queue.Enqueue($root) }
    $cancelPath = Join-Path $OutputFolder 'cancel'
    $clock = [Diagnostics.Stopwatch]::StartNew()
    function Save-SearchStatus {
        $temp = Join-Path $OutputFolder 'status.tmp'
        [IO.File]::WriteAllText($temp,($status | ConvertTo-Json -Compress))
        Move-Item -LiteralPath $temp -Destination (Join-Path $OutputFolder 'status.json') -Force
    }
    Save-SearchStatus
    try {
        while ($queue.Count -gt 0) {
            if ([IO.File]::Exists($cancelPath)) { $status.Cancelled=$true; break }
            $directory = $queue.Dequeue()
            try {
                $info = [IO.DirectoryInfo]::new($directory)
                if ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) { $status.SkippedLinks++; continue }
                $status.Directories++
                foreach ($file in $info.EnumerateFiles()) {
                    if ($file.Extension -in @('.vhd','.vhdx')) {
                        $record = [ordered]@{Path=$file.FullName;Bytes=$file.Length;Modified=$file.LastWriteTime.ToString('s')}
                        [IO.File]::AppendAllText($resultsPath,($record | ConvertTo-Json -Compress)+[Environment]::NewLine)
                        $status.Found++
                    }
                    if ([IO.File]::Exists($cancelPath)) { $status.Cancelled=$true; break }
                }
                if ($status.Cancelled) { break }
                foreach ($child in $info.EnumerateDirectories()) { $queue.Enqueue($child.FullName) }
            }
            catch { $status.SkippedDirectories++ }
            if ($clock.ElapsedMilliseconds -ge 500) { Save-SearchStatus; $clock.Restart() }
        }
    }
    catch { $status.Error=$_.Exception.Message }
    finally { $status.Finished=$true; Save-SearchStatus }
}

if ($OutputFolder) { Find-EZfixVhdFiles -OutputFolder $OutputFolder }

