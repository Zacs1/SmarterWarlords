# Copies the built test mission into the dedicated server's MPMissions folder.
# That folder is the only part of the server install this project may write to.

param(
    [string]$ServerDir = 'C:\Program Files (x86)\Steam\steamapps\common\Arma 3 Server'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'tests\missions\SWL_Test.Tanoa'
$mpm = Join-Path $ServerDir 'mpmissions'
$dest = Join-Path $mpm 'SWL_Test.Tanoa'

if (-not (Test-Path (Join-Path $src 'mission.sqm'))) { throw "Build the mission first: $src is missing." }
if (-not (Test-Path $mpm)) { throw "MPMissions folder not found at $mpm." }

if (Test-Path -LiteralPath $dest) { Remove-Item -Recurse -Force -LiteralPath $dest -Confirm:$false }
Copy-Item -Recurse -LiteralPath $src -Destination $dest

Write-Output "Installed $dest"
