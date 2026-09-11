<#
    EZfix-CategoryScoping.ps1
    Category-based evidence collection (modo Scoping, replaces the
    original EZfix-Scoping.ps1 - same "read-only, evidence only" rule,
    organized by domain instead of one generic bucket).

    Why categories: a vague problem ("the app doesn't work", "the user
    can't log in") wastes time if you start by reading every log there
    is. A sysadmin triages by domain first - is this a network problem,
    an auth problem, an app problem, an OS problem? - then only looks at
    what that domain actually touches. This module mirrors that: you
    pick ONE category and it collects exactly the data points relevant
    to that domain, nothing else. "Other" is the catch-all for anything
    that doesn't fit cleanly (this is what the old generic Scoping did).

    Categories and what each one collects:
      Network - IP config, active TCP connections, DNS cache, and
                System log events from network-related providers
                (Tcpip, Dhcp-Client, Dnsapi, NETLOGON).
      Auth    - Security log logon failures (4625), account lockouts
                (4740), recent successful logons (4624), local users,
                and local Administrators group membership.
      App     - Application log errors/warnings, application-crash
                events specifically (Application Error, .NET Runtime),
                and startup programs.
      OS      - System log errors/warnings, OS version/uptime/install
                date, installed hotfixes, disk free space, and a quick
                CPU/memory snapshot.
      Other   - System + Application errors/warnings, unfiltered - the
                same behavior the original EZfix-Scoping.ps1 had.

    Live machine vs. offline disk: every category works two ways -
      - No -EvtxRoot: reads THIS machine's live named event logs
        (Get-WinEvent -LogName ...). This is what the EZfix Quick Fixes
        section in the GUI uses - "run this on my own PC".
      - -EvtxRoot <path>: reads .evtx FILES from that path instead (e.g.
        a mounted disk's D:\Windows\System32\winevt\Logs), the same
        technique EZfix-OfflineAnalysis.ps1 uses for a disk that won't
        boot. In this mode, data points that only make sense on a
        running system (live TCP connections, local users, installed
        hotfixes, CPU load right now) are skipped - you can't ask a
        disconnected disk what its CPU usage is - only the event-log
        data points run.
      This isn't wired into the GUI yet (the GUI always calls it live,
      for the current machine) - the parameter is there so the same
      engine can later point at a disk in the Advanced section without
      writing a second copy of all this collection logic.

    Report folder structure (2026-09-11): categories collected within
    24 hours of each other share one parent timestamped folder instead
    of scattering across a new folder per click - so a multi-category
    investigation (Network now, Auth twenty minutes later) lands
    together:

        Desktop\EZfix\scoping\<session timestamp>\
            Network\NetworkConfig.csv, ActiveConnections.csv, ...
            Auth\Security-logon-failures.csv, LocalUsers.csv, ...
            OS\HotFixes.csv, OSInfo.csv, ...

    Older than 24 hours since the last session folder -> a new one is
    started, so old and new investigations don't get mixed together.

    Still read-only, still evidence-only: this module changes nothing
    on the machine it inspects. If a category finding calls for an
    actual fix, that's the human research step this whole project has
    always deferred to - EZfix collects, it does not diagnose-and-fix
    beyond the safe/reversible actions already covered by the Quick
    Fixes section.
#>

#Requires -RunAsAdministrator

# Reuse New-EZfixReportFolder's directory-creation pattern, but this
# module needs its own session-folder logic (the 24-hour reuse window),
# so it doesn't call New-EZfixReportFolder directly - see
# Get-EZfixScopingSessionFolder below.
if (-not (Get-Command New-EZfixReportFolder -ErrorAction SilentlyContinue)) {
    $commonPath = Join-Path $PSScriptRoot "EZfix-Common.ps1"
    if (Test-Path $commonPath) {
        . $commonPath
    }
    else {
        Write-Host "EZfix-Common.ps1 was not found in this folder. Load it first with:  . .\EZfix-Common.ps1" -ForegroundColor Red
        return
    }
}

function Get-EZfixScopingSessionFolder {
    <#
        Returns the folder for this scoping "session". If a session
        folder was created in the last 24 hours, reuses it (so multiple
        categories collected the same day/investigation land together).
        Otherwise creates a new one.
    #>
    $basePath = Join-Path ([Environment]::GetFolderPath('Desktop')) "EZfix\scoping"
    New-Item -Path $basePath -ItemType Directory -Force | Out-Null

    $existingSessions = Get-ChildItem -Path $basePath -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{8}_\d{6}$' } |
        Sort-Object Name -Descending

    if ($existingSessions) {
        $latest = $existingSessions[0]
        $latestTime = [datetime]::ParseExact($latest.Name, 'yyyyMMdd_HHmmss', $null)
        if (((Get-Date) - $latestTime).TotalHours -lt 24) {
            return $latest.FullName
        }
    }

    $newSessionPath = Join-Path $basePath (Get-Date -Format 'yyyyMMdd_HHmmss')
    New-Item -Path $newSessionPath -ItemType Directory -Force | Out-Null
    return $newSessionPath
}

function Start-EZfixCategoryScoping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Network', 'Auth', 'App', 'OS', 'Other')]
        [string]$Category,

        # Path to a mounted disk's event log folder (e.g.
        # "D:\Windows\System32\winevt\Logs") to collect from an offline
        # disk instead of this live machine. Omit for the live machine.
        [string]$EvtxRoot,

        [int]$MaxEventsPerLog = 100
    )

    $sessionFolder = Get-EZfixScopingSessionFolder
    $categoryFolder = Join-Path $sessionFolder $Category
    New-Item -Path $categoryFolder -ItemType Directory -Force | Out-Null

    $isLive = -not $EvtxRoot

    Write-Host "=== EZFIX EVIDENCE COLLECTION - $($Category.ToUpper()) ===" -ForegroundColor Cyan
    Write-Host "Target: $(if ($isLive) { 'this machine (live)' } else { $EvtxRoot })"
    Write-Host "Session folder:  $sessionFolder"
    Write-Host "Category folder: $categoryFolder"
    Write-Host ""

    function Save-EZfixEventLog {
        <#
            Reads one named log's events (live, or from a .evtx file
            under $EvtxRoot) and exports matches to CSV in the category
            folder. Works the same way in both modes - only where the
            events come from differs.
        #>
        param(
            [string]$LogName,
            [int[]]$Level,
            [int[]]$Id,
            [string[]]$ProviderName,
            [string]$OutFileName
        )

        $filter = @{ MaxEvents = $MaxEventsPerLog }
        if ($EvtxRoot) {
            $evtxPath = Join-Path $EvtxRoot "$LogName.evtx"
            if (-not (Test-Path $evtxPath)) {
                Write-Host "$LogName.evtx was not found under $EvtxRoot - skipping." -ForegroundColor DarkGray
                return
            }
            $filterHash = @{ Path = $evtxPath }
        }
        else {
            $filterHash = @{ LogName = $LogName }
        }
        if ($Level) { $filterHash['Level'] = $Level }
        if ($Id) { $filterHash['Id'] = $Id }
        if ($ProviderName) { $filterHash['ProviderName'] = $ProviderName }

        try {
            $events = Get-WinEvent -FilterHashtable $filterHash -MaxEvents $MaxEventsPerLog -ErrorAction Stop
            $outFile = Join-Path $categoryFolder $OutFileName
            $events | Select-Object TimeCreated, LevelDisplayName, ProviderName, Id, Message |
                Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8
            Write-Host "OK: $($events.Count) event(s) from $LogName saved to $OutFileName" -ForegroundColor Green
        }
        catch {
            if ($_.Exception.Message -match "No events were found") {
                Write-Host "No matching events in $LogName for this filter - good sign." -ForegroundColor DarkGray
            }
            else {
                Write-Host "Could not read $LogName - $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    function Save-EZfixData {
        <#
            Runs a live-only data collector (a scriptblock returning
            objects) and exports the result to CSV, or skips cleanly
            when in offline-disk mode (-EvtxRoot) - a disconnected disk
            can't answer "what's your CPU load right now".
        #>
        param(
            [string]$Description,
            [scriptblock]$Collector,
            [string]$OutFileName
        )

        if (-not $isLive) {
            Write-Host "$Description - skipped (only available for the live machine, not an offline disk)." -ForegroundColor DarkGray
            return
        }

        try {
            $data = & $Collector
            if (-not $data) {
                Write-Host "$Description - no data returned." -ForegroundColor DarkGray
                return
            }
            $outFile = Join-Path $categoryFolder $OutFileName
            $data | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8
            Write-Host "OK: $Description saved to $OutFileName" -ForegroundColor Green
        }
        catch {
            Write-Host "$Description - could not collect: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    switch ($Category) {
        'Network' {
            Save-EZfixData -Description "Network configuration" -OutFileName 'NetworkConfig.csv' -Collector {
                Get-NetIPConfiguration | Select-Object InterfaceAlias, InterfaceDescription, IPv4Address, IPv4DefaultGateway, DNSServer
            }
            Save-EZfixData -Description "Active TCP connections" -OutFileName 'ActiveConnections.csv' -Collector {
                Get-NetTCPConnection | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess
            }
            Save-EZfixData -Description "DNS client cache" -OutFileName 'DnsCache.csv' -Collector {
                Get-DnsClientCache | Select-Object Entry, Name, Data, TimeToLive
            }
            Save-EZfixEventLog -LogName 'System' -Level 2, 3 -ProviderName 'Tcpip', 'Dhcp-Client', 'Dnsapi', 'NETLOGON' -OutFileName 'System-network-events.csv'
        }

        'Auth' {
            Save-EZfixEventLog -LogName 'Security' -Id 4625 -OutFileName 'Security-logon-failures.csv'
            Save-EZfixEventLog -LogName 'Security' -Id 4740 -OutFileName 'Security-account-lockouts.csv'
            Save-EZfixEventLog -LogName 'Security' -Id 4624 -OutFileName 'Security-successful-logons.csv'
            Save-EZfixData -Description "Local user accounts" -OutFileName 'LocalUsers.csv' -Collector {
                Get-LocalUser | Select-Object Name, Enabled, LastLogon, PasswordLastSet
            }
            Save-EZfixData -Description "Local Administrators group membership" -OutFileName 'LocalAdmins.csv' -Collector {
                Get-LocalGroupMember -Group "Administrators"
            }
        }

        'App' {
            Save-EZfixEventLog -LogName 'Application' -Level 2, 3 -OutFileName 'Application-errors-warnings.csv'
            Save-EZfixEventLog -LogName 'Application' -ProviderName 'Application Error', '.NET Runtime' -OutFileName 'Application-crashes.csv'
            Save-EZfixData -Description "Startup programs" -OutFileName 'StartupPrograms.csv' -Collector {
                Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User
            }
        }

        'OS' {
            Save-EZfixEventLog -LogName 'System' -Level 2, 3 -OutFileName 'System-errors-warnings.csv'
            Save-EZfixData -Description "OS version and uptime" -OutFileName 'OSInfo.csv' -Collector {
                $os = Get-CimInstance Win32_OperatingSystem
                [pscustomobject]@{
                    Caption         = $os.Caption
                    Version         = $os.Version
                    BuildNumber     = $os.BuildNumber
                    InstallDate     = $os.InstallDate
                    LastBootUpTime  = $os.LastBootUpTime
                    UptimeHours     = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)
                }
            }
            Save-EZfixData -Description "Installed hotfixes" -OutFileName 'HotFixes.csv' -Collector {
                Get-HotFix | Select-Object HotFixID, Description, InstalledOn | Sort-Object InstalledOn -Descending
            }
            Save-EZfixData -Description "Disk free space" -OutFileName 'DiskSpace.csv' -Collector {
                Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 } |
                    Select-Object Name, @{N = 'UsedGB'; E = { [math]::Round($_.Used / 1GB, 1) } }, @{N = 'FreeGB'; E = { [math]::Round($_.Free / 1GB, 1) } }
            }
            Save-EZfixData -Description "CPU/memory snapshot" -OutFileName 'PerformanceSnapshot.csv' -Collector {
                $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
                $mem = Get-CimInstance Win32_OperatingSystem
                [pscustomobject]@{
                    CPULoadPercent  = $cpu
                    TotalMemoryMB   = [math]::Round($mem.TotalVisibleMemorySize / 1KB, 0)
                    FreeMemoryMB    = [math]::Round($mem.FreePhysicalMemory / 1KB, 0)
                }
            }
        }

        'Other' {
            Save-EZfixEventLog -LogName 'System' -Level 2, 3 -OutFileName 'System-errors-warnings.csv'
            Save-EZfixEventLog -LogName 'Application' -Level 2, 3 -OutFileName 'Application-errors-warnings.csv'
        }
    }

    Write-Host ""
    Write-Host "=== EVIDENCE COLLECTION FINISHED ($Category) ===" -ForegroundColor Cyan
    Write-Host "Saved to: $categoryFolder" -ForegroundColor Green

    return $categoryFolder
}

<#
    USAGE:
        . .\EZfix-Common.ps1
        . .\EZfix-CategoryScoping.ps1

        Start-EZfixCategoryScoping -Category Network
            Collects network-related evidence from THIS machine.

        Start-EZfixCategoryScoping -Category Auth -EvtxRoot "D:\Windows\System32\winevt\Logs"
            Collects auth-related event log evidence from a mounted,
            offline disk's event logs instead (live-only data points,
            like local users, are skipped in this mode).
#>