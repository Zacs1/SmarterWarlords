# Part A as built: hold X, reinforce the holdouts

Status: lint clean, gate checked against a hand-written log only. Nothing has run in Arma yet.

Code: `commander/swlc/holdouts.sqf`. Hooks: `settings.sqf` (one block after `ruleCommitTimer`), `init.sqf` (load order), `commander.sqf` (`holdoutTick` in the tick list), `status.sqf` (group reason, panel text), `adapter.sqf` (`adProtectSector`, `adUnprotectSector`).

Switch: `ruleHoldouts`, under `rulesVariant`. Default on.

## Spec as built

1. **Forming.** When a sector the side owned, or its current target, turns enemy with its groups inside (X's square plus `holdoutMargin`), those groups become holdouts: `SWLC_holdout` true, state "Defending". Part D's "Engaged" is accepted as well. Bases never become X. Raiding, Probing, Borrowed, Pickup and Hunting groups are left alone. One X at a time per side: a second loss during a hold doesn't start a new one.
2. **Staying alive.** Warlords kills AI in a sector that is neither on `BIS_WL_conqueredSectors_<side>` nor `BIS_WL_currentSector_<side>`. The conquered list is only ever added to, so a sector the side once captured is already safe. If X isn't on it, `adProtectSector` adds it, and it's taken off again `holdoutUnprotectGrace` seconds after the hold ends. A protected X doesn't depend on the vote going through.
3. **Target stays X.** Set by `preferredTarget` and a forced revote (`adForceRevote`), not by writing the target variable, which would leave Warlords' vote loop holding a stale sector. If the side's target isn't X for `holdoutVoteGrace` seconds in a row, the hold ends with reason `target_moved`. The revote happens once, when the hold forms, so players voting elsewhere can end a hold this way.
4. **Reinforcing.** While the goal is X, `forceGo` is set on the operation every tick. That opens the existing muster and rally, so free groups go without forming a wave. Once the first group is in, the wave's existing reinforce mode sends the rest. The muster sector is the existing staging choice (nearest owned sector). Part C's defence of Y is the only job ahead of this.
5. **Digging in.** Each holdout gets a spot within `holdoutCoverRadius` of X: buildings with room inside first, then the terrain's best spots from the staging search. After `holdoutSettleSeconds` at the spot it uses LAMBS garrison if LAMBS is loaded (`holdoutGarrison`). Without LAMBS it holds the spot under a HOLD waypoint.
6. **Breaking.** A group at or under `holdoutBreakFraction` of the strength it had when the hold formed (its own threshold, separate from the existing break-and-consolidate rule) moves to the nearest cover on the X side of the way to the nearest owned sector, `holdoutFallbackBeyond` past X's edge, never beyond `holdoutFallbackMax` from X. It stays a holdout and waits there.
7. **Resupply.** When any holdout group is short of ammunition or launchers, and `cpFree` covers `holdoutResupplyCost` (so the reserve is respected), the side pays and a crate appears beside that group after `holdoutResupplyDelay`. `holdoutResupplyCooldown` limits the rate, `holdoutResupplyFirstDelay` holds off the first one. The usual rearm is blocked by combat and LAMBS, so `holdRestock` takes from the crate where the soldier stands, using the squad rearm helpers (`holdoutRestock`, `holdoutRestockSeconds`).
8. **Wiped.** With no holdouts left, the goal becomes "counter" and X remains the target, so arriving groups attack it. The commitment timer still applies: when it moves the side on, the hold ends with reason `commit`.
9. **End reasons.** `recaptured`, `commit`, `target_moved`.

## Tunables (all in `settings.sqf`)

`holdoutCheckSeconds` 3, `holdoutMargin` 60, `holdoutVoteGrace` 150, `holdoutUnprotectGrace` 60, `holdoutCoverRadius` 120, `holdoutGarrison` true, `holdoutSettleSeconds` 20, `holdoutBreakFraction` 0.34, `holdoutFallbackBeyond` 40, `holdoutFallbackMax` 300, `holdoutCoverSearch` 60, `holdoutArriveMargin` 30, `holdoutResupply` true, `holdoutResupplyCost` 200, `holdoutResupplyCooldown` 240, `holdoutResupplyFirstDelay` 30, `holdoutResupplyDelay` 30, `holdoutRestock` true, `holdoutRestockSeconds` 15.

## Decision rows

| Decision | Why | Alternative rejected |
|---|---|---|
| Keep X as target by vote plus preferred target, and protect X separately if needed | Writing the target directly leaves Warlords' vote loop out of step | Direct write to `BIS_WL_currentSector` |
| Open reinforcement with `forceGo`, not `pushStart` | An ASSAULT phase with no attackers returns "wiped" and repeats the push-over | `pushStart` |
| Crate is a CP debit plus a direct spawn after 30 s | Warlords' airdrop lands 50 to 150 m away, beyond rearm reach of men in cover | Warlords' airdrop |
| Reinforcements carrying extra ammunition: **not built** | Optional in the brief, and the crate covers the need | |
| One X at a time per side | Keeps the goal and the panel unambiguous | A list of holds |
| If Y falls during a hold, Y gets the same protection on the way out and its groups head for X | The men inside would otherwise die to Warlords' kill rule | |

## Player-visible text

Radio (`%1` is the sector name), cooldown in seconds:

- `holdformed` (20): "We've lost %1 but we're still in there. Holding on." / "%1 has fallen with our people inside. They're staying." / "Enemy has %1. Our groups inside are holding."
- `holdsupply` (30): "Resupply on the way to %1." / "Ammo drop coming in at %1." / "Crate inbound for the holdouts at %1."

Group reason on the panel: "holding out, waiting for reinforcements". Goal text is in `part-c.md`.

## Item 8: ground between rally points, per Tanoa link

From `MP_Warlords_03.Tanoa` `mission.sqm`. Rally gap = centre distance minus both half sizes minus 2 x `rallyOutside` (200 m), straight line. This is an estimate: the real rally point is on the route, and square sectors are measured along the line.

| Link | Centre distance (m) | Rally gap (m) | Result |
|---|---|---|---|
| Base (2787,5711) to Industrial (1715,6128) | 1149 | 549 | Fine |
| Base (2787,5711) to Town (3411,6704) | 1173 | 573 | Fine |
| Base (1602,8489) to Town (983,7656) | 1038 | 388 | Fine |
| Base (1602,8489) to Radio (2341,8183) | 801 | 201 | Tightest, still open ground |
| Industrial to Town (3411,6704) | 1791 | 1191 | Fine |
| Town (3411,6704) to Military (2665,7345) | 984 | 334 | Fine |
| Town (983,7656) to Radio | 1457 | 807 | Fine |
| Military to Radio | 897 | 247 | Second tightest, still open ground |

All are positive, so no per-map change was made. The two tight links are the ones to watch in a round.

## Scenario and gate

Scenario `tests/mission_overlay/swl/scenarios/fronta.sqf`, gate `tools/gates_fa.py` (`--gate fronta`, in `analyse_round.py`).

Round command: `-DurationMinutes 18 -Scenario fronta -Overrides "ruleCommitTimer=false;scanBuying=false;holdClearSeconds=60"`, then `python tools/analyse_round.py <rpt> --gate fronta`.

Gate limits, constants at the top of `gates_fa.py`: reinforcements leave within 180 s (the tunable the brief asked to have reported), vote allowed 90 s, target share 0.9, stay within 350 m, fallback slack 60 m, delivered within 40 m.

The scenario makes WEST lose a sector on a real route: three groups are teleported in, 12 invulnerable EAST men garrison it, X is flipped to EAST. It then makes ammunition low (t0+150), breaks a group (t0+300) and wipes the holdouts (t0+620). `SWLC_capMult_WEST` is 100 on X so a capture can't undo it.

## Scenario limits

- WEST only. The code is side-neutral but EAST isn't exercised.
- `SWLC_fnc_frontFighting` is replaced by a stub, so Part B's detection isn't tested here.
- The scenario can run about 17 of the 18 minutes, so a late start may cut the end.
- "Arrive while holdouts live in a reasonable share of runs" needs several runs; one round gives one sample.
- The winner mustering at X (item 7) is existing behaviour and unchanged. The scenario's EAST is invulnerable and static, so it doesn't test that push.
