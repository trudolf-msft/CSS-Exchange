# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

function Load-ConfigSnapshot {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $File
    )

    $global:ExchangeConfigurationSnapshot = Import-Clixml $File

    <#
        Organization info functions
    #>

    Set-Item function:global:Get-DatabaseAvailabilityGroup {
        $global:ExchangeConfigurationSnapshot.Organization.DatabaseAvailabilityGroup
    }

    Set-Item function:global:Get-ExchangeServer {
        $global:ExchangeConfigurationSnapshot.Organization.ExchangeServer
    }

    Set-Item function:global:Get-MailboxDatabase {
        $global:ExchangeConfigurationSnapshot.Organization.MailboxDatabase
    }

    Set-Item function:global:Get-OrganizationConfig {
        $global:ExchangeConfigurationSnapshot.Organization.OrganizationConfig
    }

    Set-Item function:global:Get-TransportRule {
        $global:ExchangeConfigurationSnapshot.Organization.TransportRule
    }

    <#
        Server-specific info functions
    #>

    Set-Item function:global:Get-ImapSettings {
        $global:ExchangeConfigurationSnapshotServerContext.ImapSettings
    }

    Set-Item function:global:Get-MailboxDatabaseCopyStatus {
        $global:ExchangeConfigurationSnapshotServerContext.MailboxDatabaseCopyStatus
    }

    Set-Item function:global:Get-PopSettings {
        $global:ExchangeConfigurationSnapshotServerContext.PopSettings
    }

    <#
        Provide a way for the user to easily set the server context
    #>

    Set-Item function:global:Set-ExchangeConfigurationSnapshotServerContext {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]
            $ServerName
        )

        $matchingContext = $global:ExchangeConfigurationSnapshot.Servers | Where-Object { $_.ServerName -eq $ServerName }
        if ($null -ne $matchingContext) {
            $global:ExchangeConfigurationSnapshotServerContext = $matchingContext
            Write-Host "Exchange server context: $($matchingContext.ServerName)."
        } else {
            Write-Host "No such server in this snapshot. Available servers:"
            $global:ExchangeConfigurationSnapshot.Servers | ForEach-Object { Write-Host $_.ServerName }
        }
    }

    Set-ExchangeConfigurationSnapshotServerContext ($global:ExchangeConfigurationSnapshot.Servers | Select-Object -First 1).ServerName

    Write-Host "Servers in this snapshot:"
    $global:ExchangeConfigurationSnapshot.Servers | ForEach-Object { Write-Host $_.ServerName }
    Write-Host "Use Set-ExchangeConfigurationSnapshotServerContext SERVERNAME to change servers."
}
