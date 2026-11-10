# Progress: tempo run, 2026-11-09

## What the played round showed (`played-round.rpt`, 30 minutes, commit `665d096`)

- Vehicles stopped 500 to 800 m from the sector centre, which is further out than the rally point (sector half-width + 200 m). Alpha 1-3 drove for 40 s, then walked 90 s from the truck to the rally.
- 16 of 28 departures were on foot. Every hop the old rule called too short (`worth_driving=false`) was walked, including Leqa to Balavu.
- After a capture every squad dropped its vehicle. The next muster only reused vehicles within 500 m of the sector centre, so WEST bought 4 new trucks for wave 2 while 4 sat at the old dismount point.
- Boarding hit the 60 s cap in most departures (`late=1`).
- WEST wave 2: target picked at t=361, first assault at t=802. Wave 3: target at t=1062, assault at t=1562, after 260 s at the rally with 42% of the wave, and only because it was forced.
- EAST lost 2 trucks on delivery at its base and had 2 more stuck there.

## Changes (one pass, as asked)

1. Dismount point 80 to 220 m outside the sector edge (was 500 to 800 m from the centre). Drive legs at full speed. A drive is worth it from 250 m beyond that.
2. A squad keeps the vehicle it dismounted from (`owner` on the vehicle record, `SWLC_ride` on the group). When the sector falls, every squad but the cleanup squads is ordered back to its vehicle at once. When the next target is picked, a squad with its vehicle within 700 m and at least half strength skips the muster, boards and drives (`vehExpress`, log event `express`). Weaker squads muster at a sector and rebuild as before.
3. Men standing within 60 m of their vehicle 25 s after the order are seated, if no player is within 150 m.
4. Rally: two squads go after 30 s; 60% of the wave goes at once; a lone squad goes after 100 s (was 270 s). Later arrivals still go straight in.
5. Cleanup squads: the 2 weakest squads near the captured sector (never more than half of them) sweep it and dig in for 90 s, then follow.
6. Armed carriers: with 4,000 CP spare, up to 3 squads a side ride the cheapest armed vehicle that seats them (APC for a full squad, armed MRAP for 4 or fewer). The squad gets out at the dismount point; driver, gunner and commander stay in, hold there, and move to 40 m outside the sector edge once their infantry are past it.
7. Parked vehicles are removed when no player is within 250 m: after 45 s if they cannot drive, 120 s with no squad, 600 s with one. Wrecks after 180 s.

Every rule has its own switch in `settings.sqf`.

## Test rounds

All rounds: dedicated server, AI only, CBA + LAMBS stable, `BIS_WLStartCP=20000` from `tempo2` on (about 150,000 CP a side, to exercise the buying). Run folders are under `tests/server/runs/`.

| Round | Length | Script errors | What it showed | What changed after it |
|---|---|---|---|---|
| `tempo1` | 7 min, stopped | 0 | Dismount about 150 m from the rally. Parked vehicles despawned. WEST attacked with two one-man squads. No carriers, CP too low. | `goPairMinMen` 8 |
| `tempo2` | 10 min, stopped | 0 | First captures. Squads sent back to their vehicles (`to_ride`) and skipped the muster (`express`). One squad was reset every 30 s while boarding (`sweep_bad_goal`): the stuck-squad sweep looked for a muster sector it did not have. Squads left the muster with 1 to 3 men. MRAP carriers bought for one-man squads. | Sweep exempts express squads. `musterFillFraction` 0.5, 12 men bought per tick. |
| `tempo3` | 5 min, stopped | 0 | No resets. EAST still attacked with 4 men in 4 squads: squads that start near the rally went straight to it without visiting a shop. No APC bought, because the rule asked for 10 seats and APCs have 8. | Thin squads muster first even next to the rally. Carriers need 8 seats. |
| `tempo4` | 12 min, full | 0 | First assaults: WEST 14 men after 30 s at the rally, EAST 29 men after 40 s. Both captured. WEST: capture t=491, next target t=506, 5 of 8 squads boarding their own vehicles at t=507, driving at t=537 to 547. EAST the same within 22 s of its capture. No resets. Activity gate: 16 of 16 commanders PASS. No carriers, because squads were 10 men and APCs seat 8. | The user asked for squads of 8 so a full squad fits an APC: `shopGroupSize` 8, `shopGroupMax` 8 (the town bonus no longer takes AI squads past 8). |
