## Copyright (c) Microsoft Corporation. All rights reserved.
## Licensed under the MIT License.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('repository', 'psresource', 'repositorylist', 'psresourcelist')]
    [string]$ResourceType,
    [Parameter(Mandatory = $true)]
    [ValidateSet('get', 'set', 'test', 'delete', 'export')]
    [string]$Operation,
    [Parameter(ValueFromPipeline)]
    $stdinput,
    [switch]$WhatIf
)

enum Scope {
    CurrentUser
    AllUsers
}

enum ExitCode {
    Success = 0
    Error = 1
    RepositoryNotFound = 2
    RepositoryNotTrusted = 3
    InstallationFailed = 4
    UnknownResourceType = 5
    ResourceNotImplemented = 6
    TestNotImplemented = 7
    ExportNotImplemented = 8
    GetNotImplemented = 9
    SetNotImplemented = 10
    DeleteNotImplemented = 11
    UnknownOperation = 12
}

class PSResource {
    [string]$name
    [string]$version
    [Scope]$scope
    [string]$repositoryName
    [bool]$preRelease
    [bool]$_exist
    [bool]$_inDesiredState
    [object]$_metadata

    PSResource([string]$name, [string]$version, [Scope]$scope, [string]$repositoryName, [bool]$preRelease) {
        $this.name = $name
        $this.version = $version
        $this.scope = $scope
        $this.repositoryName = $repositoryName
        $this.preRelease = $preRelease
        $this._exist = $true
    }

    PSResource([string]$name) {
        $this.name = $name
        $this._exist = $false
    }

    [bool] IsInDesiredState([PSResource] $other) {
        $retValue = $true

        $psResourceSplat = @{
            Name           = $this.name
            Version        = if ($this.version) { $this.version } else { '*' }
        }

        Get-PSResource @psResourceSplat | Where-Object {
            ($null -eq $this.scope -or $_.Scope -eq $this.scope) -and
            ($null -eq $this.repositoryName -or $_.Repository -eq $this.repositoryName)
        } | Select-Object -First 1 | ForEach-Object {
            Write-Trace -message "Matching resource found: Name=$($_.Name), Version=$($_.Version), Scope=$($_.Scope), Repository=$($_.Repository), PreRelease=$($_.PreRelease)" -level debug
            $this._exist = $true
        }

        if ($this.name -ne $other.name) {
            Write-Trace -message "Name mismatch: $($this.name) vs $($other.name)" -level debug
            $retValue = $false
        }
        elseif ($null -ne $this.version -and $null -ne $other.version -and -not (SatisfiesVersion -version $this.version -versionRange $other.version)) {
            Write-Trace -message "Version mismatch: $($this.version) vs $($other.version)" -level debug
            $retValue = $false
        }
        elseif ($null -ne $this.scope -and $this.scope -ne $other.scope) {
            Write-Trace -message "Scope mismatch: $($this.scope) vs $($other.scope)" -level debug
            $retValue = $false
        }
        elseif ($null -ne $this.repositoryName -and $this.repositoryName -ne $other.repositoryName) {
            Write-Trace -message "Repository mismatch: $($this.repositoryName) vs $($other.repositoryName)" -level debug
            $retValue = $false
        }
        elseif ($this._exist -ne $other._exist) {
            Write-Trace -message "_exist mismatch: $($this._exist) vs $($other._exist)" -level debug
            $retValue = $false
        }

        return $retValue
    }

    [string] ToJson() {
        [string[]]$excludeProps = @('_inDesiredState')
        if ($null -eq $this._metadata) { $excludeProps += '_metadata' }
        $retVal = ($this | Select-Object -ExcludeProperty $excludeProps | ConvertTo-Json -Compress -EnumsAsStrings)
        Write-Trace -message "Serializing PSResource to JSON. Name: $($this.name), Version: $($this.version), Scope: $($this.scope), RepositoryName: $($this.repositoryName), PreRelease: $($this.preRelease), _exist: $($this._exist)" -level debug
        Write-Trace -message "Serialized JSON: $retVal" -level trace
        return $retVal
    }

    [string] ToJsonForTest() {
        [string[]]$excludeProps = @()
        if ($null -eq $this._metadata) { $excludeProps += '_metadata' }
        return ($this | Select-Object -ExcludeProperty $excludeProps | ConvertTo-Json -Compress -Depth 5 -EnumsAsStrings)
    }
}

class PSResourceList {
    [string]$repositoryName
    [PSResource[]]$resources
    [bool]$trustedRepository
    [bool]$_inDesiredState

    PSResourceList([string]$repositoryName, [PSResource[]]$resources, [bool]$trustedRepository) {
        $this.repositoryName = $repositoryName
        $this.resources = $resources
        $this.trustedRepository = $trustedRepository
    }

    [bool] IsInDesiredState([PSResourceList] $other) {
        if ($this.repositoryName -ne $other.repositoryName) {
            Write-Trace -message "RepositoryName mismatch: $($this.repositoryName) vs $($other.repositoryName)" -level debug
            return $false
        }

        if ($null -ne $this.resources -and $this.resources.Count -ne $other.resources.Count) {
            Write-Trace -message "Resources count mismatch: $($this.resources.Count) vs $($other.resources.Count)" -level debug
            return $false
        }

        foreach ($otherResource in $other.resources) {
            $found = $false
            foreach ($resource in $this.resources) {
                if ($resource.IsInDesiredState($otherResource)) {
                    $found = $true
                    break
                }
            }

            if ($found) {
                Write-Trace -message "Resource match found for: $($otherResource.name)" -level debug
                break
            }
            else {
                Write-Trace -message "Resource mismatch for: $($otherResource.name)" -level debug
                return $false
            }
        }

        return $true
    }

    [string] ToJson() {
        ## Assign the array directly so that an empty list serializes as [] rather than null
        [object[]]$resourceObjects = @()
        if ($this.resources) {
            $resourceObjects = @($this.resources | ForEach-Object {
                [string[]]$excludeProps = @('_inDesiredState')
                if ($null -eq $_._metadata) { $excludeProps += '_metadata' }
                $_ | Select-Object -ExcludeProperty $excludeProps
            })
        }
        $retVal = [ordered]@{
            repositoryName = $this.repositoryName
            resources      = $resourceObjects
        } | ConvertTo-Json -Compress -Depth 5 -EnumsAsStrings
        Write-Trace -message "Serializing PSResourceList to JSON. RepositoryName: $($this.repositoryName), TrustedRepository: $($this.trustedRepository), Resources count: $($this.resources.Count)" -level debug
        Write-Trace -message "Serialized JSON: $retVal" -level trace
        return $retVal
    }

    [string] ToJsonForTest() {
        Write-Trace -message "Serializing PSResourceList to JSON for test output. RepositoryName: $($this.repositoryName), TrustedRepository: $($this.trustedRepository), Resources count: $($this.resources.Count)" -level debug
        [object[]]$resourceObjects = @()
        if ($this.resources) {
            $resourceObjects = @($this.resources | ForEach-Object {
                [string[]]$excludeProps = @()
                if ($null -eq $_._metadata) { $excludeProps += '_metadata' }
                if ($excludeProps.Count -gt 0) { $_ | Select-Object -ExcludeProperty $excludeProps } else { $_ }
            })
        }
        $retVal = [ordered]@{
            repositoryName    = $this.repositoryName
            resources         = $resourceObjects
            trustedRepository = $this.trustedRepository
            _inDesiredState   = $this._inDesiredState
        } | ConvertTo-Json -Compress -Depth 5 -EnumsAsStrings
        Write-Trace -message "Serialized JSON: $retVal" -level trace
        return $retVal
    }
}

class Repository {
    [string]$name
    [string]$uri
    [bool]$trusted
    [int]$priority
    [string]$repositoryType
    [bool]$_exist

    Repository([string]$name) {
        $this.name = $name
        $this._exist = $false
        $this.repositoryType = 'Unknown'
    }

    Repository([string]$name, [string]$uri, [bool]$trusted, [int]$priority, [string]$repositoryType) {
        $this.name = $name
        $this.uri = $uri
        $this.trusted = $trusted
        $this.priority = $priority
        $this.repositoryType = $repositoryType
        $this._exist = $true
    }

    Repository([PSCustomObject]$repositoryInfo) {
        $this.name = $repositoryInfo.Name
        $this.uri = $repositoryInfo.Uri
        $this.trusted = $repositoryInfo.Trusted
        $this.priority = $repositoryInfo.Priority
        $this.repositoryType = $repositoryInfo.ApiVersion
        $this._exist = $true
    }

    Repository([string]$name, [bool]$exist) {
        $this.name = $name
        $this._exist = $exist
        $this.repositoryType = 'Unknown'
    }

    [string] ToJson() {
        return ($this | ConvertTo-Json -Compress -EnumsAsStrings)
    }
}

function Write-Trace {
    param(
        [string]$message,

        [ValidateSet('error', 'warn', 'info', 'debug', 'trace')]
        [string]$level = 'trace'
    )

    $trace = [pscustomobject]@{
        $level.ToLower() = $message
    } | ConvertTo-Json -Compress

    $host.ui.WriteErrorLine($trace)
}

function SatisfiesVersion {
    param(
        [string]$version,
        [string]$versionRange
    )

    $typeName = 'NuGet.Versioning.VersionRange'

    Write-Trace -message "Checking if version '$version' satisfies version range '$versionRange'." -level debug

    if ($typeName -as [type]) {
        Write-Trace -message "NuGet.Versioning assembly is already loaded. Using existing assembly." -level debug
    }
    else {
        Write-Trace -message "Loading NuGet.Versioning assembly from $PSScriptRoot/dependencies/NuGet.Versioning.dll" -level debug
        Add-Type -Path "$PSScriptRoot/dependencies/NuGet.Versioning.dll" -ErrorAction Stop | Out-Null
    }

    try {
        $versionRangeObj = [NuGet.Versioning.VersionRange]::Parse($versionRange)
        $resourceVersion = [NuGet.Versioning.NuGetVersion]::Parse($version)
        return $versionRangeObj.Satisfies($resourceVersion)
    }
    catch {
        Write-Trace -message "Error parsing version or version range: $($_.Exception.Message)" -level error
        return $false
    }
}

function ConvertInputToPSResource(
    [PSCustomObject]$inputObj,
    [string]$repositoryName = $null
) {
    $scope = if ($inputObj.Scope) { [Scope]$inputObj.Scope } else { [Scope]"CurrentUser" }

    $psResource = [PSResource]::new(
        $inputObj.Name,
        $inputObj.Version,
        $scope,
        $inputObj.repositoryName ? $inputObj.repositoryName : $repositoryName,
        $inputObj.PreRelease
    )

    if ($null -ne $inputObj._exist) {
        $psResource._exist = $inputObj._exist
    }

    return $psResource
}

# catch any un-caught exception and write it to the error stream
trap {
    Write-Trace -message "Exiting with error code 1 due to unhandled exception: $($_.Exception.Message)" -level debug
    exit [ExitCode]::Error
}

function GetPSResourceList {
    param(
        [PSCustomObject]$inputObj
    )

    $inputResources = @()
    $inputResources += if ($inputObj.resources) {
        $inputObj.resources | ForEach-Object {
            ConvertInputToPSResource -inputObj $_ -repositoryName $inputObj.repositoryName
        }
    }

    $repositoryState = Get-PSResourceRepository -Name $inputObj.repositoryName -ErrorAction SilentlyContinue

    if (-not $repositoryState) {
        Write-Trace -message "Repository not found: $($inputObj.repositoryName)" -level info
        $emptyResources = @()
        $emptyResources += $inputResources | ForEach-Object {
            [PSResource]::new($_.Name)
        }

        return [PSResourceList]::new($inputObj.repositoryName, $emptyResources, $false)
    }

    $inputPSResourceList = [PSResourceList]::new($inputObj.repositoryName, $inputResources, $repositoryState.Trusted)

    $allPSResources = @()

    if ($inputPSResourceList.repositoryName) {
        $currentUserPSResources = Get-PSResource -Scope CurrentUser -ErrorAction SilentlyContinue | Where-Object { $_.Repository -eq $inputPSResourceList.RepositoryName }
        $allUsersPSResources = Get-PSResource -Scope AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Repository -eq $inputPSResourceList.RepositoryName }
    }

    $allPSResources += $currentUserPSResources | ForEach-Object {
        [PSResource]::new(
            $_.Name,
            $_.Prerelease ? $_.Version.ToString() + "-" + $_.Prerelease : $_.Version.ToString(),
            [Scope]"CurrentUser",
            $_.Repository,
            $_.PreRelease
        )
    }

    $allPSResources += $allUsersPSResources | ForEach-Object {
        [PSResource]::new(
            $_.Name,
            $_.Prerelease ? $_.Version.ToString() + "-" + $_.Prerelease : $_.Version.ToString(),
            [Scope]"AllUsers",
            $_.Repository,
            $_.PreRelease ? $true : $false
        )
    }

    $resolvedResources = @()

    foreach ($inputResource in $inputResources) {
        $matchingResources = $allPSResources | Where-Object { $_.Name -eq $inputResource.Name }

        if ($matchingResources) {
            $preferred = $null
            if ($inputResource.Version) {
                $preferred = $matchingResources | Where-Object {
                    try { SatisfiesVersion -version $_.Version -versionRange $inputResource.Version } catch { $false }
                } | Select-Object -First 1
            }
            elseif (-not ($resolvedResources | Where-Object { $_.Name -eq $inputResource.Name })) {
                # No version constraint: any installed version means the resource exists.
                # Only record the first match so that one input resource maps to one current resource.
                Write-Trace -message "No version constraint for input: $($inputResource.Name). Treating installed version $($matchingResources[0].Version) as a match." -level debug
                $preferred = $matchingResources | Select-Object -First 1
            }

            if ($preferred) {
                Write-Trace -message "Resource '$($inputResource.Name)' version '$($preferred.Version)' satisfies requested range '$($inputResource.Version)'." -level debug
                $resolvedResources += $preferred
            }
            else {
                # Installed but doesn't satisfy the version range - report actual installed version with _exist = false
                $fallback = $matchingResources | Select-Object -First 1
                Write-Trace -message "Resource '$($inputResource.Name)' installed at '$($fallback.Version)' does not satisfy requested range '$($inputResource.Version)'. Reporting _exist = false." -level debug
                $fallback._exist = $false
                $resolvedResources += $fallback
            }
        }
        else {
            Write-Trace -message "Resource '$($inputResource.Name)' is not installed. Reporting _exist = false." -level debug
            $resolvedResources += [PSResource]::new($inputResource.Name)
        }
    }

    PopulatePSResourceListObjectByRepository -resourcesExist $resolvedResources -inputResources $inputResources -repositoryName $inputPSResourceList.RepositoryName -trustedRepository $inputPSResourceList.trustedRepository
}

function GetOperation {
    param(
        [string]$ResourceType
    )

    if ([string]::IsNullOrEmpty($stdinput)) {
        Write-Trace -level error -message "Get operation requires --input with the resource properties. No input was provided."
        exit [ExitCode]::Error
    }

    $inputObj = $stdinput | ConvertFrom-Json -ErrorAction Stop

    Write-Trace -message "Starting Get operation for ResourceType: $ResourceType" -level trace

    switch ($ResourceType) {
        'repository' {
            $inputRepository = [Repository]::new($inputObj)
            $rep = Get-PSResourceRepository -Name $inputRepository.Name -ErrorVariable err -ErrorAction SilentlyContinue
            Write-Trace -message "Get-PSResourceRepository returned: $($rep | ConvertTo-Json -Compress)" -level trace

            $ret = if ($err.FullyQualifiedErrorId -eq 'ErrorGettingSpecifiedRepo,Microsoft.PowerShell.PSResourceGet.Cmdlets.GetPSResourceRepository') {
                Write-Trace -message "Repository not found: $($inputRepository.Name). Returning _exist = false" -level debug
                [Repository]::new(
                    $InputRepository.Name,
                    $false
                )
            }
            else {
                [Repository]::new(
                    $rep.Name,
                    $rep.Uri,
                    $rep.Trusted,
                    $rep.Priority,
                    $rep.ApiVersion
                )

                Write-Trace -message "Returning repository object for: $($ret.Name)" -level trace
            }

            Write-Trace -message "Serialized JSON output for Get operation: $($ret.ToJson())" -level trace

            return ( $ret.ToJson() )
        }

        'repositorylist' {
            Write-Trace -level error -message "Get operation is not implemented for RepositoryList resource."
            exit [ExitCode]::ResourceNotImplemented
        }
        'psresource' {
            Write-Trace -level error -message "Get operation is not implemented for PSResource resource."
            exit [ExitCode]::ResourceNotImplemented
        }
        'psresourcelist' {
            (GetPSResourceList -inputObj $inputObj).ToJson()
        }
        default {
            Write-Trace -level error -message "Unknown ResourceType: $ResourceType"
            exit [ExitCode]::ResourceNotImplemented
        }
    }
}

function TestPSResourceList {
    param(
        [PSCustomObject]$inputObj
    )

    $inputResources = @()
    $inputResources += $inputObj.resources | ForEach-Object { ConvertInputToPSResource -inputObj $_ -repositoryName $inputObj.repositoryName }

    $repositoryState = Get-PSResourceRepository -Name $inputObj.repositoryName -ErrorAction SilentlyContinue

    if (-not $repositoryState) {
        Write-Trace -message "Repository not found: $($inputObj.repositoryName). Returning PSResourceList with _inDesiredState = false." -level debug
        $retValue = [PSResourceList]::new($inputObj.repositoryName, $inputResources, $false)
        $retValue._inDesiredState = $false
        $retValue.ToJsonForTest()
        '["repositoryName", "resources"]'
    }

    $inputPSResourceList = [PSResourceList]::new($inputObj.repositoryName, $inputResources, $repositoryState.Trusted)

    $currentState = GetPSResourceList -inputObj $inputObj
    $inDesiredState = $currentState.IsInDesiredState($inputPSResourceList)

    $currentState._inDesiredState = $inDesiredState

    if ($inDesiredState) {
        Write-Trace -message "PSResourceList is in desired state." -level debug
        $currentState.ToJsonForTest()
        ## Return empty array as we are in desired state and there are no differing properties
        '[]'
    }
    else {
        Write-Trace -message "PSResourceList is NOT in desired state." -level debug
        $inputPSResourceList.ToJsonForTest()
        '["resources"]'
    }
}

function TestOperation {
    param(
        [string]$ResourceType
    )

    $inputObj = $stdinput | ConvertFrom-Json -ErrorAction Stop

    switch ($ResourceType) {
        'repository' {
            Write-Trace -level error -message "Test operation is not implemented for Repository resource."
            exit [ExitCode]::TestNotImplemented
        }
        'repositorylist' {
            Write-Trace -level error -message "Test operation is not implemented for RepositoryList resource."
            exit [ExitCode]::TestNotImplemented
        }
        'psresource' {
            Write-Trace -level error -message "Test operation is not implemented for PSResource resource."
            exit [ExitCode]::TestNotImplemented
        }
        'psresourcelist' {
            TestPSResourceList -inputObj $inputObj
        }

        default {
            Write-Trace -level error -message "Unknown ResourceType: $ResourceType"
            exit [ExitCode]::UnknownResourceType
        }
    }
}

function ExportOperation {
    switch ($ResourceType) {
        'repository' {
            $rep = Get-PSResourceRepository -ErrorAction SilentlyContinue

            if (-not $rep) {
                Write-Trace -message "No repositories found. Returning empty array." -level debug
                return @()
            }

            $rep | ForEach-Object {
                [Repository]::new(
                    $_.Name,
                    $_.Uri,
                    $_.Trusted,
                    $_.Priority,
                    $_.ApiVersion
                ).ToJson()
            }
        }

        'repositorylist' {
            Write-Trace -level error -message "Export operation is not implemented for RepositoryList resource."
            exit [ExitCode]::ExportNotImplemented
        }
        'psresource' {
            Write-Trace -level error -message "Export operation is not implemented for PSResource resource."
            exit [ExitCode]::ExportNotImplemented
        }
        'psresourcelist' {
            $currentUserPSResources = Get-PSResource
            $allUsersPSResources = Get-PSResource -Scope AllUsers
            PopulatePSResourceListObject -allUsersPSResources $allUsersPSResources -currentUserPSResources $currentUserPSResources
        }
        default {
            Write-Trace -level error -message "Unknown ResourceType: $ResourceType"
            exit [ExitCode]::UnknownResourceType
        }
    }
}

function WhatIfPSResourceList {
    param(
        $inputObj
    )

    $repositoryName = $inputObj.repositoryName
    $currentState = GetPSResourceList -inputObj $inputObj
    $projectedResources = @()
    $inputObj.resources | ForEach-Object {
        $resourceDesiredState = ConvertInputToPSResource -inputObj $_ -repositoryName $repositoryName
        $name = $resourceDesiredState.name
        $version = $resourceDesiredState.version
        $scope = if ($resourceDesiredState.scope) { $resourceDesiredState.scope } else { [Scope]'CurrentUser' }
        $currentResource = $currentState.resources | Where-Object { $_.name -eq $name } | Select-Object -First 1

        if (-not $resourceDesiredState._exist -and $null -ne $currentResource -and $currentResource._exist) {
            $msg = "Would uninstall resource '$name'"
            Write-Trace -message "WhatIf: $msg." -level debug
            $resource = [PSResource]::new(
                $currentResource.name,
                $currentResource.version,
                $currentResource.scope,
                $currentResource.repositoryName,
                $currentResource.preRelease
            )
            $resource._exist = $false
            $resource._metadata = [pscustomobject]@{ whatIf = @($msg) }
            $projectedResources += $resource
        }
        elseif ($resourceDesiredState._exist -and ($null -eq $currentResource -or -not $currentResource._exist)) {
            $versionStr = if ($version) { $version } else { 'latest' }
            $msg = "Would install resource '$name' version '$versionStr'"
            Write-Trace -message "WhatIf: $msg." -level debug
            $resource = [PSResource]::new($name, $versionStr, [Scope]$scope, $repositoryName, $resourceDesiredState.preRelease)
            $resource._metadata = [pscustomobject]@{ whatIf = @($msg) }
            $projectedResources += $resource
        }
        else {
            Write-Trace -message "WhatIf: Resource '$name' is already in desired state." -level debug
            if ($null -ne $currentResource) {
                $projectedResources += $currentResource
            }
            else {
                $projectedResources += $resourceDesiredState
            }
        }
    }

    ## Report the same failures a real set operation would hit before installing anything
    $installRequired = @($projectedResources | Where-Object { $_._exist -and $null -ne $_._metadata }).Count -gt 0
    if ($installRequired) {
        $psRepository = Get-PSResourceRepository -Name $repositoryName -ErrorAction SilentlyContinue

        if (-not $psRepository) {
            Write-Trace -level error -message "Repository '$repositoryName' not found. Cannot install resources."
            exit [ExitCode]::RepositoryNotFound
        }

        if (-not $psRepository.Trusted -and -not $inputObj.trustedRepository) {
            Write-Trace -level error -message "Repository '$repositoryName' is not trusted. Cannot install resources."
            exit [ExitCode]::RepositoryNotTrusted
        }
    }

    $list = [PSResourceList]::new($repositoryName, $projectedResources, $currentState.trustedRepository)
    $list.ToJson()
}

function SetPSResourceList {
    param(
        $inputObj,
        [switch]$WhatIf
    )

    if ($WhatIf) {
        return WhatIfPSResourceList -inputObj $inputObj
    }

    $repositoryName = $inputObj.repositoryName
    $resourcesToUninstall = @()
    $resourcesToInstall = [System.Collections.Generic.Dictionary[string, psobject]]::new()

    $resourcesChanged = $false

    $currentState = GetPSResourceList -inputObj $inputObj

    $inputObj.resources | ForEach-Object {
        $resourceDesiredState = ConvertInputToPSResource -inputObj $_ -repositoryName $repositoryName
        $name = $resourceDesiredState.name
        $version = $resourceDesiredState.version
        $scope = if ($resourceDesiredState.scope) { $resourceDesiredState.scope } else { "CurrentUser" }

        # Resource should not exist - uninstall if it does
        $currentState.resources | ForEach-Object {

            $isInDesiredState = $_.IsInDesiredState($resourceDesiredState)

            # Uninstall if resource should not exist but does
            if (-not $resourceDesiredState._exist -and $_._exist) {
                Write-Trace -message "Resource $($resourceDesiredState.name) exists but _exist is false. Adding to uninstall list." -level debug
                $resourcesToUninstall += $_
            }
            # Install if resource should exist but doesn't, or exists but not in desired state
            elseif ($resourceDesiredState._exist -and (-not $_._exist -or -not $isInDesiredState)) {
                Write-Trace -message "Resource $($resourceDesiredState.name) needs to be installed." -level debug
                $versionStr = if ($version) { $resourceDesiredState.version } else { 'latest' }
                $key = $name.ToLowerInvariant() + '-' + $versionStr.ToLowerInvariant()
                if (-not $resourcesToInstall.ContainsKey($key)) {
                    $resourcesToInstall[$key] = $resourceDesiredState
                }
            }
            # Otherwise resource is in desired state, no action needed
            else {
                Write-Trace -message "Resource $($resourceDesiredState.name) is in desired state." -level debug
            }
        }
    }

    if ($resourcesToUninstall.Count -gt 0) {
        Write-Trace -message "Uninstalling resources: $($resourcesToUninstall | ForEach-Object { "$($_.Name) - $($_.Version)" })" -level debug
        $resourcesToUninstall | ForEach-Object {
            $cmdWarnings = $null
            Uninstall-PSResource -Name $_.Name -Scope $scope -ErrorAction Stop -WarningVariable cmdWarnings
            foreach ($w in $cmdWarnings) {
                Write-Trace -message ([string]$w) -level warn
            }
        }
        $resourcesChanged = $true
    }

    if ($resourcesToInstall.Count -gt 0) {
        $psRepository = Get-PSResourceRepository -Name $repositoryName -ErrorAction SilentlyContinue

        if (-not $psRepository) {
            Write-Trace -level error -message "Repository '$repositoryName' not found. Cannot install resources."
            exit [ExitCode]::RepositoryNotFound
        }

        if (-not $psRepository.Trusted -and -not $inputObj.trustedRepository) {
            Write-Trace -level error -message "Repository '$repositoryName' is not trusted. Cannot install resources."
            exit [ExitCode]::RepositoryNotTrusted
        }

        Write-Trace -message "Installing resources: $($resourcesToInstall.Values | ForEach-Object { " $($_.Name) -- $($_.Version) " })" -level debug
        $resourcesToInstall.Values | ForEach-Object {
            $usePrerelease = if ($_.preRelease) { $true } else { $false }

            $installErrors = @()

            $name = $_.Name
            $version = $_.Version

            try {
                $cmdWarnings = $null
                Install-PSResource -Name $_.Name -Version $_.Version -Scope $scope -Repository $repositoryName -ErrorAction Stop -TrustRepository:$inputObj.trustedRepository -Prerelease:$usePrerelease -Reinstall -WarningVariable cmdWarnings
                foreach ($w in $cmdWarnings) {
                    Write-Trace -message ([string]$w) -level warn
                }
            } catch {
                Write-Trace -level error -message "Failed to install resource '$name' with version '$version'. Error: $($_.Exception.Message)"
                $installErrors += $_.Exception.Message
            }

            if ($installErrors.Count -gt 0) {
                Write-Trace -level error -message "One or more errors occurred while installing resource '$name' with version '$version': $($installErrors -join '; ')"
                Write-Trace -level trace -message "Exiting with error code 4 due to installation failure."
                exit [ExitCode]::InstallationFailed
            }
        }

        $resourcesChanged = $true
    }

    (GetPSResourceList -inputObj $inputObj).ToJson()
    if ($resourcesChanged) {
        '["resources"]'
    }
    else {
        '[]'
    }
}

function SetOperation {
    param(
        [string]$ResourceType
    )

    $inputObj = $stdinput | ConvertFrom-Json -ErrorAction Stop

    switch ($ResourceType) {
        'repository' {
            $rep = Get-PSResourceRepository -Name $inputObj.Name -ErrorAction SilentlyContinue

            $properties = @('name', 'uri', 'trusted', 'priority', 'repositoryType')

            $splatt = @{}

            foreach ($property in $properties) {
                if ($null -ne $inputObj.PSObject.Properties[$property]) {
                    if ($property -eq 'repositoryType') {
                        $splatt['ApiVersion'] = $inputObj.$property
                    }
                    else {
                        $splatt[$property] = $inputObj.$property
                    }
                }
            }

            if ($null -eq $rep -and $inputObj._exist -ne $false) {
                Register-PSResourceRepository @splatt
            }
            else {
                if ($inputObj._exist -eq $false) {
                    Write-Trace -message "Repository $($inputObj.Name) exists and _exist is false. Deleting it." -level debug
                    Unregister-PSResourceRepository -Name $inputObj.Name
                }
                else {
                    Set-PSResourceRepository @splatt
                }
            }

            return GetOperation -ResourceType $ResourceType
        }

        'repositorylist' {
            Write-Trace -level error -message "Set operation is not implemented for RepositoryList resource."
            exit [ExitCode]::SetNotImplemented
        }
        'psresource' {
            Write-Trace -level error -message "Set operation is not implemented for PSResource resource."
            exit [ExitCode]::SetNotImplemented
        }
        'psresourcelist' { return SetPSResourceList -inputObj $inputObj -WhatIf:$WhatIf }
        default {
            Write-Trace -level error -message "Unknown ResourceType: $ResourceType"
            exit [ExitCode]::UnknownResourceType
        }
    }
}

function DeleteOperation {
    param(
        [string]$ResourceType
    )

    $inputObj = $stdinput | ConvertFrom-Json -ErrorAction Stop
    switch ($ResourceType) {
        'repository' {
            if ($inputObj._exist -ne $false) {
                throw "_exist property is not set to false for the repository. Cannot delete."
            }

            $rep = Get-PSResourceRepository -Name $inputObj.Name -ErrorAction SilentlyContinue

            if ($null -ne $rep) {
                Unregister-PSResourceRepository -Name $inputObj.Name
            }
            else {
                Write-Trace -message "Repository not found: $($inputObj.Name). Nothing to delete." -level debug
            }

            return GetOperation -ResourceType $ResourceType
        }
        'repositorylist' {
            Write-Trace -level error -message "Delete operation is not implemented for RepositoryList resource."
            exit [ExitCode]::DeleteNotImplemented
        }
        'psresource' {
            Write-Trace -level error -message "Delete operation is not implemented for PSResource resource."
            exit [ExitCode]::DeleteNotImplemented
        }
        'psresourcelist' {
            Write-Trace -level error -message "Delete operation is not implemented for PSResourceList resource."
            exit [ExitCode]::DeleteNotImplemented
        }
        default {
            Write-Trace -level error -message "Unknown ResourceType: $ResourceType"
            exit [ExitCode]::UnknownResourceType
        }
    }
}

function PopulatePSResourceListObjectByRepository {
    param (
        $resourcesExist,
        $inputResources,
        $repositoryName,
        $trustedRepository
    )

    $resources = @()

    if (-not $resourcesExist) {
        $resources = $inputResources | ForEach-Object {
            [PSResource]::new(
                $_.Name
            )
        }
    }
    else {
        $resources += $resourcesExist | ForEach-Object {
            $srcExist = $_._exist
            $r = if ($_.version) {
                [PSResource]::new(
                    $_.Name,
                    $_.Version.ToString(),
                    $_.Scope,
                    $_.RepositoryName,
                    $_.PreRelease ? $true : $false
                )
            } else {
                [PSResource]::new($_.Name)
            }
            $r._exist = $srcExist
            $r
        }
    }

    $psresourceListObj =
    [PSResourceList]::new(
        $repositoryName,
        $resources,
        $trustedRepository
    )

    return $psresourceListObj
}

function PopulatePSResourceListObject {
    param (
        $allUsersPSResources,
        $currentUserPSResources
    )

    $allPSResources = @()

    $allPSResources += $allUsersPSResources | ForEach-Object {
        return [PSResource]::new(
            $_.Name,
            $_.Version,
            [Scope]"AllUsers",
            $_.Repository,
            $_.PreRelease ? $true : $false
        )
    }

    $allPSResources += $currentUserPSResources | ForEach-Object {
        return [PSResource]::new(
            $_.Name,
            $_.Version,
            [Scope]"CurrentUser",
            $_.Repository,
            $_.PreRelease ? $true : $false
        )
    }

    $repoGrps = $allPSResources | Group-Object -Property repositoryName

    $repoGrps | ForEach-Object {
        $repositoryTrust = if ($_.Name) { (Get-PSResourceRepository -Name $_.Name -ErrorAction SilentlyContinue).Trusted } else { $false }
        $repoName = $_.Name
        $resources = $_.Group
        [PSResourceList]::new($repoName, $resources, $repositoryTrust).ToJson()
    }
}

## This is mostly needed for CI tests as the PSModulePath has a different version PSResourceGet
## If the module is loaded from a different path, then we get an error "Assembly with same name is already loaded"
if ($null -eq (Get-Module -Name Microsoft.PowerShell.PSResourceGet)) {
    $path = Join-Path -Path $PSScriptRoot -ChildPath "Microsoft.PowerShell.PSResourceGet.psd1"
    Write-Trace -level trace -message "Importing Microsoft.PowerShell.PSResourceGet module from path: $path"
    Import-Module -Name $path -Force -ErrorAction Stop
}

# Suppress warnings from PSResourceGet cmdlets to prevent them from reaching stdout and
# breaking DSC's JSON parsing. Warnings should be captured on individual cmdlets
$WarningPreference = 'SilentlyContinue'

switch ($Operation.ToLower()) {
    'get' { return (GetOperation -ResourceType $ResourceType) }
    'set' { return (SetOperation -ResourceType $ResourceType) }
    'test' { return (TestOperation -ResourceType $ResourceType) }
    'export' { return (ExportOperation -ResourceType $ResourceType) }
    'delete' { return (DeleteOperation -ResourceType $ResourceType) }
    default {
        Write-Trace -level error -message "Unknown Operation: $Operation"
        exit [ExitCode]::UnknownOperation
    }
}

# SIG # Begin signature block
# MIInKAYJKoZIhvcNAQcCoIInGTCCJxUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDtmX6pofbNRiNn
# hIbPhM7MJAxcS0SAfz0Q5EY34FcuCKCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# KoZIhvcNAQkEMSIEIO1Xft2IOfoKZzgDkhl5ppa0TDCYoERiUWtemTPoYlU2MEIG
# CisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAMpXtcqxBza11eZD3
# FsPkujgvu65ARx97Se4Wh/j5hc2WhsuuDIHoz+wMUIP2dgxMU7SEJB9MkUx15uDb
# VlQJrAOfonX1+MBVXhaP5BaqaIOvqWsZiij8jqWML71CdXUBjDakLRyhzT6L08tP
# D+BLSrQ5IpVkfTVvDPXHQbTRHJQhZRoIXqVr9HOvgdMwOgA994fSLGo0JdqTMwC3
# qTWEinD7/lYg+3+ke7k1j/lWSFHlVoCUOqVClScPonoWWYLusTKXQugk/EPFoHQy
# bWjQm8mW2JaM9m11xntgSHPmwf4hHBlXkWw8wU5mOP+qGcF4+rdLNPnZje6GthYC
# T5vkr6GCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCCF20w
# ghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9
# MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCChy+V/jB5gIItv
# IVDLN9/pQkkF01ZgMx4Z7ZCBDS/YawIGarf2Pl8PGBMyMDI2MTEwNTIyMTEyNS40
# NjRaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScw
# JQYDVQQLEx5uU2hpZWxkIFRTUyBFU046MzMwMy0wNUUwLUQ5NDcxJTAjBgNVBAMT
# HE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHqMIIHIDCCBQigAwIBAgIT
# MwAAAiEzwDX70g8hpAABAAACITANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNjAyMTkxOTM5NTRaFw0yNzA1MTcxOTM5NTRa
# MIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQL
# ExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxk
# IFRTUyBFU046MzMwMy0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDb
# cTACqU1YvRocyWL2PL9fyf/+ULs2qK7U1aZsRnDZSnlCr7K7jgA3eFCEJL5BZ7dU
# TC0DeZepf+ZC+7HEbB4IdzmJfQAUDFFerqY5VTHmQvP2XA3lWSFj740idcGUHglP
# 5H/PbCJU7GAHWP2HdcCjdx1lYAo0A+zLI7xwnTQeMyOXX212Eg4UmDPPJgxdTMw6
# WFVWsBPWRBi5gDixy2s+7R8ADk5lbBBFDB5h0CjrNWIN7uCAzF5g7trrL8nXIKp1
# 0mj9RxhcGQ+tlht6VIvdygRVTUGdzFB2/nBvJqQ9kxxFltQST70fEdx4TyaKow/f
# 5+BSh4z4/9f7NXIVVTLn/8kcJAfRqFmRrrFt3IKby7VrzmYuoQWD0lmNFtGQ57Br
# JkPrPFAPek1ALtcbb7FH3nQpvi8ngz/MFX/+cnmNFWFU29VVLmzB9XvLZxbYvkee
# tt0mh5lfteeN2rEwUyrdrKufz9h2S6pbate+C2h02CrXwSka0x6ezpTmGkIJLFt2
# 5ub/UYXNLdHdsxGD6EfckOIoJYsm4MS9F/vSqLNHK89I0vTLBngQEp6LIFkINanR
# T3PtNx3pNKRKJRALc6L6mhW4hL4aHL749qPfQ72t5qAMm5xiKYMgJ2WanidRLNuI
# 251JIN7raaeA/2vb0XFkZcIbTR1pfQGsco4U0g5tjwIDAQABo4IBSTCCAUUwHQYD
# VR0OBBYEFOYjIs5qa6pfuquPyyK1FTr5QDCnMB8GA1UdIwQYMBaAFJ+nFV0AXmJd
# g/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0El
# MjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGlt
# ZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0l
# AQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUA
# A4ICAQA4I/3bkdnTxD2rFum3MF8xVKdEkohAObbePrQ+0fr5bRimjz9sVkKT/7gc
# j4OMcClSYG+IdX6Mp3EYsLHWfjvwfzFoeZE+yTbdBj/1VHZQRuCmw6QqeVCTbw2n
# nS7nBxnWd9oZXbPUpqEawH5DqXQaWFgR9A4KWVK/IvXVDMj1PlPCES1P3JonNbdh
# kkkz49rJuKOm5b7e/BH8loqAmXOXRc22yxWVTMWrEp4pslmv8eT7VoY8X/jdKYTP
# VEXsfmLbVFcqzMuB8vFGfUyWsWROS8wgq7lQYfWcYqh7NymoATX+wWYK3zWG7aRc
# iPGUAzznXdf+aHtIWnQLNa5HFmSXkiak3fSuprWYZiHhuYjE16hroApcBHpm+8S/
# kNqhm9WjQX+2BxnYv+Jejy6lqTi8fLBLS069WXVw/ptf5IV+FtYl34GvVoeg31Uo
# UmVVZe1SDUJkm9dDXc8l/qBDYiAIT2CCsPTyt9XA9JVuHxdP63n7ChvWAO/47QRu
# CDsUlFJoWwyBwl7jeYpaRVMtQt0iuJMGGjgEaJX1Q/2j8sXURvTceLHDD9ipWt09
# 2ZDWMQciDRmhHNFOX1dnjBvk/k1UMcg997j5oYznAnSpJvlg/4BP3aVE0h/YH2Kg
# sKbU4NXZHAjJXj2Slqo1C115CG6qBZaFkM8W6vPZCm5qnSezOjCCB3EwggVZoAMC
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
# U1MgRVNOOjMzMDMtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1T
# dGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQALbEgZZnyYHXJ1DGb5fGjplXpt
# uaCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3
# DQEBCwUAAgUA7pcpIjAiGA8yMDI2MTEwNTE2MTExNFoYDzIwMjYxMTA2MTYxMTE0
# WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDulykiAgEAMAcCAQACAg+bMAcCAQAC
# AhPJMAoCBQDumHqiAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKg
# CjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAEOH2bB5
# N+kidNL4n5WQJAFw6NcEqV/RaQHVfj+UO3j8cdJyKZ9p3PPf8Fhl509Qypcip3Hw
# FEX37sXfYsw7ZsVk0/hySfY2f9QTVRtqjtaT8Dpbztk4OqQhzAOejNW0yw+4L7na
# icF7DW566R3gDXt+YjlXYCLgSZ5jSx6QiQLCrvyY4z4XQV7ZfntJTDUcOFBoAwXC
# ywE+Jf666M/id8SVrPPEHNwGi11blUcvOONT4sPOxoIzbE5A7TdY9e7UKnB+Nrha
# FfgiasdBcYIN6SvIpuGFHXoKsS2SnPUiTba109o2HFuk5jozAdeBZlsyIBsTUj76
# C17Cg3H8SZfezIoxggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMAITMwAAAiEzwDX70g8hpAABAAACITANBglghkgBZQMEAgEFAKCCAUow
# GgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCDGV7LF
# fUB61KOPpvlUVnDtSPCncxfBsIw2DizojUXvwzCB+gYLKoZIhvcNAQkQAi8xgeow
# gecwgeQwgb0EIADvIQefFVUa4BJy8IZywMAvmGSKdUVqEmy9A++PCj1EMIGYMIGA
# pH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIhM8A1+9IPIaQA
# AQAAAiEwIgQgyf65E7h55v+4qdK9vSOo0+vhTOCtHdWuiWKZIoc59SwwDQYJKoZI
# hvcNAQELBQAEggIAajJhp11x4OKsjNETlomx139cJhx3Sxr0lsMbrNM0+1isqkHJ
# 51NNVF7THqQhV/XKKNomKh6wgK/GCbY9kS3raoWmSACpD1BplRNIMEad+umzDnDC
# OLTK4Bc5cNZ96/YPf/V8KNsXzaT9tT4qBYotRgjTuFDa0k+TLMGOlPWTj1s61jJ5
# /LZCoxAnTDuPaT83cV8IMgB1d3G2LtGzvlbhzUwAv9fMHdB2Uf4ibEIDpqkKBHBq
# OxOz0YrwW44ax6lZwEtF+HNDIaqWO3GTLedLtiMwUhxSnNc+5aXb7V9VErhp76GB
# A3mgXgZIIWTIW/bd6C3xLlZ1k5/HYtix0SeGIEP+YyRSfOHILhdtFgyLqWkfrs56
# r1dBTCNxeSsQ5hqEO0Zpcb/umpHfefT7cHjVBe+5pSMKVBhb1TU/oyXnQ5xsFiZu
# JTgdNF7uRcq0gmxFnrGwOZt8KZxUIJ49GdNkUYZlFsQJyJ2lTdoQ36Dcxno5ZvY8
# UCkNrv68kFz8F3TpEkvokl97J2HNasmkvMlvny95DUWs5pCfCdAwy1n8318SGoXr
# bmG1PxOvcPfJCcc4KYZ7SPDD6ZJJMUWbeOxJvp598zgPwJztCufBbeFdZWNUJDU1
# m8W3pYiwSbJe1krpPxwqKbJpcdmN24XxgSa4jbqOU92WNYqioGS6yD8Gy60=
# SIG # End signature block
