<#
    Network-Diagnostics.ps1
    Diagnostic toolkit module 1 - Network (cross-platform version)

    Runs on PowerShell Core (pwsh), not Windows PowerShell (powershell.exe).
    pwsh is the same language on Windows and on Linux - that's why it's
    used as the common engine instead of having a separate script per OS.

    WHY IT'S BUILT THIS WAY:
    Network troubleshooting goes from the lowest layer to the highest:
      1. Do I have an IP?       -> if not, the problem is DHCP/adapter
      2. Can I reach the gateway? -> if not, the problem is local (cable, wifi, switch)
      3. Does DNS resolve?      -> if the gateway responds but this doesn't, the problem is DNS
      4. Do I reach the internet? -> if DNS works but this doesn't, there's a break further along the route

    THE KEY DIFFERENCE BETWEEN WINDOWS AND LINUX FOR A SCRIPT LIKE THIS:
    Windows has native cmdlets for almost everything (Get-NetIPConfiguration,
    Resolve-DnsName, Clear-DnsClientCache) - but those cmdlets DO NOT EXIST
    on Linux, because they depend on underlying Windows APIs.
    On Linux there's no single "the" command - it varies by distro
    (resolvectl on some, nscd on others, no DNS cache at all on others).
    The fix isn't a magic cmdlet that works on both sides: it's detecting
    which system we're on ($IsWindows / $IsLinux, pwsh's automatic
    variables) and using the right tool on each branch, or falling back
    to something universal from .NET (like [System.Net.Dns]) when it exists.
#>

Write-Host "=== NETWORK DIAGNOSTICS ===" -ForegroundColor Cyan
Write-Host "Computer:    $([System.Net.Dns]::GetHostName())"
Write-Host "System:   $($PSVersionTable.OS)"
Write-Host "Date:     $(Get-Date)"
Write-Host ""

# 1. Current IP configuration (layer 3 - addressing)
Write-Host "--- 1. IP configuration ---" -ForegroundColor Yellow

$gateway = $null

if ($IsWindows) {
    Get-NetIPConfiguration | Format-Table InterfaceAlias, IPv4Address, IPv4DefaultGateway -AutoSize | Out-String -Width 4096 | Write-Host
    $gateway = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1).IPv4DefaultGateway.NextHop
}
else {
    # Linux doesn't have Get-NetIPConfiguration. We use the native "ip"
    # command, which exists on practically every modern distro.
    ip -4 addr show | Select-String "inet " | ForEach-Object { Write-Host $_.Line.Trim() }
    $routeLine = (ip route show default | Select-Object -First 1)
    Write-Host $routeLine
    if ($routeLine -match "via\s+(\S+)") {
        $gateway = $Matches[1]
    }
}
Write-Host ""

# 2. Can I reach the gateway? If this fails, the problem is local (cable, wifi, switch).
Write-Host "--- 2. Gateway ping ---" -ForegroundColor Yellow

if ($gateway) {
    # Native ping, not Test-Connection: the count flag differs between systems
    # (-n on Windows, -c on Linux/Mac), so it's resolved based on the platform.
    $pingArgs = if ($IsWindows) { @("-n", "2", $gateway) } else { @("-c", "2", $gateway) }
    $pingOutput = & ping @pingArgs 2>&1
    $pingOutput | ForEach-Object { Write-Host $_ }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK: gateway ($gateway) responds." -ForegroundColor Green
    } else {
        Write-Host "FAILED: no reply from gateway ($gateway). Check the local network; ICMP may also be blocked." -ForegroundColor Red
    }
} else {
    Write-Host "No configured gateway was found on this computer." -ForegroundColor Red
}
Write-Host ""

# 3. Does DNS resolve? Uses .NET directly ([System.Net.Dns]) instead of
#    Resolve-DnsName because Resolve-DnsName is a Windows cmdlet that
#    doesn't exist on Linux. [System.Net.Dns] is part of the .NET
#    framework, and runs the same on both sides.
Write-Host "--- 3. DNS resolution ---" -ForegroundColor Yellow
try {
    $addresses = [System.Net.Dns]::GetHostAddresses("www.google.com")
    Write-Host "OK: DNS resolves (www.google.com -> $($addresses[0].IPAddressToString))" -ForegroundColor Green
} catch {
    Write-Host "FAILED: DNS resolution failed. Check the configured DNS server." -ForegroundColor Red
}
Write-Host ""

# 4. Flush the DNS cache - THIS is the best example of why there's no
#    single universal command. Windows always has a system-level DNS
#    cache. On Linux it depends on what the distro is running:
#    systemd-resolved (common on recent Ubuntu/Fedora), nscd (older),
#    or nothing at all (many minimal distros don't cache DNS).
Write-Host "--- 4. Flush DNS cache ---" -ForegroundColor Yellow

if ($IsWindows) {
    Clear-DnsClientCache
    Write-Host "DNS cache cleared (Clear-DnsClientCache)."
}
elseif (Get-Command resolvectl -ErrorAction SilentlyContinue) {
    resolvectl flush-caches
    Write-Host "DNS cache cleared (systemd-resolved via resolvectl)."
}
elseif (Get-Command nscd -ErrorAction SilentlyContinue) {
    Write-Host "nscd detected - restart it manually with: sudo service nscd restart"
}
else {
    Write-Host "No system-wide DNS cache was detected - not applicable." -ForegroundColor DarkGray
}
Write-Host ""

# 5. Do I reach the internet? tracert (Windows) vs traceroute (Linux,
#    sometimes not even installed by default - that's why it's checked first).
Write-Host "--- 5. Internet route trace ---" -ForegroundColor Yellow

if ($IsWindows) {
    tracert -h 15 www.google.com
}
elseif (Get-Command traceroute -ErrorAction SilentlyContinue) {
    traceroute -m 15 www.google.com
}
else {
    Write-Host "The 'traceroute' command is not installed on this system." -ForegroundColor DarkGray
    Write-Host "Install it with: sudo apt install traceroute  (Debian/Ubuntu)"
}

Write-Host ""
Write-Host "=== END OF NETWORK DIAGNOSTICS ===" -ForegroundColor Cyan
