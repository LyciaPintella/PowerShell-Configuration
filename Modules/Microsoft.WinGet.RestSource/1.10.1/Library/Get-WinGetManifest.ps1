# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

function Get-WinGetManifest {
    <#
    .SYNOPSIS
    Connects to the specified Windows Package Manager source, or local file system path to retrieve the package manifest, returning
    the manifest found.

    .DESCRIPTION
    Connects to the specified Windows Package Manager source, or local file system path to retrieve the package Manifest, returning
    the manifest found. Allows for retrieving results based on the package identifier when targeting the Windows Package Manager source.

    .PARAMETER Path
    Points to either a folder containing a specific Manifest of type .json or .yaml or to a specific .json or .yaml file.

    If you are processing a multi-file Manifest, point to the folder that contains all yamls. Note: all yamls within the folder must be part of
    the same Manifest.

    .PARAMETER PriorManifest
    A WinGetManifest object containing a single Windows Package Manager REST source Manifest that will be merged with locally processed .yaml files.
    This is used by the script infrastructure internally.

    .PARAMETER FunctionName
    Name of the Azure Function that contains the Windows Package Manager REST source.

    .PARAMETER PackageIdentifier
    Supports input from pipeline. The Windows Package Manager Package Identifier of a specific Package Manifest result.

    .PARAMETER SubscriptionName
    [Optional] The name of the subscription containing the Windows Package Manager REST source.

    .EXAMPLE
    Get-WinGetManifest -Path "C:\AppManifests\Microsoft.PowerToys"

    Returns a Manifest object based on the files found within the specified Path.

    .EXAMPLE
    Get-WinGetManifest -Path "C:\AppManifests\Microsoft.PowerToys\Microsoft.PowerToys.json"

    Returns a Manifest object (*.json) of the specified JSON file.

    .EXAMPLE
    Get-WinGetManifest -FunctionName "contosorestsource" -PackageIdentifier "Windows.PowerToys"

    Returns a Manifest object of the specified Package Identifier that is queried against the Windows Package Manager REST source.

    .EXAMPLE
    Get-WinGetManifest -FunctionName "contosorestsource" -PackageIdentifier "Windows.PowerToys" -SubscriptionName "Visual Studio Subscription"

    Returns a Manifest object of the specified Package Identifier that is queried against the Windows Package Manager REST source from the specified Subscription Name.

    #>
    [CmdletBinding(DefaultParameterSetName = 'Azure')]
    param(
        [Parameter(Position = 0, Mandatory = $true, ParameterSetName = 'File')]  [string]$Path,
        [Parameter(Mandatory = $false, ParameterSetName = 'File')]  [WinGetManifest]$PriorManifest = $null,
        [Parameter(Position = 0, Mandatory = $true, ParameterSetName = 'Azure')] [string]$FunctionName,
        [Parameter(Position = 1, Mandatory = $true, ParameterSetName = 'Azure', ValueFromPipeline = $true)][ValidateNotNullOrEmpty()] [string]$PackageIdentifier,
        [Parameter(Mandatory = $false, ParameterSetName = 'Azure')] [string]$SubscriptionName = ''
    )
    begin {
        [WinGetManifest[]] $Return = @()

        ###############################
        ## Determines the PowerShell Parameter Set that was used in the call of this Function.
        switch ($PsCmdlet.ParameterSetName) {
            'Azure' {
                ###############################
                ## Connects to Azure, if not already connected.
                Write-Verbose 'Validating connection to azure, will attempt to connect if not already connected.'
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

                ## Retrieves the Azure Function URL used to add new manifests to the REST source
                Write-Verbose -Message "Retrieving Azure Function Web Applications matching to: $FunctionName."
                $FunctionApp = Get-AzFunctionApp -ResourceGroupName $ResourceGroupName -Name $FunctionName

                $FunctionAppId = $FunctionApp.Id
                $DefaultHostName = $FunctionApp.DefaultHostName

                $TriggerName = 'ManifestGet'
                $ApiMethod = 'Get'

                ## Creates the API Post Header
                $ApiHeader = New-Object 'System.Collections.Generic.Dictionary[[String],[String]]'
                $ApiHeader.Add('Accept', 'application/json')
                $FunctionKey = (Invoke-AzResourceAction -ResourceId "$FunctionAppId/functions/$TriggerName" -Action listkeys -Force).default
                $ApiHeader.Add('x-functions-key', $FunctionKey)
            }
            'File' {
                ## Nothing to prepare
            }
        }        
    }
    process {
        switch ($PsCmdlet.ParameterSetName) {
            'Azure' {
                $AzFunctionURL = 'https://' + $DefaultHostName + '/api/packageManifests/' + $PackageIdentifier
                
                ## Publishes the Manifest to the Windows Package Manager REST source
                Write-Verbose -Message 'Invoking the REST API call.'

                $Response = Invoke-RestMethod $AzFunctionURL -Headers $ApiHeader -Method $ApiMethod -ErrorVariable ErrorInvoke

                if ($ErrorInvoke) {
                    $ErrorMessage = "Failed to get Manifest from $FunctionName. Verify the information you provided and try again."
                    $ErrReturnObject = @{
                        AzFunctionURL = $AzFunctionURL
                        ApiMethod     = $ApiMethod
                        Response      = $Response
                        InvokeError   = $ErrorInvoke
                    }
                
                    Write-Error -Message $ErrorMessage -TargetObject $ErrReturnObject
                } else {
                    Write-Verbose "Found ($($Response.Data.Count)) Manifests that matched."

                    foreach ($ResponseData in $Response.Data) {
                        Write-Verbose -Message "Parsing through the returned results: $ResponseData"
                        $Return += [WinGetManifest]::CreateFromObject($ResponseData)
                        Write-Information "Returned Manifest from JSON file: $($Return[-1].PackageIdentifier)"
                    }
                }
            }
            'File' {
                ## Convert to full path if applicable
                $Path = [System.IO.Path]::GetFullPath($Path, $pwd.Path)
                
                $ManifestFileExists = Test-Path -Path $Path

                if (!$ManifestFileExists) {
                    $ErrReturnObject = @{
                        FilePath           = $Path
                        ManifestFileExists = $ManifestFileExists
                    }

                    Write-Error -Message 'Target path did not point to an object.' -TargetObject $ErrReturnObject
                    return
                }

                $PathItem = Get-Item $Path
                $ManifestFile = ''
                $ApplicationManifest = ''
                $ManifestFileType = ''

                if ($PathItem.PSIsContainer) {
                    ## $Path variable is pointing at a directory
                    $PathChildItemsJSON = Get-ChildItem -Path $Path -Filter '*.json'
                    $PathChildItemsYAML = Get-ChildItem -Path $Path -Filter '*.yaml'

                    Write-Verbose -Message "Path pointed to a directory, found $($PathChildItemsJSON.count) JSON files, and $($PathChildItemsYAML.Count) YAML files."
                    
                    $ErrReturnObject = @{
                        JSONFiles = $PathChildItemsJSON
                        YAMLFiles = $PathChildItemsYAML
                        JSONCount = $PathChildItemsJSON.Count
                        YAMLCount = $PathChildItemsYAML.Count
                    }

                    ## Validating found objects
                    if ($PathChildItemsJSON.Count -eq 0 -and $PathChildItemsYAML.Count -eq 0) {
                        ## No JSON or YAML files were found in the directory.
                        $ErrorMessage = 'Directory does not contain any JSON or YAML files.'
                        Write-Error -Message $ErrorMessage -TargetObject $ErrReturnObject
                        return
                    } elseif ($PathChildItemsJSON.Count -gt 0 -and $PathChildItemsYAML.Count -gt 0) {
                        ## A combination of JSON and YAML Files were found.
                        $ErrorMessage = 'Directory contains a combination of JSON and YAML files.'
                        Write-Error -Message $ErrorMessage -TargetObject $ErrReturnObject
                        return
                    } elseif ($PathChildItemsJSON.Count -gt 1) {
                        ## More than one Package Manifest's JSON files was found.
                        $ErrorMessage = 'Directory contains more than one JSON file.'
                        Write-Error -Message $ErrorMessage -TargetObject $ErrReturnObject
                        return
                    } elseif ($PathChildItemsJSON.Count -eq 1) {
                        ## Single JSON has been found in the target folder.
                        Write-Verbose -Message 'Single JSON has been found in the specified directory.'
                        $ManifestFile = $PathChildItemsJSON
                        $ApplicationManifest = Get-Content -Path $PathChildItemsJSON[0].FullName -Raw
                        $ManifestFileType = '.json'
                    } elseif ($PathChildItemsYAML.Count -gt 0) {
                        Write-Verbose -Message 'YAML has been found in the specified directory.'
                        ## YAML has been found in the target folder.
                        $ManifestFile = $PathChildItemsYAML
                        $ManifestFileType = '.yaml'
                    }
                } else {
                    ## $Path variable is pointing at a file
                    Write-Verbose -Message "Retrieving the Package Manifest for: $Path"
            
                    ## Gets the Manifest object and contents of the Manifest - identifying the manifest file extension.
                    $ApplicationManifest = Get-Content -Path $Path -Raw
                    $ManifestFile = Get-Item -Path $Path
                    $ManifestFileType = $ManifestFile.Extension.ToLower()

                    Write-Verbose -Message "Retrieved content from the manifest ($($ManifestFile.Name))."
                }
                
                switch ($ManifestFileType) {
                    ## If the path resolves to a JSON file
                    '.json' {
                        ## Sets the return result to be the contents of the JSON file if the Manifest test passed.
                        $Return += [WinGetManifest]::CreateFromString($ApplicationManifest) 
                        Write-Information "Returned Manifest from JSON file: $($Return[-1].PackageIdentifier)"
                    }
                    ## If the path resolves to a YAML file
                    '.yaml' {
                        ## Directory - *.yaml files included within.
                        Write-Verbose -Message 'YAML Files have been found in the target directory. Building a JSON manifest with found files.'
                        if ($PriorManifest) {
                            Write-Verbose 'Prior manifest provided. New manifest will be merged with prior manifest.'
                            $Return += [WinGetManifest]::CreateFromString([Microsoft.WinGet.RestSource.PowershellSupport.YamlToRestConverter]::AddManifestToPackageManifest($Path, $PriorManifest.GetJson()))
                        } else {
                            Write-Verbose 'Prior manifest not provided.'
                            $Return += [WinGetManifest]::CreateFromString([Microsoft.WinGet.RestSource.PowershellSupport.YamlToRestConverter]::AddManifestToPackageManifest($Path, ''))
                        }

                        Write-Information "Returned Manifest from JSON file: $($Return[-1].PackageIdentifier)"
                    }
                    default {
                        $ErrorMessage = "Incorrect file type. Verify the file is of type '*.yaml' or '*.json' and try again."
                        $ErrReturnObject = @{
                            ApplicationManifest = $ApplicationManifest
                            ManifestFile        = $ManifestFile
                            $ManifestFileType   = $ManifestFileType
                        }

                        Write-Error -Message $ErrorMessage -TargetObject $ErrReturnObject
                    }
                }
            }
        }
    }
    end {
        ## Returns results
        Write-Verbose -Message "Returning ($($Return.Count)) manifests based on search."
        return $Return
    }
}

# SIG # Begin signature block
# MIInKAYJKoZIhvcNAQcCoIInGTCCJxUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDJpS5MwgcOPees
# cqLP3ILaZVsTIN6hJWHCh4SEKr+2oaCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# 1cY2L4A7GTQG1h32HHAvfQESWP0xghnEMIIZwAIBATBuMFcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIdTRnITtcPV0gAAAAAAh0w
# DQYJYIZIAWUDBAIBBQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJ
# KoZIhvcNAQkEMSIEILyAgp8lyOEdDUVDMLHp5Bl7Wf8Spjojf5JBBp5CQ5CtMEIG
# CisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAS2SZRmxbVBHeMJW3
# tXkpaZT5o63hlIwDZ2vFvABg4iltNfFmKmm+kxOmkyU5ARf6xkrjpvBdYwGEW2MB
# KD6Sz3fe5aJJVnngZ2lFweFoYUKTZjQwl9zqohiir8o5La7768x7L08Sl0cYp4SC
# H6w9dg/IT41kHBKyP3bGgW7KfftgZUZP4b+fE+RCe2ZGkNRzk2d1MY6mhRvczP/D
# aJjRfkVrTtQh5EYdX2ZSDJ4P+E/NJLEuLmh27XE0zQsELDslhqjuCi9jnpAlsaLs
# SfTpvO0IXD5e6LsdYM2AbMPCgetpTfU7Hnrt/9DN7hNfiXXRJgrctXbZarnm89DV
# uYSezaGCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCCF20w
# ghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9
# MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCAzKgqbkodmfL9J
# 2B0ptJkNYXBKIm8F1COg0knoADbVIQIGaql/HQlxGBMyMDI2MDkyNTIxNDM1NC40
# MDZaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScw
# JQYDVQQLEx5uU2hpZWxkIFRTUyBFU046QTAwMC0wNUUwLUQ5NDcxJTAjBgNVBAMT
# HE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHqMIIHIDCCBQigAwIBAgIT
# MwAAAiu7AFD/TTuaoQABAAACKzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNjAyMTkxOTQwMTFaFw0yNzA1MTcxOTQwMTFa
# MIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQL
# ExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxk
# IFRTUyBFU046QTAwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCX
# 3mi6OD3syUqQm4QqgkrKPbcsK/Qx3fYctL8+VM1uOY3booi5GxwauTgQf6JFHITT
# oxS7gjqKlK8OFLzL6UTl0jxEK5t6DuOcgJXdvutimoTlOS0C3kyITXBAXoj/gp6h
# RR9z6WRip1Ktkilb3dJXCjQqT9P2Cuujr+Vz8r+Z+jDl09ji/ic/4G34r3mVwjs/
# /Gnx9Pu31V8rXFicNiAzxpubawpbd8pqfzlWT2vnG3kF9l6MiREbvJ3XHLUwHQsh
# 0t/TrSFx/s/yCqpJWYJ6oClG70tvsFH0aRP8wB4cP/CFa2ILvk26i3OcJBl+pqKj
# HTSBy9mvwTPEDlnzco0Nt8R6pSPTXZgBsscHhoKfC0WQmOzY2keXbAmRTcZMyXz5
# v/AJbmoI0y07Bazvt5NkXddG9TErQWwtsFyIKrElDgWfHeCoTu1wu2ciD3dK72z3
# ca2gzoEDxT2j9BXIUKaiTzTdQPRsAMaO3dU0zaGwMMlwtSJyDh14YEgZoUu5vS8M
# ugMqdrNjphyL65yKhjpAWbhYkIHO/0uZju95tP8zZNqXIRh4tdfWHJPATn9r+cxk
# yuh2x0VLdfx1lmK9X3NjH0NtgAs5JB/wOlkyuudxmFTfWVyRrL37ispOZ8aPAFgv
# yR6cNTkGpkFo35JRjciNmZiU4qT9Uty+V5gudFk1jwIDAQABo4IBSTCCAUUwHQYD
# VR0OBBYEFD4WjuQTUJbtbd3jmvZku0FZ2eU2MB8GA1UdIwQYMBaAFJ+nFV0AXmJd
# g/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0El
# MjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGlt
# ZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0l
# AQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
# A4ICAQDO/CKsciEM8kr1fqH4TlfT66ENoTjxXw810pyEq0PdrgLwfgT3x+1gz7CQ
# HtUdevqMQ5qHyDLhm6pT911CYkGN+6g+MU7fMYTr6d3SxieJwBIoWkfR4g7SitGz
# MKU465KEYejfddoUgovC/xcRpaALO5p3/A248ByhJiMttBQNDtsT/HaCFwRFCURb
# y/f8c1kky8F8xkCXFz+/MtZ5d1lWFjwOI2geZHWq9XihDOgee5nS2koo5V6n8XG2
# 20UTevVf+pgmpIH71XKDVIYTGGZJs6yPlfJ2aXqw1ME4NR6okNsY3P1M31H6DMYR
# fJGNBNep595kXGh3YzA3cCiyg+jmJ58h/fTvjngIpuUFfODpDjFx0ic1YoLANxhC
# F3RhS9qYM7K40NEhKshYuaAkIG2XBKYig3r/0/b0sjvjBws55AYonMm3A8qcX/6k
# 9Vfc0mv9dtonHuWGfA2b+qE2qpCnhzGbdDHq7iOSZEw01nNupAMf1c41k9IoTQ2z
# 3iw6w4ZZoLOyg4TKMbp1krpT4trip/y30Cv5khyqCDNqaXQpBkOYON8LgtoQ3amV
# OX7ix5jdrnx/vUxTUSigXvrWdL7Uk8kpmS0zto2Toy7aT5oBzCTvfj9iJ/BN/E1v
# hFBkhJCvZ7PVvsMSnTTmkx2Fal2lVkztuAI44fD/uyLJdaMQSzCCB3EwggVZoAMC
# AQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29m
# dCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIy
# NVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAw
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9
# DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2
# Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N
# 7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXc
# ag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJ
# j361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjk
# lqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37Zy
# L9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M
# 269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLX
# pyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLU
# HMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode
# 2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEA
# ATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYE
# FJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEB
# MEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# RG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEE
# AYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB
# /zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEug
# SaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9N
# aWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsG
# AQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jv
# b0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt
# 4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsP
# MeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++
# Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9
# QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2
# wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aR
# AfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5z
# bcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nx
# t67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3
# Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+AN
# uOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/Z
# cGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNNMIICNQIBATCB+aGB0aSBzjCB
# yzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMc
# TWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBU
# U1MgRVNOOkEwMDAtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1T
# dGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQAJrD90ykHpo/0AGb7lmwvsCtqR
# OaCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3
# DQEBCwUAAgUA7mEq8jAiGA8yMDI2MDkyNTE3MTYzNFoYDzIwMjYwOTI2MTcxNjM0
# WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDuYSryAgEAMAcCAQACAg2qMAcCAQAC
# AhMyMAoCBQDuYnxyAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKg
# CjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAE2orXnk
# blHI/pdOW0aYcTkMpaLUj3nxtz7PZvs7vDg4rBr69gtHvjDO7ZwQ36whcg0giWud
# 1mv+jwGsbnKIBNRkn05ICDVjL5dlcVGuegLkZOp84DM+18E4bWzaYyL/kszl6m4w
# g3LD1GCOWpo8Up7D9EO1Z6EWmoxaB1ZP53bhvqZv6Kru6jNktfnHJ4JuVlUjcFft
# eNw3H4rxu+NZVMDPiQQitGSUWW4VlfdLHKi2yFzioarztyzh85noTQAZ513rfCI9
# uMVjqcsoVf/DJtUgewLUY6We9CDd8TFA1JQ88jIHEYUA/nrf0nfxgx6OvlVHa6QF
# Ifi+eESBROSF7OMxggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMAITMwAAAiu7AFD/TTuaoQABAAACKzANBglghkgBZQMEAgEFAKCCAUow
# GgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCCXliU1
# TJ1SI7X7JtuqhQiM4JWVNwFJRqshEafSFpyhuDCB+gYLKoZIhvcNAQkQAi8xgeow
# gecwgeQwgb0EIHIOI/Q/kFftYA+M2OY+1Bx3ajBD6/WDAtPT2vFkv25SMIGYMIGA
# pH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIruwBQ/007mqEA
# AQAAAiswIgQgcOrdDVIthrAhMGpaLnUYYMS/zu+flJjNtUM++Y8YdY0wDQYJKoZI
# hvcNAQELBQAEggIAZGKXw4bsfPPvSPFNXVzwLhRrWE6Hvlls0ZbF9/MRM5YRUlrA
# iGycAgT+dQ0Naze/Zqvu5P8FdaIQLlPj8P6wcft4M43t4CAtJEdtnjJ1ojHqUF2Z
# 9msogniZF7McquJnH7Q6tbOWkCXBeT/bB3g+E4N3Gl2jArF3n57K4Wy8FTEVJWmz
# p/76BfP41Y7ExCdSdQKDEEm7brfxxON4LH0awjIeyupn7NGPLAWF0nAu+8HSTKTX
# HLDQMS3ZJhjHXDYA3ieNWdOxnrmKxjGcKvACDIouetmA2xJUd8nKIn2FXWlL8jo3
# ltYuM64pcrTVGyCQPP8XNKdXzOuiSmqvW2UWfVYQ+Vi1YO2sKx1+lcQXxTPsY81E
# xtPri2YdvinUkeyPBhLOgoSCgndNPMg/ROSbTitHzhQXEJjnPCqtWkX0s0/gwkwK
# YUR7LR2BfoRnEoHKFz076s0i0KLheAKGuOFTReFZBFRoz13WjIOmJphlzFaFZ0w0
# o5CqxUDxN38SYVFSZhDgDEiFUX+KoDv7nlDTuswbxrcVZ4VLLE9v/Tvte2Fu6yj5
# 0x+FHE71WZIxAIz9hI9j4nog8zT1yY58pZ9nn9DUYehbbpVjGvf/HcTrcDKCoFkJ
# U8LNHrQjrGvh7nHhEXRq+E1K/7ad0PpfOkjPWEmWructquOPBOIBwwvG++M=
# SIG # End signature block
