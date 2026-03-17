# ProfileHelpers module
# This module contains the custom functions and aliases that were previously defined directly
# in Microsoft.PowerShell_profile.ps1.

# ============================================================
# FUNCTION: EmptyRecycleBin
# ============================================================
function EmptyRecycleBin {
	[CmdletBinding()]
	param(
		[switch]$WhatIf
	)

	# Try the supported cmdlet first
	if (Get-Command -Name Clear-RecycleBin -ErrorAction SilentlyContinue) {
		if ($WhatIf) {
			Write-Host "Preview: Clear-RecycleBin -Confirm:`$false -WhatIf" -ForegroundColor Cyan
			Clear-RecycleBin -Confirm:$false -WhatIf
		}
		else {
			Write-Host "Running Clear-RecycleBin for current user..." -ForegroundColor Cyan
			Clear-RecycleBin -Confirm:$false -Force
		}
	}
	else {
		Write-Host "Clear-RecycleBin not available in this session; skipping to force removal." -ForegroundColor Yellow
	}

	# If user asked for force removal or if items remain, enumerate drives and remove $Recycle.Bin contents
	Write-Host "Enumerating drives for `$Recycle.Bin folders..." -ForegroundColor Yellow
	$drives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root

	foreach ($root in $drives) {
		$rbPath = Join-Path -Path $root -ChildPath '$Recycle.Bin'
		if (Test-Path $rbPath) {
			Write-Host "Found: $rbPath" -ForegroundColor Green
			if ($WhatIf) {
				Get-ChildItem -Path $rbPath -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -WhatIf
			}
			else {
				try {
					# Attempt to take ownership and grant Administrators full control (may require elevation)
					takeown.exe /f $rbPath /r /d y | Out-Null
					icacls.exe $rbPath /grant Administrators:F /t | Out-Null
				}
				catch {
					# ignore ownership errors and continue
				}
				Get-ChildItem -Path $rbPath -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
			}
		}
	}

	Write-Host "Done. If some items remain, try running PowerShell as Administrator and re-run this command." -ForegroundColor Cyan
}

# ============================================================
# FUNCTION: OneDriveSecurityPermissionDeniedFix
# ============================================================
function OneDriveSecurityPermissionDeniedFix {
	<#
    .SYNOPSIS
    Removes "Deny - Delete subfolders and files" ACL entries for Everyone
    under specified OneDrive folders.

    .DESCRIPTION
    Iterates a list of folder paths, reports any Deny-Delete rules found,
    attempts to remove them, re-enables inheritance, and verifies success.
    #>

	[CmdletBinding()]
	param(
		[string[]]$Folders = @(
			"E:\OD\Cejesti",
			"E:\OD\Cejesti\OneDrive",
			"E:\OD\Erelyn",
			"E:\OD\Erelyn\OneDrive",
			"E:\OD\Jessica",
			"E:\OD\Jessica\OneDrive",
			"E:\OD\Lycia",
			"E:\OD\Lycia\OneDrive",
			"E:\OD\Rose",
			"E:\OD\Rose\OneDrive"
		)
	)

	foreach ($path in $Folders) {
		Write-Host "Processing folder: $path"

		if (-not (Test-Path $path)) {
			Write-Warning "  -> Path not found. Skipping."
			continue
		}

		$acl = Get-Acl -Path $path
		$denyRules = $acl.Access | Where-Object {
			$_.IdentityReference -eq 'Everyone' -and
			$_.FileSystemRights -match 'DeleteSubdirectoriesAndFiles' -and
			$_.AccessControlType -eq 'Deny'
		}

		if ($denyRules.Count -eq 0) {
			Write-Host "  -> No Deny-Delete rules found."
		}
		else {
			Write-Host "  -> Found $($denyRules.Count) Deny-Delete rule(s). Attempting removal..."

			foreach ($rule in $denyRules) {
				$acl.RemoveAccessRule($rule)
			}

			# Preserve inherited rules and remove explicit protection
			$acl.SetAccessRuleProtection($false, $true)

			try {
				Set-Acl -Path $path -AclObject $acl

				# Verify
				$newAcl = Get-Acl -Path $path
				$stillDenied = $newAcl.Access | Where-Object {
					$_.IdentityReference -eq 'Everyone' -and
					$_.FileSystemRights -match 'DeleteSubdirectoriesAndFiles' -and
					$_.AccessControlType -eq 'Deny'
				}

				if ($stillDenied.Count -eq 0) {
					Write-Host "  -> Successfully removed all Deny-Delete rules." -ForegroundColor Green
				}
				else {
					Write-Warning "  -> Removal attempted, but $($stillDenied.Count) rule(s) still present."
				}
			}
			catch {
				Write-Error "  -> Error applying ACL: $_"
			}
		}

		Write-Host ""  # Blank line for readability
	}
}

# ============================================================
# FUNCTION: OneDriveSize
# ============================================================
# Get OneDrive Total File Size
function OneDriveSize {
	[CmdletBinding()]
	param(
		[string]$OneDrivePath = "e:\od"
	)

	if (-not (Test-Path $OneDrivePath)) {
		Write-Error "Cache path '$OneDrivePath' does not exist."
		return
	}

	# ! Begin OneDrive File Size Check.

	# Sum all file lengths under the cache directory
	$totalBytes = Get-ChildItem -Path $OneDrivePath -Recurse -Force |
	Where-Object { -not $_.PSIsContainer } |
	Measure-Object -Property Length -Sum |
	Select-Object -ExpandProperty Sum

	if ($null -eq $totalBytes) {
		Write-Output "No files found under '$OneDrivePath'."
		return
	}

	# Convert to human-readable units
	$sizeGB = [math]::Round($totalBytes / 1GB, 2)
	$sizeMB = [math]::Round($totalBytes / 1MB, 2)

	[PSCustomObject]@{
		OneDrivePath = $OneDrivePath
		Bytes        = $totalBytes
		MB           = "$sizeMB MB"
		GB           = "$sizeGB GB"
	}
}

# ============================================================
# FUNCTION: GoogleDriveSize
# ============================================================
# Get Google Drive Total File Size
function GoogleDriveSize {
	[CmdletBinding()]
	param(
		[string]$GoogleDrivePath = "F:\Google Drive",
		[string]$GDriveTempFolderPath = "D:\Temp\GoogleDriveFS",
		[string]$GoogleDriveStreamingCachePath = "D:\Google Drive Streaming Cache\DriveFS"
	)
	
	# ! Begin Google Drive File Size Check.
	if (-not (Test-Path $GoogleDrivePath)) {
		Write-Error "Cache path '$GoogleDrivePath' does not exist."
		return
	}

	# Sum all file lengths under the cache directory
	$totalBytes = Get-ChildItem -Path $GoogleDrivePath -Recurse -Force |
	Where-Object { -not $_.PSIsContainer } |
	Measure-Object -Property Length -Sum |
	Select-Object -ExpandProperty Sum

	if ($null -eq $totalBytes) {
		Write-Output "No files found under '$GoogleDrivePath'."
		return
	}

	# Convert to human-readable units
	$sizeGB = [math]::Round($totalBytes / 1GB, 2)
	$sizeMB = [math]::Round($totalBytes / 1MB, 2)

	[PSCustomObject]@{
		GoogleDrivePath = $GoogleDrivePath
		Bytes           = $totalBytes
		MB              = "$sizeMB MB"
		GB              = "$sizeGB GB"
	}

	if (-not (Test-Path $GDriveTempFolderPath)) {
		Write-Error "Cache path '$GDriveTempFolderPath' does not exist."
		return
	}
	
	# ! Begin Google Drive Temporary File Size Check.
	# Sum all file lengths under the GoogleDriveTemporaryFilesPath directory
	$totalBytes = Get-ChildItem -Path $GDriveTempFolderPath -Recurse -Force |
	Where-Object { -not $_.PSIsContainer } |
	Measure-Object -Property Length -Sum |
	Select-Object -ExpandProperty Sum

	if ($null -eq $totalBytes) {
		Write-Output "No files found under '$GDriveTempFolderPath'."
		return
	}

	# Convert to human-readable units
	$sizeGB = [math]::Round($totalBytes / 1GB, 2)
	$sizeMB = [math]::Round($totalBytes / 1MB, 2)

	[PSCustomObject]@{
		GoogleDriveTempFolderPath = $GDriveTempFolderPath
		Bytes                     = $totalBytes
		MB                        = "$sizeMB MB"
		GB                        = "$sizeGB GB"
	}
	
	# ! Begin Google Drive Streaming Cache File Size Check.
	
	if (-not (Test-Path $GoogleDriveStreamingCachePath)) {
		Write-Error "Cache path '$GoogleDriveStreamingCachePath' does not exist."
		return
	}

	# Sum all file lengths under the cache directory
	$totalBytes = Get-ChildItem -Path $GoogleDriveStreamingCachePath -Recurse -Force |
	Where-Object { -not $_.PSIsContainer } |
	Measure-Object -Property Length -Sum |
	Select-Object -ExpandProperty Sum

	if ($null -eq $totalBytes) {
		Write-Output "No files found under '$GoogleDriveStreamingCachePath'."
		return
	}

	# Convert to human-readable units
	$sizeGB = [math]::Round($totalBytes / 1GB, 2)
	$sizeMB = [math]::Round($totalBytes / 1MB, 2)

	[PSCustomObject]@{
		GoogleDriveCachePath = $GoogleDriveStreamingCachePath
		Bytes                = $totalBytes
		MB                   = "$sizeMB MB"
		GB                   = "$sizeGB GB"
	}
}

# ============================================================
# FUNCTION: SymbolicLinks
# ============================================================
function SymbolicLinks {
	[CmdletBinding()]
	param(
		[string]$Path = '.',
		[switch]$Symbolic,
		[switch]$Directory
	)

	$gciParams = @{
		Path        = $Path
		Recurse     = $true
		Force       = $true
		Attributes  = 'ReparsePoint'
		ErrorAction = 'SilentlyContinue'
	}

	# Only add FollowSymlink parameter in PowerShell 7+
	if ($PSVersionTable.PSVersion.Major -ge 7) {
		$gciParams['FollowSymlink'] = $false
	}

	$items = Get-ChildItem @gciParams

	if ($Symbolic) {
		$items = $items | Where-Object { $_.LinkType -eq 'SymbolicLink' }
	}
	else {
		if ($Directory) {
			$items = $items | Where-Object { $_.LinkType -eq 'Directory' }
		}
		else {
			$items = $items | Where-Object { $_.LinkType -in 'SymbolicLink', 'Directory' }
		}
	}

	$items | Select-Object FullName, LinkType, Target
}

# Returns the current PowerShell version.
function PowerShellVersion {
	$version = $PSVersionTable.PSVersion
	Write-Host "PowerShell Version: $($version.Major).$($version.Minor).$($version.Build)" -ForegroundColor Blue
}

function PowerShellProfileFunctions {
	$moduleName = $MyInvocation.MyCommand.Module.Name

	Write-Host "Custom Functions Defined in module '$moduleName':" -ForegroundColor DarkBlue
	Get-Command -CommandType Function -Module $moduleName | ForEach-Object { Write-Host "  $($_.Name)" -ForegroundColor Green }
}

function PowerShellProfileAliases {
	$moduleName = $MyInvocation.MyCommand.Module.Name

	Write-Host "`nCustom Aliases Defined in module '$moduleName':" -ForegroundColor Magenta
	Get-Command -CommandType Alias -Module $moduleName | ForEach-Object { Write-Host "  $($_.Name) -> $($_.Definition)" -ForegroundColor DarkBlue }
}

# ============================================================
# Aliases (exported so that Get-Alias shows this module as the source)
Set-Alias -Name Aliases -Value PowerShellProfileAliases
Set-Alias -Name Functions -Value PowerShellProfileFunctions
Set-Alias -Name GDriveSize -Value GoogleDriveSize
Set-Alias -Name Junctions -Value SymbolicLinks
Set-Alias -Name OneDriveSecurity -Value OneDriveSecurityPermissionDeniedFix
Set-Alias -Name Version -Value PowerShellVersion
Set-Alias -Name About -Value PowerShellVersion

# Export members (functions + aliases)
$functions = 'EmptyRecycleBin', 'OneDriveSecurityPermissionDeniedFix', 'SymbolicLinks', 'PowerShellProfileFunctions', 'PowerShellProfileAliases', 'OneDriveSize', 'GoogleDriveSize', 'PowerShellVersion'
$aliases = 'OneDriveSecurity', 'OneDriveFixDeniedPermissions', 'SymbolicLinks', 'Junctions', 'GDriveSize', 'Version', 'About', 'Aliases', 'Functions'
Export-ModuleMember -Function $functions -Alias $aliases