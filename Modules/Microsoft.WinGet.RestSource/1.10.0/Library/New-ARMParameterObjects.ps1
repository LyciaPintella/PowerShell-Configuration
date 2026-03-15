# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
Function New-ARMParameterObjects
{
    <#
    .SYNOPSIS
    Creates the parameter files, and an object which points to both the created parameter and template files.

    .DESCRIPTION
    Creates a new PowerShell object that contains the Azure Resource type, name, and parameter values. Once created it'll
    output the parameter files into a *.json file that can be used in combination with with template files to build Azure
    resources required for hosting a Windows Package Manager REST source. Returns the PowerShell object.

    .PARAMETER ParameterFolderPath
    Path to the directory where the Parameter files will be created.

    .PARAMETER TemplateFolderPath
    Path to the directory containing the Template files.

    .PARAMETER Name
    The name of the objects to be created.

    .PARAMETER Region
    The Azure location where objects will be created in.

    .PARAMETER ImplementationPerformance
    ["Developer", "Basic", "Enhanced"] specifies the performance of the resources to be created for the Windows Package Manager REST source.

    .PARAMETER PublisherName
    [Optional] The WinGet rest source publisher name

    .PARAMETER PublisherEmail
    [Optional] The WinGet rest source publisher email

    .PARAMETER RestSourceAuthentication
    [Optional] ["None", "MicrosoftEntraId"] The WinGet rest source authentication type. (Default: None)

    .PARAMETER MicrosoftEntraIdResource
    [Optional] Microsoft Entra Id authentication resource

    .PARAMETER MicrosoftEntraIdResourceScope
    [Optional] Microsoft Entra Id authentication resource scope

    .PARAMETER ForUpdate
    [Optional] The operation is for update. (Default: False)

    .EXAMPLE
    New-ARMParameterObjects -ParameterFolderPath "C:\WinGet\Parameters" -TemplateFolderPath "C:\WinGet\Templates" -Name "contosorestsource" -AzLocation "westus" -ImplementationPerformance "Developer"

    Creates the Parameter files required for the creation of the ARM objects.

    #>
    PARAM(
        [Parameter(Position=0, Mandatory=$true)] [string]$ParameterFolderPath,
        [Parameter(Position=1, Mandatory=$true)] [string]$TemplateFolderPath,
        [Parameter(Position=2, Mandatory=$true)] [string]$Name,
        [Parameter(Position=3, Mandatory=$true)] [string]$Region,
        [Parameter(Position=4, Mandatory=$true)] [string]$ImplementationPerformance,
        [Parameter(Mandatory=$false)] [string]$PublisherName = "",
        [Parameter(Mandatory=$false)] [string]$PublisherEmail = "",
        [ValidateSet("None", "MicrosoftEntraId")]
        [Parameter(Mandatory=$false)] [string]$RestSourceAuthentication = "None",
        [Parameter(Mandatory=$false)] [string]$MicrosoftEntraIdResource = "",
        [Parameter(Mandatory=$false)] [string]$MicrosoftEntraIdResourceScope = "",
        [Parameter()] [switch]$ForUpdate
    )

    $ARMObjects = @()

    ## The Names that are to be assigned to each resource.
    $LogAnalyticsName   = "log-" + $Name -replace "[^a-zA-Z0-9-]", ""
    $AppInsightsName    = "appi-" + $Name -replace "[^a-zA-Z0-9-]", ""
    $KeyVaultName       = "kv-" + $Name -replace "[^a-zA-Z0-9-]", ""
    $StorageAccountName = "st" + $Name.ToLower() -replace "[^a-z0-9]", ""
    $AspName            = "asp-" + $Name -replace "[^a-zA-Z0-9-]", ""
    $CDBAccountName     = "cosmos-" + $Name.ToLower() -replace "[^a-z0-9-]", ""
    $FunctionName       = "func-" + $Name -replace "[^a-zA-Z0-9-]", ""
    $AppConfigName      = "appcs-" + $Name -replace "[^a-zA-Z0-9-]", ""
    $ApiManagementName  = "apim-" + $Name -replace "[^a-zA-Z0-9-]", ""
    $ServerIdentifier   = "WinGetRestSource-" + $Name -replace "[^a-zA-Z0-9-]", ""

    ## Not supported in deployment script
    ## $FrontDoorName   = ""
    ## $AspGenevaName   = ""

    ## The names of the Azure Cosmos Database and Container - Do not change (Must match with the values in the compiled
    ## Windows Package Manager Functions [WinGet.RestSource.Functions.zip])
    $CDBDatabaseName    = "WinGet"
    $CDBContainerName   = "Manifests"

    if ($RestSourceAuthentication -eq "MicrosoftEntraId") {
        $ServerAuthenticationType = "microsoftEntraId"
        $QueryApiValidationEnabled = $true
    }
    else {
        $ServerAuthenticationType = "none"
        $MicrosoftEntraIdResource = ""
        $MicrosoftEntraIdResourceScope = ""
        $QueryApiValidationEnabled = $false
    }

    ## The values required for Function ARM Template. But not supported in deployment script.
    $ManifestCacheEndpoint      = ""
    $MonitoringTenant           = ""
    $MonitoringRole             = ""
    $MonitoringMetricsAccount   = ""
    $RunFromPackageUrl          = ""

    ## Relative Path from the Working Directory to the Azure ARM Template Files
    $TemplateLogAnalyticsPath   = "$TemplateFolderPath\loganalytics.json"
    $TemplateAppInsightsPath    = "$TemplateFolderPath\applicationinsights.json"
    $TemplateKeyVaultPath       = "$TemplateFolderPath\keyvault.json"
    $TemplateStorageAccountPath = "$TemplateFolderPath\storageaccount.json"
    $TemplateASPPath            = "$TemplateFolderPath\asp.json"
    $TemplateCDBAccountPath     = "$TemplateFolderPath\cosmosdb.json"
    $TemplateCDBPath            = "$TemplateFolderPath\cosmosdb-sql.json"
    $TemplateCDBContainerPath   = "$TemplateFolderPath\cosmosdb-sql-container.json"
    $TemplateFunctionPath       = "$TemplateFolderPath\azurefunction.json"
    $TemplateAppConfigPath      = "$TemplateFolderPath\appconfig.json"
    $TemplateApiManagementPath  = "$TemplateFolderPath\apimanagement.json"

    $ParameterLogAnalyticsPath   = "$ParameterFolderPath\loganalytics.json"
    $ParameterAppInsightsPath    = "$ParameterFolderPath\applicationinsights.json"
    $ParameterKeyVaultPath       = "$ParameterFolderPath\keyvault.json"
    $ParameterStorageAccountPath = "$ParameterFolderPath\storageaccount.json"
    $ParameterASPPath            = "$ParameterFolderPath\asp.json"
    $ParameterCDBAccountPath     = "$ParameterFolderPath\cosmosdb.json"
    $ParameterCDBPath            = "$ParameterFolderPath\cosmosdb-sql.json"
    $ParameterCDBContainerPath   = "$ParameterFolderPath\cosmosdb-sql-container.json"
    $ParameterFunctionPath       = "$ParameterFolderPath\azurefunction.json"
    $ParameterAppConfigPath      = "$ParameterFolderPath\appconfig.json"
    $ParameterApiManagementPath  = "$ParameterFolderPath\apimanagement.json"

    Write-Verbose -Message "ARM Parameter Resource performance is based on the: $ImplementationPerformance."

    $PrimaryRegion       = $(Get-AzLocation).Where({$_.Location -eq $Region})
    $PrimaryRegionName   = $PrimaryRegion.DisplayName
    if ($PrimaryRegion.PairedRegion.Length -gt 0) {
        $SecondaryRegionName = $(Get-AzLocation).Where({$_.Location -eq $PrimaryRegion.PairedRegion[0].Name}).DisplayName
    }

    Write-Verbose -Message "Retrieving the Azure Tenant and User Information"
    $AzContext = Get-AzContext
    $AzTenantID = $AzContext.Tenant.Id
    $AzTenantDomain = $AzContext.Tenant.Domains[0]

    if ($AzContext.Account.Type -eq "User") {
        $LocalDeployment = $true
        $AzObjectID = $(Get-AzADUser -SignedIn).Id
        if (!$PublisherEmail) {
            $PublisherEmail = $AzContext.Account.Id
        }
        if (!$PublisherName) {
            $PublisherName = $AzContext.Account.Id
        }
    }
    else {
        $LocalDeployment = $false
        $AzObjectID = $(Get-AzADServicePrincipal -ApplicationId $AzContext.Account.ID).Id
        if (!$PublisherEmail) {
            $PublisherEmail = "WinGetRestSource@$AzTenantDomain"
        }
        if (!$PublisherName) {
            $PublisherName = "WinGetRestSource@$AzTenantDomain"
        }
    }
    Write-Verbose -Message "Retrieved the Azure Object Id: $AzObjectID"

    $AzEnvironment = Get-AzEnvironment -Name $AzContext.Environment.Name
    $blobStorageServiceUri  = "https://" + $StorageAccountName + ".blob." + $AzEnvironment.StorageEndpointSuffix
    $queueStorageServiceUri = "https://" + $StorageAccountName + ".queue." + $AzEnvironment.StorageEndpointSuffix
    $tableStorageServiceUri = "https://" + $StorageAccountName + ".table." + $AzEnvironment.StorageEndpointSuffix
    $keyVaultServiceUri     = "https://" + $KeyVaultName + "." + $AzEnvironment.AzureKeyVaultDnsSuffix

    switch ($ImplementationPerformance) {
        "Developer" {
            $AppConfigSku = "Free"
            $KeyVaultSKU  = "Standard"
            $StorageAccountPerformance = "Standard_LRS"
            $AspSku = "B1"
            $CosmosDBAEnableFreeTier   = $true
            ## To enable Serverless then set CosmosDBACapatilities to "[{"name": ""EnableServerless""}]"
            $CosmosDBACapabilities     = "[]"
            $CosmosDBAConsistency      = "ConsistentPrefix"
            $CosmosDBALocations = @(
                            @{
                                locationName     = $PrimaryRegionName
                                failoverPriority = 0
                                isZoneRedundant  = $false
                            }
                        )
            $ApiManagementSku = "Developer"
        }
        "Basic" {
            $AppConfigSku = "Standard"
            $KeyVaultSKU  = "Standard"
            $StorageAccountPerformance = "Standard_GRS"
            $AspSku = "S1"
            $CosmosDBAEnableFreeTier   = $false
            ## To enable Serverless then set CosmosDBACapatilities to "[{"name": ""EnableServerless""}]"
            $CosmosDBACapabilities     = "[]"
            $CosmosDBAConsistency      = "Session"
            $CosmosDBALocations = @(
                            @{
                                locationName     = $PrimaryRegionName
                                failoverPriority = 0
                                isZoneRedundant  = $false
                            }
                        )
            if ($SecondaryRegionName) {
                $CosmosDBALocations += @{
                                locationName     = $SecondaryRegionName
                                failoverPriority = 1
                                isZoneRedundant  = $false
                            }
            }
            $ApiManagementSku = "Basic"
        }
        "Enhanced" {
            $AppConfigSku = "Standard"
            $KeyVaultSKU  = "Standard"
            $StorageAccountPerformance = "Standard_GRS"
            $AspSku = "P1V2"
            $CosmosDBAEnableFreeTier   = $false
            ## To enable Serverless then set CosmosDBACapatilities to "[{"name": ""EnableServerless""}]"
            $CosmosDBACapabilities     = "[]"
            $CosmosDBAConsistency      = "Session"
            $CosmosDBALocations = @(
                            @{
                                locationName     = $PrimaryRegionName
                                failoverPriority = 0
                                isZoneRedundant  = $false
                            }
                        )
            if ($SecondaryRegionName) {
                $CosmosDBALocations += @{
                                locationName     = $SecondaryRegionName
                                failoverPriority = 1
                                isZoneRedundant  = $false
                            }
            }
            $ApiManagementSku = "Standard"
        }
    }

    ## This is specific to the JSON file creation
    $JSONContentVersion = "1.0.0.0"
    $JSONSchema         = "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#"

    ## Creates a PowerShell object array to contain the details of the Parameter files.
    $ARMObjects = @(
        @{  ObjectType = "LogAnalytics"
            ObjectName = $LogAnalyticsName
            ParameterPath  = "$ParameterLogAnalyticsPath"
            TemplatePath   = "$TemplateLogAnalyticsPath"
            Error      = ""
            Parameters = @{
                '$Schema' = $JSONSchema
                contentVersion = $JSONContentVersion
                Parameters = @{
                    name       = @{ value = $LogAnalyticsName }
                }
            }
        },
        @{  ObjectType = "AppInsight"
            ObjectName = $AppInsightsName
            ParameterPath  = "$ParameterAppInsightsPath"
            TemplatePath   = "$TemplateAppInsightsPath"
            Error      = ""
            Parameters = @{
                '$Schema' = $JSONSchema
                contentVersion = $JSONContentVersion
                Parameters = @{
                    name       = @{ value = $AppInsightsName }
                    location   = @{ value = $Region }
                    workspaceResourceName = @{ value = $LogAnalyticsName }
                }
            }
        },
        @{  ObjectType = "Keyvault"
            ObjectName = $KeyVaultName
            ParameterPath  = "$ParameterKeyVaultPath"
            TemplatePath   = "$TemplateKeyVaultPath"
            Error      = ""
            Parameters = @{
                '$Schema' = $JSONSchema
                contentVersion = $JSONContentVersion
                Parameters = @{
                    name            = @{ value = $KeyVaultName }
                    location        = @{ value = $Region }
                    sku             = @{ value = $KeyVaultSKU }
                    accessPolicies  = @{
                        value = @(
                            @{
                                tenantId = $AzTenantID
                                objectID = $AzObjectID
                                permissions = @{
                                    keys         = @()
                                    secrets      = @( "Get", "Set" )
                                    certificates = @()
                                }
                            }
                        )
                    }
                }
            }
        },
        @{  ObjectType = "AppConfig"
            ObjectName = $FunctionName
            ParameterPath  = "$ParameterAppConfigPath"
            TemplatePath   = "$TemplateAppConfigPath"
            Error      = ""
            Parameters = @{
                '$Schema' = $JSONSchema
                contentVersion = $JSONContentVersion
                Parameters = @{
                    appConfigName           = @{ value = $appConfigName         }   # Name used to contain the Storage Account connection string in the Key Value
                    location                = @{ value = $Region                }   # Azure hosting location
                    sku                     = @{ value = $AppConfigSku          }
                    localDeployment         = @{ value = $LocalDeployment       }
                }
            }
        },
        @{  ObjectType = "StorageAccount"
            ObjectName = $StorageAccountName
            ParameterPath  = "$ParameterStorageAccountPath"
            TemplatePath   = "$TemplateStorageAccountPath"
            Error      = ""
            Parameters = @{
                '$Schema' = $JSONSchema
                contentVersion = $JSONContentVersion
                Parameters = @{
                    location           = @{ value = $Region }
                    storageAccountName = @{ value = $StorageAccountName }
                    accountType        = @{ value = $StorageAccountPerformance }
                }
            }
        },
        @{  ObjectType = "asp"
            ObjectName = $aspName
            ParameterPath  = "$ParameterASPPath"
            TemplatePath   = "$TemplateASPPath"
            Error      = ""
            Parameters = @{
                '$Schema' = $JSONSchema
                contentVersion = $JSONContentVersion
                Parameters = @{
                    aspName         = @{ value = $aspName }
                    location        = @{ value = $Region }
                    skuCode         = @{ value = $AspSku }
                }
            }
        },
        @{  ObjectType = "CosmosDBAccount"
            ObjectName = $CDBAccountName
            ParameterPath  = "$ParameterCDBAccountPath"
            TemplatePath   = "$TemplateCDBAccountPath"
            Error      = ""
            Parameters = @{
                '$Schema' = $JSONSchema
                contentVersion = $JSONContentVersion
                Parameters = @{
                    name = @{ value = $CDBAccountName }
                    location = @{ value = $Region }
                    enableFreeTier = @{ value = $CosmosDBAEnableFreeTier }
                    consistencyPolicy = @{
                        value = @{
                            defaultConsistencyLevel = $CosmosDBAConsistency
                            maxIntervalInSeconds    = 5
                            maxStalenessPrefix      = 100
                        }
                    }
                    locations = @{ value = $CosmosDBALocations }
                    backupPolicy = @{
                        value = @{
                            type = "Periodic"
                            periodicModeProperties = @{
                                backupIntervalInMinutes        = 240
                                backupRetentionIntervalInHours = 720
                            }
                        }
                    }
                }
            }
        },
        @{  ObjectType = "CosmosDBDatabase"
            ObjectName = $CDBDatabaseName
            ParameterPath  = "$ParameterCDBPath"
            TemplatePath   = "$TemplateCDBPath"
            Error      = ""
            Parameters = @{
                '$Schema' = $JSONSchema
                contentVersion = $JSONContentVersion
                Parameters = @{
                    cosmosName = @{ value = $CDBAccountName }
                    sqlname    = @{ value = $CDBDatabaseName }
                    options    = @{
                        Value  = @{
                            autoscaleSettings = @{
                                maxThroughput = 4000
                            }
                        }
                    }
                }
            }
        },
        @{  ObjectType = "CosmosDBContainer"
            ObjectName = $CDBContainerName
            ParameterPath  = "$ParameterCDBContainerPath"
            TemplatePath   = "$TemplateCDBContainerPath"
            Error      = ""
            Parameters = @{
                '$Schema' = $JSONSchema
                contentVersion = $JSONContentVersion
                Parameters = @{
                    cosmosName     = @{ Value = $CDBAccountName }
                    sqlname        = @{ Value = $CDBDatabaseName }
                    containerName  = @{ value = $CDBContainerName}
                    indexingPolicy = @{ Value = @{
                        IndexingMode  = "consistent"
                        automatic     = $true
                        includedPaths = @(@{
                            path = "/*"
                        })
                        excludePaths = @(@{
                            path = '/"_etag"/?'
                        })
                    }}
                    partitionKey = @{
                        value = @{
                            paths = @("/id")
                            kind = "Hash"
                        }
                    }
                    conflictResolutionPolicy = @{
                        value = @{
                            mode = "LastWriterWins"
                            conflictResolutionPath = "/_ts"
                        }
                    }
                }
            }
        },
        @{  ObjectType = "Function"
            ObjectName = $FunctionName
            ParameterPath  = "$ParameterFunctionPath"
            TemplatePath   = "$TemplateFunctionPath"
            Error      = ""
            Parameters = @{
                '$Schema' = $JSONSchema
                contentVersion = $JSONContentVersion
                Parameters = @{
                    location                 = @{ value = $Region                   }   # Azure hosting location
                    cosmosDatabase           = @{ value = $CDBDatabaseName          }   # Cosmos Database Name
                    cosmosContainer          = @{ value = $CDBContainerName         }   # Cosmos Container Name
                    serverIdentifier         = @{ value = $ServerIdentifier         }   # Azure Function Server Identifier
                    functionName             = @{ value = $FunctionName             }   # Azure Function Name
                    appServiceName           = @{ value = $aspName                  }   # Azure App Service Name
                    keyVaultServiceUri       = @{ value = $keyVaultServiceUri       }   # Azure Keyvault Uri
                    blobStorageServiceUri    = @{ value = $blobStorageServiceUri    }   # Azure Blob Storage Uri
                    queueStorageServiceUri   = @{ value = $queueStorageServiceUri   }   # Azure Queue Storage Uri
                    tableStorageServiceUri   = @{ value = $tableStorageServiceUri   }   # Azure Table Storage Uri
                    appInsightName           = @{ value = $AppInsightsName          }   # Azure App Insights Name
                    manifestCacheEndpoint    = @{ value = $manifestCacheEndpoint    }   # Not suported
                    monitoringTenant         = @{ value = $monitoringTenant         }   # Not suported
                    monitoringRole           = @{ value = $monitoringRole           }   # Not suported
                    monitoringMetricsAccount = @{ value = $monitoringMetricsAccount }   # Not suported
                    runFromPackageUrl        = @{ value = $RunFromPackageUrl        }   # Not suported
                    serverAuthenticationType = @{ value = $ServerAuthenticationType }   # Server authentication type
                    microsoftEntraIdResource = @{ value = $MicrosoftEntraIdResource }   # Microsoft Entra Id Resource
                    microsoftEntraIdResourceScope = @{ value = $MicrosoftEntraIdResourceScope }  # Microsoft Entra Id Resource Scope
                }
            }
        },
        @{  ObjectType = "ApiManagement"
            ObjectName = $ApiManagementName
            ParameterPath  = "$ParameterApiManagementPath"
            TemplatePath   = "$TemplateApiManagementPath"
            Error      = ""
            Parameters = @{
                '$Schema' = $JSONSchema
                contentVersion = $JSONContentVersion
                Parameters = @{
                    serviceName = @{ value = $ApiManagementName }
                    publisherEmail = @{ value = $PublisherEmail }
                    publisherName = @{ value = $PublisherName }
                    sku = @{ value = $ApiManagementSku }
                    location = @{ value = $Region }
                    keyVaultServiceUri = @{ value = $keyVaultServiceUri }
                    backendUrls = @{ value = @() }  # Value to be populated after Azure Function is created
                    queryApiValidationEnabled = @{ value = $QueryApiValidationEnabled }
                    microsoftEntraIdResource = @{ value = $MicrosoftEntraIdResource }
                }
            }
        }
    )

    ## Uses the newly created ARMObjects[#].Parameters to create new JSON Parameter files.
    Write-Verbose -Message "Creating JSON Parameter files for Azure Object Creation:"

    ## Creates each JSON Parameter file inside of a Parameter folder in the working directory
    foreach ($object in $ARMObjects) {
        ## Converts the structure of the variable to a JSON file.
        Write-Verbose -Message "Creating the Parameter file for $($Object.ObjectType) in the following location: $($Object.ParameterPath)"

        if ($ForUpdate -and (Test-Path -Path $Object.ParameterPath)) {
            $Object.Parameters = Get-Content -Path $Object.ParameterPath -Raw | ConvertFrom-Json
        }
        else {
            $ParameterFileContent = $Object.Parameters | ConvertTo-Json -Depth 8
            $ParameterFileContent | Out-File -FilePath $Object.ParameterPath -Force
        }
    }

    ## Returns the completed object.
    return $ARMObjects
}

# SIG # Begin signature block
# MIIoUgYJKoZIhvcNAQcCoIIoQzCCKD8CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBPZmdnILiKJain
# bzF5CpzpNRPH1sBUMRM8qAZW+zhY86CCDYUwggYDMIID66ADAgECAhMzAAAEhJji
# EuB4ozFdAAAAAASEMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjUwNjE5MTgyMTM1WhcNMjYwNjE3MTgyMTM1WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDtekqMKDnzfsyc1T1QpHfFtr+rkir8ldzLPKmMXbRDouVXAsvBfd6E82tPj4Yz
# aSluGDQoX3NpMKooKeVFjjNRq37yyT/h1QTLMB8dpmsZ/70UM+U/sYxvt1PWWxLj
# MNIXqzB8PjG6i7H2YFgk4YOhfGSekvnzW13dLAtfjD0wiwREPvCNlilRz7XoFde5
# KO01eFiWeteh48qUOqUaAkIznC4XB3sFd1LWUmupXHK05QfJSmnei9qZJBYTt8Zh
# ArGDh7nQn+Y1jOA3oBiCUJ4n1CMaWdDhrgdMuu026oWAbfC3prqkUn8LWp28H+2S
# LetNG5KQZZwvy3Zcn7+PQGl5AgMBAAGjggGCMIIBfjAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUBN/0b6Fh6nMdE4FAxYG9kWCpbYUw
# VAYDVR0RBE0wS6RJMEcxLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEWMBQGA1UEBRMNMjMwMDEyKzUwNTM2MjAfBgNVHSMEGDAW
# gBRIbmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIw
# MTEtMDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDEx
# XzIwMTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIB
# AGLQps1XU4RTcoDIDLP6QG3NnRE3p/WSMp61Cs8Z+JUv3xJWGtBzYmCINmHVFv6i
# 8pYF/e79FNK6P1oKjduxqHSicBdg8Mj0k8kDFA/0eU26bPBRQUIaiWrhsDOrXWdL
# m7Zmu516oQoUWcINs4jBfjDEVV4bmgQYfe+4/MUJwQJ9h6mfE+kcCP4HlP4ChIQB
# UHoSymakcTBvZw+Qst7sbdt5KnQKkSEN01CzPG1awClCI6zLKf/vKIwnqHw/+Wvc
# Ar7gwKlWNmLwTNi807r9rWsXQep1Q8YMkIuGmZ0a1qCd3GuOkSRznz2/0ojeZVYh
# ZyohCQi1Bs+xfRkv/fy0HfV3mNyO22dFUvHzBZgqE5FbGjmUnrSr1x8lCrK+s4A+
# bOGp2IejOphWoZEPGOco/HEznZ5Lk6w6W+E2Jy3PHoFE0Y8TtkSE4/80Y2lBJhLj
# 27d8ueJ8IdQhSpL/WzTjjnuYH7Dx5o9pWdIGSaFNYuSqOYxrVW7N4AEQVRDZeqDc
# fqPG3O6r5SNsxXbd71DCIQURtUKss53ON+vrlV0rjiKBIdwvMNLQ9zK0jy77owDy
# XXoYkQxakN2uFIBO1UNAvCYXjs4rw3SRmBX9qiZ5ENxcn/pLMkiyb68QdwHUXz+1
# fI6ea3/jjpNPz6Dlc/RMcXIWeMMkhup/XEbwu73U+uz/MIIHejCCBWKgAwIBAgIK
# YQ6Q0gAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEw
# OTA5WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYD
# VQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+la
# UKq4BjgaBEm6f8MMHt03a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc
# 6Whe0t+bU7IKLMOv2akrrnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4D
# dato88tt8zpcoRb0RrrgOGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+
# lD3v++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nk
# kDstrjNYxbc+/jLTswM9sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6
# A4aN91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmd
# X4jiJV3TIUs+UsS1Vz8kA/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL
# 5zmhD+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zd
# sGbiwZeBe+3W7UvnSSmnEyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3
# T8HhhUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS
# 4NaIjAsCAwEAAaOCAe0wggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRI
# bmTlUAXTgqoXNzcitW2oynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAL
# BgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBD
# uRQFTuHqp8cx0SOJNDBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3JsMF4GCCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3J0MIGfBgNVHSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1h
# cnljcHMuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkA
# YwB5AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn
# 8oalmOBUeRou09h0ZyKbC5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7
# v0epo/Np22O/IjWll11lhJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0b
# pdS1HXeUOeLpZMlEPXh6I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/
# KmtYSWMfCWluWpiW5IP0wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvy
# CInWH8MyGOLwxS3OW560STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBp
# mLJZiWhub6e3dMNABQamASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJi
# hsMdYzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYb
# BL7fQccOKO7eZS/sl/ahXJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbS
# oqKfenoi+kiVH6v7RyOA9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sL
# gOppO6/8MO0ETI7f33VtY5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtX
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGiMwghofAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAASEmOIS4HijMV0AAAAA
# BIQwDQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIO/4
# gTzwcH+jguaOYRWzSPlPrCXiRt0/DFT3HbYyjv44MEIGCisGAQQBgjcCAQwxNDAy
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20wDQYJKoZIhvcNAQEBBQAEggEAfF9RhOMYbCuNK/6c+w//Q+fmIS/svUXACD6V
# tR11s1aI+h5DPKbLxv3BDdhtD2AbzbH0cXVVJKpunYGXPP4Dmgnbkcf41KaPnF6H
# ewv6FZoEiPDDeYHfxggd9a6Hs6ktzq00RaBg3vVDOe/atD3j76J5mP3c1HgG5UXf
# cwmoRjQZWA3U6zhzOC2wnUbypvDgbNzGVvcsbrMbcTyMwXZmBJr8ZXSn64sEQWt/
# qz7fzeGNpGQOpmPDAlE8b/UyKJVP1d0z5xSMaW0KnANYt0OrV0W45M0i+JkXTamA
# CYu48bp327jJRgn3k75bTcTT7kMlcvN4Km9eLiC2fNshMb32+aGCF60wghepBgor
# BgEEAYI3AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheCAgEDMQ8wDQYJYIZI
# AWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGE
# WQoDATAxMA0GCWCGSAFlAwQCAQUABCBiLo+XQceca3ubNE9JlI+yqeXPON2Iu2bV
# A3aET/RlbQIGaHpt0JsZGBMyMDI1MDcyNTAwMTMxNi4zNjZaMASAAgH0oIHZpIHW
# MIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQL
# EyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsT
# Hm5TaGllbGQgVFNTIEVTTjo2RjFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEfswggcoMIIFEKADAgECAhMzAAAB/Big
# r8xpWoc6AAEAAAH8MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwMB4XDTI0MDcyNTE4MzExNFoXDTI1MTAyMjE4MzExNFowgdMxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jv
# c29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
# ZCBUU1MgRVNOOjZGMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# p1DAKLxpbQcPVYPHlJHyW7W5lBZjJWWDjMfl5WyhuAylP/LDm2hb4ymUmSymV0EF
# RQcmM8BypwjhWP8F7x4iO88d+9GZ9MQmNh3jSDohhXXgf8rONEAyfCPVmJzM7yts
# urZ9xocbuEL7+P7EkIwoOuMFlTF2G/zuqx1E+wANslpPqPpb8PC56BQxgJCI1LOF
# 5lk3AePJ78OL3aw/NdlkvdVl3VgBSPX4Nawt3UgUofuPn/cp9vwKKBwuIWQEFZ83
# 7GXXITshd2Mfs6oYfxXEtmj2SBGEhxVs7xERuWGb0cK6afy7naKkbZI2v1UqsxuZ
# t94rn/ey2ynvunlx0R6/b6nNkC1rOTAfWlpsAj/QlzyM6uYTSxYZC2YWzLbbRl0l
# RtSz+4TdpUU/oAZSB+Y+s12Rqmgzi7RVxNcI2lm//sCEm6A63nCJCgYtM+LLe9pT
# shl/Wf8OOuPQRiA+stTsg89BOG9tblaz2kfeOkYf5hdH8phAbuOuDQfr6s5Ya6W+
# vZz6E0Zsenzi0OtMf5RCa2hADYVgUxD+grC8EptfWeVAWgYCaQFheNN/ZGNQMkk7
# 8V63yoPBffJEAu+B5xlTPYoijUdo9NXovJmoGXj6R8Tgso+QPaAGHKxCbHa1QL9A
# SMF3Os1jrogCHGiykfp1dKGnmA5wJT6Nx7BedlSDsAkCAwEAAaOCAUkwggFFMB0G
# A1UdDgQWBBSY8aUrsUazhxByH79dhiQCL/7QdjAfBgNVHSMEGDAWgBSfpxVdAF5i
# XYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRp
# bWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1Ud
# JQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsF
# AAOCAgEAT7ss/ZAZ0bTaFsrsiJYd//LQ6ImKb9JZSKiRw9xs8hwk5Y/7zign9gGt
# weRChC2lJ8GVRHgrFkBxACjuuPprSz/UYX7n522JKcudnWuIeE1p30BZrqPTOnsc
# D98DZi6WNTAymnaS7it5qAgNInreAJbTU2cAosJoeXAHr50YgSGlmJM+cN6mYLAL
# 6TTFMtFYJrpK9TM5Ryh5eZmm6UTJnGg0jt1pF/2u8PSdz3dDy7DF7KDJad2qHxZO
# RvM3k9V8Yn3JI5YLPuLso2J5s3fpXyCVgR/hq86g5zjd9bRRyyiC8iLIm/N95q6H
# WVsCeySetrqfsDyYWStwL96hy7DIyLL5ih8YFMd0AdmvTRoylmADuKwE2TQCTvPn
# jnLk7ypJW29t17Yya4V+Jlz54sBnPU7kIeYZsvUT+YKgykP1QB+p+uUdRH6e79Va
# iz+iewWrIJZ4tXkDMmL21nh0j+58E1ecAYDvT6B4yFIeonxA/6Gl9Xs7JLciPCIC
# 6hGdliiEBpyYeUF0ohZFn7NKQu80IZ0jd511WA2bq6x9aUq/zFyf8Egw+dunUj1K
# tNoWpq7VuJqapckYsmvmmYHZXCjK1Eus7V1I+aXjrBYuqyM9QpeFZU4U01YG15uW
# wUCaj0uZlah/RGSYMd84y9DCqOpfeKE6PLMk7hLnhvcOQrnxP6kwggdxMIIFWaAD
# AgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3Nv
# ZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0yMTA5MzAxODIy
# MjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciELeaLL1yR5
# vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5KWv64
# NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTegCjhu
# je3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7M62AW36MEBydUv626GIl
# 3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPg
# yY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy1cCGMFxPLOJiss254o2I
# 5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2
# ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP8BDyt0cY7afomXw/
# TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy
# 16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb0f2y
# 1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV2xo3xwgVGD94q0W29R6H
# XtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcVAQQFAgMB
# AAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0GA1UdDgQW
# BBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdMg30B
# ATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3Bz
# L0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYB
# BAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMB
# Af8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBL
# oEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMv
# TWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggr
# BgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNS
# b29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcNAQELBQADggIBAJ1Vffwq
# reEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1OW27
# DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYAA7AFvonoaeC6Ce5732pv
# vinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihVJ9Ak
# vUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZUnWK
# NsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2
# kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k+SS+
# c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep
# 8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9y8FBSX5+k77L+Dvk
# txW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1Zyvg
# DbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ8cirOoo6CGJ/
# 2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDVjCCAj4CAQEwggEBoYHZpIHW
# MIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQL
# EyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsT
# Hm5TaGllbGQgVFNTIEVTTjo2RjFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUATkEpJXOaqI2w
# fqBsw4NLVwqYqqqggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAx
# MDANBgkqhkiG9w0BAQsFAAIFAOws1OcwIhgPMjAyNTA3MjQxNTUxMDNaGA8yMDI1
# MDcyNTE1NTEwM1owdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA7CzU5wIBADAHAgEA
# AgIU7zAHAgEAAgIVMjAKAgUA7C4mZwIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgor
# BgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBCwUA
# A4IBAQArGFCyNIch49li6q9pCKbsr/+Nv7ADUqH5mk62eLdFDrU2+v12BS3soEDZ
# aF8/3U+r8FbfsYMLA+inEKxZUx0ZdKwmOXcx5OXbdbQgUrACaa34dqyv9D+k4+q6
# WYFaCa45vovNdqK9UCB8rf5BmpLFFmbTvoMmnT7j52tuyOoUwy58X5ltWuuR+2v3
# zu34I9dheHuC5vukqEn3f8/0nDFTKPk3x4y2Tmi7D/zCSkW7Hc1UWKLRdss4iC4Q
# keQ4vWgA6uJoSSLlZV+xOKZcxZm5k80WwWYNVb9KSyB0SMhpf83BJBHyCCzLyWOd
# zqyL3BAdUKZ7xHzkCThmnKfmNWRrMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAH8GKCvzGlahzoAAQAAAfwwDQYJYIZIAWUD
# BAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0B
# CQQxIgQgS4ArmuSFrjiTnudl3AC2WIe03oLfoygdofH133ZoVS0wgfoGCyqGSIb3
# DQEJEAIvMYHqMIHnMIHkMIG9BCCVQq+Qu+/h/BOVP4wweUwbHuCUhh+T7hq3d5MC
# aNEtYjCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAB
# /Bigr8xpWoc6AAEAAAH8MCIEIMIJF2R/u0oT81wzisJYJnU3cZH8hua21hksATOY
# PcQGMA0GCSqGSIb3DQEBCwUABIICAFWQG9ClcRblZHvFiTqXrocLnUffQRC1sZNm
# 0x/PW3h/3OXPmjjAxhqZAr0h2tkl2W8D//12Hk2Ou0uiULVuYFnfNIuRIlv8p53h
# Y85qxKAUAl6VYMyXPGWpZitHB/Y6bmdYIssV6QhabW1jxTdXgdBNXqgggYEyiL9d
# OncLsOA5Eyq2N+HgjEls7Xs+K03/zZw/Q0FB655FynnM9S2knsm49UhcnHKCB7Vd
# 8HsYFwmhdFJJjxUWWZC8BIDfVHSLUByzodbUZEaTU+6Nby1XyqCt4UzVWnvWu1Gl
# Rpx43kn3Ri8lUXzvrsU3yo6vsawmXf8KaFgYYfm4Su9V9bcHKZlvD9a4EieuCcuP
# DN9sfGIeT1VyTeqLmrAJ9HCOt0iBCmBlm6JjPpeEXB/HeAdc8QRWPVyXA3+yoqE8
# MweZVlaUL9gNLgemeVtET32xslKcl4uezrbOwSwkpw5ZzsgUgfhPEo/0qulZX7gv
# Tz9yiglit/zZDS8rP5XVj+nnPemqklbWwj09gF3inzDuOId7QOQbQVvrgFnpq4IU
# i0+L7sHGQc6mkR6atbnooD/GXsX9hWCQDsCfBSsQKZ03+GB5BSp/bRsyFhYANVOh
# /wvAmfR1tZoDaGpAnCAIwHb132XdTnUAsHKoWgv8oiPJdDc5JmW+chbsHRNrbx4L
# 1GYU79XX
# SIG # End signature block
