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
	."C:\OD\Jessica\OneDrive\Documents\PowerShell Scripts\Windows Troubleshooting\Windows-Driver-Installation.ps1"
}

function SetEfficiencyModeSystemwide {
	."C:\OD\Jessica\OneDrive\Documents\PowerShell Scripts\Windows Troubleshooting\Set-Efficiency-Mode-Systemwide.ps1" *> "C:\OD\Jessica\OneDrive\Documents\PowerShell Scripts\Windows Troubleshooting\Set-Efficiency-Mode-Systemwide-log.txt"
	notepad "C:\OD\Jessica\OneDrive\Documents\PowerShell Scripts\Windows Troubleshooting\Set-Efficiency-Mode-Systemwide-log.txt"
}

function BadAccounts {
	."C:\OD\Jessica\OneDrive\Documents\PowerShell Scripts\Windows Troubleshooting\DeleteUserAccountFiles.ps1"
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

function WingetInstallBatch {
	."C:\OD\Jessica\OneDrive\Documents\PowerShell Scripts\App Installer Scripts\Winget-Install-Batch.ps1"
}

function GetOllamaAIModels {
	ollama pull deepseek-coder:6.7b
	ollama pull llama2-uncensored:7b
	ollama pull qwen3:8b # Qwen 3 8B (Reasoning model)
	ollama pull llama3.1:8b
	ollama pull mistral
	ollama pull gemma2
	ollama pull llava
	ollama pull codellama:7b
	ollama pull openthinker:7b
	ollama pull qwen2.5-coder:7b
	ollama pull codellama:7b
	ollama pull starcoder2:7b
	ollama pull dolphin3:8b
	ollama pull qwen2.5:7b
	ollama pull codegemma:7b
	ollama pull codellama:7b
	ollama pull mistral:7b
	ollama pull llama3.1:8b
	#Supports image input
	ollama pull llava:7b
}

function FormatUSBOSInstallers1 {
	diskpart /s "C:\OD\Jessica\OneDrive\Documents\PowerShell Scripts\Make_a_Multiple_ISO_Bootable_USB_Drive_Run_First.bat"
}

function FormatUSBOSInstallers2 {
	#."C:\OD\Jessica\OneDrive\Documents\PowerShell Scripts\App Installer Scripts\Make_a_Multiple_ISO_Bootable_USB_Drive_Run_Second.ps1"
	<# ! Samsung USB Drive #>
	<# ! Samsung USB Drive #>
	<# ! Samsung USB Drive #>
	# MemTest86
	# Identify the target USB drive (ensure correct drive letter)
	$usbDrive = "M:"
	
	# Format the USB drive
	# Format-Volume -DriveLetter $usbDrive.Trim(":") -FileSystem FAT -NewFileSystemLabel "MemTest86" -Confirm:$false
	
	# Mount the ISO file
	$isoPath = "C:\OD\Jessica\OneDrive\Jess Files\USB OS Installers and Tools\memtest.iso"
	$mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
	# Get all volumes associated with the mounted image
	$volumeInfo = $mountResult | Get-Volume
	
	# Pick the one that actually has a label
	$osVolumeInfo = $mountResult | Get-Volume | Where-Object { $_.FileSystemLabel } | Select-Object -First 1
	Write-Host "Writing Source: $($osVolumeInfo.DriveLetter): - $($osVolumeInfo.FileSystemLabel) to $usbDrive" -ForegroundColor Green
	
	# Copy files to the USB
	$isoDriveLetter = $volumeInfo.DriveLetter
	robocopy "$($osVolumeInfo.DriveLetter):\" "$usbDrive\" /E /XN /XO /NFL /NDL /NJH /NJS /NC /NS
	
	# Clean up: Unmount the ISO
	Dismount-DiskImage -ImagePath $isoPath #-DevicePath $volumeInfo.DeviceID
	
	# Debian Linux
	# Identify the target USB drive (ensure correct drive letter)
	$usbDrive = "N:"
	
	# Format the USB drive
	# Format-Volume -DriveLetter $usbDrive.Trim(":") -FileSystem FAT32 -NewFileSystemLabel "Debian" -Confirm:$false
	
	# Mount the ISO file
	$isoPath = "C:\OD\Jessica\OneDrive\Jess Files\USB OS Installers and Tools\Debian v13.4.0 x64.iso"
	$mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
	# Get all volumes associated with the mounted image
	$volumeInfo = $mountResult | Get-Volume
	
	# Pick the one that actually has a label
	$osVolumeInfo = $mountResult | Get-Volume | Where-Object { $_.FileSystemLabel } | Select-Object -First 1
	Write-Host "Writing Source: $($osVolumeInfo.DriveLetter): - $($osVolumeInfo.FileSystemLabel) to $usbDrive" -ForegroundColor Green
	
	# Copy files to the USB
	$isoDriveLetter = $volumeInfo.DriveLetter
	robocopy "$($osVolumeInfo.DriveLetter):\" "$usbDrive\" /E /XN /XO /NFL /NDL /NJH /NJS /NC /NS
	
	# Clean up: Unmount the ISO
	Dismount-DiskImage -ImagePath $isoPath #-DevicePath $volumeInfo.DeviceID
	
	# Ubuntu Linux
	# Identify the target USB drive (ensure correct drive letter)
	$usbDrive = "O:"
	
	# Format the USB drive
	# Format-Volume -DriveLetter $usbDrive.Trim(":") -FileSystem FAT32 -NewFileSystemLabel "Ubuntu" -Confirm:$false
	
	# Mount the ISO file
	$isoPath = "C:\OD\Jessica\OneDrive\Jess Files\USB OS Installers and Tools\Ubuntu 25.10 Questing Quokka x64.iso"
	$mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
	# Get all volumes associated with the mounted image
	$volumeInfo = $mountResult | Get-Volume
	
	# Pick the one that actually has a label
	$osVolumeInfo = $mountResult | Get-Volume | Where-Object { $_.FileSystemLabel } | Select-Object -First 1
	Write-Host "Writing Source: $($osVolumeInfo.DriveLetter): - $($osVolumeInfo.FileSystemLabel) to $usbDrive" -ForegroundColor Green
	
	# Copy files to the USB
	$isoDriveLetter = $volumeInfo.DriveLetter
	robocopy "$($osVolumeInfo.DriveLetter):\" "$usbDrive\" /E /XN /XO /NFL /NDL /NJH /NJS /NC /NS
	
	# Clean up: Unmount the ISO
	Dismount-DiskImage -ImagePath $isoPath #-DevicePath $volumeInfo.DeviceID
	
	# Win 11 Retail
	# Identify the target USB drive (ensure correct drive letter)
	$usbDrive = "P:"
	
	# Format the USB drive
	# Format-Volume -DriveLetter $usbDrive.Trim(":") -FileSystem NTFS -NewFileSystemLabel "Windows 11 Retail 25H2" -Confirm:$false
	
	# Mount the ISO file
	$isoPath = "C:\OD\Jessica\OneDrive\Jess Files\USB OS Installers and Tools\Windows 11 Retail 25H2 x64.iso"
	$mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
	# Get all volumes associated with the mounted image
	$volumeInfo = $mountResult | Get-Volume
	
	# Pick the one that actually has a label
	$osVolumeInfo = $mountResult | Get-Volume | Where-Object { $_.FileSystemLabel } | Select-Object -First 1
	Write-Host "Writing Source: $($osVolumeInfo.DriveLetter): - $($osVolumeInfo.FileSystemLabel) to $usbDrive" -ForegroundColor Green
	
	# Copy files to the USB
	$isoDriveLetter = $volumeInfo.DriveLetter
	robocopy "$($osVolumeInfo.DriveLetter):\" "$usbDrive\" /E /XN /XO /NFL /NDL /NJH /NJS /NC /NS
	# Clean up: Unmount the ISO
	Dismount-DiskImage -ImagePath $isoPath #-DevicePath $volumeInfo.DeviceID
}

function FormatUSBOSInstallers3 {
	#."C:\OD\Jessica\OneDrive\Documents\PowerShell Scripts\App Installer Scripts\Make_a_Multiple_ISO_Bootable_USB_Drive_Run_Third.ps1"
	<# ! Cruzer USB Drive #>
	<# ! Cruzer USB Drive #>
	<# ! Cruzer USB Drive #>
	# Debian Linux
	# Identify the target USB drive (ensure correct drive letter)
	$usbDrive = "Q:"
	
	# Format the USB drive
	# Format-Volume -DriveLetter $usbDrive.Trim(":") -FileSystem FAT32 -NewFileSystemLabel "Debian" -Confirm:$false
	
	$isoPath = "C:\OD\Jessica\OneDrive\Jess Files\USB OS Installers and Tools\Debian v13.4.0 x64.iso"
	$mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
	# Get all volumes associated with the mounted image
	$volumeInfo = $mountResult | Get-Volume
	
	# Pick the one that actually has a label
	$osVolumeInfo = $mountResult | Get-Volume | Where-Object { $_.FileSystemLabel } | Select-Object -First 1
	Write-Host "Writing Source: $($osVolumeInfo.DriveLetter): - $($osVolumeInfo.FileSystemLabel) to $usbDrive" -ForegroundColor Green
	
	# Copy files to the USB
	$isoDriveLetter = $volumeInfo.DriveLetter
	robocopy "$($osVolumeInfo.DriveLetter):\" "$usbDrive\" /E /XN /XO /NFL /NDL /NJH /NJS /NC /NS/XO
	
	# Clean up: Unmount the ISO
	Dismount-DiskImage -ImagePath $isoPath #-DevicePath $volumeInfo.DeviceID
	
	# Ubuntu Linux
	# Identify the target USB drive (ensure correct drive letter)
	$usbDrive = "R:"
	
	# Format the USB drive
	# Format-Volume -DriveLetter $usbDrive.Trim(":") -FileSystem FAT32 -NewFileSystemLabel "Ubuntu" -Confirm:$false
	
	# Mount the ISO file
	$isoPath = "C:\OD\Jessica\OneDrive\Jess Files\USB OS Installers and Tools\Ubuntu 25.10 Questing Quokka x64.iso"
	$mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
	# Get all volumes associated with the mounted image
	$volumeInfo = $mountResult | Get-Volume
	
	# Pick the one that actually has a label
	$osVolumeInfo = $mountResult | Get-Volume | Where-Object { $_.FileSystemLabel } | Select-Object -First 1
	Write-Host "Writing Source: $($osVolumeInfo.DriveLetter): - $($osVolumeInfo.FileSystemLabel) to $usbDrive" -ForegroundColor Green
	
	# Copy files to the USB
	$isoDriveLetter = $volumeInfo.DriveLetter
	robocopy "$($osVolumeInfo.DriveLetter):\" "$usbDrive\" /E /XN /XO /NFL /NDL /NJH /NJS /NC /NS/XO
	
	# Clean up: Unmount the ISO
	Dismount-DiskImage -ImagePath $isoPath #-DevicePath $volumeInfo.DeviceID
	
	
	# Win 11 Retail
	# Identify the target USB drive (ensure correct drive letter)
	$usbDrive = "S:"
	
	# Format the USB drive
	# Format-Volume -DriveLetter $usbDrive.Trim(":") -FileSystem NTFS -NewFileSystemLabel "Windows 11 Retail 25H2" -Confirm:$false
	
	# Mount the ISO file
	$isoPath = "C:\OD\Jessica\OneDrive\Jess Files\USB OS Installers and Tools\Windows 11 Retail 25H2 x64.iso"
	$mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
	# Get all volumes associated with the mounted image
	$volumeInfo = $mountResult | Get-Volume
	
	# Pick the one that actually has a label
	$osVolumeInfo = $mountResult | Get-Volume | Where-Object { $_.FileSystemLabel } | Select-Object -First 1
	Write-Host "Writing Source: $($osVolumeInfo.DriveLetter): - $($osVolumeInfo.FileSystemLabel) to $usbDrive" -ForegroundColor Green
	
	# Copy files to the USB
	$isoDriveLetter = $volumeInfo.DriveLetter
	robocopy "$($osVolumeInfo.DriveLetter):\" "$usbDrive\" /E /XN /XO /NFL /NDL /NJH /NJS /NC /NS/XO
	
	# Clean up: Unmount the ISO
	Dismount-DiskImage -ImagePath $isoPath #-DevicePath $volumeInfo.DeviceID
	
	# Win 11 Insider Preview
	# Identify the target USB drive (ensure correct drive letter)
	$usbDrive = "T:"
	
	# Format the USB drive
	# Format-Volume -DriveLetter $usbDrive.Trim(":") -FileSystem NTFS -NewFileSystemLabel "Win 11 Insider Preview" -Confirm:$false
	
	# Mount the ISO file
	$isoPath = "C:\OD\Jessica\OneDrive\Jess Files\USB OS Installers and Tools\Windows 11 Insider Preview x64 v22621.iso"
	$mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
	# Get all volumes associated with the mounted image
	$volumeInfo = $mountResult | Get-Volume
	
	# Pick the one that actually has a label
	$osVolumeInfo = $mountResult | Get-Volume | Where-Object { $_.FileSystemLabel } | Select-Object -First 1
	Write-Host "Writing Source: $($osVolumeInfo.DriveLetter): - $($osVolumeInfo.FileSystemLabel) to $usbDrive" -ForegroundColor Green
	
	# Copy files to the USB
	$isoDriveLetter = $volumeInfo.DriveLetter
	robocopy "$($osVolumeInfo.DriveLetter):\" "$usbDrive\" /E /XN /XO /NFL /NDL /NJH /NJS /NC /NS/XO
	
	# Clean up: Unmount the ISO
	Dismount-DiskImage -ImagePath $isoPath #-DevicePath $volumeInfo.DeviceID
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
$functions = 'EmptyRecycleBin', 'OneDriveSecurity', 'SymbolicLinks', 'Functions', 'Aliases', 
'OneDriveSize', 'GoogleDriveSize', 'PowerShellVersion', 'RemoveAllAttributes', 'InstallDrivers', 
'SetEfficiencyModeSystemwide', 'ReloadProfile', 'BadAccounts', 'RepairRecycleBin', 'GetOllamaAIModels', 
'WingetInstallBatch', 'FormatUSBOSInstallers1', 'FormatUSBOSInstallers2', 'FormatUSBOSInstallers3'

$aliases = 'OneDriveFixDeniedPermissions', 'SymbolicLinks', 'Junctions', 'Version', 'About', 'SecurityReset', 
'SymLinks', 'Reload'

Export-ModuleMember -Function $functions -Alias $aliases