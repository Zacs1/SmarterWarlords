# Part C as built: switching between holding X and defending Y

Status: lint clean, gate checked against a hand-written log only. Nothing has run in Arma yet.

Code: `commander/swlc/holdouts.sqf` (`holdGoalTick`, `holdDefendTick`, `holdDefendGroup`, `holdDefendRelease`, `holdSetGoal`, `holdStatusText`). Part B's `SWLC_fnc_frontFighting` is the only source of "active fighting at Y", called through a nil guard, so the fast travel rule and the AI share one signal.

Switch: `holdoutSwitching`, under `ruleHoldouts`. Default on.

## Spec as built

`_cmd get "frontGoal"` is `[]`, `["hold", X]`, `["counter", X]` or `["defend", Y]`.

1. **Switch to Y.** While a hold is on, if any owned sector has active fighting, the nearest to X becomes Y and the goal is `defend`.
2. **Groups at or near X.** A group within `holdNearXMetres` of X that is fighting carries on. Holdouts never switch and keep the resupply rules.
3. **Groups at or near Y.** Those within Y's half size plus `holdDefendNearMetres`, in a normal job state, turn to defend Y.
4. **New arrivals.** Unassigned, Mustering or Travelling groups on foot fast travel to the side's nearest other sector that allows it, then push into Y. Groups in vehicles drive.
5. **Back to X.** Y is clear when `frontFighting` is false and no enemy is known there for `holdClearSeconds`. Groups defending Y go back to Unassigned and the normal assignment sends them to X, as `hold` or `counter` depending on whether any holdouts are alive.
6. **Y falls while defended.** The goal returns to X. Y gets the same sector protection as X, so the men inside can walk out.
7. **Commitment timer.** If it moves the side on, the hold ends and `frontGoal` clears.

## Tunables

`holdoutSwitching` true, `holdClearSeconds` 120, `holdNearXMetres` 350, `holdDefendNearMetres` 150.

## Decision rows

| Decision | Why |
|---|---|
| While a hold exists, reinforcements stop only when the goal is `defend`; the target stays X throughout | Holdouts at X still need Warlords' protection, and a target flip would risk that |
| Y's clear test is `frontFighting` plus the commander's known threat at Y | Matches the brief's "no active fighting, and no enemy known inside Y's area" |
| Assaulting groups count as near Y only when they're at Y | A group attacking elsewhere shouldn't be pulled off |

## Player-visible text

Radio (`%1` is the sector name), each with a 20 s cooldown:

- `holdgoal_hold`: "Holding %1. All free units get to them." / "Priority is %1. Reinforce the holdouts." / "Holding %1, reinforcements go there first."
- `holdgoal_counter`: "Counterattacking %1." / "Holdouts are gone. Counterattack %1." / "We're taking %1 back."
- `holdgoal_defend`: "Defending %1. Expel them." / "Enemy at %1, everyone not fighting defends it." / "Defending %1, push them out."

Panel, in front of the capture status line: "Holding %1", "Counterattacking %1" or "Defending %1". No client change was needed.

## Scenario and gate

Same scenario and round as Part A (`fronta`). It switches the stubbed `frontFighting` on for Y at t0+390 and off at t0+480. The override `holdClearSeconds=60` shortens the wait for the switch back.

Gate limits: switch within 30 s of fighting starting at Y, back to X within 200 s of it stopping, counter within 40 s of the wipe.

## Scenario limits

- `frontFighting` is a stub, so the real detection is only exercised in Part B's own scenario.
- The merged result (A, B, C and D together) hasn't been tested. Without Part B merged, no sector counts as fighting outside the scenario, so the goal never becomes `defend`. Without Part D, "fighting" falls back to the leader being in COMBAT mode.
- A forced revote also affects a side with human players on it, because Warlords has one vote per side.
- Only one Y at a time. A second sector under attack waits until the first is resolved.
