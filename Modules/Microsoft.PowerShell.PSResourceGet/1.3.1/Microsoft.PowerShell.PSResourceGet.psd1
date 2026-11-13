# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

@{
    RootModule             = './Microsoft.PowerShell.PSResourceGet.dll'
    NestedModules          = @('./Microsoft.PowerShell.PSResourceGet.psm1')
    ModuleVersion          = '1.3.1'
    CompatiblePSEditions   = @('Core', 'Desktop')
    GUID                   = 'e4e0bda1-0703-44a5-b70d-8fe704cd0643'
    Author                 = 'Microsoft Corporation'
    CompanyName            = 'Microsoft Corporation'
    Copyright              = '(c) Microsoft Corporation. All rights reserved.'
    Description            = 'PowerShell module with commands for discovering, installing, updating and publishing the PowerShell artifacts like Modules, Scripts, and DSC Resources.'
    PowerShellVersion      = '5.1'
    DotNetFrameworkVersion = '2.0'
    CLRVersion             = '4.0.0'
    FormatsToProcess       = 'PSGet.Format.ps1xml'
    CmdletsToExport        = @(
        'Compress-PSResource',
        'Find-PSResource',
        'Get-InstalledPSResource',
        'Get-PSResourceRepository',
        'Get-PSScriptFileInfo',
        'Install-PSResource',
        'Register-PSResourceRepository',
        'Reset-PSResourceRepository',
        'Save-PSResource',
        'Set-PSResourceRepository',
        'New-PSScriptFileInfo',
        'Test-PSScriptFileInfo',
        'Update-PSScriptFileInfo',
        'Publish-PSResource',
        'Uninstall-PSResource',
        'Unregister-PSResourceRepository',
        'Update-PSModuleManifest',
        'Update-PSResource'
    )
    FunctionsToExport      = @(
        'Import-PSGetRepository'
    )
    VariablesToExport = 'PSGetPath'
    AliasesToExport = @(
        'Get-PSResource',
        'fdres',
        'gres',
        'isres',
        'pbres',
        'svres',
        'udres',
        'usres')
    PrivateData = @{
        PSData = @{
            # Prerelease = ''
            Tags         = @('PackageManagement',
                'PSEdition_Desktop',
                'PSEdition_Core',
                'Linux',
                'Mac',
                'Windows')
            ProjectUri   = 'https://go.microsoft.com/fwlink/?LinkId=828955'
            LicenseUri   = 'https://go.microsoft.com/fwlink/?LinkId=829061'
            ReleaseNotes = @'
## 1.3.1

## 1.3.0

## 1.3.0-rc2

### New Features
- Add `-AllowInsecureConnection` to `Publish-PSResource` to explicitly allow publishing to HTTP NuGet repositories (#2072)

## 1.3.0-rc1

### Bug Fixes
- Initialize the repository store before resolving `Set-PSResourceRepository` dynamic parameters so setting PSGallery trust works on a fresh installation (#2067)
- Use concurrent queues for installation messages and avoid reinstalling dependencies that are already installed unless `-Reinstall` is specified (#2064)
- Fix V3 `packageContent` URL selection by comparing parsed package versions (#2019)
- Revert platform-aware installation filtering and remove the `-RuntimeIdentifier` and `-TargetFramework` parameters, restoring installation of all package runtime and library assets (#2070)

## 1.3.0-preview2

### New Features
- Add concurrency for parent package installation (#2016)
- Implement unimplemented concurrency methods for all server classes (#2012)
- Add platform-aware installation, filtering out runtimes by `-RuntimeIdentifier` and libraries by `-TargetFramework` (#1963)
- Add `PSContentPath` standard platform paths (#1912)
- Add `WhatIf` functionality to `PSResourceList` operations (#2004 Thanks @Gijsreyn!)

### Bug Fixes
- Add input validation for Repository DSCResource for GetOperation (#2002 Thanks @Gijsreyn!)
- Capture cmdlet warnings to prevent stdout contamination breaking DSC JSON parsing (#2000 Thanks @Gijsreyn!)
- Bug fix for PSResourcelistGet DSCResource operation filters out resources on installed version (#1998 Thanks @Gijsreyn!)
- Add custom exception messages for PSGallery (#2038)

## 1.3.0-preview1

### New Features
- Add `MAR` as default registered repository (#1955)
- Add concurrent (parallel) execution for `Install-PSResource` workflows (#1950)
- Add DSC V3 resource for PSResourceGet (#1852)

## Bug fix
- Bump `Azure.Identity` from `1.17.1` to `1.17.2`(#1994)
- Bump `Azure.Identity` from `1.14.2` to `1.17.1` and remove deprecated DefaultAzureCredentialOptions from constructor (#1987)
- Make flaky CI tests more lenient (#1976)
- Fixing the logic to determine if the current PowerShell session is Windows PowerShell or PowerShell Core (#1974 Thanks @Borgquite!)
- Include local-copy prerelease string when deciding update applicability in `Update-PSResource` (#1954 Thanks @sean-r-williams!)

See change log (CHANGELOG) at https://github.com/PowerShell/PSResourceGet
'@
        }
    }

    HelpInfoUri            = 'https://go.microsoft.com/fwlink/?linkid=2238183'
}

# SIG # Begin signature block
# MIInTwYJKoZIhvcNAQcCoIInQDCCJzwCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBZUmQxxB4MMcjE
# uldyzkaLXX0UrD3aZmJaf2SW3UgV/KCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
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
# Ql0v4q8J/AUmQN5W4n101cY2L4A7GTQG1h32HHAvfQESWP0xghncMIIZ2AIBATBu
# MFcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# KDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIc
# +s3Fm+gvfsQAAAAAAhwwDQYJYIZIAWUDBAIBBQCggZAwGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIEIGD4WYFfIRY7HHfnm1vf9YEBcC09
# ZuW8jVcaM+givKa5MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBv
# AGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAE
# ggEAI+bGBGq2dk+DdIgRxG163WJp7eW06qAsydM0SgqFEUjxXAdZkk/d9eoO8Vg5
# EkI67/uWmTCqIHMVZemhWmtu3CkcMGv2wrIUHxGX/3Atvo/wH7i//Y30yUMCjLhe
# ebOMUpVJ5dQyHlZ3MjHbnhb/dX3WQaZ4JWXEJP6nkiVEg69NUBvztqCQG72XEKHC
# HdXybLxVz7kW8TInVRoBncEBoBx7N30P8ZWiqOMHMYjGYAjLitToxphcUHSiKeM5
# c1J/dkbpa1Pv+0JrmcukJEcxXQ+zRg/OidWiZ9qdgF55bwZ4ThiE/Y/J/HPMnDjh
# unWMaY51dooS1fx+USpaAiP4rKGCF6wwgheoBgorBgEEAYI3AwMBMYIXmDCCF5QG
# CSqGSIb3DQEHAqCCF4UwgheBAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFZBgsqhkiG
# 9w0BCRABBKCCAUgEggFEMIIBQAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQC
# AQUABCD7roNsHOTzG1qXACkIdHKLApuWKLNLJh1K06Bw3vclDwIGauvd53DpGBIy
# MDI2MTEwNTIyMTEyNi4yMVowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5k
# IE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjU1
# MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2
# aWNloIIR+zCCBygwggUQoAMCAQICEzMAAAIwPwcEM8T7OdYAAQAAAjAwDQYJKoZI
# hvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEm
# MCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMjYxMDE1
# MTgzNzM1WhcNMjgwMTExMTgzNzM1WjCB0zELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0
# aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046NTUxQS0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDVwRBW2y1exyTQANEW30RXgtkb
# jibnGhGNMgd90qNcF6HbZMOlVjk2/FAF1C4iBx/9p5fCdCin+Z6ZssW8KwvESArd
# jPZFd7/sNE7UhHt3zmgU2qpv+4SpU+09HmRqiltt/CbyZ4DwHp1E0TNJ69zkI7mQ
# nxntgFaLAy2ypUgjOlZii2yaBuxhqwWBVJYe7g0wUc6PknYpbx3a87tjAAavYlK9
# ncz0WKZ9P/isPK+X4nMMxD6539C6fqYx7idfg54/oIVA6600HlbQEHFA7GBwVpaZ
# X9kPAPOTezYE+G7DvLwT0+TwS0q9QvbhIbwna5KGsnX6wNokkjBcJJq5BXJ1P8jN
# 1eTV3ZTWu11L+aMlHUSIoJ8BR9y6zBJl2WqFsk7YMbaFTpv34kPcLed0ok7NC4KU
# hc9cBxcwnWrcEse8dEDJPOT10jX6KyvJ+C1/4CL+18kYjGlNhEVFRm/dS7G1GRtj
# 9/V1MmO2SAFiqpkBZeHvOZ4AY4P6GimdYXefZgFBoH76/BbXk+AizfU+qXJiOEjL
# NmxYZH39QebQZZPW4XBw6iFDVqZJ/opOJZsozYYklY+VXz05LgvacaVOaZzqQE5B
# HmXufqgHm0f+r9IDiPqG2vHqh9Vo5eXd6eAqarWHfQOSP2SvrpyG6pX445aMrdQ1
# mzKYi9EIhkosw1UIeQIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFOKoYUNBGcCqpVEk
# CMzFm47bcbAFMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQAB2HcW7x5FJppHuoLh
# l38Nf48DKFBQBXr+CJUJQaWSnG7SonxxC+t36ANDTGVmywG4+rCIe/03xhXUMXyz
# iziOfagjVK/1PDqM6eqpC7HoZV930/S9IJTVHZ2fwWdCQOMNrhWJ8Y8LD4ruzjK6
# 0RYvkIPBYjjDlMlHvphVLfzoRmg76vgBt2jgQFwI0wbF6LsJSnnDMwQrVf6WvmH/
# I0x6KAufGwJPg2LJIJdn3FEIFGeJp4eUsvRXCN1TIrVNtlg6cHYZ+XLwgsv4Bht5
# hdUm6KU1XlOhBwnOtetTdrt474+eQy1x60AeySMOUkyBrplucHiS/CXhlUPH2BiT
# 6ICtiFMZL2N3jkx3wN1eE0D8Sna9Pwd7GuJ4PPZ+HokzeH9QVoE+9xUf6wJY8+ko
# rNf1MaU989qZg75yPKS4d8P96vJXwxka0n/mj6V90xl/iYfNEXirlT4lHo2I1q4a
# Lr6kChGAxWe5J0LVfzBkRcep6rHqHzYY2f+bsnQ7flSdeQF81dq3bagKv1FGbMu7
# 44qxxspr8l9z4R4sodeB+Piz4wNUQ/htBQU4M3bZIBVU/tgKabAOhfz67vB69oYQ
# V4NuH6fk7oUhGgY7FJxP3oLRK+G10wzLMP10Ocm24NljJdZT6LSoVBHdYfCx3U3z
# gRLHlBTw6y10tBq7RKmkYxjzwDCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
# AAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRl
# IEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVow
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX
# 9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1q
# UoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8d
# q6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byN
# pOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2k
# rnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4d
# Pf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgS
# Uei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8
# QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6Cm
# gyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzF
# ER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQID
# AQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQU
# KqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1
# GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0
# bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMA
# QTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbL
# j+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1p
# Y3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0w
# Ni0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIz
# LmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwU
# tj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN
# 3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU
# 5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5
# KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGy
# qVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB6
# 2FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltE
# AY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFp
# AUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcd
# FYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRb
# atGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQd
# VTNYs6FwZvKhggNWMIICPgIBATCCAQGhgdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5k
# IE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjU1
# MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2
# aWNloiMKAQEwBwYFKw4DAhoDFQCnszgvh8f2WUeirqwnKpMhjr7BPqCBgzCBgKR+
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA
# 7pcFCTAiGA8yMDI2MTEwNTEzMzcxM1oYDzIwMjYxMTA2MTMzNzEzWjB0MDoGCisG
# AQQBhFkKBAExLDAqMAoCBQDulwUJAgEAMAcCAQACAg18MAcCAQACAhTUMAoCBQDu
# mFaJAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMH
# oSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBACXGqZ9Ex1G5iNuX95le
# kZUA0Un+jfIZWP7bzK3Cs/UGGUR/hidBuVi5U7PAdeiMjynmdF9lP0UqvNPJxY++
# PYIMeoFK4ItW9bSyGbjMbuJ4XudsO9DrffFl6nLyyOpZq0VFXStZ4bK9kT432ywu
# g2uoJgakE2heHfrSuMweC2YWTvj/KneRj7/FzlXqHT1M9r/mekDVCzHgSkwW9lcX
# 5/trbppHWssVSrLuMJrzO0FA4FRaC+PfmUa1TjUzMD2dNP1AkMk3EdeWRdhIie1F
# MFTZ1+zCWVlDkE0c4O3knbV/B1Hi0mKpROqL4ybtN9yos1Vfu6sccpcw6CKVpqzt
# pD8xggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAIT
# MwAAAjA/BwQzxPs51gABAAACMDANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcN
# AQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCAaKprALQlu5AZKp+qR
# wZy5r0TygKwxEO1yePDszrfDrzCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0E
# IBSSWLrvRZbPgVa4c8ZpeOnOU3JHYBu9Ox7cqaICH9FoMIGYMIGApH4wfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIwPwcEM8T7OdYAAQAAAjAwIgQg
# 1h76dWH5K1F50eS/4Sj/e+nVF4EIvbceX9ZQKmhxK1IwDQYJKoZIhvcNAQELBQAE
# ggIAj3DnT/f+iy+stflsIYTYxCl8+KgV4dB2WExy+h3Uy5QWGMgzfXtv6O7OYcIB
# QuH86GTBlDEBCC4pX/E1DuHFvJXZcfjvcstrrzAefaOwhQQ99Ki43E8OS6Z59SGL
# RcnzFfrCLEOyLNNVnu2NUphRmI45X4Zy3rftAUDHnqbSFFHxRJ5cZjfC/8Nvcldy
# iVyHN14FMdjghiOp+DykmsdMow+I6kzTwX0oa6ltCF2kLjSi3+7fCTeTGhG699Nl
# 79U5GZjY7AU0UAZox6xBBPTzE090PaCIR11hi1Z3mfEH1PNHCO36sOsBTAIgxT+F
# tNp13rpyoIyt6PNYlnWEc89kIjhGT9Ds/LYyxu9/4ElHTFWA9MTc8NcKTfr1vAsI
# IzTKO7//lGFRbrU3LWRIOBj9mZFbKoUfqL6iE1CmBAZ8ZQ/fK4TKoDGG8GxUJj4z
# qcXiwYDYjOtgsaYD9c+/JpZGeTZMseYNBq83Vtx7dPXSGMmIOsvVYLr/yuaI5ohd
# st7BGhXo9blkwtghGYbZtHIBaqi/tUNBhjNGu9AW01tBHM6gyNzCd4rYndpxVdLT
# q3JDvjAdUsH1+ISVKInLXVo1uBSSq2IGk0WmZwZH8OWMU9f9Nqo3WJg7O1GXmsuV
# vf3MU/HK6W8fj09K/goOquEU2xOvB3nStM6o/qwk5e2Qkd0=
# SIG # End signature block
