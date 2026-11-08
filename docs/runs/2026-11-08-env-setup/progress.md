# Progress log: env setup (2026-11-08)

- Saved the prompt. Project folder was empty at first; the design doc arrived during the run and has been read.
- Steam: registry SteamPath read, two libraries parsed from libraryfolders.vdf (C: and D:).
- Arma 3 found on D:. Warlords PBOs listed, nothing unpacked.
- Arma 3 Server and Arma 3 Tools: no appmanifest in either library, so not installed.
- Workshop content found on D:, 33 items. CBA_A3 and LAMBS (stable and DEV) present.
- Profiles: only Documents\Arma 3. No "Other Profiles" folder. Created mpmissions there, as the prompt allows.
- Log folder confirmed by its one .rpt file.
- HEMTT was missing. Installed BrettMayson.HEMTT via winget, per hemtt.dev. `hemtt --version` reports 1.23.1. Not used on anything.
- Wrote .gitignore and CLAUDE.md, committed both (7fdea11). Wrote docs/local-environment.md.
- Checked the Claude Code docs: deny beats allow, so the profile's non-mission contents are denied by name.
- Wrote .claude/settings.local.json. It loaded live, no restart needed.
- Probed with Edits on nonexistent files, which can't write: install, Workshop, logs, profile Saved and profile *.cfg all denied; mpmissions and missions passed. Reads confirmed in logs and Workshop.
