# Front line build brief (shared by all four helpers)

The full request is `docs/runs/2026-11-09-front-line/prompt.md`; it is authoritative. Hard time limit: code done within about 40 minutes of starting, because the rest of the 2.5 hours is for testing. Prefer the simple version that works over the complete version that doesn't exist yet.

## Rules for every helper
- Work only in your own git worktree and commit there (end each commit with the two trailer lines below). Never push. The owner merges.
- Never start an Arma server, `tools/run-round.ps1` or `tools/build-playable.ps1`. Rounds are the owner's job. Lint with `powershell -NoProfile -ExecutionPolicy Bypass -File tools/lint-sqf.ps1` (run it from your worktree; it needs no server; output has ANSI colours; look for `error[` lines).
- Bohemia's code is read-only reference at `D:\Projects\SmarterWarlords\reference\functions_f_warlords\Warlords\` and LAMBS at `D:\Projects\SmarterWarlords\reference\lambs_stable\`. That folder is gitignored and is not in your worktree; read it by the absolute path. Never copy Bohemia code into the repo.
- Follow the existing structure: settings in `commander/swlc/settings.sqf` read with `CFG("key")`, Warlords calls through `adapter.sqf`, logging with `["C_TYPE", [["key", value], ...]] call SWLC_fnc_log`, radio via `radio.sqf` (see how existing lines are added and given a cooldown).
- New .sqf files must be added to the file list in `commander/swlc/init.sqf`.
- Everything works for both sides and wherever `isServer` is true. Never control player-led groups or AI a player owns (see how `SWLC_fnc_resMayTouch` is used). Nothing Tanoa-specific outside `commander/swlc/maps/`.
- Every behaviour gets its own switch and tunables, default on. Rule changes sit under `CFG("rulesVariant")`.
- SQF traps: `objNull != objNull` is true; hashmap keys can't be objects; don't `set` nil into a hashmap; `exitWith` in a `forEach` leaves the loop, in `then` leaves that block; privates inside `if` go out of scope; any new `BIS_fnc_WL*` adapter call needs a `private [...]` shield because Bohemia functions leak undeclared locals; group names repeat across sides, so key by side and name in gates.
- Put your spec and decisions in `docs/runs/2026-11-09-front-line/notes/part-<letter>.md` (spec as built, decision rows, player-visible text, scenario limits). Don't edit `docs/design/rules-variant.md`; the owner folds your notes in.
- To limit merge conflicts: add your settings as one block, after the anchor named for your part, and keep edits to shared files small.
- Commit trailer:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01XyBkVFNfSmKycACHEwkkry
  ```

## Shared interface (the parts code against this; don't change it)

Part D owns unit fire tracking, in `commander/swlc/engaged.sqf`:
- Every AI and player unit gets one set of event handlers on the server (`Fired`, `FiredNear` or `Suppressed`, `Hit`). They write `_unit setVariable ["SWLC_firedAt", time]` and `_unit setVariable ["SWLC_underFireAt", time]`. `SWLC_fnc_contactAttachAll` runs on the tick and attaches to units not yet done. Install it for every side, including GUER.
- `[_group] call SWLC_fnc_groupFighting` returns true if any living man in the group fired or came under fire within `CFG("fightingWindow")` (90 s). This is the only definition of "fighting" for groups.
- Group state "Engaged". Group variable `SWLC_holdout` (true) marks a holdout (set by part A).

Part B owns the sector signal, in `commander/swlc/front.sqf`:
- `[_sector] call SWLC_fnc_frontFighting` returns true while active fighting is on at that sector, for the side that owns it. `[_side, _sector] call SWLC_fnc_frontFTOpen` returns true if that side may fast travel there.
- Reads `SWLC_firedAt` and `SWLC_underFireAt` from units, `EntityKilled` for casualties. Runs from `SWLC_fnc_frontTick` once per side's tick or on its own server loop.

Part A owns the side's goal, in `commander/swlc/holdouts.sqf`:
- `_cmd get "frontGoal"` is `[]` or `["hold", X]`, `["counter", X]`, `["defend", Y]`, where X and Y are sector objects. Part C's switching lives here too.

Sector, target and group helpers already exist in `adapter.sqf`; read them first.

## What the owner found already
- Warlords' player menu lists fast travel destinations as owned sectors filtered by the sector variable `FastTravelEnabled` (`fn_WLRequestFastTravel.sqf` line 60); `SWLC_fnc_adCanFTTo` already reads the same variable. So one public `setVariable ["FastTravelEnabled", bool, true]` on the sector may drive both players and the commander. Verify that it does and that nothing else blocks fast travel to a targeted owned sector under setting 4.
- The AI-kill rule is the trigger in `fn_WLSectorsCommonInit.sqf` about line 66 (`BIS_WL_sectorZR`, statement `{if !(isPlayer _x) then {_x setDamage 1}} forEach thislist`) and possibly `fn_WLSectorsSetup.sqf` line 107. Read its condition.
- `C_KILL` lines (position, side, killer side) are already logged from `commander/swlc/init.sqf`, before the `commanderEnabled` check, so a commander-off round has them too.
- Existing related code: `smart.sqf` (reinforce mode, break-and-consolidate, dig in), `rules.sqf` (commitment timer), `defence.sqf`, `wave.sqf`, `resilience.sqf` (sweep, ladder), `watchdog.sqf`, `tools/gates_activity.py`, `tools/gates_r.py`.
