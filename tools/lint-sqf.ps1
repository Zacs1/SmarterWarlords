# Fast syntax check of the commander and test scripts with HEMTT, without starting the game.
# Builds a throwaway HEMTT project in a temp folder (nothing is written to the repo).
#   powershell -ExecutionPolicy Bypass -File tools\lint-sqf.ps1

$ErrorActionPreference = 'Stop'

$hemtt = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\BrettMayson.HEMTT_Microsoft.Winget.Source_8wekyb3d8bbwe\hemtt.exe"
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([System.IO.Path]::GetTempPath()) 'swl-hemtt-check'
if (Test-Path $work) { Remove-Item -Recurse -Force -LiteralPath $work -Confirm:$false }

$addon = Join-Path $work 'addons\main'
New-Item -ItemType Directory -Force -Path (Join-Path $work '.hemtt'), $addon | Out-Null
Set-Content -LiteralPath (Join-Path $work '.hemtt\project.toml') -Encoding ascii -Value @'
name = "swl"
prefix = "swl"
mainprefix = "swl"

[version]
major = 0
minor = 1
patch = 0
build = 0
git_hash = 0
'@
Set-Content -LiteralPath (Join-Path $addon '$PBOPREFIX$') -Value 'swl\addons\main' -Encoding ascii
Set-Content -LiteralPath (Join-Path $addon 'config.cpp') -Encoding ascii -Value @'
class CfgPatches { class swl_main { units[] = {}; weapons[] = {}; requiredVersion = 2.22; requiredAddons[] = {}; }; };
'@
Copy-Item -Recurse -Force -Path (Join-Path $root 'commander\swlc') -Destination $addon
Copy-Item -Recurse -Force -Path (Join-Path $root 'tests\mission_overlay\swl') -Destination $addon

Push-Location $work
try {
    & $hemtt check
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
