# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

function Get-ActiveDirectoryAcl {
    [CmdletBinding()]
    [OutputType([System.DirectoryServices.ActiveDirectorySecurity])]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $DistinguishedName,

        [Parameter(Mandatory = $false)]
        [string]
        $DomainController
    )

    $dc = ""
    if (-not [string]::IsNullOrEmpty($DomainController)) {
        $dc = $DomainController + "/"
    }

    $path = "LDAP://$($dc)$($DistinguishedName)"
    $adEntry = [ADSI]($path)
    $sdFinder = New-Object System.DirectoryServices.DirectorySearcher($adEntry, "(objectClass=*)", [string[]]("distinguishedName", "ntSecurityDescriptor"), [System.DirectoryServices.SearchScope]::Base)
    $sdResult = $sdFinder.FindOne()
    $ntsdProp = $sdResult.Properties["ntSecurityDescriptor"][0]
    $adSec = New-Object System.DirectoryServices.ActiveDirectorySecurity
    $adSec.SetSecurityDescriptorBinaryForm($ntsdProp)
    return $adSec
}
