# Automated round tests

A round runs unattended on the dedicated server. A passive observer in the test mission writes structured lines to the RPT, and the tools judge the round from those lines.

```powershell
powershell -ExecutionPolicy Bypass -File tools\run-round.ps1 -DurationMinutes 45
python tools\analyse_round.py <path-to-rpt>
python tools\plot_round.py <path-to-rpt>
```

`run-round.ps1` prints the RPT path. Each run gets its own folder in `tests/server/runs/` (gitignored), which is also the server's profile folder, so saved scenario progress cannot leak between runs. The server stops at round end or after the duration. It sits in a Windows job object, so it also dies if the script is killed.

Options for `run-round.ps1`:

| Option | Meaning |
| --- | --- |
| `-Name x` | Suffix for the run folder |
| `-Scenario x` | Copies `mission_overlay/swl/scenarios/x.sqf` into the test mission |
| `-Overrides "a=1;b=[2]"` | Commander settings for this run only |
| `-Params "BIS_WLFTEnabled=4,BIS_WLAIVoting=1"` | Lobby parameter values |
| `-Mods "450814997,1858075458"` | Workshop items to load. Only CBA_A3 and LAMBS stable are allowed |
| `-NoBuild` | Uses the test mission as last built |

Scenario tests are short and end with `python tools\analyse_round.py <rpt> --gate <name>`. Gates are `gate0`, `phase1`, `gate2`, `phase2soak`, `phase3`, `phase4`, `phase6`, `partr` and `soakr`. The analyser exits 0 only if every check that ran passed.

The `sabotage` scenario is the resilience test and stays in the suite: it kills leaders, teleports groups into the sea, forest and rocks, deletes waypoints, flips and immobilises vehicles, scatters a squad and throws an error in one group's handling, then `--gate partr` checks each group is moving again within 3 minutes. Run it with `-Scenario sabotage -Overrides "testHooks=true"`. `--gate soakr` runs on any full round: no commander group goes 4 minutes without progress.

`tools/lint-sqf.ps1` parses every commander file with HEMTT. `tools/build-playable.ps1` builds the scenario for hosted play.

## What's in here

| Path | Tracked | Purpose |
| --- | --- | --- |
| `mission_overlay/` | Yes | Our only changes to the stock mission |
| `missions/SWL_Test.Tanoa` | No | Built by `tools/build-test-mission.ps1`: stock `MP_Warlords_03.Tanoa` from `reference/` plus the overlay |
| `server/server.cfg`, `server/basic.cfg` | Yes | Dedicated server config |
| `server/runs/` | No | One folder per run: RPT, server profile, caches |

## Test-only changes to the stock mission

- `description.ext`: identical to stock, plus `disabledAI = 0`.
- `initServer.sqf` and `swl/observer.sqf`: new, start the observer on the server.
- `mission.sqm` and `init.sqf` are unchanged.
- `server.cfg` sets the `BIS_WLAIVoting` parameter to 1. Every other parameter stays at its stock default, including fast travel (1, which allows AI fast travel) and CP.

## Observer line format

One record per line, after the RPT's timestamp:

```
SWL|<TYPE>|t=<mission seconds>|key=value|key=value...
```

Fields are separated by `|`, and each field splits on its first `=`. `t` is mission time in whole seconds. A missing value is written as `-`. Side names are `WEST`, `EAST`, `GUER`.

To parse: find `SWL|` in the line and split from there. `tools/swl_log.py` does this.

| Type | When | Fields |
| --- | --- | --- |
| `START` | Observer starts | `world`, `mission`, `dedicated` (0/1), `version`, `build`, `params` (comma-separated `paramsArray`) |
| `SECTORINIT` | Once, when sectors exist | `name`, `owner`, `x`, `y`, `base` (0/1) |
| `TICK` | Every 30 s | `wl_ready` (0/1), `west_groups`, `east_groups`, `west_units`, `east_units`, `guer_units`, `players`, `west_target`, `east_target`, `fps` |
| `GRP` | Every 30 s, one per BLUFOR or OPFOR group with living units | see below |
| `SEC` | Every 30 s, one per sector | `name`, `owner`, `x`, `y`, `base`, `size` (metres, the sector's diameter) |
| `C_*` | Commander decisions and costs, written by `commander/swlc` | Varies by type; `C_TICK` has `avg_ms`, `poll_ms`, `guard_ms`, `groups`, `flying`, `fps` |
| `G<n>` | Written by a scenario in `mission_overlay/swl/scenarios` | `event` plus scenario details |
| `CAPTURE` | Within 1 s of a sector changing owner | `sector`, `from`, `to`, `x`, `y`, `base` |
| `TARGET` | Within 1 s of a side's voted target changing | `side`, `sector` (`-` means none) |
| `ROUNDEND` | The moment a base falls | `winner` (`WEST` or `EAST`) |
| `ENDED` | Mission end event handlers | `type` |

`GRP` fields:

| Field | Meaning |
| --- | --- |
| `id` | `netId` of the group, unique for the round |
| `name` | `str group`, such as `B Alpha 1-1` |
| `side` | `WEST` or `EAST` |
| `leader` | `ai` or `player` |
| `x`, `y` | Leader position in metres |
| `units` | Living units in the group |
| `wp` | Current waypoint index and waypoint count, as `index/count` |
| `wpx`, `wpy`, `wptype` | Current waypoint, or `-` if the group has run out of waypoints |
| `destx`, `desty`, `plan` | `expectedDestination` of the leader. `0,0` with `DoNotPlan` means no destination |
| `combat` | 1 if the leader's behaviour is `COMBAT` |
| `beh` | Leader behaviour |
| `veh` | Vehicle class if the leader is mounted, otherwise `-` |
| `warlord` | 1 if the leader is one of the mode's warlords (playable units) |

Sectors that have no location name are named `Sector_<x>_<y>`, because their localised default name is empty on a dedicated server. A sector's name can change during a round: it can start as `Sector_<x>_<y>` and later gain its location name, such as `Rautake`. Position is the sector's identity, so `tools/swl_log.py` merges both names and reports the location name. Positions are cached before any capture, because Warlords briefly moves a sector's logic object to `[100,100]` when it changes hands.

## Analyser definitions

- **Idle**: the leader stays within 30 m of where the stretch began for 3 minutes or more. Fighting in place counts as idle, and the report gives the share of each stretch spent in combat.
- **Fast travel**: an on-foot leader moves over 400 m between samples. A jump that ends within 300 m of the group's own base is reported separately, since it can be a respawn. A new leader taking over far from the old one could also look like a jump.

## Adding a check

In `tools/analyse_round.py`, write a function that takes a `Round` and returns `(passed, detail)`, then decorate it with `@check("name")`. It runs and prints automatically. A check that raises counts as a FAIL.
