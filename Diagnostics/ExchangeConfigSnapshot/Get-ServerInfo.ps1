# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

function Get-ServerInfo {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $ServerName
    )

    $WarningPreference = "SilentlyContinue"
    $null = Import-PSSession (New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "http://$ServerName/powershell" -Authentication Kerberos)

    [PSCustomObject]@{
        ServerName                = $ServerName.ToUpper()
        ImapSettings              = Get-ImapSettings *>&1
        MailboxDatabaseCopyStatus = Get-MailboxDatabaseCopyStatus *>&1
        PopSettings               = Get-PopSettings *>&1
    }
}
