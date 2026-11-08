# Builds tests/missions/SWL_Test.Tanoa from the stock Tanoa scenario in reference/ plus tests/mission_overlay/.
# The output is derived from a Bohemia scenario, so it is gitignored and rebuilt on demand.

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$stock = Join-Path $root 'reference\missions_f_warlords\MPScenarios\MP_Warlords_03.Tanoa'
$overlay = Join-Path $root 'tests\mission_overlay'
$missions = Join-Path $root 'tests\missions'
$out = Join-Path $missions 'SWL_Test.Tanoa'

if (-not (Test-Path (Join-Path $stock 'mission.sqm'))) {
    throw "Stock scenario not found at $stock. Unpack missions_f_warlords.pbo into reference/ first."
}

New-Item -ItemType Directory -Force -Path $missions | Out-Null
if (Test-Path $out) { Remove-Item -Recurse -Force -LiteralPath $out -Confirm:$false }

Copy-Item -Recurse -LiteralPath $stock -Destination $out
Copy-Item -Recurse -Force -Path (Join-Path $overlay '*') -Destination $out

Write-Output "Built $out"
