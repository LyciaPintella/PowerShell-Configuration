# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

Function Get-WinGetManifest
{
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
    PARAM(
        [Parameter(Position=0, Mandatory=$true, ParameterSetName="File")]  [string]$Path,
        [Parameter(Mandatory=$false,ParameterSetName="File")]  [WinGetManifest]$PriorManifest = $null,
        [Parameter(Position=0, Mandatory=$true, ParameterSetName="Azure")] [string]$FunctionName,
        [Parameter(Position=1, Mandatory=$true, ParameterSetName="Azure", ValueFromPipeline=$true)][ValidateNotNullOrEmpty()] [string]$PackageIdentifier,
        [Parameter(Mandatory=$false,ParameterSetName="Azure")] [string]$SubscriptionName = ""
    )
    BEGIN
    {
        [WinGetManifest[]] $Return = @()

        ###############################
        ## Determines the PowerShell Parameter Set that was used in the call of this Function.
        switch ($PsCmdlet.ParameterSetName) {
            "Azure" {
                ###############################
                ## Connects to Azure, if not already connected.
                Write-Verbose "Validating connection to azure, will attempt to connect if not already connected."
                $Result = Connect-ToAzure -SubscriptionName $SubscriptionName
                if(!($Result)) {
                    Write-Error "Failed to connect to Azure. Please run Connect-AzAccount to connect to Azure, or re-run the cmdlet and enter your credentials." -ErrorAction Stop
                }

                ###############################
                ## Gets Resource Group name of the Azure Function
                Write-Verbose -Message "Determines the Azure Function Resource Group Name"
                $ResourceGroupName = $(Get-AzFunctionApp).Where({$_.Name -eq $FunctionName}).ResourceGroupName
                if(!$ResourceGroupName) {
                    Write-Error "Failed to confirm Azure Function exists in Azure. Please verify and try again. Function Name: $FunctionName" -ErrorAction Stop
                }

                ## Retrieves the Azure Function URL used to add new manifests to the REST source
                Write-Verbose -Message "Retrieving Azure Function Web Applications matching to: $FunctionName."
                $FunctionApp = Get-AzFunctionApp -ResourceGroupName $ResourceGroupName -Name $FunctionName

                $FunctionAppId   = $FunctionApp.Id
                $DefaultHostName = $FunctionApp.DefaultHostName

                $TriggerName    = "ManifestGet"
                $ApiMethod      = "Get"

                ## Creates the API Post Header
                $ApiHeader = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                $ApiHeader.Add("Accept", 'application/json')
                $FunctionKey = (Invoke-AzResourceAction -ResourceId "$FunctionAppId/functions/$TriggerName" -Action listkeys -Force).default
                $ApiHeader.Add("x-functions-key", $FunctionKey)
            }
            "File" {
                ## Nothing to prepare
            }
        }        
    }
    PROCESS
    {
        switch ($PsCmdlet.ParameterSetName) {
            "Azure" {
                $AzFunctionURL = "https://" + $DefaultHostName + "/api/packageManifests/" + $PackageIdentifier
                
                ## Publishes the Manifest to the Windows Package Manager REST source
                Write-Verbose -Message "Invoking the REST API call."

                $Response = Invoke-RestMethod $AzFunctionURL -Headers $ApiHeader -Method $ApiMethod -ErrorVariable ErrorInvoke

                if($ErrorInvoke) {
                    $ErrorMessage = "Failed to get Manifest from $FunctionName. Verify the information you provided and try again."
                    $ErrReturnObject = @{
                        AzFunctionURL       = $AzFunctionURL
                        ApiMethod           = $ApiMethod
                        Response            = $Response
                        InvokeError         = $ErrorInvoke
                    }
                
                    Write-Error -Message $ErrorMessage -TargetObject $ErrReturnObject
                }
                else {
                    Write-Verbose "Found ($($Response.Data.Count)) Manifests that matched."

                    foreach ($ResponseData in $Response.Data){
                        Write-Verbose -Message "Parsing through the returned results: $ResponseData"
                        $Return += [WinGetManifest]::CreateFromObject($ResponseData)
                        Write-Information "Returned Manifest from JSON file: $($Return[-1].PackageIdentifier)"
                    }
                }
            }
            "File" {
                ## Convert to full path if applicable
                $Path = [System.IO.Path]::GetFullPath($Path, $pwd.Path)
                
                $ManifestFileExists  = Test-Path -Path $Path

                if(!$ManifestFileExists) {
                    $ErrReturnObject = @{
                        FilePath           = $Path
                        ManifestFileExists = $ManifestFileExists
                    }

                    Write-Error -Message "Target path did not point to an object." -TargetObject $ErrReturnObject
                    return
                }

                $PathItem = Get-Item $Path
                $ManifestFile = ""
                $ApplicationManifest = ""
                $ManifestFileType = ""

                if($PathItem.PSIsContainer) {
                    ## $Path variable is pointing at a directory
                    $PathChildItemsJSON = Get-ChildItem -Path $Path -Filter "*.json"
                    $PathChildItemsYAML = Get-ChildItem -Path $Path -Filter "*.yaml"

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
                        $ErrorMessage    = "Directory does not contain any JSON or YAML files."
                        Write-Error -Message $ErrorMessage -TargetObject $ErrReturnObject
                        return
                    }
                    elseif ($PathChildItemsJSON.Count -gt 0 -and $PathChildItemsYAML.Count -gt 0) {
                        ## A combination of JSON and YAML Files were found.
                        $ErrorMessage    = "Directory contains a combination of JSON and YAML files."
                        Write-Error -Message $ErrorMessage -TargetObject $ErrReturnObject
                        return
                    }
                    elseif ($PathChildItemsJSON.Count -gt 1) {
                        ## More than one Package Manifest's JSON files was found.
                        $ErrorMessage    = "Directory contains more than one JSON file."
                        Write-Error -Message $ErrorMessage -TargetObject $ErrReturnObject
                        return
                    }
                    elseif ($PathChildItemsJSON.Count -eq 1) {
                        ## Single JSON has been found in the target folder.
                        Write-Verbose -Message "Single JSON has been found in the specified directory."
                        $ManifestFile        = $PathChildItemsJSON
                        $ApplicationManifest = Get-Content -Path $PathChildItemsJSON[0].FullName -Raw
                        $ManifestFileType    = ".json"
                    }
                    elseif ($PathChildItemsYAML.Count -gt 0) {
                        Write-Verbose -Message "YAML has been found in the specified directory."
                        ## YAML has been found in the target folder.
                        $ManifestFile     = $PathChildItemsYAML
                        $ManifestFileType = ".yaml"
                    }
                }
                else {
                    ## $Path variable is pointing at a file
                    Write-Verbose -Message "Retrieving the Package Manifest for: $Path"
            
                    ## Gets the Manifest object and contents of the Manifest - identifying the manifest file extension.
                    $ApplicationManifest = Get-Content -Path $Path -Raw
                    $ManifestFile        = Get-Item -Path $Path
                    $ManifestFileType    = $ManifestFile.Extension.ToLower()

                    Write-Verbose -Message "Retrieved content from the manifest ($($ManifestFile.Name))."
                }
                
                switch ($ManifestFileType) {
                    ## If the path resolves to a JSON file
                    ".json" {
                        ## Sets the return result to be the contents of the JSON file if the Manifest test passed.
                        $Return += [WinGetManifest]::CreateFromString($ApplicationManifest) 
                        Write-Information "Returned Manifest from JSON file: $($Return[-1].PackageIdentifier)"
                    }
                    ## If the path resolves to a YAML file
                    ".yaml" {
                        ## Directory - *.yaml files included within.
                        Write-Verbose -Message "YAML Files have been found in the target directory. Building a JSON manifest with found files."
                        if($PriorManifest){
                            Write-Verbose "Prior manifest provided. New manifest will be merged with prior manifest."
                            $Return += [WinGetManifest]::CreateFromString([Microsoft.WinGet.RestSource.PowershellSupport.YamlToRestConverter]::AddManifestToPackageManifest($Path, $PriorManifest.GetJson()))
                        }
                        else{
                            Write-Verbose "Prior manifest not provided."
                            $Return += [WinGetManifest]::CreateFromString([Microsoft.WinGet.RestSource.PowershellSupport.YamlToRestConverter]::AddManifestToPackageManifest($Path, ""))
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
    END
    {
        ## Returns results
        Write-Verbose -Message "Returning ($($Return.Count)) manifests based on search."
        return $Return
    }
}

# SIG # Begin signature block
# MIIoRQYJKoZIhvcNAQcCoIIoNjCCKDICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCsW+zwMY8qdr7G
# eJoOjQeym3El5ER2ixWvHAZCO3Uf/KCCDXYwggX0MIID3KADAgECAhMzAAAEhV6Z
# 7A5ZL83XAAAAAASFMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjUwNjE5MTgyMTM3WhcNMjYwNjE3MTgyMTM3WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDASkh1cpvuUqfbqxele7LCSHEamVNBfFE4uY1FkGsAdUF/vnjpE1dnAD9vMOqy
# 5ZO49ILhP4jiP/P2Pn9ao+5TDtKmcQ+pZdzbG7t43yRXJC3nXvTGQroodPi9USQi
# 9rI+0gwuXRKBII7L+k3kMkKLmFrsWUjzgXVCLYa6ZH7BCALAcJWZTwWPoiT4HpqQ
# hJcYLB7pfetAVCeBEVZD8itKQ6QA5/LQR+9X6dlSj4Vxta4JnpxvgSrkjXCz+tlJ
# 67ABZ551lw23RWU1uyfgCfEFhBfiyPR2WSjskPl9ap6qrf8fNQ1sGYun2p4JdXxe
# UAKf1hVa/3TQXjvPTiRXCnJPAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUuCZyGiCuLYE0aU7j5TFqY05kko0w
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzUwNTM1OTAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBACjmqAp2Ci4sTHZci+qk
# tEAKsFk5HNVGKyWR2rFGXsd7cggZ04H5U4SV0fAL6fOE9dLvt4I7HBHLhpGdE5Uj
# Ly4NxLTG2bDAkeAVmxmd2uKWVGKym1aarDxXfv3GCN4mRX+Pn4c+py3S/6Kkt5eS
# DAIIsrzKw3Kh2SW1hCwXX/k1v4b+NH1Fjl+i/xPJspXCFuZB4aC5FLT5fgbRKqns
# WeAdn8DsrYQhT3QXLt6Nv3/dMzv7G/Cdpbdcoul8FYl+t3dmXM+SIClC3l2ae0wO
# lNrQ42yQEycuPU5OoqLT85jsZ7+4CaScfFINlO7l7Y7r/xauqHbSPQ1r3oIC+e71
# 5s2G3ClZa3y99aYx2lnXYe1srcrIx8NAXTViiypXVn9ZGmEkfNcfDiqGQwkml5z9
# nm3pWiBZ69adaBBbAFEjyJG4y0a76bel/4sDCVvaZzLM3TFbxVO9BQrjZRtbJZbk
# C3XArpLqZSfx53SuYdddxPX8pvcqFuEu8wcUeD05t9xNbJ4TtdAECJlEi0vvBxlm
# M5tzFXy2qZeqPMXHSQYqPgZ9jvScZ6NwznFD0+33kbzyhOSz/WuGbAu4cHZG8gKn
# lQVT4uA2Diex9DMs2WHiokNknYlLoUeWXW1QrJLpqO82TLyKTbBM/oZHAdIc0kzo
# STro9b3+vjn2809D0+SOOCVZMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCGiUwghohAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAASFXpnsDlkvzdcAAAAABIUwDQYJYIZIAWUDBAIB
# BQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIGSCukinexMUV7qdRHWSTHSs
# mP+NsCB9y5d4ZoXv7KpNMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
# BQAEggEApuCziVnkcQ1zCJnYPbUhtVaf6CGdZTPEh6UiYh1OBM7tNTgIrTBrVq2x
# tu6gcZD5MJY32eHHuJN1wa4dfwAVd2cntXGQhbyXdetpQHDC4uz3CVEE2O9S5GIQ
# jLj1ZQkNTymoLCdeOPzwl0TTlSWdO+Ia6QWUpw9m6Om29kPHDhe12V2vmFOmuXDf
# qOwsBsbJVSj1rvYGIHDrHuom0leRBACDjnGt3fUaFJwE+CRIf/KUx0n3xmVVF1l2
# 0p80wZf+o1MZu+0EtOhY2k6KYb8xjX4sUHPMlNNbQNHSUVWIPjyqaQORc0SLHhDI
# aNoYWS9+hy3vTBdg/zRzSw6wAdyJBKGCF68wgherBgorBgEEAYI3AwMBMYIXmzCC
# F5cGCSqGSIb3DQEHAqCCF4gwgheEAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFZBgsq
# hkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFl
# AwQCAQUABCDCKEBGQVtK5ct8XKZBhtTG0ClRs5kmwJZAkL908XxWogIGaHptolCu
# GBIyMDI1MDcyNTAwMTI1Ni4xNVowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVs
# YW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNO
# OjU3MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNloIIR/jCCBygwggUQoAMCAQICEzMAAAH7y8tsN2flMJUAAQAAAfswDQYJ
# KoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMjQw
# NzI1MTgzMTEzWhcNMjUxMDIyMTgzMTEzWjCB0zELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3Bl
# cmF0aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046NTcxQS0w
# NUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Uw
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCowlZB5YCrgvC9KNiyM/RS
# +G+bSPRoA4mIwuDSwt/EqhNcB0oPqgy6rmsXmgSI7FX72jHQf3lDx+GhmrfH2XGC
# 5nJM4riXbG1yC0kK2NdGWUzZtOmM6DflFSsHLRwCWgFT0YkGzssE2txsfqsGI6+o
# NA2Jw9FnCrXrHKMyJ1TUnUAm5q33Iufu1qJ+gPnxuVgRwG+SPl0fWVr3NTzjpAN4
# 6hE7o1yocuwPHz/NUpnE/fSZbpjtEyyq0HxwYKAbBVW6s6do0tezfWpNFPJUdfym
# k52hKKEJd6p5uAkJHMbzMb97+TShoGMUUaX7y4UQvALKHjAr1nn5rNPN9rYYPinq
# KG2yRezeWdbTlQp8MmEAAO3q+I5zRGT9zzM6KrOHSUql/95ZRjaj+G9wM9k2Atoe
# /J8OpvwBZoq87fqJFlJeqFLDxLEmjRMKmxsKOa3HQukeeptvVQXtyrT2QJx9ZMM9
# w3XaltgupyTRsgh88ptzseeuQ1CSz+ZJtVlOcPJPc7zMX2rgMJ9Z6xKvVqTJwN24
# bEJ0oG+C0mHVjEOrWyRPB5jHmIBZecHsozKWzdZBltO5tMIsu3xefy36yVwqbkOS
# +hu5uYdKuK5MDfBPIjLgXFqZMqbRUO72ZZ2zwy2NRIlXA1VWUFdpDdkxxWOKPJWh
# Q1W4Fj0xzBhwhArrbBDbQQIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFEdVIZhQ1DdH
# A6XvXMgC5SMgqDUqMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8G
# A1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBs
# BggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUy
# MDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
# AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQDDOggo5jZ2dSN9
# a4yIajP+i+hzV7zpXBZpk0V2BGY6hC5F7ict21k421Mc2TdKPeeTIGzPPFJtkRDQ
# N27Ioccjk/xXzuMW20aeVHTA8/bYUB5tu8Bu62QwxVAwXOFUFaJYPRUCe73HR+OJ
# 8soMBVcvCi6fmsIWrBtqxcVzsf/QM+IL4MGfe1TF5+9zFQLKzj4MLezwJintZZel
# nxZv+90GEOWIeYHulZyawHze5zj8/YaYAjccyQ4S7t8JpJihCGi5Y6vTuX8ozhOd
# 3KUiKubx/ZbBdBwUTOZS8hIzqW51TAaVU19NMlSrZtMMR3e2UMq1X0BRjeuucXAd
# PAmvIu1PggWG+AF80PeYvV55JqQp/vFMgjgnK3XlJeEd3mgj9caNKDKSAmtYDnus
# acALuu7f9lsU0Iwr8mPpfxfgvqYE5hrY0YrAfgDftgYOt5wn+pddZRi98tiocZ/x
# OFiXXZiDWvBIqlYuiUD8HV6oHDhNFy9VjQi802Lmyb7/8cn0DDo0m5H+4NHtfu8N
# eJylcyVE2AUzIANvwAUi9A90epxGlGitj5hQaW/N4nH/aA1jJ7MCiRusWEAKwnYF
# /J4vIISjoC7AQefnXU8oTx0rgm+WYtKgePtUVHc0cOTfNGTHQTGSYXxo52m+gqG7
# AELGhn8mFvNLOu9nvgZWMoojK3kUDTCCB3EwggVZoAMCAQICEzMAAAAVxedrngKb
# SZkAAAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmlj
# YXRlIEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIy
# NVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXI
# yjVX9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjo
# YH1qUoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1y
# aa8dq6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v
# 3byNpOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pG
# ve2krnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viS
# kR4dPf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYr
# bqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlM
# jgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSL
# W6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AF
# emzFER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIu
# rQIDAQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIE
# FgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWn
# G1M1GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEW
# M2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5
# Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBi
# AEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV
# 9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3Js
# Lm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAx
# MC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2
# LTIzLmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv
# 6lwUtj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZn
# OlNN3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1
# bSNU5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4
# rPf5KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU
# 6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDF
# NLB62FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/
# HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdU
# CbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKi
# excdFYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTm
# dHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZq
# ELQdVTNYs6FwZvKhggNZMIICQQIBATCCAQGhgdmkgdYwgdMxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVs
# YW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNO
# OjU3MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQAEcefs0Ia6xnPZF9VvK7BjA/KQFaCBgzCB
# gKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUA
# AgUA7CzUuTAiGA8yMDI1MDcyNDE1NTAxN1oYDzIwMjUwNzI1MTU1MDE3WjB3MD0G
# CisGAQQBhFkKBAExLzAtMAoCBQDsLNS5AgEAMAoCAQACAhnCAgH/MAcCAQACAhO6
# MAoCBQDsLiY5AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAI
# AgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAEqbtauThBCJ
# oBmr9SazaphEUrVMVQSjBqIlgzgahsQQCNO7e8KRHEt6OlKpmPnyImJUKnFn374b
# Q6KodBWNneEpzsJxp2cWNOnhS208m8tb9z/0x06KoRNJj2ncquMc21rkFKHvZok0
# KW05t99NALu20b9Qe7cZD1+Z7WtDa2F6bOrnUSFeGmM51nEMjIxv1PDx7usBKdhP
# nNyQJnjJxo4zcSfvtvTrgFDLegW2SYe+vaFYLHNebWUHS4Hciven5KDzDU6K1R7l
# /L/dSTad1l8S+L1hX2hs2uxNt0neFpVO7SGRHEl/POziK01HLgFBbSzL62ggYuC/
# /hpxjJ7jkagxggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMAITMwAAAfvLy2w3Z+UwlQABAAAB+zANBglghkgBZQMEAgEFAKCCAUowGgYJ
# KoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCCM6f5lJ3p8
# pXXbxfpU9fImo5+vo9LaUBOmgLyD49N6dDCB+gYLKoZIhvcNAQkQAi8xgeowgecw
# geQwgb0EIDnbAqv8oIWVU1iJawIuwHiqGMRgQ/fEepioO7VJJOUYMIGYMIGApH4w
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAH7y8tsN2flMJUAAQAA
# AfswIgQg25Cj5zYf60opab/8IIGixWf6Xt69TALqaF4Z0/DNsLcwDQYJKoZIhvcN
# AQELBQAEggIAZakagaNb7FDOB2F2bu31+gatvhxPQkdVxcccGea7uzfeJU2PljnU
# 61/prdTYraoSjY4WjUk5EESk41b+K3WZPdJyclltNwOjV9gVwI/nei2aBrovicBQ
# sp7IInx8baRhhew54z4dffO5baTQCSQEdhBmb6eTiU75yUAgAHy6fTgg+BR0mV2Y
# ixU0GZZKILma8chU8SOTaI2N29amwRELNdT60/P2MRMXXCK/HyID8VojVunIbvN9
# Xh5ai0MaVC671WZ7YXUL7RA4NFhkaKOFDMHnvoGb1KdozoVG2pNAIAzJTWDUYr0r
# EAVR4ewkLkeOcefgRt874wJNqqjjHYJjKvuNQBkwy48HFhy9NNS44TIecv5liRpw
# +edegOH/+WF8lPXgg705daO7LvKuIYQDeqhy2eK91BpTQNkKwWRX+PnOGYCg52hW
# pfJW/UpIQGkUkOMec7k6G/wz2p4RPRf7wrNqL5glNp/rKOohyun6Xvln3WzZ2lsf
# k5dhNNQtPUC64nq4KjFgH9b4aiPeNe0chmSU1bPIEzFUpHZkbNeTEPURkkMekuuM
# PWq1dv7EXlWnf6BmyJRCilbTaYPJZ+06V9siimMfWDe6TzE2c8AC7xZIY1jG6npf
# iMXsslxlyxYzKvfWaMpsiigzrRD+G7hRMT22OYxVsN7KUaZHjR/xq/A=
# SIG # End signature block
