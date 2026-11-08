# Runs one unattended Warlords round on the dedicated server, vanilla, no players.
#
#   powershell -ExecutionPolicy Bypass -File tools\run-round.ps1 -DurationMinutes 45
#
# Stops at round end or after the duration, whichever comes first. The server is held in a Windows
# job object, so it dies with this script even if the script is killed.
# Exit codes: 0 finished, 2 mission never started, 3 server exited early, 4 server install changed.

param(
    [Parameter(Mandatory = $true)][double]$DurationMinutes,
    [string]$Name = 'round',
    [string]$ServerDir = 'C:\Program Files (x86)\Steam\steamapps\common\Arma 3 Server',
    [int]$Port = 2402,
    [int]$StartTimeoutSeconds = 300,
    [switch]$NoBuild
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

$running = Get-Process -Name 'arma3server_x64' -ErrorAction SilentlyContinue
if ($running) { throw "An arma3server_x64 process is already running (PID $($running.Id -join ', ')). Stop it first." }

if (-not $NoBuild) {
    & (Join-Path $PSScriptRoot 'build-test-mission.ps1')
}
& (Join-Path $PSScriptRoot 'install-test-mission.ps1') -ServerDir $ServerDir

$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$runDir = Join-Path $root "tests\server\runs\${stamp}_$Name"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$cfg = Join-Path $root 'tests\server\server.cfg'
$basic = Join-Path $root 'tests\server\basic.cfg'

# Nothing loads with -mod, so no Workshop mod can load: vanilla only.
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

if (Get-Process -Name 'arma3server_x64' -ErrorAction SilentlyContinue) {
    Write-Output 'WARNING: an arma3server_x64 process is still running.'
}

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
