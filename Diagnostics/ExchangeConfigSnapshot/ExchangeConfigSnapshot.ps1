# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

[CmdletBinding()]
param (
    [Parameter(ParameterSetName = "Save", Mandatory = $true)]
    [switch]
    $Save,

    [Parameter(ParameterSetName = "Save", Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('Fqdn')]
    [string[]]
    $Server,

    [Parameter(ParameterSetName = "Load", Mandatory = $true)]
    [switch]
    $Load,

    [Parameter(ParameterSetName = "Load", Mandatory = $true)]
    [string]
    $File
)

begin {
    . $PSScriptRoot\Save-ConfigSnapshot.ps1
    . $PSScriptRoot\Load-ConfigSnapshot.ps1

    $servers = New-Object System.Collections.ArrayList
}

process {
    if ($Save) {
        foreach ($serverName in $Server) {
            $null = $servers.Add($serverName.Split(".")[0].ToUpper())
        }
    }
}

end {
    if ($Save) {
        $thisServer = Get-Module | ForEach-Object { if ($_.Description -match "Implicit remoting for https?:\/\/(.+?)[.|\/]") { $Matches[1] } }
        $null = $servers.Add($thisServer.ToUpper())
        $uniqueServers = $servers | Select-Object -Unique | Sort-Object

        Save-ConfigSnapshot -Servers $uniqueServers
    }

    if ($Load) {
        Load-ConfigSnapshot $File
    }
}
