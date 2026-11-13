# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
function New-ARMObjects {
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
    param(
        [Parameter(Position = 0, Mandatory = $true)] [array] [ref] $ARMObjects,
        [Parameter(Position = 1, Mandatory = $true)] [string] $RestSourcePath,
        [Parameter(Position = 2, Mandatory = $true)] [string] $ResourceGroup
    )

    # Function to create a new Function App key
    function New-FunctionAppKey {
        $private:characters = 'abcdefghiklmnoprstuvwxyzABCDEFGHIJKLMENOPTSTUVWXYZ'
        $private:randomChars = 1..64 | ForEach-Object { Get-Random -Maximum $characters.length }
    
        # Set the output field separator to empty instead of space
        $private:ofs = ''
        return [String]$characters[$randomChars]
    }

    # Function to ensure Azure role assignment
    function Set-RoleAssignment {
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

    function Get-SecureString {
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
    $StorageAccountName = $ARMObjects.Where({ $_.ObjectType -eq 'StorageAccount' }).Parameters.Parameters.storageAccountName.value
    $KeyVaultName = $ARMObjects.Where({ $_.ObjectType -eq 'Keyvault' }).Parameters.Parameters.name.value
    $CosmosAccountName = $ARMObjects.Where({ $_.ObjectType -eq 'CosmosDBAccount' }).Parameters.Parameters.name.value
    $AppConfigName = $ARMObjects.Where({ $_.ObjectType -eq 'AppConfig' }).Parameters.Parameters.appConfigName.value
    $FunctionName = $ARMObjects.Where({ $_.ObjectType -eq 'Function' }).Parameters.Parameters.functionName.value

    ## Azure Keyvault Secret Names - Do not change values (Must match with values in the Template files)
    $CosmosAccountEndpointKeyName = 'CosmosAccountEndpoint'
    $AzureFunctionHostKeyName = 'AzureFunctionHostKey'
    $AppConfigPrimaryEndpointName = 'AppConfigPrimaryEndpoint'
    $AppConfigSecondaryEndpointName = 'AppConfigSecondaryEndpoint'

    ## Creates the Azure Resources following the ARM template / parameters
    Write-Information 'Creating Azure Resources following ARM Templates.'

    ## This is order specific, please ensure you used the New-ARMParameterObjects function to create this object in the pre-determined order.
    foreach ($Object in $ARMObjects) {
        if ($Object.DeploymentSuccess) {
            Write-Verbose "Skipped the Azure Object - $($Object.ObjectType). Deployment success detected."
            continue
        }

        Write-Information "Creating the Azure Object - $($Object.ObjectType)"

        ## Pre ARM deployment operations
        if ($Object.ObjectType -eq 'Function') {
            $CosmosAccountEndpointValue = Get-SecureString($(Get-AzCosmosDBAccount -Name $CosmosAccountName -ResourceGroupName $ResourceGroup).DocumentEndpoint)
            Write-Verbose 'Creating Keyvault Secret for Azure CosmosDB endpoint.'
            $Result = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $CosmosAccountEndpointKeyName -SecretValue $CosmosAccountEndpointValue -ErrorVariable ErrorSet
            if ($ErrorSet) {
                Write-Error "Failed to set keyvault secret. Name: $CosmosAccountEndpointKeyName Error: $ErrorSet"
                return $false
            }

            $AppConfigEndpointValue = Get-SecureString($(Get-AzAppConfigurationStore -Name $AppConfigName -ResourceGroupName $ResourceGroup).Endpoint)
            Write-Verbose 'Creating Keyvault Secret for Azure App Config endpoint.'
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
        } elseif ($Object.ObjectType -eq 'ApiManagement') {
            ## Create instance manually if not exist
            $ApiManagementParameters = $Object.Parameters.Parameters
            $ApiManagement = Get-AzApiManagement -ResourceGroupName $ResourceGroup -Name $ApiManagementParameters.serviceName.value -ErrorVariable ErrorGet -ErrorAction SilentlyContinue
            if (!$ApiManagement) {
                Write-Warning "Creating new Api Aanagement service. Name: $($ApiManagementParameters.serviceName.value)"
                Write-Warning 'This is a long-running action. It can take between 30 and 40 minutes to create and activate an API Management service.'
                $ApiManagement = New-AzApiManagement -ResourceGroupName $ResourceGroup -Name $ApiManagementParameters.serviceName.value -Location $ApiManagementParameters.location.value -Organization $ApiManagementParameters.publisherName.value -AdminEmail $ApiManagementParameters.publisherEmail.value -Sku $ApiManagementParameters.sku.value -SystemAssignedIdentity -ErrorVariable DeployError
                if ($DeployError) {
                    Write-Error "Failed to create Api Aanagement service. Error: $DeployError"
                    return $false
                }
            }

            ## Set secret get permission for Api Management service
            Write-Verbose 'Set keyvault secret access for Api Management service'
            $Result = Set-AzKeyVaultAccessPolicy -VaultName $KeyVaultName -ResourceGroupName $ResourceGroup -ObjectId $ApiManagement.Identity.PrincipalId -PermissionsToSecrets Get -BypassObjectIdValidation -ErrorVariable ErrorSet
            if ($ErrorSet) {
                Write-Error "Failed to set keyvault secret access for Api Management Service. Error: $ErrorSet"
                return $false
            }

            ## Update backend urls and re-create parameters file if needed
            $FunctionApp = Get-AzFunctionApp -ResourceGroupName $ResourceGroup -Name $FunctionName
            $FunctionAppUrl = "https://$($FunctionApp.DefaultHostName)/api"
            if ($ApiManagementParameters.backendUrls.value.Where({ $_ -eq $FunctionAppUrl }).Count -eq 0) {
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
        if ($DeployError -or ($DeployResult.ProvisioningState -ne 'Succeeded' -and $DeployResult.ProvisioningState -ne 'Created')) {
            $ErrReturnObject = @{
                DeployError  = $DeployError
                DeployResult = $DeployResult
            }

            Write-Error "Failed to create Azure object. Error: $DeployError" -TargetObject $ErrReturnObject
            return $false
        }

        Write-Information -MessageData "$($Object.ObjectType) was successfully created."

        ## Post ARM deployment operations
        if ($Object.ObjectType -eq 'Function') {
            ## Publish GitHub Functions to newly created Azure Function
            $FunctionName = $Object.Parameters.Parameters.functionName.value
            $FunctionApp = Get-AzFunctionApp -ResourceGroupName $ResourceGroup -Name $FunctionName
            $FunctionAppId = $FunctionApp.Id

            ## Assign necessary Azure roles
            if (!$(Set-RoleAssignment -PrincipalId $FunctionApp.IdentityPrincipalId -RoleName 'Storage Account Contributor' -ResourceGroup $ResourceGroup -ResourceName $StorageAccountName -ResourceType 'Microsoft.Storage/storageAccounts')) { return $false }
            if (!$(Set-RoleAssignment -PrincipalId $FunctionApp.IdentityPrincipalId -RoleName 'Storage Blob Data Owner' -ResourceGroup $ResourceGroup -ResourceName $StorageAccountName -ResourceType 'Microsoft.Storage/storageAccounts')) { return $false }
            if (!$(Set-RoleAssignment -PrincipalId $FunctionApp.IdentityPrincipalId -RoleName 'Storage Table Data Contributor' -ResourceGroup $ResourceGroup -ResourceName $StorageAccountName -ResourceType 'Microsoft.Storage/storageAccounts')) { return $false }
            if (!$(Set-RoleAssignment -PrincipalId $FunctionApp.IdentityPrincipalId -RoleName 'Storage Queue Data Contributor' -ResourceGroup $ResourceGroup -ResourceName $StorageAccountName -ResourceType 'Microsoft.Storage/storageAccounts')) { return $false }
            if (!$(Set-RoleAssignment -PrincipalId $FunctionApp.IdentityPrincipalId -RoleName 'Storage Queue Data Message Processor' -ResourceGroup $ResourceGroup -ResourceName $StorageAccountName -ResourceType 'Microsoft.Storage/storageAccounts')) { return $false }
            if (!$(Set-RoleAssignment -PrincipalId $FunctionApp.IdentityPrincipalId -RoleName 'Storage Queue Data Message Sender' -ResourceGroup $ResourceGroup -ResourceName $StorageAccountName -ResourceType 'Microsoft.Storage/storageAccounts')) { return $false }
            if (!$(Set-RoleAssignment -PrincipalId $FunctionApp.IdentityPrincipalId -RoleName 'App Configuration Data Reader' -ResourceGroup $ResourceGroup -ResourceName $AppConfigName -ResourceType 'Microsoft.AppConfiguration/configurationStores')) { return $false }

            ## Set keyvault secrets get permission
            Write-Verbose 'Set keyvault secret access for Azure Function'
            $Result = Set-AzKeyVaultAccessPolicy -VaultName $KeyVaultName -ResourceGroupName $ResourceGroup -ObjectId $FunctionApp.IdentityPrincipalId -PermissionsToSecrets Get -BypassObjectIdValidation -ErrorVariable ErrorSet
            if ($ErrorSet) {
                Write-Error "Failed to set keyvault secret access for Azure Function. Error: $ErrorSet"
                return $false
            }

            ## Assign cosmos db roles
            $CosmosAccount = Get-AzCosmosDBAccount -ResourceGroupName $ResourceGroup -Name $CosmosAccountName
            $RoleId = '00000000-0000-0000-0000-000000000002' ## Built in contributor role
            $RoleDefinitionId = "$($CosmosAccount.Id)/sqlRoleDefinitions/$RoleId"
            if ((Get-AzCosmosDBSqlRoleAssignment -ResourceGroupName $ResourceGroup -AccountName $CosmosAccountName).Where({ $_.PrincipalId -eq $FunctionApp.IdentityPrincipalId -and $_.RoleDefinitionId -eq $RoleDefinitionId }).Count -eq 0) {
                Write-Verbose 'Assigning Cosmos DB Account contributor role'
                $Result = New-AzCosmosDBSqlRoleAssignment -AccountName $CosmosAccountName -ResourceGroupName $ResourceGroup -RoleDefinitionId $RoleId -Scope '/' -PrincipalId $FunctionApp.IdentityPrincipalId -ErrorVariable ErrorNew
                if ($ErrorNew) {
                    Write-Error "Failed to assign Azure Function with Cosmos DB contributor role. Error: $ErrorNew"
                    return $false
                }
            }

            ## Create Function app key and also add to keyvault
            $NewFunctionKeyValue = New-FunctionAppKey
            $Result = Invoke-AzRestMethod -Path "$FunctionAppId/host/default/functionKeys/WinGetRestSourceAccess?api-version=2024-04-01" -Method PUT -Payload (@{properties = @{name = 'WinGetRestSourceAccess'; value = $NewFunctionKeyValue } } | ConvertTo-Json -Depth 8)
            if ($Result.StatusCode -ne 200 -and $Result.StatusCode -ne 201) {
                Write-Error "Failed to create Azure Function key. $($Result.Content)"
                return $false
            }

            Write-Information -MessageData 'Add Function App host key to keyvault.'
            $Result = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AzureFunctionHostKeyName -SecretValue (Get-SecureString($NewFunctionKeyValue)) -ErrorVariable ErrorSet
            if ($ErrorSet) {
                Write-Error "Failed to set keyvault secret. Name: $AzureFunctionHostKeyName Error: $ErrorSet"
                return $false
            }

            Write-Information -MessageData 'Publishing function files to the Azure Function.'
            $DeployResult = Publish-AzWebApp -ArchivePath $RestSourcePath -ResourceGroupName $ResourceGroup -Name $FunctionName -Force -ErrorVariable DeployError

            ## Verifies that no error occured when publishing the Function App
            if ($DeployError -or !$DeployResult) {
                $ErrReturnObject = @{
                    DeployError  = $DeployError
                    DeployResult = $DeployResult
                }

                Write-Error "Failed to publishing the Function App. Error: $DeployError" -TargetObject $ErrReturnObject
                return $false
            }

            ## Restart the Function App
            Write-Verbose 'Restarting Azure Function.'
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
# MIInNwYJKoZIhvcNAQcCoIInKDCCJyQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCH0RmF7XtPH31V
# f4W7WRCSppIJ75yEnLQcDYMu5Kn1UqCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
# xZvoL37EAAAAAAIcMA0GCSqGSIb3DQEBCwUAMFcxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBD
# b2RlIFNpZ25pbmcgUENBIDIwMjQwHhcNMjYwNDE2MTg1OTQxWhcNMjcwNDE1MTg1
# OTQxWjB0MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYD
# VQQDExVNaWNyb3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQDVsZfgOKmM31HPfoWOoNEiw0SlCiIxUMC0I9NMWbucKOw/e9lP
# oAoehQVu6SG65V4EPzrYsnBnFPNoi4/HoOdjhz1qkrEt4I6tEcxXU6oOeY9zGveC
# /3iBeuhLYxM3M/PkcUoebF+Nednm8OkdSPoDu8imViHPQq/8CQUu0WRR4rE+dMRf
# rpVqfmNi2qWCX94T4MsepijGVkwE//tJg0ryAiYdHT34LSnlG/RSBZmQRGWZ5g8j
# qnKjRParSqMft1gvjuUTVgtWNZfgcLFSK5Wa0myrq8OPcgTGGsRgun+tnSS+IxDT
# xVsAPH1OzvPjwomguByhUe/OcvUN0D5Wmp7xAgMBAAGjggGqMIIBpjAOBgNVHQ8B
# Af8EBAMCB4AwHwYDVR0lBBgwFgYKKwYBBAGCN0wIAQYIKwYBBQUHAwMwHQYDVR0O
# BBYEFNoH7a2YDjOSwpkp6DHcmUS7J+0yMFQGA1UdEQRNMEukSTBHMS0wKwYDVQQL
# EyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxFjAUBgNVBAUT
# DTIzMDAxMis1MDc1NjkwHwYDVR0jBBgwFoAUf1k/VCHarU/vBeXmo9ctBpQSCDEw
# YAYDVR0fBFkwVzBVoFOgUYZPaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDI0LmNy
# bDBtBggrBgEFBQcBAQRhMF8wXQYIKwYBBQUHMAKGUWh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwQ29kZSUyMFNpZ25pbmcl
# MjBQQ0ElMjAyMDI0LmNydDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4IC
# AQAUnEqhaRXe0T3hIJjvdQErEkrA/7bByjn6t5IArODkkRjzkYwtKMc2yYj2quaN
# rLutWw2YZcngKPy1b71YyDJQTy4NDRwaSh9Tw5thrk3NmcPrAHia5vtcBJ1CgtKK
# 7mQbIcQ22d/N3813ayCDDFewu1+jsZmX+r/aTEqaOM4TVxVtRSkuCy8nAXKuChOK
# Li/zA4XuH8iEYqIsj2YoNaeSxVmeGiERXpKdo3dDmYi0kO5w2D8VS4c3+9h6gElY
# BaAAg/dYErBg27qT3vv0zRDJhJufvCNylA8S7/+8H5E/PV5cng6na9VV/w9OV3qu
# uND6zdGa2EX38Glp50F9AIQk3p2xXmcvorDeM4XJ7UlWYBi6g80J1SSOQnInCYFE
# msfUNn3+1AaTJKSJL83quKArTac2pKhu0Yzzzrzo6HrsRiQKzpnRBb1/dMa6P3hz
# 75XbMRBctNsFhZC07WCmjExdLg2eHW5uV0TY8D5+6wozJf7vF3+WHkYPO85Z+BC6
# U4FkNbYNycZ9cE4j1tXRdyDCfml6c0HWPHjNVDObrv9lKt3qUqFpX38VCqVCyNOO
# 1UcXfQiVjJw32U2WUKZjt/neJKHEBsm9kFsLuWzkQ53+qcaSaytmsCnk2gOglrlD
# 5d3kKyvvAw+rzm0lT8K38P6PLxfZQHhu4W8dV7Av8N2ZmDCCBr0wggSloAMCAQIC
# EzMAAAA5O7Y3Gb8GHWcAAAAAADkwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBS
# b290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDExMB4XDTI0MDgwODIwNTQxOFoX
# DTM2MDMyMjIyMTMwNFowVzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQ
# Q0EgMjAyNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANgBnB7jOMeq
# lRYHNa265v4IY9fH8TKhemHfPINe1gpLaV3dhg324WwH06LcHbpnsBukCDNitryo
# 0dtS/EW6I/yEL/bLSY8hKpbfQuWusBPr9qazYcDxCW/qnjb5JsI1s8bNOg3bVATv
# QVL4tcf03aTycsz8QeCdM0l/yHRObJ9QqazM1r6VPEOJ7LL+uEEb73w6QCuhs89a
# 1uv1zerOYMnsneRRwCbpyW11IcggU0cRKDDq1pjVJzIbIF6+oiXXbReOsgeI8zu1
# FyQfK0fVkaya8SmVHQ/tOf23mZ4W9k0Ri22QW9p3UgSC5OUDktKxxcCmGL6tXLfO
# GSWHIIV4YrTJTT6PNty5REojHJuZHArkF9VnHTERWoTjAzfI3kP+5b4alUdhgAZ7
# ttOu1bVnXfHaqPYl2rPs20ji03LOVWsh/radgE17es5hL+t6lV0eVHrVhsssROWJ
# uz2MXMCt7iw7lFPG9LXKGjsmonn2gotGdHIuEg5JnJMJVmixd5LRlkmgYRZKzhxS
# CwyoGIq0PhaA7Y+VPct5pCHkijcIIDm0nlkK+0KyepolcqGm0T/GYQRMhHJlGOOm
# VQop36wUVUYklUy++vDWeEgEo4s7hxN6mIbf2MSIQ/iIfMZgJxC69oukMUXCrOC3
# SkE/xIkgpfl22MM1itkZ35nNXkMolU1lAgMBAAGjggFOMIIBSjAOBgNVHQ8BAf8E
# BAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFH9ZP1Qh2q1P7wXl5qPX
# LQaUEggxMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMB
# Af8wHwYDVR0jBBgwFoAUci06AjGQQ7kUBU7h6qfHMdEjiTQwWgYDVR0fBFMwUTBP
# oE2gS4ZJaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMv
# TWljUm9vQ2VyQXV0MjAxMV8yMDExXzAzXzIyLmNybDBeBggrBgEFBQcBAQRSMFAw
# TgYIKwYBBQUHMAKGQmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMv
# TWljUm9vQ2VyQXV0MjAxMV8yMDExXzAzXzIyLmNydDANBgkqhkiG9w0BAQwFAAOC
# AgEAFJQfOChP7onn6fLIMKrSlN1WYKwDFgAddymOUO3FrM8d7B/W/iQ6DxXsDn7D
# 5W4wMwYeLystcEqfkjz4NURRgazyMu5yRzQh4LqjA4tStTcJh1opExo7nn5PuPBY
# nbu0+THSuVHTe0VTTPVhily/piFrDo3axQ9P4C+Ol5yet+2gTfekICS5xS+cYfSI
# vgn0JksVBVMYVI5QFu/qhnLhsEFEUzG8fvv0hjgkO+lkpV9ty6GkN4vdnd7ya6Q6
# aR9y34aiM1qmxaxBi6OUnyNl6fkuun/diTFnYDLTppOkr/mg5WSfCiDVMNCxtj4w
# PKC5OmHm1DQIt/MNokbbH3UGsFP1QbzsLocuSqLCvH09Io3fDPTmscR9Y75G4qX7
# RTX8AdBPo0I6OEojf39zuFZt0qOHm65YWQE69cZM2ueE1MB05dNNgHK9gTE7zKvK
# /fg8B2qjW88MT/WF5V5uvZGtqa9FSL2RazArA+rDPuf6JGYz4HpgMZHB4S6szWSK
# YBv0VisCzfxgeU+dquXW9bd0auYlOB58DPcOYKdc3Se94g+xL4pcEhbB54JOgAkw
# YTu/9dLeH2pDqeJZAABVDWRQCaXfO5LgyKwKCLYXpigrZYCjUSBcr+Ve8PFWMhVT
# Ql0v4q8J/AUmQN5W4n101cY2L4A7GTQG1h32HHAvfQESWP0xghnEMIIZwAIBATBu
# MFcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# KDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIc
# +s3Fm+gvfsQAAAAAAhwwDQYJYIZIAWUDBAIBBQCggZAwGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIEICeMbx+AfPo6FnBKLUJcPjI58Ldb
# gYyU1MPYi25qdKzOMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBv
# AGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAE
# ggEAwK46us2BkX/h3ba7sLCZY0f7k0JjwiK1GylSivloX885+trCNSt/JbGmGbXs
# S9KDy6v62rKnOjUqeS5JvvF+GLvLIwnfeuB+EjbF6mdQPpMldfM84q2gqCK2dhF9
# nlZOsdka9zk9TYZP9Eyb080oLW5OFHFtv4oUp7udhMwQBO4CrL7mmE2FdybrgvRU
# oJNr5VO8wER3hbsBWZr2xakWzkfV4j1kraprH4jg1oiVwuCAgfemLRQ2hDp+FgY/
# uAZiPmafUun632nYXb0IZVXnLkxNkEtoyL7hEXlqHD3eUMeQJA9CsjgcEO/jWTPD
# nvOr2Ebkecxxptw5qM/gwmbAJKGCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wG
# CSqGSIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG
# 9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCAJeel40DBgDo+FigOq1cq0PJaLAEttzkeVVmhNgeU5kAIGarUjm/8IGBMy
# MDI2MDkyNTIxNDM1MS42MzhaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046QTkzNS0wM0Uw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHq
# MIIHIDCCBQigAwIBAgITMwAAAifVwIPDsS5XLQABAAACJzANBgkqhkiG9w0BAQsF
# ADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
# Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNjAyMTkxOTQwMDRa
# Fw0yNzA1MTcxOTQwMDRaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScw
# JQYDVQQLEx5uU2hpZWxkIFRTUyBFU046QTkzNS0wM0UwLUQ5NDcxJTAjBgNVBAMT
# HE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQDixWy1fDOSL4qj3A1pady+elIDLwnF3UuLzJIOWwGHcEgr
# xxwtnyviUIDmmxylTUl1u+2rBPp2zT4BwwQhvGaJpExqvPLlDFlbfmSflKI86eFq
# ofiZ7j8NTRO4l7wGg9Njm+muNauTcFW2qdfIjKE950Okrm9MnMOGYy+fibNYdxTP
# RPq1T4MLZK3s3vdMyMEOldcOQkSKpxD6/1Gk6gOmCu2KgI8f0ex6vYxnKDl9W0OL
# SEa/6y82oIbsm+1QBifOQ47xWKTG1CmvtGr85LzA75/MAcUmRw5/of/qET0UFV1W
# ulMcJrI6DASAsNCNB+6WLrotuBZAj+VMlqbn5RMZ6Q4IY7JwaAiIXh7VjxrnwUOY
# ZG8WEGhfrA98di+7LEn9AqvvEOyG+UQcjVhCCbMGXigJXSApeyeWupCsD0jgQMNC
# xfB5BLBDWxgdY3dJBEPgxfkgTDQLBggtVv2d5CYxHKgIItB4bI5eSb5jkIG2Wotn
# FetT0legpw/Eozwf39ao6tENY21eVWIzRw/GsmvwjYQF6vVrxOD0pGVsfqGF8s3V
# PeY7hI2TxHFMqNA0IB/a2NLY7JTxYAKAP/11EJZt7xbqDLMgD1YDdGEzGpQijm3n
# APCL2CebP/jmu90abJ2W425yglGHTI/nCBrwSpfRCgwzrfFelJaCKM6+35aFfwID
# AQABo4IBSTCCAUUwHQYDVR0OBBYEFNLW58N4MGSG6ud7jWqgT92orfReMB8GA1Ud
# IwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRp
# bWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYI
# KwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMv
# TWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1Ud
# EwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeA
# MA0GCSqGSIb3DQEBCwUAA4ICAQAqncud4PSC1teb2H6nRuy7sDiKK13FXJirVB4T
# fwjdo2Mb+QL4j7wZ/k4G9P0CANHZFrDQcK0VFDTysrYu8Z0Aha14acDZPsyIoPvA
# GRRhaHEuf7NckRjkfa/ylo1KyII8jbL9N9sJAqBPL8V4FNBjljv+1GHDOw127rZz
# 5ZSTPoAPb2SA0v5yDgcpUMfxglPyp6cnPPoQpTtD9OGx8Dwm2P+o1TPxBIy6I0T9
# RauulogVCvKwflfeLTcKAvnSG1rCjerSXmU1DNXOsAD/bsrSjgbX5mAbD7XTRMF/
# vawAWESFcn/BjjizxeWZb00aYSlkJA2rVtFlMM481aVWXdAbXPP5RzUiWTlgyHf/
# G7lCxHYWGIZuB13T3aI6Y8mEgn/ou40aiFJo8r0+i0P5GdNneWtxiR0CMKUfko+5
# s/73cwe1Wfp8BKXa270cicVQasFf5sRV7pFm+V7fNRXwCu7anTOmga76zO7/2t+z
# OlibvphT+Q6Zd+B2qYsSn4xBaY+YzHpnycLW5cvJyhPxBCcb1oRYfhRzCADb2utI
# 2EtGCjc2P2ii4LyR4QMb/n8cOweL9IqVTKKzzVk+zZJxV3vrp4LyuQXw0O30la6B
# cHdNAAAB9UC83zs3G9d+AlIfZLM97tMUNKWjbBpIirFx6LTDFXVtZQd7hqzLYByj
# bjH0ujCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcN
# AQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAw
# BgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEw
# MB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk
# 4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9c
# T8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWG
# UNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6Gnsz
# rYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2
# LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLV
# wIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTd
# EonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0
# gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFph
# AXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJ
# YfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXb
# GjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJ
# KwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnP
# EP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMw
# UQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggr
# BgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYw
# DwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoY
# xDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtp
# L2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYB
# BQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20v
# cGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0B
# AQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U5
# 18JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgAD
# sAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo
# 32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZ
# iefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZK
# PmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RI
# LLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgk
# ujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9
# af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzba
# ukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/
# OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNNMIIC
# NQIBATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUG
# A1UECxMeblNoaWVsZCBUU1MgRVNOOkE5MzUtMDNFMC1EOTQ3MSUwIwYDVQQDExxN
# aWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQAjHzqt
# hPwO0GDckDMA6x54lIiMKqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7mDzWzAiGA8yMDI2MDkyNTEzMTkyM1oY
# DzIwMjYwOTI2MTMxOTIzWjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDuYPNbAgEA
# MAcCAQACAgrZMAcCAQACAheeMAoCBQDuYkTbAgEAMDYGCisGAQQBhFkKBAIxKDAm
# MAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcN
# AQELBQADggEBADV0RFIVAjDwQfvIm+CsxfdT4Jf8PRb8WHi7mri/t/XnBpVBFpks
# 3xeuInzbqphpDIIp8GUqePe1FF7cvgP7qkEHV6Xwwh9xZ30vgulAuBTpPpjzArZ4
# uoqO8mhsXD8b5m6XdkzXu49NRY5AopPhJGg2OKcWi1ZBUYyqrdBEX8vEVw6LSyJn
# 0A0i9YXhbfUvkrRDvYYqe0tfgrV5JuEwFiV7hMxWzc3fkb+mSsGthIUHbYxE5jVk
# KbsY/mNKt6aQDFZH8LP3rc52+V//xwYyfw9RUbrzLRTojrIi0jDTKWPWQEVSlwLs
# /55RtvGxuoyuwyF4QVFKInDaaRsYsVcJoFsxggQNMIIECQIBATCBkzB8MQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3Nv
# ZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAifVwIPDsS5XLQABAAACJzANBglg
# hkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqG
# SIb3DQEJBDEiBCADzP4Uqly3Ef330etSKItrmYXtgUOE2q22/qUdUnGpTzCB+gYL
# KoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIOXnARo1oVIcOLJKDqlE0adq/jZ9TXdl
# nXWRcXGThBFyMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAC
# EzMAAAIn1cCDw7EuVy0AAQAAAicwIgQgOyvLKWqPz41D5/4e6WOJx4OuTqg4z6lo
# RUJh/PIQuQQwDQYJKoZIhvcNAQELBQAEggIASh7DYRddLZRxsXhfDreGKY+yWOkr
# 03gWc9RzPmeG8asVoTt9J4NKUYNtMmK22GHlro6mdWOMMy4rPNuk16ch8F0fGnRO
# Ocq83+D5oDw96+cy94iBdWBJMrAdsTf/qQAQyC+AaMncC6V5TaZOd4+iYRHZYKdQ
# myruLNYbOyXJTx9SqYyWvbDjvo15eqVnNnsSi/UmfGFVBMWafKxfZ+nKxkgC2Lts
# 0eItnVYcgPUiXIs81YtSMBqSbz0sx/G7KDCsdGZtOqKx5XvgaEY9mc/JPUgOTU3d
# Gru7vJ/9bB6N29xeZQ+FVk9ocSplwyBAJNEkx4zEZvoFi3+RxPfhK+zCnhvahQ4g
# aziclKjtWUtcBS4WhZgaRHMPMSrjMfCDUoxV6fnZQjNJs1ks3nzQUcNPuwxj+037
# 0mWfqT5WcSNtUjIsWe4cNJ/8osDwIlmOzU1vpn+tyKSdwEritczjcmldbpvaEsR5
# YlZEyEd0M2gFzdM4n9++A3F8TZ+8U3+6ajXni+sP1C0gwetCSSUj2Rx7+LodHhmm
# idxIC9xIOABvDwVdNvHSH58ITXJGH9pHZLczqi8IBM0fd1wSkKQdM6V7eNEKQq6U
# x3AfLYZBA2Mubvjn7qy89BoiKhQpxEULsJaCTpcXMH3uV3TuiN2l1aRkVzf/UquQ
# 6RG8ai0EfU+JC1o=
# SIG # End signature block
