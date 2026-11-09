User's instruction when pasting this (2026-11-08): "Please save this prompt, and start working on it after you finish this one (although you are free to do prep work/intergrate parts from it into this run where it makes sense to do so, in fact, just merge them into one giant run please)"

---

SmarterWarlords: rules variant run. This builds on the commander from the overnight build (phases 0 to 6). It adds a set of game-mode rule changes, raids and probing, proportionate defence, a commander menu for players and smarter squad behaviour, then teaches the commander to use all of it. I won't be at the desk: never wait on me. Make the best call, write down why, and keep going.

Read first: CLAUDE.md; docs/local-environment.md; the design doc; the overnight build's hand-off in docs/runs/2026-11-08-overnight-build/; tests/README.md. Build on what exists and follow its structure (adapter, settings file, analyser). If something the overnight run built conflicts with this prompt, this prompt wins; note the conflict in the hand-off.

Save this prompt and a progress log in docs/runs/<today's date>-rules-variant/. The log must let you resume after compaction.

## My notes from playing v1.0
[FILL IN BEFORE PASTING: what felt wrong, broken or missing when we played. If empty, skip this section.]
Fix these first, before any new work, unless a note says otherwise.

## Ground rules
- Commit at sensible points; tag each finished part (rules-a-done, rules-b-done, ...). Never push.
- Mods: vanilla for every test, except part H's LAMBS tests, which load CBA_A3 and LAMBS stable only. Never LAMBS DEV, ASR AI3, Vcom or Advanced AI Command. I'll be playing with CBA and LAMBS loaded from now on, so everything must work both with and without them.
- No deadline. Work through the parts in order, then "if time remains".
- One Arma server at a time. Helper agents for work that doesn't need the server (reading Warlords or LAMBS code, drafting, analyser checks, the review), started while rounds run; never leave one waiting on the server.
- Never wait blindly on a round: check its log periodically (well within 45 minutes) and kill and investigate stalls.
- Big calls are yours: record them in a decision log in the new rules doc and the hand-off.
- Every new rule and behaviour gets its own on/off switch and tunables in the settings file, default on. Also add one lobby parameter, "Rules variant: on/off", that turns all of parts B to E's rule changes off at once, leaving vanilla Warlords rules with the smarter commander and squads.
- Keep it releasable: nothing Tanoa-specific outside per-map settings; nothing that blocks other maps.
- Commander logic runs wherever isServer is true (including a client host). Never take control of player-led groups or AI a player owns, except groups a player explicitly borrows through the commander menu.
- Anything players see that you write (radio lines, menu text, hints, map marker labels) goes in a list in the hand-off for me to review.
- Write the spec for everything in this run as a new doc, docs/design/rules-variant.md, as you build it. Add a pointer to it in CLAUDE.md.

## Part A: fixes from my notes
As above. Test each fix where it can be tested.

## Part B: breaking deadlocks
The vanilla baseline showed a 41-minute deadlock at Balavu: respawns kept defenders inside the capture area, the countdown kept resetting, and Warlords has no target timeout.
1. No respawning in a sector being seized. While a sector is being seized, its owner's respawn there is disabled; they respawn at the nearest owned sector not under attack, or their base.
2. Capture progress pauses instead of resetting. When attackers are pushed off, the countdown holds, then decays slowly (tunable) rather than snapping back to zero.
3. Target commitment timer. After about 10 to 12 minutes (tunable) on one target without a capture, that side may pick a new target.
   - AI sides: the commander decides from capture progress, recent wave outcomes and the loss ratio. Close to winning, it stays; clearly losing, it switches to another reachable sector (prefer one its probes found weak), or pulls back to defend and rebuild for a while.
   - Human sides: the vote reopens when the timer runs out, with a radio call. Warlords already has a paid voting reset (BIS_WLVotingResetEnabled, priced via CfgWLAssetCostOverride); reuse it if possible, e.g. made free once the timer expires.
   - No ping-pong: an abandoned target can't be picked again by that side for a while (tunable).
   - Settle first: whether the commander can trigger Warlords' voting reset for an AI side or needs its own way to change target; and that a capture countdown that keeps restarting counts as progress, so a side about to win doesn't switch away.
Gates (scenario tests): a deliberately deadlocked target gets a decision within timer + one commander tick; no defender respawns inside a sector being seized; capture progress pauses and decays as specified.

## Part C: economy and capabilities
Goal: stop the snowball where the leading side ends with tanks against defenders respawning in starter kit, and make the final base fight a real one. Sectors should give the leader a wider toolkit, not mainly more money.
1. Income: a flat base income, the same for both sides; a modest per-sector bonus with diminishing returns (the first few sectors count fully, each further one less; tunable curve); combat income for kills (weighted by what was destroyed, with bounties for armour and for wiping out a whole squad), captures, and successfully defending a sector.
2. Capabilities by sector type. Holding a sector of a type unlocks what it gives:
   - Airfield: jets and planes (as Warlords does now).
   - Harbour: boats (as now).
   - Military base: armour, and better infantry kit (AT, marksmen).
   - Industrial: cheaper vehicles, repair and rearm.
   - Town: bigger squad cap, faster respawn nearby.
   - Radio tower: cheaper scans, and enemy contacts the side has seen shown on the map.
   Warlords already gates assets by sector disposition (A, H, W requirements); extend that idea. Sector types live in per-map settings. Classify Tanoa's sectors yourself from their names, positions and what's there, and list your classification in the hand-off for me to check.
3. Supply lines: a capability only counts while its sector connects back to the side's base through owned sectors (use the sector graph). Cutting the enemy's chain removes their capabilities without capturing the sector itself.
4. Fortress base: a side's home base always offers full infantry kit, AT and AA launchers included, whatever else it holds, and has static defences.
5. Cheaper when cornered: purchases at your own base cost less while it's under attack (tunable discount).
6. Stretched supply: rearm and repair only work near your own base, industrial sectors or owned sectors within a set distance, so a final push needs a forward sector to stage from.
7. Sectors dig in: a sector held for a while gains light fortifications (sandbags, one static weapon) in sensible positions; newly captured sectors are the vulnerable ones.
8. Counterattack window: for a few minutes after losing a sector, the old owner can buy cheaper units near it to try to take it back.
9. Scale the AI side to the humans: an all-AI side gets a little more CP or more groups for each human player on the other side (tunable), aiming for a fair fight for two humans plus AI against all-AI.
10. Optional round time limit (lobby parameter, off by default): when it runs out, the side holding more sectors wins.
Gates (soak rounds compared with the vanilla baseline): the trailing side can still afford AT and vehicles late in the round; the final base fight lasts a meaningful time instead of being a walkover; the leading side still wins most rounds it leads clearly (rounds mustn't drag on forever); capabilities switch off when a supply chain is cut.

## Part D: raids and probing
1. Raid order. A secondary target a side can buy through the commander menu (part F): pay CP, pick an enemy front-line sector (adjacent to one you own) on the map. It's marked on your side's map only. Rules:
   - Seizing it takes 2 to 3 times as long as the main target (tunable).
   - Stealth: the enemy isn't told. They find out only when a picket sees the raiders or seizing starts.
   - One active raid per side, a cooldown after it ends, and an expiry if it isn't taken in time.
   - Warlords only runs seizing on the current target, so the mod handles raid captures itself. Read Warlords' seize logic before building this, and make raid captures consistent with it (ownership change, rewards, messages). This is the most invasive change in the run; get it right before anything builds on it.
2. Probes. Every so often the commander sends one spare group (by quad bike or light vehicle if affordable) to look at the weakest-looking or least-scouted enemy front-line sector. Everything it sees goes on the intel board. If the sector is lightly held and the probe wins its fight, the commander may buy a raid order there and let the probe start seizing; if it meets real resistance, it breaks off and pulls back. Probes only use groups the current wave can spare; probe more when the main attack is going badly, none when the side is short of men.
3. The AI side uses raid orders under exactly the same costs and limits as players. A raid that pulls defenders away from the main target counts as useful even if the raiders die; factor that into when to raid.
Gates: raid captures work end to end in a scenario test; the enemy gets no warning until spotting or seizing; probes happen, report and pull back when outmatched; the AI buys raids within the limits.

## Part E: front-line pickets and proportionate response
1. Pickets: every owned front-line sector keeps a small group (a fire team or one squad). Its job is to spot, report and delay, not to hold alone.
2. Defenders get a radio call when an enemy starts seizing one of their sectors.
3. Response scaled to the threat: the picket's report goes on the board; the commander sends just enough to beat the reported force with a margin, usually 1 or 2 groups, taken from the reserve first, then from the main attack's least-engaged groups (never ones mid-fight). Responders fast travel to the nearest safe owned sector, never into the one under attack, then move in.
4. Cap: no more than about a third of the main attack peels off for one raid. Bigger than that means it's a counterattack, and the full defence rules take over.
5. Escalate or return: if responders find more than reported, they call for help and the commander sends the next layer; if they win, they return to staging and rejoin the next wave, with a radio call.
6. The main push bends but doesn't break: if peeling groups off drops the current wave below a workable size, it holds at its holding points rather than pushing in or collapsing, and resumes when responders return.
Gates (scenario tests): a small raid on a front-line sector draws a proportionate response within the cap; responders return afterwards; a bigger attack escalates to the defence rules; the main wave holds rather than collapsing.

## Part F: commander menu
One scroll-menu action, "Commander...", opening a short list of options. Don't add anything to Warlords' own request menu. Options:
- Order raid on sector: pick an enemy front-line sector on the map (part D rules and costs).
- Send groups with me: ask for 2 to 3 groups to join you; they meet you and move with you until released.
- Hold the wave for us: hold the go signal for players on their way to staging, capped at about 2 minutes.
- Go now: launch the wave immediately if enough groups are at staging.
- Report contact: mark an enemy you've spotted; it goes on the intel board at high confidence.
- Defend this sector: give a chosen owned sector extra weight in the defence logic for a while.
- Request a pickup: a transport comes to your position.
- Release my groups: borrowed groups return to the commander.
- What's the plan?: the commander answers on the radio with the current target, staging point, wave timer and any active raid.
Every request goes through the commander's normal rules: it can refuse when it has nothing to spare and says why on the radio. Each option has a short cooldown. This replaces any earlier player request actions; remove or fold those in.
Gates: none of these can be tested without players. Confirm the action and every option cause no errors with no players connected, and list them for me to test.

## Part G: teach the commander the new rules
- Value sectors by what they unlock and by supply lines, not just position: target enemy capability sectors and weak links in their chain on purpose; protect its own.
- Use the target timer, raids and probes as described above, and fortress-aware buying (expect a hard final fight at the enemy base; stage the final push from a forward sector).
- Respond with pickets and proportionate response instead of all-or-nothing defence.
Gates: in soak rounds, the commander targets capability sectors and supply links noticeably more than chance; raids and probes happen at a sensible rate; no deadlock outlasts the timer.

## Part H: smarter squads
How commander-owned squads move and fight once they've been told where to go. All of it applies only to commander-owned groups (and groups a player has borrowed, while they follow that player's lead), never player-led groups.
1. Formation and speed that fit the situation: column at full speed on roads far from known enemies; a spread formation (wedge or line) across open ground; slower, more careful movement and lower stances in the last few hundred metres to the target or near known contacts. Use Arma's own formation, speed mode, behaviour and stance commands. Switch smoothly; don't thrash between modes every tick.
2. Bounding overwatch near the target: from the holding point inward, infantry squads split into two fire teams that leapfrog, one moving while the other holds and covers, then swapping, with sensible bound lengths (tunable, roughly 50 to 100 m) and each bound ending at cover where possible. Fall back to normal movement when the squad is too small to split, or when in close-quarters fighting.
3. Suppress and flank: when a squad is pinned by a known enemy position (heavy incoming fire, no progress), one fire team suppresses it (Arma's suppressive fire command) while the other moves round the side to a flanking position using cover, then assaults. Give up and fall back to the commander's normal handling if the flank fails or the squad takes heavy losses.
4. Rearming: soldiers low on ammunition, and especially AT or AA soldiers out of rockets, restock from the nearest safe source: a supply crate, a friendly vehicle's inventory, or a fallen friendly's kit, without wandering far from the squad. Respect part C's stretched-supply rules for crates.
5. Use LAMBS when it's loaded: detect LAMBS at runtime. When present, squads taking or holding a sector use its garrison and building-clearing tasks instead of our simpler positioning, and our squad behaviours must not fight its danger handling (read LAMBS' own docs and code for how to hand off cleanly, e.g. not overriding its reactions mid-contact). When absent, everything works on our own behaviours.
Gates (scenario tests, vanilla and again with CBA + LAMBS stable): squads use the right formation and speed per situation; bounding happens near the target with both teams alternating; a squad pinned by a placed enemy MG suppresses and flanks; an AT soldier out of rockets restocks before rejoining; with LAMBS loaded, squads garrison and clear captured sectors through LAMBS with no script errors and no fighting between our orders and LAMBS reactions.

## Testing
- Same approach as the overnight build: short scenario tests with injected situations for each part, analyser checks printing PASS or FAIL, and soak rounds on full Tanoa. Extend tools/analyse_round.py with this run's checks.
- Balance needs soak rounds compared with the vanilla baseline and the overnight build's final soak: track man counts and the trailing side's CP and kit over time, round length, the longest single-target fight, and how many raids, probes and responses happened. Look at the plots, not just the numbers.
- One common-sense code review per part before its final commit (a single Opus reviewer; no stacked reviews). In-depth testing of what each part built. At the end: a full regression with everything on, one soak with CBA + LAMBS loaded (the way I'll play), and one soak with the rules variant off to prove vanilla rules still work.

## If time remains
- More balance soak rounds, tuning towards close, dynamic rounds that still end.
- An Altis smoke test with the rules variant on, including classifying Altis sectors (list them for me to check).

## Deliverable
- The playable SmarterWarlords.Tanoa scenario regenerated in my mpmissions folder, with the rules variant on by default, the "Rules variant" and round time limit lobby parameters available, and the debug overlay off but toggleable. It must work with and without CBA + LAMBS loaded.

## Finish
- docs/design/rules-variant.md complete, with the decision log.
- Hand-off doc in the run folder: per part, what was built, gates PASS or FAIL with evidence, known issues, deferred items and red flags; the Tanoa sector classification; the list of player-visible text.
- Final message: per-part gate results; what changed for us as players; what to test in a hosted round (especially the commander menu, raids with borrowed groups, squad behaviour up close, and the final base fight); decisions to review; anything that needs me.

## Addition from the user, during the run

"Will you also make sure you do fairly rigirous testing, to ensure that commanders are actively doing stuff during the rounds?"

Treat this as a gate on every soak round: measured per commander, pass or fail, reported per round in the hand-off and final message.
