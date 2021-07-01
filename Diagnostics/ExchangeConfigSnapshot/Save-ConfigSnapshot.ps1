# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

. $PSScriptRoot\Get-OrgInfo.ps1
. $PSScriptRoot\Get-ServerInfo.ps1

function Save-ConfigSnapshot {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]
        $Servers
    )

    $orgInfo = Get-OrgInfo
    $serverInfo = $Servers | ForEach-Object {
        Write-Host "Getting configuration for server $_"
        $job = Start-Job -ScriptBlock ${function:Get-ServerInfo} -ArgumentList $_
        $null = Wait-Job $job
        Receive-Job $job
    }

    $timeString = [DateTime]::Now.ToString("yyMMddHHmmss")
    $fileName = Join-Path $PSScriptRoot "ExchangeConfiguration-$timeString.xml"

    [PSCustomObject]@{
        Time         = [DateTime]::Now
        Organization = $orgInfo
        Servers      = $serverInfo
    } | Export-Clixml $fileName

    Write-Host "Configuration snapshot saved to file: $fileName"
}
