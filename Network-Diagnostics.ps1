<#
    Network-Diagnostics.ps1
    Modulo 1 del toolkit de diagnostico - Red (version multiplataforma)

    Corre con PowerShell Core (pwsh), no con Windows PowerShell (powershell.exe).
    pwsh es el mismo lenguaje en Windows y en Linux - por eso lo usamos como
    motor comun en vez de tener un script distinto por sistema operativo.

    POR QUE ESTA ARMADO ASI:
    Troubleshooting de red va de la capa mas baja a la mas alta:
      1. Tengo IP?           -> si no, el problema es DHCP/adaptador
      2. Le pego al gateway? -> si no, el problema es local (cable, wifi, switch)
      3. Resuelve DNS?       -> si el gateway responde pero esto no, el problema es DNS
      4. Llego a internet?   -> si DNS funciona pero esto no, hay un corte en la ruta

    LA DIFERENCIA CLAVE ENTRE WINDOWS Y LINUX PARA UN SCRIPT COMO ESTE:
    Windows tiene cmdlets nativos para casi todo (Get-NetIPConfiguration,
    Resolve-DnsName, Clear-DnsClientCache) - pero esos cmdlets NO EXISTEN
    en Linux, porque dependen de APIs de Windows por debajo.
    En Linux no hay "el" comando - varia por distro (resolvectl en unas,
    nscd en otras, ninguna cache de DNS en otras). La solucion no es tener
    un cmdlet magico que funcione en los dos lados: es detectar en que
    sistema estamos ($IsWindows / $IsLinux, variables automaticas de pwsh)
    y usar la herramienta correcta en cada rama, o caer a algo universal
    del .NET (como [System.Net.Dns]) cuando existe.
#>

Write-Host "=== NETWORK DIAGNOSTICS ===" -ForegroundColor Cyan
Write-Host "Computer:    $([System.Net.Dns]::GetHostName())"
Write-Host "System:   $($PSVersionTable.OS)"
Write-Host "Date:     $(Get-Date)"
Write-Host ""

# 1. Configuracion IP actual (capa 3 - direccionamiento)
Write-Host "--- 1. IP configuration ---" -ForegroundColor Yellow

$gateway = $null

if ($IsWindows) {
    Get-NetIPConfiguration | Format-Table InterfaceAlias, IPv4Address, IPv4DefaultGateway -AutoSize | Out-String -Width 4096 | Write-Host
    $gateway = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1).IPv4DefaultGateway.NextHop
}
else {
    # Linux no tiene Get-NetIPConfiguration. Usamos los comandos nativos "ip",
    # que existen en practicamente cualquier distro moderna.
    ip -4 addr show | Select-String "inet " | ForEach-Object { Write-Host $_.Line.Trim() }
    $routeLine = (ip route show default | Select-Object -First 1)
    Write-Host $routeLine
    if ($routeLine -match "via\s+(\S+)") {
        $gateway = $Matches[1]
    }
}
Write-Host ""

# 2. Le pego al gateway? Si esto falla, el problema es local (cable, wifi, switch).
Write-Host "--- 2. Gateway ping ---" -ForegroundColor Yellow

if ($gateway) {
    # Ping nativo, no Test-Connection: el flag de conteo cambia entre sistemas
    # (-n en Windows, -c en Linux/Mac), asi que lo resolvemos segun la plataforma.
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

# 3. Resuelve DNS? Usamos .NET directo ([System.Net.Dns]) en vez de Resolve-DnsName
#    porque Resolve-DnsName es un cmdlet de Windows que no existe en Linux.
#    [System.Net.Dns] es parte del framework .NET, corre igual en los dos lados.
Write-Host "--- 3. DNS resolution ---" -ForegroundColor Yellow
try {
    $addresses = [System.Net.Dns]::GetHostAddresses("www.google.com")
    Write-Host "OK: DNS resolves (www.google.com -> $($addresses[0].IPAddressToString))" -ForegroundColor Green
} catch {
    Write-Host "FAILED: DNS resolution failed. Check the configured DNS server." -ForegroundColor Red
}
Write-Host ""

# 4. Flush de cache DNS - ESTE es el mejor ejemplo de por que no existe
#    "un" comando universal. En Windows siempre hay cache de DNS a nivel
#    de sistema. En Linux depende de que este corriendo la distro:
#    systemd-resolved (comun en Ubuntu/Fedora recientes), nscd (mas viejo),
#    o nada en absoluto (muchas distros minimas no cachean DNS).
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

# 5. Llega hasta internet? tracert (Windows) vs traceroute (Linux, a veces
#    ni siquiera viene instalado por defecto - por eso lo chequeamos antes).
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


