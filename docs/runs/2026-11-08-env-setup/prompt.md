We're starting a new project in this folder: SmarterWarlords, a smarter AI commander layered on top of Arma 3's Warlords game mode. The design doc is somewhere in this folder (find it and skim it so you understand the project, but don't start building anything). This run is environment setup only: give yourself durable access to the folders the project needs, record where everything is, and report what's missing. Save this prompt to docs/runs/2026-11-08-env-setup/prompt.md and keep a short progress log next to it as you go.

1. Find these locations on this Windows machine. Don't assume default paths: Steam libraries can be on any drive and Documents may be redirected to OneDrive.
   - Steam install: read the SteamPath value from the registry (HKCU\Software\Valve\Steam), then parse steamapps/libraryfolders.vdf to get every Steam library.
   - Arma 3 install (app 107410): the folder containing arma3_x64.exe. Confirm its Addons folder contains the Warlords PBOs (search for "warlords" in the PBO file names, and also note the PBO holding the BIS_fnc_WL functions if you can identify it from file names). List them; don't unpack anything yet.
   - Arma 3 Server (app 233780) and Arma 3 Tools (app 233800): note whether each is installed and where.
   - Workshop content for Arma 3: steamapps/workshop/content/107410 in whichever library has it. Note whether CBA_A3 and LAMBS_Danger.fsm are present (check the mod.cpp or meta.cpp in each subfolder for names).
   - Arma 3 profile folders: Documents\Arma 3 and every folder under Documents\Arma 3 - Other Profiles. For each, note the missions and mpmissions folders (create mpmissions if a profile lacks it, but ask me first which profile I play on if there's more than one).
   - Log folder: %LOCALAPPDATA%\Arma 3 (where .rpt logs go). Note the newest .rpt file name to confirm it's the right place.

2. Give yourself durable access via .claude/settings.local.json in this project (create .claude if needed). Use permissions.additionalDirectories for the Arma 3 install, the Arma 3 Server install if present, the Workshop content folder, the profile folder(s), and the log folder. Allow reads in all of those. Allow writes only in this project folder and the profile's missions/mpmissions folders. Never write into the Arma 3 install, the server install, or Workshop content; add explicit deny rules for edits there. If you're unsure of the exact settings schema, check the Claude Code docs rather than guessing. Add .claude/settings.local.json to .gitignore since it's machine-specific.

3. Write docs/local-environment.md (also gitignored) listing every path you found, what's installed and what's missing. Future runs will read this instead of searching again.

4. Create a short CLAUDE.md at the project root: one paragraph on what the project is, a pointer to the design doc, a pointer to docs/local-environment.md, and these standing rules:
   - Never write into the Arma 3 install, the server install or Workshop content.
   - Commit locally at sensible points; never push.
   - Every run saves its prompt and a progress log under docs/runs/<date>-<name>/ and ends with a brief hand-off doc there: how it went, next steps, and any red flags.
   - Anything needing my action or approval goes in the run's final message, not just in a file.

5. Check whether HEMTT is available. If it isn't, find the current recommended install method for Windows and install it (winget or the official release is fine). Confirm `hemtt --version` works. Don't use it on anything yet.

6. Commit .gitignore and CLAUDE.md (not the gitignored files).

Finish with a hand-off doc in the run folder and a final message that tells me: whether I need to restart Claude Code for the new permissions to take effect; what's installed and what's missing (especially Arma 3 Server, CBA_A3, LAMBS); which profile folder you'll use; and anything you need me to do.
