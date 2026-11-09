# Prompt: living front line run

Saved 2026-11-09 about 17:50. The user's covering message, verbatim:

> Save this and start working on it, don't interrupt the soak (unless you have to) but the absolute priority is having this built and as tested as possible in 2.5 hours time, so focus on getting all the code changes done as quickly as possible so the majority of the time can be spent focusing on testing/refining

That 2.5 hours overrides "No deadline" below. Target: built and tested by about 20:30.

The prompt's "Notes from my game" section was still its unfilled placeholder, so it was empty.

---

SmarterWarlords: living front line run. Make the fighting happen at and around the contested sector and in the ground between sectors, rather than rolling straight into the losing side's sectors: a side that loses a contested sector keeps fighting there and pours reinforcements and supplies into its holdouts, defenders keep fast travel to their own threatened sector until real fighting reaches it, and groups that meet the enemy on the way fight it out instead of being snapped back onto their route. Everything stays on the stock Tanoa Warlords layout. I won't be at the desk: never wait on me. Make the best call, write down why, and keep going.

Read first: CLAUDE.md; docs/local-environment.md; the design doc; docs/design/rules-variant.md; the latest run's folder docs/runs/2026-11-08-rules-variant/ (its hand-off if there is one, otherwise its progress log); tests/README.md; PLAYABLE.md. Build on what exists and follow its structure (adapter, settings file, muster and rally model, resilience, analyser, scenario scripts). Where this prompt conflicts with earlier rules, this prompt wins; record the conflict in the decision log. If that run left parts unfinished or gates failing, note them in the hand-off but don't spend this run finishing them unless they block the work below.

Save this prompt and a progress log in docs/runs/<today's date>-front-line/. The log must let you resume after compaction.

## Notes from my game
[OPTIONAL, FILL IN BEFORE PASTING: what felt wrong or good when we played. Delete this section if empty.]
Fix anything here that's clearly broken before starting part A, and list what you did in the hand-off.

## The idea, in my words
Teams one and two fight over X. Team one wins X and targets Y, one of team two's sectors. Team two doesn't just let its men at X die or withdraw: its priority is reinforcing and resupplying those holdouts, to keep the fighting at X and stop it drawing back towards its own sectors. Team two can still fast travel to Y, rally there and push back towards X to reinforce, so team one advancing from X towards Y meets team two coming the other way. Team two loses fast travel to Y only once there's real fighting at Y. From then on it can fast travel only to its other nearest sectors, and its main goal becomes defending Y and kicking team one out. Fast travel to Y is purely the defender's advantage. A single enemy sneaking into Y and hiding must never be able to switch it off.

## Ground rules
- Keep the stock Tanoa Warlords layout. Don't add, move or relink sectors.
- Commit at sensible points; tag each finished part (front-a-done, ...). Never push.
- Mods: vanilla for tests, except the final soak, which loads CBA_A3 and LAMBS stable (the way I play). Never LAMBS DEV, ASR AI3, Vcom or Advanced AI Command.
- No deadline. Work through the parts in order, then "if time remains".
- At most 2 Arma servers at once (the PC has crashed with 3); the final soak runs alone. Before starting any round, check free memory; if the machine is short (other heavy processes running), wait and recheck rather than starting.
- Helper agents for work that doesn't need a server (reading code, drafting, scenario scripts, analyser checks, the review), started while rounds run; never leave one waiting on a server.
- Never wait blindly on a round: check its log periodically (well within 45 minutes) and kill and investigate stalls.
- Big calls are yours: record them in the decision log in docs/design/rules-variant.md and in the hand-off.
- Every new rule and behaviour gets its own switch and tunables in settings.sqf, default on. The holdout and fast-travel rules count as rule changes and sit under the existing "Rules variant" lobby parameter; the meeting-engagement behaviour is AI behaviour and stays on with the rules variant off, like resilience.
- Everything applies to both sides, including a side with human players.
- Keep it releasable: nothing Tanoa-specific outside per-map settings. Keep Bohemia's files out of the repo.
- Anything players see that you write goes in the player-visible text list (wherever the project keeps it, otherwise in the hand-off).
- Add the spec for everything built here to docs/design/rules-variant.md as you build it.

## Part A: hold X, reinforce the holdouts
The losing side's priority is to keep the fight at X, not to fall back to its own sectors.
1. Holdouts stay. When a side loses a sector it was fighting over (call it X), its groups still at X keep fighting rather than withdrawing. Warlords kills AI inside a sector that is neither owned nor targeted, so make sure X stays that side's target (or is otherwise protected) while holdouts are inside; check this against Warlords' code.
2. Reinforcing the holdouts is the side's top priority while it has holdouts at X. New and free groups go to X to join them, ahead of any other job except defending a sector that already has active fighting (part C). Reinforcements don't wait to form a full wave: they go to the holdouts as soon as they're ready, in the existing "reinforce troops already fighting" mode, mustering at the side's nearest owned sector to X (call it Y) and driving or walking the last stretch.
3. Resupply the holdouts. Send ammunition and launchers to them: reinforcements carry extra and drop it with the holdouts, and the side buys a resupply crate delivered close to them (Warlords' own airdrop or crate purchase) when the holdouts are low and CP allows, within the CP reserve. Holdouts use the existing rearming rules to restock from it.
4. Holdouts dig in rather than charge: they hold the best cover in and around X (buildings, walls, treelines) and fight from there, so they last until reinforcements arrive. With LAMBS loaded, use its garrison for this.
5. Holdouts that break (the existing break-and-consolidate rule) fall back only to the nearest cover on the X side of the route towards Y and wait there for reinforcements, rather than retreating to Y or base, so the fight stays near X.
6. The losing side's target stays X: if the holdouts are wiped out before reinforcements arrive, the reinforcements carry on as a counterattack on X. The commitment timer still applies on top, so if X can't be held or retaken, the side can give up on it later.
7. The winning side, now targeting Y, musters at X and must push through the holdouts and the arriving reinforcements to reach Y. Its route to Y and the losing side's reinforcement route to X overlap, which is the point.
8. The stock layout has short distances between sectors. Check that both sides' rally and muster points still leave real ground between them on Tanoa's links; where a link is too short, place them so the sides meet in the open or at X rather than both sitting at sector edges, and note what you did per link.
Gates (scenario): when X falls with the losing side's groups still inside, they stay and fight; the side's target stays X; reinforcements head for the holdouts within a short time (tunable, report it) and arrive while holdouts are still alive in a reasonable share of runs; a resupply reaches the holdouts when they're low and CP allows; broken holdouts fall back no further than cover near X; with no holdouts left, the reinforcements counterattack X.

## Part B: defender fast travel until real fighting reaches Y
1. A side may fast travel to its own sector Y while the enemy is targeting it, until there is active fighting at Y. This is the defender's advantage, and it's how reinforcements for the holdouts at X get close quickly.
2. Active fighting at Y means all of these, all tunable:
   - Area: inside Y's capture area, or within about 175 m of its edge.
   - Both sides: gunfire from both sides in the area, or casualties there. One side shooting at nothing doesn't count.
   - Sustained: fighting detected for most of the last 60 to 90 seconds (for example in at least 2 of the last 3 thirty-second windows), not one shot or one grenade.
   - Numbers: at least 3 men of the attacking side involved. A lone sniper or infiltrator can never trigger it, hidden or shooting.
   - It also counts as active fighting while the enemy is seizing Y (Warlords already refuses fast travel into a sector being seized).
   - It lifts once the area has been quiet for about 2 minutes, so it doesn't flicker on and off during lulls.
3. While active fighting is on, that side can fast travel only to its other owned sectors, nearest first.
4. Warlords' fast travel setting 4 may already block fast travel into any contested sector, which may include Y as soon as the enemy targets it. Find out from Warlords' code. If it does, override it so defenders keep fast travel to Y until active fighting starts, for human players as well as the commander. Find the cleanest way to change what Warlords' fast travel menu offers players; if that's too invasive, implement the rule for the commander's groups only, and say so prominently in the final message.
5. The same active-fighting signal drives the commander's decision in part C, so the fast travel rule and the AI can never disagree about where the front is.
6. Radio lines when fast travel to a sector closes and reopens; the commander panel shows each threatened sector's fast travel state.
Gates (scenario): a lone enemy hidden in Y's area keeps fast travel open; a lone enemy shooting from inside Y keeps it open; 3 or more attackers in a sustained exchange close it within about 90 s; an enemy seizing Y closes it; 2 quiet minutes reopen it; the commander's fast travel follows the same state.

## Part C: switching between holding X and defending Y
1. When active fighting starts at Y, the losing side's main goal switches from holding and reinforcing X to defending Y and expelling the enemy:
   - groups already fighting at or near X carry on (never abandon a fight in progress), and keep using the resupply rules
   - groups at or near Y turn to defend it
   - new arrivals fast travel to the side's other nearest sectors and push into Y from there
2. Once Y is clear (no active fighting, and no enemy known inside Y's area for about 2 minutes), the goal switches back to reinforcing the holdouts at X or retaking it, unless the commitment timer has moved the side on.
3. Radio and panel show which it's doing ("Holding X", "Counterattacking X" or "Defending Y").
Gates (scenario): the goal switches to defending Y when active fighting starts there, and back to X once Y is clear; groups already in a fight near X are not pulled away.

## Part D: fights on the way are real fights
1. A group or wave in transit that meets the enemy stops and fights instead of being put back on its route: a new job state (for example "Engaged") with its own rules. It reports the contact on the radio (where, how strong), and nearby free groups of its side can join it, using the existing proportionate-response logic. When the contact is cleared, it carries on to where it was going.
2. If the enemy force is clearly much bigger, it falls back to the nearest owned sector, reports, and the commander treats that force as a threat in its own right (defend against it or send a wave at it), not just an obstacle.
3. Vehicles in transit that meet the enemy: combat vehicles fight with their infantry; transports dismount their passengers short of the contact and pull back.
4. Resilience must not fight this: an active firefight counts as progress for the sweep, the escalation ladder, the activity gate and the 4-minute no-progress check, and so does holding at X as a holdout while in contact. Cap it: a group that hasn't fired or been fired on for about 90 s is no longer "fighting", so nothing can sit in the Engaged or holdout state forever without the normal checks.
Gates (scenario): two waves on a collision course both stop and fight, the contact appears on the radio and the board, nearby groups join within the proportionate limits, no watchdog re-route or ladder rung fires on a group mid-fight, and survivors resume their route once it's clear. The sabotage scenario still passes.

## Part E: measure where the fighting happens
1. Make sure kills (and, if cheap to log, firefight contacts) are logged with position, side and time, in the test rounds and in the playable build.
2. Extend the analyser: classify every kill as inside the contested sector X's capture area, inside any other sector's capture area, at a sector edge (within about 200 m), or between sectors. Report the shares per 10-minute window and for the whole round, after the first sector clash.
3. Draw it on the plot: a heat map of where kills happened, over the sectors and links.
4. Report also: how long holdouts survived after a sector fell; time from losing a sector to the first reinforcements leaving for the holdouts and to them arriving; resupplies sent and delivered; how far the fighting moved from X towards Y over time; how often fast travel to a threatened sector closed and for how long; and how many Engaged contacts happened in transit.
5. Baseline: measure the same on a vanilla round (reuse the stored baseline log if it has the data, otherwise run a vanilla round) and on the current build before parts A to D, so the change is visible.
Gate: in the final soak, after a sector falls, the fighting stays at or around it, and in the ground towards the losing side's next sector, for clearly longer than the baseline, rather than rolling straight into the losing side's own sectors. Report the numbers either way; don't tune the rules just to hit a number if the rounds look wrong in the plots.

## Testing
- Short scenario tests for each part, with analyser checks printing PASS or FAIL. Batch them: run several scenarios per server launch where the scenario scripts allow, and only rerun what fails.
- Lint each build step; one short smoke round before each batch of scenario tests.
- One common-sense code review for parts A and B together and one for parts C to E (a single Opus reviewer each; no stacked reviews).
- Final soak: SmarterWarlords.Tanoa, everything on, CBA + LAMBS stable, alone on the machine. It doubles as the regression: all existing soak gates (activity, the 4-minute check, escalation rung counts) plus part E's measures. Then the sabotage scenario once on the final code, and a short smoke round with the rules variant off.

## If time remains
- Tuning soaks towards close rounds with a living front that still end.
- Mortars: add a mortar team or static mortar to both sides' asset lists in the scenario, so the commander's prep fire and "call artillery first" rules have something to use. Test that the commander buys and uses them.
- An after-action report: a tool that turns a round's RPT into a short page (timeline of captures, where the fighting was, each commander's activity).

## Deliverable
- The playable SmarterWarlords.Tanoa regenerated in my mpmissions folder after each finished part. Never leave it in a broken state.
- PLAYABLE.md updated each time: what's in the build, how to host, lobby settings for two humans plus AI against all-AI, what to look for in the front-line behaviour, known issues.

## Finish
- docs/design/rules-variant.md updated with parts A to E and the decision log.
- Hand-off doc in the run folder: per part, what was built, gates PASS or FAIL with evidence (log and plot paths), the baseline comparison from part E, the rally and muster placement per link from part A, known issues, deferred items, red flags, and the player-visible text list.
- Final message: per-part results; the front-line numbers against the baseline; whether players get the defender fast travel rule or only the commander does; what to look for when we play it; decisions to review; anything that needs me.

---

## Addition from the user, during the run (verbatim)

Also a side note but I really want the feeling of sustained intensive combat, so maybe relax the rally and prep point time requirements so that groups can set off as soon as their own individual commander is happy (I.e all the troops they've spawned in have gotten in a vehicle, let's go, type thing) and then at the rally point they only rally and wait if no other troops are already attacking that point, if they are, they go straight in to support those troops
