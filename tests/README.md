# Automated round tests

A round runs unattended on the dedicated server. A passive observer in the test mission writes structured lines to the RPT, and the tools judge the round from those lines.

```powershell
powershell -ExecutionPolicy Bypass -File tools\run-round.ps1 -DurationMinutes 45
python tools\analyse_round.py <path-to-rpt>
python tools\plot_round.py <path-to-rpt>
```

`run-round.ps1` prints the RPT path. Each run gets its own folder in `tests/server/runs/` (gitignored), which is also the server's profile folder, so saved scenario progress cannot leak between runs. The server stops at round end or after the duration. It sits in a Windows job object, so it also dies if the script is killed.

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

Sectors that have no location name are named `Sector_<x>_<y>`, because their localised default name is empty on a dedicated server. Positions are cached before any capture, because Warlords briefly moves a sector's logic object to `[100,100]` when it changes hands.

## Analyser definitions

- **Idle**: the leader stays within 30 m of where the stretch began for 3 minutes or more. Fighting in place counts as idle, and the report gives the share of each stretch spent in combat.
- **Fast travel**: an on-foot leader moves over 400 m between samples. A jump that ends within 300 m of the group's own base is reported separately, since it can be a respawn. A new leader taking over far from the old one could also look like a jump.

## Adding a check

In `tools/analyse_round.py`, write a function that takes a `Round` and returns `(passed, detail)`, then decorate it with `@check("name")`. It runs and prints automatically. A check that raises counts as a FAIL.
