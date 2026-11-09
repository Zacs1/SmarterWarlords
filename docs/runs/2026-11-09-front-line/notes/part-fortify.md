# Item 3 as built: defenders fortify

Files: `commander/swlc/fortify.sqf` (new), scenario `tests/mission_overlay/swl/scenarios/fortify.sqf`, gate `tools/gates_fort.py`. Small edits in `init.sqf` (file list), `commander.sqf` (its own stage slice after the picket and defence slice), `settings.sqf` (one block after `commanderEnabled`), `upkeep.sqf` (two exemptions), `radio.sqf` (one line) and `tools/analyse_round.py` (gate list).

**Nothing here has run in Arma.** It passes HEMTT lint and the gate compiles. Every claim below about behaviour in the game is what the code is written to do.

## Spec as built

Runs once per commander tick (10 s), per side, under `fortifyEnabled` (default on, and not under the rules variant).

**Threat signal.** Only `_cmd getOrDefault ["alert", createHashMap]`. Empty means nothing happens beyond logging the catalog, so until the alert helper is merged this module buys nothing. There is no second threat signal.

**What it buys.** Warlords' Defences list (`adPurchasable` index 3), filtered to crewed static MG, GL and AT. `fortifyMix` is walked from the gun's slot, so a kind that isn't on offer, isn't allowed or can't be paid for gives way to the next. Capability rules go through `econAssetAllowed` and prices through `econPriceMult`, both on every purchase.

**How much.**

| Tunable | Attack | Hold | Rebuild |
|---|---|---|---|
| `fortifyStatics<Stance>`, guns per sector | 2 | 4 | 4 |
| `fortifyCpFraction<Stance>`, most a single gun may cost as a share of free CP | 0.25 | 0.6 | 0.6 |

`fortifyMaxPerSector` (4) is a hard cap over all of these, and `fortifyBuyPerTick` (1) limits the rate. An unknown stance reads as attack. Free CP is `SWLC_fnc_cpFree`, so the reserve always holds, and each purchase also writes a `C_BUY` line (`what=static`, `buyer=fortify`) for the analyser's reserve check.

**Remembered per sector.** `_cmd "fort"` maps sector name to a list of records (gun, class, kind, cost, position, facing, gunner). The cap counts live guns plus any destroyed within the last `fortifyReplaceSeconds` (240), so a second alert doesn't rebuy past the cap and a contested sector can't be used to drain CP.

**Placement.** Along the approach bearing at `fortifyEdgeFraction` (0.4) of the sector's width, trying ±20, ±40 and ±60 degrees and ±30 m. A spot must be inside the sector's square, at least `fortifyMinCentreDist` (40 m) from the centre, not restricted, not water, not on or within `fortifyRoadClear` (8 m) of a road, gradient below `fortifyMaxGradient`, an empty position for that class, at least `fortifySpacing` (30 m) from this sector's other guns, and clear of men. The first spot with open terrain along its line of fire (`fortifyCoverRange`, 200 m) wins; if none has that, the first valid one. Facing is at the approach point, or along the bearing if that point is on top of the gun or behind it. Creation is the economy's pattern (`CAN_COLLIDE`, then set on the ground). Weapon disassembly is off, as Warlords does for player defences.

**Crew.** From the record's `"groups"` only, each one passing `resMayTouch`, so never a player or AI a player owns. A man must be alive, not a player, on foot, not the leader, not an AT soldier, not on a kit errand or another fortify job, and able to move (`PATH` on). Nearest first, men with no launcher before men with one, within `fortifyCrewReach` (300 m), at most `fortifyMaxCrewPerGroup` (2) per group. The order is `assignAsGunner` and `orderGetIn`, with no `addVehicle`, and the man stays in his group, so `SWLC_order` and the waypoints are never touched. He gets `fortifyCrewWalkSeconds` (30) plus the distance at `fortifyCrewWalkSpeed` (2.5 m/s). If time runs out and he is within `fortifyCrewSeatDist` (12 m) he is seated directly (twice at most); otherwise he is released and another is picked.

Every tick: a dead gunner's body is taken out of the seat and the gun gets a new man from the same groups. Anyone alive in the seat, ours or not, counts as crewed. A man whose group has left the record or gone to a player is released and replaced.

**AT soldiers.** Up to `fortifyATMen` (2) non-leader AT soldiers from the record's groups, from groups with no LAMBS task and not fighting when picked. Each goes to a spot `fortifyATRoadOffset` (12 m) off a road point within `fortifyATReachFraction` (0.75) of the sector's width, off the tarmac, furthest forward first, opposite sides of the road in turn. On arrival: `doStop`, `doWatch` along the road towards the enemy, kneel. With no road points, the same on the line of the approach. Knocked further than `fortifyATDrift` (25 m) off the spot he is sent back up to `fortifyATDriftMax` (2) times and then released. If his group gets a LAMBS task the job ends at once with no commands from here, so a garrison or defend task is never disturbed.

**Alert end.** Guns stay, and so does the memory of them. Every gunner is unassigned, told to get out and sent back to his leader (`doFollow`, unless his group has a LAMBS task); AT men are released the same way, stance and watch reset. The men return to whatever their group is doing. The same applies if the alert moves to another sector or the sector is lost. A gun left unmanned can be used by anyone, including the enemy if the sector falls.

**Upkeep.** `upkeepOnJob` now treats `SWLC_fortGun` and `SWLC_fortAT` as on a job, and `upkeepLooseCrew` skips a man with `SWLC_fortGun`, so they aren't pulled away.

## Real Defences classes (Warlords config, `A3DefaultAll`, inherited by the test mission's `A3PacificAll` preset)

| Kind | WEST | EAST | Cost |
|---|---|---|---|
| MG | `B_HMG_01_F`, `B_HMG_01_high_F` | `O_HMG_01_F`, `O_HMG_01_high_F` | 250 |
| GL | `B_GMG_01_F`, `B_GMG_01_high_F` | `O_GMG_01_F`, `O_GMG_01_high_F` | 250 |
| AT | `B_static_AT_F` | `O_static_AT_F` | 500 |
| Not used: autonomous | `B_HMG_01_A_F`, `B_GMG_01_A_F` | `O_` equivalents | 500 |
| Not used: AA, SAM, radar | `B_static_AA_F` 500, `B_SAM_System_03_F` 27500, `B_Radar_System_01_F` 8500 | `O_static_AA_F`, `O_SAM_System_04_F`, `O_Radar_System_02_F` | |

**AT is on offer for both sides** in this preset. On a preset without it, the mix moves on to MG and GL, and `C_FORT event=catalog_summary` says so at the start of the round. These were read from the Warlords config, not from a running game.

## Decisions

| Decision | Why |
|---|---|
| Kind worked out from the class name (`_at_`, `gmg`, `mg`), then a `StaticWeapon` and not-`isUav` check | Warlords' list only says "Defences". A modded preset with unusual names logs `kind=none` for those classes and they're skipped. The catalog line shows it. |
| Prefer the `_high` tripods for MG and GL | Better chance of seeing over grass and low walls. An assumption, not tested. `fortifyPreferHigh=false` turns it off. |
| No buying with an enemy near the front of the sector (`adEnemyNear`, 200 m) | Warlords refuses a player placing a defence in that case. It uses real positions, as the Warlords rule and the fast travel check do; it isn't the commander's intel. `fortifyRespectEnemyNear=false` turns it off. An alert raised with attackers already inside 200 m buys nothing. |
| Destroyed guns count against the cap for 240 s | Stops the commander pouring CP into a gun line that keeps being shot up. |
| Don't buy if no man could crew it | An unmanned gun is a waste of CP and a gift to the enemy. |
| Men released at alert end rather than left on the guns | The brief wants men back on their group's normal orders. Guns stay for next time. |
| Seat directly only within 12 m, twice at most | AI boarding can fail on a static; moving a man who is already beside it isn't a visible teleport. A man who isn't there gets replaced instead. |
| Not garrisoned men (`PATH` off) | LAMBS has them in a position. Pulling them out would break the garrison the brief says not to break. |
| One gun bought per tick | Keeps the spend visible and the slice cheap; the whole cap is in within about 40 s. |
| Sector name is the record key | Hashmap keys can't be objects. Sector names are unique. |

## Radio and panel text

One new radio type `fortbuilt`, sent once per alert when the first gun goes in, via the HQ voice with the default cooldown:

- "Guns going in at %1, facing their approach."
- "Setting up static weapons at %1."
- "Digging guns in at %1, they're coming that way."
- "%1 is getting guns on the approach."

No panel text.

## Log

`C_FORT` with `side` and `event`: `catalog`, `catalog_summary`, `alert_seen`, `buy`, `placed`, `crew_assign`, `crew_in`, `crew_lost`, `crew_timeout`, `crew_release` (`why`), `gun_lost`, `at_assign`, `at_hold`, `at_drift`, `at_release` (`why`), `standdown` (`why`), and `refuse` (`reason`: `not_owned`, `no_approach`, `cap`, `no_men`, `enemy_near`, `catalog_empty`, `not_allowed`, `funds`, `no_spot`, `create_failed`, `at_no_spot`). Refusals are limited to one line per sector and reason per `fortifyRefuseLogSeconds` (60).

## Scenario and its limits

```
powershell -ExecutionPolicy Bypass -File tools\run-round.ps1 -DurationMinutes 12 -Name fortify -Scenario fortify -Overrides "goMinGroups=99;rallyLoneWait=99999;scanBuying=false;ruleCommitTimer=false;ftChargeCost=false"
python tools/analyse_round.py <rpt> --gate fortify
```

About 9 minutes of game time. It has not been run. Stages: no alert, attack stance (cap 2), hold stance (cap 4 and crews), a gunner killed and replaced, alert ended, and a second alert at the same sector.

Limits:

- **Test hook.** The scenario writes the alert record straight onto the WEST commander, along with the stance (every second, so a merged stance module can't overwrite it). It tests fortify, not how the alert is raised or whether the record's `"groups"` are sensible. A real round's `C_ALERT` and `C_FORT` lines are needed for that.
- It doesn't test what happens with no enemy-free ground, with an enemy near (`enemy_near`), with a human player's group listed in the record, with a group under LAMBS, or with the sector lost during an alert.
- WEST only, and no enemy fires on the guns, so `gun_lost` and the cap on destroyed guns aren't exercised. The defenders can't be killed except for the one man shot on purpose.
- Terrain is whichever sector the setup picks. The gate accepts 3 guns of 4 if it logged a `no_spot` refusal.
- The AT road check is skipped for distance if the sector has no road on that side, though the man still gets his fallback spot.

## Risks

- AI boarding a static on order, and staying there, is the part most likely to misbehave. It's what the gate's `crewed` check is for.
- A group with a man seated on a gun can't fast travel: `adFastTravel` refuses while any member is in a vehicle. A defending group that is told to hop elsewhere during an alert won't go until it is released.
- Nothing stops other commander code pulling a man off a gun or the road: LAMBS' release moves men out of statics, and several squad and resilience paths call `doFollow` on the whole group. Upkeep is the only one exempted. The AT drift logic covers part of this; crew would be re-picked after a timeout.
- A LAMBS garrison freezes men, so if every man in the groups is garrisoned the guns get no crew (`no_men`) and, for a gun not yet bought, no purchase.
- If the alert helper rebuilds `"groups"` with different groups from tick to tick, men will be released and re-picked. The merge should keep that list stable through an alert.
- A sector that falls leaves its guns standing for the enemy to use, and they stay counted if the sector is retaken.
- Guns aren't registered with Warlords' per-player asset tracking, so they aren't cleaned up or counted by any Warlords limit.
