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

function Confirm-WingetResult {
    param([string]$Id, [long]$Code)
    # A scheduled task reports the code as an unsigned 32-bit value.
    if ($Code -gt [int32]::MaxValue) { $Code -= 4294967296 }
    if ($WingetOkCodes -contains $Code) { return }
    Write-Host ("  FAILED: {0} (winget exit 0x{1:X8})" -f $Id, [int32]$Code) -ForegroundColor Red
    $script:FailedPackages += $Id
}
