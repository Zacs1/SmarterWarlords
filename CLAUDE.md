# SmarterWarlords

SmarterWarlords is a rule-based AI commander layered on top of Arma 3's Warlords game mode. One server-side commander per side stages AI groups at owned sectors, shares intel only from what its soldiers have seen, and launches coordinated waves, while Warlords keeps owning sectors, CP, voting, purchasing and respawn.

- Design doc: `Smarter Warlords — AI Commander Design.md` (project root).
- Machine-specific paths and what's installed: `docs/local-environment.md` (gitignored). Read it instead of searching for Arma folders again.

## Standing rules

- Never write into the Arma 3 install, the server install or Workshop content.
- Commit locally at sensible points; never push.
- Every run saves its prompt and a progress log under `docs/runs/<date>-<name>/` and ends with a brief hand-off doc there: how it went, next steps, and any red flags.
- Anything needing the user's action or approval goes in the run's final message, not just in a file.
