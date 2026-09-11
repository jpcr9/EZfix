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
        Creates (if it doesn't exist) Desktop\EZfix\<timestamp>\ and
        returns the path. Every run that needs to save evidence calls
        this ONCE and uses the returned folder for all of that run's
        files - so each run stays separate, without overwriting
        previous runs.
    #>
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $basePath = Join-Path ([Environment]::GetFolderPath('Desktop')) "EZfix"
    $reportPath = Join-Path $basePath $timestamp

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