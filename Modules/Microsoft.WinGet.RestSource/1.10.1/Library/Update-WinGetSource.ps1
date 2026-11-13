# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
function Update-WinGetSource {
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
    param(
        [Parameter(Mandatory = $false)] [string]$Name,
        [Parameter(Mandatory = $false)] [string]$ResourceGroup = 'WinGetRestSource',
        [Parameter(Mandatory = $false)] [string]$SubscriptionName = '',
        [Parameter(Mandatory = $false)] [string]$TemplateFolderPath = "$PSScriptRoot\..\Data\ARMTemplates",
        [Parameter(Mandatory = $false)] [string]$ParameterOutputPath = "$($(Get-Location).Path)\Parameters",
        [Parameter(Mandatory = $false)] [string]$RestSourcePath = "$PSScriptRoot\..\Data\WinGet.RestSource.Functions.zip",
        [Parameter(Mandatory = $false)] [string]$PublisherName = '',
        [Parameter(Mandatory = $false)] [string]$PublisherEmail = '',
        [ValidateSet('Developer', 'Basic', 'Enhanced')]
        [Parameter(Mandatory = $false)] [string]$ImplementationPerformance = 'Basic',
        [ValidateSet('None', 'MicrosoftEntraId')]
        [Parameter(Mandatory = $false)] [string]$RestSourceAuthentication = 'None',
        [Parameter(Mandatory = $false)] [string]$MicrosoftEntraIdResource = '',
        [Parameter(Mandatory = $false)] [string]$MicrosoftEntraIdResourceScope = '',
        [Parameter(Mandatory = $false)] [int]$MaxRetryCount = 3,
        [Parameter(Mandatory = $false)] [string]$FunctionName = '',
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
    } else {
        Write-Error "Failed to create ARM parameter files output path. Path: $ParameterOutputPath"
        return $false
    }

    ## Connects to Azure, if not already connected.
    Write-Information 'Validating connection to azure, will attempt to connect if not already connected.'
    $Result = Connect-ToAzure -SubscriptionName $SubscriptionName
    if (!($Result)) {
        Write-Error 'Failed to connect to Azure. Please run Connect-AzAccount to connect to Azure, or re-run the cmdlet and enter your credentials.'
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
            Write-Error 'FunctionName is null or empty'
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

            Write-Error "Failed to publishing the Function App. $DeployError" -TargetObject $ErrReturnObject
            return $false
        }

        ## Restart the Function App
        Write-Verbose 'Restarting Azure Function.'
        if (!$(Restart-AzFunctionApp -Name $FunctionName -ResourceGroupName $ResourceGroup -Force -PassThru)) {
            Write-Error "Failed to restart Function App. Name: $FunctionName"
            return $false
        }
    } else {
        if ([string]::IsNullOrWhiteSpace($Name)) {
            Write-Error 'Name is null or empty'
            return $false
        }

        ## Check Microsoft Entra Id input
        if ($RestSourceAuthentication -eq 'MicrosoftEntraId' -and !$MicrosoftEntraIdResource) {
            Write-Error 'When Microsoft Entra Id authentication is requested, MicrosoftEntraIdResource should be provided.'
            return $false
        }

        ## Creates the ARM files
        $ARMObjects = New-ARMParameterObjects -ParameterFolderPath $ParameterOutputPath -TemplateFolderPath $TemplateFolderPath -Name $Name -Region $Region -ImplementationPerformance $ImplementationPerformance -PublisherName $PublisherName -PublisherEmail $PublisherEmail -RestSourceAuthentication $RestSourceAuthentication -MicrosoftEntraIdResource $MicrosoftEntraIdResource -MicrosoftEntraIdResourceScope $MicrosoftEntraIdResourceScope -ForUpdate
        if (!$ARMObjects) {
            Write-Error 'Failed to create ARM parameter objects.'
            return $false
        }

        ## Verifies ARM Parameters are correct
        $Result = Test-ARMTemplates -ARMObjects $ARMObjects -ResourceGroup $ResourceGroup
        if ($Result) {
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
                    Write-Verbose 'Retrying deployment after 15 seconds.'
                    Start-Sleep -Seconds 15
                } else {
                    Write-Error 'Failed to create Azure resources for WinGet rest source.'
                    return $false
                }
            }
        } while ($Retry)
    }

    return $true
}

# SIG # Begin signature block
# MIInUwYJKoZIhvcNAQcCoIInRDCCJ0ACAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCATuH8walZG//Z4
# Dq9A9b/sUa1/gcXINwXJMHQdQPnz0KCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
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
# Ql0v4q8J/AUmQN5W4n101cY2L4A7GTQG1h32HHAvfQESWP0xghngMIIZ3AIBATBu
# MFcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# KDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIc
# +s3Fm+gvfsQAAAAAAhwwDQYJYIZIAWUDBAIBBQCggZAwGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIEIAQRKxOoeaZhUuUS3V+OsABkZDPm
# 0LNHR+m7GHDD6TJNMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBv
# AGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAE
# ggEAlpDTA/H6lDy1PTP6Zcd7zcss/GAb5yWms44ct6nDLyoZSJg73/qJfHo67Q1t
# pMrQGaCpcG46WDBF5PALK9/oRcLS/lXTCsxpaC2Svsw/LBfsqqg/9A5KLQySOD62
# /TzRQ8hX/6Wtz1EammaghWAle2eZwBa7/khGeYXXo2h3JVatcKvp0JUHmkkfEK7V
# 1JpXKYUP9+EFl4x1FQIW82+UJmQuK3PFRq6rQTlbHmjsNzqGx8lL5DbtVTjx6NTn
# qWMPTZ0PTV1NQCFnirPJTYr7tsHioASUXnq76wvxFZs2y6AturlCJ+i5wUnP5uUy
# cHdjyALSNgsTWE3eUrBsn8CjvaGCF7AwghesBgorBgEEAYI3AwMBMYIXnDCCF5gG
# CSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG
# 9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCBCV61uerNvx9F1zTBlj/odT34GBPyDieTaINRvIsi1kwIGaq0oragKGBMy
# MDI2MDkyNTIxNDM1NS4xMDJaMASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFu
# ZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo2
# QjA1LTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vy
# dmljZaCCEf4wggcoMIIFEKADAgECAhMzAAACEUUYOZtDz/xsAAEAAAIRMA0GCSqG
# SIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI1MDgx
# NDE4NDgxM1oXDTI2MTExMzE4NDgxM1owgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjZCMDUtMDVF
# MC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIIC
# IjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAz7m7MxAdL5Vayrk7jsMo3Gnh
# N85ktHCZEvEcj4BIccHKd/NKC7uPvpX5dhO63W6VM5iCxklG8qQeVVrPaKvj8dYY
# JC7DNt4NN3XlVdC/voveJuPPhTJ/u7X+pYmV2qehTVPOOB1/hpmt51SzgxZczMdn
# Fl+X2e1PgutSA5CAh9/Xz5NW0CxnYVz8g0Vpxg+Bq32amktRXr8m3BSEgUs8jgWR
# PVzPHEczpbhloGGEfHaROmHhVKIqN+JhMweEjU2NXM2W6hm32j/QH/I/KWqNNfYc
# hHaG0xJljVTYoUKPpcQDuhH9dQKEgvGxj2U5/3Fq1em4dO6Ih04m6R+ttxr6Y8oR
# JH9ZhZ3sciFBIvZh7E2YFXOjP4MGybSylQTPDEFAtHHgpkskeEUhsPDR9VvWWhek
# hQx3qXaAKh+AkLmz/hpE3e0y+RIKO2AREjULJAKgf+R9QnNvqMeMkz9PGrjsijqW
# GzB2k2JNyaUYKlbmQweOabsCioiY2fJbimjVyFAGk5AeYddUFxvJGgRVCH7BeBPK
# Aq7MMOmSCTOMZ0Sw6zyNx4Uhh5Y0uJ0ZOoTKnB3KfdN/ba/eKHFeEhi3WqAfzTxi
# y0rMvhsfsXZK7zoclqaRvVl8Q48J174+eyriypY9HhU+ohgiYi4uQGDDVdTDeKDt
# oC/hD2Cn+ARzwE1rFfECAwEAAaOCAUkwggFFMB0GA1UdDgQWBBRifUUDwOnqIcvf
# b53+yV0EZn7OcDAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNV
# HR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2Ny
# bC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYI
# KwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAy
# MDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMI
# MA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEApEKdnMeIIUiU6Pat
# Z/qbrwiDzYUMKRczC4Bp/XY1S9NmHI+2c3dcpwH2SOmDfdvIIqt7mRrgvBPYOvJ9
# CtZS5eeIrsObC0b0ggKTv2wrTgWG+qktqNFEhQeipdURNLN68uHAm5edwBytd1kw
# y5r6B93klxDsldOmVWtw/ngj7knN09muCmwr17JnsMFcoIN/H59s+1RYN7Vid4+7
# nj8FcvYy9rbZOMndBzsTiosF1M+aMIJX2k3EVFVsuDL7/R5ppI9Tg7eWQOWKMZHP
# dsA3ZqWzDuhJqTzoFSQShnZenC+xq/z9BhHPFFbUtfjAoG6EDPjSQJYXmogja8OE
# a19xwnh3wVufeP+ck+/0gxNi7g+kO6WaOm052F4siD8xi6Uv75L7798lHvPThcxH
# HsgXqMY592d1wUof3tL/eDaQ0UhnYCU8yGkU2XJnctONnBKAvURAvf2qiIWDj4Lp
# cm0zA7VuofuJR1Tpuyc5p1ja52bNZBBVqAOwyDhAmqWsJXAjYXnssC/fJkee314F
# h+GIyMgvAPRScgqRZqV16dTBYvoe+w1n/wWs/ySTUsxDw4T/AITcu5PAsLnCVpAr
# DrFLRTFyut+eHUoG6UYZfj8/RsuQ42INse1pb/cPm7G2lcLJtkIKT80xvB1LiaNv
# PTBVEcmNSvFUM0xrXZXcYcxVXiYwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZ
# AAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMDAeFw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVa
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0BAQEF
# AAOCAg8AMIICCgKCAgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1
# V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY6GB9
# alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9cmmv
# Haus9ja+NSZk2pg7uhp7M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN7928
# jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDuaRr3t
# pK56KTesy+uDRedGbsoy1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEe
# HT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2K26o
# ElHovwUDo9Fzpk03dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4C
# vEJoLhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZki1ug
# poMhXV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXps
# xREdcu+N+VLEhReTwDwV2xo3xwgVGD94q0W29R6HXtqPnhZyacaue7e3PmriLq0C
# AwEAAaOCAd0wggHZMBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYE
# FCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJlpxtT
# NRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5o
# dG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBD
# AEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZW
# y4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5t
# aWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAt
# MDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0y
# My5jcnQwDQYJKoZIhvcNAQELBQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/ypb+pc
# FLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulmZzpT
# Td2YurYeeNg2LpypglYAA7AFvonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM9W0j
# VOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3
# +SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4FOmR
# sqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSw
# ethQ/gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5b
# RAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVXVAmx
# aQFEfnyhYWxz/gq77EFmPWn9y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsX
# HRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0
# W2rRnj7tfqAxM328y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0
# HVUzWLOhcGbyoYIDWTCCAkECAQEwggEBoYHZpIHWMIHTMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFu
# ZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo2
# QjA1LTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vy
# dmljZaIjCgEBMAcGBSsOAwIaAxUAKyp8q2VdgAq1VGkzd7PZwV6zNc2ggYMwgYCk
# fjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
# Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIF
# AO5g4N0wIhgPMjAyNjA5MjUxMjAwMjlaGA8yMDI2MDkyNjEyMDAyOVowdzA9Bgor
# BgEEAYRZCgQBMS8wLTAKAgUA7mDg3QIBADAKAgEAAgIB0gIB/zAHAgEAAgISVTAK
# AgUA7mIyXQIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIB
# AAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBCwUAA4IBAQBr4xKR3OSBnzVz
# SC9hmcE7cG3NElRvxmuLGXcFAwk/vMk4mv6HAd7JR05YuGwwVs/pDJOxIVM9gaU0
# Tkiq2JUih3YTXdaZJpcLrxPsu5t3XvJJWD6awEVJnzWzSrUjK6HYjVeUuu892x6j
# JXDL/x+kq6pddqqDnpdtsYBtz01gqVEkShQblii4H5cfz+E8c4OzxxBeS+zKulpn
# yxF7swfukYZPqcbQYeo4Wt235tcXvuyswQsmMQ9HOEStnZ80yyyBXDutl6kMMHQR
# NEfzFVI27mvjtIzmcPnrblYxOdlrwGJSuk48UeLAHMDCUwz5m1nqACwmuEdm3MBD
# SP1eHI8/MYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTACEzMAAAIRRRg5m0PP/GwAAQAAAhEwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqG
# SIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQg8CzdCHmAmWvb
# 4L5v0rcnlxuZMOZ7FXGBbbaRE3R3uy8wgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHk
# MIG9BCAsrTOpmu+HTq1aXFwvlhjF8p2nUCNNCEX/OWLHNDMmtzCBmDCBgKR+MHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACEUUYOZtDz/xsAAEAAAIR
# MCIEIHlk9kxxb0zL4QY4Ep59rjBmlclMUCa623ZfZnWdfSGqMA0GCSqGSIb3DQEB
# CwUABIICAMBd1WchgWZjjp2t0l+a1KBdmr9nzhddfSDGnwB8+3QFeTTBuZkG+dBc
# Kpk9fz/A7z/2257hccO8q3HfUe/dLolLaBJ7tzoR7+IwlyfnM308BoDRYF/Ne+yK
# yLJH90hGjCU5nqTiUgO3RVcn9tM6VH2NJmAHGJ33a0tdH+LPMKkvU+XbRhfca8lW
# Z6tPhjPlfxK3LHAjaFSaYEYVI6t83gOuMzjWNqRHHuWrrHsq69z3XTqWW1w4bawd
# GFzmYKBe7JPyeyRLJIIG0BKYnpQ08mr+nMuBV18Z/aAmX7igcao8eQqqXyqUcPdg
# VbPv1VqY4iPwYcCkL1eCFhr0LCUpicjyiE1OkZtON1POxUZ6D4JjMzBjYC6Z1foe
# ZVNWK7SUszzeYH+4al7zj3cgGE30WoIrQHt5CYEHzgpwS+YIZeBHskKs4r0WOoQC
# haiUuw2TiEScAOK9QNe7MnAY5aRZPcYiAQEfxOsrW/+xjMzVosKxaufKY9vPr9xf
# IZsTNSRldkNN38zNPRdv68e3b2fOFVlfM6PoF55UPGNE8pSDLby4jezsnLGDbiSI
# qppI7BP6QML4HaBezcRHSnBqjCxbRPsE0HNP1+FDCx6G6S7cdl+HD8CLC3nq6m50
# pQLiVTFPXTg8CoqL0iHsAxR5oSVG6ux/dcp2ZnFhWYfPwN+kEkRf
# SIG # End signature block
