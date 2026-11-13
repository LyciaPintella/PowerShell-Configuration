# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
function New-MicrosoftEntraIdApp {
    <#
    .SYNOPSIS
    Creates a new Microsoft Entra Id app registration to be used for WinGet rest source Microsoft Entra Id based authentication.

    .DESCRIPTION
    Creates a new Microsoft Entra Id app registration to be used for WinGet rest source Microsoft Entra Id based authentication.
    Always create a new Microsoft Entra Id app registration.
    
    .PARAMETER Name
    Name of the Microsoft Entra Id app to be created.

    .EXAMPLE
    New-MicrosoftEntraIdApp -Name "contosoapp"

    Assumes an active connection to Azure. Creates a new Microsoft Entra Id app named "contosoapp".
    #>

    param(
        [Parameter(Position = 0, Mandatory = $true)] [string]$Name
    )
    
    $Return = @{
        Result        = $false
        Resource      = ''
        ResourceScope = ''
    }
    
    ## Normalize Microsoft Entra Id app name
    $NormalizedName = $Name -replace '[^a-zA-Z0-9-()_.]', ''
    if ($Name -cne $NormalizedName) {
        $Name = $NormalizedName
        Write-Warning "Removed special characters from the Microsoft Entra Id app name (New Name: $Name)."
    }
    
    ## Creating a line break from previous steps
    Write-Information "Microsoft Entra Id app name to be created: $Name"

    $App = New-AzADApplication -DisplayName $Name -AvailableToOtherTenants $false
    if (!$App) {
        Write-Error "Failed to create Microsoft Entra Id app. Name: $Name"
        return $Return
    }

    ## Add App Id Uri
    $AppId = $App.AppId
    $App = Update-AzADApplication -ApplicationId $AppId -IdentifierUri "api://$AppId" -ErrorVariable ErrorUpdate
    if ($ErrorUpdate) {
        Write-Error "Failed to add App Id Uri. Error: $ErrorUpdate"
        return $Return
    }

    ## Add Api scope
    $ScopeId = [guid]::NewGuid().ToString()
    $ScopeName = 'user_impersonation'
    $Api = @{
        oauth2PermissionScopes = @(
            @{
                adminConsentDescription = "Sign in to access $Name WinGet rest source"
                adminConsentDisplayName = 'Access WinGet rest source'
                userConsentDescription  = "Sign in to access $Name WinGet rest source"
                userConsentDisplayName  = 'Access WinGet rest source'
                id                      = $ScopeId
                isEnabled               = $true
                type                    = 'User'
                value                   = $ScopeName
            }
        )
    }
    $App = Update-AzADApplication -ApplicationId $AppId -Api $Api -ErrorVariable ErrorUpdate
    if ($ErrorUpdate) {
        Write-Error "Failed to add Api scope. Error: $ErrorUpdate"
        return $Return
    }

    ## Add authorized client
    $Api = @{
        preAuthorizedApplications = @(
            @{
                appId                  = '7b8ea11a-7f45-4b3a-ab51-794d5863af15'
                delegatedPermissionIds = @($ScopeId)
            }
            @{
                appId                  = '04b07795-8ddb-461a-bbee-02f9e1bf7b46'
                delegatedPermissionIds = @($ScopeId)
            }
            @{
                appId                  = '1950a258-227b-4e31-a9cf-717495945fc2'
                delegatedPermissionIds = @($ScopeId)
            }
        )
    }
    $App = Update-AzADApplication -ApplicationId $AppId -Api $Api -ErrorVariable ErrorUpdate
    if ($ErrorUpdate) {
        Write-Error 'Failed to add authorized clients'
        return $Return
    }

    $Return.Result = $true
    $Return.Resource = $AppId
    $Return.ResourceScope = $ScopeName
    return $Return
}
# SIG # Begin signature block
# MIInQwYJKoZIhvcNAQcCoIInNDCCJzACAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDUSwHNQwgk6NSZ
# 3FE3VAiLg2KzGCApAOz/bbqadRUUn6CCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# 1cY2L4A7GTQG1h32HHAvfQESWP0xghnfMIIZ2wIBATBuMFcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIdTRnITtcPV0gAAAAAAh0w
# DQYJYIZIAWUDBAIBBQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJ
# KoZIhvcNAQkEMSIEIJAAg6My0i9BmvBlByfSJM3Vj11RzeoXN3DyJOZBFYviMEIG
# CisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAKSMIMnJ+T76sPPpB
# T256XK61SPAjTuedQPJYMn2CBKMTTpYigpjr5HcI7qdJAwSbW/cLVGxz1Q9R06dd
# jzJ2th2/iaptm6EclFBNf8cJYRYw+XtiI2q0mXtRJmvT81QKKV80lABZz3DVayHf
# 4M5N0fCBuUV+QQikR/rn5giYW/HfTPb3vzi7Vcmou3nKieXnmhzS4raHf53yjfCL
# dHIW4F7MbERpJw1VK2+5CsBEa9WkjgehJfiLAgevUhwQL11TjYKfQ4dStLpy1MNR
# UMfCOqYy3Rl+W/LGA8SFiXv51uPcI9s5bkZomhvysG+mSaSFcO99hpLHWStYgay2
# 3k33UaGCF68wgherBgorBgEEAYI3AwMBMYIXmzCCF5cGCSqGSIb3DQEHAqCCF4gw
# gheEAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFZBgsqhkiG9w0BCRABBKCCAUgEggFE
# MIIBQAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCKc6typuNsJuJr
# 2rStWbJDP7/JxewOMx/wHZxYOT1luQIGaq2l+vUEGBIyMDI2MDkyNTIxNDM1My40
# NlowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGlt
# aXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjMyMUEtMDVFMC1EOTQ3MSUw
# IwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR/jCCBygwggUQ
# oAMCAQICEzMAAAIaqaAdBqAPQ6oAAQAAAhowDQYJKoZIhvcNAQELBQAwfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMjUwODE0MTg0ODI4WhcNMjYxMTEz
# MTg0ODI4WjCB0zELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEt
# MCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMScw
# JQYDVQQLEx5uU2hpZWxkIFRTUyBFU046MzIxQS0wNUUwLUQ5NDcxJTAjBgNVBAMT
# HE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQCZgQDBJPPv2rZXdlbNDkS/tEqBp1C0wHLv5XddDxHQ0vxH
# 2a6nFyolD8o95kYlMRH71Cr+3sc5B8FsPLp7RN6m8EVX9FjfD4s48wqfRSiHb/wi
# 91JsnyoBZFWjPZL1WsnNmkHz9/mtBxEROBf+3w3roPYmURe/h9lAHtfNwkxevWm6
# G5ds631FgTI3VDdntiNGSF8GxFz5IP8L0XiLBmp9CCjzYYbjCC4iGMlTv5cx+u/i
# /EAU1WDeafU+gxYZlaKj57Xj48Zg9UsqVp37QiF0crkCA/JcqSoCERmliFhhUQi0
# c46+qvC6TFUAlcy9YDcZq1aRFmffdYMlW2CEJbpc8uLVwMqIYTlRxdlJXg6NAhQH
# y+nYtQxFe53kjj0UgFwT2dPTTPwD4R6Ss8z44CTTtoN/Blt2ZnnqPu5vl80Mt/zI
# hvxDFnwyvhHBbL9zMG5XmuRZBD6ayMnkAq1hnEl2dpl6FSBQ0CtT+7fpIfV5coxA
# ZFev/F4oUYjy++/kmXWSdnxSoRCv0/ENuKzs5enZZIwrmUsZ1hUfxWjCdgXexs6J
# GTHlDkZoTJN6E5CnZJ91uwlmWDRJeYemEaehbX+BD/k/oGBKrg8BYhloMmPoC8ss
# J1tRGBHlqk1BB53bNhSBRuMAID9OiYDwuXsCuu/ahkaJQ7lV2LjHG0DcFFNBNQID
# AQABo4IBSTCCAUUwHQYDVR0OBBYEFPCrIgndAyg9qwNwZ0ai9tpjwiU2MB8GA1Ud
# IwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRp
# bWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYI
# KwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMv
# TWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1Ud
# EwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeA
# MA0GCSqGSIb3DQEBCwUAA4ICAQDVrvZYWrsHpslPdU4nbWedOg8n07+rnVvDVuE9
# 9DLru7L5/zHxqSKnM0vaTlvqa3G49tkakGqkEqC4PBCbFWlfxwaZp96jfAavhrxi
# TpLLT20SH83DCWzKrsFGsk2fpsY4HyIbg5PL6mYxSHsV6M09GC+B6j84/K2bg02s
# wyD3xRWWtnEY05iyJ+lEkWDmMT9i7qWoVrWVOb1we49jFZragTALSwQCxMVvr2Iq
# k3Sw7X3EFkKvSHkKVT0+Cjp6SIlvtAmgPOsOg9AfBs0DzsK2jtMu6mGPSb2X8jvS
# AuMSrndIeO5RHPCmY3F2bXxCD6uWRowLpjYq6Q58nugJK729w0ZAz6KeX2Cw2CKt
# nrImT1WxcSyhO2hHt8w1To/Lq58lAYxOarpkKrZ4gY5dYwFvv1kXq2IpNripqaLd
# RLSZNjjUnXb1eYCCVXL66NJmQe7aUckNEezsWOchdlVQTmmXrJQiXbeMbnR9FMtB
# xK13Bj8u8lSAQcIjOO+UtOou3olVHltyzlo3gOHRg8b3kH2IMxmuriuWLlKcY1Z6
# /ksuwNjV9usrq5WkP6my9Iuw2mG3btBwdGxh0AwAtcz4c2zPYtnzGI5/C3qs6xVZ
# eiIdXzr9N4zLlNkVSXuoHn0g2gxImANGVp1Vd5P1/A66KsUiiqCMoaTe87ZsQutg
# w3RBXDCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcN
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
# OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNZMIIC
# QQIBATCCAQGhgdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGlt
# aXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjMyMUEtMDVFMC1EOTQ3MSUw
# IwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4D
# AhoDFQDxiu62YqlKu5sJoBixTim3UW3wNqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7mFeODAiGA8yMDI2MDky
# NTIwNTUyMFoYDzIwMjYwOTI2MjA1NTIwWjB3MD0GCisGAQQBhFkKBAExLzAtMAoC
# BQDuYV44AgEAMAoCAQACAhWZAgH/MAcCAQACAhMjMAoCBQDuYq+4AgEAMDYGCisG
# AQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMB
# hqAwDQYJKoZIhvcNAQELBQADggEBAGjH7RfoWRGdrdsya3wfCyPmb7cPqPogF3De
# /OCpM9UrH+j0AmvfYbDsB123IZkoCPQjOXtmnX61yVCL6X7+yrL6+KGXN/wJj5SP
# +ZnWTbbLK0zvn4cNVPMmewwxMZePJXG3y6ZjkjCd+K2vd3dNmix7li/o1vzEw1fw
# X1rN21cQbE7ILChGWE6ME8a/8855AEQ2SPcS909bjJtw6VMn5E34mk8L29UGfOUt
# bQ4PyMmpun21XEA7IRwunDl+qiDV5kI0MR7irE6ZD7are3m0yvQxXcEg+URghPQC
# /OkxcnD/y5kQ+kl8V8oH0Gk5Ldf2Z1t9YFAUjtVPSjjiYu5mG2sxggQNMIIECQIB
# ATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAhqpoB0GoA9D
# qgABAAACGjANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3
# DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCBUSV27tqEcnMWOF/eTVOFxPzbc219VZ1YQ
# dQND8vwR/zCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIJ16Icetu2kpzAHb
# R2hVTz1Ycg4fxLvDfu5odwOZ6Yr7MIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTACEzMAAAIaqaAdBqAPQ6oAAQAAAhowIgQgxKEqKadXnJQw3jtK
# TWLyEQVYJmqnv44bd6s1eRGvrZcwDQYJKoZIhvcNAQELBQAEggIAbZJgBoFgsxdp
# z2GYkZq4VVqAKV0KMrUr459G+AuzFnpoH3q7NG2AHlz/xUj5cNPuNlmeGx7Advx1
# C198AvEzxRdXxkYu86/VaCoOIowqUM+oKMiPbBN7I4Yp79crGmLKyqNs0FFdK5E5
# B23JbmlgokT5sdwobj4A2X4qabvyDKKkcSvwenTrfuRlwFJVWji2cokKJRZvCTB8
# Mf7g6YMJHTZXcdZ9Bl36WEZn8STcduiHJOKDhaxoP5bTzldAw4m/t1feycPWkVP+
# nq8WUQoXRppYp95Ic5h1Uki42Xb72TySDAZ5lBoGKSBi2pWT3mLQ7Wtfa8jSXscS
# FT9QpEILh2H3JzFMyUjvHqr3V4xXuhxSo6nsfUHhhZxNm520RwBENp7i2Sr/68CG
# 6etIDdLwF7G3tFcR1tybbNjiDJc34SE3NhPM9Wa27HcjAtBGEWQ3RPDCwfXElQTi
# xQ32xn0q/CKRNYG/yVs65DEAeWQbCUCwcCR6ds1TGOpkjxcbSD+GDnpmYbt69gVo
# PfVhdslyGQjkJXl/y9xpVw9E+26YXROr6+QRZHPY5XLL2w0bG/7tTVGmuZoUepaj
# 6MpiP3ewc4RxZ9s63ix5zzIT6b8LW4IUBXrSmFfywOtlIo41xksG02CAmMIkaE/s
# /6Fk1ovKdfAt8gL0atrbRhUSjZu820E=
# SIG # End signature block
