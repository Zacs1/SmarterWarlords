# Hand-off: test feasibility (2026-11-08)

## How it went

It worked. A full Arma 3 Warlords round ran from start to finish with no human involved and was judged from its log. The first method tried worked, so no fallback was needed.

- Method: the dedicated server `arma3server_x64.exe` from the Arma 3 Server install, with `-autoInit`, `-world=empty`, no `-mod`, the mission set in `tests/server/server.cfg` with `persistent=1`, its own profile folder per run, and no players or headless client.
- Run a round: `powershell -ExecutionPolicy Bypass -File tools\run-round.ps1 -DurationMinutes 75 -Name myround`. It prints the run folder and log path.
- Analyse: `python tools/analyse_round.py <rpt>`. Plot: `python tools/plot_round.py <rpt>`. The plot lands next to the log.
- The runner stops on round end or at the duration, holds the server in a job object so it can't be orphaned, and compares the server install before and after.

## Vanilla baseline

Run `tests/server/runs/2026-11-08_19-26-56_baseline`, log `arma3server_x64_2026-11-08_19-26-57.rpt`. Vanilla, Tanoa, 7 sectors including bases, fast travel 1, AI voting on, 500 start CP.

| Measure | Result |
| --- | --- |
| Round length | 70:26, WEST won by taking the OPFOR base |
| First capture | 3:10 (Leqa, by EAST). The 4-minute smoke round had its first at 3:41 |
| Captures | Leqa 3:10, Sector_1715_6128 4:37, Rautake 8:30, Balavu 50:14, Leqa retaken 58:10, OPFOR Base about 70:26 |
| Script errors | 0 |
| Server FPS | 14 to 20 |
| Idle 3+ min | 12 of the 16 warlord groups (WEST 8/8, EAST 4/8) |
| Longest idle | 10:02 (B Alpha 1-6 at Balavu) |
| Where | 33 stretches: Balavu 25, open ground 6, OPFOR Base 1, Leqa 1 |
| Fast travel | 104 long jumps across all 16 groups, plus 31 returns to base |
| Reaching the target | Warlord groups inside the sector: WEST 8/8, 4/8, 8/8, 4/8, 5/8. EAST 8/8, 8/8 |

Idle and fast travel by ten-minute window, for comparing against the commander:

| Window | Idle group-minutes | Groups idle | Fast travels | Base returns |
| --- | --- | --- | --- | --- |
| 0:00 | 5.3 | 4 | 39 | 0 |
| 10:00 | 29.4 | 7 | 12 | 4 |
| 20:00 | 49.3 | 10 | 7 | 4 |
| 30:00 | 40.8 | 7 | 13 | 4 |
| 40:00 | 37.6 | 7 | 11 | 5 |
| 50:00 | 11.8 | 3 | 16 | 14 |
| 60:00 | 10.8 | 2 | 5 | 0 |

What this shows:

- AI groups do fast travel, repeatedly. After respawning at base, EAST groups jumped again and again to almost the same spot about 340 m from Balavu, then walked in.
- The idle problem in this round was groups pinned in a long firefight at the contested sector, not groups lost in open country. Most idle stretches were 85 to 100% in combat. The design doc's "idle in the wilderness" pattern barely appeared on this small map (6 stretches).
- Balavu held both sides for 41 minutes. Each side kept feeding it from respawns and neither held the capture area long enough. Warlords has no target timeout, so a deadlock like this only ends by attrition.
- EAST kept Balavu as its target until the end, even after WEST captured it. An enemy capture doesn't clear a side's target.
- Three extra EAST groups, not warlord groups, appeared at 50:38 and were gone by 58:39.

Warning: this is one round on one small map, so treat these numbers as a rough reference rather than a stable average.

## Warlords file layout

- `reference/functions_f_warlords/` (75 files): `Misc`, `Warlords`, `$PBOPREFIX$`, `config.bin`, `config.cpp`, `properties.txt`. The mode's code is in `Warlords/`: `fn_WLInit.sqf`, `fn_WLVarsInit.sqf`, `fn_WLSectorsSetup.sqf`, `fn_WLAICore.fsm`, `fn_WLAIPurchases.fsm`, `fn_WLSectorHandleServer.fsm`, `fn_WLSectorSelectionHandleServer.fsm`, `fn_WLMostVotedSector.sqf`.
- `reference/missions_f_warlords/` (44 files): `data`, `kb`, `MPScenarios`, `cfgMissionParams.inc`, `cfgMissionParams_subclasses.inc`, `commonInitScript.sqf`, `defaultDescription.inc`, config files. `MPScenarios` holds `MP_Warlords_01`, `01a`, `01b`, `01_large`, `01_large_ver2` (Altis), `02`, `02_large` (Stratis), `03`, `03a` (Tanoa), `04`, `04_large` (Malden). The stock Tanoa scenario is `MP_Warlords_03.Tanoa`.
- The overnight build's notes in `docs/runs/2026-11-08-overnight-build/notes/` answer most of the code questions.

## What's committed and what isn't

- Bohemia's files stay out of the repo. `reference/` and the built `tests/missions/SWL_Test.Tanoa` are gitignored. Our changes live in `tests/mission_overlay/`, and `tools/build-test-mission.ps1` rebuilds the mission from `reference/`.
- `tools/extract-tanoa-map.ps1` makes the plot's terrain background at `reference/map/tanoa_picturemap.png`, which is local only.
- Test-only mission changes: `disabledAI = 0`, `initServer.sqf` starting the observer. `mission.sqm` and `init.sqf` are stock.

## Next steps

The overnight build in `docs/runs/2026-11-08-overnight-build/prompt.md`.

## Red flags

- The base capture that ends a round isn't logged as a `CAPTURE`, because the mission ends first. `ROUNDEND` is the record of it, and the analyser's "final ownership" line still shows the base with its old owner.
- Sector names can change mid-round, and logic objects move to [100,100] at capture. Identify sectors by cached position.
- The server logs one startup warning about deleted content for `a3_characters_f`. The mission runs normally, and the analyser reports it apart from script errors.
- Server and client builds differ (25600558 and 25623484). It doesn't matter for server-only tests, but a client may refuse to join this server until both are updated.
- Long-jump counts are inferred from positions (on foot, 400 m or more within 45 s), so a fast travel and a respawn can look alike unless the jump ends near base.
- `persistent=1` restarts the mission after it ends. The runner stops the server within about 30 seconds, and the analyser reads only the first round.
- D: is 96% full, with 43 GB free. Run folders are about 13 MB, so tests are no threat to it.
