# Part D: fights on the way are real fights

Code: `commander/swlc/engaged.sqf`, small hooks elsewhere. Switch: `behEngaged`, default on, independent of the rules variant. Nothing here has run in Arma yet: lint and the gate tool against a made-up log are the only checks so far.

## As built

**Fire tracking.** Every unit on the server gets `FiredMan`, `Suppressed` and `Hit` handlers once (`SWLC_fnc_contactAttachAll`, at most every 5 s). They write `SWLC_firedAt` and `SWLC_underFireAt`. `SWLC_fnc_groupFighting` is true if a living man fired or was fired on within `fightingWindow` (90 s). Smoke doesn't count, and neither does fire from a friendly side.

**Entering Engaged.** Each tick, a group in `engagedStates` (Travelling, Advancing) stops if it is fighting and knows of enemy within `engagedRange` (300 m), or knows of enemy within `engagedCloseRange` (120 m) whether fighting or not. Not inside the attack's target square, not a group under a LAMBS task, not a group `SWLC_fnc_resMayTouch` refuses. It saves its job, goal, order, leg and wave, then gets a search-and-destroy order at the contact, or holds where it is if the contact is on water or in a sector it may not enter.

**One fight.** Contacts within `engagedMergeMetres` (250 m) share a record, which holds position, strength (infantry + 3 x light + 6 x armour, as in defence) and members. The first contact gives one radio report.

**Joining.** Need is the defence formula: `ceil(strength x responseMargin / defenceMenPerGroup)`, at least 1, at most `defenceMaxGroups`. `responseMargin` is read directly so it applies with the rules variant off. Candidates are in `engagedJoinStates`, within `engagedJoinRadius` (600 m), on foot, not in combat, not fighting. Groups from the current wave are capped at `floor(wave groups x responseCapFraction)`.

**Ending.** The fight ends when no enemy is known near and nobody has fired for `engagedClearSeconds` (40 s), or when nobody has fired for `fightingWindow` even with a sighting still listed. Each group goes back to its saved job, goal, order and leg if its wave or muster still exists, otherwise to Unassigned. A group whose transport has gone continues on foot.

**Bigger enemy.** If strength is at least `engagedFallbackMinMen` (10) and at least `engagedFallbackRatio` (2.5) times the men on hand (a combat vehicle adds 5), the groups go to the nearest owned sector through `defSend`. That sector gets a threat record with the force's strength and is held open `engagedFallbackHoldSeconds` (150 s), and `defRespond` runs at once.

**Vehicles.** A combat vehicle stays crewed and fights under the group's order, then resumes. A transport on its DRIVE leg drops its passengers where it stands, the driver drives `engagedTransportBack` (200 m) away from the contact, then gets out and walks back to the group.

**Resilience.** `groupFighting` is the only test, in each of: watchdog (post-contact reset and progress), ladder (`ladderStep`), sweep (`resFaultOf`, `resIsIdle`), waypoint guard, vehicle stuck check. `waveVehicleLegs` skips Engaged groups. The observer logs `fighting=` on every GRP line. `gates_activity.py` and `gates_r.py` use it and list Engaged as a working job.

## Decisions

| Decision | Why |
|---|---|
| In transit means Travelling and Advancing only | Mustering and Waiting are already standing at a sector or the rally and fight there. Regrouping and Assaulting have their own rules. `engagedStates` can widen it |
| `FiredMan`, not `Fired` as the brief listed | `Fired` on a man misses shots from a vehicle turret |
| A holdout has no separate test | The 90 s cap makes "holdout in contact" the same as `groupFighting`, so holdouts are covered without Part A code |
| Script errors still climb the ladder for a fighting group | An error says nothing about the fight |
| Waypoint guard leaves a fighting group's waypoints alone unless it is Engaged | Restoring can re-plan a route or fast travel. Warlords' waypoints can stand for up to 90 s after the last shot |
| Mustering groups can't join | Pulling one out would break its muster. Defence still takes them when their own sector is hit |
| Vehicle-borne groups can't join | A transport joining from far away would dismount far from the fight |
| Aircraft don't count as contact | A passing helicopter shouldn't stop a march |
| Contacts need `intelMinKnows` | Same bar as a sighting on the board, so a group only reacts to what its men have seen |

## Player-visible text

Radio, in `radio.sqf`: `engaged` (where and how strong), `engagedjoin`, `engagedclear`, `engagedfall`. Status panel: job "Fighting", place "on the way", reason "in contact" or "moving to help".

## Scenario limits (`frontd.sqf`)

- Needs both sides to have an attack running within 300 s, otherwise it logs `no_op` and the gate fails.
- The groups are real commander groups moved into position, so the march isn't a natural meeting of two waves. If a wave resolves during the test, its groups go to Unassigned, not back on route.
- The join gate needs the leaders to see about 9 of the 12 enemy men, or the need stays at 2 and nobody is called.
- The helper group is held in place with `SWLC_patrolAt` and `SWLC_noAssignUntil`, but the reserve can still shrink and release it.
- The waves are on foot, so the transport gate only judges a transport if one meets the enemy by chance. It passes otherwise, and says so.
- The bigger enemy is 16 Syndikat men, on the assumption that independents are hostile to both sides on this mission.

## Known limits

- `Hit` and `Suppressed` fire only where the unit is local, so player-local units may under-report being fired on. Commander AI is server-local.
- On falling back, `defSend` releases the group's vehicle, so a combat vehicle is left parked. Same as any defence pull today.
- Tick cost is estimated, not measured. Run with `profileStages=true`, and the gate prints `engagedTick` and `contactAttachAll`.
