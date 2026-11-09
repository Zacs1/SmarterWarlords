# Alert on enemy targeting and defence in depth (items 2 and 4)

Code: `commander/swlc/alert.sqf`, small hooks elsewhere. Switches: `alertEnabled`, `alertScreen`, `alertCounter`, default on, not under the rules variant. All tunables are in one block in `settings.sqf`, straight after `commanderEnabled`. Nothing here has run in Arma: lint reports no errors on the commander and the scenario, and the gate was only run against a small made-up log.

## As built

**Trigger.** `alertTick` runs just before `defenceTick`. An alert starts when `[_enemySide] call SWLC_fnc_adTarget` is one of the side's sectors. It clears when the enemy's target changes (`target_changed`) or the sector changes owner (`owner_changed`). This warning is the only use of enemy knowledge beyond the intel board.

**Record.** `_cmd getOrDefault ["alert", createHashMap]`, empty when none. Keys for others to read: `sector`, `since`, `approach` as `[bearing, pointOnApproach, roadPoints]`, `groups` (the threat record's own list, so fortify crews stay current), `screen`, `counter`. Internal keys: `counts`, `hit`, `seen`, `screenSent`, `screenSpot`, `counterPost`. Logged as `C_ALERT` with event `start`, `main`, `screen`, `counter`, `counter_hit`, `clear`.

**Approach.** `[_cmd, _sector] call SWLC_fnc_alertApproach` returns the same triple. It compares the `alertApproachCandidates` nearest enemy sectors by road length and walks the shortest route out from the sector. The bearing and point are read where the route is `alertApproachSample` (500 m) out. Road points are route nodes within `alertRoadRange`, thinned by `alertRoadSpacing`, at most `alertRoadMax`. With no route it uses the straight line to the nearest enemy sector and samples `nearRoads` along it.

**Numbers.** `alertLayers` maps stance to `[main, screen, counter, share of the side's groups]`: attack `[1, 1, 0, 0.34]`, hold `[2, 1, 1, 0.6]`, rebuild `[3, 1, 2, 0.8]`. A sector worth at least `alertValueHigh` (60) gets one more main group. The share caps the total: main first, then screen, then counter. Stance comes from `SWLC_fnc_stanceOf` when it exists, otherwise `_cmd getOrDefault ["stance", "attack"]`.

**Main position.** No second mover. The alert writes or refreshes a threat record, marked `alertOnly` if it created it, with `alertNeed` as a floor on `defRespond`'s need and `spots` from `SWLC_fnc_alertSpots`: `holdCover` around a point on the approach side, kept within `alertCoverArc` of the bearing, at least `alertCoverMinFraction` of the half-width out from the centre, within `alertCoverOutside` of the square. Falls back to `defSpots`. `defRespond` then sends groups in its usual order. A real sighting, an engaged fallback or a counter hit clears `alertOnly`. With LAMBS, `lambsHold` centres its garrison on the group's spot through `SWLC_alertCover`. Groups at their spots turn to face the approach (`setFormDir`, `doWatch`) every `alertFaceSeconds`; `doWatch` is cancelled when the alert ends.

**Screen.** One small group on foot, `alertScreenBeyond` (250 m) beyond the sector edge on the approach, at cover within `alertScreenCover` if there is any. State Defending, not on the threat record, so it isn't counted against the main position. Once lost it isn't replaced in that alert.

**Counterattack reserve.** State Reserve, `SWLC_counterFor` set to the sector, waiting `alertCounterBack` (150 m) behind the sector edge. On a break-in, each goes at once to Defending with a search-and-destroy on the sector centre, `C_ALERT event=counter_hit`, and joins the threat record. A break-in is `SWLC_fnc_capBeingSeized`, or at least `alertBreakInMen` (2) enemy known inside the square from the board.

**Who may be taken.** `SWLC_fnc_alertPool`: a picket on this sector, the reserve, then Unassigned and a muster at this sector, then the attack only when the stance isn't attack. Never a group in a fight (`SWLC_fnc_groupFighting`), one under a LAMBS task or one a commander may not touch. While `SWLC_fnc_holdPriority` is true and this sector isn't fighting, only the picket and reserve steps apply, matching `defRespond`.

**Edits outside `alert.sqf`.** `defRespond`: need floor, alert-only records stop at the peel step and never pull attackers (step 4), the muster keeps running, fighting groups are skipped, Reserve excludes counter groups. `defReserveTick`: counter groups aren't rotated, shrunk or moved, but count towards the reserve size. `defenceTick` and `engagedFallback`: a real contact clears `alertOnly`. `frontHot`: an alert-only record isn't hot, otherwise fast travel would go next door to a sector nobody has attacked yet. `smart.sqf` hunt pool and `engaged.sqf` join pool skip counter groups. `lambsHold`: centre.

## Decisions

| Decision | Why |
|---|---|
| The main position goes through a threat record, not a separate list | One mover, one set of rules for who is taken, fast travel and stand-down |
| A real threat on the sector keeps its groups and takes the approach spots for groups still to come | A real sighting's bearing beats a prediction for groups already there |
| An alert-only threat clears as soon as the alert does; a real one runs its own timer | Nothing was seen, so there's nothing to wait out |
| Alert-only never reaches step 4 of `defRespond` | The warning can't justify pulling attackers in contact or on their way in; the peel step still takes up to the cap |
| An alert-only record isn't hot in `frontHot` | Defenders should land in the sector, and it's quiet until someone arrives |
| Counter groups stay in state Reserve | Everything that reads the reserve still sees them; a flag keeps rotation and other jobs off them |
| Screen isn't on the threat record | It's a separate layer and shouldn't fill `alertNeed` |
| A lost screen isn't refilled | Feeding groups one at a time into the attackers is worse than the warning it gives |
| Screen and counter are released at clear only if still in their state | A group already fighting or sent in stays on its current job |

## Player-visible text

Radio, in `alert.sqf`: `alert` (the sector and the compass direction of the approach, three variants), `alertcounter` (three variants). 30 s cooldowns. Status panel shows the screen and main groups as Defending, the counter as Reserve, through the existing text.

## Left out

- The screen doesn't fall back when overrun. It fights where it stands and isn't replaced.
- The approach is one prediction per alert. It isn't updated when the enemy shows up from elsewhere; the threat record's `bearing` is, but cover spots for groups already sent aren't.
- A picket taken for the screen becomes Defending, leaving the picket slot to be refilled by `picketTick`.
- `alertSpots` picks by buildings near the approach side. It doesn't score walls or treelines beyond what `holdCover`'s `stagingPlaces` fallback gives.

## Scenario limits (`alert.sqf`, gate `alert`)

- All stance rows are forced to `[2, 1, 1]` so one run covers every layer, and the stance is held at "hold". The stance numbers themselves aren't tested.
- The attackers start on the predicted approach, so the run checks the defence against the prediction, not the prediction against a real attacker.
- The break-in is a faked seize countdown. The "enemy known inside the square" path isn't exercised.
- Attackers that can't be hurt and groups under test that can't be hurt: the gates are about where groups go, not fights.
- Run: `powershell -ExecutionPolicy Bypass -File tools\run-round.ps1 -DurationMinutes 12 -Name alert -Scenario alert -Overrides "goMinGroups=99;rallyLoneWait=99999;scanBuying=false;ruleCommitTimer=false"`, then `python tools/analyse_round.py <rpt> --gate alert`.
