# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

function Get-TokenGroupsGlobalAndUniversal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $AccountDN
    )

    $searchRoot = [ADSI]("GC://" + $AccountDN)
    $searcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot, "(objectClass=*)", @("tokenGroupsGlobalAndUniversal"), [System.DirectoryServices.SearchScope]::Base)
    $result = $searcher.FindOne()
    if ($null -eq $result) {
        throw "Account not found: $AccountDN"
    }

    foreach ($sidBytes in $result.Properties["tokenGroupsGlobalAndUniversal"]) {
        $translated = $null
        $sid = New-Object System.Security.Principal.SecurityIdentifier($sidbytes, 0)
        try {
            $translated = $sid.Translate("System.Security.Principal.NTAccount").ToString()
        } catch {
            try {
                $adObject = ([ADSI]("LDAP://<SID=" + $sid.ToString() + ">"))
                $translated = $adObject.Properties["samAccountName"][0].ToString()
            } catch {
                Write-Error ("Failed to translate SID: " + $sid.ToString())
                throw
            }
        }

        [PSCustomObject]@{
            SID  = $sid.ToString();
            Name = $translated;
        }
    }
}
