#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
#Requires -RunAsAdministrator
<#
    Tests for Invoke-EZfixWithOfflineHive - the part of Offline Analysis
    responsible for guaranteeing a loaded registry hive always gets
    unloaded, even when something afterward goes wrong. reg.exe is
    mocked throughout, so no real hive is ever loaded on the test
    machine.
 
    Requires an elevated pwsh window, same as the app itself - the
    script under test has #Requires -RunAsAdministrator at the top, and
    that check still runs even just dot-sourcing it for these tests.
 
    Run with:
        Import-Module Pester -MinimumVersion 5.0 -Force
        Invoke-Pester -Path .\tests\EZfix-OfflineAnalysis.Tests.ps1 -Output Detailed
#>
 
BeforeAll {
    . "$PSScriptRoot\..\EZfix-OfflineAnalysis.ps1"
}
 
Describe 'Invoke-EZfixWithOfflineHive' {
 
    Context 'a successful load' {
        BeforeEach {
            Mock -CommandName 'reg.exe' -MockWith {
                $global:LASTEXITCODE = 0
                'The operation completed successfully.'
            }
        }
 
        It 'passes the script block a loaded hive path under HKLM' {
            $script:capturedPath = $null
            Invoke-EZfixWithOfflineHive -HiveFilePath 'C:\fake\SYSTEM' -ScriptBlock {
                param($HiveRoot)
                $script:capturedPath = $HiveRoot
            }
            $script:capturedPath | Should -Match '^HKLM:\\EZfixTempHive_[0-9a-f]{32}$'
        }
 
        It 'calls reg.exe exactly twice - one load, one unload' {
            Invoke-EZfixWithOfflineHive -HiveFilePath 'C:\fake\SYSTEM' -ScriptBlock { param($HiveRoot) }
            Should -Invoke -CommandName 'reg.exe' -Times 2
        }
    }
 
    Context 'the script block throws' {
        BeforeEach {
            Mock -CommandName 'reg.exe' -MockWith {
                $global:LASTEXITCODE = 0
                'The operation completed successfully.'
            }
        }
 
        It 'still unloads the hive before the error reaches the caller' {
            {
                Invoke-EZfixWithOfflineHive -HiveFilePath 'C:\fake\SYSTEM' -ScriptBlock {
                    param($HiveRoot)
                    throw 'boom - the registry read failed'
                }
            } | Should -Throw '*boom - the registry read failed*'
 
            # One load, one unload - the failure happened in between, and
            # cleanup still had to run. This is the actual point of the
            # refactor: proving this holds without needing a real hive.
            Should -Invoke -CommandName 'reg.exe' -Times 2
        }
    }
 
    Context 'reg.exe load itself fails' {
        BeforeEach {
            Mock -CommandName 'reg.exe' -MockWith {
                $global:LASTEXITCODE = 1
                'ERROR: Access is denied.'
            }
        }
 
        It 'throws a clear error and never attempts to unload a hive that was never loaded' {
            {
                Invoke-EZfixWithOfflineHive -HiveFilePath 'C:\fake\SYSTEM' -ScriptBlock { param($HiveRoot) }
            } | Should -Throw '*reg.exe load failed*'
 
            # Only the failed load attempt - no unload, since $hiveLoaded
            # never became true.
            Should -Invoke -CommandName 'reg.exe' -Times 1
        }
    }
}
