﻿# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

[CmdletBinding()]
param()

Describe "Testing Health Checker by Mock Data Imports" {

    BeforeAll {
        . $PSScriptRoot\HealthCheckerTests.ImportCode.NotPublished.ps1
        $Script:MockDataCollectionRoot = "$Script:parentPath\Tests\DataCollection\E19"
        . $PSScriptRoot\HealthCheckerTest.CommonMocks.NotPublished.ps1
    }

    Context "Checking Scenarios 1" {
        BeforeAll {
            Mock Get-RemoteRegistryValue -ParameterFilter { $GetValue -eq "KeepAliveTime" } -MockWith { return 0 }
            Mock Get-RemoteRegistryValue -ParameterFilter { $GetValue -eq "CtsProcessorAffinityPercentage" } -MockWith { return 10 }
            Mock Get-RemoteRegistryValue -ParameterFilter { $GetValue -eq "LsaCfgFlags" } -MockWith { return 1 }
            Mock Get-ExchangeApplicationConfigurationFileValidation { return Import-Clixml "$Script:MockDataCollectionRoot\Exchange\GetExchangeApplicationConfigurationFileValidation1.xml" }
            Mock Get-ServerRebootPending { return Import-Clixml "$Script:MockDataCollectionRoot\OS\GetServerRebootPending1.xml" }
            Mock Get-AllTlsSettings { return Import-Clixml "$Script:MockDataCollectionRoot\OS\GetAllTlsSettings1.xml" }
            Mock Get-Smb1ServerSettings { return Import-Clixml "$Script:MockDataCollectionRoot\OS\GetSmb1ServerSettings1.xml" }
            Mock Get-OrganizationConfig { return Import-Clixml "$Script:MockDataCollectionRoot\Exchange\GetOrganizationConfig1.xml" }
            Mock Get-OwaVirtualDirectory { return Import-Clixml "$Script:MockDataCollectionRoot\Exchange\GetOwaVirtualDirectory1.xml" }
            Mock Get-HttpProxySetting { return Import-Clixml "$Script:MockDataCollectionRoot\OS\GetHttpProxySetting1.xml" }
            Mock Get-AcceptedDomain { return Import-Clixml "$Script:MockDataCollectionRoot\Exchange\GetAcceptedDomain_Problem.xml" }
            Mock Invoke-ScriptBlockHandler -ParameterFilter { $ScriptBlockDescription -eq "Getting Shared Web Config Files" } -MockWith { return Import-Clixml "$Script:MockDataCollectionRoot\Exchange\GetIISSharedWebConfig1.xml" }
            Mock Invoke-ScriptBlockHandler -ParameterFilter { $ScriptBlockDescription -eq "Get-IISWebApplication" } -MockWith { return Import-Clixml "$Script:MockDataCollectionRoot\Exchange\GetIISWebApplication1.xml" }
            Mock Invoke-ScriptBlockHandler -ParameterFilter { $ScriptBlockDescription -eq "Getting applicationHost.config" } -MockWith { return Get-Content "$Script:MockDataCollectionRoot\Exchange\GetApplicationHostConfig1.config" }
            Mock Get-ExchangeSettingOverride { return Import-Clixml "$Script:MockDataCollectionRoot\Exchange\GetExchangeSettingOverride1.xml" }
            Mock Get-Service {
                param(
                    [string]$ComputerName,
                    [string]$Name
                )
                if ($Name -eq "MSExchangeMitigation") { return Import-Clixml "$Script:MockDataCollectionRoot\Exchange\GetServiceMitigation.xml" }
                return Import-Clixml "$Script:MockDataCollectionRoot\OS\GetService1.xml"
            }

            SetDefaultRunOfHealthChecker "Debug_Scenario1_Results.xml"
        }

        It "Generic Exchange Information" {
            SetActiveDisplayGrouping "Exchange Information"
            TestObjectMatch "Setting Overrides Detected" $true
            TestObjectMatch "Extended Protection Enabled (Any VDir)" $true
        }

        It "Dependent Services" {
            $displayFormat = "{0} - Status: {1} - StartType: {2}"
            TestObjectMatch "Critical Pla" ($displayFormat -f "pla", "Stopped", "Manual") -WriteType "Red"
            TestObjectMatch "Critical HostControllerService" ($displayFormat -f "HostControllerService", "Stopped", "Disabled") -WriteType "Red"
            TestObjectMatch "Common MSExchangeDagMgmt" ($displayFormat -f "MSExchangeDagMgmt", "Stopped", "Automatic") -WriteType "Yellow"
        }

        It "Http Proxy Settings" {
            SetActiveDisplayGrouping "Operating System Information"
            $httpProxy = GetObject "Http Proxy Setting"
            $httpProxy.ProxyAddress | Should -Be "proxy.contoso.com:8080"
            $httpProxy.ByPassList | Should -Be "localhost;*.contoso.com;*microsoft.com"
            $httpProxy.HttpProxyDifference | Should -Be "False"
            $httpProxy.HttpByPassDifference | Should -Be "False"
        }

        It "TCP Keep Alive Time" {
            SetActiveDisplayGrouping "Frequent Configuration Issues"
            TestObjectMatch "TCP/IP Settings" 0 -WriteType "Red"
        }

        It "CTS Processor Affinity Percentage" {
            TestObjectMatch "CTS Processor Affinity Percentage" 10 -WriteType "Red"
        }

        It "Credential Guard Enabled" {
            TestObjectMatch "Credential Guard Enabled" "True" -WriteType "Red"
        }

        It "EdgeTransport.exe.config Present" {
            TestObjectMatch "EdgeTransport.exe.config Present" "False --- Error" -WriteType "Red"
        }

        It "Open Relay Wild Card Domain" {
            TestObjectMatch "Open Relay Wild Card Domain" "Error --- Accepted Domain `"Problem Accepted Domain`" is set to a Wild Card (*) Domain Name with a domain type of InternalRelay. This is not recommended as this is an open relay for the entire environment.`r`n`t`tMore Information: https://aka.ms/HC-OpenRelayDomain" -WriteType "Red"
        }

        It "Testing Missing Configuration File" {
            TestObjectMatch "Missing Configuration File" $true -WriteType "Red"
        }

        It "Testing Default Variable Detected" {
            TestObjectMatch "Default Variable Detected" $true -WriteType "Red"
        }

        It "Testing Bin Search Folder Not Found" {
            TestObjectMatch "Bin Search Folder Not Found" $true -WriteType "Red"
        }

        It "Server Pending Reboot" {
            SetActiveDisplayGrouping "Operating System Information"
            TestObjectMatch "Server Pending Reboot" "True" -WriteType "Yellow"
            TestObjectMatch "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations" "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations" -WriteType "Yellow"
            TestObjectMatch "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -WriteType "Yellow"
            TestObjectMatch "HKLM:\Software\Microsoft\Updates\UpdateExeVolatile\Flags" "HKLM:\Software\Microsoft\Updates\UpdateExeVolatile\Flags" -WriteType "Yellow"
            TestObjectMatch "Reboot More Information" "True" -WriteType "Yellow"
        }

        It "TLS Settings" {
            SetActiveDisplayGrouping "Security Settings"
            TestObjectMatch "TLS 1.0" "Misconfigured" -WriteType "Red"
            TestObjectMatch "TLS 1.1" "Misconfigured" -WriteType "Red"
            TestObjectMatch "TLS 1.2" "Enabled" -WriteType "Green"
            TestObjectMatch "TLS 1.3" "Disabled" -WriteType "Green"

            TestObjectMatch "Display Link to Docs Page" "True" -WriteType "Yellow"

            TestObjectMatch "Detected TLS Mismatch Display More Info" "True" -WriteType "Yellow"

            $tlsCipherSuite = (GetObject "TLS Cipher Suite Group")
            $tlsCipherSuite.Count | Should -Be 8
        }

        It "SMB Settings" {
            TestObjectMatch "SMB1 Installed" "True" -WriteType "Red"
            TestObjectMatch "SMB1 Blocked" "False" -WriteType "Red"
        }

        It "Enabled Domains" {
            SetActiveDisplayGrouping "Security Vulnerability"
            $downloadDomains = GetObject "CVE-2021-1730"
            $downloadDomains.DownloadDomainsEnabled | Should -Be "True"
            $downloadDomains.ExternalDownloadHostName | Should -Be "Set to the same as Internal Or External URL as OWA."
            $downloadDomains.InternalDownloadHostName | Should -Be "Set to the same as Internal Or External URL as OWA."
        }

        It "Extended Protection" {
            TestObjectMatch "Extended Protection Vulnerable" "True" -WriteType "Red"
            TestObjectMatch "Extended Protection Vulnerable Details" "Extended Protection is configured, but not supported on this Exchange Server build" -WriteType "Red"
        }

        It "AMSI Enabled" {
            SetActiveDisplayGrouping "Security Settings"
            TestObjectMatch "AMSI Enabled" "False" -WriteType "Yellow"
        }

        It "EEMS Enabled And OCS Reachable" {
            SetActiveDisplayGrouping "Security Settings"
            TestObjectMatch "Exchange Emergency Mitigation Service" "Enabled" -WriteType "Green"
            TestObjectMatch "Windows service" "Running"
            TestObjectMatch "Pattern service" "200 - Reachable"
            TestObjectMatch "Telemetry enabled" "False"
        }
    }

    Context "Checking Scenarios 2" {
        BeforeAll {
            Mock Get-RemoteRegistryValue -ParameterFilter { $GetValue -eq "KeepAliveTime" } -MockWith { return 1800000 }
            Mock Get-RemoteRegistryValue -ParameterFilter { $GetValue -eq "DisableGranularReplication" } -MockWith { return 1 }
            Mock Get-RemoteRegistryValue -ParameterFilter { $GetValue -eq "DisableAsyncNotification" } -MockWith { return 1 }
            Mock Get-AllTlsSettings { return Import-Clixml "$Script:MockDataCollectionRoot\OS\GetAllTlsSettings2.xml" }
            Mock Get-OrganizationConfig { return Import-Clixml "$Script:MockDataCollectionRoot\Exchange\GetOrganizationConfig1.xml" }
            Mock Get-OwaVirtualDirectory { return Import-Clixml "$Script:MockDataCollectionRoot\Exchange\GetOwaVirtualDirectory2.xml" }
            Mock Get-AcceptedDomain { return Import-Clixml "$Script:MockDataCollectionRoot\Exchange\GetAcceptedDomain_Bad.xml" }
            Mock Get-DnsClient { return Import-Clixml "$Script:MockDataCollectionRoot\OS\GetDnsClient1.xml" }
            Mock Get-ExSetupDetails { return Import-Clixml "$Script:MockDataCollectionRoot\Exchange\ExSetup1.xml" }
            Mock Invoke-ScriptBlockHandler -ParameterFilter { $ScriptBlockDescription -eq "Getting applicationHost.config" } -MockWith { return Get-Content "$Script:MockDataCollectionRoot\Exchange\GetApplicationHostConfig1.config" }

            SetDefaultRunOfHealthChecker "Debug_Scenario2_Results.xml"
        }

        It "Generic Exchange Information" {
            SetActiveDisplayGrouping "Exchange Information"
            TestObjectMatch "Extended Protection Enabled (Any VDir)" $true
        }

        It "TCP Keep Alive Time" {
            SetActiveDisplayGrouping "Frequent Configuration Issues"

            TestObjectMatch "TCP/IP Settings" 1800000 -WriteType "Green"
        }

        It "Open Relay Wild Card Domain" {
            TestObjectMatch "Open Relay Wild Card Domain" "Error --- Accepted Domain `"Bad Accepted Domain`" is set to a Wild Card (*) Domain Name with a domain type of ExternalRelay. This is not recommended as this is an open relay for the entire environment.`r`n`t`tMore Information: https://aka.ms/HC-OpenRelayDomain" -WriteType "Red"
        }

        It "DisableGranularReplication" {
            TestObjectMatch "DisableGranularReplication" $true -WriteType "Red"
        }

        It "Disable Async Notification" {
            TestObjectMatch "Disable Async Notification" $true -WriteType "Yellow"
        }

        It "TLS Settings" {
            SetActiveDisplayGrouping "Security Settings"
            TestObjectMatch "TLS 1.0" "Misconfigured" -WriteType "Red"
            TestObjectMatch "TLS 1.1" "Misconfigured" -WriteType "Red"
            TestObjectMatch "TLS 1.2" "Enabled" -WriteType "Green"
            TestObjectMatch "TLS 1.3" "Enabled" -WriteType "Red"

            TestObjectMatch "TLS 1.3 not disabled" $true -WriteType "Red"

            TestObjectMatch "Display Link to Docs Page" "True" -WriteType "Yellow"

            TestObjectMatch "Detected TLS Mismatch Display More Info" "True" -WriteType "Yellow"

            $tlsCipherSuite = (GetObject "TLS Cipher Suite Group")
            $tlsCipherSuite.Count | Should -Be 8
        }

        It "Enabled Domains" {
            SetActiveDisplayGrouping "Security Vulnerability"
            $downloadDomains = GetObject "CVE-2021-1730"
            $downloadDomains.DownloadDomainsEnabled | Should -Be "True"
            $downloadDomains.ExternalDownloadHostName | Should -Be "Set Correctly."
            $downloadDomains.InternalDownloadHostName | Should -Be "Not Configured"
        }

        It "Extended Protection" {
            $testFind = GetObject "Extended Protection Vulnerable"
            $testFind | Should -Be $null
        }

        It "No Register in DNS" {
            SetActiveDisplayGrouping "NIC Settings Per Active Adapter"
            TestObjectMatch "No NIC Registered In DNS" "Error: This will cause server to crash and odd mail flow issues. Exchange Depends on the primary NIC to have the setting Registered In DNS set." -WriteType "Red"
        }
    }

    Context "Checking Scenario 3 - Physical" {
        BeforeAll {
            $Script:date = Get-Date
            Mock Get-WmiObjectHandler -ParameterFilter { $Class -eq "Win32_ComputerSystem" } `
                -MockWith { return Import-Clixml "$Script:MockDataCollectionRoot\Hardware\Physical_Win32_ComputerSystem1.xml" }
            Mock Get-WmiObjectHandler -ParameterFilter { $Class -eq "Win32_PhysicalMemory" } `
                -MockWith { return Import-Clixml "$Script:MockDataCollectionRoot\Hardware\Physical_Win32_PhysicalMemory.xml" }
            Mock Get-WmiObjectHandler -ParameterFilter { $Class -eq "Win32_Processor" } `
                -MockWith { return Import-Clixml "$Script:MockDataCollectionRoot\Hardware\Physical_Win32_Processor1.xml" }
            Mock Get-ExSetupDetails { return Import-Clixml "$Script:MockDataCollectionRoot\Exchange\ExSetup1.xml" }
            Mock Invoke-ScriptBlockHandler -ParameterFilter { $ScriptBlockDescription -eq "Getting applicationHost.config" } -MockWith { return Get-Content "$Script:MockDataCollectionRoot\Exchange\GetApplicationHostConfig2.config" }

            SetDefaultRunOfHealthChecker "Debug_Scenario3_Physical_Results.xml"
        }

        It "Extended Protection Enabled" {
            SetActiveDisplayGrouping "Exchange Information"
            TestObjectMatch "Extended Protection Enabled (Any VDir)" $true
        }

        It "Number of Processors" {
            SetActiveDisplayGrouping "Processor/Hardware Information"
            TestObjectMatch "Number of Processors" 4 -WriteType "Red"
        }

        It "Number of Physical Cores" {
            TestObjectMatch "Number of Physical Cores" 48 -WriteType "Green"
        }

        It "Number of Logical Cores" {
            TestObjectMatch "Number of Logical Cores" "96 - Error" -WriteType "Red"
        }

        It "Hyper-Threading" {
            TestObjectMatch "Hyper-Threading" "True" -WriteType "Red"
        }

        It "NUMA Group Size Optimization" {
            TestObjectMatch "NUMA Group Size Optimization" "Clustered" -WriteType "Red"
        }

        It "Current Processor Speed" {
            TestObjectMatch "Current Processor Speed" 2200 -WriteType "Red"
        }

        It "HighPerformanceSet" {
            TestObjectMatch "HighPerformanceSet" $false -WriteType "Red"
        }

        It "Extended Protection" {
            SetActiveDisplayGrouping "Security Vulnerability"
            TestObjectMatch "Extended Protection Vulnerable" "True" -WriteType "Red"
            TestObjectMatch "Extended Protection Vulnerable Details" "Extended Protection isn't configured as expected" -WriteType "Red"
        }
    }
}
