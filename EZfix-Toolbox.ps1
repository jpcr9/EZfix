<#
    EZfix-Toolbox.ps1
    Quick-reference tool cards for the Engineering panel.

    Deliberately NOT a documentation project: each card is just enough
    to open a tool, understand what it's for, and try a couple of
    commands. Anything deeper is one click away via the tool's own
    official documentation - that's the source of truth, and it's the
    part that actually stays current on its own over time. This file
    only needs upkeep if a tool gets renamed or a link moves.
#>

$script:EZfixToolbox = [ordered]@{
    'Network' = @(
        [pscustomobject]@{
            Name      = 'TCPView (Sysinternals)'
            ToolLink  = 'https://learn.microsoft.com/en-us/sysinternals/downloads/tcpview'
            DocLink   = 'https://learn.microsoft.com/en-us/sysinternals/downloads/tcpview'
            WhatFor   = "Shows every active TCP and UDP endpoint on the machine in real time - local/remote address, port, state, and which process owns it. Reach for it when you need to see right now what a machine is actually talking to, or confirm a specific process's network behavior live."
            EasySetup = 'No install - portable .exe, just download and run. Needs admin to see which process owns each connection.'
            Commands  = @(
                'tcpview.exe /accepteula   # skips the license prompt on first run'
                'tcpvcon.exe -a            # command-line sibling: dumps all connections to the console'
                'tcpvcon.exe -c            # same, but as CSV - easy to save alongside evidence'
            )
        },
        [pscustomobject]@{
            Name      = 'Wireshark'
            ToolLink  = 'https://www.wireshark.org/download.html'
            DocLink   = 'https://www.wireshark.org/docs/'
            WhatFor   = "Captures and inspects network traffic packet by packet. Reach for it when TCPView tells you a connection exists but you need to know what's actually being sent - a failed handshake, unexpected traffic, or a protocol-level problem TCPView can't show."
            EasySetup = 'Installer (also installs Npcap, the packet-capture driver it needs). Requires admin to capture on most adapters.'
            Commands  = @(
                'Capture filter: host 10.0.0.5              # only show traffic to/from one address'
                'Display filter: tcp.port == 443             # narrow an existing capture to one port'
                'Display filter: tcp.analysis.retransmission # find dropped/retried packets fast'
            )
        },
        [pscustomobject]@{
            Name      = 'nslookup (built-in)'
            ToolLink  = $null
            DocLink   = 'https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/nslookup'
            WhatFor   = "Queries DNS directly, bypassing the client's cache - the fastest way to tell 'is this a DNS problem' apart from everything else."
            EasySetup = 'Already on every Windows machine - just open a terminal.'
            Commands  = @(
                'nslookup example.com            # basic lookup using the default DNS server'
                'nslookup example.com 8.8.8.8     # same, against a specific DNS server - isolates a bad local resolver'
                'nslookup -type=MX example.com    # check mail routing records'
            )
        },
        [pscustomobject]@{
            Name      = 'PsPing (Sysinternals)'
            ToolLink  = 'https://learn.microsoft.com/en-us/sysinternals/downloads/psping'
            DocLink   = 'https://learn.microsoft.com/en-us/sysinternals/downloads/psping'
            WhatFor   = 'Ping, but it can also test actual TCP port connectivity and measure latency/bandwidth - useful when ICMP ping is blocked but you need to know if a specific port/service is reachable.'
            EasySetup = 'No install - portable .exe, just download and run.'
            Commands  = @(
                'psping.exe -accepteula server:443    # tests whether a specific TCP port is reachable'
                'psping.exe -l 1000 -n 20 server:443   # 20 pings of 1000 bytes to that port - a quick latency read'
            )
        }
    )
    'Auth' = @(
        [pscustomobject]@{
            Name      = 'klist (built-in)'
            ToolLink  = $null
            DocLink   = 'https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/klist'
            WhatFor   = "Lists the Kerberos tickets cached for the current logon session - the fastest way to confirm a machine actually holds a valid ticket for a resource, or to force a fresh one after a group or permissions change hasn't taken effect yet."
            EasySetup = 'Already on every Windows machine - just open a terminal.'
            Commands  = @(
                'klist                    # lists every ticket cached for this logon session'
                'klist purge              # clears the cache, forcing new tickets on next access'
                'klist tgt                # shows just the Ticket Granting Ticket - confirms the machine can even reach a domain controller'
            )
        },
        [pscustomobject]@{
            Name      = 'whoami (built-in)'
            ToolLink  = $null
            DocLink   = 'https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/whoami'
            WhatFor   = 'Shows exactly who and what a session is authenticated as - user, SID, group memberships and privileges. Reach for it whenever access is denied and you need to confirm the account actually has the rights it should.'
            EasySetup = 'Already on every Windows machine - just open a terminal.'
            Commands  = @(
                'whoami /all              # full identity: user, groups and privileges in one shot'
                'whoami /groups           # just group memberships - usually the first thing to check for a permissions issue'
                'whoami /priv             # shows which privileges are enabled vs. merely present but disabled'
            )
        },
        [pscustomobject]@{
            Name      = 'LogonSessions (Sysinternals)'
            ToolLink  = 'https://learn.microsoft.com/en-us/sysinternals/downloads/logonsessions'
            DocLink   = 'https://learn.microsoft.com/en-us/sysinternals/downloads/logonsessions'
            WhatFor   = "Lists every active logon session on the machine and, optionally, which processes belong to each - useful for spotting a stuck or duplicate session, or confirming which account a suspicious process is really running under."
            EasySetup = 'No install - portable .exe, just download and run. Needs admin for full detail.'
            Commands  = @(
                'logonsessions.exe -accepteula   # lists all active logon sessions'
                'logonsessions.exe -p            # same, but also lists the processes running under each session'
            )
        },
        [pscustomobject]@{
            Name      = 'Local Security Policy (secpol.msc, built-in)'
            ToolLink  = $null
            DocLink   = 'https://learn.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/security-policy-settings'
            WhatFor   = "Shows and edits local account lockout, password and audit policy - the place to check when a logon is being rejected or an account locked for policy reasons rather than a simply wrong password."
            EasySetup = 'Already on Windows Pro/Enterprise - press Win+R and type secpol.msc. Not available on Windows Home.'
            Commands  = @(
                'secpol.msc               # opens the policy editor directly'
                'net accounts             # command-line view of lockout threshold and duration'
            )
        }
    )
    'App' = @(
        [pscustomobject]@{
            Name      = 'Process Explorer (Sysinternals)'
            ToolLink  = 'https://learn.microsoft.com/en-us/sysinternals/downloads/process-explorer'
            DocLink   = 'https://learn.microsoft.com/en-us/sysinternals/downloads/process-explorer'
            WhatFor   = "A far deeper Task Manager: full process tree, which DLLs and handles a process holds, and which other process actually launched it. Reach for it when an app misbehaves and you need to see what it's really doing under the hood, not just that it's using CPU."
            EasySetup = 'No install - portable .exe, just download and run. Needs admin to see handles/DLLs for processes you do not own.'
            Commands  = @(
                'procexp.exe /accepteula        # skips the license prompt on first run'
                'Ctrl+F in the app              # searches every process for one that holds a specific handle or DLL - great for "who is locking this file"'
            )
        },
        [pscustomobject]@{
            Name      = 'Process Monitor (Procmon, Sysinternals)'
            ToolLink  = 'https://learn.microsoft.com/en-us/sysinternals/downloads/procmon'
            DocLink   = 'https://learn.microsoft.com/en-us/sysinternals/downloads/procmon'
            WhatFor   = "Records file, registry and process activity live, in real time. Reach for it when an app fails silently or can't find something it needs - it shows exactly which file or registry key it looked for right before giving up."
            EasySetup = 'No install - portable .exe, just download and run. Needs admin to capture system-wide.'
            Commands  = @(
                'procmon.exe /accepteula /quiet /minimized   # starts capturing immediately with no prompts'
                'Filter: Process Name is <app>.exe            # narrows the flood of events down to one app'
                'Filter: Result is NAME NOT FOUND              # a fast way to spot a missing file or registry key'
            )
        },
        [pscustomobject]@{
            Name      = 'sfc / DISM (built-in)'
            ToolLink  = $null
            DocLink   = 'https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/sfc'
            WhatFor   = 'Checks and repairs corrupted system files and the underlying component store - a common, easy-to-miss cause of apps crashing or failing to install for no obvious reason.'
            EasySetup = 'Already on every Windows machine - run from an elevated terminal.'
            Commands  = @(
                'sfc /scannow                                       # scans and repairs protected system files'
                'DISM /Online /Cleanup-Image /CheckHealth           # quick check for component store corruption'
                'DISM /Online /Cleanup-Image /RestoreHealth         # repairs the component store, needed if sfc alone cannot fix things'
            )
        },
        [pscustomobject]@{
            Name      = 'AppCrashView (NirSoft)'
            ToolLink  = 'https://www.nirsoft.net/utils/app_crash_view.html'
            DocLink   = 'https://www.nirsoft.net/utils/app_crash_view.html'
            WhatFor   = "Reads Windows Error Reporting crash records into one readable, sortable list - the faulting module and exception code for every app crash on the machine, without digging through raw dump files one at a time."
            EasySetup = 'No install - portable .exe, just download and run.'
            Commands  = @(
                'AppCrashView.exe                     # opens straight to the crash list, newest first'
                'Right-click a crash > Properties      # shows the full faulting-module detail for that one event'
            )
        }
    )
    'OS' = @(
        [pscustomobject]@{
            Name      = 'Autoruns (Sysinternals)'
            ToolLink  = 'https://learn.microsoft.com/en-us/sysinternals/downloads/autoruns'
            DocLink   = 'https://learn.microsoft.com/en-us/sysinternals/downloads/autoruns'
            WhatFor   = "Shows everything configured to start automatically - startup folder, services, scheduled tasks, drivers, browser extensions - in every location Windows checks, not just the few Task Manager shows. Reach for it on a slow boot or an app that keeps reappearing after being removed."
            EasySetup = 'No install - portable .exe, just download and run. Needs admin for full detail.'
            Commands  = @(
                'autoruns64.exe /accepteula          # opens the full GUI view'
                'autorunsc64.exe -accepteula -a * -c   # command-line sibling: dumps everything to CSV, easy to save alongside evidence'
            )
        },
        [pscustomobject]@{
            Name      = 'systeminfo (built-in)'
            ToolLink  = $null
            DocLink   = 'https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/systeminfo'
            WhatFor   = 'One-shot summary of OS version, install date, hotfixes, memory and boot configuration. Reach for it as a fast baseline before digging deeper into any OS-level problem.'
            EasySetup = 'Already on every Windows machine - just open a terminal.'
            Commands  = @(
                'systeminfo                                   # full report to the console'
                'systeminfo | findstr /C:"Hotfix"              # quick check of what has and has not been patched'
            )
        },
        [pscustomobject]@{
            Name      = 'Reliability Monitor (built-in)'
            ToolLink  = $null
            DocLink   = 'https://learn.microsoft.com/en-us/windows/client-management/monitor-windows-reliability'
            WhatFor   = "A day-by-day timeline of crashes, hangs, failed installs and driver problems, plotted against a stability score. Reach for it to see whether today's problem is new or part of a pattern that started around a specific update or install."
            EasySetup = 'Already on Windows - press Win+R and type perfmon /rel.'
            Commands  = @(
                'perfmon /rel               # opens Reliability Monitor directly'
            )
        },
        [pscustomobject]@{
            Name      = 'BlueScreenView (NirSoft)'
            ToolLink  = 'https://www.nirsoft.net/utils/blue_screen_view.html'
            DocLink   = 'https://www.nirsoft.net/utils/blue_screen_view.html'
            WhatFor   = "Reads the minidump files Windows leaves behind after a blue screen and lists the crashing driver or module for each one - the fastest way to tell whether repeated BSODs share a common cause."
            EasySetup = 'No install - portable .exe, just download and run.'
            Commands  = @(
                'BlueScreenView.exe                    # scans the default minidump folder and lists every crash found'
            )
        },
        [pscustomobject]@{
            Name      = 'NotMyFault (Sysinternals)'
            ToolLink  = 'https://learn.microsoft.com/en-us/sysinternals/downloads/notmyfault'
            DocLink   = 'https://learn.microsoft.com/en-us/sysinternals/downloads/notmyfault'
            WhatFor   = "Deliberately forces a controlled crash or hang so you can confirm the crash dump pipeline actually works - the right dump type is configured, the page file is large enough, and a real dump file lands where it should before you need one during an actual incident. CAUTION: this reboots the machine on a real crash - only run it on a machine you can afford to restart right now."
            EasySetup = 'No install - portable .exe, run notmyfaultc64.exe from an elevated terminal.'
            Commands  = @(
                'Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl"   # check the current dump type/path first - no risk, no reboot'
                'notmyfaultc64.exe /crash                                                  # forces an immediate kernel crash (BSOD) to generate a real dump'
                'notmyfaultc64.exe /hang                                                   # hangs the system instead of crashing it - tests hang detection separately'
            )
        },
        [pscustomobject]@{
            Name      = 'chkdsk / fsutil (built-in)'
            ToolLink  = $null
            DocLink   = 'https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/chkdsk'
            WhatFor   = "Scans an NTFS volume for filesystem inconsistencies and bad sectors (chkdsk) and reports low-level volume details like the dirty bit or NTFS version (fsutil). Reach for it when a drive reports as corrupted, files disappear or won't open, or Windows keeps nagging about a check on next boot."
            EasySetup = 'Already on every Windows machine - run from an elevated terminal.'
            Commands  = @(
                'chkdsk C:                        # read-only scan, reports problems without fixing anything'
                'chkdsk C: /f /r                  # fixes errors and locates bad sectors - needs a restart if it is the system drive'
                'fsutil dirty query C:            # checks whether the volume is flagged dirty, which forces a chkdsk on next boot'
            )
        },
        [pscustomobject]@{
            Name      = 'bootrec / bcdedit (built-in)'
            ToolLink  = $null
            DocLink   = 'https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/bcdedit-command-line-options'
            WhatFor   = "Rebuilds the boot sector and boot configuration data (bootrec) or inspects and edits boot entries directly (bcdedit) - the standard fix for 'operating system not found', a missing or corrupt BCD, or a machine that lands straight on a recovery screen instead of booting."
            EasySetup = 'Already on every Windows install/recovery media. Run from the Windows Recovery Environment command prompt (Advanced Startup > Troubleshoot > Command Prompt) - not from the running OS whose own boot files are the problem.'
            Commands  = @(
                'bootrec /scanos           # scans attached disks for installed Windows systems not currently in the boot menu'
                'bootrec /fixmbr           # rewrites the master boot record without touching the partition table'
                'bootrec /rebuildbcd       # rebuilds the boot configuration data store from scratch'
                'bcdedit /enum             # lists current boot entries - useful on a machine that does boot, to inspect them before changing anything'
            )
        },
        [pscustomobject]@{
            Name      = 'Reboot to UEFI Firmware Settings (built-in)'
            ToolLink  = $null
            DocLink   = 'https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/advanced-startup-options-ga-secure-boot'
            WhatFor   = "Reboots straight into the UEFI/BIOS setup screen, skipping the timing-sensitive 'hit the key at the right instant' step. Reach for it when you need to change a firmware setting (boot order, Secure Boot, virtualization) and want to get there reliably."
            EasySetup = 'Already on every UEFI machine - run from an elevated terminal. CAUTION: this reboots the machine immediately, with no confirmation and no way to cancel once run - only use it when you are ready for that right now.'
            Commands  = @(
                'shutdown /r /fw /t 0      # reboots now, landing in firmware setup instead of Windows'
                'shutdown /r /fw /t 30     # same, but with a 30 second delay - gives a moment to cancel with shutdown /a'
            )
        }
    )
    'Other' = @(
        [pscustomobject]@{
            Name      = 'Everything (voidtools)'
            ToolLink  = 'https://www.voidtools.com/'
            DocLink   = 'https://www.voidtools.com/support/everything/'
            WhatFor   = "Indexes every file and folder name on local drives and searches them instantly - useful any time a problem doesn't fit neatly into Network/Auth/App/OS and you just need to find a specific file, log or leftover installer fast."
            EasySetup = 'Installer, or a portable version with no install needed. Indexing starts automatically and finishes in seconds on most drives.'
            Commands  = @(
                'Search: *.log datemodified:today     # every log touched today, across the whole machine'
                'Search: size:>1gb                     # quickly finds what is actually eating disk space'
            )
        },
        [pscustomobject]@{
            Name      = 'ProcDump (Sysinternals)'
            ToolLink  = 'https://learn.microsoft.com/en-us/sysinternals/downloads/procdump'
            DocLink   = 'https://learn.microsoft.com/en-us/sysinternals/downloads/procdump'
            WhatFor   = "Captures a memory dump of any running process, on demand or automatically when a condition is met (a spike in CPU, an unhandled exception). A good catch-all when something is clearly wrong but it is not obvious yet whether it is a network, app or OS problem."
            EasySetup = 'No install - portable .exe, just download and run. Needs admin for most processes.'
            Commands  = @(
                'procdump.exe -accepteula -ma <PID>          # captures one full dump of a process right now'
                'procdump.exe -accepteula -c 90 -ma <PID>    # waits until CPU hits 90% before capturing - catches an intermittent spike'
            )
        },
        [pscustomobject]@{
            Name      = 'Get-ComputerInfo (built-in PowerShell)'
            ToolLink  = $null
            DocLink   = 'https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-computerinfo'
            WhatFor   = 'A broad one-shot inventory of OS, hardware, BIOS and network adapter details in a single structured object - a fast way to gather context before deciding which category a problem actually belongs to.'
            EasySetup = 'Already on every Windows machine with PowerShell - just open a terminal.'
            Commands  = @(
                'Get-ComputerInfo                                              # full inventory to the console'
                'Get-ComputerInfo | Select-Object Os*, Bios*, Csphysical*      # trims it down to the fields most worth a quick look'
            )
        }
    )
}

function Show-EZfixToolCard {
    <#
        Displays the tool cards for one category in a small read-only
        dialog: what each tool is, why you'd reach for it, how to get
        it running, and a couple of commands to start with. Deeper
        material is the tool's own official documentation - this
        dialog just gets you moving.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Windows.Forms.Form] $Owner,
        [Parameter(Mandatory)] [string] $Category
    )

    $tools = $script:EZfixToolbox[$Category]
    if (-not $tools) {
        [System.Windows.Forms.MessageBox]::Show("No tool cards yet for '$Category'.", 'EZfix', 'OK', 'Information') | Out-Null
        return
    }

    $dialog = [System.Windows.Forms.Form]::new()
    $dialog.Text = "EZfix Toolbox - $Category"
    $dialog.Size = [System.Drawing.Size]::new(560, 480)
    $dialog.MinimumSize = [System.Drawing.Size]::new(480, 360)
    $dialog.StartPosition = 'CenterParent'
    $dialog.Font = [System.Drawing.Font]::new('Segoe UI', 9)

    $listBox = [System.Windows.Forms.ListBox]::new()
    $listBox.SetBounds(12, 12, 170, 400)
    $listBox.Anchor = 'Top,Bottom,Left'
    foreach ($tool in $tools) { [void]$listBox.Items.Add($tool.Name) }
    $dialog.Controls.Add($listBox)

    $txtCard = [System.Windows.Forms.TextBox]::new()
    $txtCard.SetBounds(194, 12, 345, 400)
    $txtCard.Multiline = $true
    $txtCard.ReadOnly = $true
    $txtCard.WordWrap = $true
    $txtCard.ScrollBars = 'Vertical'
    $txtCard.Font = [System.Drawing.Font]::new('Consolas', 9)
    $txtCard.Anchor = 'Top,Bottom,Left,Right'
    $dialog.Controls.Add($txtCard)

    $close = [System.Windows.Forms.Button]::new()
    $close.Text = 'Close'
    $close.SetBounds(459, 418, 80, 28)
    $close.Anchor = 'Bottom,Right'
    $close.Add_Click({ $dialog.Close() })
    $dialog.Controls.Add($close)

    $listBox.Add_SelectedIndexChanged({
        $tool = $tools[$listBox.SelectedIndex]
        $lines = @()
        $lines += $tool.Name
        $lines += ('=' * $tool.Name.Length)
        $lines += ''
        $lines += 'WHAT IT''S FOR:'
        $lines += $tool.WhatFor
        $lines += ''
        $lines += 'EASY SETUP:'
        $lines += $tool.EasySetup
        $lines += ''
        $lines += 'A FEW COMMANDS:'
        $lines += $tool.Commands
        $lines += ''
        if ($tool.ToolLink) { $lines += "Tool: $($tool.ToolLink)" }
        $lines += "Official docs: $($tool.DocLink)"
        $txtCard.Text = ($lines -join "`r`n")
    })
    $listBox.SelectedIndex = 0

    [void]$dialog.ShowDialog($Owner)
    $dialog.Dispose()
}
