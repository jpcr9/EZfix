function Show-EZfixVhdFinder {
    [CmdletBinding()]
    param([System.Windows.Forms.Form]$Owner)
    $folder = Join-Path ([IO.Path]::GetTempPath()) ('EZfix-search-' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $folder -ItemType Directory -Force | Out-Null
    $dialog = [Windows.Forms.Form]::new()
    $dialog.Text = 'Find VHD/VHDX on this computer'
    $dialog.Size = [Drawing.Size]::new(950,530)
    $dialog.MinimumSize = [Drawing.Size]::new(700,400)
    $dialog.StartPosition = 'CenterParent'
    $dialog.Font = [Drawing.Font]::new('Segoe UI',9)
    $statusLabel = [Windows.Forms.Label]::new()
    $statusLabel.SetBounds(12,12,730,50)
    $statusLabel.Anchor = 'Top,Left,Right'
    $statusLabel.Text = 'Searching local fixed and removable drives. Network drives and directory links are excluded.'
    $cancel = [Windows.Forms.Button]::new()
    $cancel.Text = 'Stop search'
    $cancel.SetBounds(790,12,130,30)
    $cancel.Anchor = 'Top,Right'
    $grid = [Windows.Forms.DataGridView]::new()
    $grid.SetBounds(12,70,908,365)
    $grid.Anchor = 'Top,Bottom,Left,Right'
    $grid.ReadOnly=$true; $grid.AllowUserToAddRows=$false; $grid.AllowUserToDeleteRows=$false
    $grid.SelectionMode='FullRowSelect'; $grid.MultiSelect=$false; $grid.RowHeadersVisible=$false
    [void]$grid.Columns.Add('Path','Full path')
    [void]$grid.Columns.Add('Size','File size (GB)')
    $grid.Columns[0].AutoSizeMode='Fill'; $grid.Columns[1].Width=120
    $open = [Windows.Forms.Button]::new()
    $open.Text='Open selected read-only'
    $open.SetBounds(12,445,220,32)
    $open.Anchor='Bottom,Left'; $open.Enabled=$false
    $close = [Windows.Forms.Button]::new()
    $close.Text='Close'; $close.SetBounds(810,445,110,32); $close.Anchor='Bottom,Right'
    $dialog.Controls.AddRange(@($statusLabel,$cancel,$grid,$open,$close))
    $state = @{Process=$null;ExitPolls=0;Seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)}
    $timer = [Windows.Forms.Timer]::new(); $timer.Interval=750
    $timer.Add_Tick({
        $statusFile=Join-Path $folder 'status.json'
        if (Test-Path -LiteralPath $statusFile) {
            try {
                $progress=Get-Content -LiteralPath $statusFile -Raw -ErrorAction Stop | ConvertFrom-Json
                foreach ($line in Get-Content -LiteralPath (Join-Path $folder 'results.jsonl') -ErrorAction Stop) {
                    try {
                        $entry=$line | ConvertFrom-Json -ErrorAction Stop
                        if ($state.Seen.Add($entry.Path)) { [void]$grid.Rows.Add($entry.Path,([math]::Round($entry.Bytes / 1GB,2))) }
                    } catch { }
                }
                $prefix=if ($progress.Cancelled) {'Stopped (partial results)'} elseif ($progress.Finished) {'Finished'} else {'Searching'}
                $statusLabel.Text="$prefix : $($progress.Found) images, $($progress.Directories) folders. Unreadable folders: $($progress.SkippedDirectories); skipped directory links: $($progress.SkippedLinks)."
                if ($progress.Error) { $statusLabel.Text="Search incomplete: $($progress.Error)" }
                if ($progress.Finished) { $timer.Stop(); $cancel.Enabled=$false }
                elseif ($state.Process -and $state.Process.HasExited) {
                    $state.ExitPolls++
                    if ($state.ExitPolls -ge 3) { $statusLabel.Text="Search stopped unexpectedly; results may be incomplete. Details: $folder"; $timer.Stop(); $cancel.Enabled=$false }
                }
                $open.Enabled=$grid.Rows.Count -gt 0
            } catch { }
        }
        if ($state.Process -and $state.Process.HasExited -and -not (Test-Path -LiteralPath $statusFile)) {
            $statusLabel.Text="Search could not start. Details: $folder"
            $timer.Stop(); $cancel.Enabled=$false
        }
    })
    $cancel.Add_Click({ [IO.File]::WriteAllText((Join-Path $folder 'cancel'),''); $cancel.Enabled=$false; $statusLabel.Text='Stopping search...' })
    $close.Add_Click({ $dialog.Close() })
    $open.Add_Click({
        if ($grid.SelectedRows.Count -gt 0) { $dialog.Tag=[string]$grid.SelectedRows[0].Cells[0].Value; $dialog.DialogResult='OK'; $dialog.Close() }
    })
    $dialog.Add_Shown({
        try {
            $worker=Join-Path $PSScriptRoot 'EZfix-FindVirtualDisks.ps1'
            $state.Process=Start-Process -FilePath (Get-Process -Id $PID).Path -WindowStyle Hidden -PassThru -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -OutputFolder "{1}"' -f $worker,$folder) -RedirectStandardError (Join-Path $folder 'error.txt')
            $timer.Start()
        } catch { $statusLabel.Text="Search could not start: $($_.Exception.Message)"; $cancel.Enabled=$false }
    })
    $dialog.Add_FormClosing({ [IO.File]::WriteAllText((Join-Path $folder 'cancel'),''); $timer.Stop() })
    try {
        [void]$dialog.ShowDialog($Owner)
        if ($dialog.Tag) { return [string]$dialog.Tag }
    }
    finally { $timer.Dispose(); $dialog.Dispose() }
}

