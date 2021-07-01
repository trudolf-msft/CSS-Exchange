# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

function Get-OrgInfo {
    Set-ADServerSettings -ViewEntireForest $true

    [PSCustomObject]@{
        DatabaseAvailabilityGroup = Get-DatabaseAvailabilityGroup *>&1
        ExchangeServer            = Get-ExchangeServer *>&1
        MailboxDatabase           = Get-MailboxDatabase *>&1
        OrganizationConfig        = Get-OrganizationConfig *>&1
        TransportRule             = Get-TransportRule *>&1
    }
}
