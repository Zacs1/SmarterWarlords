"""Stance gate (attack, hold, rebuild). Imported by analyse_round.py, which calls register(check).

Reads C_STANCE and C_WAVE lines from the commander and the GST lines from the stance scenario.
Everything is split by side, because the two commanders are judged separately.
"""

from __future__ import annotations

from typing import Callable

GATE = "stance"
SIDE = "WEST"
OTHER = "EAST"

REACTION_SECONDS = 40       # the scenario makes the side weak to the stance changing, one evaluation plus slice timing
COMMIT_REACTION_SECONDS = 25
GRACE_SECONDS = 20          # a wave may be logged in the tick the stance changes
MIN_STATE_LINES = 3         # periodic lines per side, so a side that never ran the stance doesn't pass


def gst(data, event: str) -> list[dict[str, str]]:
    return [e for e in data.of("GST") if e.get("event") == event]


def _t(entry: dict[str, str]) -> int:
    return int(entry["t"])


def stance_rows(data, side: str, event: str) -> list[dict[str, str]]:
    return [e for e in data.of("C_STANCE") if e.get("side") == side and e.get("event") == event]


def switches(data, side: str) -> list[dict[str, str]]:
    return stance_rows(data, side, "switch")


def first_after(rows: list[dict[str, str]], t: int) -> dict[str, str] | None:
    return next((r for r in rows if _t(r) >= t), None)


def min_seconds(data) -> int:
    start = gst(data, "start")
    return int(float(start[0].get("min", 0))) if start else 0


def defensive_windows(data, side: str) -> list[tuple[int, int]]:
    """(start, end) of each stretch not in attack. A stretch still open at the end of the log runs to the last tick."""
    windows = []
    opened = None
    for row in switches(data, side):
        if row.get("to") != "attack" and opened is None:
            opened = _t(row)
        if row.get("to") == "attack" and opened is not None:
            windows.append((opened, _t(row)))
            opened = None
    if opened is not None:
        windows.append((opened, 10**9))
    return windows


def check_goes_defensive(data) -> tuple[bool, str]:
    weak = gst(data, "weak")
    if not weak:
        return False, "scenario did not reach the weak stage"
    hit = first_after(switches(data, SIDE), _t(weak[0]))
    if not hit:
        return False, f"{SIDE} never switched after t={_t(weak[0])}"
    delay = _t(hit) - _t(weak[0])
    ok = hit.get("to") in ("hold", "rebuild") and hit.get("reason") == "balance" and delay <= REACTION_SECONDS
    return ok, f"{SIDE} to {hit.get('to')} {delay} s after being made weak, ratio {hit.get('ratio')}, own {hit.get('own')}, known {hit.get('known')}"


def check_reaches_rebuild(data) -> tuple[bool, str]:
    rows = [r for r in switches(data, SIDE) if r.get("to") == "rebuild" and r.get("reason") == "balance"]
    return bool(rows), f"{len(rows)} balance switches to rebuild" + (f", first at t={_t(rows[0])} ratio {rows[0].get('ratio')}" if rows else "")


def check_recovers(data) -> tuple[bool, str]:
    recover = gst(data, "recover")
    if not recover:
        return False, "scenario did not reach the recovery stage"
    rows = [r for r in switches(data, SIDE) if _t(r) >= _t(recover[0]) and r.get("to") == "attack"]
    if not rows:
        return False, f"{SIDE} did not go back to attack after t={_t(recover[0])}"
    return True, f"{SIDE} back in attack {_t(rows[0]) - _t(recover[0])} s after recovering, ratio {rows[0].get('ratio')}"


def _gaps(data, side: str) -> list[tuple[int, str, str]]:
    rows = switches(data, side)
    return [(_t(b) - _t(a), a.get("to", ""), b.get("to", "")) for a, b in zip(rows, rows[1:]) if b.get("reason") == "balance"]


def check_min_time(data) -> tuple[bool, str]:
    minimum = min_seconds(data)
    if minimum <= 0:
        return False, "scenario did not log the minimum time"
    gaps = _gaps(data, SIDE) + _gaps(data, OTHER)
    bad = [g for g in gaps if g[0] < minimum]
    return not bad and bool(gaps), f"{len(gaps)} balance-driven switches followed another, shortest gap {min(g[0] for g in gaps) if gaps else '-'} s, minimum {minimum} s, too short: {bad or 'none'}"


def check_min_time_bit(data) -> tuple[bool, str]:
    held = stance_rows(data, SIDE, "held")
    return bool(held), f"{len(held)} times the minimum time held back a change {SIDE} wanted" + (f", first wanted {held[0].get('wanted')} from {held[0].get('stance')}, {held[0].get('left')} s left" if held else "")


def check_per_side(data) -> tuple[bool, str]:
    other = switches(data, OTHER)
    lines = {side: len(stance_rows(data, side, "state")) for side in (SIDE, OTHER)}
    done = gst(data, "done")
    east_end = done[0].get("east", "?") if done else "?"
    ok = not other and all(n >= MIN_STATE_LINES for n in lines.values()) and east_end == "attack"
    return ok, f"{OTHER} switched {len(other)} times and ended in {east_end}; C_STANCE state lines {lines}"


def check_no_new_waves(data) -> tuple[bool, str]:
    windows = defensive_windows(data, SIDE)
    if not windows:
        return False, f"{SIDE} was never out of attack"
    bad = []
    for row in data.of("C_WAVE"):
        if row.get("side") != SIDE or row.get("event") not in ("new", "assault"):
            continue
        t = _t(row)
        if any(start + GRACE_SECONDS <= t < end for start, end in windows):
            bad.append(f"{row.get('event')} at t={t}")
    return not bad, f"{len(windows)} stretches out of attack, waves started in them: {bad or 'none'}"


def check_commit_feeds(data) -> tuple[bool, str]:
    start = gst(data, "commit_set")
    if not start:
        return False, "scenario did not reach the commit stage"
    t0 = _t(start[0])
    until = int(float(start[0].get("until", 0)))
    rows = [r for r in switches(data, SIDE) if _t(r) >= t0]
    if not rows or rows[0].get("to") != "rebuild" or rows[0].get("reason") != "commit" or _t(rows[0]) - t0 > COMMIT_REACTION_SECONDS:
        return False, f"first switch after the commit rebuild started: {rows[0] if rows else 'none'}"
    left_early = [r for r in rows[1:] if _t(r) < until]
    return not left_early, f"rebuild stance {_t(rows[0]) - t0} s after the commit rebuild began, runs to t={until}, left early: {left_early or 'no'}"


def report_counts(data) -> tuple[bool, str]:
    return True, "; ".join(f"{side}: " + (" ".join(f"{r.get('to')}@{r['t']}({r.get('reason')})" for r in switches(data, side)) or "no switches") for side in (SIDE, OTHER))


def finished(data) -> tuple[bool, str]:
    fails = [e.get("event") for e in data.of("GST") if e.get("event", "").startswith("fail")]
    return bool(gst(data, "done")) and not fails, f"finished={bool(gst(data, 'done'))}, failures={fails or 'none'}"


def no_script_errors(data) -> tuple[bool, str]:
    ours = [e for e in data.script_errors if "swlc" in (e.file or "").lower() or "stance" in (e.file or "").lower()]
    total = sum(e.count for e in ours)
    shown = "; ".join(f"{e.count}x {e.detail[:80]} [{e.file}]" for e in ours[:6])
    return total == 0, f"{total} errors in our scripts" + (f": {shown}" if shown else "")


def register(check: Callable) -> None:
    check("Stance: a side made clearly weaker goes to hold or rebuild", gate=GATE)(check_goes_defensive)
    check("Stance: still weak after the minimum time, it goes to rebuild", gate=GATE)(check_reaches_rebuild)
    check("Stance: it goes back to attack when it recovers", gate=GATE)(check_recovers)
    check("Stance: no flip inside the minimum time, either side", gate=GATE)(check_min_time)
    check("Stance: the minimum time really held a change back", gate=GATE)(check_min_time_bit)
    check("Stance: per side, the other commander ran it and stayed in attack", gate=GATE)(check_per_side)
    check("Stance: no new wave or assault while out of attack", gate=GATE)(check_no_new_waves)
    check("Stance: a commit-timer rebuild sets the rebuild stance and runs its length", gate=GATE)(check_commit_feeds)
    check("Stance: switches", gate=GATE)(report_counts)
    check("Stance: the scenario ran to the end", gate=GATE)(finished)
    check("Stance: no script errors", gate=GATE)(no_script_errors)
