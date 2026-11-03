<#
.SYNOPSIS
    Install the dsh-harness skill for Codex (and optionally Claude Code).

.DESCRIPTION
    Copies skills\dsh-harness from this repository into the host skills directory.
    Defaults to Codex (~/.codex/skills). Use -Target claude to install for
    Claude Code, or -Target both. Existing installs are overwritten ("update in
    place") after a warning; use -Force to skip the prompt.

.PARAMETER Target
    codex | claude | both. Default: codex.

.PARAMETER Force
    Overwrite an existing installation without prompting.

.PARAMETER RepoRoot
    Repository root that contains skills\dsh-harness. Default: this script's directory.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -Target both -Force
#>
[CmdletBinding()]
param(
    [ValidateSet('codex', 'claude', 'both')]
    [string]$Target = 'codex',
    [switch]$Force,
    [string]$RepoRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$source = Join-Path $RepoRoot 'skills\dsh-harness'
if (-not (Test-Path (Join-Path $source 'SKILL.md'))) {
    throw "SKILL.md not found under $source. Run this script from the repository root or pass -RepoRoot."
}

function Install-Skill {
    param([string]$Name, [string]$DestinationRoot, [string]$Source)

    $destination = Join-Path $DestinationRoot 'dsh-harness'
    Write-Host "Installing $Name skill -> $destination"

    if (Test-Path $destination) {
        if (-not $Force) {
            $answer = Read-Host "The skill already exists at '$destination'. Overwrite? [y/N]"
            if ($answer -notmatch '^(y|yes)$') {
                Write-Host 'Skipped.'
                return
            }
        }
        Remove-Item -Recurse -Force $destination
    }

    New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null
    Copy-Item -Recurse -Force $Source $destination

    if (Test-Path (Join-Path $destination 'SKILL.md')) {
        Write-Host "  OK: SKILL.md present" -ForegroundColor Green
    } else {
        throw "Install failed: SKILL.md missing at $destination"
    }
}

$homeDir = $env:USERPROFILE
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $homeDir '.codex' }

if ($Target -in @('codex', 'both')) {
    Install-Skill -Name 'Codex' -DestinationRoot (Join-Path $codexHome 'skills') -Source $source
    Write-Host "Codex will discover it as `$dsh-harness." -ForegroundColor Cyan
}

if ($Target -in @('claude', 'both')) {
    Install-Skill -Name 'Claude Code' -DestinationRoot (Join-Path $homeDir '.claude\skills') -Source $source
    Write-Host 'Claude Code auto-loads it as dsh-harness@skills-dir on the next session (or /reload-plugins).' -ForegroundColor Cyan
}

Write-Host 'Done.'
