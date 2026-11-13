# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
function Add-WinGetManifest {
    <#
    .SYNOPSIS
    Submits a Manifest to the Windows Package Manager REST source.

    .DESCRIPTION
    Submits a Manifest to the Windows Package Manager REST source.
    Running this function will first connect to the Azure Tenant that hosts the Windows Package Manager REST source. 
    The function will then collect the required URL before retrieving the contents of the Manifest for submission.

    .PARAMETER FunctionName
    Name of the Azure Function that hosts the Windows Package Manager REST source.

    .PARAMETER Path
    Supports input from pipeline. The path to the Manifest file or folder hosting either a JSON or YAML file(s) that will be uploaded to the REST source. 
    This path may contain a single Manifest file, or a folder containing multiple YAML files for a single Manifest. Does not support 
    targeting a single folder containing multiple different Manifests.

    .PARAMETER SubscriptionName
    [Optional] The name of the subscription containing the Windows Package Manager REST source.

    .EXAMPLE
    Add-WinGetManifest -FunctionName "contosorestsource" -Path "C:\AppManifests\Microsoft.PowerToys\PowerToys.json"

    Connects to Azure, then runs the Azure Function "contosorestsource" REST APIs to add the specified Manifest (*.json) 
    to the Windows Package Manager REST source.

    .EXAMPLE
    Add-WinGetManifest -FunctionName "contosorestsource" -Path "C:\AppManifests\Microsoft.PowerToys\"

    Connects to Azure, then runs the Azure Function "contosorestsource" REST APIs to adds the Manifest (*.json / *.yaml) 
    found in the specified folder to the Windows Package Manager REST source.

    .EXAMPLE
    Add-WinGetManifest -FunctionName "contosorestsource" -Path "C:\AppManifests\Microsoft.PowerToys\PowerToys.json" -SubscriptionName "Visual Studio Subscription"

    Connects to Azure and the specified Subscription, then runs the Azure Function "contosorestsource" REST APIs to add the 
    specified Manifest (*.json) to the Windows Package Manager REST source.
    #>

    param(
        [Parameter(Position = 0, Mandatory = $true)]  [string]$FunctionName,
        [Parameter(Position = 1, Mandatory = $true, ValueFromPipeline = $true)] [string]$Path,
        [Parameter(Mandatory = $false)] [string]$SubscriptionName = ''
    )
    begin {
        [WinGetManifest[]] $Return = @()
        
        ###############################
        ## Connects to Azure, if not already connected.
        Write-Verbose -Message 'Validating connection to azure, will attempt to connect if not already connected.'
        $Result = Connect-ToAzure -SubscriptionName $SubscriptionName
        if (!($Result)) {
            Write-Error 'Failed to connect to Azure. Please run Connect-AzAccount to connect to Azure, or re-run the cmdlet and enter your credentials.' -ErrorAction Stop
        }

        ###############################
        ## Gets Resource Group name of the Azure Function
        Write-Verbose -Message 'Determines the Azure Function Resource Group Name'
        $ResourceGroupName = $(Get-AzFunctionApp).Where({ $_.Name -eq $FunctionName }).ResourceGroupName
        if (!$ResourceGroupName) {
            Write-Error "Failed to confirm Azure Function exists in Azure. Please verify and try again. Function Name: $FunctionName" -ErrorAction Stop
        }

        #############################################
        ##############  REST api call  ##############

        ## Specifies the REST api call that will be performed
        $ApiContentType = 'application/json'
        $ApiMethodPost = 'Post'
        $ApiMethodGet = 'Get'
        $ApiMethodPut = 'Put'

        ## Retrieves the Azure Function URL used to add new manifests to the REST source
        Write-Verbose -Message "Retrieving the Azure Function $FunctionName to build out the REST API request."
        $FunctionApp = Get-AzFunctionApp -ResourceGroupName $ResourceGroupName -Name $FunctionName

        $FunctionAppId = $FunctionApp.Id
        $DefaultHostName = $FunctionApp.DefaultHostName
        $FunctionKeyPost = (Invoke-AzResourceAction -ResourceId "$FunctionAppId/functions/ManifestPost" -Action listkeys -Force).default
        $FunctionKeyGet = (Invoke-AzResourceAction -ResourceId "$FunctionAppId/functions/ManifestGet" -Action listkeys -Force).default
        $FunctionKeyPut = (Invoke-AzResourceAction -ResourceId "$FunctionAppId/functions/ManifestPut" -Action listkeys -Force).default
        
        
        ## Creates the API Post Header
        $ApiHeader = New-Object 'System.Collections.Generic.Dictionary[[String],[String]]'
        $ApiHeader.Add('Accept', 'application/json')
        
        $AzFunctionURLBase = 'https://' + $DefaultHostName + '/api/packageManifests/'
    }
    process {
        $Path = [System.IO.Path]::GetFullPath($Path, $pwd.Path)

        ###############################
        ## Gets the content from the Package Manifest (*.JSON, or *.YAML) file for posting to REST source.
        Write-Verbose -Message 'Retrieving a copy of the app Manifest file for submission to WinGet source.'
        $ApplicationManifest = Get-WinGetManifest -Path $Path
        if ($ApplicationManifest.Count -ne 1) {
            Write-Error 'Failed to retrieve a proper manifest. Verify and try again.'
            return
        }

        $Manifest = $ApplicationManifest[0]
        Write-Verbose -Message "Contents of manifest have been retrieved. Package Identifier: $($Manifest.PackageIdentifier)."
        
        Write-Verbose -Message "Confirming that the Package ID doesn't already exist in Azure for $($Manifest.PackageIdentifier)."
        $ApiHeader['x-functions-key'] = $FunctionKeyGet
        $AzFunctionURL = $AzFunctionURLBase + $Manifest.PackageIdentifier
        $Response = Invoke-RestMethod $AzFunctionURL -Headers $ApiHeader -Method $ApiMethodGet -ErrorVariable ErrorInvoke

        if ($ErrorInvoke -or $Response.Data.Count -eq 0) {
            ## No existing manifest retrieved, submit as new manifest
            Write-Verbose "No manifest that matched. Package Identifier: $($Manifest.PackageIdentifier)"

            $ApiMethod = $ApiMethodPost
            $AzFunctionURL = $AzFunctionURLBase
            $ApiHeader['x-functions-key'] = $FunctionKeyPost
        } else {
            ## Existing manifest retrieved, submit as update existing manifest
            Write-Verbose "Found manifest that matched. Package Identifier: $($Manifest.PackageIdentifier)"
            
            if ($Response.Data.Count -gt 1) {
                Write-Error "Found conflicting manifests. Package Identifier: $($Manifest.PackageIdentifier)"
                return
            }
            
            $ApiMethod = $ApiMethodPut
            $AzFunctionURL = $AzFunctionURLBase + $Manifest.PackageIdentifier
            $ApiHeader['x-functions-key'] = $FunctionKeyPut

            ## Merge with prior manifest
            $PriorManifest = [WinGetManifest]::CreateFromObject($Response.Data[0])
            $ApplicationManifest = Get-WinGetManifest -Path $Path -PriorManifest $PriorManifest
            $Manifest = $ApplicationManifest[0]
        }
        
        Write-Verbose -Message "The Manifest will be added using the $ApiMethod REST API."

        $Response = Invoke-RestMethod $AzFunctionURL -Headers $ApiHeader -Method $ApiMethod -Body $Manifest.GetJson() -ContentType $ApiContentType -ErrorVariable ErrorInvoke

        if ($ErrorInvoke) {
            $ErrReturnObject = @{
                AzFunctionURL       = $AzFunctionURL
                ApiMethod           = $ApiMethod
                ApiContentType      = $ApiContentType
                ApplicationManifest = $Manifest.GetJson()
                Response            = $Response
                InvokeError         = $ErrorInvoke
            }

            Write-Error -Message 'Failed to add manifest.' -TargetObject $ErrReturnObject
        } else {
            if ($Response.Data.Count -ne 1) {
                Write-Warning "Returned conflicting manifests after adding the manifest. Package Identifier: $($Manifest.PackageIdentifier)"
            }
            
            foreach ($ResponseData in $Response.Data) {
                Write-Verbose "Parsing through the returned results: $ResponseData"
                $Return += [WinGetManifest]::CreateFromObject($ResponseData)
            }
        }
    }
    end {
        return $Return
    }
}

# SIG # Begin signature block
# MIInQQYJKoZIhvcNAQcCoIInMjCCJy4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDsXQTnttYdQD4u
# Yplqcz2sE8HwgDx9fyio54/wyuJxdKCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
# yE7XD1dIAAAAAAIdMA0GCSqGSIb3DQEBCwUAMFcxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBD
# b2RlIFNpZ25pbmcgUENBIDIwMjQwHhcNMjYwNDE2MTg1OTQzWhcNMjcwNDE1MTg1
# OTQzWjB0MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYD
# VQQDExVNaWNyb3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQDQvewXxx9gZZFC6Ys1WBay8BJ8kGA4JQnH5CMafqOASlTpK9H8
# o5ZXTXt0caVQTNMUPt445wXYD+dFtaKWTwDn1I52oUSrC9vJin1Gsqt+zyKJL5Dg
# 3eQXbQNR61DmMy20GLTIO3SFed9Rfi/ophgCLGFLDR3r0KvHjwMb/jYWS0celV/4
# Lz27LfAekm8v9E5IXaeiXbAUYZKK090n4CVl3JBtbN+9DtI9SNu/yjvozW52/u7R
# X/Ttpa/KDlpuokZ+Zcbvmtd9ur9gFLvZzh41o9MsE/clQtdaFWGvuo6Jua/ntpgk
# ey3E5/vBFe+MJPG6phdnuo6r57ZudCudiI1bAgMBAAGjggGbMIIBlzAOBgNVHQ8B
# Af8EBAMCB4AwHwYDVR0lBBgwFgYKKwYBBAGCN0wIAQYIKwYBBQUHAwMwHQYDVR0O
# BBYEFH6QuMwqcPG0hQlQ6c5jCtTTLrVeMEUGA1UdEQQ+MDykOjA4MR4wHAYDVQQL
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xFjAUBgNVBAUTDTIzMDAxMis1MDc1NTkw
# HwYDVR0jBBgwFoAUf1k/VCHarU/vBeXmo9ctBpQSCDEwYAYDVR0fBFkwVzBVoFOg
# UYZPaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0
# JTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDI0LmNybDBtBggrBgEFBQcBAQRh
# MF8wXQYIKwYBBQUHMAKGUWh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y2VydHMvTWljcm9zb2Z0JTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDI0LmNy
# dDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4ICAQBKTbYOjzwTG/DXGaz9
# s6+fQeaTtDcFmMY+5UyVFCyj7Pv+5i37qfX8lSL/tBIfYQfWsMuBQlfZurJD6r4H
# VJ2CeH+1fgiq8dcHdVKoZ3Sa2qXoX3cq9iS8cVb06B7+5/XJ7I0OxHH9fDsvJ3T3
# w5V/ZtAIFmLrl+P0CtG+92uzRsn0nTbdFjOkLMLWPLAU3THohKRlSEMgFJpPkm5n
# 5UAZ35xX6FWCrDLsSKb555bTifwa8mJBwdlof0bmfYidH+dxZ1FdDxvLnNl9zeKs
# A4kejaaIqqIPguhwAti5Ql7BlTNoJNwxCvBmqW2MQLnCkYN/VVUsR3V2x/rcTNzo
# Bf/Z/SpROvdaA2ZOOd1uioXJt3tdLQ7vHpqpib0KfWr/FWXW10q38VxfCnRQBqzb
# SuztR7nEMuzX7Ck+B/XaPDXd1qh72+QYyB0Z2VzWmO9zsnb9Uq/dwu8LGeQqnyu6
# 7SDGACvnXii2fb9+US492VTnXSnFKyqwgzUyFMtZK1/sHYTv6bG4TtQUygQxTN+Z
# V+aJIlKO2MqZ7bKrAnOzS9m6NgoTdWOq11bTOZwKlIEV/EhV9SWkDmdpR/hPPT2v
# 6TEj4F8PT/zHjRezIU5c/DGlt/VhY/pK0XkJtEyMmmS1BMtjU/rqBZVMIm3dnxQs
# /TBByr+Cf8Z1r7aifQVQ+WSqzjCCBr0wggSloAMCAQICEzMAAAA5O7Y3Gb8GHWcA
# AAAAADkwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRl
# IEF1dGhvcml0eSAyMDExMB4XDTI0MDgwODIwNTQxOFoXDTM2MDMyMjIyMTMwNFow
# VzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEo
# MCYGA1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAyNDCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBANgBnB7jOMeqlRYHNa265v4IY9fH8TKh
# emHfPINe1gpLaV3dhg324WwH06LcHbpnsBukCDNitryo0dtS/EW6I/yEL/bLSY8h
# KpbfQuWusBPr9qazYcDxCW/qnjb5JsI1s8bNOg3bVATvQVL4tcf03aTycsz8QeCd
# M0l/yHRObJ9QqazM1r6VPEOJ7LL+uEEb73w6QCuhs89a1uv1zerOYMnsneRRwCbp
# yW11IcggU0cRKDDq1pjVJzIbIF6+oiXXbReOsgeI8zu1FyQfK0fVkaya8SmVHQ/t
# Of23mZ4W9k0Ri22QW9p3UgSC5OUDktKxxcCmGL6tXLfOGSWHIIV4YrTJTT6PNty5
# REojHJuZHArkF9VnHTERWoTjAzfI3kP+5b4alUdhgAZ7ttOu1bVnXfHaqPYl2rPs
# 20ji03LOVWsh/radgE17es5hL+t6lV0eVHrVhsssROWJuz2MXMCt7iw7lFPG9LXK
# Gjsmonn2gotGdHIuEg5JnJMJVmixd5LRlkmgYRZKzhxSCwyoGIq0PhaA7Y+VPct5
# pCHkijcIIDm0nlkK+0KyepolcqGm0T/GYQRMhHJlGOOmVQop36wUVUYklUy++vDW
# eEgEo4s7hxN6mIbf2MSIQ/iIfMZgJxC69oukMUXCrOC3SkE/xIkgpfl22MM1itkZ
# 35nNXkMolU1lAgMBAAGjggFOMIIBSjAOBgNVHQ8BAf8EBAMCAYYwEAYJKwYBBAGC
# NxUBBAMCAQAwHQYDVR0OBBYEFH9ZP1Qh2q1P7wXl5qPXLQaUEggxMBkGCSsGAQQB
# gjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU
# ci06AjGQQ7kUBU7h6qfHMdEjiTQwWgYDVR0fBFMwUTBPoE2gS4ZJaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0MjAx
# MV8yMDExXzAzXzIyLmNybDBeBggrBgEFBQcBAQRSMFAwTgYIKwYBBQUHMAKGQmh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0MjAx
# MV8yMDExXzAzXzIyLmNydDANBgkqhkiG9w0BAQwFAAOCAgEAFJQfOChP7onn6fLI
# MKrSlN1WYKwDFgAddymOUO3FrM8d7B/W/iQ6DxXsDn7D5W4wMwYeLystcEqfkjz4
# NURRgazyMu5yRzQh4LqjA4tStTcJh1opExo7nn5PuPBYnbu0+THSuVHTe0VTTPVh
# ily/piFrDo3axQ9P4C+Ol5yet+2gTfekICS5xS+cYfSIvgn0JksVBVMYVI5QFu/q
# hnLhsEFEUzG8fvv0hjgkO+lkpV9ty6GkN4vdnd7ya6Q6aR9y34aiM1qmxaxBi6OU
# nyNl6fkuun/diTFnYDLTppOkr/mg5WSfCiDVMNCxtj4wPKC5OmHm1DQIt/MNokbb
# H3UGsFP1QbzsLocuSqLCvH09Io3fDPTmscR9Y75G4qX7RTX8AdBPo0I6OEojf39z
# uFZt0qOHm65YWQE69cZM2ueE1MB05dNNgHK9gTE7zKvK/fg8B2qjW88MT/WF5V5u
# vZGtqa9FSL2RazArA+rDPuf6JGYz4HpgMZHB4S6szWSKYBv0VisCzfxgeU+dquXW
# 9bd0auYlOB58DPcOYKdc3Se94g+xL4pcEhbB54JOgAkwYTu/9dLeH2pDqeJZAABV
# DWRQCaXfO5LgyKwKCLYXpigrZYCjUSBcr+Ve8PFWMhVTQl0v4q8J/AUmQN5W4n10
# 1cY2L4A7GTQG1h32HHAvfQESWP0xghndMIIZ2QIBATBuMFcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIdTRnITtcPV0gAAAAAAh0w
# DQYJYIZIAWUDBAIBBQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJ
# KoZIhvcNAQkEMSIEIOuzNJsa4yTZtd2DJQY2LtNSqvxon0RBRFCkEnqw1SW0MEIG
# CisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAYRBWa8We9CU6CGr0
# H/IVa/YSkkU4KX1Dqunjcb4KOgMprafIfVRSaumayBG5BOX0+RExVledTorosSEi
# 6G4zU0luQbanuDxB+4+M7H5gaOnCKkSocETMERsLHDOIkLIZOcM1QY02Dm3eWbNZ
# xKHB8R5Tj9OyTkxKtLTuPyc1wdJOC+d9XZiof+610JtM7Vs5M2Vc+fPHPaYIipQg
# 0Tph3+PCnSm0TsEivGBWlZau5GNB/UkAn19zRyKryT4GHHVsNLneirQ7iySven4B
# JtQwb5vqgG62GG2a910Im42rgMgNOfxL9A3ZwkehqV2Sn57aq4fUV7Pz+DR+hEcq
# L9CK7KGCF60wghepBgorBgEEAYI3AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4Yw
# gheCAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFF
# MIIBQQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCEudFfo0KgCf7d
# bj+EOTAP51FybV/kVoAyT4vI6ap/1wIGaq8lGnuiGBMyMDI2MDkyNTIxNDUxMi4z
# NTJaMASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExp
# bWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo1NTFBLTA1RTAtRDk0NzEl
# MCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEfswggcoMIIF
# EKADAgECAhMzAAACG9CyuAJn93LPAAEAAAIbMA0GCSqGSIb3DQEBCwUAMHwxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI1MDgxNDE4NDgzMFoXDTI2MTEx
# MzE4NDgzMFowgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# LTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEn
# MCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjU1MUEtMDVFMC1EOTQ3MSUwIwYDVQQD
# ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEF
# AAOCAg8AMIICCgKCAgEAjsWd52ZZkzB5Xe5g/l2GsOjAz30sg6jVxfFJV+w4xIDV
# yaI3LO8bIpmzYul3AZHg50UIQ8PrSRZGpQqFkRNu+o3YKJ4g2uGYBRksHnHYR0uV
# SCQg58ThkYyeplGX3oAvGRVuPIpQtAiTsR76A/gdoU7HDwEbb73bJwTyrbKHhR+W
# aMy9DQHI4k5Qo4+bZDs0kj76bvhJvdGU+S8zxQBp7UAhjJnFqKxIusSITE7zCCR4
# 22ELhkhVVOFqK2w6h1MAvILe76hxRIcPj0SBL2r8O9tx5njU4+tg2rAdU153pmyh
# qazdpUccYBE9wDRFUd/e9CoWx7TdnUicB+Mai7RT6qse7e5aGqX1B7bnj/ZHvrrf
# F+BJEIlS9iDXAUgekvXZ+FZmjvLwP+dN+0/crh++r4e8FknF7EX6IJfnmNeDN/68
# Z59kbaJ1f+P5mnKYfydCeZmxrGpS0taWkDk36D3jPVZflvxrc+1rhCIlM5v9agLE
# FI12QiBTfpOBOBr3AGCPk+eH0+latjQajug+2/BD12qb82500LQytUWT2ota/HYn
# RgSv1jvZ0/dml1FsxWYzOnCrjfdB/7N6pNySt4vn+PGN6dFLim7kxos+B9WfQPez
# Ji3fuKyyDAB9zSHPj1Zu8nZfecZJ9um4zj7DFgvJXTDTnG5qlG4ZdbFRa/rrfzkC
# AwEAAaOCAUkwggFFMB0GA1UdDgQWBBS2vp93/lxLppNK8OkauJ2AvNmIUDAfBgNV
# HSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5o
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBU
# aW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwG
# CCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRz
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNV
# HRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIH
# gDANBgkqhkiG9w0BAQsFAAOCAgEAZkU1XxQD4OTM3GTht32TXShIfPBoMfSsFsBQ
# qFOZqLJOxyJOllIBFpmpvOtGNPkC5Z8ldG8aCpvgFNo/jDWeT5FiW53dAj9KnZxp
# sQ3Pf5fRzSGHRcxEMOdXIVzDJwcZUX0cjfxna7ydNv8eXB/Xk6G6SyrR2OH6S1LH
# MW11m3UvKF+eLjIPl45rximuDCoEd+ad0lOAXA5/vZOKN5n/ePYeP0LRchZX0Q6H
# 8n/ZmSPMlbli3MO851Q09RmT/ZGHa+/Fdy+WLDrwcYykV9mUy/4TbwKw6FtdR6ZP
# HxMdIi1pk8Y2mC/GzCq0LCsH0uTFeQ6Q7Nc3MRmER/3mLWUhbaWHgX1FbYchvR22
# b+Bup+YPR5Q/0BhaaAN6AIBfcGs+u/nJoIByyZKA8cTyCmnUI/4vW6D4vywg3XBF
# f4f2DwFHy/evsC+58KMl+k2wa05X2kK0T/bCPLhaov9ZXyobawfNOLYGiauKT2FW
# vbwZzHIFCTxjBww6Pt5uRvCE/jnUcf/xhlOGMn6iKO9Xt49vZTE2SfIBk/34iLTR
# BJ6H7aGPTTQnza3OfWu1/dRycC6Wl5ons3PjnGXTSKSxXllJPmg6R/ulGonP/UCY
# oJ6mN+EXjfyDLPXLqsr91+VTG1rYzRCjPwBFAHv4EIwaE0ajCrf75eUGI3+oXU0U
# P6rloZ8wggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3
# DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIw
# MAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAx
# MDAeFw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# 5OGmTOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/
# XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1
# hlDcwUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7
# M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3K
# Ni1wjjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy
# 1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF80
# 3RKJ1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQc
# NIIP8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahha
# YQFzymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkL
# iWHzNgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV
# 2xo3xwgVGD94q0W29R6HXtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIG
# CSsGAQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUp
# zxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBT
# MFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYI
# KwYBBQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGG
# MA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186a
# GMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3Br
# aS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsG
# AQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcN
# AQELBQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1
# OdfCcTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYA
# A7AFvonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbz
# aN9l9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6L
# GYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA0j3m
# Sj5mO0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0
# SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxko
# JLo4S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFm
# PWn9y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC482
# 2rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7
# vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDVjCC
# Aj4CAQEwggEBoYHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExp
# bWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo1NTFBLTA1RTAtRDk0NzEl
# MCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsO
# AwIaAxUAhoV6r49M4GBd41K1RYB1Z0f4zuCggYMwgYCkfjB8MQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAO5g4yowIhgPMjAyNjA5
# MjUxMjEwMThaGA8yMDI2MDkyNjEyMTAxOFowdDA6BgorBgEEAYRZCgQBMSwwKjAK
# AgUA7mDjKgIBADAHAgEAAgIQxzAHAgEAAgIZxjAKAgUA7mI0qgIBADA2BgorBgEE
# AYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYag
# MA0GCSqGSIb3DQEBCwUAA4IBAQAmwgY8V8rLlU/+qAQcOj3XFSmaor4jj4rS3vfL
# p1WhsQqj7pcRgmX916f/MrdxtEf0UZ7mGEY3kskaHXHif5Bwf8kgFbM/TJpP+CIO
# XpcoVDFgklycc3ZNVCrBW3Lmc1szglSSbvO0JcCtGTN4p3ck5MTbWD1HEsxYiHmW
# qCyPVpRWO2M13337ZeDhnbGqoBC4pAb+6qTsQCFkUjyn4SjeP7KpiDF8AinRO0Pj
# /982rBadFTNVm5c3ezUAox4qxHNBP7tRhgP1H/vZYO3y75pIwaGrbG/eOEtKjm+y
# OeOJoKHHprMUNqrt5POdXu37I9RPkn3koCcvYShvHhmys19fMYIEDTCCBAkCAQEw
# gZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIb0LK4Amf3cs8A
# AQAAAhswDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0B
# CRABBDAvBgkqhkiG9w0BCQQxIgQgtjqYkJsETMZZkPeH3oJ+QCV5DxQwHGGylYCX
# +yz9RfgwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAwJRSVuD2jmMcQCFXd
# LuJAwDpUVNZ6bc6dfJU83Q2LgDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwAhMzAAACG9CyuAJn93LPAAEAAAIbMCIEICSGNfPk3jtVZG3qIeOt
# OZnXZx4VG5Iqcs2+LpMHAIIsMA0GCSqGSIb3DQEBCwUABIICAE27/QFbuTQ49CT6
# Bh1P7pVt2CH0XbOBZcgiLFJcwWup0TXdtOooNIEZo7gqQ0xznRnjsMvLkGRQQwc0
# FmJkWZXqJhaaYiR48NIPG/CUgTVwvi38BzooavSfG097LMQFdvrlCRS0BK6Xkf5Z
# 0sZR0M9fjeePAw/1KqmPpHd3q5kseBlkoX5kTjE5jOJmw8+XcoCDo1jTecgp5SW0
# ZIrEFRdL5F0reSxg3DY9hRNHobPCF/yBHZ88B2ir52L+IiwlJuDNOfBQ8MdLsVBW
# NlHSNdFdJPoeWW1ivo3CRwPbb/qwqzJMWcg2aHv0QS+nW5anFbet+WDk0op8IXMV
# ENmCRpSwqfsoCsD7nCnkKC/nReSkO9KJWkBHdVtDac6Tw6oMvrXZhcneYTk2IWMV
# Mlc3EjdzCD+HRM8zxrpIR3/j4Dx1mbRu3fpbA1Mbp40Mxx7Fw9PncVHiJj2VJ4Zl
# jXAllZXA3X8wzUmaLvcOBFvcHvagQ+GZixWUj1+GXdmUrwHhYgf5zROB9y8sjpn6
# Yz/Vp9JFu/jhVwX5ciD1se3Fdm3uzm7qJJLca8z9aVlfmoAiDIllJ3odV2cVWTv9
# TT7KOumwZhyJD9/6+uC9hv6jGDXsXIL1uveSBMMUOphZ7uUIVUfh8QF9HHT4ycmz
# 9YUAwd6Q+LDJT2ZMZrMChFwF3s06
# SIG # End signature block
