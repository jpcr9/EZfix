#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
#Requires -RunAsAdministrator
<#
    Tests for Disk-Selector.ps1 - specifically Set-DataDiskState, the one
    function in EZfix that can take a disk offline. Everything here is
    mocked: no real disk is ever touched, on purpose.
 
    Requires an elevated pwsh window, same as the app itself - the script
    under test has #Requires -RunAsAdministrator at the top, and that
    check still runs even just dot-sourcing it for these tests.
 
    Run with:
        Import-Module Pester -MinimumVersion 5.0 -Force
        Invoke-Pester -Path .\tests\Disk-Selector.Tests.ps1 -Output Detailed
#>
 
BeforeAll {
    . "$PSScriptRoot\..\Disk-Selector.ps1"
 
    # A fake two-disk world: disk 0 is the system disk (mounted at
    # $env:SystemDrive), disk 1 is an ordinary data disk. Get-Disk,
    # Get-Partition and Set-Disk are all mocked so none of this ever
    # reaches a real disk.
    Mock -CommandName Get-Partition -MockWith {
        param($DriveLetter, $DiskNumber)
        if ($DriveLetter -and $DriveLetter -eq $env:SystemDrive.TrimEnd(':')) {
            return [pscustomobject]@{ DiskNumber = 0 }
        }
        # Called per-disk by Show-DiskInventory just to list drive
        # letters - returning nothing here means "no drive letter",
        # which is already handled as a normal case, not an error.
        return $null
    }
    Mock -CommandName Get-Disk -MockWith {
        @(
            [pscustomobject]@{ Number = 0; FriendlyName = 'System Disk'; Size = 500GB; OperationalStatus = 'Online'; IsBoot = $true;  IsSystem = $true }
            [pscustomobject]@{ Number = 1; FriendlyName = 'Data Disk';   Size = 1GB;   OperationalStatus = 'Online'; IsBoot = $false; IsSystem = $false }
        )
    }
    Mock -CommandName Set-Disk -MockWith { }
}
 
Describe 'Set-DataDiskState' {
 
    Context 'the system disk' {
        It 'is blocked and never reaches Set-Disk, even with -Confirm:$false' {
            Set-DataDiskState -DiskNumber 0 -TargetState Offline -Confirm:$false
            Should -Invoke -CommandName Set-Disk -Times 0
        }
    }
 
    Context 'a non-system disk' {
        It 'does not call Set-Disk under -WhatIf' {
            Set-DataDiskState -DiskNumber 1 -TargetState Offline -WhatIf
            Should -Invoke -CommandName Set-Disk -Times 0
        }
 
        It 'calls Set-Disk with the right disk and direction when explicitly confirmed' {
            Set-DataDiskState -DiskNumber 1 -TargetState Offline -Confirm:$false
            Should -Invoke -CommandName Set-Disk -Times 1 -ParameterFilter {
                $Number -eq 1 -and $IsOffline -eq $true
            }
        }
 
        It 'requests Online (not Offline) when TargetState is Online' {
            Set-DataDiskState -DiskNumber 1 -TargetState Online -Confirm:$false
            Should -Invoke -CommandName Set-Disk -Times 1 -ParameterFilter {
                $Number -eq 1 -and $IsOffline -eq $false
            }
        }
    }
 
    Context 'an unknown disk number' {
        It 'reports the error and never calls Set-Disk' {
            Set-DataDiskState -DiskNumber 99 -TargetState Offline -Confirm:$false
            Should -Invoke -CommandName Set-Disk -Times 0
        }
    }
}
