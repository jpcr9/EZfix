<#
    EZfix-Common.ps1
    Shared functions used by every EZfix module.

    Agreed convention (2026-09-10): when a module can't fully resolve
    something on its own, instead of getting lost investigating it right
    there, it saves the relevant evidence (logs, exports, whatever
    applies) into a timestamped folder under Desktop\EZfix, and moves
    on. Deep investigation is a separate, human step, done afterward
    with that evidence already in hand.

    This is the project's real scope boundary: every module does only
    three things - diagnose, auto-fix ONLY if the fix is safe and
    reversible (flush DNS, restart a stopped service, etc.), and if it
    can't fix itself, save useful evidence and report it. Nothing more
    than that - no trying to "solve everything" inside the module
    itself.
#>

function New-EZfixReportFolder {
    <#
        Creates (if it doesn't exist) Desktop\EZfix\<timestamp>_<label>\
        and returns the path. Every run that needs to save evidence
        calls this once and uses the returned folder for all of that
        run's files - so each run stays separate, without overwriting
        previous runs, and the folder name itself says what produced it
        instead of being a bare timestamp.

        If a report folder was already created for the current action
        (see $script:EZfixCurrentReportFolder, set by Invoke-EZfixAction
        in EZfix-Interface.ps1 around the whole action), that same
        folder is reused instead of creating a second one - this is what
        keeps, for example, Offline Analysis's own detailed evidence
        files in the same folder as the summary report the GUI already
        created for that one click, rather than splitting one action's
        output across two differently-timestamped folders. Calling this
        directly from a console, outside the GUI, always creates a
        fresh folder as before, since that script-scope hint is never
        set there.
    #>
    param(
        [string]$Label
    )

    if ($script:EZfixCurrentReportFolder -and (Test-Path -LiteralPath $script:EZfixCurrentReportFolder)) {
        return $script:EZfixCurrentReportFolder
    }

    $safeLabel = if ($Label) { '_' + ($Label -replace '[^A-Za-z0-9]+', '-').Trim('-') } else { '' }
    $timestamp = (Get-Date -Format "yyyyMMdd_HHmmss") + $safeLabel
    $basePath = Join-Path ([Environment]::GetFolderPath('Desktop')) "EZfix"
    $reportPath = Join-Path $basePath $timestamp

    # Two actions finishing in the same second with the same label is
    # rare but possible - only append a short random suffix if the
    # plain name is already taken, so the common case stays as clean as
    # the name alone.
    if (Test-Path -LiteralPath $reportPath) {
        $reportPath = $reportPath + '_' + [guid]::NewGuid().ToString('N').Substring(0,4)
    }

    New-Item -Path $reportPath -ItemType Directory -Force | Out-Null

    return $reportPath
}

<#
    USAGE EXAMPLE inside a module:

    $reportFolder = New-EZfixReportFolder

    # ... the module tries to diagnose and fix whatever it can ...

    # If something couldn't be resolved on its own, save evidence and report it:
    Get-WinEvent -LogName System -MaxEvents 50 |
        Where-Object { $_.LevelDisplayName -in 'Error', 'Critical' } |
        Export-Csv (Join-Path $reportFolder "system-errors.csv") -NoTypeInformation

    Write-Host "Could not resolve this automatically. Evidence saved to: $reportFolder" -ForegroundColor Yellow
#>
