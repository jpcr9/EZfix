<#
    EZfix-Bootstrap.ps1
    Modulo de instalador/bootstrap de dependencias de EZfix (modo TS -
    rapido, no persiste nada).

    Que hace: revisa que el entorno tenga lo que los demas modulos de
    EZfix necesitan para funcionar bien, y ofrece instalar SOLO lo que
    ya identificamos como dependencia real de otro modulo - nada de
    instalar "cosas utiles en general". Instalar software es una accion
    mas grande que reiniciar un servicio caido, asi que siempre pide
    confirmacion explicita antes de tocar nada (mismo patron
    SupportsShouldProcess + ConfirmImpact 'High' que ya conoces).
#>

if (-not (Test-Path Variable:IsWindows)) {
    $IsWindows = $env:OS -eq 'Windows_NT'
    $IsLinux   = -not $IsWindows
}

function Start-EZfixBootstrap {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param()

    Write-Host "=== EZFIX BOOTSTRAP ===" -ForegroundColor Cyan
    Write-Host "Equipo: $([System.Net.Dns]::GetHostName())"
    Write-Host "Fecha:  $(Get-Date)"
    Write-Host ""

    # PowerShell que esta corriendo esto ahora mismo. No es obligatorio
    # tener pwsh (los modulos de EZfix ya corren en 5.1 con el parche de
    # compatibilidad), pero se ofrece como mejora opcional.
    Write-Host "--- PowerShell ---" -ForegroundColor Yellow
    $isCore = $PSVersionTable.PSEdition -eq 'Core'
    Write-Host "Corriendo: PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"

    if ($isCore) {
        Write-Host "OK: ya estas en PowerShell 7+ (pwsh)." -ForegroundColor Green
    }
    elseif (Get-Command pwsh -ErrorAction SilentlyContinue) {
        Write-Host "PowerShell 7 (pwsh) ya esta instalado en este equipo - esta sesion en particular esta corriendo con Windows PowerShell 5.1." -ForegroundColor DarkGray
    }
    elseif ($IsWindows) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "PowerShell 7 no esta instalado. No es obligatorio, pero da mejor rendimiento y soporte oficial mas largo." -ForegroundColor Yellow
            if ($PSCmdlet.ShouldProcess("PowerShell 7 (pwsh)", "Instalar via winget")) {
                try {
                    winget install --id Microsoft.PowerShell -e --accept-source-agreements --accept-package-agreements
                    Write-Host "OK: instalacion de PowerShell 7 lanzada." -ForegroundColor Green
                }
                catch {
                    Write-Host "FALLA: no se pudo instalar - $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
        else {
            Write-Host "PowerShell 7 no esta instalado, y winget tampoco esta disponible para instalarlo automatico." -ForegroundColor Red
            Write-Host "Instalalo a mano desde: https://aka.ms/PSWindows" -ForegroundColor DarkGray
        }
    }
    Write-Host ""

    # Modulos de Windows que otros modulos de EZfix ya usan - Storage
    # (Disk-Selector), NetSecurity/NetTCPIP (EZfix-RDP). Vienen incluidos
    # con Windows, no se instalan por separado - esto es mas un chequeo
    # de "algo raro paso con esta instalacion de Windows" que algo que
    # se pueda arreglar solo.
    if ($IsWindows) {
        Write-Host "--- Modulos de Windows requeridos por otros modulos de EZfix ---" -ForegroundColor Yellow
        foreach ($mod in @('Storage', 'NetSecurity', 'NetTCPIP')) {
            if (Get-Module -ListAvailable -Name $mod) {
                Write-Host "OK: $mod disponible." -ForegroundColor Green
            }
            else {
                Write-Host "FALTA: $mod no esta disponible - los modulos que lo usan no van a funcionar bien en este equipo." -ForegroundColor Red
            }
        }
        Write-Host ""
    }

    # En Linux: paquetes que Network-Diagnostics.ps1 necesita para las
    # partes que dependen de comandos externos (no de .NET puro).
    if ($IsLinux) {
        Write-Host "--- Paquetes de red requeridos por Network-Diagnostics.ps1 ---" -ForegroundColor Yellow
        $requiredCommands = [ordered]@{
            'ping'       = 'iputils-ping'
            'traceroute' = 'traceroute'
            'ip'         = 'iproute2'
        }
        $missingPackages = @()
        foreach ($cmd in $requiredCommands.Keys) {
            if (Get-Command $cmd -ErrorAction SilentlyContinue) {
                Write-Host "OK: $cmd disponible." -ForegroundColor Green
            }
            else {
                Write-Host "FALTA: $cmd no esta instalado (paquete: $($requiredCommands[$cmd]))." -ForegroundColor Red
                $missingPackages += $requiredCommands[$cmd]
            }
        }

        if ($missingPackages.Count -gt 0) {
            Write-Host ""
            if (Get-Command apt-get -ErrorAction SilentlyContinue) {
                if ($PSCmdlet.ShouldProcess(($missingPackages -join ', '), "Instalar via apt-get")) {
                    try {
                        & sudo apt-get update
                        & sudo apt-get install -y @missingPackages
                        Write-Host "OK: paquetes instalados." -ForegroundColor Green
                    }
                    catch {
                        Write-Host "FALLA: no se pudieron instalar - $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }
            else {
                Write-Host "apt-get no disponible en esta distro - instala estos paquetes a mano: $($missingPackages -join ', ')" -ForegroundColor DarkGray
            }
        }
        Write-Host ""
    }

    # Permisos de administrador - Disk-Selector y el auto-arreglo de
    # EZfix-RDP los necesitan para poder ACTUAR (no solo diagnosticar).
    Write-Host "--- Permisos ---" -ForegroundColor Yellow
    if ($IsWindows) {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($isAdmin) {
            Write-Host "OK: esta sesion corre como Administrador." -ForegroundColor Green
        }
        else {
            Write-Host "Esta sesion NO corre como Administrador - Disk-Selector no va a funcionar, y el auto-arreglo de EZfix-RDP va a fallar (el diagnostico si funciona sin ser admin)." -ForegroundColor Yellow
        }
    }
    else {
        $whoami = & whoami
        Write-Host "Usuario actual: $whoami (para acciones que requieran privilegios, usa sudo segun haga falta)."
    }
    Write-Host ""

    Write-Host "=== FIN DEL BOOTSTRAP ===" -ForegroundColor Cyan
}

<#
    USO:
        . .\EZfix-Bootstrap.ps1

        Start-EZfixBootstrap -WhatIf
            Modo dry-run: dice que instalaria, sin instalar nada.

        Start-EZfixBootstrap
            Pregunta confirmacion antes de instalar cualquier cosa.
#>