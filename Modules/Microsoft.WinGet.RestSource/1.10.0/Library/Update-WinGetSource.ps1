# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
Function Update-WinGetSource
{
    <#
    .SYNOPSIS
    Updates a Windows Package Manager REST source in Azure.

    .DESCRIPTION
    Updates a Windows Package Manager REST source in Azure.
    The update operation will not be able to detect existing Windows Package Manager REST source configurations by default.
    To use existing configurations, put existing ARM Template Parameter files in ParameterOutputPath.

    .PARAMETER Name
    [Optional] The base name of Azure Resources (Windows Package Manager REST source components) that will be created. Required if not PublishAzureFunctionOnly.

    .PARAMETER ResourceGroup
    [Optional] The name of the Resource Group that the Windows Package Manager REST source will reside. All Azure
    Resources will be updated in in this Resource Group (Default: WinGetRestSource)

    .PARAMETER SubscriptionName
    [Optional] The name of the subscription that will be used to host the Windows Package Manager REST source. (Default: Current connected subscription)

    .PARAMETER TemplateFolderPath
    [Optional] The directory containing required ARM templates. (Default: $PSScriptRoot\..\Data\ARMTemplates)

    .PARAMETER ParameterOutputPath
    [Optional] The directory containing ARM Template Parameter files. If existing ARM Template Parameter files are found, they will be used for Windows Package Manager REST source update without modification.
    If ARM Template Parameter files are not found, new ARM Template Parameter files with default values will be created. (Default: Current Directory\Parameters)

    .PARAMETER RestSourcePath
    [Optional] Path to the compiled Azure Function (Windows Package Manager REST source) Zip file. (Default: $PSScriptRoot\..\Data\WinGet.RestSource.Functions.zip)

    .PARAMETER PublisherName
    [Optional] The WinGet rest source publisher name. (Default: Signed in user email Or WinGetRestSource@DomainName)

    .PARAMETER PublisherEmail
    [Optional] The WinGet rest source publisher email. (Default: Signed in user email Or WinGetRestSource@DomainName)

    .PARAMETER ImplementationPerformance
    [Optional] ["Developer", "Basic", "Enhanced"] specifies the performance of the Azure Resources to be created for the Windows Package Manager REST source.
    | Preference | Description                                                                                                             |
    |------------|-------------------------------------------------------------------------------------------------------------------------|
    | Developer  | Specifies lowest cost for developing the Windows Package Manager REST source. Uses free-tier options when available.    |
    | Basic      | Specifies a basic functioning Windows Package Manager REST source.                                                      |
    | Enhanced   | Specifies a higher tier functionality with data replication across multiple data centers.                               |

    Note for updating Windows Package Manager REST source, performance downgrading is not allowed by Azure Resources used in Windows Package Manager REST source.

    (Default: Basic)

    .PARAMETER RestSourceAuthentication
    [Optional] ["None", "MicrosoftEntraId"] The Windows Package Manager REST source authentication type. (Default: None)

    .PARAMETER MicrosoftEntraIdResource
    [Optional] Microsoft Entra Id authentication resource. (Default: None)

    .PARAMETER MicrosoftEntraIdResourceScope
    [Optional] Microsoft Entra Id authentication resource scope. (Default: None)

    .PARAMETER MaxRetryCount
    [Optional] Max ARM Templates deployment retry count upon failure. (Default: 3)

    .PARAMETER FunctionName
    [Optional] The Azure Function name. Required if PublishAzureFunctionOnly is specified. (Default: None)

    .PARAMETER PublishAzureFunctionOnly
    [Optional] If specified, only performs Azure Function publish. (Default: False)

    .EXAMPLE
    Update-WinGetSource -Name "contosorestsource" -InformationAction Continue -Verbose

    Updates the Windows Package Manager REST source in Azure with resources named "contosorestsource" with the basic level performance.

    .EXAMPLE
    Update-WinGetSource -Name "contosorestsource" -ResourceGroup "WinGet" -SubscriptionName "Visual Studio Subscription" -ParameterOutput "C:\WinGet" -ImplementationPerformance "Basic" -InformationAction Continue -Verbose

    Updates the Windows Package Manager REST source in Azure with resources named "contosorestsource" with the basic level performance in the "Visual Studio Subscription" subscription.

    .EXAMPLE
    Update-WinGetSource -Name "contosorestsource" -ResourceGroup "WinGet" -RestSourceAuthentication "MicrosoftEntraId" -MicrosoftEntraIdResource "GUID" -MicrosoftEntraIdResourceScope "user-impersonation" -InformationAction Continue -Verbose

    Updates the Windows Package Manager REST source in Azure with resources named "contosorestsource" with the basic level performance.
    Uses existing Microsoft Entra Id app registration.

    .EXAMPLE
    Update-WinGetSource -Name "contosorestsource" -PublishAzureFunctionOnly -InformationAction Continue -Verbose

    Updates the Windows Package Manager REST source in Azure with resources named "contosorestsource" with publishing Azure Function only.

    #>
    PARAM(
        [Parameter(Mandatory=$false)] [string]$Name,
        [Parameter(Mandatory=$false)] [string]$ResourceGroup = "WinGetRestSource",
        [Parameter(Mandatory=$false)] [string]$SubscriptionName = "",
        [Parameter(Mandatory=$false)] [string]$TemplateFolderPath = "$PSScriptRoot\..\Data\ARMTemplates",
        [Parameter(Mandatory=$false)] [string]$ParameterOutputPath = "$($(Get-Location).Path)\Parameters",
        [Parameter(Mandatory=$false)] [string]$RestSourcePath = "$PSScriptRoot\..\Data\WinGet.RestSource.Functions.zip",
        [Parameter(Mandatory=$false)] [string]$PublisherName = "",
        [Parameter(Mandatory=$false)] [string]$PublisherEmail = "",
        [ValidateSet("Developer", "Basic", "Enhanced")]
        [Parameter(Mandatory=$false)] [string]$ImplementationPerformance = "Basic",
        [ValidateSet("None", "MicrosoftEntraId")]
        [Parameter(Mandatory=$false)] [string]$RestSourceAuthentication = "None",
        [Parameter(Mandatory=$false)] [string]$MicrosoftEntraIdResource = "",
        [Parameter(Mandatory=$false)] [string]$MicrosoftEntraIdResourceScope = "",
        [Parameter(Mandatory=$false)] [int]$MaxRetryCount = 3,
        [Parameter(Mandatory=$false)] [string]$FunctionName = "",
        [Parameter()] [switch]$PublishAzureFunctionOnly
    )

    $TemplateFolderPath = [System.IO.Path]::GetFullPath($TemplateFolderPath, $pwd.Path)
    $ParameterOutputPath = [System.IO.Path]::GetFullPath($ParameterOutputPath, $pwd.Path)
    $RestSourcePath = [System.IO.Path]::GetFullPath($RestSourcePath, $pwd.Path)

    ## Check input paths
    if (!$(Test-Path -Path $TemplateFolderPath)) {
        Write-Error "REST Source Function Code is missing in specified path ($TemplateFolderPath)"
        return $false
    }
    if (!$(Test-Path -Path $RestSourcePath)) {
        Write-Error "REST Source Function Code is missing in specified path ($RestSourcePath)"
        return $false
    }

    ## Create folder for the Parameter output path
    $Result = New-Item -ItemType Directory -Path $ParameterOutputPath -Force
    if ($Result) {
        Write-Verbose -Message "Created Directory to contain the ARM Parameter files ($($Result.FullName))."
    }
    else {
        Write-Error "Failed to create ARM parameter files output path. Path: $ParameterOutputPath"
        return $false
    }

    ## Connects to Azure, if not already connected.
    Write-Information "Validating connection to azure, will attempt to connect if not already connected."
    $Result = Connect-ToAzure -SubscriptionName $SubscriptionName
    if (!($Result)) {
        Write-Error "Failed to connect to Azure. Please run Connect-AzAccount to connect to Azure, or re-run the cmdlet and enter your credentials."
        return $false
    }

    ## Check resource group exists
    $GetResult = Get-AzResourceGroup -Name $ResourceGroup
    if (!$GetResult) {
        Write-Error "Failed to get Azure Resource Group. Name: $ResourceGroup"
        return $false
    }
    $Region = $GetResult.Location

    if ($PublishAzureFunctionOnly) {
        if ([string]::IsNullOrWhiteSpace($FunctionName)) {
            Write-Error "FunctionName is null or empty"
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

            Write-Error "Failed to publishing the Function App. $DeployError" -TargetObject $ErrReturnObject
            return $false
        }

        ## Restart the Function App
        Write-Verbose "Restarting Azure Function."
        if (!$(Restart-AzFunctionApp -Name $FunctionName -ResourceGroupName $ResourceGroup -Force -PassThru)) {
            Write-Error "Failed to restart Function App. Name: $FunctionName"
            return $false
        }
    }
    else {
        if ([string]::IsNullOrWhiteSpace($Name)) {
            Write-Error "Name is null or empty"
            return $false
        }

        ## Check Microsoft Entra Id input
        if ($RestSourceAuthentication -eq "MicrosoftEntraId" -and !$MicrosoftEntraIdResource) {
            Write-Error "When Microsoft Entra Id authentication is requested, MicrosoftEntraIdResource should be provided."
            return $false
        }

        ## Creates the ARM files
        $ARMObjects = New-ARMParameterObjects -ParameterFolderPath $ParameterOutputPath -TemplateFolderPath $TemplateFolderPath -Name $Name -Region $Region -ImplementationPerformance $ImplementationPerformance -PublisherName $PublisherName -PublisherEmail $PublisherEmail -RestSourceAuthentication $RestSourceAuthentication -MicrosoftEntraIdResource $MicrosoftEntraIdResource -MicrosoftEntraIdResourceScope $MicrosoftEntraIdResourceScope -ForUpdate
        if (!$ARMObjects) {
            Write-Error "Failed to create ARM parameter objects."
            return $false
        }

        ## Verifies ARM Parameters are correct
        $Result = Test-ARMTemplates -ARMObjects $ARMObjects -ResourceGroup $ResourceGroup
        if($Result){
            $ErrReturnObject = @{
                ARMObjects    = $ARMObjects
                ResourceGroup = $ResourceGroup
                Result        = $Result
            }

            Write-Error -Message "Testing found an error with the ARM template or parameter files. Error: $err" -TargetObject $ErrReturnObject
            return $false
        }

        ## Creates Azure Objects with ARM Templates and Parameters
        $Attempt = 0
        $Retry = $false
        do {
            $Attempt++
            $Retry = $false

            $Result = New-ARMObjects -ARMObjects ([ref]$ARMObjects) -RestSourcePath $RestSourcePath -ResourceGroup $ResourceGroup
            if (!$Result) {
                if ($Attempt -lt $MaxRetryCount) {
                    $Retry = $true
                    Write-Verbose "Retrying deployment after 15 seconds."
                    Start-Sleep -Seconds 15
                }
                else {
                    Write-Error "Failed to create Azure resources for WinGet rest source."
                    return $false
                }
            }
        } while ($Retry)
    }

    return $true
}

# SIG # Begin signature block
# MIIoUgYJKoZIhvcNAQcCoIIoQzCCKD8CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBQeeHb2LTNr8w+
# 3bw3hJNtRn6AlAnTZc34kNE+Ad81UaCCDYUwggYDMIID66ADAgECAhMzAAAEhJji
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
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIHCj
# Ndfwh2SnGLeACBb5na3zucOIQO84if9BE3mEetamMEIGCisGAQQBgjcCAQwxNDAy
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20wDQYJKoZIhvcNAQEBBQAEggEAgt7Hz8s8uSh/ec6Ypqv390mGxqMFGH1e28UW
# 7+PayhhuNCI6J6doar8jPXagWmHVrsb+jBFjqGjZvvQQgRT9xCJ4IJZXHQUWic3V
# qg9EMj4jUXzoLr4nQ42QejW3o2uV3k/mJOQbHvStbTY+JRnLVKI39peLiEG3rD8Y
# 2/GQbwhE3rURDiYU7nz6n/b0dN0TNfPmP+45tfZZIV+P+rU6d8yeVef207cSy8M4
# k3/iilGb1CdIulP6uMnOU7XLkMpymqxt/vpQVZEHixfv1QJNoGTy0NEQj0zF/0Vb
# 4bS+KKepZDDYuMHP63Q3Dy+51PoEbTfU1Gu0Jb/gO2Ixcb/lAqGCF60wghepBgor
# BgEEAYI3AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheCAgEDMQ8wDQYJYIZI
# AWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGE
# WQoDATAxMA0GCWCGSAFlAwQCAQUABCDap6vfVwfYykfNwByd46ePv4iHOm3w39P1
# z18jWQ/kowIGaHpV/1n7GBMyMDI1MDcyNTAwMTI1OC40MzJaMASAAgH0oIHZpIHW
# MIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQL
# EyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsT
# Hm5TaGllbGQgVFNTIEVTTjo0MzFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEfswggcoMIIFEKADAgECAhMzAAAB+vs7
# RNN3M8bTAAEAAAH6MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwMB4XDTI0MDcyNTE4MzExMVoXDTI1MTAyMjE4MzExMVowgdMxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jv
# c29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVs
# ZCBUU1MgRVNOOjQzMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# yhZVBM3PZcBfEpAf7fIIhygwYVVP64USeZbSlRR3pvJebva0LQCDW45yOrtpwIpG
# yDGX+EbCbHhS5Td4J0Ylc83ztLEbbQD7M6kqR0Xj+n82cGse/QnMH0WRZLnwggJd
# enpQ6UciM4nMYZvdQjybA4qejOe9Y073JlXv3VIbdkQH2JGyT8oB/LsvPL/kAnJ4
# 5oQIp7Sx57RPQ/0O6qayJ2SJrwcjA8auMdAnZKOixFlzoooh7SyycI7BENHTpkVK
# rRV5YelRvWNTg1pH4EC2KO2bxsBN23btMeTvZFieGIr+D8mf1lQQs0Ht/tMOVdah
# 14t7Yk+xl5P4Tw3xfAGgHsvsa6ugrxwmKTTX1kqXH5XCdw3TVeKCax6JV+ygM5i1
# NroJKwBCW11Pwi0z/ki90ZeO6XfEE9mCnJm76Qcxi3tnW/Y/3ZumKQ6X/iVIJo7L
# k0Z/pATRwAINqwdvzpdtX2hOJib4GR8is2bpKks04GurfweWPn9z6jY7GBC+js8p
# SwGewrffwgAbNKm82ZDFvqBGQQVJwIHSXpjkS+G39eyYOG2rcILBIDlzUzMFFJbN
# h5tDv3GeJ3EKvC4vNSAxtGfaG/mQhK43YjevsB72LouU78rxtNhuMXSzaHq5fFiG
# 3zcsYHaa4+w+YmMrhTEzD4SAish35BjoXP1P1Ct4Va0CAwEAAaOCAUkwggFFMB0G
# A1UdDgQWBBRjjHKbL5WV6kd06KocQHphK9U/vzAfBgNVHSMEGDAWgBSfpxVdAF5i
# XYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRp
# bWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1Ud
# JQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsF
# AAOCAgEAuFbCorFrvodG+ZNJH3Y+Nz5QpUytQVObOyYFrgcGrxq6MUa4yLmxN4xW
# dL1kygaW5BOZ3xBlPY7Vpuf5b5eaXP7qRq61xeOrX3f64kGiSWoRi9EJawJWCzJf
# UQRThDL4zxI2pYc1wnPp7Q695bHqwZ02eaOBudh/IfEkGe0Ofj6IS3oyZsJP1yat
# cm4kBqIH6db1+weM4q46NhAfAf070zF6F+IpUHyhtMbQg5+QHfOuyBzrt67CiMJS
# KcJ3nMVyfNlnv6yvttYzLK3wS+0QwJUibLYJMI6FGcSuRxKlq6RjOhK9L3QOjh0V
# CM11rHM11ZmN0euJbbBCVfQEufOLNkG88MFCUNE10SSbM/Og/CbTko0M5wbVvQJ6
# CqLKjtHSoeoAGPeeX24f5cPYyTcKlbM6LoUdO2P5JSdI5s1JF/On6LiUT50adpRs
# tZajbYEeX/N7RvSbkn0djD3BvT2Of3Wf9gIeaQIHbv1J2O/P5QOPQiVo8+0AKm6M
# 0TKOduihhKxAt/6Yyk17Fv3RIdjT6wiL2qRIEsgOJp3fILw4mQRPu3spRfakSoQe
# 5N0e4HWFf8WW2ZL0+c83Qzh3VtEPI6Y2e2BO/eWhTYbIbHpqYDfAtAYtaYIde87Z
# ymXG3MO2wUjhL9HvSQzjoquq+OoUmvfBUcB2e5L6QCHO6qTO7WowggdxMIIFWaAD
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
# Hm5TaGllbGQgVFNTIEVTTjo0MzFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA94Z+bUJn+nKw
# BvII6sg0Ny7aPDaggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAx
# MDANBgkqhkiG9w0BAQsFAAIFAOwsvRQwIhgPMjAyNTA3MjQxNDA5MjRaGA8yMDI1
# MDcyNTE0MDkyNFowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA7Cy9FAIBADAHAgEA
# AgILDjAHAgEAAgISIDAKAgUA7C4OlAIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgor
# BgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBCwUA
# A4IBAQCtiG6LcX5NQgZFrVpDqMQNrFVdaOOzlJjfqDJU1pEvj242lWsLfYeLiLQC
# 6KeXN6R81QyHXngpbkgeR1tSg1Q6wMiA8xw1PYKptpR8XbPXxlZgMPRIJEmcpgFz
# XxGvYg8YLE+FSt7/bwyCDqrblWp1+0C2MK8igZiPpLpyzcqZIy4JUR8vqQEVLx7L
# sdramwiHPNa+EiiViYuaJ74hpxhqXh/GwjSr1Eo7mDRUJqGf23j/mtEbPdJrDCqK
# 4cKdN5JuDhU2a1V52/e0VaCnakqLrhURYR5rRGxrNeIpvDquRiaa93a9vOqMuKx/
# vGELgsKhSP11Pxc8w52qnLlxLfZtMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAH6+ztE03czxtMAAQAAAfowDQYJYIZIAWUD
# BAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0B
# CQQxIgQgK1+5bc1dguCIl6NQPZ18/eu8nlTcgcepQltXse0+ApkwgfoGCyqGSIb3
# DQEJEAIvMYHqMIHnMIHkMIG9BCB98n8tya8+B2jjU/dpJRIwHwHHpco5ogNStYoc
# bkOeVjCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAB
# +vs7RNN3M8bTAAEAAAH6MCIEIGfduYAgQ8TkYPH530hgJ2uEX9YiKmnmk9xqhtpo
# rcJ0MA0GCSqGSIb3DQEBCwUABIICAAxvWad46Arm/l3WNjRrssSeJG+jzYqR91XX
# 9+liAExyAPKW+hLVqtRG6tnSwvuw8vr9Dv8JEmgiBtKa9LThjfavfpEt5FfVloIM
# gL7Xy2t8XsvKcuD76sTY0XIOWw2ithQzTnPegYGljsIPaByx0yeQtQfaDRVB5yiA
# EYAl6rFLZCRS5KGcoCqAn6VHrkHDkS9WfWhYWpkgP1bcriRheU3bZ8t8MuTdagek
# RhuWOnfcVD+3yDoFb/DN3NQBcouvhK1Qsu9ZlUyYSvYWLtxYQDKFRvoKz9UuQZKp
# hYXmBP0a8fSknVpeRzGEyEU2d0q5JZRMFXAtoJbgW4ijsv9bMnw9hpgHuIFF8CiE
# FxoHyza/gqzE76jZrN7owidlLSHbeEqz/bJOWM9tMI6wu9xO0V03euvyGrMaPELM
# QgINBiZAVfUqfkqGEdPJCn6lmfg7fjH/uOmhWqI7mLLPRi5TbMG+e6r3Vk9zvXeF
# yKloUNZDHyHgM1+FqJzlwClLUM85+2CsZe/aAKUpYCPWEujR0ohxNBwIksd5pYZQ
# s5c8wz6QukXxXpokZPKuL8eKVCEEPTXkl/rfsN+k18xt++aDFvZD7YzHPMWvnPPJ
# 7htjRwoIevHxZftMCCElxHGXdVEsVdiC48NQWABdACGKyjxeib6bZF9Ex/1SxhFg
# 4mHmd1sZ
# SIG # End signature block
