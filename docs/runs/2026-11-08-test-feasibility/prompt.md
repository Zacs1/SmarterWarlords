SmarterWarlords: automated test feasibility run. Read CLAUDE.md, docs/local-environment.md and the design doc first. The goal of this run is to prove, tonight, that an Arma 3 Warlords round can run with no human involvement and that you can judge from logs how it went. If that works, an overnight run will build the whole design using this loop. If it doesn't work, I need to know now, while I'm here. No commander code in this run; only the testing foundation.

Save this prompt to docs/runs/2026-11-08-test-feasibility/prompt.md and keep a progress log there that would let you resume after compaction. I'm at my desk, so if you hit something only I can do (Steam, firewall, a dialog on screen), say so straight away in the chat rather than waiting.

0. Housekeeping
- Commit the design doc and the existing docs/runs folder, which the setup run left untracked.
- Add a gitignored reference/ folder for unpacked Bohemia files. Never commit Bohemia's code or missions to this repo.
- Mods: vanilla only for every test in this run. CBA, LAMBS (stable and DEV), ASR AI3, Vcom and Advanced AI Command are all in my Workshop folder and must not be loaded.

1. Arma 3 Server
- Confirm Arma 3 Server is now installed (I've just installed it from Steam) and add its location to docs/local-environment.md. If the Arma 3 install itself also contains a usable arma3server_x64.exe, note that too.
- Exception to the CLAUDE.md rule: you may write into the server install's MPMissions folder only, nothing else in the server install. Update .claude/settings.local.json and CLAUDE.md to reflect exactly that one exception. Server configs, profiles and logs go inside this project (e.g. tests/server/), using the server's -config, -profiles and -name options so nothing else lands in the server install.

2. Unpack the reference material
- Unpack functions_f_warlords.pbo and missions_f_warlords.pbo into reference/ using HEMTT, falling back to another reliable PBO tool if HEMTT can't do it. Use the full HEMTT path from docs/local-environment.md if hemtt isn't on PATH in your shell.
- Find the stock Tanoa Warlords scenario. If it isn't in missions_f_warlords.pbo, search the other Addons PBOs by name for it and unpack that one.
- Don't study the Warlords code in depth yet; that's the overnight run's phase 0. Just note the file layout in the hand-off.

3. Test mission
- Build tests/missions/SWL_Test.Tanoa: a copy of the stock Tanoa Warlords scenario, changed only as needed for an unattended AI-vs-AI round. All playable slots AI-enabled on both sides, sensible lobby defaults (fast travel enabled for AI, normal CP), and a passive observer script. The observer has no gameplay effect: every 30 seconds it writes structured lines to the RPT via diag_log with a fixed prefix (e.g. SWL|), covering game time, every BLUFOR and OPFOR group (id, side, leader is player or AI, position, unit count, current waypoint, whether in combat) and sector ownership. Also log sector captures and round end the moment they happen. Pick a line format that's trivially machine-parseable and document it in tests/README.md.
- A small script installs (copies or junctions) the test mission into the server's MPMissions folder.

4. Running a round with one command
- Write tools/run-round.ps1: starts the dedicated server with the test mission, no players, vanilla mods only, writes the server log into this project, stops the server after a duration I pass in (or when round end is logged), and prints where the log is. It must clean up after itself: no orphan server processes left running.
- First try the dedicated server with -autoInit and the mission set in a server config (persistent, AI-enabled). If Warlords won't start or won't progress without a connected player, work through alternatives and document what you tried. Candidates: a headless client connecting to the server; a locally hosted non-dedicated session started from the client exe via launch options; a minimal test-only init change that starts the mode without a player. Any change to the mission must stay test-only and be documented.
- Whatever you use, a round must start, progress and be stoppable with no human input. Check the log, not your expectations.

5. Analyser and plotter
- tools/analyse_round.py: parses the SWL lines from a log and prints a summary (groups per side over time, sectors captured and when, how many AI groups were idle for 3+ minutes, the longest idle stretch per group, any script errors in the RPT) plus a list of named checks, each PASS or FAIL. For this run the checks are: AI groups spawned on both sides; AI groups moved; at least one sector was captured; no script errors. Structure it so later runs can add checks (wave sizes, AT counts, defence response) without rewriting it.
- tools/plot_round.py: draws group positions over time on a Tanoa canvas with sectors marked and labelled, coloured by side, so stalls and wandering are visible. A plain coordinate canvas is fine; a terrain background is a nice-to-have only if you can produce one locally.

6. Prove it
- Run at least one real round long enough to see a sector change hands or to be sure it won't (watch the log as it goes; if it's still running after a while, check it's actually progressing rather than waiting blindly). Run the analyser and plotter on it and look at the plot yourself.
- Report what vanilla Warlords AI does unattended: do groups fast travel, do they reach the target, how many go idle and where. That's our baseline for the overnight run.

Commit at sensible points; never push.

Finish with a hand-off doc in the run folder and a final message telling me:
- Verdict: can a full round run and be judged with no human involvement? Yes or no, and the exact method that works.
- The one command to run a round, and to analyse and plot it.
- Measured facts from the real round(s): time to first sector capture, how many AI groups went idle, anything surprising.
- Anything you couldn't automate, and what I need to do, if anything.
- Anything the overnight build run must know.
