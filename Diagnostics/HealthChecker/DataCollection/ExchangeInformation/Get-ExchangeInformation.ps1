﻿# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

. $PSScriptRoot\..\..\..\..\Security\src\ExchangeExtendedProtectionManagement\DataCollection\Get-ExtendedProtectionConfiguration.ps1
. $PSScriptRoot\..\..\..\..\Shared\ErrorMonitorFunctions.ps1
. $PSScriptRoot\..\..\..\..\Shared\Get-ExchangeBuildVersionInformation.ps1
. $PSScriptRoot\..\..\..\..\Shared\Get-ExchangeSettingOverride.ps1
. $PSScriptRoot\IISInformation\Get-ExchangeAppPoolsInformation.ps1
. $PSScriptRoot\IISInformation\Get-ExchangeServerIISSettings.ps1
. $PSScriptRoot\Get-ExchangeAMSIConfigurationState.ps1
. $PSScriptRoot\Get-ExchangeApplicationConfigurationFileValidation.ps1
. $PSScriptRoot\Get-ExchangeConnectors.ps1
. $PSScriptRoot\Get-ExchangeDependentServices.ps1
. $PSScriptRoot\Get-ExchangeEmergencyMitigationServiceState.ps1
. $PSScriptRoot\Get-ExchangeRegistryValues.ps1
. $PSScriptRoot\Get-ExchangeSerializedDataSigningState.ps1
. $PSScriptRoot\Get-ExchangeServerCertificates.ps1
. $PSScriptRoot\Get-ExchangeServerMaintenanceState.ps1
. $PSScriptRoot\Get-ExchangeUpdates.ps1
. $PSScriptRoot\Get-ExSetupDetails.ps1
. $PSScriptRoot\Get-FIPFSScanEngineVersionState.ps1
. $PSScriptRoot\Get-ServerRole.ps1
function Get-ExchangeInformation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [object]$PassedOrganizationInformation
    )
    process {
        Write-Verbose "Calling: $($MyInvocation.MyCommand)"
        $params = @{
            ComputerName           = $Server
            ScriptBlock            = { [environment]::OSVersion.Version -ge "10.0.0.0" }
            ScriptBlockDescription = "Windows 2016 or Greater Check"
            CatchActionFunction    = ${Function:Invoke-CatchActions}
        }
        $windows2016OrGreater = Invoke-ScriptBlockHandler @params
        $getExchangeServer = (Get-ExchangeServer -Identity $Server -Status)
        $exchangeCertificates = Get-ExchangeServerCertificates -Server $Server
        $exSetupDetails = Get-ExSetupDetails -Server $Server
        $versionInformation = (Get-ExchangeBuildVersionInformation -FileVersion ($exSetupDetails.FileVersion))

        $buildInformation = [PSCustomObject]@{
            ServerRole         = (Get-ServerRole -ExchangeServerObj $getExchangeServer)
            MajorVersion       = $versionInformation.MajorVersion
            CU                 = $versionInformation.CU
            ExchangeSetup      = $exSetupDetails
            VersionInformation = $versionInformation
            KBsInstalled       = [array](Get-ExchangeUpdates -Server $Server -ExchangeMajorVersion $versionInformation.MajorVersion)
        }

        $dependentServices = (Get-ExchangeDependentServices -MachineName $Server)

        try {
            $getMailboxServer = (Get-MailboxServer -Identity $Server -ErrorAction Stop)
        } catch {
            Write-Verbose "Failed to run Get-MailboxServer"
            Invoke-CatchActions
        }

        try {
            $getOwaVirtualDirectory = Get-OwaVirtualDirectory -Identity ("{0}\owa (Default Web Site)" -f $Server) -ADPropertiesOnly -ErrorAction Stop
            $getWebServicesVirtualDirectory = Get-WebServicesVirtualDirectory -Server $Server -ErrorAction Stop
        } catch {
            Write-Verbose "Failed to get OWA or EWS virtual directory"
            Invoke-CatchActions
        }

        $params = @{
            RequiredInformation = [PSCustomObject]@{
                ComputerName       = $Server
                MitigationsEnabled = if ($null -ne $PassedOrganizationInformation.OrganizationConfig) { $PassedOrganizationInformation.OrganizationConfig.MitigationsEnabled } else { $null }
                GetExchangeServer  = $getExchangeServer
            }
            CatchActionFunction = ${Function:Invoke-CatchActions}
        }

        $exchangeEmergencyMitigationService = Get-ExchangeEmergencyMitigationServiceState @params

        if (($windows2016OrGreater) -and
        ($getExchangeServer.IsEdgeServer -eq $false)) {
            $amsiConfiguration = Get-ExchangeAMSIConfigurationState -GetSettingOverride $PassedOrganizationInformation.SettingOverride
        } else {
            Write-Verbose "AMSI Interface is not available on this OS / Exchange server role"
        }

        $registryValues = Get-ExchangeRegistryValues -MachineName $Server -CatchActionFunction ${Function:Invoke-CatchActions}
        $serverExchangeBinDirectory = [System.Io.Path]::Combine($registryValues.MsiInstallPath, "Bin\")
        Write-Verbose "Found Exchange Bin: $serverExchangeBinDirectory"

        if ($getExchangeServer.IsEdgeServer -eq $false) {
            $applicationPools = Get-ExchangeAppPoolsInformation -Server $Server

            Write-Verbose "Query Exchange Connector settings via 'Get-ExchangeConnectors'"
            $exchangeConnectors = Get-ExchangeConnectors -ComputerName $Server -CertificateObject $exchangeCertificates

            $exchangeServerIISParams = @{
                ComputerName        = $Server
                IsLegacyOS          = ($windows2016OrGreater -eq $false)
                CatchActionFunction = ${Function:Invoke-CatchActions}
            }

            Write-Verbose "Trying to query Exchange Server IIS settings"
            $iisSettings = Get-ExchangeServerIISSettings @exchangeServerIISParams

            Write-Verbose "Query extended protection configuration for multiple CVEs testing"
            $getExtendedProtectionConfigurationParams = @{
                ComputerName        = $Server
                ExSetupVersion      = $buildInformation.ExchangeSetup.FileVersion
                CatchActionFunction = ${Function:Invoke-CatchActions}
            }

            try {
                if ($null -ne $iisSettings.ApplicationHostConfig) {
                    $getExtendedProtectionConfigurationParams.ApplicationHostConfig = [xml]$iisSettings.ApplicationHostConfig
                }
                Write-Verbose "Was able to convert the ApplicationHost.Config to XML"

                $extendedProtectionConfig = Get-ExtendedProtectionConfiguration @getExtendedProtectionConfigurationParams
            } catch {
                Write-Verbose "Failed to get the ExtendedProtectionConfig"
                Invoke-CatchActions
            }
        }

        $applicationConfigFileStatus = Get-ExchangeApplicationConfigurationFileValidation -ComputerName $Server -ConfigFileLocation ("{0}EdgeTransport.exe.config" -f $serverExchangeBinDirectory)
        $serverMaintenance = Get-ExchangeServerMaintenanceState -Server $Server -ComponentsToSkip "ForwardSyncDaemon", "ProvisioningRps"
        $settingOverrides = Get-ExchangeSettingOverride -Server $Server -CatchActionFunction ${Function:Invoke-CatchActions}

        if (($versionInformation.BuildVersion -ge "15.1.0.0") -and
        ($getExchangeServer.IsEdgeServer -eq $false)) {
            Write-Verbose "SerializedDataSigning must be configured via SettingOverride"
            $serializationDataSigningConfiguration = Get-ExchangeSerializedDataSigningState -GetSettingOverride $PassedOrganizationInformation.SettingOverride
        } elseif (($versionInformation.BuildVersion -like "15.0.*") -and
        ($getExchangeServer.IsEdgeServer -eq $false)) {
            Write-Verbose "SerializedDataSigning must be configured via Registry Value"
            $serializationDataSigningConfiguration = $registryValues.SerializedDataSigning
        } else {
            Write-Verbose "SerializedDataSigning is not supported on this Exchange version & role combination"
        }

        if (($getExchangeServer.IsMailboxServer) -or
        ($getExchangeServer.IsEdgeServer)) {
            try {
                $exchangeServicesNotRunning = @()
                $testServiceHealthResults = Test-ServiceHealth -Server $Server -ErrorAction Stop
                foreach ($notRunningService in $testServiceHealthResults.ServicesNotRunning) {
                    if ($exchangeServicesNotRunning -notcontains $notRunningService) {
                        $exchangeServicesNotRunning += $notRunningService
                    }
                }
            } catch {
                Write-Verbose "Failed to run Test-ServiceHealth"
                Invoke-CatchActions
            }
        }

        Write-Verbose "Checking if FIP-FS is affected by the pattern issue"
        $fipFsParams = @{
            ComputerName       = $Server
            ExSetupVersion     = $buildInformation.ExchangeSetup.FileVersion
            AffectedServerRole = $($getExchangeServer.IsMailboxServer -eq $true)
        }

        $FIPFSUpdateIssue = Get-FIPFSScanEngineVersionState @fipFsParams
    } end {

        Write-Verbose "Exiting: Get-ExchangeInformation"
        return [PSCustomObject]@{
            BuildInformation                      = $buildInformation
            GetExchangeServer                     = $getExchangeServer
            GetMailboxServer                      = $getMailboxServer
            GetOwaVirtualDirectory                = $getOwaVirtualDirectory
            GetWebServicesVirtualDirectory        = $getWebServicesVirtualDirectory
            ExtendedProtectionConfig              = $extendedProtectionConfig
            ExchangeConnectors                    = $exchangeConnectors
            AMSIConfiguration                     = [array]$amsiConfiguration
            SerializationDataSigningConfiguration = [array]$serializationDataSigningConfiguration
            ExchangeServicesNotRunning            = [array]$exchangeServicesNotRunning
            ApplicationPools                      = $applicationPools
            RegistryValues                        = $registryValues
            ServerMaintenance                     = $serverMaintenance
            ExchangeCertificates                  = [array]$exchangeCertificates
            ExchangeEmergencyMitigationService    = $exchangeEmergencyMitigationService
            ApplicationConfigFileStatus           = $applicationConfigFileStatus
            DependentServices                     = $dependentServices
            IISSettings                           = $iisSettings
            SettingOverrides                      = $settingOverrides
            FIPFSUpdateIssue                      = $FIPFSUpdateIssue
        }
    }
}
