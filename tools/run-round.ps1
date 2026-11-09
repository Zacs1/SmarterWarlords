# Runs one unattended Warlords round on the dedicated server, vanilla, no players.
#
#   powershell -ExecutionPolicy Bypass -File tools\run-round.ps1 -DurationMinutes 45
#
# Stops at round end or after the duration, whichever comes first. The server is held in a Windows
# job object, so it dies with this script even if the script is killed.
# Vanilla unless -Mods names the CBA_A3 and LAMBS stable Workshop items, which are read in place.
# Exit codes: 0 finished, 2 mission never started, 3 server exited early, 4 server install changed.
#
# Up to three rounds can run at once. Each takes a free slot, which gives it its own port and mission
# folder. -Solo needs a machine with no other server and holds every slot, for rounds whose performance
# and balance numbers must not be skewed.

param(
    [Parameter(Mandatory = $true)][double]$DurationMinutes,
    [string]$Name = 'round',
    [string]$ServerDir = 'C:\Program Files (x86)\Steam\steamapps\common\Arma 3 Server',
    [switch]$Solo,
    [int]$StartTimeoutSeconds = 300,
    [switch]$NoBuild,
    # Test scenario from tests/mission_overlay/swl/scenarios, and settings overrides ("a=1;b=[2]").
    [string]$Scenario = '',
    [string]$Overrides = '',
    # Lobby parameter values, e.g. "BIS_WLFTEnabled=4,BIS_WLStartCP=5000". BIS_WLAIVoting defaults to 1.
    [string]$Params = 'BIS_WLFTEnabled=4,BIS_WLAIVoting=1',
    # Workshop item IDs to load, comma-separated. Only the mods allowed below can be named; the default is none.
    [string]$Mods = '',
    [string]$WorkshopDir = 'D:\SteamLibrary\steamapps\workshop\content\107410'
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class SwlJob
{
    [StructLayout(LayoutKind.Sequential)]
    struct BasicLimit
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct IoCounters
    {
        public ulong a, b, c, d, e, f;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct ExtendedLimit
    {
        public BasicLimit Basic;
        public IoCounters Io;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateJobObject(IntPtr attributes, string name);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref ExtendedLimit info, int size);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    public static IntPtr KillOnClose(IntPtr process)
    {
        IntPtr job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
        ExtendedLimit info = new ExtendedLimit();
        info.Basic.LimitFlags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if (!SetInformationJobObject(job, 9, ref info, Marshal.SizeOf(typeof(ExtendedLimit))))
            throw new System.ComponentModel.Win32Exception();
        if (!AssignProcessToJobObject(job, process))
            throw new System.ComponentModel.Win32Exception();
        return job;
    }
}
'@

function Get-InstallSnapshot {
    # Metadata of every file in the server install except mpmissions.
    $prefix = $ServerDir.TrimEnd('\').Length + 1
    Get-ChildItem -LiteralPath $ServerDir -Recurse -File -Force |
        Where-Object { $_.FullName.Substring($prefix) -notmatch '^(?i)mpmissions\\' } |
        ForEach-Object { '{0}|{1}|{2}' -f $_.FullName.Substring($prefix), $_.Length, $_.LastWriteTimeUtc.Ticks } |
        Sort-Object
}

function Read-NewLines {
    param([string]$Path, [ref]$Offset)
    $stream = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite,Delete')
    try {
        if ($stream.Length -le $Offset.Value) { return @() }
        [void]$stream.Seek($Offset.Value, 'Begin')
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd()
        $Offset.Value = $stream.Length
        return $text -split "`r?`n"
    } finally {
        $stream.Dispose()
    }
}

$root = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $ServerDir 'arma3server_x64.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw "Server exe not found: $exe" }

# Slots: 2402, 2412, 2422. Arma also uses the few ports above each one. A slot is held by an open
# exclusive file, which Windows releases even if this script is killed.
$maxServers = 3
$running = @(Get-CimInstance Win32_Process -Filter "Name='arma3server_x64.exe'")
if ($Solo -and $running.Count -gt 0) { throw "-Solo needs no other server running (PID $($running.ProcessId -join ', '))." }
if ($running.Count -ge $maxServers) { throw "$($running.Count) servers are already running; the limit is $maxServers." }
$usedPorts = @($running | ForEach-Object { if ($_.CommandLine -match '-port=(\d+)') { [int]$Matches[1] } })

$slotsDir = Join-Path $root 'tests\server\runs'
New-Item -ItemType Directory -Force -Path $slotsDir | Out-Null
$slotLocks = @()
$slot = -1
for ($i = 0; $i -lt $maxServers; $i++) {
    if ($usedPorts -contains (2402 + 10 * $i)) { continue }
    try {
        $slotLocks += [System.IO.File]::Open((Join-Path $slotsDir ".slot$i.lock"), 'OpenOrCreate', 'ReadWrite', 'None')
    } catch [System.IO.IOException] {
        continue
    }
    if ($slot -lt 0) { $slot = $i }
    if (-not $Solo) { break }
}
if ($slot -lt 0 -or ($Solo -and $slotLocks.Count -lt $maxServers)) { throw 'No free server slot.' }
$Port = 2402 + 10 * $slot
$mission = if ($slot -eq 0) { 'SWL_Test.Tanoa' } else { "SWL_Test_$slot.Tanoa" }

if (-not $NoBuild) {
    & (Join-Path $PSScriptRoot 'build-test-mission.ps1') -Scenario $Scenario -Overrides $Overrides -MissionName $mission
}
& (Join-Path $PSScriptRoot 'install-test-mission.ps1') -ServerDir $ServerDir -MissionName $mission

$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$runDir = Join-Path $root "tests\server\runs\${stamp}_$Name"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

# Per-run server.cfg: the template with this run's lobby parameters.
$template = Join-Path $root 'tests\server\server.cfg'
$cfg = Join-Path $runDir 'server.cfg'
$paramLines = ($Params -split ',' | Where-Object { $_.Trim() } | ForEach-Object {
    $k, $v = $_ -split '=', 2
    '				{0} = {1};' -f $k.Trim(), $v.Trim()
}) -join "`r`n"
$cfgText = (Get-Content -LiteralPath $template -Raw) -replace '@PARAMS@', $paramLines -replace '@MISSION@', $mission
Set-Content -LiteralPath $cfg -Value $cfgText -Encoding ascii
$basic = Join-Path $root 'tests\server\basic.cfg'

# Only these two may load. LAMBS DEV, ASR AI3, Vcom and Advanced AI Command are never allowed.
$allowedMods = @{ '450814997' = 'CBA_A3'; '1858075458' = 'LAMBS stable' }
$modPaths = @()
foreach ($id in ($Mods -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    if (-not $allowedMods.ContainsKey($id)) { throw "Workshop item $id is not on the allowed list." }
    $path = Join-Path $WorkshopDir $id
    if (-not (Test-Path -LiteralPath $path)) { throw "Workshop item not found: $path" }
    $modPaths += $path
}

$argLine = @(
    "-port=$Port",
    "`"-config=$cfg`"",
    "`"-cfg=$basic`"",
    "`"-profiles=$runDir`"",
    '-name=swl',
    '-autoInit',
    '-noSplash',
    '-world=empty'
) -join ' '
if ($modPaths.Count -gt 0) {
    $argLine += " `"-mod=$($modPaths -join ';')`""
}

$before = Get-InstallSnapshot
$server = $null
$job = [IntPtr]::Zero
$exitCode = 0
$rpt = $null

try {
    Write-Output "Starting server: $exe $argLine"
    $server = Start-Process -FilePath $exe -ArgumentList $argLine -WorkingDirectory $ServerDir -PassThru -WindowStyle Minimized
    $job = [SwlJob]::KillOnClose($server.Handle)
    Set-Content -LiteralPath (Join-Path $runDir 'server.pid') -Value $server.Id -Encoding ascii

    $started = Get-Date
    $deadline = $started.AddMinutes($DurationMinutes)
    $startDeadline = $started.AddSeconds($StartTimeoutSeconds)
    $offset = [long]0
    $sawStart = $false
    $sawEnd = $false
    $endAt = $null
    $lastT = '-'
    $captures = 0
    $lastStatus = Get-Date

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5

        if ($server.HasExited) {
            Write-Output "Server exited on its own with code $($server.ExitCode)."
            if (-not $sawEnd) { $exitCode = 3 }
            break
        }

        if (-not $rpt) {
            $found = Get-ChildItem -LiteralPath $runDir -Filter '*.rpt' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime | Select-Object -Last 1
            if ($found) { $rpt = $found.FullName }
        }

        if ($rpt) {
            foreach ($line in (Read-NewLines -Path $rpt -Offset ([ref]$offset))) {
                if ($line -match 'SWL\|START\|') { $sawStart = $true; Write-Output "Mission started: $line" }
                if ($line -match 'SWL\|TICK\|t=(\d+)') { $lastT = $Matches[1] }
                if ($line -match 'SWL\|(CAPTURE|TARGET)\|') { Write-Output $line }
                if ($line -match '(Error in expression|SWL\|C_READY)') { Write-Output $line }
                if ($line -match 'SWL\|CAPTURE\|') { $captures++ }
                if ($line -match 'SWL\|(ROUNDEND|ENDED)\|' -and -not $sawEnd) {
                    Write-Output $line
                    $sawEnd = $true
                    $endAt = (Get-Date).AddSeconds(15)
                }
            }
        }

        if (-not $sawStart -and (Get-Date) -gt $startDeadline) {
            Write-Output "No SWL|START line within $StartTimeoutSeconds seconds. The mission did not start."
            $exitCode = 2
            break
        }

        if ($sawEnd -and (Get-Date) -gt $endAt) { break }

        if (((Get-Date) - $lastStatus).TotalSeconds -ge 60) {
            $lastStatus = Get-Date
            $elapsed = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
            Write-Output "[$elapsed min] mission time ${lastT}s, captures: $captures"
        }
    }
}
finally {
    if ($server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -Force -Confirm:$false -ErrorAction SilentlyContinue
        [void]$server.WaitForExit(30000)
    }
    Remove-Item -LiteralPath (Join-Path $runDir 'server.pid') -ErrorAction SilentlyContinue -Confirm:$false
}

if ($server -and (Get-Process -Id $server.Id -ErrorAction SilentlyContinue)) {
    Write-Output "WARNING: this round's server (PID $($server.Id)) is still running."
}
$slotLocks | ForEach-Object { $_.Dispose() }

$after = Get-InstallSnapshot
$diff = Compare-Object -ReferenceObject $before -DifferenceObject $after
if ($diff) {
    Write-Output 'WARNING: files outside mpmissions changed in the server install:'
    $diff | ForEach-Object { Write-Output ('  {0} {1}' -f $_.SideIndicator, $_.InputObject) }
    if ($exitCode -eq 0) { $exitCode = 4 }
} else {
    Write-Output 'Server install check: nothing outside mpmissions changed.'
}

if (-not $rpt) {
    $found = Get-ChildItem -LiteralPath $runDir -Filter '*.rpt' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime | Select-Object -Last 1
    if ($found) { $rpt = $found.FullName }
}

Write-Output "Run folder: $runDir"
Write-Output "Log: $rpt"
exit $exitCode
