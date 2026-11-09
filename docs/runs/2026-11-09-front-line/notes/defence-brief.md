# Defence build brief (shared by the four defence helpers)

The request is `docs/runs/2026-11-09-front-line/prompt-defence.md`; it is authoritative. Hard limit: code done within about 35 minutes of starting, because everything still has to run in Arma. Prefer the simple version that works over the complete one that doesn't exist yet.

Follow every rule in `notes/build-brief.md` (own worktree, never start Arma servers or the run/build scripts, Bohemia code read-only by absolute path under `D:\Projects\SmarterWarlords\reference\`, settings in one block, `CFG("key")`, Warlords calls through `adapter.sqf`, SQF traps, commit trailer). Differences from that brief:

- These behaviours stay **on with the rules variant off**, like resilience. Do not put them under `CFG("rulesVariant")`. Each has its own switch, default on.
- This run's features (`SWLC_fnc_holdPriority`, `frontFighting`, `frontFTOpen`, Engaged state) exist on master. Some return false with the rules variant off, which is fine, so don't assume they are active.
- Commander groups only. Use `SWLC_fnc_resMayTouch`. Never touch players or AI they own. Must work on a side with human players, for both sides, and nothing Tanoa-specific outside `commander/swlc/maps/`.
- Enemy strength comes only from what the side knows: the intel board in `intel.sqf`. Its own numbers may be real. The one exception the user gave is that Warlords tells a side when one of its sectors becomes the enemy's target: `[_enemySide] call SWLC_fnc_adTarget`.
- Spec, decisions, radio lines, panel text and scenario limits go in `notes/part-<name>.md` (`stance`, `alert`, `fortify`, `steamroll`). Don't edit `docs/design/rules-variant.md`.
- A scenario should take at most 12 minutes of game time. Say exactly how to run it and which `--gate` name to use.

## Shared interface (code against this, don't change it)

All read with defaults, so merge order doesn't matter.

**Stance** (`commander/swlc/stance.sqf`, helper "stance"):
- `_cmd getOrDefault ["stance", "attack"]` is `"attack"`, `"hold"` or `"rebuild"`. Helper function: `[_cmd] call SWLC_fnc_stanceOf`.
- Logs `C_STANCE`. Each switch logs `event=switch`, `from`, `to`, and the numbers that drove it.

**Alert and depth** (`commander/swlc/alert.sqf`, helper "alert"):
- `_cmd getOrDefault ["alert", createHashMap]` is the current record for a threatened sector, empty when none. Keys: `"sector"`, `"since"` (time), `"approach"` as `[bearing, pointOnApproach, roadPoints]` (bearing in degrees from the sector towards the attacker; `roadPoints` is a list of positions on roads along the approach, possibly empty), `"groups"` (main position), `"screen"` (groups), `"counter"` (groups).
- `[_cmd, _sector] call SWLC_fnc_alertApproach` returns the same `[bearing, pointOnApproach, roadPoints]` and is usable by others.
- Logs `C_ALERT`.

**Fortify** (`commander/swlc/fortify.sqf`, helper "fortify"):
- Reads the alert record. Logs `C_FORT`. Crews from `"groups"` in the record.

Existing code to reuse rather than parallel: `defence.sqf` (threat records, reserve, `defRespond`, proportionate response), `pickets.sqf`, `rules.sqf` (commitment timer, `SWLC_fnc_rebuilding`, `rebuildUntil`), `smart.sqf` (dig-in), `economy.sqf` and `logistics.sqf` (buying, `SWLC_fnc_cpFree`, capability rules such as `econAssetAllowed`), `holdouts.sqf` (`holdCover`), `routes.sqf` (route network), `squads.sqf` (LAMBS tasks).

Tell the owner in your final report: the branch, how to run your scenario, what you left out, and your real risks. Don't say something works unless it was checked, and nothing here has run in Arma.
