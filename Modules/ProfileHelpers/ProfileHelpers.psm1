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
	$Path1 = "C:\Windows.old\Windows"
	$Path2 = "C:\Windows.old\Users"
	$Path3 = "C:\Windows.old"
	
	# ! If the above method fails due to locked files, we can attempt to take ownership and grant full control to Administrators, then remove read-only, system, and hidden attributes before deleting the folder.
	
	if (Test-Path $Path1) {
		Write-Host "Taking ownership of $Path1 ..." -ForegroundColor Cyan
		takeown /F $Path1 /A /R /D Y | Out-Null

		Write-Host "Granting Administrators full control ..." -ForegroundColor Cyan
		icacls $Path1 /grant Administrators:F /T /C | Out-Null

		Write-Host "Removing attributes (read-only, system, hidden) ..." -ForegroundColor Cyan
		Get-ChildItem -Path $Path1 -Recurse -Force | ForEach-Object {
			try {
				attrib -R -S -H $_.FullName
			}
			catch {}
		}
		
		Write-Host "Deleting folder..." -ForegroundColor Yellow
		Remove-Item $Path1 -Recurse -Force -ErrorAction SilentlyContinue
	
		if (-not (Test-Path $Path1)) {
			Write-Host "Windows.old successfully deleted." -ForegroundColor Green
		}
		else {
			Remove-Item $Path1 -Recurse -Force -ErrorAction SilentlyContinue
			Write-Host "Some files in $Path1 could not be deleted. A reboot may be required." -ForegroundColor Red
		}
	}
	else {
		Write-Host "$Path1 does not exist." -ForegroundColor DarkYellow
	}
	
	if (Test-Path $Path2) {
		Write-Host "Taking ownership of $Path2 ..." -ForegroundColor Cyan
		takeown /F $Path2 /A /R /D Y | Out-Null

		Write-Host "Granting Administrators full control ..." -ForegroundColor Cyan
		icacls $Path2 /grant Administrators:F /T /C | Out-Null

		Write-Host "Removing attributes (read-only, system, hidden) ..." -ForegroundColor Cyan
		Get-ChildItem -Path $Path2 -Recurse -Force | ForEach-Object {
			try {
				attrib -R -S -H $_.FullName
			}
			catch {}
		}
		
		Write-Host "Deleting folder..." -ForegroundColor Yellow
		Remove-Item $Path2 -Recurse -Force -ErrorAction SilentlyContinue
	
		if (Test-Path $Path3) {
			Write-Host "Taking ownership of $Path3 ..." -ForegroundColor Cyan
			takeown /F $Path3 /A /R /D Y | Out-Null
	
			Write-Host "Granting Administrators full control ..." -ForegroundColor Cyan
			icacls $Path3 /grant Administrators:F /T /C | Out-Null
	
			Write-Host "Removing attributes (read-only, system, hidden) ..." -ForegroundColor Cyan
			Get-ChildItem -Path $Path2 -Recurse -Force | ForEach-Object {
				try {
					attrib -R -S -H $_.FullName
				}
				catch {}
			}
			
			if (-not (Test-Path $Path2)) {
				Write-Host "$Path2 successfully deleted." -ForegroundColor Green
			}
			else {
				Remove-Item $Path2 -Recurse -Force -ErrorAction SilentlyContinue
				Write-Host "Some files in $Path2 could not be deleted. A reboot may be required." -ForegroundColor Red
			}
			if (-not (Test-Path $Path3)) {
				Write-Host "$Path3 successfully deleted." -ForegroundColor Green
			}
			else {
				Remove-Item $Path3 -Recurse -Force -ErrorAction SilentlyContinue
				Write-Host "Some files in $Path3 could not be deleted. A reboot may be required." -ForegroundColor Red
			}
		
			Remove-Item $Path3 -Recurse -Force -ErrorAction SilentlyContinue
			# ! Use Robocopy to mirror an empty directory over Windows.old, which can help remove stubborn files on next reboot if the above method fails.
			mkdir C:\Empty
			robocopy C:\Empty C:\Windows.old /MIR /R:1 /W:1
		}
		else {
			Write-Host "C:\Windows.old does not exist." -ForegroundColor DarkYellow
		}
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

function WingetInstallBatch {
<# WINGET INSTALLATION #>
$progressPreference = 'silentlyContinue'
<# ! Trust the PSGallery repositoryu #>
<# ! Get-Module lists modules installed from PSGallery! #>
Write-Host "Installing WinGet PowerShell module from PSGallery..."
Set-PSRepository PSGallery -InstallationPolicy Trusted
Install-PackageProvider -Name NuGet -Force | Out-Null
Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null
Write-Host "Using Repair-WinGetPackageManager cmdlet to bootstrap WinGet..."
Repair-WinGetPackageManager -AllUsers
Write-Host "Done."
<# WINGET INSTALLATION #>

<# ! Main Application Install Batch ! #>
winget install Logitech.GHUB --accept-source-agreements --accept-package-agreements # --force # Logitech G HUB
winget update Microsoft.Onedrive --accept-source-agreements --accept-package-agreements # --force # Logitech G HUB # OneDrive

# ^ Not needed unless troubleshooting, as OneDrive is already included with Windows and should update through Windows Update.
# ^ winget install Microsoft.Onedrive --accept-source-agreements --accept-package-agreements # --force # OneDrive

winget install Microsoft.Edge.Beta --accept-source-agreements --accept-package-agreements # --force # Microsoft Edge Beta
winget install Discord.Discord --accept-source-agreements --accept-package-agreements # --force # Discord
winget install Microsoft.WindowsTerminal.Preview --accept-source-agreements --accept-package-agreements --force # Windows Terminal (Preview)
winget install Microsoft.WindowsTerminal --accept-source-agreements --accept-package-agreements --force # Windows Terminal
winget install Microsoft.PowerShell.Preview --source winget --accept-source-agreements --accept-package-agreements --force # PowerShell 7.6 (Preview)
winget install Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements --force # PowerShell 7.6
winget install CodeSector.TeraCopy --accept-source-agreements --accept-package-agreements # --force # TeraCopy
winget install MartiCliment.UniGetUI --accept-source-agreements --accept-package-agreements # --force # UniGetUI - A GUI for winget
winget install M2Team.NanaZip --accept-source-agreements --accept-package-agreements # --force # NanaZip
winget install 7zip.7zip --accept-source-agreements --accept-package-agreements # --force # 7-Zip
# ^ winget install M2Team.NanaZip.Preview --accept-source-agreements --accept-package-agreements # --force # NanaZip Preview

<# & AI Apps #>
winget install Ollama.Ollama --accept-source-agreements --accept-package-agreements # --force # Ollama
winget install Anthropic.Claude --accept-source-agreements --accept-package-agreements # --force # Claude
winget install XP8JNQFBQH6PVF --accept-source-agreements --accept-package-agreements # --force # Perplexity AI
winget install ElementLabs.LMStudio --accept-package-agreements --accept-source-agreements # --force # LM Studio

Set-Location "E:\OD\Jessica\OneDrive\Jess Files\Windows Application Installers\! AI LLM CLIENTS"
./"Desktop Commander x64.msi"

<# & AI Apps #>

winget install Chocolatey.Chocolatey --accept-source-agreements --accept-package-agreements # --force # Chocolatey
winget install --id "Chocolatey.ChocolateyGUI" --exact --source winget --accept-source-agreements --disable-interactivity --silent --accept-package-agreements # --force

Set-Location "C:\OD\Jessica\OneDrive\Jess Files\Windows Application Installers\WinGet and UniGetUI"
./"Winget-Auto-Update.msi"
./"Winget-Auto-Upgrade.msi"
# ! MaWinget-Auto-Upgrade.msi
# ! winget install KnifMelti.WAU-Settings-GUI --accept-source-agreements --accept-package-agreements # --force # WAU Settings GUI (A GUI for Romanitho's Winget AutoUpdate)
<# & AI Apps #>

winget install --id "peterandree.winget-chocolatey-manager" --exact --source winget --accept-source-agreements --disable-interactivity --silent --accept-package-agreements # --force  <# identified all your installed apps, that are not managed by winget or chocolatey and registers them for chocolatey if possible, allowing automated updates #>
<# 
Winget AutoUpgrade is a tool that automatically updates all your installed applications using winget. It checks for updates regularly and installs them without requiring user intervention.
winget source add -n salamek-win -t "Microsoft.Rest" -a https://repository.salamek.cz/win/api/
winget install salamek.winget-auto-upgrade --silent --accept-package-agreements --accept-source-agreements
./"E:\OD\Jessica\OneDrive\Jess Files\Windows Application Installers\WinGet and UniGetUI\Winget-Auto-Upgrade.msi"
#>
choco install amd-ryzen-master -y # --force
choco install Firefox -y # --force
choco install applet-runner-pro -y # --force # Desktop Commander
choco install cupscale -y # --force # Cupscale
choco install nvidia-display-driver -y # --force # NVIDIA Display Driver
choco install amd-cleanup-utility -y # --force # AMD Cleanup Utility
choco install xmedia-recode -y # --force # XMedia Recode
choco install hydralauncher -y # --force # HydraLauncher
choco install realtek-hd-audio-driver -y # --force # Realtek HD Audio Driver

<# Activate Chocolatey Manager to register all non-winget apps with chocolatey, allowing for automated updates. #>
winget-choco-manager

<# ^ PowerShell Modules #>
Install-Module -Name PSWindowsUpdate
Install-Module -Name PackageManagement
Install-Module -Name RunAsUser
Install-Module -Name PowerShellGet -AllowPrerelease -Force

# * Updates PowerShell help files for all installed modules.
Update-Help -Force
<# ^ PowerShell Modules #>

<# ^ IrfanView and plugins +GIMP #>
winget install IrfanSkiljan.IrfanView --accept-source-agreements --accept-package-agreements # --force # IrfanView
winget install IrfanSkiljan.IrfanView.PlugIns --accept-source-agreements --accept-package-agreements # --force # IrfanView PlugIns
winget install GIMP.GIMP.3 --accept-source-agreements --accept-package-agreements # --force # GIMP 3.0
winget install Foxit.FoxitReader --accept-source-agreements --accept-package-agreements # --force # Foxit PDF Reader
winget install FoxIt.FoxitPDFEditor --accept-source-agreements --accept-package-agreements # --force # Foxit PDF Editor
winget install TheDocumentFoundation.LibreOffice --accept-source-agreements --accept-package-agreements # --force # LibreOffice
# winget install Mozilla.Thunderbird --accept-source-agreements --accept-package-agreements # --force # Mozilla Thunderbird
winget install Microsoft.EdgeWebView2Runtime --accept-source-agreements --accept-package-agreements # --force # Microsoft Edge WebView2 Runtime
winget install Valve.Steam --accept-source-agreements --accept-package-agreements # --force # Steam
# ! The winget package isn't working for some reason, so I'm installing it manually for now. # Steam Library Manager
# ! winget install RevoLand.Steam-Library-Manager --accept-source-agreements --accept-package-agreements # --force # Steam Library Manager
winget install GNE.DualMonitorTools --accept-source-agreements --accept-package-agreements # --force # Dual Monitor Tools
winget install winaero.tweaker --accept-source-agreements --accept-package-agreements # --force
winget install Glarysoft.GlaryUtilities --accept-source-agreements --accept-package-agreements # --force
winget install Google.GoogleDrive --accept-source-agreements --accept-package-agreements # --force #Google Drive
winget install Microsoft.PowerToys --accept-source-agreements --accept-package-agreements # --force # PowerToys
winget install Dropbox.Dropbox --accept-source-agreements --accept-package-agreements # --force # Dropbox
winget install VideoLAN.VLC --accept-source-agreements --accept-package-agreements # --force # VLC Media Player
winget install Microsoft.PowerShell.Archive --accept-source-agreements --accept-package-agreements # --force # PowerShell Archive
winget install Microsoft.PowerShell.PSResourceGet --accept-source-agreements --accept-package-agreements # --force # PowerShell PSResourceGet
winget install Microsoft.PowerShell.ConsoleGuiTools --accept-source-agreements --accept-package-agreements # --force # PowerShell ConsoleGuiTools
winget install Microsoft.PowerShell.Crescendo --accept-source-agreements --accept-package-agreements # --force # PowerShell Crescendo
winget install Microsoft.PowerShell.WhatsNew --accept-source-agreements --accept-package-agreements # --force # PowerShell WhatsNew
winget install Microsoft.PowerShell.TextUtility --accept-source-agreements --accept-package-agreements # --force # PowerShell TextUtility
winget install Microsoft.PowerShell.PSAdapter --accept-source-agreements --accept-package-agreements # --force # PowerShell PSAdapter
winget install WinDirStat.WinDirStat.Beta --accept-source-agreements --accept-package-agreements # --force # WinDirStat Beta
winget install Skillbrains.Lightshot 
winget install FastStone.Viewer --accept-source-agreements --accept-package-agreements # --force
winget install HandBrake.HandBrake --accept-source-agreements --accept-package-agreements # --force # HandBrake
winget install HandBrake.HandBrake.CLI --accept-source-agreements --accept-package-agreements # --force # HandBrake CLI
winget install Mozilla.Firefox --accept-source-agreements --accept-package-agreements # --force
winget install CPUID.CPU-Z --accept-source-agreements --accept-package-agreements # --force
winget install CPUID.HWMonitor --accept-source-agreements --accept-package-agreements # --force
winget install REALiX.HWiNFO --accept-source-agreements --accept-package-agreements # --force
winget install CrystalDewWorld.CrystalDiskInfo --accept-source-agreements --accept-package-agreements # --force
winget install CrystalDewWorld.CrystalDiskMark --accept-source-agreements --accept-package-agreements # --force
winget install VoodooSoft.DefenderUI --accept-source-agreements --accept-package-agreements # --force # DefenderUI
winget install GOG.Galaxy --accept-source-agreements --accept-package-agreements # --force # GOG Galaxy
winget install EpicGames.EpicGamesLauncher --accept-source-agreements --accept-package-agreements # --force # Epic Games Launcher
winget install ElectronicArts.EADesktop --accept-source-agreements --accept-package-agreements # --force # EA Desktop

# winget install Cygwin.Cygwin --accept-source-agreements --accept-package-agreements # --force # Cygwin
# winget install qBittorrent.qBittorrent --accept-source-agreements --accept-package-agreements # --force # qBittorrent
winget install LiteratureAndLatte.Scrivener --accept-source-agreements --accept-package-agreements # --force # Scrivener v3
winget install Wagnardsoft.DisplayDriverUninstaller --accept-source-agreements --accept-package-agreements # --force # Display Driver Uninstaller (DDU)
winget install JamesCJ60.Universalx86TuningUtility --accept-source-agreements --accept-package-agreements # --force

<# ! Integrated Development Environments (IDEs) & Other Tools #>
winget install Microsoft.VisualStudioCode --accept-source-agreements --accept-package-agreements # --force <# Visueal Studio Code#>
winget install Microsoft.VisualStudioCode.Insiders --accept-source-agreements --accept-package-agreements # --force <# Visueal Studio Code#>
winget install VSCodium.VSCodium --accept-source-agreements --accept-package-agreements --accept-source-agreements --accept-package-agreements # --force # VSCodium
winget install Microsoft.VisualStudio.Community --accept-source-agreements --accept-package-agreements # --force <# Visual Studio Community Edition#>
winget install LuaLS.lua-language-server --accept-source-agreements --accept-package-agreements # --force <# Lua Language Server#>
winget install Koihik.vscode-lua-format --accept-source-agreements --accept-package-agreements # --force <# Lua Format#>
winget install GitHub.Copilot --accept-source-agreements --accept-package-agreements # --force # Copilot CLI v.1.0.7
winget install Anthropic.ClaudeCode --accept-source-agreements --accept-package-agreements # --force
winget install vscode-powershell --accept-source-agreements --accept-package-agreements # --force <# PowerShell Extension for VSCode#>
winget install Git.Git --accept-source-agreements --accept-package-agreements # --force <# Git Version Control#>
winget install GitHub.GitHubDesktop --accept-source-agreements --accept-package-agreements # --force <# GitHub Desktop#>
winget install Microsoft.CmdPalGitHubExtension --accept-source-agreements --accept-package-agreements # --force <# GitHub extension for Command Palette#>
winget install 15722UsefulApp.WorkspaceLauncherForVSCode --accept-source-agreements --accept-package-agreements # --force <# Workspace Launcher for VSCode#>
winget install Microsoft.VisualStudioCode.CLI --accept-source-agreements --accept-package-agreements # --force <# Microsoft Visual Studio Code CLI#>
winget install AlexanderBrandt.AIConsumptionTracker --accept-source-agreements --accept-package-agreements # --force # AI Consumption Tracker v.2.2.23 Tag:github-copilot
winget install rjpcomputing.luaforwindows --accept-source-agreements --accept-package-agreements # --force <# Lua for Windows#>
winget install JonahFintzDEV.CommandPalette-VSCode # --force
winget install GitHub.cli --accept-source-agreements --accept-package-agreements # --force <# GitHub CLI#>
winget install Python.PythonInstallManager --accept-source-agreements --accept-package-agreements # --force
winget install Python.Python.3.14 --accept-source-agreements --accept-package-agreements # --force
winget install Python.Python.3.14.Launcher --accept-source-agreements --accept-package-agreements # --force
winget install CondaForge.Miniforge3 --accept-source-agreements --accept-package-agreements # --force
winget install 9NPR957HTH9Q --accept-source-agreements --accept-package-agreements # --force # LuaBox
<# ! Integrated Development Environments (IDEs) & Other Tools #>



<# Integrated Development Environments (IDEs) & Other Tools (DISABLED)
winget install Microsoft.WindowsDriverKit --accept-source-agreements --accept-package-agreements # --force # Windows Driver Kit (WDK)
winget install Microsoft.VisualStudioCode.Insiders --accept-source-agreements --accept-package-agreements # --force
winget install Microsoft.VisualStudioCode.Insiders.CLI --accept-source-agreements --accept-package-agreements # --force
winget install VSCodium.VSCodium.Insiders --accept-source-agreements --accept-package-agreements # --force # VSCodium Insiders
winget install zokugun.MrCode --accept-source-agreements --accept-package-agreements --accept-source-agreements --accept-package-agreements # --force # MrCode
winget install EclipseFoundation.TheiaIDE --accept-source-agreements --accept-package-agreements # --force
winget install KDE.Kate --accept-source-agreements --accept-package-agreements # --force # Kate
winget install Alex313031.Codium --accept-source-agreements --accept-package-agreements # --force # Codium https://itsfoss.com/vs-code-vs-codium/

<# ^ Are these any good?
winget install Docker.DockerDesktop --accept-source-agreements --accept-package-agreements # --force
winget install Docker.DockerCompose --accept-source-agreements --accept-package-agreements # --force
winget install Docker.DockerDesktopEdge --accept-source-agreements --accept-package-agreements # --force
winget install Docker.DockerCLI --accept-source-agreements --accept-package-agreements # --force
#>
Integrated Development Environments (IDEs) & Other Tools (DISABLED) #>

<# Microsft .Net Runtimes #>
winget install Microsoft.DotNet.DesktopRuntime.3_1 --accept-source-agreements --accept-package-agreements # --force
winget install Microsoft.DotNet.DesktopRuntime.5 --accept-source-agreements --accept-package-agreements # --force
winget install Microsoft.DotNet.DesktopRuntime.7 --accept-source-agreements --accept-package-agreements # --force
winget install Microsoft.DotNet.DesktopRuntime.8 --accept-source-agreements --accept-package-agreements # --force
winget install Microsoft.DotNet.DesktopRuntime.9 --accept-source-agreements --accept-package-agreements # --force
winget install Microsoft.DotNet.DesktopRuntime.10 --accept-source-agreements --accept-package-agreements # --force
winget install Microsoft.DotNet.Runtime.5 --accept-source-agreements --accept-package-agreements # --force
winget install Microsoft.DotNet.Runtime.6 --accept-source-agreements --accept-package-agreements # --force
winget install Microsoft.DotNet.Runtime.7 --accept-source-agreements --accept-package-agreements # --force
winget install Microsoft.DotNet.Runtime.8 --accept-source-agreements --accept-package-agreements # --force
winget install Microsoft.DotNet.Runtime.9 --accept-source-agreements --accept-package-agreements # --force
<# Microsft .Net Runtimes #>

<# *  LINUX DISTROS & Virtual Machines 	#>
winget install Microsoft.WSL --accept-source-agreements --accept-package-agreements # --force <# Windows Subsystem for Linux#>
winget install Canonical.Ubuntu --accept-source-agreements --accept-package-agreements # --force
winget install Oracle.OracleLinux.9.5 --accept-source-agreements --accept-package-agreements # --force <# Oracle Linux 9.5#>
winget install SUSE.openSUSE.Leap.15.6 --accept-source-agreements --accept-package-agreements # --force # openSUSE Leap 15.6
winget install OffSec.KaliLinux --accept-source-agreements --accept-package-agreements # --force # Kali Linux
winget install 9PLSJR4TG2GQ --accept-source-agreements --accept-package-agreements # --force <# Linux WSL Distribution Manager#>
winget install Toxblh.WinToLinux # --forcex <# Creates a Linux VM based on your Windows configuration and allows you to install Linux distros on it. #>
winget install 9P5RWLM70SN9 --accept-source-agreements --accept-package-agreements # --force # AlmaLinux OS 9
winget install 9P41G2MV9CQ3 --accept-source-agreements --accept-package-agreements # --force # Pistachio Linux
winget install whitewaterfoundry.fedora-remix-for-wsl --accept-source-agreements --accept-package-agreements # --force # Fedora Remix for WSL
winget install Canonical.UbuntuProforWSL --accept-source-agreements --accept-package-agreements # --force
winget install Whop42.LinuxConvert --accept-source-agreements --accept-package-agreements # --force <# Linux Convert - Converts a Linux ISO into a WSL distro#>
winget install Mintty.WSLtty --accept-source-agreements --accept-package-agreements # --force <# WSLtty - A terminal for WSL#>

winget install Fedora.FedoraMediaWriter --accept-source-agreements --accept-package-agreements # --force # Fedora Media Writer

<# ^ Virtual Machines #>
winget install Oracle.VirtualBox --accept-source-agreements --accept-package-agreements # --force <# ^Oracle VM VirtualBox #>
Set-Location "E:\OD\Jessica\OneDrive\Jess Files\Windows Application Installers\Virtual Machines"
.\"VMware Player.exe"
<# ^  Virtual Machines #>

<# * Weather Applications
winget install 9WZDNCRFJ3Q2 --accept-source-agreements --accept-package-agreements # --force
winget install 9PP0MFQFVSC5 --accept-source-agreements --accept-package-agreements # --force
winget install 9N33PK9646X9 --accept-source-agreements --accept-package-agreements # --force
winget install 9P1HHTX0G22F --accept-source-agreements --accept-package-agreements # --force
winget install 9WZDNCRDNDDC --accept-source-agreements --accept-package-agreements # --force
winget install 9WZDNCRDDD9P --accept-source-agreements --accept-package-agreements # --force
winget install 9PFD136M8457 --accept-source-agreements --accept-package-agreements # --force
winget install 9NBLGGH5M67C --accept-source-agreements --accept-package-agreements # --force
winget install 9NKC37BC8SRX --accept-source-agreements --accept-package-agreements # --force
winget install 9N0F79RT175S --accept-source-agreements --accept-package-agreements # --force
winget install 9NK7991SSJF1 --accept-source-agreements --accept-package-agreements # --force
winget install 9PN5DLPMHV1Z --accept-source-agreements --accept-package-agreements # --force
winget install 9PN4P7PMP4JT --accept-source-agreements --accept-package-agreements # --force
* Weather Applications #>

<# ? 	GitHub 	# 
winget install AmarBego.GitTop --accept-source-agreements --accept-package-agreements # --force # GitTop v.0.4.0 Tag:github
winget install Bostrot.WSLManager --accept-source-agreements --accept-package-agreements # --force # WSL Manager v.1.10.0 Tag:github
winget install CosimoMatteini.DRA --accept-source-agreements --accept-package-agreements # --force # DRA v.0.10.1 Tag:github
winget install CosmoX.Lepton --accept-source-agreements --accept-package-agreements # --force # Lepton v.1.10.0 Tag:github
winget install DuckStudio.GitHubLabelsManager --accept-source-agreements --accept-package-agreements # --force # GitHub v.1.13 Tag:github
winget install DuckStudio.GitHubView --accept-source-agreements --accept-package-agreements # --force # GitHubView v.1.0.6 Tag:github
winget install DuckStudio.GitHubView.Nightly --accept-source-agreements --accept-package-agreements # --force # GitHubView (Nightly) v.2025.12.14.20209192776 Tag:github
winget install Git.GCM --accept-source-agreements --accept-package-agreements # --force # Git Credential Manager (User) v.2.7.0 Tag:github
winget install GitHub.Copilot.Prerelease --accept-source-agreements --accept-package-agreements # --force # Copilot CLI (Preview) v.1.0.8-0 Tag:github
winget install GitHub.GitHubDesktop.Beta --accept-source-agreements --accept-package-agreements # --force # GitHub Desktop Beta v.3.5.5-beta2 Tag:github
winget install GitHub.GitLFS --accept-source-agreements --accept-package-agreements # --force # Git LFS v.3.7.1 Tag:github
winget install GitHub.git-sizer --accept-source-agreements --accept-package-agreements # --force # git-sizer v.1.5.0 Tag:github
winget install Gitify.Gitify --accept-source-agreements --accept-package-agreements # --force # Gitify v.6.17.0 Tag:github
winget install GordonBeeming.CopilotHere --accept-source-agreements --accept-package-agreements # --force # copilot_here v.2026.03.08.441 Tag:github
winget install PenguinLabs.Cacher --accept-source-agreements --accept-package-agreements # --force # Cacher v.2.43.2 Tag:github
winget install Shinokada.Gitstart --accept-source-agreements --accept-package-agreements # --force # GITSTART v.1.1.0 Tag:github
winget install StefHeyenrath.GitHubReleaseNotes --accept-source-agreements --accept-package-agreements # --force # GitHubReleaseNotes v.1.0.10.1 Tag:github
winget install ZacharyYedidia.Eget --accept-source-agreements --accept-package-agreements # --force # Eget v.1.3.4 Tag:github
winget install docmirror.dev-sidecar --accept-source-agreements --accept-package-agreements # --force # dev-sidecar v.2.0.0 Tag:github
winget install dvcrn.markright --accept-source-agreements --accept-package-agreements # --force # MarkRight v.0.1.11 Tag:github
winget install feraxhp.grp --accept-source-agreements --accept-package-agreements # --force # grp v.0.12.0 Tag:github
winget install nektos.act --accept-source-agreements --accept-package-agreements # --force # act v.0.2.84 Tag:github
winget install polrivero.GitHubDesktopPlus --accept-source-agreements --accept-package-agreements # --force # GitHub Desktop Plus v.3.5.7-r0 Tag:github
winget install zhaopengme.gitnote --accept-source-agreements --accept-package-agreements # --force # GitNote v.3.1.0 Tag:github
winget install CoolPlayLin.FastGithub --accept-source-agreements --accept-package-agreements # --force # FastGithub v.2.1.4 Tag:Github
winget install EryouHao.Gridea --accept-source-agreements --accept-package-agreements # --force # Gridea v.0.9.3 Tag:github-pages
winget install GitTools.GitVersion --accept-source-agreements --accept-package-agreements # --force # GitTools GitVersion v.6.6.2 Tag:githubflow
winget install GorillaDevs.Ferium --accept-source-agreements --accept-package-agreements # --force # Ferium v.4.7.1 Tag:github-releases
winget install rhysd.actionlint --accept-source-agreements --accept-package-agreements # --force # actionlint v.1.7.11 Tag:github-actions
winget install zizmor.zizmor --accept-source-agreements --accept-package-agreements # --force # zizmor v.1.23.1 Tag:github-actions
winget install zed.rainxch.githubstore --accept-source-agreements --accept-package-agreements # --force # GitHub Store v.1.6.2
winget install tekumara.gh-doctor --accept-source-agreements --accept-package-agreements # --force # GitHub Doctor v.0.3.0
winget install GitHub.Atom --accept-source-agreements --accept-package-agreements # --force # Atom v.1.60.0
winget install GitHub.Atom.Beta --accept-source-agreements --accept-package-agreements # --force # Atom Beta v.1.61.0-beta0
winget install GitHub.ClassroomAssistant --accept-source-agreements --accept-package-agreements # --force # classroom-assistant v.2.0.4
winget install GitHub.Copilot.modernization.agent --accept-source-agreements --accept-package-agreements # --force # Copilot modernization agent v.0.0.246
winget install GitHub.hub --accept-source-agreements --accept-package-agreements # --force # hub v.2.14.2
winget install GitHub.smimesign --accept-source-agreements --accept-package-agreements # --force # smimesign v.0.2.0-rc1
< ? 	GitHub 	#>

<# Activate Chocolatey Manager to register all non-winget apps with chocolatey, allowing for automated updates. #>
winget-choco-manager


<# ^ Winget Repair and Upgrade All #>
winget repair --all --accept-package-agreements --include-unknown
winget upgrade --all --accept-package-agreements --include-unknown
<# ^ Winget Repair and Upgrade All #>
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
'SetEfficiencyModeSystemwide', 'ReloadProfile', 'Windows.Old', 'RepairRecycleBin', 'GetOllamaAIModels', 
'WingetInstallBatch'

$aliases = 'OneDriveFixDeniedPermissions', 'SymbolicLinks', 'Junctions', 'Version', 'About', 'SecurityReset', 
'SymLinks', 'Reload'

Export-ModuleMember -Function $functions -Alias $aliases