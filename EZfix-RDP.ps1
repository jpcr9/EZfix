# EZfix-RDP.ps1
<#
    EZfix-RDP.ps1
    EZfix RDP diagnostics module (TS mode - fast, saves nothing to disk).

    RDP is a Windows protocol - this module is deliberately Windows-only
    (same reasoning as Disk-Selector: don't force cross-platform when
    the concept itself doesn't exist the same way on the other side).

    Layered troubleshooting, from most basic to most specific - the same
    logic as Network-Diagnostics, applied to RDP:
      1. Is the Remote Desktop service running?
      2. Is RDP allowed at the system level (not blocked by config)?
      3. Does the Windows Firewall let the connection through?
      4. Is port 3389 actually listening right now?

    Deliberately scoped to just this: if the SERVICE is down, it
    restarts it on its own (a safe, reversible action, same as any
    other stopped service). Enabling RDP at the system or Firewall
    level is a security decision for whoever administers the machine -
    that gets reported, not changed automatically.
#>

# Same compatibility patch as EZfix-Performance.ps1: $IsWindows is a
# pwsh (PowerShell 7+) automatic variable, it doesn't exist in Windows
# PowerShell 5.1 - we build it by hand if needed.
if (-not (Test-Path Variable:IsWindows)) {
    $IsWindows = $env:OS -eq 'Windows_NT'
    $IsLinux   = -not $IsWindows
}

function Start-EZfixRDPCheck {
    [CmdletBinding()]
    param()

    if (-not $IsWindows) {
        Write-Host "This module is Windows-specific (RDP is a Windows protocol) - it does not apply on this system." -ForegroundColor DarkGray
        return
    }

    Write-Host "=== EZFIX RDP DIAGNOSTICS ===" -ForegroundColor Cyan
    Write-Host "Computer: $([System.Net.Dns]::GetHostName())"
    Write-Host "Date:     $(Get-Date)"
    Write-Host ""

    try {
        $edition=(Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction Stop).EditionID
        Write-Host "Windows edition: $edition"
        if($edition -like 'Core*'){Write-Host 'Windows Home does not provide the built-in incoming Remote Desktop host. Service and network checks below are still shown.'}
    } catch {Write-Host 'Windows edition information unavailable.'}
    $rdpPort=3389
    try {
        $settings=Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -ErrorAction Stop
        if($settings.PortNumber -ge 1 -and $settings.PortNumber -le 65535){$rdpPort=[int]$settings.PortNumber}
        $nla = if($null -eq $settings.UserAuthentication){'Not reported'}else{[string]($settings.UserAuthentication -eq 1)}
        Write-Host "RDP port checked: $rdpPort | Network Level Authentication required: $nla"
    } catch {Write-Host 'RDP settings unavailable; checking default port 3389.'}
    # 1. Remote Desktop service (TermService). If it's down, it's
    # restarted automatically - this is exactly the kind of safe,
    # reversible fix that DOES fall within EZfix's scope boundary
    # (same as a DNS flush).
    Write-Host "--- 1. Remote Desktop service (TermService) ---" -ForegroundColor Yellow

    $service = Get-Service -Name TermService -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "FAILED: the TermService service was not found on this computer." -ForegroundColor Red
    }
    elseif ($service.Status -eq 'Running') {
        Write-Host "OK: the service is running." -ForegroundColor Green
    }
    else {
        Write-Host "The service is '$($service.Status)' - attempting to start it (a safe, reversible action)." -ForegroundColor Yellow
        try {
            Start-Service -Name TermService -ErrorAction Stop
            Write-Host "OK: service started." -ForegroundColor Green
        }
        catch {
            Write-Host "FAILED: could not start the service - $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Needs PowerShell running as Administrator to be able to start services." -ForegroundColor DarkGray
        }
    }
    Write-Host ""

    # 2. Allowed at the system level. fDenyTSConnections = 0 means
    # ALLOWED (the name is backwards from what you'd expect - "Deny" at
    # 0 means it's NOT denying, i.e. it DOES allow).
    Write-Host "--- 2. RDP allowed at the system level ---" -ForegroundColor Yellow

    $regPath = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
    $deny = (Get-ItemProperty -Path $regPath -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections

    if ($null -eq $deny) {
        Write-Host "Could not read the setting (fDenyTSConnections not found, or no permission)." -ForegroundColor Red
    }
    elseif ($deny -eq 0) {
        Write-Host "OK: RDP is allowed at the system level." -ForegroundColor Green
    }
    else {
        Write-Host "RDP is BLOCKED at the system level (fDenyTSConnections = 1)." -ForegroundColor Red
        Write-Host "This is a security decision made by whoever administers this computer - it is not changed automatically. To enable it by hand:" -ForegroundColor DarkGray
        Write-Host "  Set-ItemProperty -Path '$regPath' -Name fDenyTSConnections -Value 0" -ForegroundColor DarkGray
    }
    Write-Host ""

    # 3. Windows Firewall - the rule can exist but be disabled, or not
    # exist at all. Those are two different failures, reported
    # differently.
    Write-Host "--- 3. Windows Firewall ---" -ForegroundColor Yellow

    $fwRules = Get-NetFirewallRule -Name "RemoteDesktop-*" -ErrorAction SilentlyContinue
    if (-not $fwRules) {
        Write-Host "No Remote Desktop Firewall rules were found on this computer." -ForegroundColor Red
    }
    else {
        $enabled = $fwRules | Where-Object { $_.Enabled -eq $true }
        if ($enabled) {
            Write-Host "OK: $($enabled.Count) of $($fwRules.Count) Remote Desktop rule(s) are enabled." -ForegroundColor Green
        }
        else {
            Write-Host "Remote Desktop Firewall rules exist but are ALL disabled." -ForegroundColor Red
        }
    }
    Write-Host ""

    # 4. Is the port actually listening - the final check, the one that
    # confirms whether the previous three actually translate into a
    # real available connection.
    Write-Host "--- 4. Port $rdpPort (actually listening) ---" -ForegroundColor Yellow

    $listening = Get-NetTCPConnection -LocalPort $rdpPort -State Listen -ErrorAction SilentlyContinue
    if ($listening) {
        Write-Host "OK: port $rdpPort is listening." -ForegroundColor Green
    }
    else {
        Write-Host "Port $rdpPort is NOT listening right now." -ForegroundColor Red
    }
    Write-Host ""

    Write-Host "=== END OF RDP DIAGNOSTICS ===" -ForegroundColor Cyan
}

<#
    USAGE (run PowerShell as Administrator, for item 1):
        . .\EZfix-RDP.ps1
        Start-EZfixRDPCheck
#>


