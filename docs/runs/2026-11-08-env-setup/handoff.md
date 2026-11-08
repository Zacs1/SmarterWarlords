# Hand-off: env setup (2026-11-08)

## How it went

Setup is complete and nothing was built or unpacked. Every path is in `docs/local-environment.md`. Access rules are in `.claude/settings.local.json`, took effect without a restart, and passed non-writing probes. `.gitignore` and `CLAUDE.md` are committed (7fdea11). HEMTT is installed and reports 1.23.1.

## What's installed

- Installed: Arma 3 (D:), Warlords PBOs, CBA_A3, LAMBS_Danger.fsm (stable and DEV), HEMTT.
- Missing: Arma 3 Server, Arma 3 Tools, DCO Soldier FSM (the design doc's optional LAMBS alternative).
- Profile in use: `C:\Users\smith\Documents\Arma 3`, the only one. `mpmissions` was created. `missions` doesn't exist yet.

## Next steps

1. Phase 0 from the design doc: unpack `functions_f_warlords.pbo` and `missions_f_warlords.pbo` somewhere inside this project, then answer the four open questions on Warlords internals. HEMTT's PBO tooling hasn't been tried yet.
2. Decide whether to install Arma 3 Server. Open question 4 in the design doc is about dedicated-server behaviour, though the v1.0 target is locally hosted.

## Red flags

- Edit rules don't stop every shell-based write. A script or subprocess could still write to protected folders, so the CLAUDE.md rule has to hold there.
- Profile protection is by name. A new top-level folder or file type in the profile would follow the permission mode rather than being denied.
- Both LAMBS stable and DEV are downloaded. Load only one. ASR AI3, Vcom AI and Advanced AI Command are also present and should stay out of test loads unless they're being tested on purpose.
- The design doc and `docs/runs/` are untracked, because this run was told to commit only `.gitignore` and `CLAUDE.md`.
- The repo's branch is `master`, with this one commit.
- Shells opened before the HEMTT install won't find `hemtt` until restarted. The full path is in `docs/local-environment.md`.
