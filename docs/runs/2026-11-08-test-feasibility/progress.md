# Progress log: test feasibility (2026-11-08)

Prompt is in `prompt.md`. Resume from the last unticked item.

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
- [ ] Commit housekeeping.
- [ ] Update `docs/local-environment.md`.
- [ ] Mission overlay, build script, observer, install script, `tests/README.md`.
- [ ] `tools/run-round.ps1`.
- [ ] `tools/analyse_round.py`, `tools/plot_round.py`.
- [ ] Real round, analysed and plotted.
- [ ] Verify nothing outside mpmissions changed in the server install.
- [ ] Hand-off.

## Log
