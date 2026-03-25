# ============================================================
# PowerShell Profile - Compatible with Windows PowerShell 5.1
# ============================================================
# This profile works in both PowerShell 5.1 and PowerShell 7+
# Save to: $HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1

# Ensure profile exists
if (-not (Test-Path -Path $PROFILE)) {
	New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}

# Load profile module so aliases show a Source in Get-Alias
$ProfileHelpersPath = Join-Path -Path (Split-Path -Parent $PROFILE) -ChildPath 'Modules\ProfileHelpers\ProfileHelpers.psm1'
if (Test-Path $ProfileHelpersPath) {
	Import-Module $ProfileHelpersPath -Force -ErrorAction SilentlyContinue
}

# ============================================================
# Profile Loaded Successfully
# ============================================================
PowerShellProfileFunctions
PowerShellProfileAliases