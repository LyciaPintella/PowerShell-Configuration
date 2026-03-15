# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

Function Find-WinGetManifest
{
    <#
    .SYNOPSIS
    Connects to the specified Windows Package Manager source REST API to retrieve available Manifests, returning only the package identifier, name, publisher and versions for each Manifest result.

    .DESCRIPTION
    Connects to the specified Windows Package Manager source REST API to retrieve available Manifests, returning only the package identifier, name, publisher and versions for each Manifest result.
    This function does not return the full WinGetManifest since the results may be very large. Use Get-WinGetManifest for retrieving individual full WinGetManifest.

    .PARAMETER FunctionName
    Name of the Azure Function that contains the Windows Package Manager REST source.

    .PARAMETER Query
    [Optional] The query to be performed against the Windows Package Manager REST source. Empty query will return all manifest infos.

    .PARAMETER PackageIdentifier
    [Optional] Filter the search results with PackageIdentifier.

    .PARAMETER PackageName
    [Optional] Filter the search results with PackageName.

    .PARAMETER SubscriptionName
    [Optional] The name of the subscription containing the Windows Package Manager REST source.

    .PARAMETER Exact
    [Optional] If specified, the Windows Package Manager REST source search will be performed with exact match.

    .EXAMPLE
    Find-WinGetManifest -FunctionName "contosorestsource" -Query "PowerToys"

    Connects to Azure, then runs the Azure Function "contosorestsource" REST APIs to search for manifests with PowerToys.

    .EXAMPLE
    Find-WinGetManifest -FunctionName "contosorestsource" -Query "PowerToys" -PackageIdentifier "Windows.PowerToys"

    Connects to Azure, then runs the Azure Function "contosorestsource" REST APIs to search for manifests with PowerToys and filter the result with package identifier Windows.PowerToys.

    .EXAMPLE
    Find-WinGetManifest -FunctionName "contosorestsource" -Query "PowerToys" -PackageName "Windows PowerToys" -Exact

    Connects to Azure, then runs the Azure Function "contosorestsource" REST APIs to search for manifests with PowerToys and filter the result with package name Windows PowerToys. Use exact match.

    #>
    PARAM(
        [Parameter(Position=0, Mandatory=$true)] [string]$FunctionName,
        [Parameter(Mandatory=$false)] [string]$Query = "",
        [Parameter(Mandatory=$false)] [string]$PackageIdentifier = "",
        [Parameter(Mandatory=$false)] [string]$PackageName = "",
        [Parameter(Mandatory=$false)] [string]$SubscriptionName = "",
        [Parameter()] [switch]$Exact
    )
    BEGIN
    {
        [PSCustomObject[]] $Return = @()

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

        $TriggerName    = "ManifestSearchPost"
        $ApiContentType = "application/json"
        $ApiMethod      = "Post"

        ## Creates the API Post Header
        $ApiHeader = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $ApiHeader.Add("Accept", 'application/json')
        $FunctionKey = (Invoke-AzResourceAction -ResourceId "$FunctionAppId/functions/$TriggerName" -Action listkeys -Force).default
        $ApiHeader.Add("x-functions-key", $FunctionKey)

        $AzFunctionURL = "https://" + $DefaultHostName + "/api/manifestSearch"
    }
    PROCESS
    {
        Write-Verbose -Message "Invoking the REST API call."

        ## Internal scan does not recognize ternary oprator, use if else here
        if ($Exact) {
            $QueryMatchType = "Exact"
        }
        else {
            $QueryMatchType = "Substring"
        }
        $RequestBody = @{
            Query = @{
                KeyWord = $Query
                MatchType = $QueryMatchType
            }
            Filters = @()
        }

        ## Internal scan does not recognize ternary oprator, use if else here
        if ($Exact) {
            $FilterMatchType = "Exact"
        }
        else {
            $FilterMatchType = "CaseInsensitive"
        }
        if (![string]::IsNullOrWhiteSpace($PackageIdentifier)) {
            $RequestBody.Filters += @{
                PackageMatchField = "PackageIdentifier"
                RequestMatch = @{
                    KeyWord = $PackageIdentifier
                    MatchType = $FilterMatchType
                }
            }
        }
        if (![string]::IsNullOrWhiteSpace($PackageName)) {
            $RequestBody.Filters += @{
                PackageMatchField = "PackageName"
                RequestMatch = @{
                    KeyWord = $PackageName
                    MatchType = $FilterMatchType
                }
            }
        }

        $RequestBodyJson = ConvertTo-Json $RequestBody -Depth 8 -Compress
        Write-Verbose "Search Request: $RequestBodyJson"

        $ContinuationToken = $null
        do {
            if ($ContinuationToken) {
                $ApiHeader["ContinuationToken"] = $ContinuationToken
            }

            $Response = Invoke-RestMethod $AzFunctionURL -Headers $ApiHeader -Method $ApiMethod -Body $RequestBodyJson -ContentType $ApiContentType -ErrorVariable ErrorInvoke
     
            if ($ErrorInvoke) {
                $ErrorMessage = "Failed to get search result from $FunctionName. Verify the information you provided and try again."
                $ErrReturnObject = @{
                    AzFunctionURL       = $AzFunctionURL
                    ApiMethod           = $ApiMethod
                    ApiContentType      = $ApiContentType
                    Response            = $Response
                    InvokeError         = $ErrorInvoke
                }
            
                Write-Error -Message $ErrorMessage -TargetObject $ErrReturnObject
                return
            }
            else {
                Write-Verbose "Found ($($Response.Data.Count)) Manifests that matched."
            
                foreach ($ResponseData in $Response.Data) {
                    Write-Verbose -Message "Parsing through the returned results: $ResponseData"
                    $ManifestInfo = [PSCustomObject]@{
                        PackageIdentifier = $ResponseData.PackageIdentifier
                        PackageName = $ResponseData.PackageName
                        Publisher = $ResponseData.Publisher
                        Versions = [string[]]@()
                    }
                    foreach ($Version in $ResponseData.Versions) {
                        $ManifestInfo.Versions += $Version.PackageVersion
                    }
                    $Return += $ManifestInfo
                }
            }

            $ContinuationToken = $Response.ContinuationToken
        } while (![string]::IsNullOrWhiteSpace($ContinuationToken))
    }
    END
    {
        ## Returns results
        Write-Verbose -Message "Returning ($($Return.Count)) manifests based on search."
        return $Return
    }
}

# SIG # Begin signature block
# MIIoOQYJKoZIhvcNAQcCoIIoKjCCKCYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCfNEcChbiMryNq
# jzt5vHzkE6K1YSGJ7O4DAi8Di4nM4aCCDYUwggYDMIID66ADAgECAhMzAAAEhJji
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
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGgowghoGAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAASEmOIS4HijMV0AAAAA
# BIQwDQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIJsB
# Z14tK+MDsxa0F9X7hjEhG7gjX+356KYExeDdz5tXMEIGCisGAQQBgjcCAQwxNDAy
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20wDQYJKoZIhvcNAQEBBQAEggEAeBcjMI4a9AYs3SX5zzytbGcWhlS/SnQfAUTe
# /ztm/GgsVJiPlKVG7M2WOReaDmz2rB7FZedGDiHu58ZtiKRynMAiyWxYTU6ENO6f
# taP5rzilrilC8kiospCivHQm6AATsoOV9TBaAKiJcusgPE86M4DMVtSTesKOEl3B
# ZW8XvadCDRGc+QMhhiPRK552kSwQJSqWdVYGRm63viMo28SPha6t3ngbVytEVE49
# RloPQYdXIQjkxiZFmUrSlyxk0aQNGF2ftNvKdqev9toevp7F0TCElBrP2YJVvSep
# 3wxmSLcwvnJnr4E+xtuidBH7UCsuZvSTzagLCZZ3VvY+NjymFqGCF5QwgheQBgor
# BgEEAYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJYIZI
# AWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGE
# WQoDATAxMA0GCWCGSAFlAwQCAQUABCDph9e58rfGhBuwfeeMKCuuPvRRLkz7mxSV
# 4CPGwbdYVQIGaF2uQozQGBMyMDI1MDcyNTAwMTM1Ny4zMzhaMASAAgH0oIHRpIHO
# MIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQL
# ExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxk
# IFRTUyBFU046OEQwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFNlcnZpY2WgghHqMIIHIDCCBQigAwIBAgITMwAAAg0Nd757No9/4wAB
# AAACDTANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAx
# MDAeFw0yNTAxMzAxOTQzMDFaFw0yNjA0MjIxOTQzMDFaMIHLMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1l
# cmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046OEQwMC0w
# NUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Uw
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCxf6gH3fH3wgmFN5TV8zRF
# /N0TJguWUYCrQZPUmwA+QhSySNp7kiGmFZd4b5zsAfN0Wh+PzIJvYsVMgVCaZcbV
# r/DJBfexwnQfc+fgIjOiAzYSjg7EtSOdWoLk81b/mGiGIBC++fLcSAzbZO3KtW4P
# RKOSsdD/5eRdtNca/Ed4EAcUT32zAGS9Sq//4kDT92KEzRNXJj8z3NDL4oGGzCQM
# vA83tQG5mrnepxF0OsNfKKHYHMqjyOEP5pTgKfT5XMfz0sEG6ARAjlXJ79SG/joe
# uHh8TqC+cJMry9wB7ZLrdMAFy8rHN3W1+kkpw47Ko+9ize2ble+P5jMaqufK033B
# u+2FXVSKphil2j0qBUWpn5vBtf2W+gsVqydA+eseBHfYxcDZ4+5oRoyDAg0tW9f7
# 9vOAv91P4bTzG+BZPBbDMzSDwmj8ASKDlVwruTeF1em7NWiedWAB+29gFH/c/NN1
# uTQLvwGDIOw1DcLnCD0VXNL7mOvifYvNWugTAHcMFLVlA1jeOH35E/IW9qcKKqra
# h7LyJax/6M5UHswQugGgLriiMNEvz3IqW+AiIJ097iYzMGzsDqbLSUztIjDEt9xf
# IHHUs/p3j9Bkr2bPP1v4z8vp/45Ck3mfFbW2F0EtjOCnGPMrJNjjGhEG9zAK1105
# Bg2kJ7Rn8WTWO5IbD/rDtQIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFBWXjpDmDgNr
# TsISj26SjU1/YMOAMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8G
# A1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBs
# BggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUy
# MDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
# AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQAcH8gT42wVQ8GQ
# Z+MHIXNJ+d4dQn0+vPG/AdFvTxk/tvOOkA2i7hnoEOEFcSbzS5EdIVCMi5Y5EiWT
# 8hEJkztdeq5hXtUWsPY+2lYSU9HdhKDfRDfjwVZ9kfCthrLRC3jw9Fah5MAGI9MH
# SETo9r7+cux8AUqQ3hmaM2jmTNWvrFOLbO01B1ciNGbvE2xK+rbzBBh/uWd3k30p
# au6Lp0azg7rDYGMGv8jWotILfpKMBeCQoufMsI/gzxo4+k9dqYBkAwMk7h1hf23y
# cb5WngSMQV/Uxl3Sxbg+64KK6GCsTSG6z7zNTgbL69PMGfwV2cnawY95Iy2cgJ6c
# bMORRUcYzvsuUd8oEQ87cW4XqqBLrheewJjROT6YyWrQ2oQ+jzGK2WJoGNnfanmN
# fqQnVKpi320onag95LMFjj8BwrflYsO9kEOiy7I5UngPBmF+RHSCv2hFSr8nK7gt
# uiy9SUOKP6FbQOzyMRvJ3UxsmrH38477XzETb/tZLAj10TdYFfkjkFeFjlb3iMTS
# s/VrJSF0r0vON/oxZqKCY8WZez+uQP0Try0QQ9wRp5D2FYJ8E1uIX/LvwuFkBdWf
# 7X7qlb+pzdvPpSAcaCgBIWTlMn2bWgkU5uPzxRPHh/0u+FI7/eRCZGbLM2qnn3yX
# QvO/h9wQm8pIABRAvodaiV0bVmHbETCCB3EwggVZoAMCAQICEzMAAAAVxedrngKb
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
# ELQdVTNYs6FwZvKhggNNMIICNQIBATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJp
# Y2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjhEMDAtMDVF
# MC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMK
# AQEwBwYFKw4DAhoDFQB7LCwoj6G3nQ7Oxhl/pfne4yATPaCBgzCBgKR+MHwxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7C0UQDAi
# GA8yMDI1MDcyNDIwMjEyMFoYDzIwMjUwNzI1MjAyMTIwWjB0MDoGCisGAQQBhFkK
# BAExLDAqMAoCBQDsLRRAAgEAMAcCAQACAgiOMAcCAQACAhKLMAoCBQDsLmXAAgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
# AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBACdTYdu2Dkg4FMPCnYuxhjiS9Au9
# YZP0J3LzHHhJCx1D7L1f1zyVabvmrTOx973qlF8qNjY65uGsFpjZ0h4HvY0j8ffu
# 3EjftwZIhr/LZwpneFX5Pp3ShBRoLVNUsTlQ1DJ/5HRxDvcasEAIbH+ExWN0rXWd
# 3FEBoYvitrwlunewqB0lkFXN6BGCcvZHjpClG5/G1Gxp0XA77ZezZPJBhrCqXthR
# 0ivHz/aTCZJ6jZ2Caz70uVReYqj8BWzxuPI1B4z8aztjvKJ3NOYa9o+noJibvjc0
# BBdjl1/7oKC4AMT43f2T62Y4dkIBYtFep8+9vaTO2pmRN8DMYr5fG/E2wPgxggQN
# MIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAg0N
# d757No9/4wABAAACDTANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCA72mxx/dEEgZd6QujZWAL5UVDD
# 3DKYNHyaKUKrLz/ECTCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIGPqB5Ts
# JGqI8OuknBKtSvb0Ffq6w5NSs5veTVwka/hAMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAINDXe+ezaPf+MAAQAAAg0wIgQgplFXKG0k
# HRyE9dleFn9RPCaOPGqLh0+JQUb4covNveQwDQYJKoZIhvcNAQELBQAEggIAoYCe
# o8BLdGfx06IY12OeXqASz76pRYs3cnPv4yPkW7DB7tph7ebfn126klXj8rEC70ks
# dqSUCgOPp8AvIqKsn1QzB1Zvq6K/vzR7P6BY3VOxMMtCakZsE4EADLA8tIl0rRMa
# xqgEfTrvaY73UT3P7e5LLi+8gjccWpwKDECbGMdnGbIxmldBxhSkG/T7CU3j1twE
# 4VsRtdkkHEsdKRuC/ofJXXMRI4L8Fo8VCiPIQBZ00Ne2vK2pQHnTsOZuhPggRo1A
# feUbzTK0Ss8tmLwIcTm6VlL1upda5eSU/+qf9YO1ECItzLmt1Z4MQVy6/yJOEOvx
# coMInHdHsoIqnDOGRvrW1jUup/mZn+IKzUh5ymwaxnOHnjS5oO/u1b/fMZNwEd3z
# pXEHGBrnswbHCamaQ4oNNE0K/SZ0OIPHbd8PjOxzwFazyE0la8GIXIxHtUdBByUp
# 2WmlUgqfZbvdXPpC4QX/OQaBeS8qcGm6xwUstu+Q7Yt30j7ryWw1gb7Ivt/dP2dB
# jiz5b5J7XnADbSKnQNS44OQvG2brPQMRvTrkYI1upHWf8A6JIc6oOwiW5+91MmbA
# Yi369FvMs+WoYRj/7LGONmfHBhIlKS1By25hwnLYvqJyNWIpFsmX0Tn+9czjjGvQ
# 8WYGD6c3VReEwQLlu5BXPNcX0CQD9U//wVdmLn8=
# SIG # End signature block
