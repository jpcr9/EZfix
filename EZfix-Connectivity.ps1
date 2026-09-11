function Start-EZfixConnectivity {
    [CmdletBinding()]
    param()
    function Show-EZfixConnectivitySection([string]$Title,[scriptblock]$Action) {
        Write-Host "`n--- $Title ---"
        try { & $Action } catch { Write-Warning "$Title unavailable: $($_.Exception.Message)" }
    }
    Write-Host '=== THIS PC: CONNECTIVITY & SECURITY ==='
    Show-EZfixConnectivitySection 'Active networks' {
        $profiles=@(Get-NetConnectionProfile -ErrorAction Stop)
        foreach($profile in $profiles) {
            Write-Host "$($profile.InterfaceAlias) | Network: $($profile.Name) | Category: $($profile.NetworkCategory) | IPv4: $($profile.IPv4Connectivity) | IPv6: $($profile.IPv6Connectivity)"
        }
        if(-not $profiles){Write-Host 'No active network profiles reported.'}
        foreach($config in Get-NetIPConfiguration -ErrorAction Stop) {
            Write-Host "$($config.InterfaceAlias) | IPv4: $($config.IPv4Address.IPAddress -join ', ') | Gateway: $($config.IPv4DefaultGateway.NextHop -join ', ') | DNS: $($config.DNSServer.ServerAddresses -join ', ')"
        }
    }
    Show-EZfixConnectivitySection 'Windows Firewall (effective policy)' {
        $profiles=@(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
        foreach($profile in $profiles) {
            Write-Host "$($profile.Name) | Enabled: $($profile.Enabled) | Default inbound: $($profile.DefaultInboundAction) | Default outbound: $($profile.DefaultOutboundAction) | Log blocked: $($profile.LogBlocked)"
        }
        if(-not $profiles){Write-Warning 'No firewall profile information was returned.'}
        $service=Get-Service -Name MpsSvc -ErrorAction Stop
        Write-Host "Firewall service (MpsSvc): $($service.Status)"
        Write-Host 'Network categories above identify the profiles in use. A profile setting alone does not prove that a specific connection is permitted.'
    }
    Show-EZfixConnectivitySection 'Microsoft Defender' {
        $status=Get-CimInstance -Namespace 'root/Microsoft/Windows/Defender' -ClassName MSFT_MpComputerStatus -ErrorAction Stop
        if(-not $status){throw 'No Defender status returned.'}
        function Read-DefenderField([string]$Name) { if ($null -eq $status.$Name) { 'Not reported' } else { $status.$Name } }
        Write-Host "Antivirus enabled: $(Read-DefenderField AntivirusEnabled) | Real-time protection: $(Read-DefenderField RealTimeProtectionEnabled) | Service enabled: $(Read-DefenderField AMServiceEnabled)"
        Write-Host "Signature version: $(Read-DefenderField AntivirusSignatureVersion) | Updated: $(Read-DefenderField AntivirusSignatureLastUpdated)"
        Write-Host "Running mode: $(Read-DefenderField AMRunningMode) | Tamper protection: $(Read-DefenderField IsTamperProtected)"
        Write-Host 'This reports Microsoft Defender only. Another antivirus or managed policy may be in use.'
    }
    Show-EZfixConnectivitySection 'Secure Boot and TPM' {
        try { Write-Host "Secure Boot enabled: $(Confirm-SecureBootUEFI -ErrorAction Stop)" } catch { Write-Host "Secure Boot: unavailable or unsupported ($($_.Exception.Message))" }
        try { $tpm=Get-Tpm -ErrorAction Stop; Write-Host "TPM present: $($tpm.TpmPresent) | Ready: $($tpm.TpmReady) | Enabled: $($tpm.TpmEnabled)" } catch { Write-Host "TPM information unavailable: $($_.Exception.Message)" }
    }
    Show-EZfixConnectivitySection 'Local TCP listeners (first 30 by port)' {
        $listeners=@(Get-NetTCPConnection -State Listen -ErrorAction Stop | Sort-Object LocalPort,LocalAddress | Select-Object -First 30)
        foreach($listener in $listeners) {
            $process=Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
            Write-Host "$($listener.LocalAddress):$($listener.LocalPort) | PID: $($listener.OwningProcess) | Process: $($process.ProcessName)"
        }
        if(-not $listeners){Write-Host 'No local TCP listeners were returned.'}
        Write-Host 'Listening locally does not prove reachability from another computer.'
    }
    Show-EZfixConnectivitySection 'Remote Desktop diagnostics and service check' {
        Start-EZfixRDPCheck
    }
    Write-Host '=== END OF CONNECTIVITY & SECURITY ==='
}


