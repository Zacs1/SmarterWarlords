# Smarter Warlords — AI Commander Design

Nov 8, 2026 · @Zachary Holt

## Overview

The goal is a side commander that makes Warlords AI fight like an army: stage at the nearest owned sector, share intel, prepare for what is actually in the target, then attack in coordinated waves. The individual soldiers stay as they are; only the layer giving them orders changes.

Vanilla Warlords has no such layer. Each AI group is handed the current target and makes its own way there, so groups trickle in one at a time, drive off in purchased vehicles and get spread out, and often stall after a firefight with no orders left. Late in a round, when the front is far from base and the AI have CP to spend, a large share of each side ends up idle in open country.

What success looks like in play:

- Every AI group is visibly doing something purposeful at all times: travelling, staging, attacking, defending or regrouping.
- Attacks arrive as waves of several groups at once, not a trickle.
- Groups heading into a sector with known armour carry AT; groups heading into a heavily held town bring more firepower.
- Radio chatter tells human players what the AI knows and what it is about to do.
- The commander only acts on what its soldiers have seen, so it can be surprised, misled and outplayed.

## Design principles

Six rules shape every decision below; when a feature conflicts with one, the rule wins.

1. **No omniscience.** The commander knows only what its soldiers have seen, heard or scanned. It never reads enemy positions from the engine directly. This keeps it fair and makes it beatable in interesting ways.
2. **Orchestrate, don't micromanage.** The commander hands out group-level orders (move here, hold, attack from this direction). How soldiers fight once they arrive is left to the engine or a soldier-level AI mod.
3. **Rule-based and readable.** Every decision comes from explicit rules and weighted scores, with no machine learning and no LLM at runtime. If the AI does something dumb, the debug overlay shows which rule fired and why.
4. **Layer on Warlords, don't fork it.** Warlords keeps owning sectors, CP, voting, purchasing and respawn. The commander sits on top and steers AI groups. This keeps maintenance small when Bohemia patches the mode.
5. **Cheap to run.** The commander thinks on a slow tick (every 10 to 20 seconds), runs only on the server, and does no per-frame work. Big games with 100+ AI must not lose frame rate to it.
6. **Visible intent.** Players should be able to read what the AI is doing from radio chatter and behaviour alone. An army that is clearly gathering in a village feels alive even before it attacks. Staging should look like an operation gearing up, not men standing around: soldiers running to the crate, vehicles arriving and lining up, a mount-up call on the radio, then convoys pulling out together. Fast travel only ever goes to safe owned sectors, never into the contested one, so the last leg is always driven or walked.

## Architecture

One commander runs per side on the server, reading enemy information only from its side's intel board and talking to Warlords only through a single adapter.

&#91;embedded content: architecture · one commander per side\]

Warlords keeps running its own systems; everything that touches Warlords internals lives in the adapter, so a Bohemia patch means fixing one file.

- **Side commander.** The brain: one per side, on a slow server tick. Owns the decision loop, the wave, the reserve and the shopping list.
- **Intel board.** Shared memory of enemy sightings for the side, fed by AI groups, players and scans.
- **AI groups.** Every AI-led group on BLUFOR and OPFOR. Each has a task state and is checked by the watchdog. Independent garrisons stay under Warlords.
- **Warlords adapter.** Reads target, sector ownership and CP; performs moves, fast travel, purchases and scans the way Warlords does.
- **Radio and markers.** Turns commander decisions and key sightings into side chat and map markers.

## The intel board

Each side keeps one shared board of enemy sightings, and it is the only source of enemy information the commander uses. Every few seconds, each friendly group's leader posts what the group currently knows about, using Arma's own per-group target knowledge (`targets`, `targetsQuery`, `knowsAbout`). The board merges duplicates, ages old reports and summarises them per sector.

### What a sighting holds

| Field | Meaning | Example |
| --- | --- | --- |
| Category | Infantry, light vehicle, APC/IFV, tank, static weapon, helicopter, jet, boat | Tank |
| Position | Last known position, with the reporter's position error | Kore, north road, ±40 m |
| Count | How many of that category in the cluster | 1 |
| Reported by | Group that saw it, used for the radio message | Bravo 2 |
| Time seen | Game time of the latest confirmation | 14:32:10 |
| Confidence | 0 to 1, from knowledge level and age | 0.85 |
| Sector | Nearest Warlords sector within 600 m, or none | Kore |

### Merging and decay

- **Clustering.** Sightings of the same category within about 75 m (infantry) or 150 m (vehicles) merge into one entry; the count is the highest seen at once, not the sum, so the same squad seen twice isn't counted as two.
- **Decay.** Confidence falls over time: infantry reports halve in about 3 minutes, vehicles in about 5, static weapons in about 15 (they don't move). Below 0.15 the entry is dropped.
- **Confirmed kills.** When a group kills a reported target, the entry is reduced or removed at once.
- **Negative information.** A group that passes through an area and sees nothing lowers confidence for entries there. This stops ghost tanks from scaring the AI for ten minutes after they've left.

### Other inputs

- **Warlords sector scan.** When a side buys a scan, the revealed units are posted at confidence 1. The commander can buy scans itself before a big wave (see the decision loop).
- **Human players.** Targets players spot and report (map markers, the vanilla report command, or a scroll-menu action) go on the board at high confidence. Spotting for your AI should matter.
- **Losses.** A friendly vehicle destroyed by an unseen attacker posts a low-confidence 'unknown AT threat' near its position.

### Per-sector threat summary

The commander doesn't read raw sightings. It reads a summary per sector, rebuilt each tick:

- infantry strength (estimated soldiers)
- armour (count of tanks and IFVs)
- light vehicles and static weapons
- air threat (helicopters and jets operating nearby)
- freshness (age of the newest report) and whether the sector is effectively unscouted

## Commander decision loop

Each side's commander runs a fixed cycle every tick (10 to 20 seconds): refresh intel, check defence, then advance the current wave through stage, launch and resolve. One wave is in flight at a time per side, with the next one already gathering.

&#91;embedded content: commander loop · one wave in flight per side\]

Defence always gets checked first; a failed wave feeds its survivors and everything it saw into the next one rather than trickling back in.

### 1. Target

Warlords' vote decides the target, so the commander normally takes it as given. When AI voting is enabled (`BIS_WLAIVoting`), the commander casts the AI votes, scoring each reachable sector by value against known defence:

- **Value:** income, whether it unlocks further sectors, closeness to own front
- **Cost:** known defenders from the intel board, scaled up if the sector is unscouted
- Prefer sectors adjacent to a sector we already own, so a staging point exists

### 2. Staging sector

The staging sector is the owned sector that best balances closeness to the target and safety:

- Candidates: owned sectors within about 2.5 km of the target, otherwise the closest owned sector on the sector graph
- Score: shorter distance to target is better; known enemy within 500 m of the candidate is a heavy penalty; good cover (buildings, woods) is a small bonus
- If no owned sector qualifies, stage at a safe point 600 to 900 m from the target on the side facing our territory

The commander announces the staging sector on radio and marks it for the side.

### 3. Assemble the wave

- Unassigned and regrouped groups are sent to staging, by fast travel where Warlords allows it for AI, otherwise on foot or by transport.
- **Who goes** is every group that has reached staging when the go signal comes. The threat summary shapes what the wave takes (AT, extra transport, a combat vehicle), not how long it waits. Unscouted targets get a sector scan before the go if it's affordable.
- **Go signal:** the wave goes when 3 or more groups have reached staging, or 4 minutes after the first one arrived, whichever comes first. No extensions: pace matters more than a perfect wave, and late arrivals join the next one.

### 4. Launch

**Mount up first.** On the go signal, groups don't drop what they're doing: they finish kit swaps, collect vehicles they've bought that are still arriving, board, and pull out together, with a mount-up call on the radio. Mount-up is capped at about 90 seconds; anything not ready by then follows the same approach as a second element rather than being abandoned.

- Groups get attack waypoints at the same moment, split across two or three approach directions about 60 to 120 degrees apart, chosen to avoid known static weapon arcs and open ground where possible.
- Each approach has a holding point 300 to 400 m out; groups pause there until all approaches report in (or 60 seconds pass), then go in together.
- Where the wave has vehicles, they drive groups to each approach's dismount point first, and combat vehicles then advance with the infantry (see Vehicles in the attack).

### 5. Resolve

- **Success:** the sector is seized. Survivors become the garrison or rejoin the next wave; the next target's staging begins.
- **Failure:** the wave falls below 35% of launch strength, or makes no progress for several minutes. Survivors regroup at staging; the next wave launches with the board updated by everything the failed wave saw.
- **Abort:** the staging sector comes under threat. Every staging and holding group switches to Defence.

## Loadout and asset prep

While groups wait at the staging sector, the commander equips the wave for the threat summary of the target, then spends CP on whatever kit can't cover. Each threat maps to a counter:

| Known threat at target | Kit change at staging | CP purchase if kit isn't enough | Wave rule |
| --- | --- | --- | --- |
| 1+ tanks or IFVs | 2 AT launchers per group (one AT specialist plus one swapped rifleman) | AT team, or own IFV/tank if the side has more CP than the threshold | Kit swaps bring AT to 2 × armour count before the go |
| Light vehicles or technicals | 1 AT or LAT per group | none | Normal launch |
| Static MGs or GMGs | Extra smoke, 1 marksman per wave | Mortar or artillery strike if available in the asset list | Approach from the static's flank, not its arc |
| Helicopters overhead | 1 AA launcher per wave | AA vehicle | Prefer approaches with tree cover |
| Heavy infantry (2× our wave or more) | Extra ammo and grenades | More infantry, or an APC to carry the wave | Call artillery first if available; add a combat vehicle if affordable |
| Nothing known (unscouted) | Standard kit | Sector scan before launch if affordable | Send a recon group first, launch on its report |

### How kit is changed

- A supply crate at the staging sector acts as the source. Units walk to it and the kit swap is applied by script (`addWeapon`, `addMagazines`), so players can see soldiers gearing up.
- Swaps use launchers from the side's own faction config so mods and custom factions keep working.
- Kit swaps are free and fast; purchases cost CP and time. The commander always tries kit first.

### Spending CP

Warlords AI already buy units and vehicles from the requisition list. The commander changes what they buy, not how: it sets a side-wide shopping list from the threat summary, and AI purchases are steered to it. Two limits keep spending sane:

- A **reserve** of CP is held back for counterattack defence and scans.
- **Vehicles only move as part of a wave.** They carry groups from staging towards the target and fight alongside the infantry (see Vehicles in the attack), but never make solo trips across the island. This kills the late-game problem of AI driving off alone.

### Vehicles in the attack

Where CP allows, waves drive most of the way to the target and walk only the last stretch. Vehicles in a wave have one of two roles.

| Role | Examples | What it does | Stops at |
| --- | --- | --- | --- |
| Transport | Offroads, trucks, quad bikes, unarmed MRAPs | Carries infantry from staging to a dismount point on its approach | The dismount point, where it parks for regroup pickups or the next wave |
| Combat | APCs, IFVs, tanks, armed MRAPs | Carries its own infantry if it can, then fights with the wave | Goes in with the infantry, staying 50 to 100 m behind the lead groups |

- **Dismount point.** One per approach, about 500 to 800 m from the target, out of the target's line of sight where the terrain allows and outside the range of known AT and static weapons. Infantry get out and continue on foot to the holding point, then in.
- **Affordability.** Before a wave launches, any group without transport gets one if the side's CP stays above its reserve after buying: the cheapest vehicle that seats the group, bought at staging. Vehicles already parked at staging or at dismount points from earlier waves are reused first. Combat vehicles are bought when the threat summary calls for them (enemy armour, heavy statics) or when CP is plentiful. Transport is the default whenever it's affordable, quad bikes included; only a side that can afford nothing but troops walks, which mostly means the first attack of a round. The CP reserve scales with income so it never stops an early side buying cheap transport.
- **Combat vehicles never go in alone.** If the infantry stall, the vehicle holds and gives fire support from where it is rather than pushing ahead.
- **Short, road-first drives.** Staging is within about 2.5 km, so drives are short. Routes prefer roads. A vehicle stuck twice gets abandoned, and its passengers walk from there.
- **Unscouted targets.** Dismount further out (the far end of the range) since nothing is known about AT in the target.

## Squad behaviour and watchdog

Every AI group the commander owns is always in exactly one task state, and a watchdog makes sure no group sits in one state longer than it should. This is the direct fix for AI 'making peace with the wilderness'.

### Task states

| State | What the group does | Normal exit | Time limit before watchdog acts |
| --- | --- | --- | --- |
| Unassigned | Just spawned or just released | Commander assigns a task next tick | 1 tick |
| Travelling | Fast travels or moves to its staging or defence sector | Arrives within 75 m | 3 min with no progress |
| Staging | Holds a position in the staging sector, gears up | Wave launched or reassigned | Wave timer (see decision loop) |
| Assaulting | Moves on its assigned approach to the target | Sector seized, wave failed, or group broken | 4 min with no progress and no contact |
| Defending | Holds positions in an owned sector under threat | Threat gone for 2 min | none while threat remains |
| Regrouping | Falls back to staging after a failed wave | Arrives, rejoins the next wave | 3 min with no progress |
| Recon | Moves ahead to scout an unscouted target | Reports, or is killed | 5 min |

### The watchdog

Every tick, for each group:

1. **Progress check.** Compare the leader's distance to its goal with the value two minutes ago. Less than 50 m closer, not in combat, and not staging or defending means the group is stuck.
2. **Post-contact reset.** After a firefight ends (no `knowsAbout` gain and no shots for 45 seconds), re-issue the group's current waypoints. Arma groups often lose their remaining waypoints after contact; this restores them.
3. **Vehicle unstick.** A vehicle that is stuck twice in a row is abandoned: crew dismount and continue on foot, and the vehicle is left for Warlords' cleanup.
4. **Escalation.** A group stuck after two resets is fast travelled to the nearest owned sector on its route (if fast travel is enabled for AI) or reassigned to the nearest useful task. Nothing is ever left idle.
5. **Logging.** Every watchdog action is logged with the group, state and reason, so stuck spots on the map show up in testing.

## Defence

The commander splits its groups between the current attack and a defence reserve, so a counterattack on an owned sector gets a response instead of being ignored. Without it, every group chases the current target and owned sectors behind the front are left empty.

### Detecting a counterattack

An owned sector is **threatened** when the intel board shows enemy strength inside or within 400 m of it above a threshold (for example 4+ infantry, or any armour), or when Warlords reports the enemy is seizing it.

### Responding

1. **Reserve first.** One or two groups are always held as a reserve, staged at a central owned sector. They respond to threats before any attacking group is pulled.
2. **Weigh the trade.** If the threat is bigger than the reserve can handle, the commander compares the value of the threatened sector (income, whether it is the staging sector, how close to base) with the value of the current attack. It pulls attacking groups only if the threatened sector is worth more.
3. **Staging sector is special.** A threat to the staging sector itself makes every staging group switch to Defending at once, since losing it breaks the wave.
4. **Defensive positions.** Defenders take building and edge positions facing the threat's direction (from the board), not a random spot in the circle.
5. **Stand down.** When the threat has been gone for two minutes, defenders return to Reserve or rejoin the attack.

The reserve size scales with how much the side owns: 1 group for up to 5 sectors, 2 for 6 to 10, 3 beyond that.

## Radio and player integration

Radio chatter is how players see the commander thinking, so every important decision produces a short side-channel message. It runs on `sideChat` text at first and can move to `sideRadio` with recorded or generated voice lines later.

### Message types

| Trigger | Sender | Example |
| --- | --- | --- |
| New high-value sighting (armour, statics, air) | Reporting group | "Bravo 2: enemy armour at Kore, north road." |
| Target chosen and staging point set | HQ | "HQ: all units, stage at Agios Dionysios for the push on Kore." |
| Group arrives at staging | Group | "Charlie 1 in position at staging." |
| Kit change for known threat | HQ | "HQ: armour reported at Kore. Staging units, draw AT." |
| Wave launched | HQ | "HQ: wave one, move out. Bravo north, Charlie east." |
| Sector seized or wave failed | HQ | "HQ: Kore is ours." / "HQ: pull back to staging, regroup." |
| Counterattack detected | Defending group or HQ | "Delta 1: contact at Neochori, infantry from the south." |

Rules: a cooldown per message type (about 30 seconds) so the channel doesn't flood, grid references or named locations instead of coordinates, and nothing the side doesn't actually know.

### Human players on the same side

- **Feed the board.** Enemies players spot and report go on the intel board at high confidence (see the intel board).
- **See the plan.** The staging point, wave timer and approach routes show as side map markers, so players can join the push.
- **Light requests.** A scroll-menu or comm-menu action lets a player ask the commander for something simple: "attack with me on my next push" pulls the next wave's timing forward if groups are ready, "defend this sector" adds weight to a sector for the defence logic. The commander can refuse when it has nothing spare, and says so on radio.
- **No player orders over AI it doesn't own.** Players' own purchased AI squads stay under player control; the commander only directs side AI groups.

## Integration with Warlords

The commander ships first as a server-side script added to a copy of an official Warlords scenario, then as a standalone addon once the hooks are proven. Warlords keeps running every system it owns; the commander reads its state and steers only AI-led groups.

### What Warlords gives us

From the [official setup guide](https://community.bistudio.com/wiki/MP_Warlords):

- **Sector graph.** A scenario is a Warlords Init module, two Base modules and Sector modules synced together; the links define which sectors unlock which. Staging-sector choice can walk this graph.
- **Lobby parameters** the commander depends on: `BIS_WLFTEnabled` (fast travel mode, five options), `BIS_WLAIVoting` (AI vote on the next target, off by default), `BIS_WLScanEnabled` (sector scans), `BIS_WLStartCP` and `BIS_WLCPMultiplier`.
- **Asset lists.** Purchasable assets come from `CfgWLRequisitionPresets` (Infantry, Vehicles, Aircraft, Naval, Gear, Defences, each with a CP cost and site requirements). `WLAIRequisitonBlacklist` keeps assets player-only, and `CfgWLAssetCostOverride` changes prices, including fast travel and scans. The shopping list in Loadout and asset prep is built from the same lists.
- **Functions.** The mode's functions are in the `BIS_fnc_WL…` family (for example `BIS_fnc_WLInit` and `BIS_fnc_WLRequestPurchase`), but the wiki pages for them are placeholders with no parameters documented. The official scenarios sit in `missions_f_warlords.pbo` under the Arma 3 Addons folder.

### Hooks to build

| Hook | Read or write | How |
| --- | --- | --- |
| Current target per side | Read | Find the variable Warlords sets after voting; fall back to watching sector state changes |
| Owned sectors per side | Read | Sector module ownership, or Warlords' own sector list |
| Which groups the commander owns | Read | AI-led groups on BLUFOR and OPFOR (no player leader), excluding independent garrisons |
| Group orders | Write | Replace waypoints on owned groups; re-assert if Warlords' own AI loop overwrites them |
| AI purchases | Write | Either steer Warlords' AI buying, or buy through the same request path as players |
| Fast travel for AI | Write | Move groups to an owned sector the same way Warlords' fast travel does, respecting `BIS_WLFTEnabled` and CP cost |
| Sector scan | Write | Trigger a scan for the side, paying its CP cost |

### Open questions to settle by reading the code

1. Where Warlords keeps the current target and sector ownership (variable names, and whether they are public).
2. Whether Warlords' AI loop can be switched off for groups the commander owns, or whether it must be overridden every tick.
3. How AI purchases and AI fast travel are triggered internally, so the commander uses the same paths and costs.
4. What changes on a dedicated server; one report says AI stall after the first sector there when fast travel is off ([feedback tracker](https://feedback.bistudio.com/T156979)).

Step one of the build is to unpack the Warlords function and mission PBOs and answer these four questions before writing any commander code.

### Answers (from reading the code, then checked in the phase 0 gate round)

1. **Target and ownership.** The target is the public `BIS_WL_currentSector_<side>`, objNull while a vote is running (19 s or more) and not cleared when the enemy takes the sector. Owner is `BIS_WL_sectorSide` on the sector logic. `BIS_WL_conqueredSectors_*` is not the same thing as owned. Sector logics are moved to [100,100] briefly during capture, so positions are cached once at start.
2. **Warlords' AI loop.** There is one `fn_WLAICore.fsm` per Warlord on the server and no per-group off switch. It only writes waypoints when it enters `fight`, `fast_travel`, `defend` or `defend_1`, so the commander **steers** instead of forking: it writes its own waypoints and a guard restores them every 3 s if anything changes them. In the gate round the ordered group walked 870 m on the commander's order with no drift, and the order was back on the group after its members died and respawned at base. The stuck-unit script (nudge, then `setDamage 1` after about 9 minutes under 1 m of movement per 90 s) means holding groups must shuffle.
3. **Purchases and fast travel.** The AI buys through `BIS_fnc_WLAirdrop` after a random pick; the commander debits funds and calls the same function. CP (`BIS_WL_funds`) sits on each unit with no side pool, and every Warlord gets the full side income; the commander only spends AI Warlords' funds. AI fast travel is an FSM state with an FSM-level rule check, so the adapter enforces the rules itself: owned sector only, not while enemies are within 200 m, 50 CP (`BIS_WL_FTCost`) charged like vanilla.
4. **Dedicated server.** Tracker T156979 (AI stall after the first sector with fast travel off) is not confirmed by the code. `BIS_WLFTEnabled` values are: 1 everyone, 0 off, 2 off for AI, 3 off for players, 4 only to owned sectors (attack fast travel off in the FSM, defend fast travel on). The commander targets value 4 and the gate round confirmed voting continues past the first capture. Hosted games: the server waits for the host's own side setup; vanilla scans look broken on an all-AI side, so the commander reads scan results itself.

## Soldier-level AI

The commander does not touch how individual soldiers fight; for cover, suppression and flinching, pair it with an existing soldier AI mod, with LAMBS Danger as the default. Vanilla soldiers' weak reaction to being shot at is a separate problem from the one this design solves, and it is already well served by mods.

- **[LAMBS Danger.fsm](https://steamcommunity.com/sharedfiles/filedetails/changelog/1858075458?l=danish)** is the default pick. It replaces the vanilla danger reactions; version 2.5 added infantry cover seeking and better fleeing under suppression ([changelog](https://steamcommunity.com/sharedfiles/filedetails/changelog/2434257231?p=3)), and 2.6.1 fixed AI knowing more than they should. It also keeps a separate dev branch on the Workshop.
- **Overlap to manage.** LAMBS already shares combat information between nearby units over a radio range per side, set by CBA settings such as `lambs_danger_radio_WEST` ([changelog](https://steamcommunity.com/sharedfiles/filedetails/changelog/1858075458?p=3)). Keep that as the local, squad-to-squad layer; the intel board is the strategic, side-wide layer. The commander must not double-count information LAMBS has already shared.
- **Waypoint conflicts.** LAMBS has its own task modules and waypoint types. Groups the commander owns should use plain move and seek-and-destroy waypoints, and LAMBS tasks should be left to mission makers.
- **Alternative.** [DCO Soldier FSM](https://steamcommunity.com/sharedfiles/filedetails/changelog/2825929474?p=7) focuses on hiding: units hide from vehicles they hear, use buildings, and change position when hit in cover. Worth testing against LAMBS.

The commander must work with no soldier AI mod loaded too, so vanilla servers can run it.

## Debugging and tuning

Tuning will take far longer than writing, so the debug tools are built in phase one, not bolted on later. Every number in this doc (decay times, wave sizes, thresholds, timers) is a starting value to tune, kept in one settings file.

### Debug overlay

A toggle (server admin or editor only) draws on the map:

- intel board entries as icons sized by count and faded by confidence
- the current target, the staging sector and each wave's approach lines
- every owned group labelled with its task state and time in state
- watchdog actions as short-lived markers where they fired
- the commander's last decision and the score that won it, as on-screen text

### Logs

Every decision, wave launch, kit change, purchase and watchdog action goes to the RPT log with a timestamp and a short tag, so a round can be read back afterwards. A small script can turn a log into a per-round summary: waves launched, how many succeeded, average staging wait, groups stuck and where.

### Test rounds

- **AI vs AI.** Fill both sides with AI and spectate. Both commanders running against each other is the fastest way to see whether waves form and land.
- **Speed up.** In a single-player editor preview, raise simulation speed to watch a round in a fraction of the time.
- **Fixed scenarios.** Keep two or three small test scenarios (a short Altis chain, a Stratis map, a Tanoa map) so changes can be compared like for like.
- **What to watch.** Idle groups in open country, waves arriving piecemeal, kit not matching the reported threat, the reserve never moving, and radio spam.

## Build phases

Six phases, numbered 0 to 5, each ending in something testable, and each gated on a play test that shows it works before the next starts. Phase 1 alone fixes the problem that started this.

1. **Phase 0, read Warlords.** Unpack the Warlords PBOs, answer the four open questions in Integration with Warlords, and write the adapter: current target, owned sectors, owned groups, move, fast travel, purchase.
   - Gate: a test script can print each side's target and owned sectors, and move one AI group to a chosen sector without Warlords overriding it.
2. **Phase 1, staging, waves and watchdog.** Staging sector choice, the wave cycle, task states, the watchdog, the debug overlay and logs. No intel board yet: waves use group count only.
   - Gate: in an AI vs AI round, no group sits idle for more than three minutes, and attacks arrive as waves of three or more groups.
3. **Phase 2, intel board and radio.** Sightings, decay, per-sector summaries, radio messages, and threat-aware wave sizes.
   - Gate: armour spotted at a target appears on the board and on radio within ten seconds, and the next wave's kit and vehicles change to match.
4. **Phase 3, loadouts and purchasing.** Kit swaps at staging, the shopping list, CP reserve, transport and combat vehicles in the attack, and buying scans for unscouted targets.
   - Gate: a wave heading into known armour leaves staging with at least twice as many AT launchers as reported tanks, and an affordable wave drives to its dismount points instead of walking from staging.
5. **Phase 4, defence and players.** Reserve, counterattack response, player reports on the board, side map markers for the plan, and the player request actions.
   - Gate: a counterattack on an owned sector gets a response within one commander tick of being detected.
6. **Phase 5, polish and release.** Settings for difficulty, performance profiling on the largest scenario, LAMBS compatibility testing, packaging as an addon, and a Workshop page.

## Risks and open questions

The biggest risk is fighting Warlords' own AI loop for control of the same groups; everything else is tuning. Each risk below has a fallback.

| Risk | Likelihood | Fallback |
| --- | --- | --- |
| Warlords' AI loop keeps overwriting the commander's waypoints | High until the code is read | Re-assert orders each tick for owned groups; at worst, replace Warlords' AI loop with ours in a forked scenario |
| Warlords internals are private or change in a patch | Medium | Read state from sector modules and public variables only; keep all hooks in one adapter file |
| Engine pathfinding still strands groups, especially vehicles | High | The watchdog: reset, dismount, fast travel; vehicles only used to reach staging |
| Waves wait too long and rounds drag | Medium | Hard cap on the staging timer; launch with what's there and say so on radio |
| Commander is too strong for human players | Low to medium | Difficulty setting: intel decay, wave size, reaction delay, whether it buys scans |
| Server performance with 100+ AI | Medium | Slow tick, work spread across ticks, no per-frame code; profile in the large Altis scenario |
| Conflicts with LAMBS or other AI mods | Medium | Owned groups use only plain waypoints; test with and without each mod |
| Scope creep eats evenings meant for other projects | High | Ship phase 1 as a playable script before starting phase 2; stop and judge it in play |

### Decisions

1. **Who it's for.** The v1.0 bar is a locally hosted co-op round: two humans plus AI on one side against an all-AI enemy side, around 8v8. Single-player and public servers with mixed AI are goals after that, and the design shouldn't block them.
2. **Map.** v1.0 targets Tanoa. All base-game maps (Altis, Stratis, Malden, Livonia and the rest) come after, so nothing map-specific goes outside per-map settings.
3. **Release.** Built for personal use first; a Workshop release follows if it turns out well, so code should stay in releasable shape (no hardcoded paths, settings in one file).

### Decision log (from the build)

1. **Steer rather than fork Warlords' AI.** One FSM per Warlord, no per-group off switch, so the commander re-asserts its own waypoints. A forked scenario would break on every Bohemia patch.
2. **The commander replaces vehicle buying; infantry top-ups stay vanilla until phase 3.** Vanilla buys armed vehicles at random and never buys unarmed transport.
3. **Fast travel value 4 is the scenario default.** Only owned sectors, so fast travel never lands in the contested sector.
4. **A wave cap beats the "one wave in flight" rule.** The prompt's "no extensions" wins over the design doc's one-at-a-time rule: the next wave waits for the previous wave to reach its assault, but the 4-minute staging cap always launches it.

## Sources

- [MP Warlords setup guide](https://community.bistudio.com/wiki/MP_Warlords) (Bohemia community wiki): modules, lobby parameters, asset lists, AI purchase blacklist, cost overrides
- [BIS\_fnc\_WLInit](https://community.bistudio.com/wiki/BIS_fnc_WLInit) and [BIS\_fnc\_WLRequestPurchase](https://community.bistudio.com/wiki/BIS_fnc_WLRequestPurchase): Warlords function pages (placeholders only)
- [AI inactivity in Warlords](https://feedback.bistudio.com/T192841) and [AI stalls on dedicated server without fast travel](https://feedback.bistudio.com/T156979) (feedback tracker)
- [Late game gets a little slow](https://steamcommunity.com/workshop/filedetails/discussion/462357997/361798516954844892) (Warlords Workshop discussion)
- [LAMBS Danger.fsm changelog](https://steamcommunity.com/sharedfiles/filedetails/changelog/1858075458?p=3) and [dev changelog](https://steamcommunity.com/sharedfiles/filedetails/changelog/2434257231?p=3)
- [DCO Soldier FSM changelog](https://steamcommunity.com/sharedfiles/filedetails/changelog/2825929474?p=7)

Prior art worth reading before building: [HETMAN Artificial Leader](https://www.moddb.com/downloads/hetman-artificial-leader), a field-commander AI that issues orders rather than fighting, and [ALiVE](https://github.com/AusTac/ALiVE.OS), whose AI Commander takes control of a faction's forces and attacks objectives you sync it to.
