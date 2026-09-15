EZfix

Windows diagnostics and evidence collection, in one graphical workspace.

Download and run
Download EZfix v1.0.0 for Windows

Release notes and downloads

Download EZfix-v1.0.0.zip above.
Right-click the ZIP, choose Extract All, and save the folder somewhere permanent, such as Documents.
Open the extracted folder and double-click Launch-EZfix.bat.
Approve the administrator prompt if you trust the download. If PowerShell 7 is missing, EZfix offers to install it from Microsoft.

Next time, use the EZfix shortcut on your Desktop. It is created automatically on first launch. No coding, editor or manual commands are needed.

EZfix is portable: keep its files together and do not run it inside the ZIP. If you move the folder, run Launch-EZfix.bat again to update the shortcut. An unrelated shortcut named EZfix is preserved. Desktop restrictions may prevent shortcut creation; the launcher still works.

For everyday use, choose the named EZfix ZIP from Releases above - it is a tested, versioned build.

Testing changes that haven't been released yet? The Releases ZIP is a fixed snapshot from whenever that version was tagged - it does not update when new commits land on main, so re-downloading it will keep giving you the same old build. Instead, use GitHub's own Code → Download ZIP button on the repository's main page (or git pull if you already have it cloned), extract that into its own folder, and run Launch-EZfix.bat the same way. Do this every time you want the current development code.

Tools
Tool	Useful for
System Overview	Windows version, uptime, CPU, RAM, GPU, BIOS and drive capacity.
Network	IP configuration, gateway, DNS and route checks; also clears DNS cache.
Performance	CPU/RAM, disk capacity/activity, process CPU time and RAM ranking, page file use.
Connectivity & Security	Network profiles, firewall, Defender, Secure Boot, TPM, listeners and RDP.
Recent Errors	Up to 50 newest System/Application Critical/Error events over 24 hours.
Cleanup	Confirmed removal of eligible temporary files older than seven days and emptying the Recycle Bin.

The resizable window wraps lines and shows brief previews. Open Last Report opens the full output. Reports are saved under Desktop/EZfix, separately for each run.

This front screen is self-service only: one click, one result, nothing to configure. Anything more technical - evidence collection, disk work, tool cheat sheets - lives under Advanced instead, described next.

Advanced

A collapsible panel below the Quick Fixes, for scoping an issue rather than fixing it in one click. Split into three tabs:

Disk Investigation - inspect disks and partitions, including the running Windows disk. The system disk is black and protected from online/offline changes. Data disk states are green for Online and red for Offline; changes require confirmation.

Find VHD/VHDX files across accessible local drives or select a file. Open one image read-only. Virtual disk identities are blue, with green/red status. Detach VHD/VHDX disconnects the virtual disk; the image file is not deleted. Only images opened by the current session can be detached here. VHD inspection requires no Hyper-V and does not start a virtual machine. Unmounted images appear in file search, rather than the attached disk list.

Offline analysis reads supported Windows version, registry, event logs and boot configuration from a secondary Windows disk, once it is brought Online with a drive letter here.

Evidence - category-based exports (Network, Auth, App, OS, Other) for investigation outside EZfix, for either this PC or a secondary disk mounted in Disk Investigation.

More - a quick-reference toolbox of handy tools by category (Network is the only category built out today): what each tool is for, easy setup, a couple of commands to try, and a link to its own official docs for anything deeper.

Requirements and behavior

Windows 10/11 desktop, administrator access and PowerShell 7. Internet is needed for prerequisite downloads and external checks. Windows edition, missing components or organization policy can limit individual features.

EZfix needs no installer. PowerShell 7 is a separate prerequisite installed only if you accept setup. The PowerShell window stays hidden; the initial BAT launch may flash briefly.

Network clears DNS without another confirmation. Connectivity & Security may start a stopped Remote Desktop service. Cleanup and disk state changes ask first. Offline analysis performs no repair, but is not forensic write-blocked acquisition: it uses a working registry copy and may temporarily assign an EFI drive letter.

Windows Home cannot host built-in Remote Desktop connections. GPU memory can be approximate or unavailable. Performance metrics are snapshots; cumulative CPU seconds are not current CPU percentage. Some checks pause the interface. Windows-generated messages retain the system language.

Reports, updates and removal

Reports and session logs are under Desktop/EZfix. A different administrator account uses its own Desktop for reports. Reports may contain names, addresses, paths and event details; review before sharing.

Update: close EZfix, extract the new version into a new permanent folder, then open its launcher to update the shortcut. Remove: close EZfix and delete its application folder and shortcut. Reports and PowerShell 7 remain separate.

An incomplete result does not mean no problems were found. Review warnings and reports. If Windows blocks execution, verify the source and follow your administrator's policy. A warning is not proof of safety. Setup errors identify the installation log folder; Microsoft's PowerShell download is https://aka.ms/PSWindows.

About

A PowerShell and Windows Forms IT support project focused on practical triage, readable results and evidence collection. Source is included for inspection.

MIT license. See LICENSE.
