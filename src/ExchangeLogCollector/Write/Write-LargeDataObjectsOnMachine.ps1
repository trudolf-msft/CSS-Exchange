#This function job is to write out the Data that is too large to pass into the main script block
#This is for mostly Exchange Related objects.
#To handle this, we export the data locally and copy the data over the correct server.
Function Write-LargeDataObjectsOnMachine {

    Write-ScriptDebug("Function Enter Write-LargeDataObjectsOnMachine")
    #Collect the Exchange Data that resides on their own machine.
    Function Invoke-ExchangeResideDataCollectionWrite {
        param(
            [Parameter(Mandatory = $true)][object]$PassedInfo
        )

        $location = $PassedInfo.SaveToLocation
        $exchBin = "{0}\Bin" -f $PassedInfo.InstallDirectory
        $configFiles = Get-ChildItem $exchBin | Where-Object { $_.Name -like "*.config" }
        $copyTo = "{0}\Config" -f $location
        $configFiles | ForEach-Object { Copy-Item $_.VersionInfo.FileName $copyTo }

        $copyServerComponentStatesRegistryTo = "{0}\regServerComponentStates.TXT" -f $location
        reg query HKLM\SOFTWARE\Microsoft\ExchangeServer\v15\ServerComponentStates /s > $copyServerComponentStatesRegistryTo

        Get-Command exsetup | ForEach-Object { $_.FileVersionInfo } > ("{0}\{1}_GCM.txt" -f $location, $env:COMPUTERNAME)

        #Exchange Web App Pools
        $windir = $env:windir
        $appCmd = "{0}\system32\inetsrv\appcmd.exe" -f $windir
        if (Test-Path $appCmd) {
            $appPools = &$appCmd list apppool

            $exchangeAppPools = $appPools |
                ForEach-Object {
                    $startIndex = $_.IndexOf('"') + 1
                    $appPoolName = $_.Substring($startIndex,
                        ($_.Substring($startIndex).IndexOf('"')))
                    return $appPoolName
                } |
                Where-Object {
                    $_.StartsWith("MSExchange")
                }

            $webAppPoolsSaveRoot = "{0}\WebAppPools" -f $location
            $cacheConfigFileListLocation = @()
            $exchangeAppPools |
                ForEach-Object {
                    $config = &$appCmd list apppool $_ /text:CLRConfigFile
                    $allInfo = &$appCmd list apppool $_ /text:*

                    if (![string]::IsNullOrEmpty($config) -and
                        (Test-Path $config) -and
                        (!($cacheConfigFileListLocation.Contains($config.ToLower())))) {

                        $cacheConfigFileListLocation += $config.ToLower()
                        $saveConfigLocation = "{0}\{1}_{2}" -f $webAppPoolsSaveRoot, $env:COMPUTERNAME,
                        $config.Substring($config.LastIndexOf("\") + 1)
                        (Get-Content $config) > $saveConfigLocation
                    }
                    $saveAllInfoLocation = "{0}\{1}_{2}.txt" -f $webAppPoolsSaveRoot, $env:COMPUTERNAME, $_
                    $allInfo | Format-List * > $saveAllInfoLocation
                }
        }
    }

    #Write the Exchange Object Information locally first to then allow it to be copied over to the remote machine.
    #Exchange objects can be rather large preventing them to be passed within an Invoke-Command -ArgumentList
    #In order to get around this and to avoid going through a loop of doing an Invoke-Command per server per object,
    #Write the data out locally, copy that directory over to the remote location.
    Function Write-ExchangeObjectDataLocal {
        param(
            [object]$ServerData,
            [string]$Location
        )
        $tempLocation = "{0}\{1}" -f $Location, $ServerData.ServerName
        Save-DataToFile -DataIn $ServerData.ExchangeServer -SaveToLocation ("{0}_ExchangeServer" -f $tempLocation)
        Save-DataToFile -DataIn $ServerData.HealthReport -SaveToLocation ("{0}_HealthReport" -f $tempLocation)
        Save-DataToFile -DataIn $ServerData.ServerComponentState -SaveToLocation ("{0}_ServerComponentState" -f $tempLocation)
        Save-DataToFile -DataIn $ServerData.ServerMonitoringOverride -SaveToLocation ("{0}_serverMonitoringOverride" -f $tempLocation)
        Save-DataToFile -DataIn $ServerData.ServerHealth -SaveToLocation ("{0}_ServerHealth" -f $tempLocation)

        if ($ServerData.Hub) {
            Save-DataToFile -DataIn $ServerData.TransportServerInfo -SaveToLocation ("{0}_TransportServer" -f $tempLocation)
            Save-DataToFile -DataIn $ServerData.ReceiveConnectors -SaveToLocation ("{0}_ReceiveConnectors" -f $tempLocation)
            Save-DataToFile -DataIn $ServerData.QueueData -SaveToLocation ("{0}_InstantQueueInfo" -f $tempLocation)
        }

        if ($ServerData.CAS) {
            Save-DataToFile -DataIn $ServerData.CAServerInfo -SaveToLocation ("{0}_ClientAccessServer" -f $tempLocation)
            Save-DataToFile -DataIn $ServerData.FrontendTransportServiceInfo -SaveToLocation ("{0}_FrontendTransportService" -f $tempLocation)
        }

        if ($ServerData.Mailbox) {
            Save-DataToFile -DataIn $ServerData.MailboxServerInfo -SaveToLocation ("{0}_MailboxServer" -f $tempLocation)
            Save-DataToFile -DataIn $ServerData.MailboxTransportServiceInfo -SaveToLocation ("{0}_MailboxTransportService" -f $tempLocation)
        }
    }

    Function Write-DatabaseAvailabilityGroupDataLocal {
        param(
            [object]$DAGWriteInfo
        )
        $dagName = $DAGWriteInfo.DAGInfo.Name
        $serverName = $DAGWriteInfo.ServerName
        $rootSaveToLocation = $DAGWriteInfo.RootSaveToLocation
        $mailboxDatabaseSaveToLocation = "{0}\MailboxDatabase\" -f $rootSaveToLocation
        $copyStatusSaveToLocation = "{0}\MailboxDatabaseCopyStatus\" -f $rootSaveToLocation
        New-Folder -NewFolders @($mailboxDatabaseSaveToLocation, $copyStatusSaveToLocation)
        Save-DataToFile -DataIn $DAGWriteInfo.DAGInfo -SaveToLocation ("{0}{1}_DatabaseAvailabilityGroup" -f $rootSaveToLocation, $dagName)
        Save-DataToFile -DataIn $DAGWriteInfo.DAGNetworkInfo -SaveToLocation ("{0}{1}_DatabaseAvailabilityGroupNetwork" -f $rootSaveToLocation, $dagName)
        Save-DataToFile -DataIn $DAGWriteInfo.MailboxDatabaseCopyStatusServer -SaveToLocation ("{0}{1}_MailboxDatabaseCopyStatus" -f $copyStatusSaveToLocation, $serverName)

        $DAGWriteInfo.MailboxDatabases |
            ForEach-Object {
                Save-DataToFile -DataIn $_ -SaveToLocation ("{0}{1}_MailboxDatabase" -f $mailboxDatabaseSaveToLocation, $_.Name)
            }

        $DAGWriteInfo.MailboxDatabaseCopyStatusPerDB.Keys |
            ForEach-Object {
                $data = $DAGWriteInfo.MailboxDatabaseCopyStatusPerDB[$_]
                Save-DataToFile -DataIn $data -SaveToLocation ("{0}{1}_MailboxDatabaseCopyStatus" -f $copyStatusSaveToLocation, $_)
            }
    }

    if ($DAGInformation) {

        $serverArgListDirectoriesToCreate = @()
        $dagWriteInformation = @()
        $argumentList.ServerObjects |
            Group-Object DAGName |
            Where-Object { ![string]::IsNullOrEmpty($_.Name) } |
            ForEach-Object {
                $dagName = $_.Name
                $getDAGInformation = Get-DAGInformation -DAGName $dagName
                $_.Group |
                    ForEach-Object {
                        $dagWriteInformation += [PSCustomObject]@{
                            ServerName                      = $_.ServerName
                            DAGInfo                         = $getDAGInformation.DAGInfo
                            DAGNetworkInfo                  = $getDAGInformation.DAGNetworkInfo
                            MailboxDatabaseCopyStatusServer = $getDAGInformation.MailboxDatabaseInfo[$_.ServerName].MailboxDatabaseCopyStatusServer
                            MailboxDatabases                = $getDAGInformation.MailboxDatabaseInfo[$_.ServerName].MailboxDatabases
                            MailboxDatabaseCopyStatusPerDB  = $getDAGInformation.MailboxDatabaseInfo[$_.ServerName].MailboxDatabaseCopyStatusPerDB
                        }
                    }
                }

        $localServerTempLocation = "{0}{1}\Exchange_DAG_Temp\" -f $Script:RootFilePath, $env:COMPUTERNAME
        $dagWriteInformation |
            ForEach-Object {
                $location = "{0}{1}" -f $Script:RootFilePath, $_.ServerName
                Write-ScriptDebug("Location of the data should be at: $location")
                $remoteLocation = "\\{0}\{1}" -f $_.ServerName, $location.Replace(":", "$")
                Write-ScriptDebug("Remote Copy Location: $remoteLocation")
                $rootTempLocation = "{0}{1}\{2}_Exchange_DAG_Information\" -f $localServerTempLocation, $_.ServerName, $_.DAGInfo.Name
                Write-ScriptDebug("Local Root Temp Location: $rootTempLocation")
                New-Folder -NewFolders $rootTempLocation
                $_ | Add-Member -MemberType NoteProperty -Name RootSaveToLocation -Value $rootTempLocation
                Write-DatabaseAvailabilityGroupDataLocal -DAGWriteInfo $_

                $zipCopyLocation = Compress-Folder -Folder $rootTempLocation -ReturnCompressedLocation $true
                Copy-Item $zipCopyLocation $remoteLocation
            }
        #Remove the temp data location
        Remove-Item $localServerTempLocation -Force -Recurse
    }

    if ($ExchangeServerInformation) {

        #Create a list that contains all the information that we need to dump out locally then copy over to each respective server within "Exchange_Server_Data"
        $exchangeServerData = @()
        foreach ($server in $Script:ValidServers) {
            $basicServerObject = Get-ExchangeBasicServerObject -ServerName $server -AddGetServerProperty $true

            if ($basicServerObject.Hub) {
                $basicServerObject | Add-Member -MemberType NoteProperty -Name "TransportServerInfo" -Value (Get-TransportService $server)
                $basicServerObject | Add-Member -MemberType NoteProperty -Name "ReceiveConnectors" -Value (Get-ReceiveConnector -Server $server)
                $basicServerObject | Add-Member -MemberType NoteProperty -Name "QueueData" -Value (Get-Queue -Server $server)
            }

            if ($basicServerObject.CAS) {

                if ($basicServerObject.Version -ge 16) {
                    $getClientAccessService = Get-ClientAccessService $server -IncludeAlternateServiceAccountCredentialStatus
                } else {
                    $getClientAccessService = Get-ClientAccessServer $server -IncludeAlternateServiceAccountCredentialStatus
                }
                $basicServerObject | Add-Member -MemberType NoteProperty -Name "CAServerInfo" -Value $getClientAccessService
                $basicServerObject | Add-Member -MemberType NoteProperty -Name "FrontendTransportServiceInfo" -Value (Get-FrontendTransportService -Identity $server)
            }

            if ($basicServerObject.Mailbox) {
                $basicServerObject | Add-Member -MemberType NoteProperty -Name "MailboxServerInfo" -Value (Get-MailboxServer $server)
                $basicServerObject | Add-Member -MemberType NoteProperty -Name "MailboxTransportServiceInfo" -Value (Get-MailboxTransportService -Identity $server)
            }

            $basicServerObject | Add-Member -MemberType NoteProperty -Name "HealthReport" -Value (Get-HealthReport $server)
            $basicServerObject | Add-Member -MemberType NoteProperty -Name "ServerComponentState" -Value (Get-ServerComponentState $server)
            $basicServerObject | Add-Member -MemberType NoteProperty -Name "ServerMonitoringOverride" -Value (Get-ServerMonitoringOverride $server)
            $basicServerObject | Add-Member -MemberType NoteProperty -Name "ServerHealth" -Value (Get-ServerHealth $server)

            $exchangeServerData += $basicServerObject
        }

        #if single server or Exchange 2010 where invoke-command doesn't work
        if (!($Script:ValidServers.count -eq 1 -and
                $Script:ValidServers[0].ToUpper().Contains($env:COMPUTERNAME.ToUpper()))) {

            <#
            To pass an action to Start-JobManager, need to create objects like this.
                Where ArgumentList is the arguments for the scriptblock that we are running
            [array]
                [PSCustom]
                    [string]ServerName
                    [object]ArgumentList

            Need to do the following:
                Collect Exchange Install Directory Location
                Create directories where data is being stored with the upcoming requests
                Write out the Exchange Server Object Data and copy them over to the correct server
            #>

            #Setup all the Script blocks that we are going to use.
            Write-ScriptDebug("Getting Get-ExchangeInstallDirectory string to create Script Block")
            $getExchangeInstallDirectoryString = (${Function:Get-ExchangeInstallDirectory}).ToString().Replace("#Function Version", (Get-WritersToAddToScriptBlock))
            Write-ScriptDebug("Creating Script Block")
            $getExchangeInstallDirectoryScriptBlock = [scriptblock]::Create($getExchangeInstallDirectoryString)

            Write-ScriptDebug("Getting New-Folder string to create Script Block")
            $newFolderString = (${Function:New-Folder}).ToString().Replace("#Function Version", (Get-WritersToAddToScriptBlock))
            Write-ScriptDebug("Creating script block")
            $newFolderScriptBlock = [scriptblock]::Create($newFolderString)

            $serverArgListExchangeInstallDirectory = @()
            $serverArgListDirectoriesToCreate = @()
            $serverArgListExchangeResideData = @()
            $localServerTempLocation = "{0}{1}\Exchange_Server_Data_Temp\" -f $Script:RootFilePath, $env:COMPUTERNAME

            #Need to do two loops as both of these actions are required before we can do actions in the next loop.
            foreach ($serverData in $exchangeServerData) {
                $serverName = $serverData.ServerName

                $serverArgListExchangeInstallDirectory += [PSCustomObject]@{
                    ServerName   = $serverName
                    ArgumentList = $true
                }

                $serverArgListDirectoriesToCreate += [PSCustomObject]@{
                    ServerName   = $serverName
                    ArgumentList = [PSCustomObject]@{
                        NewFolders = (@(
                                ("{0}{1}\Exchange_Server_Data\Config" -f $Script:RootFilePath, $serverName),
                                ("{0}{1}\Exchange_Server_Data\WebAppPools" -f $Script:RootFilePath, $serverName)
                            ))
                    }
                }
            }

            Write-ScriptDebug ("Calling job for Get Exchange Install Directory")
            $serverInstallDirectories = Start-JobManager -ServersWithArguments $serverArgListExchangeInstallDirectory -ScriptBlock $getExchangeInstallDirectoryScriptBlock `
                -NeedReturnData $true `
                -DisplayReceiveJobInCorrectFunction $true `
                -JobBatchName "Exchange Install Directories for Write-LargeDataObjectsOnMachine"

            Write-ScriptDebug("Calling job for folder creation")
            Start-JobManager -ServersWithArguments $serverArgListDirectoriesToCreate -ScriptBlock $newFolderScriptBlock `
                -DisplayReceiveJobInCorrectFunction $true `
                -JobBatchName "Creating folders for Write-LargeDataObjectsOnMachine"

            #Now do the rest of the actions
            foreach ($serverData in $exchangeServerData) {
                $serverName = $serverData.ServerName

                $saveToLocation = "{0}{1}\Exchange_Server_Data" -f $Script:RootFilePath, $serverName
                $serverArgListExchangeResideData += [PSCustomObject]@{
                    ServerName   = $serverName
                    ArgumentList = [PSCustomObject]@{
                        SaveToLocation   = $saveToLocation
                        InstallDirectory = $serverInstallDirectories[$serverName]
                    }
                }

                #Write out the Exchange object data locally as a temp and copy it over to the remote server
                $location = "{0}{1}\Exchange_Server_Data" -f $Script:RootFilePath, $serverName
                Write-ScriptDebug("Location of data should be at: {0}" -f $location)
                $remoteLocation = "\\{0}\{1}" -f $serverName, $location.Replace(":", "$")
                Write-ScriptDebug("Remote Copy Location: {0}" -f $remoteLocation)
                $rootTempLocation = "{0}{1}" -f $localServerTempLocation, $serverName
                Write-ScriptDebug("Local Root Temp Location: {0}" -f $rootTempLocation)
                #Create the temp location and write out the data
                New-Folder -NewFolders $rootTempLocation
                Write-ExchangeObjectDataLocal -ServerData $serverData -Location $rootTempLocation
                Get-ChildItem $rootTempLocation |
                    ForEach-Object {
                        Copy-Item $_.VersionInfo.FileName $remoteLocation
                    }
            }

            #Remove the temp data location right away
            Remove-Item $localServerTempLocation -Force -Recurse

            Write-ScriptDebug("Calling Invoke-ExchangeResideDataCollectionWrite")
            Start-JobManager -ServersWithArguments $serverArgListExchangeResideData -ScriptBlock ${Function:Invoke-ExchangeResideDataCollectionWrite} `
                -DisplayReceiveJob $false `
                -JobBatchName "Write the data for Write-LargeDataObjectsOnMachine"
        } else {

            if ($null -eq $ExInstall) {
                $ExInstall = Get-ExchangeInstallDirectory
            }
            $location = "{0}{1}\Exchange_Server_Data" -f $Script:RootFilePath, $exchangeServerData.ServerName
            [array]$createFolders = @(("{0}\Config" -f $location), ("{0}\WebAppPools" -f $location))
            New-Folder -NewFolders $createFolders -IncludeDisplayCreate $true
            Write-ExchangeObjectDataLocal -Location $location -ServerData $exchangeServerData

            $passInfo = [PSCustomObject]@{
                SaveToLocation   = $location
                InstallDirectory = $ExInstall
            }

            Write-ScriptDebug("Writing out the Exchange data")
            Invoke-ExchangeResideDataCollectionWrite -PassedInfo $passInfo
        }
    }
}