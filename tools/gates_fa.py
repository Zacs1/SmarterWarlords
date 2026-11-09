"""Parts A and C (holding a lost sector, switching the goal) gates. Imported by analyse_round.py, which calls register(check).

Reads C_HOLD lines from the commander and the GFA lines from the fronta scenario. Group names repeat across sides,
so everything here is for SIDE only. Prints PASS/FAIL per check through analyse_round.py.
"""

from __future__ import annotations

from typing import Callable

GATE = "fronta"
SIDE = "WEST"

REINFORCE_WITHIN_SECONDS = 180    # first group heading for the holdouts after they form
VOTE_ALLOW_SECONDS = 90           # the side may be without X as its target this long after it falls: a Warlords vote takes time
TARGET_SHARE = 0.9                # share of samples with X as the target after that
FIGHT_REACTION_SECONDS = 30       # fighting forced at Y to the goal switching to it
BACK_LIMIT_SECONDS = 200          # fighting stopped at Y to the goal back on X: the scenario's clear time of 60 s, plus the enemy memory and sampling
COUNTER_REACTION_SECONDS = 40     # holdouts killed to the goal becoming a counterattack
STAY_METRES = 350                 # holdouts count as having stayed within this of X
FALLBACK_SLACK_METRES = 60        # the group may be this far past its fallback limit, spread and sample timing
DELIVERED_METRES = 40             # a crate this close to the group it was bought for


def gf(data, event: str) -> list[dict[str, str]]:
    return [e for e in data.of("GFA") if e.get("event") == event]


def hold(data, event: str) -> list[dict[str, str]]:
    return [e for e in data.of("C_HOLD") if e.get("side") == SIDE and e.get("event") == event]


def _t(entry: dict[str, str] | None) -> int:
    return int(entry["t"]) if entry else 0


def _num(entry: dict[str, str], key: str, default: float = 0.0) -> float:
    try:
        return float(entry.get(key, default))
    except (TypeError, ValueError):
        return default


def first(rows: list[dict[str, str]]) -> dict[str, str] | None:
    return rows[0] if rows else None


def x_name(data) -> str:
    fell = first(gf(data, "x_fell"))
    return fell.get("x", "") if fell else ""


def formed(data) -> dict[str, str] | None:
    return first([e for e in hold(data, "formed") if e.get("sector") == x_name(data)])


def goal_changes(data, to: str, after: int = 0) -> list[dict[str, str]]:
    return [e for e in hold(data, "goal_change") if e.get("to") == to and _t(e) >= after]


def check_formed(data) -> tuple[bool, str]:
    row = formed(data)
    fell = first(gf(data, "x_fell"))
    if not fell:
        return False, "the scenario never flipped X: " + ", ".join(e.get("event", "") for e in data.of("GFA")[:6])
    if not row:
        return False, f"no holdouts formed at {x_name(data)}"
    return _num(row, "groups") >= 1, f"{row.get('groups')} groups, {row.get('men')} men at {row.get('sector')}, {_t(row) - _t(fell)} s after it fell, target was {row.get('target_was')}"


def check_stayed(data) -> tuple[bool, str]:
    row = formed(data)
    if not row:
        return False, "no holdouts"
    broke_at = _t(first(gf(data, "break"))) or 10**9
    rows = [e for e in gf(data, "track") if _t(row) + 30 <= _t(e) < broke_at]
    far = [e for e in rows if _num(e, "dist_x") > STAY_METRES]
    return bool(rows) and not far, f"{len(rows)} samples before the break, {len(far)} further than {STAY_METRES} m from X"


def check_target(data) -> tuple[bool, str]:
    row = formed(data)
    if not row:
        return False, "no holdouts"
    x = x_name(data)
    start = _t(row) + VOTE_ALLOW_SECONDS
    end = _t(first(gf(data, "done"))) or 10**9
    rows = [e for e in gf(data, "tick") if start <= _t(e) <= end]
    good = sum(1 for e in rows if e.get("target") == x)
    share = good / len(rows) if rows else 0.0
    others = sorted({e.get("target", "") for e in rows if e.get("target") != x})
    return share >= TARGET_SHARE, f"target was {x} in {good} of {len(rows)} samples ({share:.0%}), needs {TARGET_SHARE:.0%}; other values: {others or 'none'}"


def check_reinforce_left(data) -> tuple[bool, str]:
    row = formed(data)
    if not row:
        return False, "no holdouts"
    left = hold(data, "reinforce_left")
    if not left:
        return False, "no group headed for the holdouts"
    after = int(_num(left[0], "after"))
    return after <= REINFORCE_WITHIN_SECONDS, f"first group ({left[0].get('group')}) left after {after} s, limit {REINFORCE_WITHIN_SECONDS} s; {len(left)} groups in all"


def check_reinforce_arrived(data) -> tuple[bool, str]:
    arrived = hold(data, "reinforce_arrived")
    alive = [e for e in arrived if _num(e, "holdouts") >= 1]
    times = [int(_num(e, "after")) for e in alive]
    return bool(alive), f"{len(alive)} of {len(arrived)} arrivals found holdouts alive, seconds after forming: {times[:8]} (one run: the share over several runs is the real measure)"


def check_resupply(data) -> tuple[bool, str]:
    low = first(gf(data, "low"))
    if not low:
        return False, "the scenario never stripped the ammo"
    sent = [e for e in hold(data, "resupply_sent") if _t(e) >= _t(low)]
    delivered = [e for e in hold(data, "resupply_delivered") if _t(e) >= _t(low)]
    close = [e for e in delivered if _num(e, "dist", 1e6) <= DELIVERED_METRES]
    restock = hold(data, "restock")
    return bool(sent) and bool(close), f"{len(sent)} sent, {len(delivered)} delivered, {len(close)} within {DELIVERED_METRES} m, {len(restock)} restocks; first sent {_t(first(sent)) - _t(low) if sent else '-'} s after going low"


def check_fallback(data) -> tuple[bool, str]:
    scen = first(gf(data, "break"))
    if not scen:
        return False, "the scenario never broke a group"
    broke = [e for e in hold(data, "broke") if e.get("group") == scen.get("group") and _t(e) >= _t(scen)]
    if not broke:
        return False, f"{scen.get('group')} never fell back"
    limit = _num(broke[0], "limit")
    spot = _num(broke[0], "dist_x")
    rows = [e for e in gf(data, "track") if e.get("group") == scen.get("group") and _t(e) >= _t(broke[0]) + 45]
    far = [e for e in rows if _num(e, "dist_x") > limit + FALLBACK_SLACK_METRES]
    ok = spot <= limit and not far
    return ok, f"{scen.get('group')} fell back to {spot:.0f} m from X, limit {limit:.0f} m; {len(rows)} samples later, {len(far)} further than {limit + FALLBACK_SLACK_METRES:.0f} m"


def check_counter(data) -> tuple[bool, str]:
    wiped = first(gf(data, "wiped"))
    if not wiped:
        return False, "the scenario never killed the holdouts"
    t0 = _t(wiped)
    counter = goal_changes(data, "counter", t0)
    x = x_name(data)
    if not counter:
        return False, "the goal never became counterattack after the holdouts died"
    after = _t(counter[0]) - t0
    ticks = [e for e in gf(data, "tick") if _t(e) > t0 + COUNTER_REACTION_SECONDS]
    on_x = sum(1 for e in ticks if e.get("target") == x)
    left = [e for e in hold(data, "reinforce_left") if _t(e) >= t0 - 300]
    ok = after <= COUNTER_REACTION_SECONDS and bool(ticks) and on_x == len(ticks)
    return ok, f"counterattack {after} s after the holdouts died; target still {x} in {on_x} of {len(ticks)} later samples; {len(left)} reinforcing groups logged in the 5 minutes before"


def check_switch_to_defend(data) -> tuple[bool, str]:
    on = first(gf(data, "fight_y_on"))
    if not on:
        return False, "the scenario never forced fighting at Y"
    changes = goal_changes(data, "defend", _t(on))
    if not changes:
        return False, "the goal never became defend"
    after = _t(changes[0]) - _t(on)
    return after <= FIGHT_REACTION_SECONDS and changes[0].get("at") == on.get("y"), f"goal became defending {changes[0].get('at')} {after} s after fighting started at {on.get('y')}, limit {FIGHT_REACTION_SECONDS} s"


def check_switch_back(data) -> tuple[bool, str]:
    off = first(gf(data, "fight_y_off"))
    if not off:
        return False, "the scenario never ended the fighting at Y"
    back = [e for e in hold(data, "goal_change") if e.get("from") == "defend" and e.get("to") in ("hold", "counter") and _t(e) >= _t(off)]
    if not back:
        return False, "the goal never went back to X"
    after = _t(back[0]) - _t(off)
    return after <= BACK_LIMIT_SECONDS and back[0].get("at") == x_name(data), f"goal back to {back[0].get('to')} {back[0].get('at')} {after} s after the fighting stopped, limit {BACK_LIMIT_SECONDS} s"


def check_not_pulled(data) -> tuple[bool, str]:
    on = first(gf(data, "fight_y_on"))
    off = first(gf(data, "fight_y_off"))
    if not on or not off:
        return False, "the scenario never ran part C"
    rows = [e for e in gf(data, "track") if _t(on) <= _t(e) <= _t(off) + 60]
    if not rows:
        return False, "no holdouts were being tracked during the fight at Y"
    moved = [e for e in rows if e.get("state") not in ("Defending", "Engaged") or _num(e, "dist_x") > STAY_METRES]
    names = {e.get("group") for e in rows}
    defend = [e for e in hold(data, "group_defend") if e.get("group") in names and _t(e) >= _t(on)]
    return not moved and not defend, f"{len(names)} holdout groups over {len(rows)} samples: {len(moved)} out of place, {len(defend)} told to defend Y"


def check_group_defend(data) -> tuple[bool, str]:
    rows = hold(data, "group_defend")
    ft = hold(data, "group_ft")
    near = [e for e in rows if e.get("was_near") == "true"]
    return bool(rows), f"{len(rows)} groups turned to defend Y ({len(near)} already near it), {len(ft)} fast travelled in from another sector"


def report_events(data) -> tuple[bool, str]:
    counts: dict[str, int] = {}
    for row in data.of("C_HOLD"):
        key = f"{row.get('side')} {row.get('event')}"
        counts[key] = counts.get(key, 0) + 1
    return True, "C_HOLD events: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items()))


def finished(data) -> tuple[bool, str]:
    fails = [e.get("event") for e in data.of("GFA") if e.get("event", "").startswith("fail")]
    reflips = len(gf(data, "reflip"))
    return bool(gf(data, "done")) and not fails, f"finished={bool(gf(data, 'done'))}, failures={fails or 'none'}, X flipped back {reflips} times by the scenario"


def no_script_errors(data) -> tuple[bool, str]:
    ours = [e for e in data.script_errors if "swlc" in (e.file or "").lower() or "fronta" in (e.file or "").lower()]
    total = sum(e.count for e in ours)
    shown = "; ".join(f"{e.count}x {e.detail[:80]} [{e.file}]" for e in ours[:6])
    return total == 0, f"{total} errors in our scripts" + (f": {shown}" if shown else "")


def register(check: Callable) -> None:
    check("Part A: holdouts form when X falls with groups inside", gate=GATE)(check_formed)
    check("Part A: holdouts stay at X", gate=GATE)(check_stayed)
    check("Part A: the side's target stays X", gate=GATE)(check_target)
    check(f"Part A: reinforcements leave within {REINFORCE_WITHIN_SECONDS} s", gate=GATE)(check_reinforce_left)
    check("Part A: reinforcements arrive while holdouts are alive", gate=GATE)(check_reinforce_arrived)
    check("Part A: a resupply reaches holdouts who are low", gate=GATE)(check_resupply)
    check("Part A: broken holdouts fall back no further than cover near X", gate=GATE)(check_fallback)
    check("Part A: with no holdouts left, the side counterattacks X", gate=GATE)(check_counter)
    check("Part C: the goal switches to defending Y when fighting starts there", gate=GATE)(check_switch_to_defend)
    check("Part C: the goal goes back to X once Y is clear", gate=GATE)(check_switch_back)
    check("Part C: holdouts fighting near X are not pulled away", gate=GATE)(check_not_pulled)
    check("Part C: other groups turn to defend Y", gate=GATE)(check_group_defend)
    check("Parts A and C: event counts", gate=GATE)(report_events)
    check("Parts A and C: the scenario ran to the end", gate=GATE)(finished)
    check("Parts A and C: no script errors", gate=GATE)(no_script_errors)
