"""Part D (fights on the way) gates. Imported by analyse_round.py, which calls register(check).

Reads the C_ENGAGED lines from commander/swlc/engaged.sqf and the GD lines from the frontd scenario.
Group names repeat across sides, so everything is keyed by side and name.
"""

from __future__ import annotations

import math
from typing import Callable

GATE = "frontd"

COLLISION_RADIUS_M = 700
BOARD_RADIUS_M = 450
BOARD_WINDOW_S = 90
MID_FIGHT_SAMPLE_S = 30    # the observer's sample interval: a fighting=1 sample covers the 30 s before it
RESUME_WINDOW_S = 60
RESUMED_OUTCOMES = ("cleared", "quiet")
MOVING_ON_JOBS = ("Advancing", "Travelling", "Waiting", "Reserve")


def _num(entry: dict[str, str], key: str, default: float = 0.0) -> float:
    try:
        return float(entry.get(key, default))
    except (TypeError, ValueError):
        return default


def _t(entry: dict[str, str]) -> float:
    return _num(entry, "t")


def engaged(data, event: str | None = None) -> list[dict[str, str]]:
    return [e for e in data.of("C_ENGAGED") if event is None or e.get("event") == event]


def gd(data, event: str) -> list[dict[str, str]]:
    return [e for e in data.of("GD") if e.get("event") == event]


def _near(entry: dict[str, str], x: float, y: float, radius: float, xk: str = "x", yk: str = "y") -> bool:
    return math.hypot(_num(entry, xk) - x, _num(entry, yk) - y) <= radius


def collision_starts(data) -> dict[str, list[dict[str, str]]]:
    """Each side's contacts inside the scenario's collision area."""
    out: dict[str, list[dict[str, str]]] = {"WEST": [], "EAST": []}
    placed = gd(data, "collision")
    if not placed:
        return out
    x, y = _num(placed[0], "x"), _num(placed[0], "y")
    for e in engaged(data, "start"):
        if e.get("side") in out and _near(e, x, y, COLLISION_RADIUS_M):
            out[e["side"]].append(e)
    return out


def both_stop(data) -> tuple[bool, str]:
    if not gd(data, "collision"):
        return False, f"the scenario never set up the collision: {gd(data, 'no_op') or gd(data, 'no_ground') or 'no GD lines'}"
    starts = collision_starts(data)
    note = f"WEST {len(starts['WEST'])}, EAST {len(starts['EAST'])} contacts"
    return bool(starts["WEST"] and starts["EAST"]), note


def on_radio_and_board(data) -> tuple[bool, str]:
    starts = collision_starts(data)
    problems = []
    notes = []
    for side, rows in starts.items():
        if not rows:
            problems.append(f"{side} no contact")
            continue
        first = min(_t(e) for e in rows)
        radio = [e for e in data.of("C_RADIO") if e.get("side") == side and e.get("type") == "engaged"]
        heard = [e for e in radio if first - 15 <= _t(e) <= first + BOARD_WINDOW_S]
        board = [
            e for e in data.of("C_INTEL")
            if e.get("side") == side and e.get("event") == "new"
            and any(abs(_t(e) - _t(r)) <= BOARD_WINDOW_S and _near(e, _num(r, "cx"), _num(r, "cy"), BOARD_RADIUS_M) for r in rows)
        ]
        if not heard:
            problems.append(f"{side} no radio report")
        if not board:
            problems.append(f"{side} nothing new on the board near the contact")
        notes.append(f"{side} radio {len(heard)}, board {len(board)}")
    return not problems, "; ".join(problems + notes)


def joined_in_limits(data) -> tuple[bool, str]:
    joined = engaged(data, "joined")
    if not joined:
        return False, "no group joined a fight"
    over = [e for e in joined if _num(e, "have") > _num(e, "need")]
    if over:
        return False, f"{len(over)} joins went past the need: {[(e.get('group'), e.get('have'), e.get('need')) for e in over[:3]]}"
    return True, f"{len(joined)} joins, need up to {max(int(_num(e, 'need')) for e in joined)}"


def _mid_fight_windows(data) -> dict[tuple[str, str], list[tuple[float, float]]]:
    """When each group was fighting: the Engaged stretch from the log, and every sample flagged as fighting."""
    out: dict[tuple[str, str], list[tuple[float, float]]] = {}
    opened: dict[tuple[str, str], float] = {}
    for e in sorted(data.of("C_STATE"), key=_t):
        key = (e.get("side", "?"), e.get("group", "?"))
        if e.get("to") == "Engaged":
            opened.setdefault(key, _t(e))
        elif e.get("from") == "Engaged" and key in opened:
            out.setdefault(key, []).append((opened.pop(key), _t(e)))
    for key, start in opened.items():
        out.setdefault(key, []).append((start, float(data.last_t)))
    for group in data.groups.values():
        key = (group.side, group.name.split(" ", 1)[-1])
        for s in group.samples:
            if s.fighting:
                out.setdefault(key, []).append((s.t - MID_FIGHT_SAMPLE_S, float(s.t)))
    return out


def not_interfered(data) -> tuple[bool, str]:
    """Interference: a ladder rung, or a watchdog stuck, reset or escalation, while the group was fighting."""
    windows = _mid_fight_windows(data)
    if not windows:
        return False, "no group was ever fighting"
    hits = []
    for kind, rows in (("ladder", data.of("C_LADDER")), ("watchdog", data.of("C_WD"))):
        for e in rows:
            # This one re-issues the order after a fight, and the watchdog only does it for a group that isn't fighting.
            if e.get("action") == "post_contact_reset":
                continue
            for start, end in windows.get((e.get("side", "?"), e.get("group", "?")), []):
                if start <= _t(e) <= end:
                    hits.append(f"{kind} {e.get('side')} {e.get('group')} at {int(_t(e))}: {e.get('rung') or e.get('action')}")
                    break
    return not hits, f"{len(hits)} on {len(windows)} groups that fought. {hits[:4]}"


def survivors_resume(data) -> tuple[bool, str]:
    ends = [e for e in engaged(data, "end") if e.get("outcome") in RESUMED_OUTCOMES]
    if not ends:
        outcomes = sorted({e.get("outcome", "?") for e in engaged(data, "end")})
        return False, f"no fight ended with survivors carrying on. Outcomes seen: {outcomes}"
    states = data.of("C_STATE")
    resumed = []
    for e in ends:
        side, group, when = e.get("side"), e.get("group"), _t(e)
        match = [
            s for s in states
            if s.get("side") == side and s.get("group") == group and s.get("from") == "Engaged"
            and s.get("to") in MOVING_ON_JOBS and abs(_t(s) - when) <= RESUME_WINDOW_S
        ]
        if match:
            resumed.append((group, match[0].get("to")))
    return bool(resumed), f"{len(resumed)} of {len(ends)} went back to a job: {resumed[:4]}"


def bigger_enemy_falls_back(data) -> tuple[bool, str]:
    placed = gd(data, "fallback")
    if not placed:
        return False, f"the scenario never set up the bigger enemy: {gd(data, 'fallback_skipped')}"
    fell = [e for e in engaged(data, "end") if e.get("outcome") == "fallback"]
    if not fell:
        return False, f"nobody fell back; ends seen: {sorted({e.get('outcome', '?') for e in engaged(data, 'end')})}"
    radio = [e for e in data.of("C_RADIO") if e.get("type") == "engagedfall"]
    sector = fell[0].get("to")
    threat = [e for e in data.of("C_DEF") if e.get("sector") == sector and e.get("event") in ("detect", "respond")]
    if not radio:
        return False, "fell back without a radio report"
    if not threat:
        return False, f"{sector} never went on the threat list"
    return True, f"{len(fell)} groups back to {sector}, {len(threat)} defence lines"


def transports_dismount(data) -> tuple[bool, str]:
    """Only judged if a transport met the enemy: the scenario's waves are on foot and a real wave may not ride."""
    driving = [e for e in engaged(data, "start") if e.get("leg") == "DRIVE"]
    if not driving:
        return True, "no transport met the enemy this round"
    parked = [e for e in data.of("C_VEH") if e.get("event") == "parked" and e.get("reason") == "contact"]
    if not parked:
        return False, f"{len(driving)} transports met the enemy, none dismounted"
    return True, f"{len(parked)} dismounted of {len(driving)}, {len(engaged(data, 'pullback'))} pulled back"


def cost_note(data) -> tuple[bool, str]:
    """C_PROF only appears with profileStages on, so this can't fail: it's here to report the cost."""
    rows = [r for r in data.of("C_PROF") if "engagedTick" in r or "contactAttachAll" in r]
    if not rows:
        return True, "no C_PROF lines. Run with profileStages=true to measure"
    tick = sum(_num(r, "engagedTick") for r in rows) / len(rows)
    attach = sum(_num(r, "contactAttachAll") for r in rows) / len(rows)
    return True, f"engagedTick {tick:.2f} ms, contactAttachAll {attach:.2f} ms per tick"


def register(check: Callable) -> None:
    check("Part D: both waves stop and fight", gate=GATE)(both_stop)
    check("Part D: the contact is on the radio and the board", gate=GATE)(on_radio_and_board)
    check("Part D: nearby groups join within the limits", gate=GATE)(joined_in_limits)
    check("Part D: no watchdog or ladder on a group mid-fight", gate=GATE)(not_interfered)
    check("Part D: survivors go back to their route", gate=GATE)(survivors_resume)
    check("Part D: a much bigger enemy means falling back and a threat", gate=GATE)(bigger_enemy_falls_back)
    check("Part D: transports dismount short and pull back", gate=GATE)(transports_dismount)
    check("Part D: cost per tick (report)", gate=GATE)(cost_note)
