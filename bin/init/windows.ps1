#Requires -Version 5.1
<#
.SYNOPSIS
    Setup script for Windows. Installs GUI applications via winget.
.DESCRIPTION
    Companion to wsl.sh which handles the CLI environment inside WSL.
    Run this script directly on Windows (PowerShell) to install desktop
    applications that correspond to Brewfile-cask and Brewfile-mas on macOS.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File windows.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Re-launch elevated if not already. Docker Desktop and other machine-scope
# winget packages require Administrator; without this the install aborts with
# "must be owned by an elevated account".
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Re-launching with Administrator privileges...' -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    exit
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n--- $Message ---" -ForegroundColor Cyan
}

. (Join-Path $PSScriptRoot 'winget-result.ps1')

# --silent: suppress the installer's own UI. The default only shows progress,
# and on CI the GnuPG installer sat waiting for six hours until the job was
# cancelled -- and, it turned out, still hangs with --silent; see GnuPG below.
# --disable-interactivity: no winget prompts either.
$WingetFlags = '--exact --silent --disable-interactivity --accept-source-agreements --accept-package-agreements'

function Install-WingetPackage {
    param(
        [string]$Id,
        # Some installers (e.g. Spotify) check the process token and refuse to
        # run elevated — --scope user alone is not enough. 'user' de-elevates
        # via a temporary scheduled task so the installer sees a standard token.
        [ValidateSet('any', 'user')]
        [string]$Scope = 'any',
        # Why the package cannot be installed on the CI runner. Given, the
        # package is skipped there, with that reason printed; a real machine
        # still installs it.
        [string]$SkipOnCI = ''
    )

    if ($SkipOnCI -and $env:GITHUB_ACTIONS -eq 'true') {
        Write-Host "  skipping $Id on CI ($SkipOnCI)" -ForegroundColor Yellow
        return
    }

    if ($Scope -eq 'user') {
        $taskName = 'DotfilesWingetInstall'
        $wingetArgs = "install --id $Id --scope user $WingetFlags"
        $action = New-ScheduledTaskAction -Execute 'winget' -Argument $wingetArgs
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $taskPrincipal -Force | Out-Null
        Start-ScheduledTask -TaskName $taskName
        Write-Host "  Installing $Id as standard user (via scheduled task)..."
        do { Start-Sleep -Seconds 2 }
        while ((Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue).State -eq 'Running')
        $result = (Get-ScheduledTaskInfo -TaskName $taskName).LastTaskResult
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        # 0x41303 SCHED_S_TASK_HAS_NOT_RUN: an Interactive task needs a logged-on
        # user, which a CI runner may not have. Not winget's answer, so it is
        # reported rather than counted.
        if ($result -eq 0x41303) {
            Write-Host "  warning: the task for $Id never ran (no interactive session?)" -ForegroundColor Yellow
            return
        }
        Confirm-WingetResult $Id $result
        return
    }

    $installed = winget list --exact --id $Id 2>$null
    $flags = $WingetFlags -split ' '
    if ($LASTEXITCODE -eq 0 -and ($installed | Select-String -Pattern $Id -Quiet)) {
        winget upgrade --id $Id @flags
    }
    else {
        winget install --id $Id @flags
    }
    Confirm-WingetResult $Id $LASTEXITCODE
}

function Repair-DockerDesktopOwnership {
    # Docker Desktop's installer rejects ProgramData\DockerDesktop unless owned by Administrators/SYSTEM.
    $dir = 'C:\ProgramData\DockerDesktop'
    if (-not (Test-Path $dir)) { return }

    $adminSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $systemSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
    $ownerSid = (Get-Acl $dir).GetOwner([System.Security.Principal.SecurityIdentifier])
    if ($ownerSid -eq $adminSid -or $ownerSid -eq $systemSid) { return }

    Write-Host "Repairing ownership on $dir (current owner: $((Get-Acl $dir).Owner))" -ForegroundColor Yellow
    takeown /F $dir /R /A /D Y | Out-Null
    icacls $dir /grant 'Administrators:F' /T /C | Out-Null
    # Remove the directory so the installer recreates it with correct ACLs.
    # Fixing ownership alone is not enough — the installer also checks ACL entries.
    Remove-Item $dir -Recurse -Force
}

# ------------------------------------------------------------------
# Preflight
# ------------------------------------------------------------------
Write-Step 'Checking winget'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error 'winget is not installed. Install App Installer from the Microsoft Store.'
}

# ------------------------------------------------------------------
# Browsers
# ------------------------------------------------------------------
Write-Step 'Installing browsers'
Install-WingetPackage 'Google.Chrome'

# ------------------------------------------------------------------
# Development
# ------------------------------------------------------------------
Write-Step 'Installing development tools'
Install-WingetPackage 'Microsoft.VisualStudioCode'
# Ownership repair must run before install; see Repair-DockerDesktopOwnership.
Repair-DockerDesktopOwnership
Install-WingetPackage 'Docker.DockerDesktop'
Install-WingetPackage 'wez.wezterm'
# On CI the GnuPG installer hangs under winget despite --silent and
# --disable-interactivity: every run since 2026-04 sat on it until the step's
# 75-minute limit, so nothing after it was ever exercised. Skipped there only;
# a real machine still installs it.
Install-WingetPackage 'GnuPG.GnuPG' -SkipOnCI 'its installer hangs there'
Install-WingetPackage 'Tailscale.Tailscale'

# ------------------------------------------------------------------
# Communication
# ------------------------------------------------------------------
Write-Step 'Installing communication apps'
Install-WingetPackage 'SlackTechnologies.Slack'
Install-WingetPackage 'Zoom.Zoom'
Install-WingetPackage 'Microsoft.Teams'

# ------------------------------------------------------------------
# Productivity & Utilities
# ------------------------------------------------------------------
Write-Step 'Installing productivity tools'
Install-WingetPackage 'AgileBits.1Password'
Install-WingetPackage 'Google.GoogleDrive'
# On CI its scheduled task ended 0x80070002 (file not found) -- most likely
# winget itself, unseen by the de-elevated task; not confirmed, and not known
# whether a real machine hits it too.
Install-WingetPackage 'Spotify.Spotify' -Scope user -SkipOnCI 'its de-elevated task fails with 0x80070002 there'

# ------------------------------------------------------------------
# Automation
# ------------------------------------------------------------------
Write-Step 'Installing automation tools'
Install-WingetPackage 'AutoHotkey.AutoHotkey'

# ------------------------------------------------------------------
# Input
# ------------------------------------------------------------------
Write-Step 'Installing input method'
Install-WingetPackage 'Google.JapaneseIME'

# ------------------------------------------------------------------
# Key remapping (Scancode Map)
# ------------------------------------------------------------------
Write-Step 'Remapping CapsLock to Left Ctrl (Scancode Map)'

# Remap at the keyboard driver level so the IME never sees a CapsLock event.
# AHK's hook-level remap (CapsLock::LCtrl) cannot prevent Google Japanese
# Input from treating CapsLock as the Eisu (英数) key.
# Requires a reboot to take effect.
$scancodeMap = [byte[]](
    0x00, 0x00, 0x00, 0x00,  # Header Version
    0x00, 0x00, 0x00, 0x00,  # Header Flags
    0x02, 0x00, 0x00, 0x00,  # Number of entries (1 remap + 1 null terminator)
    0x1D, 0x00, 0x3A, 0x00,  # CapsLock (0x003A) -> Left Ctrl (0x001D)
    0x00, 0x00, 0x00, 0x00   # Null terminator
)
$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'
# Get-ItemProperty returns an object without the property when the value is
# absent, which Set-StrictMode -Version Latest treats as an error.
try { $current = Get-ItemPropertyValue -Path $regPath -Name 'Scancode Map' }
catch { $current = $null }
if (-not $current -or (Compare-Object $scancodeMap $current)) {
    Set-ItemProperty -Path $regPath -Name 'Scancode Map' -Value $scancodeMap -Type Binary
    Write-Host '  Scancode Map written. A reboot is required for this to take effect.' -ForegroundColor Yellow
}
else {
    Write-Host '  Scancode Map already set.'
}

# ------------------------------------------------------------------
# AutoHotkey script deployment
# ------------------------------------------------------------------
Write-Step 'Deploying AutoHotkey key remap script'

# Copy rather than symlink — the dotfiles repo lives in WSL and Windows AHK
# cannot follow WSL symlinks or UNC paths reliably.
$ahkSource = Join-Path $PSScriptRoot '..\..\autohotkey\keyremap.ahk'
$ahkDest   = Join-Path $env:USERPROFILE 'Documents\AutoHotkey'
$ahkFile   = Join-Path $ahkDest 'keyremap.ahk'
$startupDir = [Environment]::GetFolderPath('Startup')
$shortcut   = Join-Path $startupDir 'keyremap.lnk'

if (-not (Test-Path $ahkDest)) {
    New-Item -ItemType Directory -Path $ahkDest -Force | Out-Null
}
Copy-Item -Path $ahkSource -Destination $ahkFile -Force
Write-Host "  Copied keyremap.ahk -> $ahkFile"

# A .lnk in the Startup folder makes Windows launch the script on login.
$WshShell = New-Object -ComObject WScript.Shell
$lnk = $WshShell.CreateShortcut($shortcut)
$lnk.TargetPath = $ahkFile
$lnk.Save()
Write-Host "  Created startup shortcut -> $shortcut"

# Start immediately so the user doesn't have to re-login.
# #SingleInstance Force in the script ensures duplicates are harmless.
Start-Process -FilePath $ahkFile
Write-Host "  Started keyremap.ahk"

# ------------------------------------------------------------------
# WezTerm configuration
# ------------------------------------------------------------------
Write-Step 'Pointing WezTerm to WSL dotfiles config'

# Set WEZTERM_CONFIG_FILE to the WSL-side wezterm.lua via UNC path so
# edits in WSL are reflected immediately (WezTerm auto-reloads on change).
# AHK must be copied because it cannot read UNC paths, but WezTerm can.
$wslConfigPath = (wsl.exe -- sh -c 'wslpath -w ~/dotfiles/wezterm.lua' 2>$null | Select-Object -Last 1)
if ($wslConfigPath) {
    $wslConfigPath = $wslConfigPath.Trim()
    [Environment]::SetEnvironmentVariable('WEZTERM_CONFIG_FILE', $wslConfigPath, 'User')
    Write-Host "  WEZTERM_CONFIG_FILE = $wslConfigPath"
}
else {
    Write-Host '  warning: could not resolve WSL path for wezterm.lua' -ForegroundColor Yellow
}

# ------------------------------------------------------------------
$status = Get-WingetExitStatus
if ($status -ne 0) { exit $status }
Write-Step 'Setup complete'
