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

Write-Host "=== DIAGNOSTICO DE RED ===" -ForegroundColor Cyan
Write-Host "Equipo:    $([System.Net.Dns]::GetHostName())"
Write-Host "Sistema:   $($PSVersionTable.OS)"
Write-Host "Fecha:     $(Get-Date)"
Write-Host ""

# 1. Configuracion IP actual (capa 3 - direccionamiento)
Write-Host "--- 1. Configuracion IP ---" -ForegroundColor Yellow

$gateway = $null

if ($IsWindows) {
    Get-NetIPConfiguration | Format-Table InterfaceAlias, IPv4Address, IPv4DefaultGateway -AutoSize
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
Write-Host "--- 2. Ping al Gateway ---" -ForegroundColor Yellow

if ($gateway) {
    # Ping nativo, no Test-Connection: el flag de conteo cambia entre sistemas
    # (-n en Windows, -c en Linux/Mac), asi que lo resolvemos segun la plataforma.
    $pingArgs = if ($IsWindows) { @("-n", "2", $gateway) } else { @("-c", "2", $gateway) }
    $pingOutput = & ping @pingArgs 2>&1
    $pingOutput | ForEach-Object { Write-Host $_ }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK: el gateway ($gateway) responde." -ForegroundColor Green
    } else {
        Write-Host "FALLA: no hay respuesta del gateway ($gateway). Problema de red local." -ForegroundColor Red
    }
} else {
    Write-Host "No se encontro gateway configurado en este equipo." -ForegroundColor Red
}
Write-Host ""

# 3. Resuelve DNS? Usamos .NET directo ([System.Net.Dns]) en vez de Resolve-DnsName
#    porque Resolve-DnsName es un cmdlet de Windows que no existe en Linux.
#    [System.Net.Dns] es parte del framework .NET, corre igual en los dos lados.
Write-Host "--- 3. Resolucion DNS ---" -ForegroundColor Yellow
try {
    $addresses = [System.Net.Dns]::GetHostAddresses("www.google.com")
    Write-Host "OK: DNS resuelve (www.google.com -> $($addresses[0].IPAddressToString))" -ForegroundColor Green
} catch {
    Write-Host "FALLA: no se pudo resolver DNS. Revisar servidor DNS configurado." -ForegroundColor Red
}
Write-Host ""

# 4. Flush de cache DNS - ESTE es el mejor ejemplo de por que no existe
#    "un" comando universal. En Windows siempre hay cache de DNS a nivel
#    de sistema. En Linux depende de que este corriendo la distro:
#    systemd-resolved (comun en Ubuntu/Fedora recientes), nscd (mas viejo),
#    o nada en absoluto (muchas distros minimas no cachean DNS).
Write-Host "--- 4. Flush DNS ---" -ForegroundColor Yellow

if ($IsWindows) {
    Clear-DnsClientCache
    Write-Host "Cache de DNS limpiado (Clear-DnsClientCache)."
}
elseif (Get-Command resolvectl -ErrorAction SilentlyContinue) {
    resolvectl flush-caches
    Write-Host "Cache de DNS limpiado (systemd-resolved via resolvectl)."
}
elseif (Get-Command nscd -ErrorAction SilentlyContinue) {
    Write-Host "nscd detectado - reinicialo manualmente con: sudo service nscd restart"
}
else {
    Write-Host "Este sistema no parece tener cache de DNS a nivel de sistema - no aplica." -ForegroundColor DarkGray
}
Write-Host ""

# 5. Llega hasta internet? tracert (Windows) vs traceroute (Linux, a veces
#    ni siquiera viene instalado por defecto - por eso lo chequeamos antes).
Write-Host "--- 5. Trace Route a Internet ---" -ForegroundColor Yellow

if ($IsWindows) {
    tracert -h 15 www.google.com
}
elseif (Get-Command traceroute -ErrorAction SilentlyContinue) {
    traceroute -m 15 www.google.com
}
else {
    Write-Host "El comando 'traceroute' no esta instalado en este sistema." -ForegroundColor DarkGray
    Write-Host "Instalalo con: sudo apt install traceroute  (Debian/Ubuntu)"
}

Write-Host ""
Write-Host "=== FIN DEL DIAGNOSTICO ===" -ForegroundColor Cyan