<#
    EZfix-Interface.ps1
    EZfix graphical interface (Windows, GUI) - two sections:

      1. EZfix Quick Fixes: network, performance, cleanup, RDP, setup
         (PowerShell 7 + prerequisites), and category-based evidence
         collection (Network/Auth/App/OS/Other - see
         EZfix-CategoryScoping.ps1) - the everyday fixes plus triage.
         Every action's output is written to a session log file (see
         below) AND shown as a pop-up confirmation, so you always know
         whether it ran cleanly or hit an error - even though this
         section still does not do deep forensic collection beyond the
         evidence category picked.

      2. Advanced (collapsible - collapsed by default): disk analysis
         for a disk under investigation. Detect disks, bring them
         online/offline with explicit confirmation, and run the
         read-only analysis on that disk (typically a Windows install
         that won't boot, mounted as a data disk on this machine - an
         on-prem scenario: a disk from another PC or VM, read from this
         Windows host). Click the "Advanced" bar to expand/collapse it.

    Why two separate sections, and how they connect: these cover two
    different scenarios that need different tools. Network, Performance,
    Cleanup, RDP, and Setup are inherently LIVE-machine checks - a
    service status, a ping, current CPU load, a running process - none
    of that exists on a disk that isn't booted, so those five buttons
    can only ever run against this PC. Category evidence collection and
    Offline Analysis are different: most of what they read (event logs,
    registry hives, file versions) lives on disk whether or not the
    machine is running, so both CAN target a foreign disk connected as
    data - and both now do, in this GUI:
      - Offline Analysis (section 2) always reads a mounted disk by
        drive letter - that was always its only mode.
      - Category evidence collection (section 1) defaults to THIS PC,
        but checking "Target mounted disk" next to it switches it to
        read that same drive letter's event logs instead (via
        Start-EZfixCategoryScoping's -EvtxRoot parameter) - live-only
        data points for that category (CPU load, local users, installed
        hotfixes, etc.) are automatically skipped in that mode, since
        they don't apply to a disk that isn't running its own OS.
    So: bring the disk online in Advanced, get its drive letter (auto-
    filled if possible), then either run Offline Analysis there, or go
    back up to section 1, tick "Target mounted disk", and run whichever
    category evidence collection applies - both read the same disk.

    Session log vs. evidence collection - the distinction that matters:
    the session log (added 2026-09-11) is a lightweight audit trail -
    one line per action, saying what ran and whether it succeeded. It
    is NOT deep diagnostics - no event log parsing, no registry reads.
    That discipline stays exactly where it always was: only category
    evidence collection and Offline Analysis do real evidence
    collection. The session log (and the pop-up confirmations in
    section 1) just answer "what did I click, and did it work" - a
    receipt, not a forensic report.

    Why a pop-up only on section 1: section 2's actions already ask for
    an explicit confirmation before running (state change) or produce
    a multi-line report better read in the log/report folder (offline
    analysis) - stacking another pop-up on top would be redundant.
    Section 1's quick fixes are one-shot actions with no separate
    report, so a pop-up is the natural way to know "did it work" without
    scrolling the log. NOTE: "completed" in the pop-up means the check
    ran without a script error - it does NOT mean no problem was found
    (e.g. RDP diagnostics can complete normally and still report RDP as
    blocked - that's a real finding, not a script failure). Read the log
    for what was actually found.

    Why GUI and not Out-ConsoleGridView: decided (2026-09-10) to use a
    real Windows Forms window instead of a console grid - same
    selection/confirmation logic as always, shown with buttons and
    radio buttons instead of plain text.

    Scope on purpose: this interface does NOT add any new action - it
    only visually organizes the modules that already exist. There is no
    "check for Windows updates" and no "auto-repair" of an offline disk
    here - that was deliberately left out: on a disk that isn't yours
    and won't boot, the only safe repair is to not touch it, which is
    why offline analysis is read-only, and this interface follows the
    same rule.

    Requires:
      - Windows, PowerShell running as Administrator.
      - PowerShell 7 (pwsh), not Windows PowerShell 5.1 - the Network
        button runs Network-Diagnostics.ps1, which uses pwsh automatic
        variables that 5.1 does not have (you should already have pwsh
        7 installed from EZfix-Bootstrap.ps1). PowerShell 7 is also what
        lets this file use the ternary operator (?:) below.
      - These files in the SAME folder as this script:
          EZfix-Common.ps1, Disk-Selector.ps1, EZfix-OfflineAnalysis.ps1,
          EZfix-Performance.ps1, EZfix-Cleanup.ps1, EZfix-RDP.ps1,
          EZfix-Bootstrap.ps1, EZfix-CategoryScoping.ps1,
          Network-Diagnostics.ps1
        (they load themselves if needed, except Network-Diagnostics.ps1,
        which is run as a separate script every time the button is
        clicked - it is not a function, so it can't be dot-sourced once
        like the others).

    Note (2026-09-11): EZfix-CategoryScoping.ps1 supersedes the old
    EZfix-Scoping.ps1 (single generic bucket) - it covers the same
    "Other" behavior as one of its five categories, plus four more
    focused ones (Network/Auth/App/OS). EZfix-Scoping.ps1 is no longer
    a dependency of this interface; keep it only for git history if you
    want, it isn't required for the panel to work.
#>

#Requires -Version 7.0
#Requires -RunAsAdministrator
#Requires -Modules Storage

# --- Automatic dependency loading (functions), same pattern as
# EZfix-CategoryScoping.ps1. Network-Diagnostics.ps1 is deliberately not in
# here - it's a top-level script, not a function, so it's run
# separately with the "&" operator each time it's needed (see the
# "Network" button below).
$ezfixDependencies = [ordered]@{
    'New-EZfixReportFolder'      = 'EZfix-Common.ps1'
    'Show-DiskInventory'         = 'Disk-Selector.ps1'
    'Set-DataDiskState'          = 'Disk-Selector.ps1'
    'Start-EZfixOfflineAnalysis' = 'EZfix-OfflineAnalysis.ps1'
    'Start-EZfixPerformance'     = 'EZfix-Performance.ps1'
    'Start-EZfixCleanup'         = 'EZfix-Cleanup.ps1'
    'Start-EZfixRDPCheck'        = 'EZfix-RDP.ps1'
    'Start-EZfixBootstrap'       = 'EZfix-Bootstrap.ps1'
    'Start-EZfixCategoryScoping' = 'EZfix-CategoryScoping.ps1'
}

foreach ($funcName in $ezfixDependencies.Keys) {
    if (-not (Get-Command $funcName -ErrorAction SilentlyContinue)) {
        $depFile = $ezfixDependencies[$funcName]
        $depPath = Join-Path $PSScriptRoot $depFile
        if (Test-Path $depPath) {
            . $depPath
        }
        else {
            Write-Host "Missing $depFile in the same folder as EZfix-Interface.ps1 - cannot continue." -ForegroundColor Red
            return
        }
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Start-EZfixInterface {
    <#
        Opens the EZfix panel. Takes no parameters - everything is
        chosen inside the window.
    #>
    [CmdletBinding()]
    param()

    if ($env:OS -ne 'Windows_NT') {
        Write-Host "This interface uses Windows Forms - it only works on Windows." -ForegroundColor Red
        return
    }

    # ============================================================
    # Session log file - a lightweight audit trail, not evidence
    # collection (see the header comment for the distinction). Created
    # once per GUI session; every log line shown on screen is also
    # appended here.
    # ============================================================
    $sessionLogFolder = Join-Path ([Environment]::GetFolderPath('Desktop')) "EZfix\sessions"
    New-Item -Path $sessionLogFolder -ItemType Directory -Force | Out-Null
    $sessionLogPath = Join-Path $sessionLogFolder ("session_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

    # ============================================================
    # Main window
    # ============================================================
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "EZfix - Control Panel"
    # ClientSize (not Size) so control coordinates, which are relative
    # to the interior area, are guaranteed visible no matter how much
    # space the window's border/title bar takes up. Height is set later
    # by Update-EZfixLayout, once we know if Advanced starts collapsed.
    $form.ClientSize = New-Object System.Drawing.Size(485, 400)
    $form.StartPosition = 'CenterScreen'
    # Sizable (not FixedDialog) + MaximizeBox so the window can be
    # resized or maximized on small screens. AutoScroll is a fallback
    # safety net for the outer form itself, in case a future addition
    # ever makes the whole window taller than the screen again - the
    # Advanced panel below has its own internal scrolling (see
    # $pnlAdvanced.AutoScroll) which is the normal way tall content
    # is handled, so this outer one should rarely if ever trigger.
    $form.FormBorderStyle = 'Sizable'
    $form.MaximizeBox = $true
    $form.AutoScroll = $true
    $form.MinimumSize = New-Object System.Drawing.Size(500, 350)
    $form.BackColor = [System.Drawing.Color]::Gainsboro
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    # ============================================================
    # SECTION 1 - EZfix Quick Fixes
    # ============================================================
    $gbQuick = New-Object System.Windows.Forms.GroupBox
    $gbQuick.Text = "1. EZfix Quick Fixes (logged + pop-up confirmation)"
    $gbQuick.Location = New-Object System.Drawing.Point(15, 10)
    $gbQuick.Size = New-Object System.Drawing.Size(455, 178)
    $form.Controls.Add($gbQuick)

    function New-EZfixQuickButton {
        param([string]$Text, [int]$X, [int]$Y, [int]$Width = 125)
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = $Text
        $btn.Location = New-Object System.Drawing.Point($X, $Y)
        $btn.Size = New-Object System.Drawing.Size($Width, 30)
        return $btn
    }

    $btnNetwork     = New-EZfixQuickButton -Text "Network"              -X 10  -Y 25
    $btnPerformance = New-EZfixQuickButton -Text "Performance"          -X 145 -Y 25
    $btnCleanup     = New-EZfixQuickButton -Text "Cleanup"              -X 280 -Y 25
    $btnRDP         = New-EZfixQuickButton -Text "RDP"                  -X 10  -Y 65
    $btnBootstrap   = New-EZfixQuickButton -Text "Setup"                -X 145 -Y 65

    foreach ($btn in @($btnNetwork, $btnPerformance, $btnCleanup, $btnRDP, $btnBootstrap)) {
        $gbQuick.Controls.Add($btn)
    }

    # Third row: category-based evidence collection (replaces the old
    # single "Evidence" button - see EZfix-CategoryScoping.ps1).
    $lblEvidence = New-Object System.Windows.Forms.Label
    $lblEvidence.Text = "Evidence:"
    $lblEvidence.Location = New-Object System.Drawing.Point(10, 110)
    $lblEvidence.Size = New-Object System.Drawing.Size(60, 24)
    $gbQuick.Controls.Add($lblEvidence)

    $cmbCategory = New-Object System.Windows.Forms.ComboBox
    $cmbCategory.Location = New-Object System.Drawing.Point(75, 107)
    $cmbCategory.Size = New-Object System.Drawing.Size(150, 24)
    $cmbCategory.DropDownStyle = 'DropDownList'
    [void]$cmbCategory.Items.AddRange(@('Network', 'Auth', 'App', 'OS', 'Other'))
    $cmbCategory.SelectedIndex = 0
    $gbQuick.Controls.Add($cmbCategory)

    $btnCollectEvidence = New-EZfixQuickButton -Text "Collect Evidence" -X 235 -Y 106 -Width 190
    $gbQuick.Controls.Add($btnCollectEvidence)

    # Fourth row: optional switch to point evidence collection at a
    # mounted disk instead of this PC - reuses the SAME drive-letter
    # field from the Advanced section below (Get/set it there first:
    # detect the disk, bring it online, confirm the drive letter).
    # Unchecked (default) = collect from this PC, same as before.
    $chkEvidenceOffline = New-Object System.Windows.Forms.CheckBox
    $chkEvidenceOffline.Text = "Target mounted disk (drive letter set in Advanced, below)"
    $chkEvidenceOffline.Location = New-Object System.Drawing.Point(10, 140)
    $chkEvidenceOffline.Size = New-Object System.Drawing.Size(415, 22)
    $gbQuick.Controls.Add($chkEvidenceOffline)

    # ============================================================
    # SECTION 2 - Advanced (collapsible disk analysis panel)
    # ============================================================

    # The toggle bar doubles as the section header and the
    # expand/collapse control - click it to show or hide everything
    # below (Update-EZfixLayout does the actual show/hide + resize).
    $btnToggleAdvanced = New-Object System.Windows.Forms.Button
    $btnToggleAdvanced.Location = New-Object System.Drawing.Point(15, 198)
    $btnToggleAdvanced.Size = New-Object System.Drawing.Size(455, 28)
    $btnToggleAdvanced.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $btnToggleAdvanced.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($btnToggleAdvanced)

    # Everything under "Advanced" lives inside this one panel, so
    # showing/hiding it is a single $pnlAdvanced.Visible flip instead of
    # toggling five controls separately.
    $pnlAdvanced = New-Object System.Windows.Forms.Panel
    $pnlAdvanced.Location = New-Object System.Drawing.Point(15, 232)
    # Fixed height, regardless of how much content lives inside it -
    # AutoScroll shows an internal scrollbar once the disk list /
    # partitions / state / offline-analysis controls (which sit below,
    # at Y values well past this height) don't all fit. This keeps the
    # outer window's size predictable no matter how many disks are
    # detected or how long a disk's model name is, instead of growing
    # the whole window taller every time content grows. (Its actual
    # height also grows/shrinks live as the window is resized - see
    # Resize-EZfixAdvancedPanel below.)
    $pnlAdvanced.Size = New-Object System.Drawing.Size(455, 460)
    $pnlAdvanced.AutoScroll = $true
    $pnlAdvanced.BackColor = [System.Drawing.Color]::Gainsboro
    $form.Controls.Add($pnlAdvanced)

    $btnDetect = New-Object System.Windows.Forms.Button
    $btnDetect.Text = "Detect Disks"
    $btnDetect.Location = New-Object System.Drawing.Point(0, 0)
    $btnDetect.Size = New-Object System.Drawing.Size(150, 30)
    $pnlAdvanced.Controls.Add($btnDetect)

    $gbDisks = New-Object System.Windows.Forms.GroupBox
    $gbDisks.Text = "Detected disks (maximum 5)"
    $gbDisks.Location = New-Object System.Drawing.Point(0, 40)
    # Tall enough for 5 two-line rows (see $rb.Text below) - a disk's
    # FriendlyName length varies by hardware, so the label is split
    # across two explicit lines instead of relying on one long line
    # that either overflows the box or wraps unpredictably.
    $gbDisks.Size = New-Object System.Drawing.Size(435, 255)
    $pnlAdvanced.Controls.Add($gbDisks)

    $diskRadios = @()
    for ($i = 0; $i -lt 5; $i++) {
        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Location = New-Object System.Drawing.Point(10, (18 + $i * 44))
        $rb.Size = New-Object System.Drawing.Size(415, 40)
        $rb.Visible = $false
        # Selecting a disk (radio goes from unchecked to checked) refreshes
        # the partition breakdown below (Update-PartitionsDisplay, defined
        # further down) - $this is the radio that raised the event, its
        # .Tag holds the disk number the same way $btnApply reads it.
        $rb.Add_CheckedChanged({
            if ($this.Checked -and $this.Tag) {
                Update-PartitionsDisplay -DiskNumber $this.Tag
            }
        })
        $gbDisks.Controls.Add($rb)
        $diskRadios += $rb
    }

    $gbPartitions = New-Object System.Windows.Forms.GroupBox
    $gbPartitions.Text = "Partitions on selected disk"
    $gbPartitions.Location = New-Object System.Drawing.Point(0, 305)
    $gbPartitions.Size = New-Object System.Drawing.Size(435, 90)
    $pnlAdvanced.Controls.Add($gbPartitions)

    $txtPartitions = New-Object System.Windows.Forms.TextBox
    $txtPartitions.Location = New-Object System.Drawing.Point(10, 20)
    $txtPartitions.Size = New-Object System.Drawing.Size(415, 62)
    $txtPartitions.Multiline = $true
    $txtPartitions.ScrollBars = 'Vertical'
    $txtPartitions.ReadOnly = $true
    $txtPartitions.Font = New-Object System.Drawing.Font("Consolas", 8)
    $txtPartitions.Text = "Select a disk above to see its partitions."
    $gbPartitions.Controls.Add($txtPartitions)

    $gbState = New-Object System.Windows.Forms.GroupBox
    $gbState.Text = "Desired state for the selected disk"
    $gbState.Location = New-Object System.Drawing.Point(0, 405)
    $gbState.Size = New-Object System.Drawing.Size(435, 55)
    $pnlAdvanced.Controls.Add($gbState)

    $rbOnline = New-Object System.Windows.Forms.RadioButton
    $rbOnline.Text = "ONLINE"
    $rbOnline.Location = New-Object System.Drawing.Point(15, 22)
    $rbOnline.Size = New-Object System.Drawing.Size(100, 22)
    $gbState.Controls.Add($rbOnline)

    $rbOffline = New-Object System.Windows.Forms.RadioButton
    $rbOffline.Text = "OFFLINE"
    $rbOffline.Location = New-Object System.Drawing.Point(150, 22)
    $rbOffline.Size = New-Object System.Drawing.Size(100, 22)
    $gbState.Controls.Add($rbOffline)

    $btnApply = New-Object System.Windows.Forms.Button
    $btnApply.Text = "Apply State Change"
    $btnApply.Location = New-Object System.Drawing.Point(0, 470)
    $btnApply.Size = New-Object System.Drawing.Size(210, 30)
    $pnlAdvanced.Controls.Add($btnApply)

    # GroupBox.Text is a single-line caption, not a paragraph - it does
    # not reliably wrap, so the explanation lives in its own wrapped
    # Label inside the box instead of being crammed into the title
    # (that's what was getting visually cut off before).
    $gbDiag = New-Object System.Windows.Forms.GroupBox
    $gbDiag.Text = "Offline Analysis"
    $gbDiag.Location = New-Object System.Drawing.Point(0, 510)
    $gbDiag.Size = New-Object System.Drawing.Size(435, 95)
    $pnlAdvanced.Controls.Add($gbDiag)

    $lblDiagInfo = New-Object System.Windows.Forms.Label
    $lblDiagInfo.Text = "Disk must already be ONLINE with a drive letter (below). Same letter is used by 'Target mounted disk' above."
    $lblDiagInfo.Location = New-Object System.Drawing.Point(10, 18)
    $lblDiagInfo.Size = New-Object System.Drawing.Size(415, 32)
    $lblDiagInfo.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblDiagInfo.ForeColor = [System.Drawing.Color]::DimGray
    $gbDiag.Controls.Add($lblDiagInfo)

    $lblLetter = New-Object System.Windows.Forms.Label
    $lblLetter.Text = "Drive:"
    $lblLetter.Location = New-Object System.Drawing.Point(10, 60)
    $lblLetter.Size = New-Object System.Drawing.Size(50, 22)
    $gbDiag.Controls.Add($lblLetter)

    $txtLetter = New-Object System.Windows.Forms.TextBox
    $txtLetter.Location = New-Object System.Drawing.Point(65, 57)
    $txtLetter.Size = New-Object System.Drawing.Size(40, 22)
    $txtLetter.MaxLength = 1
    $gbDiag.Controls.Add($txtLetter)

    $btnDiag = New-Object System.Windows.Forms.Button
    $btnDiag.Text = "Run Offline Analysis"
    $btnDiag.Location = New-Object System.Drawing.Point(120, 55)
    $btnDiag.Size = New-Object System.Drawing.Size(170, 28)
    $gbDiag.Controls.Add($btnDiag)

    # ============================================================
    # Log - shared by both sections, also written to the session log file.
    # Its Y position moves depending on whether Advanced is expanded -
    # Update-EZfixLayout (defined further below, called at the end)
    # positions it and resizes the window.
    # ============================================================
    $lblLog = New-Object System.Windows.Forms.Label
    $lblLog.Text = "Log:"
    $lblLog.Size = New-Object System.Drawing.Size(300, 20)
    $form.Controls.Add($lblLog)

    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Size = New-Object System.Drawing.Size(455, 150)
    $txtLog.Multiline = $true
    $txtLog.ScrollBars = 'Vertical'
    $txtLog.ReadOnly = $true
    $txtLog.Font = New-Object System.Drawing.Font("Consolas", 8.5)
    $form.Controls.Add($txtLog)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Size = New-Object System.Drawing.Size(85, 28)
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)

    function Set-EZfixLogAndCloseLocation {
        <#
            Positions the Log label/box and Close button directly below
            $pnlAdvanced's CURRENT bottom edge (whatever height it
            happens to have right now - its collapsed/expanded default,
            or whatever Resize-EZfixAdvancedPanel last resized it to).
            Shared by Update-EZfixLayout (collapse/expand) and
            Resize-EZfixAdvancedPanel (live window resize) so the "233px
            reserved below the panel" arithmetic (label + textbox +
            close button + margins) only lives in one place.
        #>
        $logY = $pnlAdvanced.Visible `
            ? ($pnlAdvanced.Location.Y + $pnlAdvanced.Height + 10) `
            : ($btnToggleAdvanced.Location.Y + $btnToggleAdvanced.Height + 8)

        $lblLog.Location = New-Object System.Drawing.Point(15, $logY)
        $txtLog.Location = New-Object System.Drawing.Point(15, ($logY + 20))
        $btnClose.Location = New-Object System.Drawing.Point(385, ($logY + 20 + $txtLog.Height + 10))
    }

    function Update-EZfixLayout {
        <#
            Shows/hides the Advanced panel and repositions everything
            below it (log + Close button) and the window itself
            accordingly. Single source of truth for the "expander"
            behavior, called once at startup (collapsed) and again on
            every click of the Advanced toggle bar.
        #>
        param([bool]$AdvancedExpanded)

        $pnlAdvanced.Visible = $AdvancedExpanded
        $btnToggleAdvanced.Text = $AdvancedExpanded `
            ? "$([char]0x25BC) Advanced (disk analysis / investigation) - click to collapse" `
            : "$([char]0x25B6) Advanced (disk analysis / investigation) - click to expand"

        Set-EZfixLogAndCloseLocation

        $desiredHeight = $btnClose.Location.Y + $btnClose.Height + 15

        # Safety net for small screens: never make the window taller
        # than the visible work area (screen minus taskbar). Normally
        # $desiredHeight already fits because $pnlAdvanced's height
        # (whether its default or a size the user dragged/maximized to
        # via Resize-EZfixAdvancedPanel) was itself already derived from
        # the screen - this just guards the collapsed state and any
        # unusually short display. $form's own AutoScroll (set above)
        # picks up the slack if this clamp ever actually kicks in.
        $maxHeight = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height - 40
        if ($desiredHeight -gt $maxHeight) { $desiredHeight = $maxHeight }

        $form.ClientSize = New-Object System.Drawing.Size(485, $desiredHeight)
    }

    function Resize-EZfixAdvancedPanel {
        <#
            Called on every window resize (see $form.Add_Resize near the
            end of this function). When Advanced is expanded, stretches
            the panel's height to use whatever extra vertical room the
            window now has, instead of leaving it blank below a
            fixed-height panel - this is what makes "maximize"
            (intercepted below to grow height only, not width) actually
            show more of the disk list / partitions / state / offline
            analysis controls, rather than just a bigger empty window.
            Does nothing while collapsed (nothing to grow) or minimized
            (ClientSize is meaningless there).
        #>
        if (-not $pnlAdvanced.Visible) { return }
        if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { return }

        $newPanelHeight = $form.ClientSize.Height - $pnlAdvanced.Location.Y - 233
        if ($newPanelHeight -lt 300) { $newPanelHeight = 300 }
        if ($newPanelHeight -eq $pnlAdvanced.Height) { return }

        $pnlAdvanced.Size = New-Object System.Drawing.Size($pnlAdvanced.Size.Width, $newPanelHeight)
        Set-EZfixLogAndCloseLocation
    }

    function Update-PartitionsDisplay {
        <#
            Fills the "Partitions on selected disk" box with every
            partition on the given disk (number, type, size, drive
            letter or "no letter") - separate from the disk list above
            it because Online/Offline is a whole-DISK operation, but a
            disk can hold several partitions (EFI, Recovery, the actual
            data/Windows partition, etc.) and seeing that breakdown
            before bringing something online is useful context, not
            just the single summary line the radio button shows.
        #>
        param([int]$DiskNumber)

        try {
            $partitions = Get-Partition -DiskNumber $DiskNumber -ErrorAction Stop | Sort-Object PartitionNumber
        }
        catch {
            $txtPartitions.Text = "Could not read partitions for disk ${DiskNumber}: $($_.Exception.Message)"
            return
        }

        if (-not $partitions) {
            $txtPartitions.Text = "No partitions found on disk $DiskNumber."
            return
        }

        $lines = foreach ($p in $partitions) {
            $sizeGB = [math]::Round($p.Size / 1GB, 2)
            $letter = if ($p.DriveLetter) { "$($p.DriveLetter):" } else { "no letter" }
            "#{0,-3} {1,-10} {2,10} GB   {3}" -f $p.PartitionNumber, $p.Type, $sizeGB, $letter
        }
        $txtPartitions.Text = ($lines -join "`r`n")
    }

    function Add-EZfixLogLine {
        <#
            Writes one line to the on-screen log AND appends it to the
            session log file on disk - this is the "receipt" the GUI
            keeps of what ran and whether it worked. Not evidence
            collection (see header comment) - just a plain audit trail.
        #>
        param([string]$Text)
        $timestamp = Get-Date -Format 'HH:mm:ss'
        $line = "[$timestamp] $Text"
        $txtLog.AppendText("$line`r`n")
        try {
            Add-Content -Path $sessionLogPath -Value $line -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            # If the log file itself can't be written (locked, no
            # permission, disk full), the GUI still works - the on-screen
            # log already showed the line. We just can't lose the whole
            # session over a log-write failure.
        }
    }

    function Invoke-EZfixAction {
        <#
            Runs one EZfix action, capturing its output (Write-Host
            travels through the Information stream from PS 5.1+, hence
            the "6>&1" inside each $Action) and dumping it line by line
            into the window's log (and the session log file). One place
            to avoid repeating the same try/catch in every button.

            -ShowPopup adds a pop-up confirmation at the end (used by
            section 1's buttons only - see header comment for why).
            "Completed" in that pop-up means "ran without a script
            error", not "found no problem" - read the log for findings.
        #>
        param(
            [Parameter(Mandatory)] [string]$Label,
            [Parameter(Mandatory)] [scriptblock]$Action,
            [switch]$ShowPopup
        )

        Add-EZfixLogLine "=== $Label ==="
        $hadError = $false
        $errorMessage = $null

        # Some checks (Network especially - ping/traceroute) take several
        # seconds. PowerShell runs the action on the same thread that
        # paints the window, so Windows can flag the window "(Not
        # Responding)" while it works - that's normal, not a crash. The
        # wait cursor is a visible sign it's still going; -NoNewWindow-
        # style blocking is unavoidable here without a bigger rewrite
        # (background jobs/runspaces), which is more complexity than this
        # project needs for what are, at most, ~30-second checks.
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
        try {
            $result = & $Action
            foreach ($item in $result) {
                if ($item -is [System.Management.Automation.InformationRecord]) {
                    Add-EZfixLogLine $item.ToString()
                }
                elseif ($item -is [string]) {
                    Add-EZfixLogLine $item
                }
            }
            Add-EZfixLogLine "--- $Label finished OK ---"
        }
        catch {
            $hadError = $true
            $errorMessage = $_.Exception.Message
            Add-EZfixLogLine "ERROR: $errorMessage"
            Add-EZfixLogLine "--- $Label finished with an ERROR ---"
        }
        finally {
            [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
        }
        Add-EZfixLogLine ""

        if ($ShowPopup) {
            if ($hadError) {
                [System.Windows.Forms.MessageBox]::Show(
                    "$Label failed to run:`r`n$errorMessage",
                    "EZfix - $Label", 'OK', 'Error'
                ) | Out-Null
            }
            else {
                [System.Windows.Forms.MessageBox]::Show(
                    "$Label completed. Check the log below for what it found.",
                    "EZfix - $Label", 'OK', 'Information'
                ) | Out-Null
            }
        }
    }

    Add-EZfixLogLine "EZfix session started on $([System.Net.Dns]::GetHostName()). Session log: $sessionLogPath"

    # ============================================================
    # SECTION 1 - events (all with -ShowPopup)
    # ============================================================
    $btnNetwork.Add_Click({
        $scriptPath = Join-Path $PSScriptRoot 'Network-Diagnostics.ps1'
        if (-not (Test-Path $scriptPath)) {
            Add-EZfixLogLine "Network-Diagnostics.ps1 was not found in this folder."
            return
        }
        Invoke-EZfixAction -Label "Network diagnostics" -Action { & $scriptPath 6>&1 } -ShowPopup
    })

    $btnPerformance.Add_Click({
        Invoke-EZfixAction -Label "Performance" -Action { Start-EZfixPerformance 6>&1 } -ShowPopup
    })

    $btnCleanup.Add_Click({
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "This will delete user temp files, system temp files, and empty the Recycle Bin. Continue?",
            "Confirm cleanup", 'YesNo', 'Warning'
        )
        if ($confirm -ne 'Yes') {
            Add-EZfixLogLine "Cleanup canceled (not confirmed)."
            return
        }
        Invoke-EZfixAction -Label "Cleanup" -Action { Start-EZfixCleanup -Confirm:$false 6>&1 } -ShowPopup
    })

    $btnRDP.Add_Click({
        Invoke-EZfixAction -Label "RDP diagnostics" -Action { Start-EZfixRDPCheck 6>&1 } -ShowPopup
    })

    $btnBootstrap.Add_Click({
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "This will check EZfix's prerequisites (PowerShell 7, required Windows modules, networking tools) and offer to install anything missing, including PowerShell 7 itself if this computer doesn't have it yet. Continue?",
            "Confirm setup", 'YesNo', 'Warning'
        )
        if ($confirm -ne 'Yes') {
            Add-EZfixLogLine "Setup canceled (not confirmed)."
            return
        }
        Invoke-EZfixAction -Label "Setup (PowerShell 7 + prerequisites)" -Action { Start-EZfixBootstrap -Confirm:$false 6>&1 } -ShowPopup
    })

    $btnCollectEvidence.Add_Click({
        if (-not $cmbCategory.SelectedItem) {
            [System.Windows.Forms.MessageBox]::Show("Select a category first.", "EZfix", 'OK', 'Warning') | Out-Null
            return
        }
        $category = $cmbCategory.SelectedItem.ToString()

        # "Target mounted disk" reuses the Advanced section's Drive
        # field - same drive letter Offline Analysis uses - so both
        # engines always point at the same disk without asking for the
        # letter twice.
        $evtxRoot = $null
        $letter = $null
        if ($chkEvidenceOffline.Checked) {
            $letter = $txtLetter.Text.Trim()
            if ($letter -notmatch '^[A-Za-z]$') {
                [System.Windows.Forms.MessageBox]::Show("Enter a valid drive letter in the Advanced section's Drive field first (expand Advanced, detect the disk, bring it Online, confirm/type its letter there), then try again.", "EZfix", 'OK', 'Warning') | Out-Null
                return
            }
            $evtxRoot = "${letter}:\Windows\System32\winevt\Logs"
            if (-not (Test-Path $evtxRoot)) {
                [System.Windows.Forms.MessageBox]::Show("Could not find $evtxRoot - check that ${letter}: is the correct, online drive letter for the disk under investigation.", "EZfix", 'OK', 'Warning') | Out-Null
                return
            }
        }

        $label = if ($evtxRoot) { "Evidence collection ($category, disk ${letter}:)" } else { "Evidence collection ($category, this PC)" }
        Invoke-EZfixAction -Label $label -Action {
            if ($evtxRoot) {
                Start-EZfixCategoryScoping -Category $category -EvtxRoot $evtxRoot 6>&1
            }
            else {
                Start-EZfixCategoryScoping -Category $category 6>&1
            }
        } -ShowPopup
    })

    # ============================================================
    # SECTION 2 - events (Advanced panel - no pop-up, see header comment)
    # ============================================================
    $btnToggleAdvanced.Add_Click({
        Update-EZfixLayout -AdvancedExpanded:(-not $pnlAdvanced.Visible)
    })

    $btnDetect.Add_Click({
        foreach ($rb in $diskRadios) {
            $rb.Visible = $false
            $rb.Checked = $false
            $rb.Tag = $null
            $rb.Font = $gbDisks.Font
        }
        $txtPartitions.Text = "Select a disk above to see its partitions."

        try {
            # Show-DiskInventory prints with Write-Host AND returns an
            # object. We filter out the InformationRecords (Write-Host)
            # to keep only the real object used to build the list.
            $inventory = Show-DiskInventory 6>&1 |
                Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] }
        }
        catch {
            Add-EZfixLogLine "ERROR detecting disks: $($_.Exception.Message)"
            return
        }

        if (-not $inventory) {
            Add-EZfixLogLine "Could not read the disk inventory (check that PowerShell is running as Administrator)."
            return
        }

        $disksToShow = $inventory.Disks | Select-Object -First 5

        if ($inventory.Disks.Count -gt 5) {
            Add-EZfixLogLine "Detected $($inventory.Disks.Count) disks - this screen only shows the first 5."
        }

        for ($i = 0; $i -lt $disksToShow.Count; $i++) {
            $disk = $disksToShow[$i]
            $sizeGB = [math]::Round($disk.Size / 1GB, 1)
            $isOSDisk = $disk.Number -eq $inventory.OSDiskNumber
            $statusText = if ($isOSDisk) { "ONLINE - SYSTEM DISK, LOCKED" } else { $disk.OperationalStatus.ToString().ToUpper() }

            # Drive letter(s), if any - shown both on the first scan and
            # after Detect Disks re-runs (Apply State Change calls
            # $btnDetect.PerformClick() at the end), so the letter this
            # list shows always reflects the disk's current state,
            # including one EZfix just auto-assigned.
            $driveLetters = (Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue |
                Where-Object { $_.DriveLetter } |
                ForEach-Object { "$($_.DriveLetter):" }) -join ', '
            if (-not $driveLetters) { $driveLetters = 'no letter' }

            $rb = $diskRadios[$i]
            # Two explicit lines (not one long line left to auto-wrap) -
            # a disk's FriendlyName length varies by hardware, and
            # letting Windows wrap a single long line put the break in
            # an unpredictable spot that got clipped by the row below it.
            $rb.Text = "[{0}] {1} - {2} GB`r`n{3} - {4}" -f $disk.Number, $disk.FriendlyName, $sizeGB, $statusText, $driveLetters
            $rb.Tag = $disk.Number
            $rb.Visible = $true
            # Same safety rule as Disk-Selector, enforced here too: the
            # system disk cannot even be selected in the GUI.
            $rb.Enabled = -not $isOSDisk
            $rb.ForeColor = if ($isOSDisk) {
                [System.Drawing.Color]::Gray
            }
            elseif ($disk.OperationalStatus -eq 'Online') {
                [System.Drawing.Color]::DarkGreen
            }
            else {
                [System.Drawing.Color]::DarkRed
            }
            # Windows renders ANY disabled control's text in a fixed
            # system gray, ignoring whatever custom ForeColor is set
            # above - that's Windows' own theming, not a bug here, so
            # the OS disk row can't actually show up in a distinct color
            # while it's disabled. Bold survives being disabled though,
            # so it's used here as the visual "this one's different" cue
            # instead, on top of the text already saying LOCKED.
            if ($isOSDisk) {
                $rb.Font = New-Object System.Drawing.Font($gbDisks.Font, [System.Drawing.FontStyle]::Bold)
            }
        }

        Add-EZfixLogLine "Disks detected. System disk: $($inventory.OSDiskNumber) (locked, not selectable)."
    })

    $btnApply.Add_Click({
        $selectedDiskRb = $diskRadios | Where-Object { $_.Visible -and $_.Checked }
        if (-not $selectedDiskRb) {
            [System.Windows.Forms.MessageBox]::Show("Select a disk first.", "EZfix", 'OK', 'Warning') | Out-Null
            return
        }
        if (-not $rbOnline.Checked -and -not $rbOffline.Checked) {
            [System.Windows.Forms.MessageBox]::Show("Select the desired state (Online or Offline).", "EZfix", 'OK', 'Warning') | Out-Null
            return
        }

        $diskNumber = $selectedDiskRb.Tag
        $targetState = if ($rbOnline.Checked) { 'Online' } else { 'Offline' }

        # Explicit GUI confirmation - same spirit as Set-DataDiskState's
        # console -Confirm, just as a dialog box. That's why the function
        # is called with -Confirm:$false afterwards: confirmation already
        # happened here, no need to ask twice.
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "This will set disk $diskNumber to $($targetState.ToUpper()) state. If this is the wrong disk, it could affect its data. Continue?",
            "Confirm state change", 'YesNo', 'Warning'
        )
        if ($confirm -ne 'Yes') {
            Add-EZfixLogLine "State change canceled (not confirmed)."
            return
        }

        Invoke-EZfixAction -Label "State change (disk $diskNumber to $targetState)" -Action {
            Set-DataDiskState -DiskNumber $diskNumber -TargetState $targetState -Confirm:$false 6>&1
        }

        if ($targetState -eq 'Online') {
            # Convenience improvement (2026-09-11): a disk that just came
            # online doesn't always get a drive letter automatically -
            # this used to mean going to Disk Management by hand before
            # Offline Analysis could run. Now: look for a letter Windows
            # already assigned, and if none exists, assign one ourselves.
            # This is safe/reversible (same "auto-fix only if safe" rule
            # as the rest of EZfix) and never touches the OS disk, which
            # is already blocked from ever reaching this code path.
            try {
                $partitions = Get-Partition -DiskNumber $diskNumber -ErrorAction Stop
                $assignedLetter = $null

                # DriveLetter is the null character (not $null) when
                # unassigned - PowerShell treats that as falsy, same as
                # an empty string or a zero, so this check works as-is.
                foreach ($partition in $partitions) {
                    if ($partition.DriveLetter) {
                        $assignedLetter = $partition.DriveLetter
                        Add-EZfixLogLine "Disk $diskNumber already has drive letter $($assignedLetter):"
                        break
                    }
                }

                if (-not $assignedLetter) {
                    $assignablePartitions = $partitions | Where-Object { $_.Type -eq 'Basic' }
                    foreach ($partition in $assignablePartitions) {
                        try {
                            Add-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $partition.PartitionNumber -AssignDriveLetter -ErrorAction Stop
                            $updated = Get-Partition -DiskNumber $diskNumber -PartitionNumber $partition.PartitionNumber
                            if ($updated.DriveLetter) {
                                $assignedLetter = $updated.DriveLetter
                                Add-EZfixLogLine "Assigned drive letter $($assignedLetter): to disk $diskNumber, partition $($partition.PartitionNumber)."
                                break
                            }
                        }
                        catch {
                            # Some partitions genuinely can't take a letter
                            # (e.g. Recovery/EFI) - expected, not an error
                            # worth stopping over.
                        }
                    }
                }

                if ($assignedLetter) {
                    $txtLetter.Text = "$assignedLetter"
                    Add-EZfixLogLine "Drive field auto-filled with $($assignedLetter): - ready for Offline Analysis."
                }
                else {
                    Add-EZfixLogLine "Could not find or assign a drive letter for disk $diskNumber - assign one manually in Disk Management if this disk has data you need to read."
                }
            }
            catch {
                Add-EZfixLogLine "Could not check partitions for a drive letter: $($_.Exception.Message)"
            }
        }

        # Refresh the list so the displayed state is up to date.
        $btnDetect.PerformClick()
    })

    $btnDiag.Add_Click({
        $letter = $txtLetter.Text.Trim()
        if ($letter -notmatch '^[A-Za-z]$') {
            [System.Windows.Forms.MessageBox]::Show("Enter a single valid drive letter (e.g. D).", "EZfix", 'OK', 'Warning') | Out-Null
            return
        }

        Invoke-EZfixAction -Label "Offline analysis (${letter}:)" -Action {
            Start-EZfixOfflineAnalysis -DriveLetter $letter 6>&1
        }
    })

    # Clicking Maximize (or double-clicking the title bar) normally
    # stretches the window to the FULL SCREEN WIDTH too, which just
    # leaves a huge blank gray area next to this narrow layout instead
    # of anything useful. Intercepted here so "maximize" keeps this
    # window's normal width and only grows it from the top of the
    # screen to the bottom - Resize-EZfixAdvancedPanel (triggered by the
    # ClientSize change this makes) then grows the Advanced panel to
    # actually use that extra height, and dragging the window's bottom
    # edge by hand does the same thing incrementally.
    $form.Add_Resize({
        if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Maximized) {
            $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
            $workArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
            $form.Location = New-Object System.Drawing.Point($form.Location.X, $workArea.Top)
            $form.ClientSize = New-Object System.Drawing.Size(485, $workArea.Height)
            # Setting ClientSize above fires this same Resize event again;
            # that re-entrant call sees WindowState already back to
            # Normal, so it falls through to Resize-EZfixAdvancedPanel on
            # its own - nothing more to do on this pass.
            return
        }
        Resize-EZfixAdvancedPanel
    })

    # Start collapsed - "Advanced" is opt-in, not the default view.
    Update-EZfixLayout -AdvancedExpanded:$false

    [void]$form.ShowDialog()
}

<#
    USAGE (PowerShell 7 / pwsh, running as Administrator):
        . .\EZfix-Interface.ps1
        Start-EZfixInterface

    The other EZfix files (Common, Disk-Selector, OfflineAnalysis,
    Performance, Cleanup, RDP, Bootstrap, CategoryScoping,
    Network-Diagnostics) must be saved in the same folder - this script
    loads them itself if needed.

    Every action's output is logged to Desktop\EZfix\sessions\ as well
    as shown on screen. Section 1 (Quick Fixes) also pops up a
    confirmation dialog when it finishes; section 2 (Advanced) does not
    - see the header comment for why.
#>