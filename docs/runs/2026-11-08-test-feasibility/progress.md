# Progress log: test feasibility (2026-11-08)

Prompt is in `prompt.md`. Resume from the last unticked item.

## Next run
When this run's hand-off and final message are done, start the overnight build in `docs/runs/2026-11-08-overnight-build/prompt.md`. The user asked for that on 2026-11-08 and will not need to prompt again.

## Decisions
- Test mission is derived from a Bohemia scenario, so `tests/missions/SWL_Test.Tanoa` is built and gitignored. Our own changes live in committed `tests/mission_overlay/` plus a build script that regenerates the mission from `reference/`.
- Server install is on C:, `C:\Program Files (x86)\Steam\steamapps\common\Arma 3 Server`, build 25600558. Client build is 25623484.
- BattlEye off in server config so nothing is written to the server's battleye folder.

## Done
- [x] Prompt saved.
- [x] Server install confirmed. Client install also has a `arma3server_x64.exe`.
- [x] Permissions and CLAUDE.md carry the one MPMissions exception. Probes passed.
- [x] HEMTT unpacked `functions_f_warlords.pbo` and `missions_f_warlords.pbo` into `reference/`.
- [x] Stock Tanoa scenario is `reference/missions_f_warlords/MPScenarios/MP_Warlords_03.Tanoa`.

## To do
- [x] Commit housekeeping.
- [x] Update `docs/local-environment.md`.
- [x] Mission overlay, build script, observer, install script, `tests/README.md`.
- [x] `tools/run-round.ps1`.
- [x] `tools/analyse_round.py`, `tools/plot_round.py` (with terrain from `tools/extract-tanoa-map.ps1`).
- [ ] Real round, analysed and plotted. Baseline running: `tests/server/runs/2026-11-08_19-26-56_baseline`, up to 75 min.
- [x] Verify nothing outside mpmissions changed in the server install (run-round checks every run).
- [ ] Hand-off.

## Log
- Smoke round (`2026-11-08_19-21-43_smoke`, 4 min): first method tried worked. Dedicated server, `-autoInit`, mission in server config, persistent=1, no players. Warlords started, both sides voted at about 0:20, AI fast travelled at about 1:02, first capture at 3:41, no script errors, install unchanged.
- Observer fixes after smoke: Warlords moves a sector's logic object to [100,100] when it changes hands, so positions are cached at init. Unnamed sectors have an empty localised name on dedicated, so they are named `Sector_<x>_<y>`.
- Removed an out-of-range `voteThreshold` from server.cfg.
- Baseline round started 19:26:56. Captures so far: Leqa to EAST 3:10, Sector_1715_6128 to WEST 4:37, Rautake to WEST 8:30. Script errors 0.
- Baseline, 24:05: both sides have targeted Balavu since 8:49 (WEST) and 3:29 (EAST) with no capture yet. It is a real fight, not a stall: nearly all groups in COMBAT, down to 1 to 4 men each, Balavu's garrison down to 2 GUER units. WEST had 8 groups (21 men) inside the 150 m radius at 24:05, EAST 2.
- Capture rule (`fn_WLSectorHandleServer.fsm`:126-143): one trigger per side with "SEIZED" activation and a timeout, so a sector flips only when one side dominates the area for the whole timeout, and only for a side that has it as its current target or already conquered it.
- Parser now treats position as sector identity (commit 79e9914). The earlier `tail -F` log watcher silently emitted nothing under Git Bash; the watcher now polls with `grep -c` and prints new lines.
