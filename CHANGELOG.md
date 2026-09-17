# v1.0.2

- Added BitLocker status and physical disk health (SMART/reliability) checks.
- Added a pending-restart check, firmware mode, and read-only firmware boot entries to System Overview.
- Added Last Known Good Configuration check and restore for an offline disk, in Disk Investigation.
- Added listing and removal of installed updates on an offline disk, for troubleshooting a KB-caused issue.
- Added an open-ended Performance + Logs Capture (Evidence tab), correlating CPU/memory/disk samples with logs from the same time window.
- Report folders are now named after the action that created them, instead of a bare timestamp.
- Fixed several scroll-position and duplicate-folder issues around Disk Investigation.
  

# v1.0.2

- Added BitLocker status and physical disk health (SMART/reliability) checks.
- Added a pending-restart check, firmware mode, and read-only firmware boot entries to System Overview.
- Added Last Known Good Configuration check and restore for an offline disk, in Disk Investigation.
- Added listing and removal of installed updates on an offline disk, for troubleshooting a KB-caused issue.
- Added an open-ended Performance + Logs Capture (Evidence tab), correlating CPU/memory/disk samples with logs from the same time window.
- Report folders are now named after the action that created them, instead of a bare timestamp.
- Fixed several scroll-position and duplicate-folder issues around Disk Investigation.


# v1.0.1

- Added Auth, App, OS and Other categories to the Toolbox, alongside the existing Network cards.
- Added an "Open PowerShell (EZfix Loaded)" button that opens an elevated console with every module already loaded.
- Added a draggable splitter between "Advanced" and the Log box so their split is adjustable, not fixed.
- Fixed a scroll-position bug on the Disk Investigation tab that could visually displace controls after a state change.

# v1.0.0

- First public release, incorporating the tested previews.
- Automatic Desktop shortcut on first launch; refreshed download and usage instructions.

# Preview 4

- Wrapped, bounded console previews and complete per-action reports with Open Last Report.
- Preserve PowerShell temporary runtime files during cleanup; query Defender through CIM.
- Added RAM process ranking, disk activity and page file metrics.
- Clarified Detach VHD/VHDX tooltip.

# EZfix v1.0.0 release preparation

## Preview 3

- GPU models, driver information, reported adapter memory, display mode, BIOS and RAM modules in System Overview.
- Connectivity & Security replaces the RDP button while retaining RDP functionality, including its existing service-start attempt.
- Added network profiles, IP/gateway/DNS, effective firewall status, Defender, Secure Boot/TPM and local TCP listeners.
- RDP uses the configured port and reports NLA and Windows Home hosting limitations.
- System disks are selectable for partition inspection; UI state controls and backend mutations remain blocked.
- Hardware/security provider failures are isolated and memory data sources are labelled.

## Preview 2

- Renamed sections to This PC: Diagnostics & Tools and Advanced: Secondary Disk Investigation.
- Replaced Setup with read-only System Overview and Recent Errors (last 24 hours).
- Integrated Windows component checks into startup; removed the unused Bootstrap file.
- Moved secondary disk evidence into its own section so This PC always targets the running computer.
- Added a cancellable VHD/VHDX search across local fixed/removable drives, with paths, sizes and coverage information.
- Added read-only attachment and explicit detachment using Windows Storage, without Hyper-V cmdlets.
- Removed the five-disk display limit.
- System disk text is black and locked; data disks are green/red; VHD identity is blue with a green/red Online/Offline label.
- Offline registry inspection uses a local working copy of SYSTEM and transaction logs, suitable for read-only source images.
- New behavior tested with synthetic data, filesystem fixtures and simulated disk APIs. Real VHD attachment and analysis remain pending.

## Earlier preparation

- Hidden PowerShell startup, graphical installation progress and startup errors.
- PowerShell installation fallback now downloads and executes the official installer.
- Fallback also runs when winget finishes without installing a usable PowerShell.
- Real window maximization and an output area that grows in both dimensions.
- Horizontal scrolling for long lines; Advanced keeps its own vertical scrolling.
- Formatted tables, warnings and error output preserved in the session log.
- English EZfix messages in Performance, Network, Cleanup and Setup.
- Disk 0 selection handling corrected; disk command errors propagate.
- Offline Analysis rejects the running Windows disk before hive or EFI access.
- BCD command exit codes are checked.
- RDP firewall and local administrator group lookup no longer depend on English display names.
- Separate folders for repeated evidence collections and offline reports.
- Obsolete generic Scoping module removed from the distribution.
- README completed and matched to actual behavior; original MIT license preserved.

Validation includes PowerShell parsing, off-screen layout checks, simulated output,
simulated disk safeguards, repeated evidence export, and simulated startup routes.
A clean-machine installation and live disk operations still need real environment testing.



