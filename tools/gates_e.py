"""Part E (pickets and proportionate response) gates. Imported by analyse_round.py, which calls register(check).

Reads C_PICKET, C_DEF, C_WAVE, C_RADIO and C_FT lines from the commander and the GE lines from the gatee scenario.
"""

from __future__ import annotations

from typing import Callable

GATE = "parte"
SIDE = "WEST"

SMALL_RAID_MAX_NEED = 3  # the scenario sets 4 men per group for stage 1, so 8 raiders need the picket, the reserve and one group from the wave


def ge(data, event: str) -> list[dict[str, str]]:
    return [e for e in data.of("GE") if e.get("event") == event]


def one(data, event: str) -> dict[str, str] | None:
    found = ge(data, event)
    return found[0] if found else None


def _num(entry: dict[str, str], key: str, default: float = 0.0) -> float:
    try:
        return float(entry.get(key, default))
    except (TypeError, ValueError):
        return default


def _failures(data) -> str:
    return ", ".join(e.get("event", "?") for e in data.of("GE") if e.get("event", "").startswith("fail")) or "none"


def sector_of(data) -> str:
    picket = one(data, "picket") or one(data, "picket_missing") or {}
    return picket.get("sector", "")


def defs(data, event: str) -> list[dict[str, str]]:
    sector = sector_of(data)
    return [e for e in data.of("C_DEF") if e.get("side") == SIDE and e.get("event") == event and e.get("sector") == sector]


def radio(data, kind: str) -> list[dict[str, str]]:
    return [e for e in data.of("C_RADIO") if e.get("side") == SIDE and e.get("type") == kind]


def waves(data, event: str) -> list[dict[str, str]]:
    return [e for e in data.of("C_WAVE") if e.get("side") == SIDE and e.get("event") == event]


def _t(entry: dict[str, str] | None, default: float = 0.0) -> float:
    return _num(entry, "t", default) if entry else default


def stage1_end(data) -> float:
    """When the first response stood down, or the end of the round if it never did."""
    start = _t(one(data, "stage1_start"))
    downs = [e for e in defs(data, "stand_down") if _t(e) >= start]
    return _t(downs[0]) if downs else float(data.last_t)


def stage1(data, event: str) -> list[dict[str, str]]:
    start = _t(one(data, "stage1_start"))
    end = stage1_end(data)
    return [e for e in defs(data, event) if start <= _t(e) <= end]


def stage2(data, event: str) -> list[dict[str, str]]:
    start = one(data, "stage2_start")
    if not start:
        return []
    return [e for e in defs(data, event) if _t(e) >= _t(start)]


def pickets_assigned(data) -> tuple[bool, str]:
    assigned = [e for e in data.of("C_PICKET") if e.get("side") == SIDE and e.get("event") == "assign"]
    if not assigned:
        return False, f"no pickets assigned. failures: {_failures(data)}"
    if not one(data, "picket"):
        return False, f"{len(assigned)} assigned, but none was on a front-line sector when the scenario looked"
    sector = sector_of(data)
    here = [e for e in assigned if e.get("sector") == sector]
    return bool(here), f"{len(assigned)} assigned, {sector} held by {here[0].get('group') if here else 'nobody'}"


def seizing_alarm(data) -> tuple[bool, str]:
    seen = one(data, "seizing")
    if not seen:
        return False, f"stage 1 never ran. failures: {_failures(data)}"
    alarms = stage1(data, "seizing")
    calls = radio(data, "seizing")
    note = "alarm raised by the scenario, the engine never started counting" if seen.get("forced") == "true" else "real Warlords countdown"
    return bool(alarms) and bool(calls), f"C_DEF seizing {len(alarms)}, radio {len(calls)}, {note}"


def reserve_first(data) -> tuple[bool, str]:
    responds = stage1(data, "respond")
    if not responds:
        return False, "nobody responded"
    ready = one(data, "wave_ready")
    if ready and _num(ready, "reserve") == 0:
        return True, "no reserve group existed, nothing to check"
    reserve = [e for e in responds if e.get("reason") == "reserve"]
    peels = stage1(data, "peel")
    if not reserve:
        return False, f"a reserve group was ready but responses were {[e.get('reason') for e in responds]}"
    if peels and _t(peels[0]) < _t(reserve[0]):
        return False, f"peeled at t={_t(peels[0]):.0f} before the reserve went at t={_t(reserve[0]):.0f}"
    return True, f"reserve {reserve[0].get('group')} sent first, {len(peels)} peeled after"


def proportionate(data) -> tuple[bool, str]:
    responds = stage1(data, "respond")
    peels = stage1(data, "peel")
    response = one(data, "stage1_response")
    if not responds or not response:
        return False, f"no response. failures: {_failures(data)}"
    if not peels:
        return False, f"nobody peeled from the wave: {response}"
    bad: list[str] = []
    distinct = {e.get("group") for e in responds}
    max_need = max(_num(e, "need") for e in peels)
    if max_need > SMALL_RAID_MAX_NEED:
        bad.append(f"asked for {max_need:.0f} groups")
    if len(distinct) > SMALL_RAID_MAX_NEED:
        bad.append(f"{len(distinct)} groups went")
    over = [e for e in peels if _num(e, "peeled") > _num(e, "cap")]
    if over:
        bad.append(f"{len(over)} peels over the cap: {[(e.get('peeled'), e.get('cap')) for e in over]}")
    held = one(data, "stage1_held") or {}
    if _num(held, "groups") > SMALL_RAID_MAX_NEED:
        bad.append(f"{held.get('groups')} on the sector after 45 s")
    note = f"{len(distinct)} groups, need {max_need:.0f}, peeled {peels[-1].get('peeled')} of cap {peels[-1].get('cap')}, strength {response.get('strength')}"
    return not bad, "; ".join(bad) + f" ({note})" if bad else note


def no_fast_travel_in(data) -> tuple[bool, str]:
    sector = sector_of(data)
    responds = defs(data, "respond")
    if not responds:
        return False, "nobody responded"
    downs = sorted(_t(e) for e in defs(data, "stand_down"))
    windows: dict[str, list[tuple[float, float]]] = {}
    for e in responds:
        start = _t(e)
        end = next((d for d in downs if d >= start), float(data.last_t))
        windows.setdefault(e.get("group", "?"), []).append((start, end))
    bad: list[str] = []
    hops = 0
    for e in data.of("C_FT"):
        if e.get("side") != SIDE or not any(start <= _t(e) <= end for start, end in windows.get(e.get("group", "?"), [])):
            continue
        hops += 1
        if e.get("sector") == sector:
            bad.append(f"{e.get('group')} at t={_t(e):.0f}")
    return not bad, f"fast travelled into {sector}: {bad}" if bad else f"{len(windows)} responders, {hops} hops, none into {sector}"


def responders_return(data) -> tuple[bool, str]:
    clear = one(data, "stage1_clear")
    if not clear:
        return False, f"stage 1 never finished. failures: {_failures(data)}"
    if clear.get("threat_gone") != "true":
        return False, "the threat never stood down"
    downs = stage1(data, "stand_down")
    if not downs or downs[0].get("why") != "clear":
        return False, f"stood down for {[e.get('why') for e in downs]}"
    back = ge(data, "returned")
    if not back:
        return False, "no peeled groups to bring back"
    stuck = [e for e in back if e.get("state") == "Defending" or _num(e, "peeled_flag", -1) >= 0]
    if stuck:
        return False, f"still on the response: {stuck}"
    if not radio(data, "defreturn"):
        return False, "no radio call for the return"
    return True, f"{len(back)} groups returned as {sorted({e.get('state') for e in back})} after {downs[0].get('duration')} s"


def escalates(data) -> tuple[bool, str]:
    big = one(data, "strength_big")
    if not big:
        return False, f"stage 2 never reached the second force. failures: {_failures(data)}"
    if big.get("reached") != "true":
        return False, f"strength stayed below the counterattack line: {big}"
    escalations = stage2(data, "escalate")
    if not escalations:
        return False, f"no escalation. first response {one(data, 'stage2_first')}"
    if not any(_num(e, "need") > _num(e, "was") for e in escalations):
        return False, f"logged escalations didn't raise the need: {escalations}"
    if not radio(data, "escalate"):
        return False, "no radio call for the escalation"
    big_at = _t(big)
    peels = [e for e in stage2(data, "peel") if _t(e) > big_at]
    if peels:
        return False, f"{len(peels)} peels after the force reached counterattack size"
    full_rules = [e for e in stage2(data, "respond") if e.get("reason") == "pulled"] + stage2(data, "not_pulling")
    if not full_rules:
        return False, "neither pulled attackers nor logged not_pulling"
    return True, f"need {escalations[0].get('was')} to {escalations[-1].get('need')}, then {sorted({e.get('reason', e.get('event')) for e in full_rules})}"


def wave_holds(data) -> tuple[bool, str]:
    start = _t(one(data, "stage1_start"), -1)
    holds = [e for e in waves(data, "peel_hold") if _t(e) >= start]
    if not holds:
        return False, f"no peel_hold logged. held {one(data, 'stage1_held')}"
    if not radio(data, "peelhold"):
        return False, "held but no radio call"
    hold_at = _t(holds[0])
    back_at = stage1_end(data)
    early = [e for e in waves(data, "assault") if hold_at <= _t(e) < back_at]
    if early:
        return False, f"assault at t={_t(early[0]):.0f} while the responders were still out (back t={back_at:.0f})"
    went = [e for e in waves(data, "assault") if _t(e) >= back_at]
    if not went:
        return False, f"the wave never went after the responders came back: {one(data, 'stage1_assault')}"
    return True, f"held from t={hold_at:.0f}, responders back t={back_at:.0f}, assault t={_t(went[0]):.0f} with {went[0].get('groups')} groups"


def no_script_errors(data) -> tuple[bool, str]:
    done = one(data, "done")
    ours = [e for e in data.script_errors if not e.file.lower().lstrip("/\\").startswith("a3")]
    return bool(done) and not ours, f"scenario finished={bool(done)}, {sum(e.count for e in ours)} errors in our scripts"


def register(check: Callable) -> None:
    check("Part E: pickets assigned on the front line", gate=GATE)(pickets_assigned)
    check("Part E: a seize raises the alarm on the radio", gate=GATE)(seizing_alarm)
    check("Part E: the reserve goes before the wave", gate=GATE)(reserve_first)
    check("Part E: a small raid draws a proportionate response within the cap", gate=GATE)(proportionate)
    check("Part E: responders never fast travel into the sector under attack", gate=GATE)(no_fast_travel_in)
    check("Part E: responders return afterwards", gate=GATE)(responders_return)
    check("Part E: a bigger attack escalates to the defence rules", gate=GATE)(escalates)
    check("Part E: the main wave holds rather than collapsing", gate=GATE)(wave_holds)
    check("Part E: finished without script errors", gate=GATE)(no_script_errors)
