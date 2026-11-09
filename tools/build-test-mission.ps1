# Builds tests/missions/SWL_Test.Tanoa from the stock Tanoa scenario in reference/, the commander
# and tests/mission_overlay/. The output is derived from a Bohemia scenario, so it is gitignored.
#   -Scenario gate0        runs tests/mission_overlay/swl/scenarios/gate0.sqf as the test scenario
#   -Overrides "a=1;b=[2]" adds settings overrides (SQF expressions separated by ;)

param(
    [string]$Scenario = '',
    [string]$Overrides = '',
    [string]$MissionName = 'SWL_Test.Tanoa'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$stock = Join-Path $root 'reference\missions_f_warlords\MPScenarios\MP_Warlords_03.Tanoa'
$commander = Join-Path $root 'commander'
$overlay = Join-Path $root 'tests\mission_overlay'
$missions = Join-Path $root 'tests\missions'
$out = Join-Path $missions $MissionName

if (-not (Test-Path (Join-Path $stock 'mission.sqm'))) {
    throw "Stock scenario not found at $stock. Unpack missions_f_warlords.pbo into reference/ first."
}

New-Item -ItemType Directory -Force -Path $missions | Out-Null
if (Test-Path $out) { Remove-Item -Recurse -Force -LiteralPath $out -Confirm:$false }

Copy-Item -Recurse -LiteralPath $stock -Destination $out
Copy-Item -Recurse -Force -Path (Join-Path $commander '*') -Destination $out
Copy-Item -Recurse -Force -Path (Join-Path $overlay '*') -Destination $out

$swl = Join-Path $out 'swl'
if ($Scenario) {
    $source = Join-Path $swl "scenarios\$Scenario.sqf"
    if (-not (Test-Path -LiteralPath $source)) { throw "No scenario $Scenario at $source" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $swl 'scenario.sqf')
}
if ($Overrides) {
    $pairs = ($Overrides -split ';' | Where-Object { $_.Trim() } | ForEach-Object {
        $k, $v = $_ -split '=', 2
        '["{0}",{1}]' -f $k.Trim(), $v.Trim()
    }) -join ','
    Set-Content -LiteralPath (Join-Path $swl 'overrides.sqf') -Value "SWLC_overrides = [$pairs];" -Encoding utf8
}

Write-Output "Built $out"
