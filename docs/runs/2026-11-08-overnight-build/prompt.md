SmarterWarlords: overnight build run. Build the design doc's phases 0 to 4 plus the parts of phase 5 that need no human, test each phase against its finish line with the automated round tooling, and leave me a playable Tanoa scenario to try tomorrow. I'm asleep and won't answer: never wait on me. Make the best call, write down why, and keep going.

Read first: CLAUDE.md; docs/local-environment.md; the design doc (it's the spec: follow its rules for the intel board, decision loop, loadouts, vehicles, watchdog, defence, radio and debugging, and where testing shows a better value or approach, use it and update the doc); the test-feasibility run's hand-off and tests/README.md (the tooling, the vanilla baseline, and the Warlords quirks found so far, e.g. captured sectors briefly moved to the map corner, unnamed sectors having empty names on dedicated servers, AI voting on its own when a side has no players, AI only fast travelling when BIS_WLFTEnabled is 1 or 3). Where this prompt and the design doc disagree, this prompt wins.

Save this prompt and a progress log in docs/runs/2026-11-08-overnight-build/. The log must let you resume after compaction: current phase, last gate passed, what's in flight, decisions made.

## What it should feel like
The whole point is that a round reads as an active military operation, not teleporting and not men standing around. A side picks a target, fast travels to a safe owned sector near it, gears up in a hurry (soldiers running to the crate, vehicles arriving and lining up), gets a mount-up call, and pulls out together in vehicles where it can afford them, driving most of the way and walking the last stretch. Pace matters more than a perfect wave. Fast travel never goes into the contested sector; the last leg is always driven or walked. When a choice in this run trades realism or caution against pace and visible activity, lean towards pace and activity.

## Ground rules
- Commit after every phase and at sensible points inside phases; tag each finished phase (phase-0-done, phase-1-done, ...). Never push.
- Vanilla mods for every test except the phase 5 LAMBS round (CBA_A3 + LAMBS stable only; never LAMBS DEV, ASR AI3, Vcom or Advanced AI Command).
- No deadline. Work through the phases in order, then down the "if time remains" list.
- One Arma server at a time. Use helper agents for work that doesn't need the server (reading Warlords code, writing analyser checks for the next phase, drafting code while a round runs, the per-phase review), and start that prep yourself while rounds run. Never leave a helper waiting on the server.
- Never wait blindly on a round: check its log periodically (well within 45 minutes on long rounds) to confirm it's progressing; kill and investigate stalls.
- Big calls are yours. Example: if Warlords' own AI loop has to be replaced rather than steered, choose the better option, record it with reasoning in a decision log in the design doc and in the hand-off, and continue. Everything is committed and tagged, so I can roll back.
- Keep it releasable: every tunable value in one settings file; anything map-specific in per-map settings (Tanoa now, but nothing that would block Altis, Stratis, Malden and the rest); the commander self-contained so it drops into any Warlords scenario as an overlay and can later become an addon.
- The v1.0 target is a locally hosted round: me and my wife plus AI on one side against an all-AI side, about 8v8. Your tests run on a dedicated server with no players, so the code must assume neither. Run commander logic wherever isServer is true (that includes a client host). Never take over groups led by a player, or AI that a player bought or commands. Don't rely on `player` on the server. Flag anything you couldn't test because it needs real players.

## Testing
- Scenario tests: short, targeted rounds on Tanoa. Make them fast however works best: a cut-down test variant (fewer sectors, more CP, shorter timers), test-only parameters, or a test script that injects situations (enemy armour placed at the target, a counterattack on an owned sector). Each ends with analyser checks printing PASS or FAIL.
- Soak rounds: full-length rounds on the full Tanoa scenario to catch problems that build up over time. At least one after phase 1 and one at the end.
- Extend tools/analyse_round.py with each phase's checks, and compare against the vanilla baseline (idle groups, where they idle, fast travel rate over time, time to captures). Look at the plots yourself, not just the checks.
- Test in depth what each phase built; don't rerun everything every phase. Full regression (all checks plus a soak) once at the end.
- One common-sense code review per phase before its final commit (a single reviewer agent on Opus, focused on the risky parts; no stacked reviews).

## Phase 0: Warlords internals and adapter
- Read the unpacked Warlords code in reference/ enough to answer the design doc's four open questions, and write the answers into its Integration section.
- Build the adapter, one module holding every Warlords hook: current target per side; owned sectors and the sector graph; CP per side; which groups the commander owns; move and waypoint orders; AI fast travel done the Warlords way (respecting BIS_WLFTEnabled and its costs) but only ever to owned sectors; purchases through Warlords' own path, including vehicles, and where purchased assets spawn; sector scans.
- Also find out exactly what each BIS_WLFTEnabled value allows, and whether one blocks fast travel into the contested sector for players while still letting the commander fast travel its groups to owned sectors.
- Gate: a test round shows the adapter tracking targets and ownership correctly over time, and moving an owned AI group to a chosen sector without Warlords overriding the order.

## Phase 1: Core loop
- One commander per side on the server, on a slow tick. Staging sector choice. Fast travel to staging (owned sectors only, never the contested one), landing groups at spread-out positions around the sector on the side away from the target.
- Staging must look busy: groups move to positions at building edges and treelines rather than standing in a clump, and anything they need to do (kit, vehicles) is visibly done.
- Go signal: the wave goes when 3 or more groups have reached staging, or 4 minutes after the first one arrived, whichever comes first. No extensions; late arrivals join the next wave.
- Launch on foot in this phase (vehicles come in phase 3) on 2 to 3 approaches with holding points, all groups getting their orders together. Resolve (seized, failed, abort); task states; the watchdog (progress check, post-contact waypoint reset, escalation); the debug overlay (map markers, off by default, toggleable); structured logging of every decision.
- Gate: AI vs AI on full Tanoa with no commander-owned group idle more than 3 minutes outside staging, staging-to-go never more than 4 minutes, most attacks arriving as waves of 3+ groups, and idle figures clearly better than the vanilla baseline, especially late in the round. Then a soak round.

## Phase 2: Intel board and radio
- The intel board as specified: sightings from group knowledge, scans and unexplained losses; clustering; decay; negative information; per-sector threat summaries. The threat summary changes what the next wave brings (kit, vehicles), never how long it waits. Radio messages with per-type cooldowns, using only what the side knows, including the staging, mount-up and move-out calls.
- Gate: in a scenario test, enemy armour seen at the target appears on the board and on radio within 10 s, and the next wave's plan changes to match. Add a check that every board entry traces back to a real sighting, so the commander never acts on enemies nobody has seen.

## Phase 3: Kit, spending and vehicles
- Kit swaps at staging from a supply crate, using launchers from the side's own faction; the side shopping list steering AI purchases; buying scans for unscouted targets before the go when affordable.
- CP reserve that scales with income, so it never stops an early side buying cheap transport.
- Vehicles in the attack. Driving is the default whenever affordable, quad bikes included; a wave only walks from staging when the side can afford nothing but troops (mostly the first attack of a round). Two roles:
  - Transport (quad bikes, offroads, trucks, unarmed MRAPs): carries infantry from staging to a dismount point on its approach, then parks there for regroup pickups or the next wave.
  - Combat (APCs, IFVs, tanks, armed MRAPs): carries its own infantry if it can, then goes in with the wave, staying 50 to 100 m behind the lead groups. It never pushes in alone: if the infantry stall, it holds and gives fire support.
  - Dismount point: one per approach, about 500 to 800 m from the target, out of the target's line of sight where terrain allows, outside the range of known AT and static weapons; the far end of that range for unscouted targets. Infantry continue on foot to the holding point, then in.
  - Buying: before the go, any group without transport gets one if CP stays above the reserve after buying: the cheapest vehicle that seats the group, bought at staging. Reuse vehicles already parked at staging or dismount points first. Buy combat vehicles when the threat summary calls for them (enemy armour, heavy statics) or when CP is plentiful.
  - Mount up: the go signal doesn't make groups abandon what they've called in. They finish kit swaps, collect vehicles they've bought that are still arriving, board, and pull out together, with a mount-up call on the radio. Cap mount-up at about 90 seconds; anything not ready by then follows the same approach as a second element.
  - Drives are short and road-first. Convoys on the same approach move together. A vehicle stuck twice is abandoned and its passengers walk from there (extend the watchdog for this).
  - Vehicles only ever move as part of a wave leg: no solo trips across the island.
- Gate: a wave heading into known armour leaves staging with at least 2 AT launchers per reported tank; an affordable wave drives to its dismount points rather than walking from staging; mount-up never exceeds about 90 s; no vehicle bought for a wave is left unused at staging when it departs; no vehicle makes a solo trip; combat vehicles never lead the infantry into the sector; the CP reserve holds.

## Phase 4: Defence and players
- Reserve sizing; counterattack detection and response; staging-sector abort; player reports feeding the board; side map markers for target, staging and approaches; the player request actions.
- Gate: in a scenario test, a counterattack on an owned sector gets a response within one commander tick of being detected, and the reserve stands down once the threat is gone. Player features can't be tested without players: confirm they cause no errors with none connected, and list them for me to test.

## Phase 5: Polish that needs no human
- Difficulty settings (intel decay, wave size, reaction delay, scan buying). Performance: log commander tick cost and server FPS; aim for an average tick cost well under 5 ms and server FPS within about 10% of the vanilla baseline. One LAMBS compatibility round. No Workshop packaging.

## Phase 6: smarter behaviours
(Added by the user during the run. Finish phases 0 to 5 as planned, then do this as phase 6, before the "if time remains" list. Add a "Phase 6: smarter behaviours" section to the design doc describing each one as built.)

Twelve cheap rules that make the commander read as thinking. Each gets its own on/off switch and tunables in the settings file, defaulting to on, so I can disable any one without touching code. Build them roughly in this order (the first three change the feel most), commit after each, and tag phase-6-done at the end. Test each with a short scenario test and an analyser check where it can be measured; one soak round at the end with everything on.

1. Break and consolidate. A group down to about a third of its strength pulls back to staging rather than fighting to the last man, then merges with another weak group of the same side into one usable group. Check: weakened groups retreat and merge rather than dying in place.
2. Livelier radio. Varied phrasings for every message type (several options each, picked at random), plus new calls: a group taking heavy fire or losses, a group breaking and falling back, a cheer when a sector falls. Keep cooldowns so it never spams. All radio text is player-visible: list every line you wrote in the hand-off so I can review them.
3. Reinforce success. If one approach breaks into the sector while another is pinned or stalled, redirect the stalled groups to follow the approach that's working. Check: in a scenario where one approach is blocked, its groups re-route.
4. Smoke before the push. Groups throw smoke between the holding point and the sector before the final push, angled to screen the approach from known enemy positions. Uses the units' own smoke grenades; give a smoke grenade or two at the staging crate if they have none.
5. Prep fire. If the side has mortars or artillery available (owned or affordable within the CP reserve rule), a short barrage lands on the target just before the infantry leave the holding points, and lifts before they arrive. Never fire on positions friendly units are in or close to.
6. Exploit momentum. If a wave takes its sector quickly with most of its strength left, and an adjacent sector is weakly held according to the intel board, push straight on to it without the full regroup cycle. Must still respect the defence reserve. Check: a fast, cheap capture next to a weak sector triggers a follow-on push.
7. Scout first. For an unscouted target, one small fast group (a quad bike or light vehicle where affordable) goes ahead to look while the wave gathers at staging. Its sightings feed the board before the go. It must not delay the go signal.
8. Hunt the unseen AT. When a friendly vehicle is destroyed by an attacker nobody saw, the nearest suitable group not in a wave's assault sweeps the likely firing area, then returns to its task.
9. Dig in after capture. Groups holding a newly captured sector take positions facing the most likely counterattack direction from the board (or towards enemy-held sectors if the board is empty), at building edges and cover, not in the middle of the circle.
10. Commander personality. At round start each side's commander randomly gets one personality (aggressive, cautious or sneaky) that shifts a few weights: go-signal timing, how wide the approaches spread, how much it spends on vehicles, how readily it exploits momentum. Log the chosen personality. Allow forcing one via a setting for testing.
11. Memory within a round. The commander remembers approaches where a wave took heavy losses at each sector and avoids or penalises them for later waves on that sector, so repeating the same ambush stops working. Check: a costly approach isn't reused for that sector's next wave.
12. Join the player's push. When a human player on the side is moving towards the current target, nearby AI groups that are free can attach and move with them, and the radio says so. Never take control away from the player or their own AI. Can't be tested without players: confirm it causes no errors with none connected, and list it for me to test.

In the hand-off and final message, add phase 6 results per feature (built, tested, PASS or FAIL, or untested and why), plus the radio lines list.

## If time remains
- More tuning soak rounds, aimed at pace: shorten anything that makes rounds drag without making them messier. An Altis smoke test proving nothing is Tanoa-specific. A local-only HEMTT addon packaging dry run.

## Deliverable for tomorrow
- A playable scenario installed in my profile's mpmissions folder (path in docs/local-environment.md), e.g. SmarterWarlords.Tanoa: stock Tanoa Warlords plus the commander, lobby defaults suited to a hosted ~8v8, debug overlay off but toggleable. If Warlords has a fast travel setting that stops players fast travelling into the contested sector while the commander's owned-sector fast travel still works, make that the default. Generated by the build script and gitignored, like the test mission.

## Finish
- Update the design doc: answered open questions, changed values and rules, and the decision log.
- Hand-off doc in the run folder: per phase, what was built, gate PASS or FAIL with evidence (log and plot paths), known issues, deferred items and red flags.
- Final message: per-phase gate results; how to load and host the playable scenario and toggle the debug overlay; what to test in an 8v8 that automation couldn't; any decisions I should review; anything that needs me.
