![Platform](https://img.shields.io/badge/platform-Windows-0078D6)
![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-5391FE)
![License](https://img.shields.io/badge/license-MIT-green)

# EZfix

**EZfix** is a self-service troubleshooting and data-collection toolkit for Windows: a single graphical control panel that runs the everyday triage checks a support engineer performs many times a day, plus a safer, guided way to investigate a Windows machine that won't boot - all backed by plain PowerShell, with every action logged.

It was built to reflect how a real support engineer actually works: check the obvious
things fast, ask before doing anything risky, never guess when a system disk is on the
line, and leave a clear record of what happened.

## Why this exists

Most "IT toolkit" scripts fall into one of two traps: either they're a pile of
one-off `.ps1` files a technician has to remember the right flags for, or they're a
kitchen-sink "fix everything" tool that quietly changes things it shouldn't. EZfix takes
a narrower, more deliberate approach:

- **Nothing runs without knowing what it does.** Every button maps to a specific,
  documented check. There's no "Optimize My PC" black box.
- **State-changing actions always ask first**, using PowerShell's own confirmation
  pattern (`SupportsShouldProcess` / `-WhatIf` / `-Confirm`), surfaced as a plain
  Windows dialog so a non-scripting user still sees exactly what's about to happen.
- **A machine's live operating system disk can never be taken offline or have its boot
  files touched**, even by accident, even if a bad disk number gets passed in. This rule
  is enforced in code, not just described in a warning label.
- **Everything is logged.** Every session writes a timestamped log to the Desktop, so
  "what did I actually run 20 minutes ago" is always answerable.

## When to use it

EZfix covers two different situations that come up constantly in support work:

**The computer in front of you is acting up.** Slow network, high CPU/disk usage,
temp files piling up, Remote Desktop refusing connections, or a fresh machine that needs
its prerequisites checked - the **Quick Fixes** section handles these in one click each,
with the result immediately visible in the log and a pop-up confirmation.

**A machine won't boot, and you need to look at its disk without booting it.**
Connect the failing drive as a secondary/data disk to a healthy Windows machine (internal
SATA bay, USB dock/enclosure, or a VM's virtual disk), and use the **Advanced** section to
safely bring it online, inspect its partitions, and read its logs, registry, and boot
configuration - all read-only, with the drive that machine actually boots from
permanently locked out of the disk list.

## Features

**Quick Fixes** (always run against the current machine):
- **Network** - IP configuration, gateway reachability, DNS resolution/flush, and a
  route trace to the internet, cross-platform under PowerShell 7.
- **Performance** - a quick CPU/memory/disk snapshot.
- **Cleanup** - clears user and system temp files and empties the Recycle Bin, with an
  explicit confirmation before anything is deleted.
- **RDP** - checks the Remote Desktop service, firewall rule, and registry setting that
  most commonly block incoming RDP connections.
- **Setup** - checks (and can install) EZfix's own prerequisites: PowerShell 7, required
  Windows modules, and networking tools.
- **Evidence collection** - five focused categories (**Network / Auth / App / OS /
  Other**) that each pull exactly the log entries and system data relevant to that kind
  of problem, instead of one undifferentiated dump of every log on the system.

**Advanced - disk analysis** (for a disk connected as data, not the machine's own):
- **Detect Disks** - lists every disk on the machine, auto-identifies which one is the
  live system disk, and locks it out of selection.
- **Online/Offline** - brings a disk online or takes it offline, with an explicit
  confirmation dialog and an automatic drive-letter assignment once it's online.
- **Partition breakdown** - shows every partition on the selected disk (type, size,
  drive letter), since a disk can hold several partitions even though Online/Offline is
  a whole-disk action.
- **Offline Analysis** - a read-only report covering OS version/build, installed
  updates, key services, and boot configuration (including modern UEFI/GPT disks, not
  just legacy BIOS/MBR), read directly from the mounted drive.
- The same category-based evidence collection above can also target this mounted disk's
  event logs instead of the live machine's, via the **Target mounted disk** option.

## Screenshots

*(Add a few screenshots here once you've run it - the main Quick Fixes panel, the
expanded Advanced section with a disk detected, and a sample evidence-collection
report folder all make good ones.)*

## Requirements

- Windows 10/11
- PowerShell 7 (pwsh) - if it isn't installed, `Launch-EZfix.bat` installs it
  automatically
- Administrator privileges (EZfix needs these to inspect disks, services, and the
  registry, and will prompt Windows' standard elevation dialog for them)

## Getting started

### Just want to run it? (no PowerShell experience needed)

1. Click the green **Code** button on this repository, then **Download ZIP**.
2. Extract the ZIP somewhere convenient (right-click it → **Extract All**).
3. Open the extracted folder and double-click **`Launch-EZfix.bat`**.
4. Windows will show one or two security prompts the first time - see
   **Windows security warnings** below, this is expected.
5. The EZfix control panel opens. Click a button.

That's it - no need to open PowerShell, type any commands, or install anything by hand.

#### Windows security warnings

The first time you run `Launch-EZfix.bat`, Windows may show:

- **"Windows protected your PC" (SmartScreen)** - this appears for any downloaded
  script from a publisher Windows doesn't recognize yet, not because anything is
  wrong. Click **More info**, then **Run anyway**.
- **"Do you want to allow this app to make changes to your device?" (UAC)** - EZfix
  needs Administrator rights to check services, disks, and the registry. Click **Yes**.
  This may appear twice on a first run: once if PowerShell 7 needs to be installed, and
  once for EZfix itself.

### Running it from PowerShell directly (technical users)

```powershell
# From the folder containing all the EZfix files, in PowerShell 7 (pwsh),
# running as Administrator:
. .\EZfix-Interface.ps1
Start-EZfixInterface
```

Each module can also be dot-sourced and used on its own from the console - see the
`USAGE` block at the bottom of each `.ps1` file.

## Project structure

| File                            | Purpose                                                         |
|----------------------------------|------------------------------------------------------------------|
| `Launch-EZfix.bat`               | Double-click entry point; installs PowerShell 7 if needed        |
| `EZfix-Launcher.ps1`             | Elevates to Administrator, then opens the interface               |
| `EZfix-Interface.ps1`            | The Windows Forms GUI - Quick Fixes + Advanced disk analysis      |
| `EZfix-Common.ps1`               | Shared helpers (e.g. report folder creation)                      |
| `Disk-Selector.ps1`              | Disk detection, online/offline state changes, safety lockout      |
| `EZfix-OfflineAnalysis.ps1`      | Read-only analysis of