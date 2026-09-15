{
    # PSAvoidAssignmentToAutomaticVariable false-positives on the
    # deliberate Windows PowerShell 5.1 compatibility pattern used in
    # EZfix-Cleanup.ps1, EZfix-Performance.ps1 and EZfix-RDP.ps1:
    #
    #     if (-not (Test-Path Variable:IsWindows)) {
    #         $IsWindows = $env:OS -eq 'Windows_NT'
    #         $IsLinux   = -not $IsWindows
    #     }
    #
    # $IsWindows/$IsLinux are read-only automatic variables from
    # PowerShell 6+ onward, but don't exist at all in Windows PowerShell
    # 5.1 - this block only defines them when they're missing, so the
    # assignment never actually runs on a version where they're
    # read-only. The rule can't see that far into the guard, so it
    # flags every assignment to these names regardless of context. This
    # is excluded here rather than changing three already-tested,
    # working modules to satisfy a linter that can't tell the
    # difference.
    ExcludeRules = @('PSAvoidAssignmentToAutomaticVariable')
}
