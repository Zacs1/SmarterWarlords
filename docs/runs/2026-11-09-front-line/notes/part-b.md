# Part B as built: defender fast travel until real fighting reaches a sector

Files: `commander/swlc/front.sqf` (new); small edits in `settings.sqf`, `init.sqf`, `rules.sqf` (install), `adapter.sqf`, `radio.sqf`, `status.sqf`, `client.sqf`, `defence.sqf`, `staging.sqf`, `menu.sqf`. Tests: `tests/mission_overlay/swl/scenarios/frontb.sqf`, `tools/gates_fb.py`.

## Do players get the rule? Yes.

Warlords' fast travel menu builds its list as `(BIS_WL_sectorsArrayFriendly # 0) select {_x getVariable ["FastTravelEnabled", TRUE]}` (`fn_WLRequestFastTravel.sqf` line 60). A public `setVariable ["FastTravelEnabled", false, true]` on the sector takes it out of every player's list. `adCanFTTo` reads the same variable, so players and the commander are driven by one switch. Nothing needs overriding in Warlords.

## What Warlords' fast travel setting 4 does (from its code)

- It does **not** block an owned sector the enemy is targeting. Slot 0 of `BIS_fnc_WLSectorListing` is simply every sector the side owns (`fn_WLSectorListing.sqf` line 17), target or not. The menu then filters only on `FastTravelEnabled`, and takes away the player's own base while `BIS_WL_baseFTDisabled` is set.
- Setting 4 offers `FTSeized` only (`fn_WLParseAssetList.sqf` line 150). `FTConflict`, fast travel to the conflict for a fee, needs setting 1 or 2.
- Warlords does **not** refuse fast travel into a sector being seized, despite what the prompt expected. The `FTSeized` item has no such check (`fn_WLSubroutine_purchaseMenuAssetAvailability.sqf` lines 12 to 16), so before this rule players could land in a sector being seized. Now a seize closes it. So the rule both keeps nothing open that Warlords would close, and closes the seize case Warlords doesn't.
- For the commander, `adCanFTTo` had no targeted-sector check either, only base-under-attack and "being seized" (rules variant). But three of its callers (`musterChoose`, `defHop`, `menuFollow`) refused any sector on the commander's threat board. Those now use `SWLC_fnc_frontHot`: with the rule on, only real fighting makes a sector off limits; with it off, the old threat-board test. That is what actually gives the commander its defender's advantage.
- Default Tanoa map setting is FT 1 (`mission.sqm`); the test tools pass 4. Every sector's `FastTravelEnabled` in the Tanoa mission is true.

## Side effect to know about (settings 1 and 2 only)

`FastTravelEnabled` is also read for the attacking side's paid "fast travel to the conflict" (`FTConflict`, line 22 of the availability file) and for vanilla AI's fast travel to the conflict at settings 1 and 3 (`fn_WLAICore.fsm`). So at settings 1 or 2 a player attacking Y loses that paid option while real fighting is on at Y. At setting 4 this can't happen, since `FTConflict` isn't offered. Accepted: it is still "no fast travel into a real fight", and the alternative is rewriting Warlords' menu.

## Spec as built

State per sector owned by WEST or EAST, polled every 5 s on its own server loop (`SWLC_fnc_frontLoop` calling `SWLC_fnc_frontTick`). All tunables in `settings.sqf`, one switch `ruleDefenderFT`, under `rulesVariant`.

- **Area**: the capture square plus `frontAreaMargin` (175 m).
- **Both sides**: at least one attacker and one defender in the area fired within `frontExchangeSeconds` (15), or a man of either side died in the area within that time, killed by someone. One side shooting at nothing doesn't count.
- **Numbers**: `frontMinAttackers` (3) men of the opposing Warlords side who, within `frontInvolvedSeconds` (90), fired, came under fire or died in the area. GUER don't count as attackers.
- **Sustained**: `frontWindowsNeeded` (2) of the last `frontWindowsTotal` (3) finished `frontWindowSeconds` (30) windows contained a moment meeting both of the above. Windows start at the first exchange, so one burst sits inside one window; the window still running doesn't count. A continuous fight closes it about 60 to 65 s after the first exchange.
- **Seizing**: `SWLC_fnc_capBeingSeized` true for the owner closes it at once, whatever the numbers. Decision: follows the prompt's list, even though a lone man could seize an empty sector, because Warlords' own seize rules decide that and at that point the sector is really being lost.
- **Lifting**: `frontQuietSeconds` (120) since the last qualifying moment and the last seize. A lone enemy can't keep it closed: a moment only qualifies with 3 or more attackers involved, so once they have gone his shots don't extend it.
- A sector changing hands drops the state, reopens its fast travel, and starts fresh for the new owner (`why=owner_changed`, no radio line).
- `SWLC_ftBase` keeps a sector the map disabled closed; `FastTravelEnabled` is written only when it changes.

Interface for the other parts: `[_sector] call SWLC_fnc_frontFighting`, `[_side, _sector] call SWLC_fnc_frontFTOpen`. Reads `SWLC_firedAt` and `SWLC_underFireAt` (part D's handlers). Without those handlers no exchange is ever seen and only a casualty or a seize can trigger it, so part B needs part D merged for real rounds.

While fighting is on, every commander fast travel goes through `adCanFTTo`, so the sector drops out and the callers' existing lists pick the nearest other owned sector (`routeFastTravel`, `watchdogEscalate`, `defHop` already sort or take nearest first).

Rules variant off, or `ruleDefenderFT` off: `frontInstall` exits, no loop or handler runs, `FastTravelEnabled` is never written, `frontFighting` is false and `frontFTOpen` is plain `adCanFTTo`. The three callers fall back to the old threat-board test.

## Decisions

| Decision | Why |
|---|---|
| One public `FastTravelEnabled`, no change to Warlords' menu | The menu and `adCanFTTo` already read it, so players and commander can't disagree |
| Windows anchored at the first exchange, only finished windows counted | Fixed clock windows let one burst across a boundary look sustained; finished windows match "most of the last 60 to 90 s" |
| Quiet is measured from the last moment that meets the full definition | Stops one remaining enemy holding fast travel shut, in the spirit of "a lone man must never control it" |
| Casualties need a killer | Warlords' restricted-area kills and accidents use `setDamage` with no instigator, and aren't a fight |
| Attackers are the opposing Warlords side only | GUER only garrison neutral sectors; a neutral garrison near Y isn't the attack on Y |
| Radio cooldown 30 s per side and type, added in `frontInstall` rather than the shared cooldown table | Keeps one settings block for this part; a second sector changing inside 30 s still logs in `C_FRONT` |

## Player-visible text

Radio (`ftclose`, `ftopen`, in `radio.sqf`), `%1` is the sector name:

- "Real fighting at %1. Fast travel there is closed, use the next sector over."
- "%1 is a fight now, no more fast travel in. Come in from a neighbouring sector."
- "Fast travel to %1 is shut, they're on it."
- "%1 is hot. Fast travel closed."
- "%1 has gone quiet. Fast travel there is open again."
- "Fast travel to %1 is back open."
- "%1 is quiet. You can fast travel in again."
- "Fighting's over at %1, fast travel is open."

Commander panel, one line under the header when a sector is targeted, on the threat board or fighting: "Fast travel: Name open, Name closed".

## Scenario limits

`frontb.sqf` (about 13 minutes, not yet run; rounds are the owner's job) drives the state machine by writing `SWLC_firedAt` directly and raises the seize alarm by hand (`BIS_WL_timeoutCur_EAST`, as gatee's fallback does). It proves the rule and the switches, not part D's handlers or a real capture. A real round's `C_FRONT` lines cover those. The "players get it" claim comes from reading Warlords' code; the scenario checks the public variable, not a live player's menu. A player who already has the destination map open when it closes can still click that sector, because the list is built when the map opens.
