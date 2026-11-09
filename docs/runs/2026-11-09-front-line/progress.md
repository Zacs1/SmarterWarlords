# Front line run: progress log

Prompt: `prompt.md` here (authoritative). Time limit from the user: built and tested by about 20:30 on 2026-11-09. Priority is code done fast, then testing and refining.

## How to resume after compaction
- Shared brief and interfaces: `notes/build-brief.md`.
- Four helpers build in worktrees and report a branch: part B (`front.sqf`, scenario `frontb`, gate `--gate frontb`), parts A and C (`holdouts.sqf`, `fronta`, `--gate fronta`), part D (`engaged.sqf`, `frontd`, `--gate frontd`), part E (`tools/gates_front.py`, `--gate front`).
- Order after they report: merge B, then D, then A+C, then E into master; lint; smoke; scenarios at most 2 servers at once; fix; Opus review A+B and one for C-E; final soak alone with CBA + LAMBS; sabotage once; rules-off smoke; playable, PLAYABLE.md, rules-variant.md, hand-off, final message.
- Baselines for part E: a commander-off round (`-Overrides "commanderEnabled=false"`) and a round on the current build, both on commit 4d7c8eb or later with `C_KILL` logging. Run these straight after the earlier soak finishes, two servers.
- Check free memory before starting any round.

## Log
- 18:10 Kill logging committed (4d7c8eb, `C_KILL` from `init.sqf`, setting `killLog`). Brief written, four helpers started.
- Prior run's `soakfinal` is still running and is left alone; it is on commit 1fa4e23, without `C_KILL`.
- The user's message: an income multiplier was suggested as the answer to slow rebuilds. It was held back: this soak shows about 16,000 CP unspent at minute 40, so income isn't the limit. Decision was open when this run started.
- 18:15 User addition (end of prompt.md): sustained combat, groups leave as soon as ready, rally only when nobody is attacking. Built on master: `rollingMuster` (each group leaves after `musterGroupSeconds` 15 s, once its men have landed, and boards on its own), `rallyLoneWait` 180 to 60. The rally already sends a group straight in when a push is under way. Decision row for the rules doc: the wait at a rally is 60 s, not removed, because a lone group sent in alone just dies.
