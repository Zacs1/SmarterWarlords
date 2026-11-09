# Playable build

**Scenario:** Smarter Warlords on Tanoa, in `Documents\Arma 3\mpmissions\SmarterWarlords.Tanoa`.
**Built:** 2026-11-09, about 13:15, from commit `7c29c77`. Resilience is not in this build yet.

## What's in this build
- An AI commander per side: staging at owned sectors, a single rally point, waves, reinforcements, side-chat radio.
- Rules variant (on by default): deadlock timer, economy and capability sectors, raids and probes, pickets and scaled response.
- "Commander..." scroll menu for humans. Raids, borrowing groups, holding the wave, pickups.
- Smarter squads, with extra behaviour when LAMBS is loaded.
- AI commanders thought panel on the Insert key.

Test state: this code ran with no script errors in its latest scenario rounds. The part gates are still being finished, so treat it as a working preview.

## How to host
1. Launch Arma 3 with **CBA_A3** and **LAMBS Danger (stable)**. It also works with no mods. Do not load LAMBS DEV, ASR AI3, Vcom or Advanced AI Command.
2. Multiplayer, Server Browser, Host Server. Choose Tanoa, then **Smarter Warlords**.
3. Set the lobby parameters below, then start.

## Lobby settings: two humans plus AI against all-AI
- Both humans take a slot on the **same side**. Leave every other slot on AI, on both sides.
- Fast Travel: 4 (the default here). AI voting: on (the default here).
- AI commander difficulty: Normal to start with.
- Rules variant: On.
- Round time limit: your choice. Off means play to a base capture. 60 or 90 minutes suits one evening.

Debug markers are off. To turn them on, open the debug console as host and run `SWLC_debug = true` on the server.

## Known issues to avoid
- Stock Tanoa has no mortars or artillery to buy.
- Borrowed groups go back to the commander when the borrowing player dies.
- A pickup delivers a vehicle but no AI driver.
- A follow route that crosses a restricted sector isn't detected, so borrowed groups can walk into one.
- Warlords' own script kills an AI warlord on foot that hasn't moved for about 9 minutes. It is stock behaviour and they respawn.
- Before you host, make sure no test round is running. Only one Arma server should be up at a time.
