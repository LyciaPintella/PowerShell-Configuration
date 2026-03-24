function Get-GDriveCacheSize {
	[CmdletBinding()]
	param(
		[string]
		$CachePath = "D:\Google Drive Streaming Cache\DriveFS"
	)

	if (-not (Test-Path $CachePath)) {
		Write-Error "Cache path '$CachePath' does not exist."
		return
	}

	# Sum all file lengths under the cache directory
	$totalBytes = Get-ChildItem -Path $CachePath -Recurse -Force `
	| Where-Object { -not $_.PSIsContainer } `
	| Measure-Object -Property Length -Sum `
	| Select-Object -ExpandProperty Sum

	if ($null -eq $totalBytes) {
		Write-Output "No files found under '$CachePath'."
		return
	}

	# Convert to human-readable units
	$sizeGB = [math]::Round($totalBytes / 1GB, 2)
	$sizeMB = [math]::Round($totalBytes / 1MB, 2)

	[PSCustomObject]@{
		CachePath = $CachePath
		Bytes     = $totalBytes
		MB        = "$sizeMB MB"
		GB        = "$sizeGB GB"
	}
}
Set-Alias gdcache Get-GDriveCacheSize


<# Remove DENY DELETE permissions from the selected folders #>

function Remove-OD-Denies {
	<#
    .SYNOPSIS
    Removes “Deny – Delete subfolders and files” ACL entries for Everyone
    under specified OneDrive folders.

    .DESCRIPTION
    Iterates a list of folder paths, reports any Deny-Delete rules found,
    attempts to remove them, re-enables inheritance, and verifies success.

    .PARAMETER Folders
    Array of folder paths to inspect and clean. Defaults to your common
    OneDrive locations.

    .EXAMPLE
    Remove-OneDriveDeny
    Runs against the hard-coded default OneDrive paths.

    .EXAMPLE
    Remove-OneDriveDeny -Folders 'E:\OD\Foo','E:\OD\Bar\OneDrive'
    Runs against the two specified paths.
    #>

	[CmdletBinding()]
	param(
		[string[]]$Folders = @(
			"E:\OD\Cejesti",
			"E:\OD\Cejesti\OneDrive",
			"E:\OD\Erelyn",
			"E:\OD\Erelyn\OneDrive"
		)
	)

	foreach ($path in $Folders) {
		Write-Host "Processing folder: $path"

		if (-not (Test-Path $path)) {
			Write-Warning "  → Path not found. Skipping."
			continue
		}

		$acl = Get-Acl -Path $path
		$denyRules = $acl.Access |
		Where-Object {
			$_.IdentityReference -eq 'Everyone' -and
			$_.FileSystemRights -match 'DeleteSubdirectoriesAndFiles' -and
			$_.AccessControlType -eq 'Deny'
		}

		if ($denyRules.Count -eq 0) {
			Write-Host "  → No Deny-Delete rules found."
		}
		else {
			Write-Host "  → Found $($denyRules.Count) Deny-Delete rule(s). Attempting removal..."

			foreach ($rule in $denyRules) {
				$acl.RemoveAccessRule($rule)
			}

			# Preserve inherited rules and remove explicit protection
			$acl.SetAccessRuleProtection($false, $true)

			try {
				Set-Acl -Path $path -AclObject $acl

				# Verify
				$newAcl = Get-Acl -Path $path
				$stillDenied = $newAcl.Access |
				Where-Object {
					$_.IdentityReference -eq 'Everyone' -and
					$_.FileSystemRights -match 'DeleteSubdirectoriesAndFiles' -and
					$_.AccessControlType -eq 'Deny'
				}

				if ($stillDenied.Count -eq 0) {
					Write-Host "  → ✔ Successfully removed all Deny-Delete rules."
				}
				else {
					Write-Warning "  → ✖ Removal attempted, but $($stillDenied.Count) rule(s) still present."
				}
			}
			catch {
				Write-Error "  → Error applying ACL: $_"
			}
		}

		Write-Host ""  # Blank line for readability
	}
}

<# Recursively Find Symbolic Links Under The Current Directory.
			Run as:
		     Get-Symlinks
	     Get-Symlinks -OnlySymbolic #>

function Get-Symlinks {
	[CmdletBinding()]
	param(
		[string]$Path = '.',
		[switch]$OnlySymbolic
	)
	$gciParams = @{
		Path        = $Path
		Recurse     = $true
		Force       = $true
		Attributes  = 'ReparsePoint'
		ErrorAction = 'SilentlyContinue'
	}
	if ($PSVersionTable.PSVersion.Major -ge 7) {
		$gciParams['FollowSymlink'] = $false
	}

	$items = Get-ChildItem @gciParams

	if ($OnlySymbolic) {
		$items = $items | Where-Object LinkType -eq 'SymbolicLink'
	}

	$items | Select-Object FullName, LinkType, Target
}