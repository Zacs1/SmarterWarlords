"""Part D (raids and probes) gates. Imported by analyse_round.py, which calls register(check).

Reads the C_RAID and C_PROBE lines from commander/swlc/raids.sqf and the GD lines from the gated scenario.
"""

from __future__ import annotations

import re
from typing import Callable

GATE = "partd"

RAID_MULT = 2.5
RAID_COST = 300
AI_GROUPS_MAX = 2
NOMINAL_TOLERANCE_S = 2.0
# A sighting and a detect land on the same commander tick, in either order.
STEALTH_TOLERANCE_S = 3
# Income can arrive in the half second between the two CP samples around a purchase.
CP_DROP_FRACTION = 0.9
# Warlords pays 10 x value x the income multiplier. Half of that still tells a payout from ordinary income.
PAYOUT_FRACTION = 0.5
CAPTURE_MIN_FRACTION = 0.6
EXPECTED_REFUSALS = {"not_front": "not_front", "funds": "funds", "active": "active", "cooldown": "cooldown"}


def gd(data, event: str) -> list[dict[str, str]]:
    return [e for e in data.of("GD") if e.get("event") == event]


def one(data, event: str) -> dict[str, str] | None:
    found = gd(data, event)
    return found[0] if found else None


def raid(data, event: str | None = None, side: str = "WEST") -> list[dict[str, str]]:
    return [e for e in data.of("C_RAID") if e.get("side") == side and (event is None or e.get("event") == event)]


def probe(data, event: str | None = None, side: str = "WEST") -> list[dict[str, str]]:
    return [e for e in data.of("C_PROBE") if e.get("side") == side and (event is None or e.get("event") == event)]


def _num(entry: dict[str, str], key: str, default: float = 0.0) -> float:
    try:
        return float(entry.get(key, default))
    except (TypeError, ValueError):
        return default


def _middle_timeout(text: str | None) -> float | None:
    """The middle number of a trigger timeout printed as [min,mid,max,interruptible]."""
    numbers = re.findall(r"-?\d+(?:\.\d+)?(?:e[+-]?\d+)?", text or "", flags=re.IGNORECASE)
    return float(numbers[1]) if len(numbers) >= 3 else None


def _failures(data) -> str:
    return ", ".join(e.get("event", "?") for e in data.of("GD") if e.get("event", "").startswith("fail")) or "none"


def setup_reached_front(data) -> tuple[bool, str]:
    front = one(data, "front")
    if not front:
        return False, f"never reached a raidable front. failures: {_failures(data)}"
    return True, f"raiding {front.get('sector')}, front {front.get('front')}, owned {front.get('owned')}"


def refusals(data) -> tuple[bool, str]:
    got = {e.get("case", "?"): e.get("got", "") for e in gd(data, "refusal")}
    wrong = {case: got.get(case, "not tested") for case, want in EXPECTED_REFUSALS.items() if got.get(case) != want}
    return not wrong, f"wrong: {wrong}" if wrong else f"{sorted(got)} all refused for the right reason"


def raid_expires_and_cleans(data) -> tuple[bool, str]:
    start, grace, after = one(data, "t1_start"), one(data, "t1_grace"), one(data, "t1_after")
    if not start or not after:
        return False, f"expiry test incomplete. start={bool(start)}, after={bool(after)}, failures: {_failures(data)}"
    base = _num(start, "base_nominal")
    bad: list[str] = []
    if start.get("in_list") != "true":
        bad.append("sector never added to the conquered list")
    if abs(_num(start, "nominal") - base * RAID_MULT) > NOMINAL_TOLERANCE_S:
        bad.append(f"raid nominal {start.get('nominal')} against base {base}")
    if start.get("marker") in (None, "[]"):
        bad.append("own-side raid marker not published")
    if not grace or grace.get("stage") != "grace" or grace.get("watched") != "false":
        bad.append(f"no grace period seen: {grace}")
    if after.get("cleared") != "true":
        bad.append("raid never cleared")
    if start.get("in_list_before") == "false" and after.get("in_list") != "false":
        bad.append("sector left in the conquered list")
    if after.get("mult") != "nil" or after.get("force") != "nil":
        bad.append(f"left mult={after.get('mult')}, force={after.get('force')}")
    middle = _middle_timeout(after.get("timeout"))
    if middle is None or abs(middle - _num(after, "base_nominal")) > NOMINAL_TOLERANCE_S:
        bad.append(f"trigger timeout {after.get('timeout')} not restored to {after.get('base_nominal')}")
    if after.get("marker") != "[]":
        bad.append(f"marker still set: {after.get('marker')}")
    if _num(after, "cooldown_left") <= 0:
        bad.append("cooldown not started")
    if after.get("owner") != "EAST":
        bad.append(f"owner changed to {after.get('owner')}")
    ended = [e for e in raid(data, "end") if e.get("sector") == start.get("sector")]
    if not raid(data, "stop") or not ended:
        bad.append("no stop or end line logged")
    return not bad, "; ".join(bad) if bad else f"held {ended[0].get('held')} s, then everything put back"


def _stealth_window(data, sector: str, start: float, end: float) -> tuple[bool, str]:
    detects = [e for e in data.of("C_DEF") if e.get("side") == "EAST" and e.get("event") == "detect" and e.get("sector") == sector and start <= _num(e, "t") <= end]
    if not detects:
        return True, f"{sector}: no warning"
    first = _num(detects[0], "t")
    caps = [_num(e, "t") for e in data.of("C_CAP") if e.get("side") == "WEST" and e.get("event") == "start" and e.get("sector") == sector and _num(e, "t") >= start]
    seen = [_num(e, "t") for e in data.of("C_INTEL") if e.get("side") == "EAST" and e.get("event") == "new" and e.get("sector") == sector and _num(e, "t") >= start]
    legitimate = min(caps + seen) if caps or seen else None
    if legitimate is None or first < legitimate - STEALTH_TOLERANCE_S:
        return False, f"{sector}: EAST warned at t={first:.0f}, first sighting or seize {legitimate}"
    return True, f"{sector}: warned t={first:.0f}, after sighting or seize at t={legitimate:.0f}"


def stealth(data) -> tuple[bool, str]:
    start, after = one(data, "t1_start"), one(data, "t1_after")
    buy, end = one(data, "ai_buy"), one(data, "t2_after")
    if not buy:
        return False, f"no AI raid to judge. failures: {_failures(data)}"
    notes: list[str] = []
    passed = True
    if start and after:
        ok, note = _stealth_window(data, start.get("sector", ""), _num(start, "t"), _num(after, "t"))
        passed, notes = passed and ok, notes + [f"T1 {note}"]
    ok, note = _stealth_window(data, buy.get("sector", ""), _num(buy, "t"), _num(end, "t") if end else data.last_t)
    return passed and ok, "; ".join(notes + [f"T2 {note}"])


def probe_outmatched(data) -> tuple[bool, str]:
    sent = one(data, "p1_sent")
    if not sent:
        return False, f"first probe never went. failures: {_failures(data)}"
    group = sent.get("group")
    events = {name: [e for e in probe(data, name) if e.get("group") == group] for name in ("sent", "observe", "back")}
    missing = [name for name, found in events.items() if not found]
    if missing:
        return False, f"{group} logged no {missing}. over: {one(data, 'p1_over')}"
    why = events["back"][0].get("why")
    if why != "outmatched":
        return False, f"{group} came back for '{why}', known {events['back'][0].get('known')}"
    return True, f"{group}: {events['observe'][0].get('men')} men against {events['back'][0].get('known')} known, pulled back"


def probe_reports(data) -> tuple[bool, str]:
    kinds = {e.get("type") for e in data.of("C_RADIO") if e.get("side") == "WEST"}
    missing = {"probe", "probeback", "probeweak"} - kinds
    return not missing, f"missing radio calls {sorted(missing)}" if missing else "sent, pulled back and weak all reported on the radio"


def probe_buys_raid(data) -> tuple[bool, str]:
    sent = one(data, "p2_sent")
    if not sent:
        return False, f"second probe never went. failures: {_failures(data)}"
    group = sent.get("group")
    weak = [e for e in probe(data, "weak") if e.get("group") == group]
    bought = [e for e in probe(data, "raid") if e.get("group") == group]
    if not weak or not bought:
        return False, f"{group} weak={len(weak)}, raid={len(bought)}. {one(data, 'p2_over')}, back {[e.get('why') for e in probe(data, 'back') if e.get('group') == group]}"
    started = [e for e in raid(data, "start") if e.get("by") == "probe"]
    if not started:
        return False, "probe logged a raid but no C_RAID start by=probe"
    return True, f"{group} found {weak[0].get('known')} known and bought a raid on {started[0].get('sector')}"


def ai_buys_within_limits(data) -> tuple[bool, str]:
    buy = one(data, "ai_buy")
    if not buy:
        return False, f"AI never bought a raid. failures: {_failures(data)}"
    started = [e for e in raid(data, "start") if e.get("by") == "ai"]
    if not started:
        return False, "scenario saw a raid but no C_RAID start by=ai"
    bad: list[str] = []
    cost = _num(started[0], "cost")
    if cost != RAID_COST:
        bad.append(f"logged cost {cost:.0f}")
    drop = _num(buy, "cp_before") - _num(buy, "cp_after")
    if drop < cost * CP_DROP_FRACTION:
        bad.append(f"CP fell only {drop:.0f}")
    if _num(started[0], "groups") > AI_GROUPS_MAX or _num(started[0], "groups") < 1:
        bad.append(f"sent {started[0].get('groups')} groups")
    if buy.get("in_front") != "true":
        bad.append("raid sector wasn't on the front")
    if buy.get("marker") in (None, "[]"):
        bad.append("marker not published")
    if abs(_num(buy, "mult") - RAID_MULT) > 0.01:
        bad.append(f"mult {buy.get('mult')}")
    return not bad, "; ".join(bad) if bad else f"{drop:.0f} CP, {started[0].get('groups')} groups on {started[0].get('sector')}"


def capture_end_to_end(data) -> tuple[bool, str]:
    buy, payout, after = one(data, "ai_buy"), one(data, "payout"), one(data, "t2_after")
    if not buy or not payout:
        return False, f"AI raid never reached the capture step. failures: {_failures(data)}"
    sector = buy.get("sector")
    if payout.get("flipped") != "true":
        return False, f"{sector} never flipped. raid ends {[e.get('result') for e in raid(data, 'end') if e.get('sector') == sector]}"
    ended = [e for e in raid(data, "end") if e.get("sector") == sector and e.get("result") == "captured"]
    if not ended:
        return False, f"{sector} flipped but no C_RAID end result=captured"
    counting = one(data, "t2_counting")
    if not counting:
        return False, "the trigger was never seen counting down"
    middle = _middle_timeout(counting.get("timeout"))
    want = _num(counting, "base_nominal") * RAID_MULT
    if middle is None or abs(middle - want) > NOMINAL_TOLERANCE_S:
        return False, f"timeout during capture {counting.get('timeout')}, wanted {want:.1f}"
    caps = [e for e in data.of("C_CAP") if e.get("side") == "WEST" and e.get("sector") == sector]
    start = [e for e in caps if e.get("event") == "start"]
    done = [e for e in caps if e.get("event") == "captured"]
    took = _num(done[-1], "t") - _num(start[0], "t") if start and done else -1
    if took < want * CAPTURE_MIN_FRACTION:
        return False, f"capture took {took:.0f} s against {want:.1f} s nominal"
    if after and after.get("cleared") != "true":
        return False, f"raid not cleared after the capture: {after}"
    return True, f"{sector} captured in {took:.0f} s, nominal {want:.1f} s"


def payout_jump(data) -> tuple[bool, str]:
    payout = one(data, "payout")
    if not payout or payout.get("flipped") != "true":
        return False, f"no capture to pay for: {payout}"
    want = 10 * _num(payout, "value") * _num(payout, "mult", 1.0) * PAYOUT_FRACTION
    jump = _num(payout, "max_jump")
    return jump >= want, f"largest warlord jump {jump:.0f} against at least {want:.0f}"


def one_raid_at_a_time(data) -> tuple[bool, str]:
    active: str | None = None
    for e in raid(data):
        if e.get("event") == "start":
            if active is not None:
                return False, f"{e.get('sector')} started at t={e.get('t')} while {active} was running"
            active = e.get("sector")
        elif e.get("event") == "end":
            active = None
    buy = one(data, "ai_buy")
    end = [e for e in raid(data, "end") if buy and e.get("sector") == buy.get("sector") and e.get("result") == "captured"]
    if not end:
        return False, "no captured raid to measure the cooldown from"
    done_at = _num(end[0], "t")
    later = [e for e in raid(data, "start") if _num(e, "t") > done_at]
    done = one(data, "done")
    if later or (done and done.get("raid_active") == "true"):
        return False, f"raid started inside the cooldown: {later}"
    return True, "never two at once, no new raid in the cooldown"


def no_script_errors(data) -> tuple[bool, str]:
    done = one(data, "done")
    ours = [e for e in data.script_errors if not e.file.lower().lstrip("/\\").startswith("a3")]
    return bool(done) and not ours, f"scenario finished={bool(done)}, {sum(e.count for e in ours)} errors in our scripts"


def register(check: Callable) -> None:
    check("Part D: scenario reached a raidable front", gate=GATE)(setup_reached_front)
    check("Part D: raids are refused for the right reasons", gate=GATE)(refusals)
    check("Part D: an expired raid stops, gives grace and undoes itself", gate=GATE)(raid_expires_and_cleans)
    check("Part D: the enemy gets no warning until spotting or seizing", gate=GATE)(stealth)
    check("Part D: a probe that meets a garrison pulls back", gate=GATE)(probe_outmatched)
    check("Part D: probes report on the radio", gate=GATE)(probe_reports)
    check("Part D: a probe that finds nobody buys a raid", gate=GATE)(probe_buys_raid)
    check("Part D: the AI buys a raid within the limits", gate=GATE)(ai_buys_within_limits)
    check("Part D: a raid captures end to end at 2.5 times the time", gate=GATE)(capture_end_to_end)
    check("Part D: a raid capture pays out", gate=GATE)(payout_jump)
    check("Part D: one raid at a time, and the cooldown holds", gate=GATE)(one_raid_at_a_time)
    check("Part D: finished without script errors", gate=GATE)(no_script_errors)
