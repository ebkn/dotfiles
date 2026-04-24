#Requires -Version 5.1
<#
.SYNOPSIS
    Setup script for Windows. Installs GUI applications via winget.
.DESCRIPTION
    Companion to wsl.sh which handles the CLI environment inside WSL.
    Run this script directly on Windows (PowerShell) to install desktop
    applications that correspond to Brewfile-cask and Brewfile-mas on macOS.
.EXAMPLE
    iex (irm 'https://raw.githubusercontent.com/ebkn/dotfiles/main/bin/init/windows.ps1')
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File windows.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
Install-WingetPackage 'Amazon.Kindle'

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
