"""Part H (smarter squads) gates. Imported by analyse_round.py, which calls register(check).

Reads the C_SQUAD lines from commander/swlc/squads.sqf and the GH lines from the gateh scenario.
"""

from __future__ import annotations

from collections import defaultdict
from typing import Callable

GATE = "parth"

MAX_POSTURE_CHANGES_PER_MIN = 1.5
MIN_POSTURE_MINUTES = 3.0
ROAD_MIN_TARGET_M = 800
CAREFUL_MAX_TARGET_M = 450
CAREFUL_MAX_CONTACT_M = 350
MIN_BOUNDS = 3


def squad(data, behaviour: str, event: str | None = None) -> list[dict[str, str]]:
    return [
        e
        for e in data.of("C_SQUAD")
        if e.get("behaviour") == behaviour and (event is None or e.get("event") == event)
    ]


def gh(data, event: str) -> list[dict[str, str]]:
    return [e for e in data.of("GH") if e.get("event") == event]


def lambs_loaded(data) -> bool:
    return any(e.get("lambs") == "true" for e in squad(data, "lambs", "detected"))


def _num(entry: dict[str, str], key: str, default: float = 0.0) -> float:
    try:
        return float(entry.get(key, default))
    except (TypeError, ValueError):
        return default


def posture_modes(data) -> tuple[bool, str]:
    modes = [e for e in squad(data, "posture", "mode") if e.get("mode") != "NONE"]
    seen = {e.get("mode") for e in modes}
    missing = {"OPEN", "CAREFUL"} - seen
    note = f"{len(modes)} changes, modes {sorted(m for m in seen if m)}"
    if missing:
        return False, f"never used {sorted(missing)}. {note}"
    wrong = [e for e in modes if e.get("speed") == "" or e.get("formation") == ""]
    if wrong:
        return False, f"{len(wrong)} changes logged no speed or formation. {note}"
    return True, note


def posture_correct(data) -> tuple[bool, str]:
    modes = [e for e in squad(data, "posture", "mode") if e.get("mode") != "NONE"]
    if not modes:
        return False, "no posture changes logged"
    bad: list[str] = []
    for e in modes:
        target = _num(e, "d_target", 1e6)
        contact = _num(e, "d_contact", -1)
        mode = e.get("mode")
        if mode == "ROAD" and (target < ROAD_MIN_TARGET_M or e.get("formation") != "COLUMN" or e.get("speed") != "FULL"):
            bad.append(f"ROAD at {target:.0f} m, {e.get('formation')}, {e.get('speed')}")
        if mode == "CAREFUL":
            near_contact = 0 <= contact <= CAREFUL_MAX_CONTACT_M
            if target > CAREFUL_MAX_TARGET_M and not near_contact:
                bad.append(f"CAREFUL at {target:.0f} m from target, contact {contact:.0f} m")
            if e.get("speed") == "FULL":
                bad.append(f"CAREFUL at FULL speed, {target:.0f} m out")
    return not bad, "; ".join(bad[:4]) if bad else f"{len(modes)} changes checked"


def posture_no_thrash(data) -> tuple[bool, str]:
    times: dict[str, list[int]] = defaultdict(list)
    for e in squad(data, "posture", "mode"):
        times[e.get("group", "?")].append(int(_num(e, "t")))
    worst = 0.0
    worst_group = "-"
    for group, stamps in times.items():
        minutes = (max(stamps) - min(stamps)) / 60.0 if len(stamps) > 1 else 0.0
        if minutes < MIN_POSTURE_MINUTES:
            continue
        rate = (len(stamps) - 1) / minutes
        if rate > worst:
            worst, worst_group = rate, group
    if not times:
        return False, "no posture changes logged"
    return worst <= MAX_POSTURE_CHANGES_PER_MIN, f"worst {worst:.2f} changes a minute ({worst_group})"


def bounds_alternate(data) -> tuple[bool, str]:
    runs: dict[str, list[str]] = defaultdict(list)
    for e in squad(data, "bound", "bound"):
        runs[e.get("group", "?")].append(e.get("team", "?"))
    if not runs:
        return False, "no bounds logged"
    best_group, best_len = "-", 0
    for group, teams in runs.items():
        length = 1 if teams else 0
        longest = length
        for prev, cur in zip(teams, teams[1:]):
            length = length + 1 if prev != cur else 1
            longest = max(longest, length)
        if longest > best_len:
            best_group, best_len = group, longest
    return best_len >= MIN_BOUNDS, f"longest alternating run {best_len} ({best_group}), {len(runs)} groups bounded"


def bounds_use_cover(data) -> tuple[bool, str]:
    bounds = squad(data, "bound", "bound")
    if not bounds:
        return False, "no bounds logged"
    covered = sum(1 for e in bounds if e.get("cover") == "true")
    too_long = [e for e in bounds if _num(e, "len") > 130]
    return not too_long, f"{covered} of {len(bounds)} ended at cover, {len(too_long)} over 130 m"


def flank_after_pin(data) -> tuple[bool, str]:
    if lambs_loaded(data):
        return True, "LAMBS loaded, flanking is off by design"
    pins = gh(data, "pin")
    if not pins:
        return False, f"pin scenario never ran, no_group={len(gh(data, 'pin_no_group'))}"
    group = pins[0].get("group")
    starts = [e for e in squad(data, "flank", "start") if e.get("group") == group]
    if not starts:
        detail = gh(data, "pin_no_flank")
        return False, f"{group} never flanked. {detail[0] if detail else ''}"
    suppress = [e for e in squad(data, "flank", "suppress") if e.get("group") == group and _num(e, "men") > 0]
    if not suppress:
        return False, f"{group} flanked but no soldier was told to suppress"
    ends = [e for e in squad(data, "flank", "end") if e.get("group") == group]
    return True, f"{group} flanked, {len(suppress)} suppress orders, ended {[e.get('why') for e in ends]}"


def at_restocks(data) -> tuple[bool, str]:
    if not gh(data, "at_setup"):
        return False, f"AT scenario never ran, no_group={len(gh(data, 'at_no_group'))}"
    done = gh(data, "at_restocked")
    if not done:
        fails = [(e.get("why"), e.get("kind")) for e in squad(data, "rearm", "fail")]
        return False, f"not restocked. rearm failures {fails}, no_source={len(squad(data, 'rearm', 'no_source'))}"
    took = [e for e in squad(data, "rearm", "done") if e.get("kind") in ("AT", "AA")]
    if not took:
        return False, "soldier has rockets but no rearm trip was logged"
    back = gh(data, "at_rejoined")
    if not back or _num(back[0], "dist", 1e6) > 40:
        return False, f"restocked but did not rejoin: {back}"
    return True, f"took {took[0].get('n')} from {took[0].get('source')}, back within {back[0].get('dist')} m"


def lambs_hand_off(data) -> tuple[bool, str]:
    if not lambs_loaded(data):
        return True, "LAMBS not loaded"
    hold = gh(data, "lambs_hold")
    clear = gh(data, "lambs_clear")
    if not hold or hold[0].get("ok") != "true":
        return False, f"garrison did not start: {hold}, no_group={len(gh(data, 'lambs_no_group'))}"
    if not clear or clear[0].get("ok") != "true":
        return False, f"clearing did not start: {clear}"
    held = gh(data, "lambs_held")
    released = gh(data, "lambs_clear_released")
    if not released or released[0].get("task") != "" or released[0].get("disable") == "true":
        return False, f"group not fully released: {released}"
    return True, f"hold {hold[0].get('task')}, indoors {held[0].get('indoors') if held else '?'}, released cleanly"


def lambs_natural_tasks(data) -> tuple[bool, str]:
    if not lambs_loaded(data):
        return True, "LAMBS not loaded"
    natural = [e for e in squad(data, "lambs") if e.get("event") in ("clear", "hold")]
    stops = squad(data, "lambs", "stop")
    replaced = [e for e in stops if e.get("why") == "replaced"]
    # Every release that came from a replaced order is the commander and LAMBS working against each other.
    return len(replaced) <= max(1, len(natural) // 2), f"{len(natural)} tasks, {len(replaced)} replaced by a new order"


def register(check: Callable) -> None:
    check("Part H: posture modes appear with speed and formation", gate=GATE)(posture_modes)
    check("Part H: posture matches distance to target and contacts", gate=GATE)(posture_correct)
    check("Part H: posture doesn't thrash", gate=GATE)(posture_no_thrash)
    check("Part H: both fire teams alternate bounds", gate=GATE)(bounds_alternate)
    check("Part H: bound length stays in range", gate=GATE)(bounds_use_cover)
    check("Part H: a pinned squad suppresses and flanks", gate=GATE)(flank_after_pin)
    check("Part H: an AT soldier out of rockets restocks and rejoins", gate=GATE)(at_restocks)
    check("Part H: LAMBS garrison and clearing hand off cleanly", gate=GATE)(lambs_hand_off)
    check("Part H: commander orders don't fight LAMBS tasks", gate=GATE)(lambs_natural_tasks)
