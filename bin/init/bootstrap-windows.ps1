#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap script for a fresh Windows machine.
.DESCRIPTION
    Downloads and runs the Windows setup script directly from GitHub.
    No local clone is needed - windows.ps1 is self-contained.
.EXAMPLE
    iex (irm 'https://raw.githubusercontent.com/ebkn/dotfiles/main/bin/init/bootstrap-windows.ps1')
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Verify winget is available.
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error 'winget is not installed. Install App Installer from the Microsoft Store.'
}

$ScriptUrl = 'https://api.github.com/repos/ebkn/dotfiles/contents/bin/init/windows.ps1'
$Headers = @{ Accept = 'application/vnd.github.raw' }

Write-Host "`n--- Downloading setup script ---" -ForegroundColor Cyan
$Script = Invoke-RestMethod -Uri $ScriptUrl -Headers $Headers

Write-Host '--- Running setup ---' -ForegroundColor Cyan
Invoke-Expression $Script
