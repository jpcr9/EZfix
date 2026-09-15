<#
EZfix v1.0.0 Windows control panel. Modules are loaded from this folder.
The output area grows with the window; "Advanced" is a collapsible panel
split into tabs (Disk Investigation / Evidence / More), each sized to
fit without dragging the others along - only the tab that actually has
long content (Disk Investigation, and inside it the disk list itself)
scrolls on its own.
Actions run on the UI thread. Review results even when an action completes.
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
    'Start-EZfixConnectivity'    = 'EZfix-Connectivity.ps1'
    'Start-EZfixRDPCheck'        = 'EZfix-RDP.ps1'
    'Open-EZfixVhd'              = 'EZfix-VirtualDisks.ps1'
    'Close-EZfixVhd'             = 'EZfix-VirtualDisks.ps1'
    'Show-EZfixVhdFinder'        = 'EZfix-VhdFinder.ps1'
    'Start-EZfixSystemOverview'  = 'EZfix-SystemTools.ps1'
    'Start-EZfixRecentErrors'    = 'EZfix-SystemTools.ps1'
    'Get-EZfixSecondaryEventPath' = 'EZfix-SystemTools.ps1'
    'Start-EZfixCategoryScoping' = 'EZfix-CategoryScoping.ps1'
    'Show-EZfixToolCard'         = 'EZfix-Toolbox.ps1'
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
[System.Windows.Forms.Application]::EnableVisualStyles()

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
    $form.Text = "EZfix v1.0.0 - Control Panel"
    # ClientSize (not Size) so control coordinates, which are relative
    # to the interior area, are guaranteed visible no matter how much
    # space the window's border/title bar takes up. Height is set later
    # by Update-EZfixLayout, once we know if "Advanced" starts collapsed.
    $form.ClientSize = New-Object System.Drawing.Size(850, 680)
    $form.StartPosition = 'CenterScreen'
    # Sizable (not FixedDialog) + MaximizeBox so the window can be
    # resized or maximized on small screens. AutoScroll is a fallback
    # safety net for the outer form itself, in case a future addition
    # ever makes the whole window taller than the screen again - each
    # tab inside the "Advanced" panel manages its own overflow (see
    # $tabsAdvanced below), so this outer one should rarely if ever trigger.
    $form.FormBorderStyle = 'Sizable'
    $form.MaximizeBox = $true
    $form.AutoScroll = $true
    $form.MinimumSize = New-Object System.Drawing.Size(540, 600)
    $form.BackColor = [System.Drawing.Color]::Gainsboro
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    # ============================================================
    # SECTION 1 - EZfix Quick Fixes
    # Self-service only: one click, one result, nothing to configure.
    # Evidence collection and the Toolbox live under "Advanced" instead
    # (see SECTION 2) - both are scoping aids for whoever picks up the
    # investigation afterward, not a fix a non-technical user would act
    # on themselves, so they don't belong on the front screen.
    # ============================================================
    $gbQuick = New-Object System.Windows.Forms.GroupBox
    $gbQuick.Text = "This PC: Diagnostics && Tools"
    $gbQuick.Location = New-Object System.Drawing.Point(15, 10)
    $gbQuick.Size = New-Object System.Drawing.Size(455, 115)
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
    $btnRDP         = New-EZfixQuickButton -Text "Connectivity && Security"                  -X 10  -Y 65
    $btnOverview   = New-EZfixQuickButton -Text "System Overview"                -X 145 -Y 65

    $btnRecentErrors = New-EZfixQuickButton -Text 'Recent Errors' -X 280 -Y 65
    foreach ($btn in @($btnNetwork, $btnPerformance, $btnCleanup, $btnRDP, $btnOverview, $btnRecentErrors)) {
        $gbQuick.Controls.Add($btn)
    }

    # ============================================================
    # SECTION 2 - "Advanced" (collapsible technical panel, tabbed)
    #
    # Everything here is for scoping an issue, not fixing it in one
    # click - so unlike Section 1, none of it pops up a "done" dialog
    # except evidence collection, which behaves the same wherever it
    # lives. Split into tabs (Disk Investigation / Evidence / More)
    # so opening one doesn't force scrolling past the other two - only
    # Disk Investigation is naturally tall, and within it the disk list
    # itself scrolls independently (see $pnlDiskList below). "More" is
    # the submenu for handy tool cards - see the Toolbox tab further
    # down for what it holds.
    # ============================================================

    # The toggle bar doubles as the section header and the
    # expand/collapse control - click it to show or hide everything
    # below (Update-EZfixLayout does the actual show/hide + resize).
    $btnToggleAdvanced = New-Object System.Windows.Forms.Button
    $btnToggleAdvanced.Location = New-Object System.Drawing.Point(15, 135)
    $btnToggleAdvanced.Size = New-Object System.Drawing.Size(455, 28)
    $btnToggleAdvanced.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $btnToggleAdvanced.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($btnToggleAdvanced)

    # Everything under "Advanced" lives inside this one panel, so
    # showing/hiding it is a single $pnlAdvanced.Visible flip instead of
    # toggling controls separately. It just hosts the tab control below -
    # it doesn't scroll itself (AutoScroll off) because $tabsAdvanced is
    # always sized to fit it exactly; each TabPage handles its own
    # overflow instead, so only the tab that's actually too tall shows a
    # scrollbar, not the whole section at once.
    $pnlAdvanced = New-Object System.Windows.Forms.Panel
    $pnlAdvanced.Location = New-Object System.Drawing.Point(15, 169)
    # Height is recalculated live in Resize-EZfixAdvancedPanel (bigger
    # now that the Log box below can be collapsed too - see
    # $btnToggleLog - so "Advanced" isn't stuck splitting the window 50/50
    # with a Log box that may not even be showing).
    $pnlAdvanced.Size = New-Object System.Drawing.Size(455, 460)
    $pnlAdvanced.AutoScroll = $false
    $pnlAdvanced.BackColor = [System.Drawing.Color]::Gainsboro
    $form.Controls.Add($pnlAdvanced)

    # Drag handle between "Advanced" and the Log box below it, so the
    # split between them is a manual choice instead of a fixed ratio -
    # same $splitState-as-a-mutable-hashtable idiom as $reportState /
    # $vhdState elsewhere in this file, so a plain drag doesn't need any
    # extra scope plumbing. Only shown while Advanced is expanded - see
    # Resize-EZfixAdvancedPanel, which also owns its position/width.
    $splitState = @{ Dragging = $false; StartY = 0; StartHeight = 0; AdvancedOverride = $null }
    $splitterAdvLog = New-Object System.Windows.Forms.Panel
    $splitterAdvLog.Height = 6
    $splitterAdvLog.BackColor = [System.Drawing.Color]::DarkGray
    $splitterAdvLog.Cursor = [System.Windows.Forms.Cursors]::SizeNS
    $form.Controls.Add($splitterAdvLog)
    $splitterAdvLog.Add_MouseDown({
        $splitState.Dragging = $true
        $splitState.StartY = [System.Windows.Forms.Cursor]::Position.Y
        $splitState.StartHeight = $pnlAdvanced.Height
        $splitterAdvLog.Capture = $true
    })
    $splitterAdvLog.Add_MouseMove({
        if (-not $splitState.Dragging) { return }
        $deltaY = [System.Windows.Forms.Cursor]::Position.Y - $splitState.StartY
        $available = [Math]::Max(300, $form.ClientSize.Height - $pnlAdvanced.Top - 80)
        $minAdv = 220
        $maxAdv = [Math]::Max($minAdv, $available)
        $splitState.AdvancedOverride = [Math]::Min($maxAdv, [Math]::Max($minAdv, ($splitState.StartHeight + $deltaY)))
        Resize-EZfixAdvancedPanel
    })
    $splitterAdvLog.Add_MouseUp({
        $splitState.Dragging = $false
        $splitterAdvLog.Capture = $false
    })

    $tabsAdvanced = New-Object System.Windows.Forms.TabControl
    $tabsAdvanced.Location = New-Object System.Drawing.Point(0, 0)
    $tabsAdvanced.Size = New-Object System.Drawing.Size(455, 460)
    $pnlAdvanced.Controls.Add($tabsAdvanced)

    $tabDisk = New-Object System.Windows.Forms.TabPage
    $tabDisk.Text = 'Disk Investigation'
    $tabDisk.AutoScroll = $true
    $tabEvidence = New-Object System.Windows.Forms.TabPage
    $tabEvidence.Text = 'Evidence'
    $tabEvidence.AutoScroll = $true
    $tabMore = New-Object System.Windows.Forms.TabPage
    $tabMore.Text = 'More'
    $tabMore.AutoScroll = $true
    $tabsAdvanced.Controls.AddRange(@($tabDisk, $tabEvidence, $tabMore))

    # ---- Tab: Disk Investigation ----
    # To analyze an affected OS disk without booting it, connect it as a
    # data disk to a healthy machine (Detect Disks / the disk list
    # below), or mount a VHD/VHDX image (Open/Find/Detach), bring it
    # ONLINE, then run Offline Analysis against its drive letter.
    $btnDetect = New-Object System.Windows.Forms.Button
    $btnDetect.Text = "Detect Disks"
    $btnDetect.Location = New-Object System.Drawing.Point(0, 8)
    $btnDetect.Size = New-Object System.Drawing.Size(150, 30)
    $tabDisk.Controls.Add($btnDetect)

    $btnVhdOpen = New-EZfixQuickButton -Text 'Open VHD/VHDX' -X 160 -Y 8 -Width 170
    $btnVhdFind = New-EZfixQuickButton -Text 'Find VHD/VHDX on this PC' -X 0 -Y 46 -Width 250
    $btnVhdDetach = New-EZfixQuickButton -Text 'Detach VHD/VHDX' -X 260 -Y 46 -Width 175
    $btnVhdDetach.Enabled = $false
    $lblVhd = [Windows.Forms.Label]::new()
    $lblVhd.Text = 'No VHD/VHDX opened here. Find searches local drives; Open selects a file.'
    $lblVhd.SetBounds(0, 84, 435, 40)
    $tabDisk.Controls.AddRange(@($btnVhdOpen, $btnVhdFind, $btnVhdDetach, $lblVhd))
    $vhdState = @{Path=$null;DiskNumber=$null}

    $gbDisks = New-Object System.Windows.Forms.GroupBox
    $gbDisks.Text = 'Detected disks'
    $gbDisks.Location = New-Object System.Drawing.Point(0, 132)
    # Tall enough for 5 two-line rows (see $rb.Text below) - a disk's
    # FriendlyName length varies by hardware, so the label is split
    # across two explicit lines instead of relying on one long line
    # that either overflows the box or wraps unpredictably. This box's
    # own internal scrollbar ($pnlDiskList.AutoScroll) is what lets you
    # scroll through the disk list specifically when there are more
    # disks than fit, independent of everything else in this tab.
    $gbDisks.Size = New-Object System.Drawing.Size(435, 255)
    $tabDisk.Controls.Add($gbDisks)
    $pnlDiskList = [Windows.Forms.Panel]::new()
    $pnlDiskList.SetBounds(5,18,425,230)
    $pnlDiskList.AutoScroll = $true
    $gbDisks.Controls.Add($pnlDiskList)

    $protectedDisks = [Collections.Generic.HashSet[int]]::new()
    $diskLabels = [Collections.Generic.List[object]]::new()
    $diskTips = [Windows.Forms.ToolTip]::new()
    $diskRadios = [Collections.Generic.List[Windows.Forms.RadioButton]]::new()
    function Add-EZfixDiskRadio {
        $i = $diskRadios.Count
        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Location = New-Object System.Drawing.Point(5, ($i * 44))
        $rb.Size = New-Object System.Drawing.Size(20, 40)
        $rb.Visible = $false
        # Selecting a disk (radio goes from unchecked to checked) refreshes
        # the partition breakdown below (Update-PartitionsDisplay, defined
        # further down) - $this is the radio that raised the event, its
        # .Tag holds the disk number the same way $btnApply reads it.
        $rb.Add_CheckedChanged({
            if ($this.Checked -and $null -ne $this.Tag) {
                $canChange = -not $protectedDisks.Contains([int]$this.Tag)
                $btnApply.Enabled=$canChange
                $rbOnline.Enabled=$canChange; $rbOffline.Enabled=$canChange
                if(-not $canChange){$rbOnline.Checked=$false; $rbOffline.Checked=$false}
                Update-PartitionsDisplay -DiskNumber $this.Tag
                # Selecting a radio buried inside this AutoScroll tab can
                # pull its scroll offset away from (0,0) even though every
                # control's own position is unchanged - WinForms doesn't
                # reset that on its own once it's nudged, so every button
                # on the tab appears to have "moved." Forcing it back to
                # (0,0) here is the fix, not a workaround for anything
                # actually wrong with the layout itself.
                $tabDisk.AutoScrollPosition = [Drawing.Point]::new(0, 0)
            }
        })
        $pnlDiskList.Controls.Add($rb)
        $diskRadios.Add($rb)
        $nameLabel=[Windows.Forms.Label]::new()
        $nameLabel.SetBounds(30,($i * 44),370,20)
        $nameLabel.AutoEllipsis=$true
        $stateLabel=[Windows.Forms.Label]::new()
        $stateLabel.SetBounds(30,($i * 44 + 20),62,20)
        $detailsLabel=[Windows.Forms.Label]::new()
        $detailsLabel.SetBounds(95,($i * 44 + 20),305,20)
        $detailsLabel.AutoEllipsis=$true
        foreach ($label in @($nameLabel,$stateLabel,$detailsLabel)) {
            $label.Tag=$rb
            $label.Add_Click({ if ($this.Tag.Enabled) { $this.Tag.Checked=$true } })
            $pnlDiskList.Controls.Add($label)
        }
        $diskLabels.Add([pscustomobject]@{Name=$nameLabel;State=$stateLabel;Details=$detailsLabel})
    }

    $gbPartitions = New-Object System.Windows.Forms.GroupBox
    $gbPartitions.Text = "Partitions on selected disk"
    $gbPartitions.Location = New-Object System.Drawing.Point(0, 395)
    $gbPartitions.Size = New-Object System.Drawing.Size(435, 90)
    $tabDisk.Controls.Add($gbPartitions)

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
    $gbState.Location = New-Object System.Drawing.Point(0, 493)
    $gbState.Size = New-Object System.Drawing.Size(435, 55)
    $tabDisk.Controls.Add($gbState)

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
    $btnApply.Enabled=$false
    $btnApply.Location = New-Object System.Drawing.Point(0, 556)
    $btnApply.Size = New-Object System.Drawing.Size(210, 30)
    $tabDisk.Controls.Add($btnApply)

    # GroupBox.Text is a single-line caption, not a paragraph - it does
    # not reliably wrap, so the explanation lives in its own wrapped
    # Label inside the box instead of being crammed into the title
    # (that's what was getting visually cut off before).
    $gbDiag = New-Object System.Windows.Forms.GroupBox
    $gbDiag.Text = "Offline Analysis"
    $gbDiag.Location = New-Object System.Drawing.Point(0, 594)
    $gbDiag.Size = New-Object System.Drawing.Size(435, 95)
    $tabDisk.Controls.Add($gbDiag)

    $lblDiagInfo = New-Object System.Windows.Forms.Label
    $lblDiagInfo.Text = "Disk must already be ONLINE with a drive letter (below). Same letter is used by Evidence and Toolbox for a secondary disk."
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

    # ---- Tab: Evidence ----
    # Category-based evidence collection (see EZfix-CategoryScoping.ps1) -
    # "This PC" for the live machine, "Secondary Disk" for whatever's
    # mounted and given a drive letter in the Disk Investigation tab.
    # Kept together, out of Section 1: this is scoping data for whoever
    # picks up the investigation, not a self-service fix, and "any
    # relevant information matters" here, so nothing is trimmed back
    # the way it is for the front screen.
    $gbEvidenceHere = New-Object System.Windows.Forms.GroupBox
    $gbEvidenceHere.Text = 'This PC'
    $gbEvidenceHere.SetBounds(0, 8, 435, 70)
    $tabEvidence.Controls.Add($gbEvidenceHere)

    $lblEvidence = New-Object System.Windows.Forms.Label
    $lblEvidence.Text = "Evidence:"
    $lblEvidence.Location = New-Object System.Drawing.Point(10, 25)
    $lblEvidence.Size = New-Object System.Drawing.Size(60, 24)
    $gbEvidenceHere.Controls.Add($lblEvidence)

    $cmbCategory = New-Object System.Windows.Forms.ComboBox
    $cmbCategory.Location = New-Object System.Drawing.Point(75, 22)
    $cmbCategory.Size = New-Object System.Drawing.Size(150, 24)
    $cmbCategory.DropDownStyle = 'DropDownList'
    [void]$cmbCategory.Items.AddRange(@('Network', 'Auth', 'App', 'OS', 'Other'))
    $cmbCategory.SelectedIndex = 0
    $gbEvidenceHere.Controls.Add($cmbCategory)

    $btnCollectEvidence = New-EZfixQuickButton -Text "Collect Evidence" -X 235 -Y 21 -Width 190
    $gbEvidenceHere.Controls.Add($btnCollectEvidence)

    $gbDiskEvidence = New-Object System.Windows.Forms.GroupBox
    $gbDiskEvidence.Text = 'Secondary Disk'
    $gbDiskEvidence.SetBounds(0, 86, 435, 100)
    $tabEvidence.Controls.Add($gbDiskEvidence)
    $lblDiskEvidence = New-Object System.Windows.Forms.Label
    $lblDiskEvidence.Text = 'Uses the Windows drive letter entered in Disk Investigation > Offline Analysis.'
    $lblDiskEvidence.SetBounds(10,20,410,32)
    $gbDiskEvidence.Controls.Add($lblDiskEvidence)
    $cmbDiskCategory = New-Object System.Windows.Forms.ComboBox
    $cmbDiskCategory.DropDownStyle = 'DropDownList'
    $cmbDiskCategory.SetBounds(10,58,150,24)
    [void]$cmbDiskCategory.Items.AddRange(@('Network','Auth','App','OS','Other'))
    $cmbDiskCategory.SelectedIndex = 0
    $gbDiskEvidence.Controls.Add($cmbDiskCategory)
    $btnDiskEvidence = New-EZfixQuickButton -Text 'Collect Disk Evidence' -X 170 -Y 55 -Width 250
    $gbDiskEvidence.Controls.Add($btnDiskEvidence)

    # ---- Tab: More (the Toolbox) ----
    # A submenu inside Advanced for handy tool cards - not much text,
    # link-rich: what a tool's for, easy setup, a couple of commands to
    # try, and a link to its own official docs for anything deeper (see
    # EZfix-Toolbox.ps1). Picked by category, same idea as Evidence
    # above. Only Network is built out today; picking any other category
    # just says so (Show-EZfixToolCard handles that gracefully).
    $lblToolboxInfo = New-Object System.Windows.Forms.Label
    $lblToolboxInfo.Text = "Quick-reference cards for tools worth reaching for during an investigation - what each is for, easy setup, and a few commands to start with. Deeper material is each tool's own official docs, linked from its card."
    $lblToolboxInfo.SetBounds(0, 8, 435, 46)
    $lblToolboxInfo.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblToolboxInfo.ForeColor = [System.Drawing.Color]::DimGray
    $tabMore.Controls.Add($lblToolboxInfo)

    $lblToolboxCategory = New-Object System.Windows.Forms.Label
    $lblToolboxCategory.Text = 'Category:'
    $lblToolboxCategory.Location = New-Object System.Drawing.Point(0, 62)
    $lblToolboxCategory.Size = New-Object System.Drawing.Size(65, 24)
    $tabMore.Controls.Add($lblToolboxCategory)

    $cmbToolboxCategory = New-Object System.Windows.Forms.ComboBox
    $cmbToolboxCategory.Location = New-Object System.Drawing.Point(70, 59)
    $cmbToolboxCategory.Size = New-Object System.Drawing.Size(150, 24)
    $cmbToolboxCategory.DropDownStyle = 'DropDownList'
    [void]$cmbToolboxCategory.Items.AddRange(@('Network', 'Auth', 'App', 'OS', 'Other'))
    $cmbToolboxCategory.SelectedIndex = 0
    $tabMore.Controls.Add($cmbToolboxCategory)

    $btnToolbox = New-EZfixQuickButton -Text "Open Toolbox" -X 230 -Y 58 -Width 195
    $tabMore.Controls.Add($btnToolbox)

    $lblPwshInfo = New-Object System.Windows.Forms.Label
    $lblPwshInfo.Text = "Opens a new elevated PowerShell window with every EZfix module already loaded, so any function - not just what's wired to a button here - can be called directly."
    $lblPwshInfo.SetBounds(0, 96, 435, 34)
    $lblPwshInfo.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblPwshInfo.ForeColor = [System.Drawing.Color]::DimGray
    $tabMore.Controls.Add($lblPwshInfo)

    $btnPwshConsole = New-EZfixQuickButton -Text "Open PowerShell (EZfix Loaded)" -X 0 -Y 134 -Width 435
    $tabMore.Controls.Add($btnPwshConsole)

    # ============================================================
    # Log - shared by both sections, also written to the session log file.
    # Its Y position moves depending on whether "Advanced" is expanded -
    # Update-EZfixLayout (defined further below, called at the end)
    # positions it and resizes the window. $btnToggleLog lets the Log
    # box itself be collapsed independently of "Advanced" or of resizing
    # the window - same idea as $btnToggleAdvanced, just for this box.
    # ============================================================
    $lblLog = New-Object System.Windows.Forms.Label
    $lblLog.Text = "Log:"
    $lblLog.Size = New-Object System.Drawing.Size(300, 20)
    $form.Controls.Add($lblLog)

    $btnToggleLog = New-Object System.Windows.Forms.Button
    $btnToggleLog.Text = 'Hide'
    $btnToggleLog.Size = New-Object System.Drawing.Size(80, 20)
    $btnToggleLog.Tag = $true
    $form.Controls.Add($btnToggleLog)

    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Size = New-Object System.Drawing.Size(455, 150)
    $txtLog.Multiline = $true
    $txtLog.ScrollBars = 'Vertical'
    $txtLog.WordWrap = $true
    $txtLog.ReadOnly = $true
    $txtLog.Font = New-Object System.Drawing.Font("Consolas", 8.5)
    $form.Controls.Add($txtLog)

    $reportState = @{ Path = $null }
    $btnReport = New-Object System.Windows.Forms.Button
    $btnReport.Text = 'Open Last Report'
    $btnReport.Size = [Drawing.Size]::new(155,28)
    $btnReport.Enabled = $false
    $btnReport.Add_Click({ if ($reportState.Path) { Start-Process notepad.exe -ArgumentList ('"' + $reportState.Path + '"') } })
    $form.Controls.Add($btnReport)
    $diskTips.SetToolTip($btnVhdDetach,'Disconnect the virtual disk. The image file will not be deleted.')
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Size = New-Object System.Drawing.Size(85, 28)
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)

    function Resize-EZfixAdvancedPanel {
        if ($form.WindowState -eq 'Minimized') { return }
        $width = [Math]::Max(455, $form.ClientSize.Width - 30)
        $gbQuick.Width = $width
        $buttonWidth = [int](($width - 40) / 3)
        $btnNetwork.SetBounds(10,25,$buttonWidth,30)
        $btnPerformance.SetBounds((20 + $buttonWidth),25,$buttonWidth,30)
        $btnCleanup.SetBounds((30 + 2 * $buttonWidth),25,$buttonWidth,30)
        $btnRDP.SetBounds(10,62,$buttonWidth,38)
        $btnOverview.SetBounds((20 + $buttonWidth),65,$buttonWidth,30)
        $btnRecentErrors.SetBounds((30 + 2 * $buttonWidth),65,$buttonWidth,30)
        $btnToggleAdvanced.Width = $width
        $pnlAdvanced.Width = $width
        $tabsAdvanced.Width = $pnlAdvanced.ClientSize.Width

        $innerWidth = [Math]::Max(300, $tabsAdvanced.ClientSize.Width - 20)

        # -- Disk Investigation tab --
        $btnVhdOpen.SetBounds(160,8,($innerWidth - 160),30)
        $findWidth = [int]($innerWidth * 0.55)
        $btnVhdFind.SetBounds(0,46,$findWidth,30)
        $btnVhdDetach.SetBounds(($findWidth + 10),46,($innerWidth - $findWidth - 10),30)
        $lblVhd.Width = $innerWidth
        foreach ($group in @($gbDisks,$gbPartitions,$gbState,$gbDiag)) { $group.Width = $innerWidth }
        $pnlDiskList.Width = $gbDisks.Width - 10
        foreach ($labels in $diskLabels) {
            $labels.Name.Width=$pnlDiskList.Width - 55
            $labels.Details.Width=$pnlDiskList.Width - 120
        }
        $txtPartitions.Width = $gbPartitions.Width - 20

        # -- Evidence tab --
        $gbEvidenceHere.Width = $innerWidth
        $btnCollectEvidence.Width = $gbEvidenceHere.Width - $btnCollectEvidence.Left - 10
        $gbDiskEvidence.Width = $innerWidth
        $lblDiskEvidence.Width = $gbDiskEvidence.Width - 20
        $btnDiskEvidence.Width = $gbDiskEvidence.Width - $btnDiskEvidence.Left - 10

        # -- More tab (Toolbox) --
        $lblToolboxInfo.Width = $innerWidth
        $btnToolbox.Width = $innerWidth - $btnToolbox.Left
        $lblPwshInfo.Width = $innerWidth
        $btnPwshConsole.Width = $innerWidth

        $logY = $btnToggleAdvanced.Bottom + 8
        if ($btnToggleAdvanced.Tag -eq $true) {
            # "Advanced" can now claim most of the window - the Log box
            # below no longer needs half the space reserved for it
            # since it can be collapsed to a single bar with
            # $btnToggleLog when you need the room. $splitState.AdvancedOverride
            # is set instead of the 0.7 default once the user has
            # dragged $splitterAdvLog at least once - re-clamped here
            # every layout pass so a later window resize can't leave it
            # oversized or the Log box with no room at all.
            $available = [Math]::Max(300, $form.ClientSize.Height - $pnlAdvanced.Top - 80)
            if ($null -ne $splitState.AdvancedOverride) {
                $pnlAdvanced.Height = [Math]::Min($available, [Math]::Max(220, $splitState.AdvancedOverride))
            }
            else {
                $pnlAdvanced.Height = [Math]::Max(220, [int]($available * 0.7))
            }
            $tabsAdvanced.Height = $pnlAdvanced.ClientSize.Height
            $splitterAdvLog.Visible = $true
            $splitterAdvLog.SetBounds($pnlAdvanced.Left, ($pnlAdvanced.Bottom + 2), $pnlAdvanced.Width, 6)
            $logY = $splitterAdvLog.Bottom + 6
        }
        else {
            $splitterAdvLog.Visible = $false
        }
        $lblLog.SetBounds(15,$logY,($width - 95),20)
        $btnToggleLog.Location = [Drawing.Point]::new((15 + $width - 85),$logY)
        $logExpanded = [bool]$btnToggleLog.Tag
        $txtLog.Visible = $logExpanded
        if ($logExpanded) {
            $txtLog.SetBounds(15,($logY + 20),$width,[Math]::Max(100,$form.ClientSize.Height - $logY - 73))
            $bottomAnchor = $txtLog.Bottom + 10
        } else {
            $bottomAnchor = $lblLog.Bottom + 10
        }
        $btnReport.Location = [Drawing.Point]::new(15,$bottomAnchor)
        $btnClose.Location = [Drawing.Point]::new(($form.ClientSize.Width - 100),$bottomAnchor)

        # General safety net for the same AutoScroll-offset issue fixed
        # above on disk selection: any full layout pass re-asserts every
        # control's correct position, so any stray scroll offset picked
        # up since the last pass (window resize, tab switch, focus
        # change) is worth clearing here too, not just on that one
        # specific trigger.
        foreach ($tab in @($tabDisk, $tabEvidence, $tabMore)) {
            $tab.AutoScrollPosition = [Drawing.Point]::new(0, 0)
        }
    }

    function Update-EZfixLayout {
        param([bool]$AdvancedExpanded)
        $btnToggleAdvanced.Tag = $AdvancedExpanded
        $pnlAdvanced.Visible = $AdvancedExpanded
        $btnToggleAdvanced.Text = 'Advanced'
        Resize-EZfixAdvancedPanel
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
        param([Parameter(Mandatory)][string]$Label,[Parameter(Mandatory)][scriptblock]$Action,[switch]$ShowPopup)
        Add-EZfixLogLine "=== $Label ==="
        $hadError=$false; $hadWarning=$false; $writer=$null; $shown=0; $lines=0
        $reportPath=$null
        [Windows.Forms.Cursor]::Current=[Windows.Forms.Cursors]::WaitCursor
        try {
            $safeLabel = ($Label -replace '[^A-Za-z0-9]+','-').Trim('-')
            $reportPath=Join-Path (New-EZfixReportFolder) ("{0}_{1}.txt" -f $safeLabel,(Get-Date -Format 'HHmmss_fff'))
            $writer=[IO.StreamWriter]::new($reportPath,$false,[Text.UTF8Encoding]::new($false))
            $writer.AutoFlush=$true
            $writer.WriteLine("EZfix | $Label | $(Get-Date -Format o) | $env:COMPUTERNAME")
            & $Action *>&1 | ForEach-Object {
                if ($_ -is [Management.Automation.ErrorRecord]) { $hadError=$true }
                if ($_ -is [Management.Automation.WarningRecord]) { $hadWarning=$true }
                $_
            } | Out-String -Stream -Width 4096 | ForEach-Object {
                $writer.WriteLine($_); $lines++
                if ($shown -lt 25) {
                    $preview=if ($_.Length -gt 240) { $_.Substring(0,240)+' ... [see report]' } else { $_ }
                    Add-EZfixLogLine $preview; $shown++
                }
            }
        } catch {
            $hadError=$true
            if ($writer) { $writer.WriteLine("ERROR: $($_.Exception.Message)") }
            Add-EZfixLogLine ("ERROR: " + $_.Exception.Message)
        } finally {
            if ($writer) { $writer.Dispose(); $reportState.Path=$reportPath; $btnReport.Enabled=$true }
            [Windows.Forms.Cursor]::Current=[Windows.Forms.Cursors]::Default
        }
        if ($lines -gt $shown) { Add-EZfixLogLine "Showing $shown of $lines lines. Full details are in the report." }
        $status=if($hadError){'finished with errors'}elseif($hadWarning){'finished with warnings; results may be incomplete'}else{'finished'}
        Add-EZfixLogLine "--- $Label $status ---"
        if ($reportPath -and (Test-Path -LiteralPath $reportPath)) { Add-EZfixLogLine "Report: $reportPath" }
        if ($ShowPopup) {
            $icon=if($hadError){'Error'}elseif($hadWarning){'Warning'}else{'Information'}
            [Windows.Forms.MessageBox]::Show("$Label $status. Use Open Last Report for full details.",'EZfix','OK',$icon) | Out-Null
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
            "This will delete eligible temporary files older than 7 days and empty the Recycle Bin. PowerShell runtime files are excluded. Continue?",
            "Confirm cleanup", 'YesNo', 'Warning'
        )
        if ($confirm -ne 'Yes') {
            Add-EZfixLogLine "Cleanup canceled (not confirmed)."
            return
        }
        Invoke-EZfixAction -Label "Cleanup" -Action { Start-EZfixCleanup -Confirm:$false 6>&1 } -ShowPopup
    })

    $btnRDP.Add_Click({
        Invoke-EZfixAction -Label "Connectivity & Security" -Action { Start-EZfixConnectivity 6>&1 } -ShowPopup
    })

    $btnOverview.Add_Click({
        Invoke-EZfixAction -Label 'System Overview (this PC)' -Action { Start-EZfixSystemOverview 6>&1 } -ShowPopup
    })
    $btnRecentErrors.Add_Click({
        Invoke-EZfixAction -Label 'Recent Errors (this PC, last 24 hours)' -Action { Start-EZfixRecentErrors 6>&1 } -ShowPopup
    })
    # ============================================================
    # SECTION 2 - events ("Advanced" panel)
    # Evidence collection still pops up a "done" dialog like Section 1 -
    # it runs to completion and reports a result the same way. Disk
    # state changes and Offline Analysis don't (see header comment).
    # ============================================================
    $btnCollectEvidence.Add_Click({
        if (-not $cmbCategory.SelectedItem) { return }
        $category = $cmbCategory.SelectedItem.ToString()
        Invoke-EZfixAction -Label "Evidence collection ($category, this PC)" -Action {
            Start-EZfixCategoryScoping -Category $category 6>&1
        } -ShowPopup
    })
    $btnToolbox.Add_Click({
        if (-not $cmbToolboxCategory.SelectedItem) { return }
        Show-EZfixToolCard -Owner $form -Category $cmbToolboxCategory.SelectedItem.ToString()
    })
    $btnPwshConsole.Add_Click({
        # Reuses $ezfixDependencies (defined at the top of this file) as
        # the single source of truth for "what counts as an EZfix
        # module" - one list, used both to load this GUI and to load a
        # manual console, so the two can never drift apart. Network-
        # Diagnostics.ps1 is deliberately excluded, same reason it's
        # excluded from $ezfixDependencies itself: it's a top-level
        # script, not a set of functions, so dot-sourcing it would run
        # the whole diagnostic immediately instead of just loading it.
        $moduleFiles = $ezfixDependencies.Values | Select-Object -Unique
        $dotSource = ($moduleFiles | ForEach-Object { ". '$(Join-Path $PSScriptRoot $_)'" }) -join '; '
        $welcome = "EZfix modules loaded from this folder - functions are ready to call directly. Network-Diagnostics.ps1 is a script, not a function: run it with .\Network-Diagnostics.ps1 when you need it."
        $command = "Set-Location -LiteralPath '$PSScriptRoot'; $dotSource; Write-Host '$welcome' -ForegroundColor Cyan"
        try {
            # No -Verb RunAs: this GUI already requires admin (#Requires
            # -RunAsAdministrator at the top), so the child process
            # inherits that elevation automatically - adding RunAs here
            # would just trigger a second, redundant UAC prompt.
            Start-Process -FilePath 'pwsh' -ArgumentList @('-NoExit', '-Command', $command) -ErrorAction Stop
            Add-EZfixLogLine "Opened an elevated PowerShell session with EZfix modules loaded."
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Could not open PowerShell: $($_.Exception.Message)", 'EZfix', 'OK', 'Error') | Out-Null
        }
    })
    $btnDiskEvidence.Add_Click({
        if (-not $cmbDiskCategory.SelectedItem) { return }
        $category = $cmbDiskCategory.SelectedItem.ToString()
        $letter = $txtLetter.Text.Trim()
        if ($letter -notmatch '^[A-Za-z]$') {
            [System.Windows.Forms.MessageBox]::Show("Enter a valid drive letter in Disk Investigation > Offline Analysis first (e.g. D). If the disk has no letter yet, bring it ONLINE there - that assigns one automatically.", "EZfix", 'OK', 'Warning') | Out-Null
            return
        }
        Invoke-EZfixAction -Label "Evidence collection ($category, secondary disk ${letter}:)" -Action {
            $evtxRoot = Get-EZfixSecondaryEventPath -DriveLetter $letter
            Start-EZfixCategoryScoping -Category $category -EvtxRoot $evtxRoot 6>&1
        } -ShowPopup
    })
    function Open-EZfixSelectedVhd([string]$ImagePath) {
        if (-not $ImagePath) { return }
        if ($vhdState.Path) {
            [Windows.Forms.MessageBox]::Show('Detach the current image before opening another one here.', 'EZfix', 'OK', 'Information') | Out-Null
            return
        }
        $confirm = [Windows.Forms.MessageBox]::Show("Attach this image read-only? It will appear as a disk in Windows. No virtual machine will be started.`r`n`r`n$ImagePath", 'Open VHD/VHDX', 'YesNo', 'Question')
        if ($confirm -ne 'Yes') { return }
        try {
            $opened=Open-EZfixVhd -ImagePath $ImagePath -Confirm:$false
            $vhdState.Path=$opened.ImagePath; $vhdState.DiskNumber=$opened.DiskNumber
            $lblVhd.Text="Read-only image: $($opened.ImagePath) | Disk $($opened.DiskNumber)"
            $btnVhdDetach.Enabled=$true
            $txtLetter.Text=[string]$opened.WindowsDriveLetter
            Add-EZfixLogLine "Attached read-only: $($opened.ImagePath). Disk $($opened.DiskNumber). Volume letters: $($opened.DriveLetters)."
            $btnDetect.PerformClick()
            $pnlDiskList.Width = $gbDisks.Width - 10
        foreach ($radio in $diskRadios) { if ($radio.Tag -eq $opened.DiskNumber) { $radio.Checked=$true; $pnlDiskList.ScrollControlIntoView($radio) } }
            if (-not $opened.WindowsDriveLetter) { Add-EZfixLogLine 'No single mounted Windows volume was identified. Check the partitions and drive letter before analysis.' }
        } catch {
            Add-EZfixLogLine "VHD open failed: $($_.Exception.Message)"
            [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Could not open VHD/VHDX','OK','Error') | Out-Null
        }
    }
    $btnVhdOpen.Add_Click({
        $picker=[Windows.Forms.OpenFileDialog]::new()
        $picker.Filter='Virtual hard disks (*.vhd;*.vhdx)|*.vhd;*.vhdx'
        $picker.Title='Select a VHD/VHDX to attach read-only'
        try { if ($picker.ShowDialog($form) -eq 'OK') { Open-EZfixSelectedVhd $picker.FileName } } finally { $picker.Dispose() }
    })
    $btnVhdFind.Add_Click({ Open-EZfixSelectedVhd (Show-EZfixVhdFinder -Owner $form) })
    $btnVhdDetach.Add_Click({
        if (-not $vhdState.Path) { return }
        $confirm=[Windows.Forms.MessageBox]::Show("Detach this image? Close files opened from it first. The VHD/VHDX file will be kept.`r`n`r`n$($vhdState.Path)", 'Detach VHD/VHDX','YesNo','Question')
        if ($confirm -ne 'Yes') { return }
        try {
            Close-EZfixVhd -ImagePath $vhdState.Path -Confirm:$false
            Add-EZfixLogLine "Detached: $($vhdState.Path)"
            $vhdState.Path=$null; $vhdState.DiskNumber=$null
            $lblVhd.Text='VHD/VHDX detached. The image file was kept.'
            $txtLetter.Clear(); $btnVhdDetach.Enabled=$false
            $btnDetect.PerformClick()
        } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Could not detach image','OK','Error') | Out-Null }
    })
    $form.Add_FormClosing({
        if ($vhdState.Path) {
            $answer=[Windows.Forms.MessageBox]::Show('A read-only VHD/VHDX is still attached. Close EZfix and leave it attached? Choose No to return and use Detach VHD.', 'EZfix', 'YesNo', 'Question')
            if ($answer -ne 'Yes') { $_.Cancel=$true }
        }
    })
    $btnToggleAdvanced.Add_Click({
        Update-EZfixLayout -AdvancedExpanded:(-not [bool]$btnToggleAdvanced.Tag)
    })

    $btnToggleLog.Add_Click({
        $expanded = -not [bool]$btnToggleLog.Tag
        $btnToggleLog.Tag = $expanded
        $btnToggleLog.Text = if ($expanded) { 'Hide' } else { 'Show' }
        Resize-EZfixAdvancedPanel
    })

    $btnDetect.Add_Click({
        $protectedDisks.Clear()
        $btnApply.Enabled=$false; $rbOnline.Enabled=$false; $rbOffline.Enabled=$false
        foreach ($rb in $diskRadios) {
            $rb.Visible = $false
            $rb.Checked = $false
            $rb.Tag = $null
            $rb.Font = $gbDisks.Font
        }
        foreach ($labels in $diskLabels) { $labels.Name.Visible=$false; $labels.State.Visible=$false; $labels.Details.Visible=$false }
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

        $disksToShow = @($inventory.Disks)

        while ($diskRadios.Count -lt $disksToShow.Count) { Add-EZfixDiskRadio }
        for ($i = 0; $i -lt $disksToShow.Count; $i++) {
            $disk = $disksToShow[$i]
            $sizeGB = [math]::Round($disk.Size / 1GB, 1)
            $isOSDisk = $disk.Number -eq $inventory.OSDiskNumber
            $statusText = if ($isOSDisk) { "ONLINE - SYSTEM DISK, LOCKED" } else { ($disk.OperationalStatus -join ', ').ToUpper() }

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
            $rb.Text = ''
            $rb.Tag = $disk.Number
            $rb.Visible = $true
            $isOSDisk = $isOSDisk -or $disk.IsBoot -or $disk.IsSystem
            if($isOSDisk){[void]$protectedDisks.Add([int]$disk.Number)}
            $rb.Enabled = $true
            $isVhd = ([string]$disk.BusType -match '^(15|File.?Backed.?Virtual)$') -or ($null -ne $vhdState.DiskNumber -and $disk.Number -eq $vhdState.DiskNumber)
            $stateText = if ($disk.IsOffline) { 'Offline' } else { 'Online' }
            $stateColor = if ($disk.IsOffline) { [Drawing.Color]::Red } else { [Drawing.Color]::Green }
            $identityColor = if ($isOSDisk) { [Drawing.Color]::Black } elseif ($isVhd) { [Drawing.Color]::Blue } else { $stateColor }
            $labels=$diskLabels[$i]
            $kind = if ($isOSDisk) { 'SYSTEM DISK - INSPECT ONLY' } elseif ($isVhd) { 'VHD/VHDX' } else { 'Data disk' }
            $labels.Name.Text="[$($disk.Number)] $($disk.FriendlyName) - $sizeGB GB - $kind"
            $labels.Name.ForeColor=$identityColor
            $labels.Name.Font=if ($isOSDisk) { [Drawing.Font]::new($gbDisks.Font,[Drawing.FontStyle]::Bold) } else { $gbDisks.Font }
            $labels.State.Text=$stateText
            $labels.State.ForeColor=if ($isOSDisk) { [Drawing.Color]::Black } else { $stateColor }
            $labels.Details.Text="$driveLetters$(if ($disk.IsReadOnly) { ' | Read-only' })"
            $labels.Details.ForeColor=$identityColor
            $diskTips.SetToolTip($labels.Name,$labels.Name.Text)
            $diskTips.SetToolTip($labels.Details,$labels.Details.Text)
            $labels.Name.Visible=$true; $labels.State.Visible=$true; $labels.Details.Visible=$true
        }
        Resize-EZfixAdvancedPanel
        Add-EZfixLogLine "Disks detected. System disk: $($inventory.OSDiskNumber) (inspect only; state changes blocked)."
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
        try {
            $currentDisk=Get-Disk -Number $diskNumber -ErrorAction Stop
            if($currentDisk.IsBoot -or $currentDisk.IsSystem -or $diskNumber -eq (Get-OSDiskNumber)) {
                Add-EZfixLogLine 'Blocked: the running system/boot disk can be inspected, but its state cannot be changed.'
                return
            }
        } catch {Add-EZfixLogLine "Disk safety check failed: $($_.Exception.Message)"; return}
        $targetState = if ($rbOnline.Checked) { 'Online' } else { 'Offline' }

        # Explicit GUI confirmation - same spirit as Set-DataDiskState's
        # console -Confirm, just as a dialog box. That's why the function
        # is called with -Confirm:$false afterwards: confirmation already
        # happened here, no need to ask twice.
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "This will set disk $diskNumber to $($targetState.ToUpper()) state. Going online may also assign a drive letter. If this is the wrong disk, it could affect its data. Continue?",
            "Confirm state change", 'YesNo', 'Warning'
        )
        if ($confirm -ne 'Yes') {
            Add-EZfixLogLine "State change canceled (not confirmed)."
            return
        }

        Invoke-EZfixAction -Label "State change (disk $diskNumber to $targetState)" -Action {
            Set-DataDiskState -DiskNumber $diskNumber -TargetState $targetState -Confirm:$false 6>&1
        }

        if ($targetState -eq 'Online' -and -not (Get-Disk -Number $diskNumber -ErrorAction Stop).IsOffline) {
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

        # The confirmation MessageBox earlier in this handler pops up
        # over an already-scrolled-down tab (Apply State Change sits at
        # Y 556) and reliably corrupts its scroll state on close.
        # Resetting AutoScrollPosition afterward didn't stick, and
        # neither did switching tabs away and back - that's too light a
        # touch, since the TabControl itself stays visible throughout.
        # What's confirmed, by hand, twice, to actually work: collapsing
        # "Advanced" and re-expanding it. That's a heavier reset - it
        # hides and re-shows the whole panel, forcing everything inside
        # it to be laid out completely fresh - so automate exactly that
        # instead of a smaller step that doesn't reproduce the same fix.
        Update-EZfixLayout -AdvancedExpanded:$false
        Update-EZfixLayout -AdvancedExpanded:$true
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

    $form.Add_Resize({ Resize-EZfixAdvancedPanel })

    # Start collapsed - "Advanced" is opt-in, not the default view.
    Update-EZfixLayout -AdvancedExpanded:$false

    [void]$form.ShowDialog()
}

<#
    USAGE (PowerShell 7 / pwsh, running as Administrator):
        . .\EZfix-Interface.ps1
        Start-EZfixInterface

    The other EZfix files (Common, Disk-Selector, OfflineAnalysis,
    Performance, Cleanup, RDP, SystemTools, CategoryScoping,
    Network-Diagnostics, Toolbox) must be saved in the same folder -
    this script loads them itself if needed.

    Every action's output is logged to Desktop\EZfix\sessions\ as well
    as shown on screen. Section 1 (Quick Fixes) and Evidence collection
    (under Advanced) pop up a confirmation dialog when they finish; disk
    state changes and Offline Analysis (also under Advanced) do not -
    see the header comment for why.
#>
