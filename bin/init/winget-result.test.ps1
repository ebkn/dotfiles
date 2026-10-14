# winget-result.test.ps1 -- pins which winget exit codes windows.ps1 counts as
# a failed package. Both mistakes are silent: an extra "ok" code hides a real
# failure behind a green run, a missing one turns CI red for good. Installs
# nothing; runs on Windows PowerShell 5.1 (CI) and pwsh 7.
#
# Run: powershell -ExecutionPolicy Bypass -File bin\init\winget-result.test.ps1
# From macOS or Linux (amd64 image; under qemu pwsh now and then crashes at
# startup, so rerun once before believing a failure):
#   docker run --rm -v "$PWD/bin/init:/w:ro" mcr.microsoft.com/powershell:latest \
#     pwsh -NoProfile -File /w/winget-result.test.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'winget-result.ps1')

$fails = 0
function Expect {
    param([string]$Name, [long]$Code, [bool]$Failed)
    $got = Test-WingetFailure $Code
    if ($got -eq $Failed) { Write-Output "ok   $Name" }
    else { Write-Output "FAIL $Name (counted as failed: $got)"; $script:fails++ }
}

# winget's own exit status is signed; a scheduled task's LastTaskResult is the
# same 32 bits unsigned, so every code is checked in both forms.
$unsigned = { param([long]$c) if ($c -lt 0) { $c + 4294967296 } else { $c } }
$ok = @{
    'success'                           = 0
    'UPDATE_NOT_APPLICABLE'             = -1978335189
    'PACKAGE_ALREADY_INSTALLED'         = -1978335135
    'INSTALL_REBOOT_REQUIRED_TO_FINISH' = -1978334967
    'UPGRADE_VERSION_NOT_NEWER'         = -1978335153
}
foreach ($k in $ok.Keys) {
    Expect "$k is not a failure" $ok[$k] $false
    Expect "$k is not a failure, unsigned" (& $unsigned $ok[$k]) $false
}
$bad = @{
    'a plain non-zero exit'                = 1
    'an MSI install failure (1603)'        = 1603
    'INSTALL_REBOOT_REQUIRED_FOR_INSTALL'  = -1978334966
    'NO_APPLICABLE_INSTALLER'              = -1978335216
    'INSTALL_PACKAGE_IN_USE'               = -1978334975
}
foreach ($k in $bad.Keys) {
    Expect "$k is a failure" $bad[$k] $true
    Expect "$k is a failure, unsigned" (& $unsigned $bad[$k]) $true
}

# Collected, not replaced: windows.ps1 reports every failed id at the end.
$script:FailedPackages = @()
Confirm-WingetResult 'one' 1 6>$null
Confirm-WingetResult 'fine' 0 6>$null
Confirm-WingetResult 'two' 1603 6>$null
if (($script:FailedPackages -join ',') -eq 'one,two') { Write-Output 'ok   failures accumulate, in order, successes left out' }
else { Write-Output "FAIL failures accumulate: $($script:FailedPackages -join ',')"; $fails++ }

# The verdict windows.ps1 exits with. Without it the collecting above is for
# nothing: the run ends "Setup complete" and green, which is the bug it fixed.
$script:FailedPackages = @()
$out = Get-WingetExitStatus 6>&1
if ("$out" -eq '0') { Write-Output 'ok   no failures: exit status 0, and nothing said' }
else { Write-Output "FAIL no failures: got '$out'"; $fails++ }
$script:FailedPackages = @('Zoom.Zoom', 'GnuPG.GnuPG')
$out = @(Get-WingetExitStatus 6>&1)
$status = $out | Where-Object { $_ -is [int] }
$said = ($out | Where-Object { $_ -isnot [int] }) -join ''
if ($status -eq 1) { Write-Output 'ok   with failures: exit status 1' }
else { Write-Output "FAIL with failures: exit status '$status'"; $fails++ }
if ($said -like '*winget failed for: Zoom.Zoom, GnuPG.GnuPG*') { Write-Output 'ok   and every failed id is named' }
else { Write-Output "FAIL and every failed id is named: '$said'"; $fails++ }

if ($fails -gt 0) { Write-Output "$fails failure(s)"; exit 1 }
Write-Output 'PASS'
