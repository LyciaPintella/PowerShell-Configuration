# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

using namespace System.Collections.Generic

# Check that we are running as an administrator
function Assert-IsAdministrator
{
    $windowsIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $windowsPrincipal = New-Object -TypeName 'System.Security.Principal.WindowsPrincipal' -ArgumentList @( $windowsIdentity )

    $adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator

    if (-not $windowsPrincipal.IsInRole($adminRole))
    {
        New-InvalidOperationException -Message "This resource must run as an Administrator."
    }
}

#region enums
enum WinGetAction
{
    Partial
    Full
}

enum WinGetEnsure
{
    Absent
    Present
}

enum WinGetMatchOption
{
    Equals
    EqualsCaseInsensitive
    StartsWithCaseInsensitive
    ContainsCaseInsensitive
}

enum WinGetInstallMode
{
    Default
    Silent
    Interactive
}

enum WinGetTrustLevel
{
    Undefined
    None
    Trusted
}

#endregion enums

#region DscResources
# Author here all DSC Resources.
# DSC Powershell doesn't support binary DSC resources without the MOF schema.
# DSC Powershell classes aren't discoverable if placed outside of the psm1.

# This resource is in charge of managing the settings.json file of winget.
[DSCResource()]
class WinGetUserSettings
{
    # We need a key. Do not set.
    [DscProperty(Key)]
    [string]$SID

    # A hash table with the desired settings.
    [DscProperty(Mandatory)]
    [Hashtable]$Settings

    [DscProperty()]
    [WinGetAction]$Action = [WinGetAction]::Full

    # Gets the current UserSettings by looking at the settings.json file for the current user.
    [WinGetUserSettings] Get()
    {
        $userSettings = Get-WinGetUserSetting
        $result = @{
            SID = ''
            Settings = $userSettings
        }
        return $result
    }

    # Tests if desired properties match.
    [bool] Test()
    {
        $hashArgs = @{
            UserSettings = $this.Settings
        }

        if ($this.Action -eq [WinGetAction]::Partial)
        {
            $hashArgs.Add('IgnoreNotSet', $true)
        }

        return Test-WinGetUserSetting @hashArgs
    }

    # Sets the desired properties.
    [void] Set()
    {
        $hashArgs = @{
            UserSettings = $this.Settings
        }

        if ($this.Action -eq [WinGetAction]::Partial)
        {
            $hashArgs.Add('Merge', $true)
        }

        Set-WinGetUserSetting @hashArgs
    }
}

# Handles configuration of administrator settings.
[DSCResource()]
class WinGetAdminSettings
{
    # We need a key. Do not set.
    [DscProperty(Key)]
    [string]$SID

    # A hash table with the desired admin settings.
    [DscProperty(Mandatory)]
    [Hashtable]$Settings

    # Gets the administrator settings.
    [WinGetAdminSettings] Get()
    {
        $settingsJson = Get-WinGetSetting
        # Get admin setting values.

        $result = @{
            SID = ''
            Settings = $settingsJson.adminSettings
        }
        return $result
    }

    # Tests if administrator settings given are set as expected.
    # This doesn't do a full comparison to allow users to don't have to update
    # their resource every time a new admin setting is added on winget.
    [bool] Test()
    {
        $adminSettings = $this.Get().Settings
        foreach ($adminSetting in $adminSettings.GetEnumerator())
        {
            if ($this.Settings.ContainsKey($adminSetting.Name))
            {
                if ($this.Settings[$adminSetting.Name] -ne $adminSetting.Value)
                {
                    return $false
                }
            }
        }

        return $true
    }

    # Sets the desired properties.
    [void] Set()
    {
        Assert-IsAdministrator

        # It might be better to implement an internal Test with one value, or
        # create a new instances with only one setting than calling Enable/Disable
        # for all of them even if only one is different.
        if (-not $this.Test())
        {
            foreach ($adminSetting in $this.Settings.GetEnumerator())
            {
                if ($adminSetting.Value)
                {
                    Enable-WinGetSetting -Name $adminSetting.Name
                }
                else
                {
                    Disable-WinGetSetting -Name $adminSetting.Name
                }
            }
        }
    }
}

[DSCResource()]
class WinGetSource
{
    [DscProperty(Key, Mandatory)]
    [string]$Name
    
    [DscProperty(Mandatory)]
    [string]$Argument
    
    [DscProperty()]
    [string]$Type
    
    [DscProperty()]
    [WinGetTrustLevel]$TrustLevel = [WinGetTrustLevel]::Undefined
    
    [DscProperty()]
    [nullable[bool]]$Explicit = $null
    
    [DscProperty()]
    [nullable[int]]$Priority = $null

    [DscProperty()]
    [WinGetEnsure]$Ensure = [WinGetEnsure]::Present

    [WinGetSource] Get()
    {
        if ([String]::IsNullOrWhiteSpace($this.Name))
        {
            throw "A value must be provided for WinGetSource::Name"
        }

        $currentSource = $null

        try {
            $currentSource = Get-WinGetSource -Name $this.Name
        }
        catch {
        }

        $result = [WinGetSource]::new()

        if ($currentSource)
        {
            $result.Ensure = [WinGetEnsure]::Present
            $result.Name = $currentSource.Name
            $result.Argument = $currentSource.Argument
            $result.Type = $currentSource.Type
            $result.TrustLevel = $currentSource.TrustLevel
            $result.Explicit = $currentSource.Explicit
            $result.Priority = $currentSource.Priority
        }
        else
        {
            $result.Ensure = [WinGetEnsure]::Absent
            $result.Name = $this.Name
        }

        return $result
    }

    [bool] Test()
    {
        return $this.TestAgainstCurrent($this.Get())
    }

    [void] Set()
    {
        Assert-IsAdministrator

        $currentSource = $this.Get()

        $removeSource = $false
        $resetSource = $false
        $addSource = $false

        if ($this.Ensure -eq [WinGetEnsure]::Present)
        {
            if ($currentSource.Ensure -eq [WinGetEnsure]::Present)
            {
                if (-not $this.TestAgainstCurrent($currentSource))
                {
                    $resetSource = $true
                    $addSource = $true
                }
                # else in desired state
            }
            else
            {
                $addSource = $true
            }
        }
        else
        {
            if ($currentSource.Ensure -eq [WinGetEnsure]::Present)
            {
                $removeSource = $true
            }
            # else in desired state (Absent)
        }

        if ($removeSource)
        {
            Remove-WinGetSource -Name $this.Name
        }
        # Only remove OR reset should be true, not both
        elseif ($resetSource)
        {
            Reset-WinGetSource -Name $this.Name
        }

        if ($addSource)
        {
            $hashArgs = @{
                Name = $this.Name
                Argument = $this.Argument
            }

            if (-not [string]::IsNullOrWhiteSpace($this.Type))
            {
                $hashArgs.Add("Type", $this.Type)
            }

            if ($this.TrustLevel -ne [WinGetTrustLevel]::Undefined)
            {
                $hashArgs.Add("TrustLevel", $this.TrustLevel)
            }

            if ($null -ne $this.Explicit)
            {
                $hashArgs.Add("Explicit", $this.Explicit)
            }

            if ($null -ne $this.Priority)
            {
                $hashArgs.Add("Priority", $this.Priority)
            }

            Add-WinGetSource @hashArgs
        }
    }
    
    # Test $this against a value retrieved from Get
    # We don't need to check Name because it is the Key for Get
    [bool] hidden TestAgainstCurrent([WinGetSource]$currentSource)
    {
        if ($this.Ensure -eq [WinGetEnsure]::Absent -and
            $currentSource.Ensure -eq [WinGetEnsure]::Absent)
        {
            return $true
        }

        if ($this.Ensure -ne $currentSource.Ensure -or
            $this.Argument -ne $currentSource.Argument)
        {
            return $false
        }

        if (-not([string]::IsNullOrWhiteSpace($this.Type)) -and
            $this.Type -ne $currentSource.Type)
        {
            return $false
        }

        if ($this.TrustLevel -ne [WinGetTrustLevel]::Undefined -and
            $this.TrustLevel -ne $currentSource.TrustLevel)
        {
            return $false
        }

        if ($null -ne $this.Explicit -and
            $this.Explicit -ne $currentSource.Explicit)
        {
            return $false
        }

        if ($null -ne $this.Priority -and
            $this.Priority -ne $currentSource.Priority)
        {
            return $false
        }

        return $true
    }
}

# TODO: It would be nice if these resource has a non configurable property that has extra information that comes from
# GitHub. We could implement it here or add more cmdlets in Microsoft.WinGet.Client.
[DSCResource()]
class WinGetPackageManager
{
    # We need a key. Do not set.
    [DscProperty(Key)]
    [string]$SID

    [DscProperty()]
    [string]$Version = ""

    [DscProperty()]
    [bool]$UseLatest

    [DscProperty()]
    [bool]$UseLatestPreRelease

    # If winget is not installed the version will be empty.
    [WinGetPackageManager] Get()
    {
        $integrityResource = [WinGetPackageManager]::new()
        if ($integrityResource.Test())
        {
            $integrityResource.Version = Get-WinGetVersion
        }

        return $integrityResource
    }

    # Tests winget is installed.
    [bool] Test()
    {
        try
        {
            $hashArgs = @{}

            if ($this.UseLatest)
            {
                $hashArgs.Add("Latest", $true)
            } elseif ($this.UseLatestPreRelease)
            {
                $hashArgs.Add("Latest", $true)
                $hashArgs.Add("IncludePrerelease", $true)
            } elseif (-not [string]::IsNullOrWhiteSpace($this.Version))
            {
                $hashArgs.Add("Version", $this.Version)
            }

            Assert-WinGetPackageManager @hashArgs
        }
        catch
        {
            return $false
        }

        return $true
    }

    # Repairs Winget.
    [void] Set()
    {
        if (-not $this.Test())
        {
            $result = -1
            $hashArgs = @{}

            if ($this.UseLatest)
            {
                $hashArgs.Add("Latest", $true)
            } elseif ($this.UseLatestPreRelease)
            {
                $hashArgs.Add("Latest", $true)
                $hashArgs.Add("IncludePrerelease", $true)
            } elseif (-not [string]::IsNullOrWhiteSpace($this.Version))
            {
                $hashArgs.Add("Version", $this.Version)
            }

            $result = Repair-WinGetPackageManager @hashArgs

            if ($result -ne 0)
            {
                # TODO: Localize.
                throw "Failed to repair winget. Result $result"
            }
        }
    }
}

[DSCResource()]
class WinGetPackage
{
    [DscProperty(Key, Mandatory)]
    [string]$Id

    [DscProperty(Key)]
    [string]$Source

    [DscProperty()]
    [string]$Version

    [DscProperty()]
    [WinGetEnsure]$Ensure = [WinGetEnsure]::Present

    [DscProperty()]
    [WinGetMatchOption]$MatchOption = [WinGetMatchOption]::EqualsCaseInsensitive

    [DscProperty()]
    [bool]$UseLatest = $false

    [DSCProperty()]
    [WinGetInstallMode]$InstallMode = [WinGetInstallMode]::Silent

    [PSObject] hidden $CatalogPackage = $null

    [WinGetPackage] Get()
    {
        if ([String]::IsNullOrWhiteSpace($this.Id))
        {
            throw "A value must be provided for WinGetPackage::Id"
        }

        $result = [WinGetPackage]::new()

        $hashArgs = @{
            Id = $this.Id
            MatchOption = $this.MatchOption
        }

        if (-not([string]::IsNullOrWhiteSpace($this.Source)))
        {
            $hashArgs.Add("Source", $this.Source)
        }

        $result.CatalogPackage = Get-WinGetPackage @hashArgs
        if ($null -ne $result.CatalogPackage)
        {
            $result.Ensure = [WinGetEnsure]::Present
            $result.Id = $result.CatalogPackage.Id
            $result.Source = $result.CatalogPackage.Source
            $result.Version = $result.CatalogPackage.InstalledVersion
            $result.UseLatest = -not $result.CatalogPackage.IsUpdateAvailable
        }
        else
        {
            $result.Ensure = [WinGetEnsure]::Absent
            $result.Id = $this.Id
            $result.MatchOption = $this.MatchOption
            $result.Source = $this.Source
        }

        return $result
    }

    [bool] Test()
    {
        return $this.TestAgainstCurrent($this.Get())
    }

    [void] Set()
    {
        $currentPackage = $this.Get()

        if (-not $this.TestAgainstCurrent($currentPackage))
        {
            $hashArgs = @{
                Id = $this.Id
                MatchOption = $this.MatchOption
                Mode = $this.InstallMode
            }
            
            if ($this.Ensure -eq [WinGetEnsure]::Present)
            {
                if (-not([string]::IsNullOrWhiteSpace($this.Source)))
                {
                    $hashArgs.Add("Source", $this.Source)
                }

                if ($currentPackage.Ensure -eq [WinGetEnsure]::Present)
                {
                    if ($this.UseLatest)
                    {
                        $this.TryUpdate($hashArgs)
                    }
                    elseif (-not([string]::IsNullOrWhiteSpace($this.Version)))
                    {
                        $hashArgs.Add("Version", $this.Version)

                        $compareResult = $currentPackage.CatalogPackage.CompareToVersion($this.Version)
                        switch ($compareResult)
                        {
                            'Lesser'
                            {
                                $this.TryUpdate($hashArgs)
                                break
                            }
                            {'Greater' -or 'Unknown'}
                            {
                                # The installed package has a greater version or unknown. Uninstall and install.
                                $this.Uninstall()
                                $this.Install($hashArgs)
                                break
                            }
                        }
                    }
                }
                else
                {
                    if (-not([string]::IsNullOrWhiteSpace($this.Version)))
                    {
                        $hashArgs.Add("Version", $this.Version)
                    }

                    $this.Install($hashArgs)
                }
            }
            else
            {
                $this.Uninstall()
            }
        }
    }
    
    [bool] hidden TestAgainstCurrent([WinGetPackage]$currentPackage)
    {
        if ($this.Ensure -eq [WinGetEnsure]::Absent -and
            $currentPackage.Ensure -eq [WinGetEnsure]::Absent)
        {
            return $true
        }

        $this.CatalogPackage = $currentPackage.CatalogPackage

        if ($this.Ensure -ne $currentPackage.Ensure)
        {
            return $false
        }

        # At this point we know is installed.
        # If asked for latest, but there are updates available.
        if ($this.UseLatest)
        {
            if (-not $currentPackage.UseLatest)
            {
                return $false
            }
        }
        # If there is an specific version, compare with the current installed version.
        elseif (-not ([string]::IsNullOrWhiteSpace($this.Version)))
        {
            $compareResult = $currentPackage.CatalogPackage.CompareToVersion($this.Version)
            if ($compareResult -ne 'Equal')
            {
                return $false
            }
        }

        return $true
    }

    hidden Install([Hashtable]$hashArgs)
    {
        $installResult = Install-WinGetPackage @hashArgs
        if (-not $installResult.Succeeded())
        {
            # TODO: Localize.
            throw "WinGetPackage Failed installing $($this.Id). $($installResult.ErrorMessage())"
        }
    }

    hidden Uninstall()
    {
        $uninstallResult = Uninstall-WinGetPackage -PSCatalogPackage $this.CatalogPackage
        if (-not $uninstallResult.Succeeded())
        {
            # TODO: Localize.
            throw "WinGetPackage Failed uninstalling $($this.Id). $($uninstallResult.ErrorMessage())"
        }
    }

    hidden Update([Hashtable]$hashArgs)
    {
        $updateResult = Update-WinGetPackage @hashArgs
        if (-not $updateResult.Succeeded())
        {
            # TODO: Localize.
            throw "WinGetPackage Failed updating $($this.Id). $($updateResult.ErrorMessage())"
        }
    }

    # Tries to update, if not, uninstall and install.
    hidden TryUpdate([Hashtable]$hashArgs)
    {
        try
        {
            $this.Update($hashArgs)
        }
        catch
        {
            $this.Uninstall()
            $this.Install($hashArgs)
        }
    }
}

#endregion DscResources

# SIG # Begin signature block
# MIInRAYJKoZIhvcNAQcCoIInNTCCJzECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA0StRn1jl/M5U2
# 2aJwI5Dbe9p/U/blobOaSnuF+Api3aCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# 1cY2L4A7GTQG1h32HHAvfQESWP0xghngMIIZ3AIBATBuMFcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIdTRnITtcPV0gAAAAAAh0w
# DQYJYIZIAWUDBAIBBQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJ
# KoZIhvcNAQkEMSIEIK8ykSG07VhTk5z+ODteGUHR8X5eedwq8Yx55KpOm1ixMEIG
# CisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAe0t7811WE7NUJE+1
# LnERcZ5ma2QrBTzcHOo5Uxuf77zA1ObF5qyu6sVytdTtodeD88Va4V4ANzPMkZIh
# DDH0QR2RquAjpFLuClWw4nl6mb/Eyb1McNNtjpLdrwCNX8XrP8l0Krh2jVZ7e0qR
# FGlLtn9zn/lBr2vRhWaWEZYmk3mTULPhvR3GQf3YwtGg9OUtDNqlYEXh7txtzG6J
# +BQ6hWlpEYR9hu36wdFWUxosgjfQvNLfpVA9J6eg35QsEpZKkRTmj2/5+f03yN6/
# QaaFWP+n5WOALgqLOzDlOsVnQR//7nF2ioxF2FdW8IBgGCYo0m9OUaXcb1xGiewf
# yZtReqGCF7AwghesBgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kw
# gheFAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFF
# MIIBQQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCDpIRpkOcD6L6LW
# XYw3i2j9kI5bdj10KbJ5MnaU1/7kVgIGaokJpDA7GBMyMDI2MDkxNzAxNDMzMC4z
# MzlaMASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExp
# bWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo0MzFBLTA1RTAtRDk0NzEl
# MCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIF
# EKADAgECAhMzAAACHUvAkoc4hX45AAEAAAIdMA0GCSqGSIb3DQEBCwUAMHwxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI1MDgxNDE4NDgzM1oXDTI2MTEx
# MzE4NDgzM1owgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# LTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEn
# MCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjQzMUEtMDVFMC1EOTQ3MSUwIwYDVQQD
# ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEF
# AAOCAg8AMIICCgKCAgEAorSgaAA8oOl4ph574zw29egUN8DDepRHLX8FM1zHNJmX
# G6KrSqUKwzcKafopuYdPTETTCvb9aJfESuAU0iGNUFI/D6R0kvdfpe2oPX+E3sbT
# QvGi4JPH5qdIYUaJ45V/4bqe8eNvbWzpC+ZKjH193DeiI1XAI918JoQmBhlEXo/T
# on1721luZJgincsf5LjMY3jX84WyXUSX3dsS7h/7xVI+w1yjg7pa+0y3o/me2Tsv
# 6UJUdSTQap5ORGSfCnclnP1z3IiiWIWr3Vo7aIPWsgJzq3m5GxpxUHCQk8qzUhk5
# 0y/uB+LGE3WIK2C77iy9iFsSfSLUnyMEzGRDW9mXHT4PH7Ozz6CHqQEiNvwcHqlv
# lCh1pHQh1NXQSAqOoVBs5mi6easf6yxWTfe5DrR79503r8pU6VqC2Y9XMRU4wH9Q
# bYXYsIUZ33Jmndy22W1LBDAbxBPQHCBlncGDU3BgdhVUVLe80mggFO98FdkWho67
# w4kPdCTRkvdvkY8PrQYE/nQjHXCa0g7LcMttZb6ejMHfQ+tUWXv6+nZ4Ynkr2Oka
# xclFCw4RIYNMWD26AWbQj/WEdzga18fKtw66L5gzXPza6jFBfPJeKE3H8QAuwpir
# mH4ms+5nUjNNQOmNgqJn0U1+3Yn7ClswD79YN0r3fdbYBMDApBZJpNlK7q7HXRsC
# AwEAAaOCAUkwggFFMB0GA1UdDgQWBBSEWfBxNEamZtXm8gl92Yq80jfxXTAfBgNV
# HSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5o
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBU
# aW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwG
# CCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRz
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNV
# HRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIH
# gDANBgkqhkiG9w0BAQsFAAOCAgEAkdweB4yxvLspLKq0D+miyD4Q0EcxVFpNZuJx
# iR54gWRkeTDDuymNeB03JhlsBpbwSYJ5uZSgDBCvwHED2VL8lJpFlOprJzxsXWC2
# NTfA+O+PO5Fk5jw6LHh6jeBADDEdQAx3Hqi7Zm0JwvQ93z5f6dtxkm29WqOcHYXR
# XfAQwy1hSrLXyfeblqR66jpP/9n0fCkWU4ggsUjQpQ2Ngj1DV09J4Y3y7p9Nd81+
# Xs6qYo++7RKm8qiB/5NDeigOLjlAeFgiEXIRUJW+mJyqpQw+OORlaqcFjR8Hu0G+
# /7bMdek68YX+kPpDBk7Ue+I/xgiYJ1xcDRBn/vczLtN72+RIlD4UgXYLuBSCk//p
# DEPX5z39Cr+rkc6E4Y28FPk4BhloAyvp628P4xfElQY8TcxraUbZShypocE6ny95
# D1K1BkltZmrHVKCxmglnuOlM15NKIrXFlXCzdqpCtIwQ417wNAVF/QDPvzzbumPd
# Ti6fb0tLbScYobV6zvbBsMsKEME4Tj1b9oIXC8dybJq4nbboEXYpRwi1QAbpSNrn
# +PxGW9uf1q63FnMJu4gm3Oh63njW/iVf723quzyHrSijWMgY0HiRiHQi0Jyu0h8M
# dhRUp7mxbmLQckPiOFwAlIaUN/k725y/aLWpkRU6fqmLlEOyH5WpyLd23AYy9r8v
# +Qoba6swggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3
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
# vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDWTCC
# AkECAQEwggEBoYHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExp
# bWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo0MzFBLTA1RTAtRDk0NzEl
# MCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsO
# AwIaAxUAuoO+BKbfXzqyfi9GLEdWHkCLeT+ggYMwgYCkfjB8MQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAO5VI6UwIhgPMjAyNjA5
# MTYxNDE4MTNaGA8yMDI2MDkxNzE0MTgxM1owdzA9BgorBgEEAYRZCgQBMS8wLTAK
# AgUA7lUjpQIBADAKAgEAAgILLwIB/zAHAgEAAgIUHjAKAgUA7lZ1JQIBADA2Bgor
# BgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAID
# AYagMA0GCSqGSIb3DQEBCwUAA4IBAQA1KhnlYB5aYaiwp/G/MKIHysUPEoMJ7QHC
# jTKbRL6Gcb3WL5IrJiGOfCyEfWxs52oOGculVdpL1o00OR+fhkArDhRe/HUHkl2l
# Lz06uaA+3LQZhazFLyIgyq88gyDYdvThKCDs4o1LNfotiworjM2xdKFtArs2/iAX
# sUnD54GhL7tMuihyORVNRpig2px21oW4TrtlKbhDumotFmHGjsicikq7i5aHLx88
# 7qZ2iY7ZVS3Fcr0LIlJmaFoObXjEobAjMQXR7XavaIeMILjl8jEwvKfHgaYAVQpo
# mD3TGVTzynRfoC1NNixpQYVCFADj0vyWY9X+r9GnHQSpxxcRe2N7MYIEDTCCBAkC
# AQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIdS8CShziF
# fjkAAQAAAh0wDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG
# 9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgRbBlLFBa7B/Uc1xi5Yv+AhreiLlzlKfN
# 7cTtF6W+M08wgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCCxtpXMXEiLJzrq
# M77ep4rTNwrMOj6gpWN9hZvpj5QFUTCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwAhMzAAACHUvAkoc4hX45AAEAAAIdMCIEINpb23dlwBfh5DkM
# tjmaxrOPmkyd/RpkPDWLPrNT17g9MA0GCSqGSIb3DQEBCwUABIICACntqB+Hxrp3
# OHRsifqx20V1Lo6Dj29ulMOBIJH9D49fVW1ARe0acrVWc8arCOV/d75wez/sriOw
# AuWaQq6Acw4GHCk7VKoiGxbbm8h9S2gIEcDgVWQk9Ijz/K8sK2rgIRkkhpNkdqrw
# urDbTPMqj0xw3v75ruvDQsIRKwYRc5WK625XgOSUuEltuy0BSIM2fZuSpEYlNOeq
# efzLFrW6hBiqqMmXl1uFWwFYnjxW/rCEWEzKx/pOOdVmdfF6UZyGja2DoCKtSkXX
# l7VEyulj7VGw/fgp0eh6QP9Up5+c/KUgk5PNmUUz75TxO51jDGYEsGnNXTtEoPB1
# 6WiC69eTW25016/0rl8AG4YdBRkPcSKQU28h07lvf9dSt705WSE15S7cR+xYHVCZ
# cXGozgTKNj9vRiw/91vo7ax5G6eG9Wy0T5Ld4czydfP7k+fHxftiodRoMZNdTwrM
# Jg/8Qz6DO2uCTm+2s1F5igMJWM5NYGyuNklEgL+STWQq2qN56N2ORBDNup8ocHXV
# 5KRHqhrom7QLVwX0j1wItFIfNCSbyygQJpOGT3gkSlAhR3wA4ZovhDh6m9SSrgUy
# MZt/fLxVWf4XpApPstctF1g65WOhRo1KrYmLG4Q+IGn2iMWgUDsghWz8MdyxRc3w
# jNiTzKrBgD4G4wQ5TIBbonFwvS9VuGYK
# SIG # End signature block
