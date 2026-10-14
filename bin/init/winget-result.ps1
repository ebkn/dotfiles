# Dot-sourced by windows.ps1, and by winget-result.test.ps1 so the
# classification can be checked without installing anything.

# Ids whose install or upgrade failed. Collected rather than thrown so one bad
# package does not skip the remap, AHK and WezTerm steps in windows.ps1; it
# exits non-zero at the end instead. Before this, winget's exit code was never
# read, so a failed install still ended in "Setup complete" and a green CI run.
$script:FailedPackages = @()

# winget exit codes that are not failures (doc/windows/package-manager/winget/
# returnCodes.md in microsoft/winget-cli): nothing to upgrade, already
# installed, installed but finishes on reboot, installed version not older.
$WingetOkCodes = @(
    0,
    -1978335189,  # 0x8A15002B UPDATE_NOT_APPLICABLE
    -1978335135,  # 0x8A150061 PACKAGE_ALREADY_INSTALLED
    -1978334967,  # 0x8A150109 INSTALL_REBOOT_REQUIRED_TO_FINISH
    -1978335153   # 0x8A15004F UPGRADE_VERSION_NOT_NEWER
)

# The code as winget's signed exit status. A scheduled task reports the same
# 32 bits unsigned.
function ConvertTo-WingetCode {
    param([long]$Code)
    if ($Code -gt [int32]::MaxValue) { $Code -= 4294967296 }
    return $Code
}

# Whether winget's exit code means the install or upgrade failed. Pure, so the
# classification is tested apart from the recording below.
function Test-WingetFailure {
    param([long]$Code)
    return -not ($WingetOkCodes -contains (ConvertTo-WingetCode $Code))
}

function Confirm-WingetResult {
    param([string]$Id, [long]$Code)
    # Converted first, and needed even though Test-WingetFailure converts too:
    # the [int32] cast below throws on the unsigned form a scheduled task gives.
    $Code = ConvertTo-WingetCode $Code
    if (-not (Test-WingetFailure $Code)) { return }
    Write-Host ("  FAILED: {0} (winget exit 0x{1:X8})" -f $Id, [int32]$Code) -ForegroundColor Red
    $script:FailedPackages += $Id
}

# The status windows.ps1 ends with: 1, after naming every failed id, or 0.
function Get-WingetExitStatus {
    if ($script:FailedPackages.Count -eq 0) { return 0 }
    Write-Host ("`nwinget failed for: {0}" -f ($script:FailedPackages -join ', ')) -ForegroundColor Red
    return 1
}
