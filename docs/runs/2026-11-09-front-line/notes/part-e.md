# Part E: measuring where the fighting happens

Built in `tools/gates_front.py`, `tools/plot_round.py` (`--heat`) and registered in `tools/analyse_round.py` as `--gate front`.

## Commands

```
python tools/gates_front.py <rpt> [<rpt> ...]
python tools/gates_front.py <rpt> --gate front --baseline-share 0.35
python tools/gates_front.py <rpt> --gate front --baseline <baseline rpt> [...]
python tools/gates_front.py --compare <baseline rpts> --variant <variant rpts> [--gate front]
python tools/analyse_round.py <rpt> --gate front --baseline-share 0.35
python tools/analyse_round.py <rpt> --gate front --baseline <baseline rpt> [...]
python tools/plot_round.py <rpt> --heat [--heat-out kills.png]
```

`--gate front` should be added to the gate list in `tests/README.md` when this is merged.

## Spec as built

Kill classes, checked in this order, for every `C_KILL` from the first sector clash on:

| Class | Meaning |
| --- | --- |
| `contested` | Inside the capture area of a sector either side is targeting at that moment |
| `other_sector` | Inside any other sector's capture area |
| `edge` | Within 200 m of any sector's capture area |
| `between` | Everywhere else |

The capture area is an axis-aligned square of the sector's `size`, as in `fn_WLSectorsSetup.sqf` (`setTriggerArea [size / 2, size / 2, 0, TRUE]`).

After a sector falls from one side to the other, kills are watched for 600 s, or until X or Y changes hands or the round ends. Each kill goes to the latest fall whose window holds it. Zones, in this order:

| Zone | Meaning |
| --- | --- |
| `at_x` | Inside X's capture area or within 200 m of it |
| `loser_sector` | Inside the capture area of a sector the losing side owns at that moment |
| `other_area` | Inside any other sector's capture area |
| `corridor` | Within 300 m of the straight line from X to Y |
| `elsewhere` | Everywhere else |

The gate share is `(at_x + corridor) / all kills in fall windows`. It passes at baseline + 10 points or better (`--margin`), with at least 20 kills in the fall windows.

## Decisions

| Decision | Why |
| --- | --- |
| The first clash is the earlier of the first capture and the first kill in or within 200 m of a targeted sector | The brief doesn't define it. Kills before that are road contact, and are counted and printed as left out |
| "The loser still targeting X" needs no code of its own | That loser's `TARGET` line still names X, so it is one of the current targets |
| Just after a capture, X counts as `contested` only if someone still targets it | This is the requested definition. A vanilla round, where the loser wasn't targeting X, shows those kills as `other_sector`. The gate's `at_x` zone counts them whatever the targets are |
| Falls from GUER are left out of the fall analysis | There is no losing commander and no next sector of its own |
| Y is the winner's next target if the losing side owned it, otherwise the losing side's nearest owned sector to X | Matches the prompt's two descriptions of Y |
| The gate counts all kills, and the report also prints the share for kills between the two sides only | The brief says "share of kills"; the second number shows how much GUER garrisons affect it |
| The gate fails when it can't judge: no baseline, or under 20 kills | A gate must not pass on missing data. The numbers are printed anyway |
| `C_HOLD`, `C_FRONT`, `C_ENGAGED` are read with `.get`, and a line without `side` or `sector` matches any fall | Those lines are being written by other helpers. Field names follow the brief |
| Sector links on the heat map are read at run time from the stock `mission.sqm` in the gitignored `reference/` | They aren't logged, and Bohemia's mission data must not be committed. With no reference folder the map draws no links and says so |
| "Stayed there" is reported but not gated | The brief's gate is the share. It ends at the first 120 s bin where kills in the losing side's sectors outnumber kills at X and in the corridor |

## Limits

- No RPT has `C_KILL` yet. Tested on synthetic logs and on a real old RPT with injected kills, so numbers from real kills are untested.
- `C_HOLD`, `C_FRONT` and `C_ENGAGED` are tested only against lines I wrote from the brief's field list. If the helpers name fields differently, those sections need a small change.
- The stored baseline (`2026-11-08_19-26-56_baseline`) has no `C_KILL` lines and only one side-to-side capture, so it can't supply a baseline share. A vanilla round with kill logging is needed for that.
- Engaged contacts are counted from `event=start`. Every start is treated as in transit, because Engaged is a transit state.
