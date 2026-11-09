"""Front line part B gates (defender fast travel). Imported by analyse_round.py, which calls register(check).

Reads the GFB lines from the frontb scenario and the C_FRONT and C_RADIO lines from the commander.
Each case is a stretch of the scenario: event=case_start, event=sample every 5 s, event=change when the state flips and
event=ft for a real fast travel attempt. event=fire_stopped marks the start of a quiet period.
"""

from __future__ import annotations

from typing import Callable

GATE = "frontb"

CLOSE_LIMIT_S = 90           # 3+ attackers in a sustained exchange close it within this long
SEIZE_CLOSE_LIMIT_S = 20     # a seize closes it within this long
QUIET_MIN_S = 110            # never reopens sooner than this after the fighting stopped: it must not flicker
QUIET_MAX_S = 160            # 2 quiet minutes, plus the last shots ageing out and a poll


def gf(data, event: str) -> list[dict[str, str]]:
    return [e for e in data.of("GFB") if e.get("event") == event]


def of_case(data, event: str, case: str) -> list[dict[str, str]]:
    return [e for e in gf(data, event) if e.get("case") == case]


def _num(entry: dict[str, str] | None, key: str, default: float = 0.0) -> float:
    try:
        return float((entry or {}).get(key, default))
    except (TypeError, ValueError):
        return default


def _true(entry: dict[str, str], key: str) -> bool:
    return str(entry.get(key, "")).lower() == "true"


def sector(data) -> str:
    setup = gf(data, "setup")
    return setup[0].get("sector", "") if setup else ""


def front(data) -> list[dict[str, str]]:
    name = sector(data)
    return [e for e in data.of("C_FRONT") if e.get("side") == "WEST" and e.get("sector") == name]


def kept_open(case: str) -> Callable:
    def run(data) -> tuple[bool, str]:
        samples = of_case(data, "sample", case)
        if not samples:
            return False, "no samples, the case didn't run"
        closed = [e for e in samples if _true(e, "fighting") or not _true(e, "ftopen")]
        changes = [e for e in of_case(data, "change", case) if _true(e, "on")]
        return (not closed and not changes), f"{len(samples)} samples, {len(closed)} with fast travel closed"

    return run


def closes(case: str, limit: float) -> Callable:
    def run(data) -> tuple[bool, str]:
        changes = [e for e in of_case(data, "change", case) if _true(e, "on")]
        if not changes:
            return False, f"never closed ({len(of_case(data, 'sample', case))} samples)"
        after = _num(changes[0], "after")
        return after <= limit, f"closed {after:.0f} s after it started (limit {limit:.0f} s)"

    return run


def reopens(quiet_case: str, stopped_case: str) -> Callable:
    def run(data) -> tuple[bool, str]:
        stopped = [e for e in gf(data, "fire_stopped") if e.get("case") == stopped_case]
        changes = [e for e in of_case(data, "change", quiet_case) if not _true(e, "on")]
        if not stopped or not changes:
            return False, f"stopped logged {len(stopped)}, reopen logged {len(changes)}"
        quiet = _num(changes[0], "t") - _num(stopped[0], "t")
        return QUIET_MIN_S <= quiet <= QUIET_MAX_S, f"reopened {quiet:.0f} s after the fighting stopped ({QUIET_MIN_S}-{QUIET_MAX_S} s allowed)"

    return run


def stayed_closed(data) -> tuple[bool, str]:
    samples = of_case(data, "sample", "exchange_more")
    bad = [e for e in samples if not _true(e, "fighting")]
    return bool(samples) and not bad, f"{len(samples)} samples while still fighting, {len(bad)} showed it open"


def commander_follows(data) -> tuple[bool, str]:
    """A real fast travel attempt at each step must follow the same state, and fall back to the other sector."""
    want = {"hidden": True, "shooting": True, "exchange": False, "exchange_more": False, "exchange_quiet": True, "seizing": False, "seizing_quiet": True}
    wrong = []
    for case, open_expected in want.items():
        tries = of_case(data, "ft", case)
        if not tries:
            wrong.append(f"{case}: no attempt")
            continue
        last = tries[-1]
        if _true(last, "moved") != open_expected or _true(last, "canft") != open_expected or _true(last, "ftopen") != open_expected or _true(last, "var") != open_expected:
            wrong.append(f"{case}: moved={last.get('moved')} canft={last.get('canft')} ftopen={last.get('ftopen')} var={last.get('var')}")
        if not open_expected and not _true(last, "other"):
            wrong.append(f"{case}: the other owned sector was closed too")
    return not wrong, "; ".join(wrong) or f"{len(want)} attempts all followed the state, player and commander switches agree"


def state_samples_agree(data) -> tuple[bool, str]:
    """Across every sample, the commander's check, frontFTOpen and Warlords' own variable never differ, and each is the opposite of fighting."""
    samples = [e for e in gf(data, "sample") if e.get("case") not in ("seizing",)]
    bad = [e for e in samples if len({_true(e, "ftopen"), _true(e, "canft"), _true(e, "var"), not _true(e, "fighting")}) != 1]
    return bool(samples) and not bad, f"{len(samples)} samples, {len(bad)} disagree"


def logged(data) -> tuple[bool, str]:
    rows = front(data)
    closed = [e for e in rows if e.get("state") == "closed"]
    opened = [e for e in rows if e.get("state") == "open"]
    whys = {e.get("why") for e in closed}
    ok = len(closed) >= 2 and len(opened) >= 2 and {"exchange", "seizing"} <= whys
    return ok, f"{len(closed)} closed ({sorted(w for w in whys if w)}), {len(opened)} opened"


def radio(data) -> tuple[bool, str]:
    rows = [e for e in data.of("C_RADIO") if e.get("side") == "WEST"]
    closed = [e for e in rows if e.get("type") == "ftclose"]
    opened = [e for e in rows if e.get("type") == "ftopen"]
    return bool(closed) and bool(opened), f"{len(closed)} closed lines, {len(opened)} open lines"


def finished(data) -> tuple[bool, str]:
    fails = [e.get("event", "?") for e in data.of("GFB") if e.get("event", "").startswith("fail")]
    return bool(gf(data, "done")) and not fails, f"done lines {len(gf(data, 'done'))}, failures {fails or 'none'}"


def no_script_errors(data) -> tuple[bool, str]:
    ours = sum(e.count for e in data.script_errors if not e.file.lower().lstrip("/\\").startswith("a3"))
    return ours == 0, f"{ours} script errors in our code"


def register(check: Callable) -> None:
    check("Front B: a lone enemy hidden in the sector keeps it open", gate=GATE)(kept_open("hidden"))
    check("Front B: a lone enemy shooting from inside keeps it open", gate=GATE)(kept_open("shooting"))
    check("Front B: 3 or more attackers in a sustained exchange close it within 90 s", gate=GATE)(closes("exchange", CLOSE_LIMIT_S))
    check("Front B: it stays closed while the fighting goes on", gate=GATE)(stayed_closed)
    check("Front B: 2 quiet minutes reopen it after an exchange", gate=GATE)(reopens("exchange_quiet", "exchange"))
    check("Front B: an enemy seizing it closes it", gate=GATE)(closes("seizing", SEIZE_CLOSE_LIMIT_S))
    check("Front B: 2 quiet minutes reopen it after a seize", gate=GATE)(reopens("seizing_quiet", "seizing"))
    check("Front B: the commander's fast travel follows the same state", gate=GATE)(commander_follows)
    check("Front B: frontFTOpen, adCanFTTo and FastTravelEnabled always agree", gate=GATE)(state_samples_agree)
    check("Front B: every state change is logged", gate=GATE)(logged)
    check("Front B: radio lines when it closes and reopens", gate=GATE)(radio)
    check("Front B: the scenario ran to the end", gate=GATE)(finished)
    check("Front B: no script errors", gate=GATE)(no_script_errors)
