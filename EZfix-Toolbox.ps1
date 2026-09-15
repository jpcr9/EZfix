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
        [System.Windows.Forms.MessageBox]::Show("No tool cards yet for '$Category'. Network is the only category built out so far.", 'EZfix', 'OK', 'Information') | Out-Null
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
