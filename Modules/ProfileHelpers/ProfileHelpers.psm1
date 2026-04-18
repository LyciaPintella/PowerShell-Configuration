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
# FUNCTION: OneDriveSecurity
# ============================================================
function OneDriveSecurity {
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
			"C:\OD\Cejesti",
			"C:\OD\Cejesti\OneDrive",
			"C:\OD\Erelyn",
			"C:\OD\Erelyn\OneDrive",
			"C:\OD\Jessica",
			"C:\OD\Jessica\OneDrive",
			"C:\OD\Lycia",
			"C:\OD\Lycia\OneDrive",
			"C:\OD\Rose",
			"C:\OD\Rose\OneDrive"
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
		[string]$OneDrivePath = "C:\OD",
		[string]$OneDriveTempPath = "C:\OneDriveTemp"
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
	$OneDriveSizeGB = [math]::Round($totalBytes / 1GB, 2)
	$OneDriveSizeMB = [math]::Round($totalBytes / 1MB, 2)
	
	# Sum all file lengths under the cache directory
	$totalBytes = Get-ChildItem -Path $OneDrivePath -Recurse -Force |
	Where-Object { -not $_.PSIsContainer } |
	Measure-Object -Property Length -Sum |
	Select-Object -ExpandProperty Sum

	if ($null -eq $totalBytes) {
		Write-Output "No files found under '$OneDrivePath'."
		return
	}
	
	# ! Begin OneDrive Temporary File Size Check.
	# Convert to human-readable units
	$OneDriveTempSizeGB = [math]::Round($totalBytes / 1GB, 2)
	$OneDriveTempSizeMB = [math]::Round($totalBytes / 1MB, 2)

	[PSCustomObject]@{
		OneDrivePath       = $OneDrivePath
		OneDriveSizeMB     = "$OneDriveSizeMB MB"
		OneDriveSizeGB     = "$OneDriveSizeGB GB"
		OneDriveTempPath   = $OneDriveTempPath
		OneDriveTempSizeMB = "$OneDriveTempSizeMB MB"
		OneDriveTempSizeGB = "$OneDriveTempSizeGB GB"
	}
}


# ============================================================
# FUNCTION: GoogleDriveSize
# ============================================================
# Get Google Drive Total File Size
function GoogleDriveSize {
	[CmdletBinding()]
	param(
		[string]$GoogleDrivePath = "E:\Google Drive",
		[string]$GDriveTempFolderPath = "C:\Users\Jessica Murphy\AppData\Local\Google\DriveFS",
		[string]$GoogleDriveStreamingPath = "E:\Google Drive\Streaming"
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
	$GoogleDriveSizeGB = [math]::Round($totalBytes / 1GB, 2)
	$GoogleDriveSizeMB = [math]::Round($totalBytes / 1MB, 2)
	
	# ! Begin Google Drive Temporary File Size Check.
	
	if (-not (Test-Path $GDriveTempFolderPath)) {
		Write-Error "Cache path '$GDriveTempFolderPath' does not exist."
		return
	}
	
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
	$GoogleDriveTempSizeGB = [math]::Round($totalBytes / 1GB, 2)
	$GoogleDriveTempSizeMB = [math]::Round($totalBytes / 1MB, 2)
	
	# ! Begin Google Drive Streaming Cache File Size Check.
	
	if (-not (Test-Path $GoogleDriveStreamingPath)) {
		Write-Error "Cache path '$GoogleDriveStreamingPath' does not exist."
		return
	}

	# Sum all file lengths under the cache directory
	$totalBytes = Get-ChildItem -Path $GoogleDriveStreamingPath -Recurse -Force |
	Where-Object { -not $_.PSIsContainer } |
	Measure-Object -Property Length -Sum |
	Select-Object -ExpandProperty Sum

	if ($null -eq $totalBytes) {
		Write-Output "No files found under '$GoogleDriveStreamingPath'."
		return
	}

	# Convert to human-readable units
	$GoogleDriveStreamingSizeGB = [math]::Round($totalBytes / 1GB, 2)
	$GoogleDriveStreamingSizeMB = [math]::Round($totalBytes / 1MB, 2)

	[PSCustomObject]@{
		GoogleDrivePath          = $GoogleDrivePath
		GoogleDriveMB            = "$GoogleDriveSizeMB MB"
		GoogleDriveGB            = "$GoogleDriveSizeGB GB"
		GoogleDriveTempPath      = $GDriveTempFolderPath
		GoogleDriveTempMB        = "$GoogleDriveTempSizeMB MB"
		GoogleDriveTempGB        = "$GoogleDriveTempSizeGB GB"
		GoogleDriveStreamingPath = $GoogleDriveStreamingPath
		GoogleDriveStreamingMB   = "$GoogleDriveStreamingSizeMB MB"
		GoogleDriveStreamingGB   = "$GoogleDriveStreamingSizeGB GB"
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
	Write-Host "PowerShell Version: $($version.Major).$($version.Minor).$($version.Build)" -ForegroundColor Magenta
}

function Functions {
	$moduleName = $MyInvocation.MyCommand.Module.Name

	Write-Host "Custom Functions Defined in module '$moduleName':" -ForegroundColor Magenta
	Get-Command -CommandType Function -Module $moduleName | ForEach-Object { Write-Host "  $($_.Name)" -ForegroundColor Green }
}

function Aliases {
	$moduleName = $MyInvocation.MyCommand.Module.Name

	Write-Host "`nCustom Aliases Defined in module '$moduleName':" -ForegroundColor Magenta
	Get-Command -CommandType Alias -Module $moduleName | ForEach-Object { Write-Host "  $($_.Name) -> $($_.Definition)" -ForegroundColor Green }
}

# Remove all attributes from a file or folder
function RemoveAllAttributes {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Path
	)

	try {
		if (-not (Test-Path -LiteralPath $Path)) {
			throw "The specified path does not exist: $Path"
		}

		# Get the file or folder object
		$item = Get-ChildItem -LiteralPath $Path -Recurse -Force

		# Clear all attributes (set to 'Normal')
		foreach ($attr in $item.Attributes) {
			if ($attr -ne [System.IO.FileAttributes]::Normal) {
				$item.Attributes = $item.Attributes -bor $attr
			}
		}

		Write-Host "All attributes removed from: $Path" -ForegroundColor Blue
	}
	catch {
		Write-Host "Error: $_" -ForegroundColor Red
	}
}

function InstallDrivers {
	Set-Location "C:\OD\Jessica\OneDrive\Documents\PowerShell Scripts\Windows Troubleshooting"
	./Windows-Driver-Installation.ps1
}

function SetEfficiencyModeSystemwide {
	Set-Location "C:\OD\Jessica\OneDrive\Documents\PowerShell Scripts\Windows Troubleshooting"
	./"Set-Efficiency-Mode-Systemwide.ps1" *> "Set-Efficiency-Mode-Systemwide-log.txt"
	notepad "Set-Efficiency-Mode-Systemwide-log.txt"
}

function Windows.Old {
	$Path = "C:\Windows.old"
	
	# ! Start by creating an empty directory and using robocopy to mirror it to C:\Windows.old, which will effectively remove all files while preserving the folder structure and avoiding issues with locked files. Then we can remove the empty Windows.old folder.
	mkdir C:\Empty
	robocopy C:\Empty C:\Windows.old /MIR /R:1 /W:1
	Remove-Item C:\Windows.old
	
	# ! If the above method fails due to locked files, we can attempt to take ownership and grant full control to Administrators, then remove read-only, system, and hidden attributes before deleting the folder.
	if (Test-Path $Path) {
		Write-Host "Taking ownership of $Path ..." -ForegroundColor Cyan
		takeown /F $Path /A /R /D Y | Out-Null

		Write-Host "Granting Administrators full control ..." -ForegroundColor Cyan
		icacls $Path /grant Administrators:F /T /C | Out-Null

		Write-Host "Removing attributes (read-only, system, hidden) ..." -ForegroundColor Cyan
		Get-ChildItem -Path $Path -Recurse -Force | ForEach-Object {
			try {
				attrib -R -S -H $_.FullName
			}
			catch {}
		}
		
		Write-Host "Deleting folder..." -ForegroundColor Yellow
		Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
	
		if (-not (Test-Path $Path)) {
			Write-Host "Windows.old successfully deleted." -ForegroundColor Green
		}
		else {
			# ! Repeat the Robocopy process to preserve our progress.
			mkdir C:\Empty
			robocopy C:\Empty C:\Windows.old /MIR /R:1 /W:1
			Remove-Item C:\Windows.old
			Write-Host "Some files could not be deleted. A reboot may be required." -ForegroundColor Red
		}
	}
	else {
			Write-Host "C:\Windows.old does not exist." -ForegroundColor DarkYellow
		}	
}

function RepairRecycleBin {
	# Repair Recycle Bin on all drives
	# Run in an elevated PowerShell window
	
	$drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -gt 0 }
	
	foreach ($drive in $drives) {
		$path = Join-Path $drive.Root '$Recycle.Bin'
	
		if (Test-Path $path) {
			Write-Host "Repairing Recycle Bin on $($drive.Root) ..." -ForegroundColor Cyan
			try {
				Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
				Write-Host "✔ Recycle Bin repaired on $($drive.Root)" -ForegroundColor Green
			}
			catch {
				Write-Host "✖ Failed on $($drive.Root): $($_.Exception.Message)" -ForegroundColor Red
			}
		}
		else {
			Write-Host "No Recycle Bin found on $($drive.Root), skipping." -ForegroundColor Yellow
		}
	}
}

function ReloadProfile {
	Clear-Host
	. $profile
}

# ============================================================
# Aliases (exported so that Get-Alias shows this module as the source)
Set-Alias -Name Junctions -Value SymbolicLinks
Set-Alias -Name SymLinks -Value SymbolicLinks
Set-Alias -Name Version -Value PowerShellVersion
Set-Alias -Name About -Value PowerShellVersion
Set-Alias -Name SecurityReset -Value RemoveAllAttributes
Set-Alias -Name Reload -Value ReloadProfile

# Export members (functions + aliases)
$functions = 'EmptyRecycleBin', 'OneDriveSecurity', 'SymbolicLinks', 'Functions', 'Aliases', 'OneDriveSize', 'GoogleDriveSize', 'PowerShellVersion', 'RemoveAllAttributes', 'InstallDrivers', 'SetEfficiencyModeSystemwide', 'ReloadProfile', 'Windows.Old', 'RepairRecycleBin'
$aliases = 'OneDriveFixDeniedPermissions', 'SymbolicLinks', 'Junctions', 'Version', 'About', 'SecurityReset', 'SymLinks', 'Reload'
Export-ModuleMember -Function $functions -Alias $aliases