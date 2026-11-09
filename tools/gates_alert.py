"""Alert and defence in depth gates. Imported by analyse_round.py, which calls register(check).

Reads the GAL lines from the alert scenario and the C_ALERT, C_STATE and C_DEF lines from the commander.
event=sample every 5 s, event=spot for each group just before the break-in, event=breakin when the attackers stop being captive.
"""

from __future__ import annotations

from typing import Callable

GATE = "alert"

ARC_TOLERANCE = 120      # alertCoverArc is 100; a leader moves a little around its spot, or into a building
GOAL_REACHED_M = 90      # a group this close to its spot counts as set up: a LAMBS garrison spreads within lambsHoldRadius (75) of it
SCREEN_ARC = 50          # the screen stands on the approach, with a short search for cover
SCREEN_BEYOND_M = 80     # at least this far outside the sector edge
COUNTER_LIMIT_S = 180    # the counterattack reserve is in the square within this long of the break-in


def gal(data, event: str) -> list[dict[str, str]]:
    return [e for e in data.of("GAL") if e.get("event") == event]


def _num(entry: dict[str, str] | None, key: str, default: float = 0.0) -> float:
    try:
        return float((entry or {}).get(key, default))
    except (TypeError, ValueError):
        return default


def sector(data) -> str:
    setup = gal(data, "setup")
    return setup[0].get("sector", "") if setup else ""


def alerts(data, event: str) -> list[dict[str, str]]:
    name = sector(data)
    return [e for e in data.of("C_ALERT") if e.get("side") == "WEST" and e.get("sector") == name and e.get("event") == event]


def _first(samples: list[dict[str, str]], key: str) -> float | None:
    for e in samples:
        if _num(e, key) > 0:
            return _num(e, "t")
    return None


def logged(data) -> tuple[bool, str]:
    rows = alerts(data, "start")
    if not rows:
        return False, f"no C_ALERT start for WEST at {sector(data) or '?'}"
    e = rows[0]
    return True, f"{e.get('sector')} bearing {e.get('bearing')}, {e.get('roads')} road points, stance {e.get('stance')}, main/screen/counter {e.get('main')}/{e.get('screen')}/{e.get('counter')}"


def defenders_first(data) -> tuple[bool, str]:
    samples = gal(data, "sample")
    main = _first(samples, "mainIn")
    if main is None:
        return False, "no main position group ever reached the square"
    breakin = gal(data, "breakin")
    attackers = _first(samples, "attIn")
    if attackers is None:
        attackers = _num(breakin[0], "t") if breakin else None
    if attackers is None:
        return False, f"defenders in at t={main:.0f} but the scenario never reached the attackers' arrival"
    return main < attackers, f"defenders in at t={main:.0f}, attackers at t={attackers:.0f}"


def main_approach(data) -> tuple[bool, str]:
    spots = [e for e in gal(data, "spot") if e.get("role") == "main"]
    if not spots:
        return False, "no main position groups at the break-in"
    set_up = [e for e in spots if 0 <= _num(e, "fromGoal", -1) <= GOAL_REACHED_M]
    if not set_up:
        return False, f"none of {len(spots)} groups was at its spot"
    wrong = [e for e in set_up if _num(e, "off", 999) > ARC_TOLERANCE or _num(e, "goalOff", 999) > ARC_TOLERANCE]
    detail = ", ".join(f"{e.get('group')} off {e.get('off')} deg" for e in set_up)
    return not wrong, f"{len(set_up)} of {len(spots)} at their spots: {detail}"


def screen_out(data) -> tuple[bool, str]:
    spots = [e for e in gal(data, "spot") if e.get("role") == "screen"]
    if not spots:
        return False, "no screen group at the break-in"
    wrong = [e for e in spots if _num(e, "goalOff", 999) > SCREEN_ARC or (_num(e, "fromGoal", 999) <= GOAL_REACHED_M and _num(e, "out") < _num(e, "half") + SCREEN_BEYOND_M)]
    detail = ", ".join(f"{e.get('group')} {e.get('out')} m out (half {e.get('half')}), goal off {e.get('goalOff')} deg" for e in spots)
    return not wrong, detail


def counter_held(data) -> tuple[bool, str]:
    assigned: dict[str, float] = {}
    for e in alerts(data, "counter"):
        assigned.setdefault(e.get("group", ""), _num(e, "t"))
    if not assigned:
        return False, "no counter reserve assigned"
    breakin = gal(data, "breakin")
    until = _num(breakin[0], "t") if breakin else 1e12
    held = [e for e in gal(data, "sample") if _num(e, "t") < until and _num(e, "counterReserve") > 0]
    moved = [e for e in data.of("C_STATE")
             if e.get("side") == "WEST" and e.get("group") in assigned and e.get("reason") in ("reserve_rotated", "reserve_shrunk")
             and assigned[e.get("group", "")] <= _num(e, "t") < until]
    ok = bool(held) and not moved
    return ok, f"{sorted(n for n in assigned if n)} held in {len(held)} samples, {len(moved)} times taken off the job"


def counter_hit(data) -> tuple[bool, str]:
    hits = alerts(data, "counter_hit")
    if not hits:
        return False, "no counter_hit logged"
    return True, f"{len(hits)} groups, why {hits[0].get('why')}, {hits[0].get('dist')} m away, {hits[0].get('after')} s after the alert"


def counter_arrives(data) -> tuple[bool, str]:
    breakin = gal(data, "breakin")
    if not breakin:
        return False, "the break-in never came"
    t0 = _num(breakin[0], "t")
    samples = [e for e in gal(data, "sample") if _num(e, "t") >= t0]
    arrived = _first(samples, "heldIn")
    if arrived is None:
        return False, f"none of the {breakin[0].get('held')} held groups reached the square"
    return arrived - t0 <= COUNTER_LIMIT_S, f"in the square {arrived - t0:.0f} s after the break-in"


def finished(data) -> tuple[bool, str]:
    fails = [e.get("event", "?") for e in data.of("GAL") if e.get("event", "").startswith("fail")]
    return bool(gal(data, "done")) and not fails, f"done lines {len(gal(data, 'done'))}, failures {fails or 'none'}"


def no_script_errors(data) -> tuple[bool, str]:
    ours = sum(e.count for e in data.script_errors if not e.file.lower().lstrip("/\\").startswith("a3"))
    return ours == 0, f"{ours} script errors in our code"


def register(check: Callable) -> None:
    check("Alert: the enemy's target starts the alert", gate=GATE)(logged)
    check("Alert: defenders reach the sector before the attackers", gate=GATE)(defenders_first)
    check("Alert: main position is on the approach side", gate=GATE)(main_approach)
    check("Alert: a screen stands forward on the approach", gate=GATE)(screen_out)
    check("Alert: the counterattack reserve is held and not rotated out", gate=GATE)(counter_held)
    check("Alert: the reserve is sent in on the break-in", gate=GATE)(counter_hit)
    check("Alert: the reserve reaches the square within 3 minutes", gate=GATE)(counter_arrives)
    check("Alert: the scenario ran to the end", gate=GATE)(finished)
    check("Alert: no script errors", gate=GATE)(no_script_errors)
