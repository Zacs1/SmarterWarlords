# Builds the playable SmarterWarlords.Tanoa into the profile's mpmissions folder: the stock Tanoa
# Warlords scenario plus the commander, set up for hosted play. Nothing from the test overlay goes in.
#   -OutputFolder overrides where it is built (for a dry run).
#
# The result is derived from a Bohemia scenario, so it stays out of git. What changes from stock:
#   - Lobby parameters are copied into the scenario with Fast Travel defaulting to 4 and AI voting to on,
#     keeping Warlords' class order, plus an AI commander difficulty parameter at the end.
#   - The same two defaults are set on the Warlords init module in mission.sqm.
#   - disabledAI = 0, so empty slots are played by AI Warlords.
#   - enableDebugConsole = 1, so the host can turn the debug overlay on with SWLC_debug = true.
#   - Per-vehicle and per-guard log lines are off, because only the test analyser reads them.

param(
    [string]$OutputFolder = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Arma 3\mpmissions')
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$ref = Join-Path $root 'reference\missions_f_warlords'
$stock = Join-Path $ref 'MPScenarios\MP_Warlords_03.Tanoa'
$commander = Join-Path $root 'commander'
$out = Join-Path $OutputFolder 'SmarterWarlords.Tanoa'

if (-not (Test-Path (Join-Path $stock 'mission.sqm'))) {
    throw "Stock scenario not found at $stock. Unpack missions_f_warlords.pbo into reference/ first."
}

New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null
if (Test-Path $out) { Remove-Item -Recurse -Force -LiteralPath $out -Confirm:$false }
Copy-Item -Recurse -LiteralPath $stock -Destination $out
Copy-Item -Recurse -Force -Path (Join-Path $commander '*') -Destination $out

Set-Content -LiteralPath (Join-Path $out 'initServer.sqf') -Encoding ascii -Value 'SWLC_overrides = [["verboseLog", false]]; [] execVM "swlc\init.sqf";'

function Set-ClassDefault([string]$Text, [string]$Class, [int]$Value) {
    $pattern = "(?s)(class\s+$Class\s*\{.*?default\s*=\s*)-?\d+(\s*;)"
    if ($Text -notmatch $pattern) { throw "Parameter class $Class not found" }
    return [regex]::new($pattern).Replace($Text, ('${1}' + $Value + '${2}'), 1)
}

$params = Get-Content -Raw -LiteralPath (Join-Path $ref 'cfgMissionParams_subclasses.inc')
$params = Set-ClassDefault $params 'BIS_WLFTEnabled' 4
$params = Set-ClassDefault $params 'BIS_WLAIVoting' 1

$difficulty = @'

class SWLC_Difficulty
{
	title = "AI commander difficulty";
	values[] = {0, 1, 2};
	texts[] = {"Easy", "Normal", "Hard"};
	default = 1;
};

class SWLC_RoundTimeLimit
{
	title = "Round time limit";
	values[] = {0, 30, 45, 60, 90, 120};
	texts[] = {"Off", "30 minutes", "45 minutes", "60 minutes", "90 minutes", "120 minutes"};
	default = 0;
};
class SWLC_RulesVariant
{
	title = "Rules variant";
	values[] = {1, 0};
	texts[] = {"On", "Off"};
	default = 1;
};
'@

$descPath = Join-Path $out 'description.ext'
$desc = Get-Content -Raw -LiteralPath $descPath
$include = '#include "\A3\Missions_F_Warlords\cfgMissionParams.inc"'
if (-not $desc.Contains($include)) { throw 'Expected parameter include not found in description.ext' }
$block = "disabledAI = 0;`r`nenableDebugConsole = 1;`r`n`r`nclass Params`r`n{`r`n$params$difficulty`r`n};"
Set-Content -LiteralPath $descPath -Encoding ascii -Value $desc.Replace($include, $block)

function Set-ModuleValue([string]$Text, [string]$Property, [int]$Value) {
    $pattern = "(?s)(property=""$Property"";.*?\bvalue=)[^;]+(;)"
    if ($Text -notmatch $pattern) { throw "Module attribute $Property not found" }
    return [regex]::new($pattern).Replace($Text, ('${1}' + $Value + '${2}'), 1)
}

$sqmPath = Join-Path $out 'mission.sqm'
$sqm = Get-Content -Raw -LiteralPath $sqmPath
$sqm = Set-ModuleValue $sqm 'ModuleWLInit_F_FTEnabled' 4
$sqm = Set-ModuleValue $sqm 'ModuleWLInit_F_AIVoting' 1
# Its own name in the host list, otherwise it shows as a second "Warlords" next to the stock scenario.
if (-not $sqm.Contains('briefingName="@STR_A3_WL_modName";')) { throw 'Expected briefingName not found in mission.sqm' }
$sqm = $sqm.Replace('briefingName="@STR_A3_WL_modName";', 'briefingName="Smarter Warlords";')
Set-Content -LiteralPath $sqmPath -Encoding ascii -NoNewline -Value $sqm

Write-Output "Built $out"
