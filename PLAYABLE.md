# Playable build

**Scenario:** Smarter Warlords on Tanoa, in `Documents\Arma 3\mpmissions\SmarterWarlords.Tanoa`.
**Built:** 2026-11-09, 20:31, from commit `92dffac`. The living front line and the defence work are in this build.

## What's in this build
- An AI commander per side: staging at owned sectors, waves, reinforcements, side-chat radio.
- Rules variant (on by default): commitment timer, economy and capability sectors, raids and probes, pickets and scaled response.
- Living front line (rules variant): men caught in a fallen sector stay and fight as holdouts, and their side votes to go back for them, reinforces and resupplies them, or counterattacks. A fight at another of your sectors takes over until it's clear.
- Fast travel to a sector being attacked closes when real fighting starts there (rules variant). It applies to players as well as the AI.
- Meeting engagements, always on: a wave that runs into the enemy on the road stops and fights, nearby free groups join, a much bigger enemy sends it back.
- Defence, always on: each commander has a stance (attack, hold or rebuild). It starts setting up as soon as the enemy picks a sector, with a screen out in front, a main position and a counterattack reserve. It buys and crews static guns on threatened sectors.
- "Commander..." scroll menu for humans. Raids, borrowing groups, holding the wave, pickups.
- Smarter squads, with extra behaviour when LAMBS is loaded.
- AI commanders thought panel on the Insert key, which now shows each side's stance.
- Resilience: lost, stuck or scattered groups are recovered. A vehicle that can't be freed gets lifted clear when nobody is watching.

Test state: filled in after the final soak, see the hand-off in `docs/runs/2026-11-09-front-line/`.

## How to host
1. Launch Arma 3 with **CBA_A3** and **LAMBS Danger (stable)**. It also works with no mods. Do not load LAMBS DEV, ASR AI3, Vcom or Advanced AI Command.
2. Multiplayer, Server Browser, Host Server. Choose Tanoa, then **Smarter Warlords**.
3. Set the lobby parameters below, then start.

## Lobby settings: two humans plus AI against all-AI
- Both humans take a slot on the **same side**. Leave every other slot on AI, on both sides.
- Fast Travel: 4 (the default here). AI voting: on (the default here).
- AI commander difficulty: Normal to start with.
- Rules variant: On. Holdouts and the fast travel rule need it. Meeting engagements and defence stay on either way.
- Round time limit: your choice. Off means play to a base capture. 60 or 90 minutes suits one evening.

Debug markers are off. To turn them on, open the debug console as host and run `SWLC_debug = true` on the server.

## What to look for in the front line
- After a sector falls, the fight should stay around it. Its old owners keep shooting from inside and the winners have to clear them before moving on.
- The side that lost it votes straight back for it. If you're on that side, radio tells you "Vote X". The AI on a human side can't reinforce holdouts unless your side votes for that sector.
- Fast travel to a sector vanishes from the list while it's under real fire. It comes back once things have been quiet for about two minutes.
- A wave that bumps into enemies between sectors stops and fights, and the side-chat radio says so.
- Before the enemy arrives, watch for men moving out ahead of a sector, guns appearing on the side facing the enemy, and AT soldiers near the road.
- A counterattack group waits behind the sector and goes in once the enemy breaks in.
- The commander goes quiet when its stance is hold or rebuild. The radio and the panel say which. On a human side that also stops the AI's waves for a while.

## Known issues to avoid
- Stock Tanoa has no mortars or artillery to buy.
- Borrowed groups go back to the commander when the borrowing player dies.
- A pickup delivers a vehicle but no AI driver.
- A follow route that crosses a restricted sector isn't detected, so borrowed groups can walk into one.
- Warlords' own script kills an AI warlord on foot that hasn't moved for about 9 minutes. It is stock behaviour and they respawn.
- A static gun can stand empty if its crew can't reach it, and the enemy can use guns left in a sector they take.
- A fast travel list you already have open can still let you click a sector that has just closed.
- Before you host, make sure no test round is running. Only one Arma server should be up at a time.
