# Extracts the game's own Tanoa overview picture into the gitignored reference/ folder,
# so tools/plot_round.py can use it as a terrain background. Bohemia's file: never commit it.

param(
    [string]$ArmaDir = 'D:\SteamLibrary\steamapps\common\Arma 3',
    [string]$Hemtt = 'C:\Users\smith\AppData\Local\Microsoft\WinGet\Packages\BrettMayson.HEMTT_Microsoft.Winget.Source_8wekyb3d8bbwe\hemtt.exe'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'reference\map'
$pbo = Join-Path $ArmaDir 'Expansion\Addons\map_tanoabuka_data.pbo'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$paa = Join-Path $outDir 'tanoa_picturemap.paa'
$png = Join-Path $outDir 'tanoa_picturemap.png'

& $Hemtt utils pbo extract $pbo 'pictureMap_ca.paa' $paa
if ($LASTEXITCODE -ne 0) { throw 'HEMTT could not extract the picture map.' }
& $Hemtt utils paa convert $paa $png
if ($LASTEXITCODE -ne 0) { throw 'HEMTT could not convert the picture map.' }

Write-Output "Wrote $png"
