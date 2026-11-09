# Per-side stance (attack, hold, rebuild)

Item 1 of the defence addition. Code is in `commander/swlc/stance.sqf`, with small hooks elsewhere. **Nothing here has run in Arma.** The SQF linted with no errors, and the gate was exercised only against hand-written logs.

## How the stance is worked out

Every `stanceTickSeconds` (20 s), for each side:

- **Own strength** = men alive + CP as men (`CP / stanceCPPerMan`, at most `stanceCPMaxMen`) + `stanceArmourWeight` x own combat vehicles, less those the known enemy AT cancels (`planAtPerArmour` launchers each). Enemy CP can't be known, so it's own only.
- **Known enemy** = from the intel board only, same filter as the threat summary (`intelThreatMinConf`, `reactionDelay`): infantry + `stanceLightWeight` x light vehicles and aircraft + `stanceArmourWeight` x armour, less what own AT cancels. Statics are left out, because they don't come for you.
- **Memory**: the known figure is a peak that halves every `stanceMemoryHalfLife` (240 s), so a side sitting at home doesn't "recover" just because its board went stale.
- **Ratio** = own / (known peak x `stanceIntelFactor`) x outcome factor. The outcome factor is 1 plus `stanceOutcomeStep` per capture, minus the same per failed push, within `stanceOutcomeWindow`, clamped to 0.7 to 1.2. Results come in from `pushOver` and `waveResolve`, including every failure that counts towards `pushFails`. I didn't use `kills`/`losses` in `rules.sqf`, as those only exist under the rules variant.
- **Little intel**: known peak under `stanceMinKnown` (12) means attack, whatever the ratio.

| From | To | When |
|---|---|---|
| attack | hold | ratio < 0.9 |
| hold | rebuild | ratio < 0.55 |
| rebuild | hold | ratio >= 0.8 |
| hold or rebuild | attack | ratio >= 1.25, or known too little to judge |

A side can't go from attack straight to rebuild on the balance; it passes through hold. `stanceMinSeconds` (180) must pass between switches. All thresholds are in one settings block after `commanderEnabled`. `stanceEnabled=false` restores today's behaviour.

## What each stance does

**Attack**: today's game. No code path changes.

**Hold**
- `SWLC_fnc_stanceNoWave` is now the gate on both `cmdNewPlan` calls in `cmdTarget` and on the idle-cap replan.
- A wave out when the stance changes: nothing new goes in (`holdGo`), every group not in a fight goes back (`stanceStandDown`), and the op ends once nobody is in contact. Contact means an assaulting group that is fighting or at the objective, or any group fighting on the way. A group in a fight is never touched.
- The whole side stands in the reserve (`stanceHoldReserveFraction` = 1). Those groups are what pickets, defence responses, raids and probes draw on.
- Pickets are not released to "go back to the attack" and may come from the reserve.
- Raids and probes (rules variant only) draw on the reserve, keep `stanceHoldRaidKeep` (3) groups back, send one group, and only at targets with at most `stanceHoldRaidMaxDefenders` (3) known defenders.
- Buying: `rebuildTick` also runs in hold, topping up infantry at the central sector. Those groups draw AT launchers through the normal kit code: one per group, plus `planAtPerArmour` per known armour. No muster shop runs without a wave, so no vehicles are bought. Statics are another helper's code and untouched.

**Rebuild**: `SWLC_fnc_rebuilding` is now true in the rebuild stance too, so the existing rebuild applies unchanged: reserve size 1000 at `defCentralSector`, infantry shop at that post, no raids or probes. Pickets are released. When the balance recovers the side goes to hold or attack; going back to attack is the counterattack.

**Commit timer**: `rebuildUntil` running puts the side in the rebuild stance at once (`reason=commit`, ignores the minimum time) and it can't leave until the timer ends. After that the balance decides, so if the side is still weak it stays in rebuild past the old 240 s. The commitment rule's "nobody votes while rebuilding" still applies during those 240 s only (`SWLC_fnc_commitRebuilding`). While a side isn't going for its target, the commitment timer and the deadlock revote are reset each tick, so neither can fire on a target it's deliberately not attacking. Coming back to attack starts a full commitment timer.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Voting in hold or rebuild | Votes normally, through `voteChoose`, which already marks down known defenders. The target is nominal until the side is back in attack, when a plan starts from it. | Warlords needs a target, and this needed no new vote logic. |
| Holdout goal "hold" in any stance | Reinforcement keeps going. With X as the target, a wave to X is allowed (`stanceHoldoutJob`), the reserve empties to feed it as today, and the rebuild stance doesn't count as rebuilding while the goal is "hold". | The brief calls this a defensive job that continues in any stance. |
| Holdout goal "counter" (holdouts dead) in hold or rebuild | No new wave. The reserve is not emptied for it. | A counterattack is an attack, which is what the stance has just ruled out. It comes when the stance returns to attack. |
| Goal "hold" but target not yet X | No wave until the vote lands on X. | Same as the commit rebuild's behaviour; holdout voting already pushes for X. |
| Commit-timer vote pause | Kept as it was, for `rebuildUntil` only. | Avoids changing the commitment rule's tested behaviour (`partb` gate). |
| Reserve in hold | Everyone, not a fraction. | Anyone left Unassigned with no op would show as idle and fail the activity checks on soaks. |
| Idle-cap and other resilience rebuild guards | Use `stanceNoWave` in place of `rebuilding`. | They replan or reassign into an op, which must not happen in hold. |
| `lastResult` | New value `stance_hold` for an op ended by the stance. Not counted as a failure. | Nothing else reads `lastResult`. |

## New text

Radio (`commander/swlc/stance.sqf`), three variants each:

- `stance_attack`: "Balance has swung back our way. We're going on the attack." / "We've got the strength now. Back on the offensive." / "All units, we're attacking again."
- `stance_hold`: "They're stronger than we thought. Hold what we have, no big attacks." / "We're going on the defensive. Hold the line." / "Enemy has the edge for now. Dig in and hold."
- `stance_rebuild`: "We're too weak to stay out there. Pull back and rebuild." / "Falling back to rebuild. Everyone to the central sector." / "We need men before we can fight. Pull back, we're rebuilding."

Panel: "Stance: ATTACK", "Stance: HOLD" or "Stance: REBUILD" on the header line, in front of the holdout goal text. Made in `status.sqf`; `client.sqf` is unchanged.

Log: `C_STANCE` with `event=switch` (`from`, `to`, `reason`, and the numbers), `event=held` (the minimum time stopped a change it wanted, once per stretch) and `event=state` (every `stanceLogSeconds`).

## Scenario and gate

```
tools/run-round.ps1 -DurationMinutes 12 -Scenario stance -Overrides "stanceMinSeconds=90;stanceTickSeconds=10;stanceMemoryHalfLife=30;stanceOutcomeStep=0;ruleCommitTimer=false"
python tools/analyse_round.py <rpt> --gate stance
```

**Test hooks**: `SWLC_fnc_stanceKnown` is replaced by the scenario, so the enemy numbers come from the script, not from sightings. WEST is told about 600 enemy infantry and then none; EAST is always told none. Own numbers are real. The commit-timer rebuild is simulated by setting `rebuildUntil`, which is all the rule does to start one. The commitment rule itself is off for this round.

Checks: goes defensive when weak; reaches rebuild; recovers to attack; no flip inside the minimum time, for either side; the minimum time really did hold back a change; per side, EAST ran the stance and stayed in attack; no new wave or assault out of attack; a commit rebuild sets the stance and runs its length; finished; no script errors.

The gate does not test: the intel-board reading (hooked out), real intel driving a switch, the numbers being sensible, a wave in contact finishing, raids and pickets in hold, AT kit, holdouts in hold or rebuild, or the panel and radio appearing.

## Left out

- Vehicle buying isn't re-weighted in hold; without a wave none is bought.
- Picking defensible sectors beyond the existing `defCentralSector`.
- Enemy statics in the strength sum.

## Risks

- Thresholds and weights are starting guesses. The real ratio on a Tanoa round hasn't been measured.
- Partial intel understates the enemy, so a side may stay in attack too long. A big enemy sighting early could also push a side into hold it doesn't need, and the 240 s memory keeps it there.
- A side with players in hold or rebuild: the AI stops following the voted target, so human players pushing a sector get no AI waves, and only the panel and radio say why.
- With the whole side in the reserve at one sector, the other owned sectors depend on pickets and `defRespond`, and one crowded post is a target for artillery.
- A side stuck in hold doesn't capture, so with both sides in hold the round could stall. The commit and deadlock timers are held off during hold, so nothing else breaks that.
