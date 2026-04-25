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

function Install-WingetPackage {
    param([string]$Id)

    $installed = winget list --exact --id $Id 2>$null
    if ($LASTEXITCODE -eq 0 -and ($installed | Select-String -Pattern $Id -Quiet)) {
        winget upgrade --exact --id $Id --accept-source-agreements --accept-package-agreements
    }
    else {
        winget install --exact --id $Id --accept-source-agreements --accept-package-agreements
    }
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
Repair-DockerDesktopOwnership
Install-WingetPackage 'Docker.DockerDesktop'
Install-WingetPackage 'wez.wezterm'

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
Install-WingetPackage 'Spotify.Spotify'

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
Write-Step 'Setup complete'
