# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
Function New-ARMObjects
{
    <#
    .SYNOPSIS
    Creates the Azure Resources to stand-up a Windows Package Manager REST Source.

    .DESCRIPTION
    Uses the custom PowerShell object provided by the "New-ARMParameterObjects" cmdlet to create Azure resources, and will 
    create the the Key Vault secrets and publish the Windows Package Manager REST source REST apis to the Azure Function.

    .PARAMETER ARMObjects
    Object returned from the "New-ARMParameterObjects" providing the paths to the ARM Parameters and Template files.

    .PARAMETER RestSourcePath
    Path to the compiled Function ZIP containing the REST APIs

    .PARAMETER ResourceGroup
    Resource Group that will be used to create the ARM Objects in.

    .EXAMPLE
    New-ARMObjects -ARMObjects $ARMObjects -RestSourcePath "C:\WinGet-CLI-RestSource\WinGet.RestSource.Functions.zip" -ResourceGroup "WinGet"

    Parses through the $ARMObjects variable, creating all identified Azure Resources following the provided ARM Parameters and Template information.
    #>
    PARAM(
        [Parameter(Position=0, Mandatory=$true)] [array] [ref] $ARMObjects,
        [Parameter(Position=1, Mandatory=$true)] [string] $RestSourcePath,
        [Parameter(Position=2, Mandatory=$true)] [string] $ResourceGroup
    )

    # Function to create a new Function App key
    function New-FunctionAppKey
    {
        $private:characters = 'abcdefghiklmnoprstuvwxyzABCDEFGHIJKLMENOPTSTUVWXYZ'
        $private:randomChars = 1..64 | ForEach-Object { Get-Random -Maximum $characters.length }
    
        # Set the output field separator to empty instead of space
        $private:ofs=""
        return [String]$characters[$randomChars]
    }

    # Function to ensure Azure role assignment
    function Set-RoleAssignment
    {
        param(
            [string] $PrincipalId,
            [string] $RoleName,
            [string] $ResourceGroup,
            [string] $ResourceName,
            [string] $ResourceType
        )
        
        $GetAssignment = Get-AzRoleAssignment -ObjectId $PrincipalId -RoleDefinitionName $RoleName -ResourceGroupName $ResourceGroup -ResourceName $ResourceName -ResourceType $ResourceType
        if (!$GetAssignment) {
            Write-Verbose "Creating role assignment. Role: $RoleName"
            $Result = New-AzRoleAssignment -ObjectId $PrincipalId -RoleDefinitionName $RoleName -ResourceGroupName $ResourceGroup -ResourceName $ResourceName -ResourceType $ResourceType -ErrorVariable ErrorNew
            if ($ErrorNew) {
                Write-Error "Failed to set Azure role. Role: $RoleName Error: $ErrorNew"
                return $false
            }
        }

        return $true
    }

    function Get-SecureString
    {
        param(
            [string] $InputString
        )

        $Result = New-Object SecureString
        foreach ($char in $InputString.ToCharArray()) {
            $Result.AppendChar($char)
        }

        return $Result
    }

    ## TODO: Consider multiple instances of same Azure Resource in the future
    ## Azure resource names retrieved from the Parameter files.
    $StorageAccountName   = $ARMObjects.Where({$_.ObjectType -eq "StorageAccount"}).Parameters.Parameters.storageAccountName.value
    $KeyVaultName         = $ARMObjects.Where({$_.ObjectType -eq "Keyvault"}).Parameters.Parameters.name.value
    $CosmosAccountName    = $ARMObjects.Where({$_.ObjectType -eq "CosmosDBAccount"}).Parameters.Parameters.name.value
    $AppConfigName        = $ARMObjects.Where({$_.ObjectType -eq "AppConfig"}).Parameters.Parameters.appConfigName.value
    $FunctionName         = $ARMObjects.Where({$_.ObjectType -eq "Function"}).Parameters.Parameters.functionName.value

    ## Azure Keyvault Secret Names - Do not change values (Must match with values in the Template files)
    $CosmosAccountEndpointKeyName = "CosmosAccountEndpoint"
    $AzureFunctionHostKeyName = "AzureFunctionHostKey"
    $AppConfigPrimaryEndpointName = "AppConfigPrimaryEndpoint"
    $AppConfigSecondaryEndpointName = "AppConfigSecondaryEndpoint"

    ## Creates the Azure Resources following the ARM template / parameters
    Write-Information "Creating Azure Resources following ARM Templates."

    ## This is order specific, please ensure you used the New-ARMParameterObjects function to create this object in the pre-determined order.
    foreach ($Object in $ARMObjects) {
        if ($Object.DeploymentSuccess) {
            Write-Verbose "Skipped the Azure Object - $($Object.ObjectType). Deployment success detected."
            continue
        }

        Write-Information "Creating the Azure Object - $($Object.ObjectType)"

        ## Pre ARM deployment operations
        if ($Object.ObjectType -eq "Function") {
            $CosmosAccountEndpointValue = Get-SecureString($(Get-AzCosmosDBAccount -Name $CosmosAccountName -ResourceGroupName $ResourceGroup).DocumentEndpoint)
            Write-Verbose "Creating Keyvault Secret for Azure CosmosDB endpoint."
            $Result = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $CosmosAccountEndpointKeyName -SecretValue $CosmosAccountEndpointValue -ErrorVariable ErrorSet
            if ($ErrorSet) {
                Write-Error "Failed to set keyvault secret. Name: $CosmosAccountEndpointKeyName Error: $ErrorSet"
                return $false
            }

            $AppConfigEndpointValue = Get-SecureString($(Get-AzAppConfigurationStore -Name $AppConfigName -ResourceGroupName $ResourceGroup).Endpoint)
            Write-Verbose "Creating Keyvault Secret for Azure App Config endpoint."
            $Result = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AppConfigPrimaryEndpointName -SecretValue $AppConfigEndpointValue -ErrorVariable ErrorSet
            if ($ErrorSet) {
                Write-Error "Failed to set keyvault secret. Name: $AppConfigPrimaryEndpointName Error: $ErrorSet"
                return $false
            }
            $Result = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AppConfigSecondaryEndpointName -SecretValue $AppConfigEndpointValue -ErrorVariable ErrorSet
            if ($ErrorSet) {
                Write-Error "Failed to set keyvault secret. Name: $AppConfigSecondaryEndpointName Error: $ErrorSet"
                return $false
            }
        }
        elseif ($Object.ObjectType -eq "ApiManagement") {
            ## Create instance manually if not exist
            $ApiManagementParameters = $Object.Parameters.Parameters
            $ApiManagement = Get-AzApiManagement -ResourceGroupName $ResourceGroup -Name $ApiManagementParameters.serviceName.value -ErrorVariable ErrorGet -ErrorAction SilentlyContinue
            if (!$ApiManagement) {
                Write-Warning "Creating new Api Aanagement service. Name: $($ApiManagementParameters.serviceName.value)"
                Write-Warning "This is a long-running action. It can take between 30 and 40 minutes to create and activate an API Management service."
                $ApiManagement = New-AzApiManagement -ResourceGroupName $ResourceGroup -Name $ApiManagementParameters.serviceName.value -Location $ApiManagementParameters.location.value -Organization $ApiManagementParameters.publisherName.value -AdminEmail $ApiManagementParameters.publisherEmail.value -Sku $ApiManagementParameters.sku.value -SystemAssignedIdentity -ErrorVariable DeployError
                if ($DeployError) {
                    Write-Error "Failed to create Api Aanagement service. Error: $DeployError"
                    return $false
                }
            }

            ## Set secret get permission for Api Management service
            Write-Verbose "Set keyvault secret access for Api Management service"
            $Result = Set-AzKeyVaultAccessPolicy -VaultName $KeyVaultName -ResourceGroupName $ResourceGroup -ObjectId $ApiManagement.Identity.PrincipalId -PermissionsToSecrets Get -BypassObjectIdValidation -ErrorVariable ErrorSet
            if ($ErrorSet) {
                Write-Error "Failed to set keyvault secret access for Api Management Service. Error: $ErrorSet"
                return $false
            }

            ## Update backend urls and re-create parameters file if needed
            $FunctionApp = Get-AzFunctionApp -ResourceGroupName $ResourceGroup -Name $FunctionName
            $FunctionAppUrl = "https://$($FunctionApp.DefaultHostName)/api"
            if ($ApiManagementParameters.backendUrls.value.Where({$_ -eq $FunctionAppUrl}).Count -eq 0) {
                $ApiManagementParameters.backendUrls.value += $FunctionAppUrl
                Write-Verbose -Message "Re-creating the Parameter file for $($Object.ObjectType) in the following location: $($Object.ParameterPath)"
                $ParameterFile = $Object.Parameters | ConvertTo-Json -Depth 8
                $ParameterFile | Out-File -FilePath $Object.ParameterPath -Force
            }
        }

        ## ARM deployment operations
        ## Creates the Azure Resource
        $DeployResult = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroup -TemplateFile $Object.TemplatePath -TemplateParameterFile $Object.ParameterPath -Mode Incremental -ErrorVariable DeployError

        ## Verifies that no error occured when creating the Azure resource
        if ($DeployError -or ($DeployResult.ProvisioningState -ne "Succeeded" -and $DeployResult.ProvisioningState -ne "Created")) {
            $ErrReturnObject = @{
                DeployError = $DeployError
                DeployResult = $DeployResult
            }

            Write-Error "Failed to create Azure object. Error: $DeployError" -TargetObject $ErrReturnObject
            return $false
        }

        Write-Information -MessageData "$($Object.ObjectType) was successfully created."

        ## Post ARM deployment operations
        if($Object.ObjectType -eq "Function") {
            ## Publish GitHub Functions to newly created Azure Function
            $FunctionName = $Object.Parameters.Parameters.functionName.value
            $FunctionApp = Get-AzFunctionApp -ResourceGroupName $ResourceGroup -Name $FunctionName
            $FunctionAppId = $FunctionApp.Id

            ## Assign necessary Azure roles
            if (!$(Set-RoleAssignment -PrincipalId $FunctionApp.IdentityPrincipalId -RoleName "Storage Account Contributor" -ResourceGroup $ResourceGroup -ResourceName $StorageAccountName -ResourceType "Microsoft.Storage/storageAccounts")) { return $false }
            if (!$(Set-RoleAssignment -PrincipalId $FunctionApp.IdentityPrincipalId -RoleName "Storage Blob Data Owner" -ResourceGroup $ResourceGroup -ResourceName $StorageAccountName -ResourceType "Microsoft.Storage/storageAccounts")) { return $false }
            if (!$(Set-RoleAssignment -PrincipalId $FunctionApp.IdentityPrincipalId -RoleName "Storage Table Data Contributor" -ResourceGroup $ResourceGroup -ResourceName $StorageAccountName -ResourceType "Microsoft.Storage/storageAccounts")) { return $false }
            if (!$(Set-RoleAssignment -PrincipalId $FunctionApp.IdentityPrincipalId -RoleName "Storage Queue Data Contributor" -ResourceGroup $ResourceGroup -ResourceName $StorageAccountName -ResourceType "Microsoft.Storage/storageAccounts")) { return $false }
            if (!$(Set-RoleAssignment -PrincipalId $FunctionApp.IdentityPrincipalId -RoleName "Storage Queue Data Message Processor" -ResourceGroup $ResourceGroup -ResourceName $StorageAccountName -ResourceType "Microsoft.Storage/storageAccounts")) { return $false }
            if (!$(Set-RoleAssignment -PrincipalId $FunctionApp.IdentityPrincipalId -RoleName "Storage Queue Data Message Sender" -ResourceGroup $ResourceGroup -ResourceName $StorageAccountName -ResourceType "Microsoft.Storage/storageAccounts")) { return $false }
            if (!$(Set-RoleAssignment -PrincipalId $FunctionApp.IdentityPrincipalId -RoleName "App Configuration Data Reader" -ResourceGroup $ResourceGroup -ResourceName $AppConfigName -ResourceType "Microsoft.AppConfiguration/configurationStores")) { return $false }

            ## Set keyvault secrets get permission
            Write-Verbose "Set keyvault secret access for Azure Function"
            $Result = Set-AzKeyVaultAccessPolicy -VaultName $KeyVaultName -ResourceGroupName $ResourceGroup -ObjectId $FunctionApp.IdentityPrincipalId -PermissionsToSecrets Get -BypassObjectIdValidation -ErrorVariable ErrorSet
            if ($ErrorSet) {
                Write-Error "Failed to set keyvault secret access for Azure Function. Error: $ErrorSet"
                return $false
            }

            ## Assign cosmos db roles
            $CosmosAccount = Get-AzCosmosDBAccount -ResourceGroupName $ResourceGroup -Name $CosmosAccountName
            $RoleId = "00000000-0000-0000-0000-000000000002" ## Built in contributor role
            $RoleDefinitionId = "$($CosmosAccount.Id)/sqlRoleAssignments/$RoleId"
            if ((Get-AzCosmosDBSqlRoleAssignment -ResourceGroupName $ResourceGroup -AccountName $CosmosAccountName).Where({$_.PrincipalId -eq $FunctionApp.IdentityPrincipalId -and $_.RoleDefinitionId -eq $RoleDefinitionId}).Count -eq 0) {
                Write-Verbose "Assigning Cosmos DB Account contributor role"
                $Result = New-AzCosmosDBSqlRoleAssignment -AccountName $CosmosAccountName -ResourceGroupName $ResourceGroup -RoleDefinitionId $RoleId -Scope "/" -PrincipalId $FunctionApp.IdentityPrincipalId -ErrorVariable ErrorNew
                if ($ErrorNew) {
                    Write-Error "Failed to assign Azure Function with Cosmos DB contributor role. Error: $ErrorNew"
                    return $false
                }
            }

            ## Create Function app key and also add to keyvault
            $NewFunctionKeyValue = New-FunctionAppKey
            $Result = Invoke-AzRestMethod -Path "$FunctionAppId/host/default/functionKeys/WinGetRestSourceAccess?api-version=2024-04-01" -Method PUT -Payload (@{properties=@{name = "WinGetRestSourceAccess"; value = $NewFunctionKeyValue}} | ConvertTo-Json -Depth 8)
            if ($Result.StatusCode -ne 200 -and $Result.StatusCode -ne 201) {
                Write-Error "Failed to create Azure Function key. $($Result.Content)"
                return $false
            }

            Write-Information -MessageData "Add Function App host key to keyvault."
            $Result = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AzureFunctionHostKeyName -SecretValue (Get-SecureString($NewFunctionKeyValue)) -ErrorVariable ErrorSet
            if ($ErrorSet) {
                Write-Error "Failed to set keyvault secret. Name: $AzureFunctionHostKeyName Error: $ErrorSet"
                return $false
            }

            Write-Information -MessageData "Publishing function files to the Azure Function."
            $DeployResult = Publish-AzWebApp -ArchivePath $RestSourcePath -ResourceGroupName $ResourceGroup -Name $FunctionName -Force -ErrorVariable DeployError

            ## Verifies that no error occured when publishing the Function App
            if ($DeployError -or !$DeployResult) {
                $ErrReturnObject = @{
                    DeployError = $DeployError
                    DeployResult = $DeployResult
                }

                Write-Error "Failed to publishing the Function App. Error: $DeployError" -TargetObject $ErrReturnObject
                return $false
            }

            ## Restart the Function App
            Write-Verbose "Restarting Azure Function."
            if (!$(Restart-AzFunctionApp -Name $FunctionName -ResourceGroupName $ResourceGroup -Force -PassThru)) {
                Write-Error "Failed to restart Function App. Name: $FunctionName"
                return $false
            }
        }

        $Object.DeploymentSuccess = $true
    }

    return $true
}

# SIG # Begin signature block
# MIIoUgYJKoZIhvcNAQcCoIIoQzCCKD8CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDrd2SH0vBU9iEI
# zlAYYTEYEdQ6GJWTCIrSFzdtRK2h7aCCDYUwggYDMIID66ADAgECAhMzAAAEhJji
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
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIC6K
# CdsorbnIV7lnuej8J4w+KbCwyDwyrV+dep8goJTpMEIGCisGAQQBgjcCAQwxNDAy
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20wDQYJKoZIhvcNAQEBBQAEggEAvq0QLVKrxQpcLRjL3nV+WmZxCGVnJuBQWE12
# gnZnRATCFO96tKP0ak61cWRC2o8CbhozGGsvM68mucw1q3ZoVGTqOgmB4KUzxk0t
# pNkFtdYLYW4/w9zeegTKXMAUwSGvY7dF7ftKUGglqM/QoT7VHIWJl9AUDiKLRwbv
# cSJu9uI8mQqNWqY70x1HS3W7xgrPiK/q3vHELwfuVQgcBc4hu83/70kllyA8aj/6
# fAYObseCJOaWd0ShPp6Uda0H6hFvRNAd2cpck+BoeOzVfmECY6QdFXsd+A8/hiW9
# PaTs2ZS8A9XFesbyC+GVtLruw34GkC8kG+guHIvjgM2/T4BOTKGCF60wghepBgor
# BgEEAYI3AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheCAgEDMQ8wDQYJYIZI
# AWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGE
# WQoDATAxMA0GCWCGSAFlAwQCAQUABCCJC1mND09K3y3xy4z2aw6HEWRKj5s0rMK3
# Qn1iXzsYQQIGaHpP8De3GBMyMDI1MDcyNTAwMTMxMi4xMDJaMASAAgH0oIHZpIHW
# MIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQL
# EyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsT
# Hm5TaGllbGQgVFNTIEVTTjo0QzFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEfswggcoMIIFEKADAgECAhMzAAAB/xI4
# fPfBZdahAAEAAAH/MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwMB4XDTI0MDcyNTE4MzExOVoXDTI1MTAyMjE4MzExOVowgdMxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jv
# c29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
# ZCBUU1MgRVNOOjRDMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# yeiV0pB7bg8/qc/mkiDdJXnzJWPYgk9mTGeI3pzQpsyrRJREWcKYHd/9db+g3z4d
# U4VCkAZEXqvkxP5QNTtBG5Ipexpph4PhbiJKwvX+US4KkSFhf1wflDAY1tu9CQqh
# hxfHFV7vhtmqHLCCmDxhZPmCBh9/XfFJQIUwVZR8RtUkgzmN9bmWiYgfX0R+bDAn
# ncUdtp1xjGmCpdBMygk/K0h3bUTUzQHb4kPf2ylkKPoWFYn2GNYgWw8PGBUO0vTM
# KjYD6pLeBP0hZDh5P3f4xhGLm6x98xuIQp/RFnzBbgthySXGl+NT1cZAqGyEhT7L
# 0SdR7qQlv5pwDNerbK3YSEDKk3sDh9S60hLJNqP71iHKkG175HAyg6zmE5p3fONr
# 9/fIEpPAlC8YisxXaGX4RpDBYVKpGj0FCZwisiZsxm0X9w6ZSk8OOXf8JxTYWIqf
# RuWzdUir0Z3jiOOtaDq7XdypB4gZrhr90KcPTDRwvy60zrQca/1D1J7PQJAJObbi
# aboi12usV8axtlT/dCePC4ndcFcar1v+fnClhs9u3Fn6LkHDRZfNzhXgLDEwb6dA
# 4y3s6G+gQ35o90j2i6amaa8JsV/cCF+iDSGzAxZY1sQ1mrdMmzxfWzXN6sPJMy49
# tdsWTIgZWVOSS9uUHhSYkbgMxnLeiKXeB5MB9QMcOScCAwEAAaOCAUkwggFFMB0G
# A1UdDgQWBBTD+pXk/rT/d7E/0QE7hH0wz+6UYTAfBgNVHSMEGDAWgBSfpxVdAF5i
# XYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRp
# bWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1Ud
# JQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsF
# AAOCAgEAOSNN5MpLiyunm866frWIi0hdazKNLgRp3WZPfhYgPC3K/DNMzLliYQUA
# p6WtgolIrativXjOG1lIjayG9r6ew4H1n5XZdDfJ12DLjopap5e1iU/Yk0eutPyf
# OievfbsIzTk/G51+uiUJk772nVzau6hI2KGyGBJOvAbAVFR0g8ppZwLghT4z3mkG
# Zjq/O4Z/PcmVGtjGps2TCtI4rZjPNW8O4c/4aJRmYQ/NdW91JRrOXRpyXrTKUPe3
# kN8N56jpl9kotLhdvd89RbOsJNf2XzqbAV7XjV4caCglA2btzDxcyffwXhLu9HMU
# 3dLYTAI91gTNUF7BA9q1EvSlCKKlN8N10Y4iU0nyIkfpRxYyAbRyq5QPYPJHGA0T
# y0PD83aCt79Ra0IdDIMSuwXlpUnyIyxwrDylgfOGyysWBwQ/js249bqQOYPdpyOd
# gRe8tXdGrgDoBeuVOK+cRClXpimNYwr61oZ2/kPMzVrzRUYMkBXe9WqdSezh8tyt
# uulYYcRK95qihF0irQs6/WOQJltQX79lzFXE9FFln9Mix0as+C4HPzd+S0bBN3A3
# XRROwAv016ICuT8hY1InyW7jwVmN+OkQ1zei66LrU5RtAz0nTxx5OePyjnTaItTS
# Y4OGuGU1SXaH49JSP3t8yGYA/vorbW4VneeD721FgwaJToHFkOIwggdxMIIFWaAD
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
# Hm5TaGllbGQgVFNTIEVTTjo0QzFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAqROMbMS8JcUl
# cnPkwRLFRPXFspmggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAx
# MDANBgkqhkiG9w0BAQsFAAIFAOwstwQwIhgPMjAyNTA3MjQxMzQzMzJaGA8yMDI1
# MDcyNTEzNDMzMlowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA7Cy3BAIBADAHAgEA
# AgIFTTAHAgEAAgISgDAKAgUA7C4IhAIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgor
# BgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBCwUA
# A4IBAQDHGiTrnZd79QNdiO+gxc0WolU2bmYyCRfOEO4a6cSRtcAYa6jSxik+gWQN
# /UgS040FVZJuxgt4Jj8+XhLRQOO7h27z8BiY4L29SLEv4SAQy8IFQpcD9cQKJEGQ
# u767vBwL1OZPuoHLiN9ph+9/15HbaidppQLMgpmDrL+1RM6Spizwkz3eF58q6RNY
# b0sIR9HegFs4RpbNhjiefx1NW9CV39bVMAbnm4BPEpms4b8gZFCRT/OUm/fIaviq
# O/yfDhf6kBs0V/bIvwIH7RswZbVHHFDZpz+1QdI0YbNDiRVereubndOb/bD+c88z
# O6wAM+SWuYmXCsu1tmR2blCHZMYvMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAH/Ejh898Fl1qEAAQAAAf8wDQYJYIZIAWUD
# BAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0B
# CQQxIgQg5SDBvDNBMbZ+Ruo4gzJYYge7Xx3CN5bWaytLCC93gXwwgfoGCyqGSIb3
# DQEJEAIvMYHqMIHnMIHkMIG9BCDkMu++yQJ3aaycIuMT6vA7JNuMaVOI3qDjSEV8
# upyn/TCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAB
# /xI4fPfBZdahAAEAAAH/MCIEII8zD7yXKjxleTNhaz3EdCsg9qD4gBdJbZhmmGgE
# ecNbMA0GCSqGSIb3DQEBCwUABIICAJBZZND/59Dzi87o8Aby9rN/LFl/n2ByMru9
# zypo/vPNiqDH6fucD3RikqxcCI95Rk83JIM04nCjLUUd0y+/Sfkc6zhAVUuPjStZ
# YBCivKumFoZpEFAm1Fki9GS1FgSz6aWA9Kp2YEdJ60zPnFG8UFrw6zkhj6GF/V2D
# 43UQAc6Ubc3toWq3KnKVM1agoYYRPx5uXIOGGblQDLezN5hyuNARsIx7eaEHVnYJ
# FoFE6hftOfkjIEZNBB26T3dy3YyqwMSr0b3uyplgB9otMNMrSGMZw8NuYM9rdU8D
# XEfW4gmLZnaDkmPbo9M7BsxncZzhYEOzKYniMsvlhRjjh4r+AhZ7yp+EMVtgLqHA
# hg7QSQiMUPqrJqHOic3nmIMA7g0W9jYiQawox1o9iV90RBBYrevlGqo8ERfXDUhz
# co+TjbtIV7Bl2YK3USxmhaQ+rFCRgke1GozHvrtBMeAmlAErUei/EKOlC9tHPCYX
# XmNIm9PBgYWGB3JNfRTX+kHzTotWKMSkZPfad/NW5dywx/kx+dzJittxh6csT9Vz
# u+wW/1daxaW7d5GICjJYbbjQ0QV4lKQbPNzZkUNkjHMKn99Fkc7H4oq2TAoU82xZ
# EhjNjzN8LBM9Gp/cj3oEbU0INfx/C4UzqdgMdYe031eJN0z0+ynWu9N8xnOhLAkM
# op4vPS4u
# SIG # End signature block
