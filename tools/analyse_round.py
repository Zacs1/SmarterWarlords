#!/usr/bin/env python3
"""Summarises an automated Warlords round from its RPT and runs named PASS/FAIL checks.

    python tools/analyse_round.py <path-to-rpt>

    python tools/analyse_round.py <path-to-rpt> --gate gate0

To add a check, write a function that takes a Round and returns (passed, detail),
and decorate it with @check("name"). Checks given a gate, @check("name", gate="gate0"), run only
with --gate. Exit code is 0 only if every check that ran passes.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).parent))

from swl_log import (  # noqa: E402
    FT_JUMP_M,
    IDLE_MIN_SECONDS,
    IDLE_RADIUS_M,
    Round,
    fmt_time,
    idle_outside_staging,
    idle_stretches,
    jumps,
    parse_log,
)

SIDES = ("WEST", "EAST")
MOVED_METRES = 100.0

CheckFn = Callable[[Round], "tuple[bool, str]"]
CHECKS: list[tuple[str, str | None, CheckFn]] = []


def check(name: str, gate: str | None = None) -> Callable[[CheckFn], CheckFn]:
    def register(fn: CheckFn) -> CheckFn:
        CHECKS.append((name, gate, fn))
        return fn

    return register


@check("AI groups spawned on both sides")
def check_spawned(data: Round) -> tuple[bool, str]:
    counts = {side: sum(1 for g in data.groups_on(side) if g.is_ai) for side in SIDES}
    return all(counts.values()), f"WEST {counts['WEST']}, EAST {counts['EAST']}"


@check("AI groups moved")
def check_moved(data: Round) -> tuple[bool, str]:
    results = []
    passed = True
    for side in SIDES:
        groups = [g for g in data.groups_on(side) if g.is_ai]
        moved = sum(1 for g in groups if g.max_displacement() >= MOVED_METRES)
        results.append(f"{side} {moved}/{len(groups)}")
        if not groups or moved * 2 < len(groups):
            passed = False
    return passed, f"moved {MOVED_METRES:.0f} m or more: " + ", ".join(results)


@check("At least one sector was captured")
def check_captured(data: Round) -> tuple[bool, str]:
    if not data.captures:
        return False, "no CAPTURE lines"
    first = data.captures[0]
    return True, f"{len(data.captures)} captures, first {first.sector} at {fmt_time(first.t)}"


@check("No script errors")
def check_errors(data: Round) -> tuple[bool, str]:
    total = sum(e.count for e in data.script_errors)
    return total == 0, f"{total} script errors"


@check("Adapter target matches the observer over time", gate="gate0")
def check_adapter_target(data: Round) -> tuple[bool, str]:
    readouts = data.of("ADAPTER")
    if not readouts:
        return False, "no ADAPTER lines"
    wrong = 0
    compared = 0
    for side in SIDES:
        changes = [(t.t, t.sector) for t in data.targets if t.side == side]
        for line in (r for r in readouts if r.get("side") == side):
            t = int(line["t"])
            if any(abs(t - c[0]) <= 2 for c in changes):
                continue  # The two loggers sample a moment apart around a change.
            expected = "-"
            for when, sector in changes:
                if when <= t:
                    expected = sector
            compared += 1
            shown = line.get("target", "-")
            if (expected == "-") != (shown == "-"):
                wrong += 1
            elif expected != "-" and expected in data.sectors:
                x, y = [float(v) for v in shown.strip("[]").split(",")[:2]]
                if math.hypot(x - data.sectors[expected].x, y - data.sectors[expected].y) > 1:
                    wrong += 1
    return wrong == 0 and compared > 0, f"{compared} readouts compared, {wrong} wrong"


@check("Adapter ownership follows captures", gate="gate0")
def check_adapter_owned(data: Round) -> tuple[bool, str]:
    readouts = data.of("ADAPTER")
    if not readouts or not data.captures:
        return False, "needs ADAPTER lines and at least one capture"
    wrong = 0
    checked = 0
    for capture in data.captures:
        after = [r for r in readouts if r.get("side") == capture.new and capture.t + 2 <= int(r["t"]) <= capture.t + 12]
        for line in after:
            checked += 1
            points = [[float(v) for v in p.strip("[]").split(",")[:2]] for p in line.get("owned", "").split(";") if p]
            if not any(math.hypot(x - capture.x, y - capture.y) < 1 for x, y in points):
                wrong += 1
    return wrong == 0 and checked > 0, f"{checked} readouts just after {len(data.captures)} captures, {wrong} missing the sector"


@check("Ordered group kept its order and got there", gate="gate0")
def check_move_test(data: Round) -> tuple[bool, str]:
    lines = data.of("MOVE_TEST")
    events = [l.get("event") for l in lines]
    if "order" not in events:
        return False, "no order was issued"
    track = [l for l in lines if l.get("event") == "track"]
    drifted = sum(1 for l in track if float(l.get("wpdist", 0)) > 5)
    reasserts = events.count("reassert")
    distances = [float(l["dist"]) for l in track]
    first = distances[0] if distances else 0
    closest = min(distances) if distances else 0
    arrived = "arrived" in events
    # The group can die and respawn at base mid-walk, so compare with its closest approach.
    detail = f"{len(track)} samples, {drifted} off-order, {reasserts} reasserts, distance {first:.0f} -> closest {closest:.0f} m, arrived={arrived}"
    return drifted == 0 and (arrived or closest < first - 300), detail


@check("Fast travel works to an owned sector and is charged", gate="gate0")
def check_ft(data: Round) -> tuple[bool, str]:
    lines = data.of("FT_TEST")
    if not lines:
        return False, "no FT_TEST line"
    line = lines[0]
    ok = line.get("ok") == "true" and float(line.get("to", 9999)) < 100
    charged = data.of("C_FT")
    return ok and bool(charged), f"ok={line.get('ok')}, {line.get('from')} m -> {line.get('to')} m, cost {charged[0].get('cost') if charged else '?'}"


@check("Fast travel to an unowned sector is refused", gate="gate0")
def check_ft_refuse(data: Round) -> tuple[bool, str]:
    lines = data.of("FT_REFUSE")
    return bool(lines) and lines[0].get("ok") == "false", f"ok={lines[0].get('ok') if lines else '?'}"


@check("Voting continues past the first capture at FT 4", gate="gate0")
def check_targets_continue(data: Round) -> tuple[bool, str]:
    if not data.captures:
        return False, "no captures"
    first = data.captures[0].t
    later = [t for t in data.targets if t.t > first and t.sector != "-"]
    return bool(later), f"{len(later)} targets chosen after the first capture at {fmt_time(first)}"


@check("No AI bought a vehicle while suppressed", gate="gate0")
def check_no_vehicles(data: Round) -> tuple[bool, str]:
    cars = 0
    for group in data.groups.values():
        if group.is_warlord and any(s.vehicle != "-" for s in group.samples):
            cars += 1
    return cars == 0, f"{cars} warlord groups seen in a vehicle"


# Vanilla baseline (tests/server/runs/2026-11-08_19-26-56_baseline): idle group-minutes per 10-minute window.
BASELINE_IDLE_BY_10_MIN = [5.3, 29.4, 49.3, 40.8, 37.6, 11.8, 10.8, 0.2]
EXEMPT_STATES = ("Mustering", "Waiting", "Defending", "Reserve")


def warlord_groups(data: Round):
    return [g for g in data.groups.values() if g.is_ai and g.is_warlord]


def raw_idle_by_window(data: Round, window: int = 600) -> list[float]:
    """Idle group-minutes per window: same measure as the baseline, whatever the group was doing."""
    last = max(data.last_t, 1)
    bins = [0.0] * (last // window + 1)
    for group in warlord_groups(data):
        for stretch in idle_stretches(group):
            for t in range(stretch.start, stretch.end):
                bins[t // window] += 1 / 60
    return [round(b, 1) for b in bins]


@check("No commander group idle 3+ minutes outside a muster or the rally", gate="phase1")
def check_no_idle(data: Round) -> tuple[bool, str]:
    rows = []
    for group in warlord_groups(data):
        for stretch in idle_outside_staging(group, EXEMPT_STATES):
            rows.append(f"{group.name} {fmt_time(stretch.seconds)} from {fmt_time(stretch.start)} at {data.locate(stretch.x, stretch.y)}")
    return not rows, f"{len(rows)} stretches" + ("; " + "; ".join(rows[:12]) if rows else "")


def rally_waits(data: Round) -> list[int]:
    return [int(e["wait"]) for e in data.of("C_WAVE") if e.get("event") == "assault" and int(e.get("wait", -1)) >= 0]


@check("Musters leave quickly and the rally wait stays under 4 minutes", gate="phase1")
def check_wait(data: Round) -> tuple[bool, str]:
    musters = [int(e["wait"]) for e in data.of("C_WAVE") if e.get("event") == "muster_go"]
    rally = rally_waits(data)
    if not rally:
        return False, f"no assaults; {len(musters)} musters left"
    timer = sum(1 for e in data.of("C_WAVE") if e.get("event") == "assault" and e.get("by_timer") == "true")
    ok = max(rally) <= 240 and (not musters or max(musters) <= 85)
    return ok, f"{len(musters)} musters, longest {fmt_time(max(musters, default=0))}; {len(rally)} assaults, longest rally wait {fmt_time(max(rally))}, {timer} alone after the timer"


@check("Groups go in together, alone only after the timer or to reinforce", gate="phase1")
def check_wave_size(data: Round) -> tuple[bool, str]:
    assaults = [e for e in data.of("C_WAVE") if e.get("event") == "assault"]
    if not assaults:
        return False, "no assaults"
    alone = [e for e in assaults if int(e["groups"]) < 2 and e.get("by_timer") != "true" and e.get("forced") != "true"]
    reinforced = sum(1 for e in data.of("C_WAVE") if e.get("event") == "reinforce")
    return not alone, f"{len(assaults)} assaults, sizes {sorted(int(e['groups']) for e in assaults)}, {len(alone)} alone without cause, {reinforced} reinforcing groups"


@check("Idle clearly better than the vanilla baseline", gate="phase1")
def check_idle_vs_baseline(data: Round) -> tuple[bool, str]:
    current = raw_idle_by_window(data)
    n = min(len(current), len(BASELINE_IDLE_BY_10_MIN))
    base_total = sum(BASELINE_IDLE_BY_10_MIN[:n])
    cur_total = sum(current[:n])
    return cur_total * 2 <= base_total, f"group-minutes per 10 min: {current} vs baseline {BASELINE_IDLE_BY_10_MIN[:n]} ({cur_total:.0f} vs {base_total:.0f})"


@check("Commander logged decisions", gate="phase1")
def check_logged(data: Round) -> tuple[bool, str]:
    counts = {k: len(data.of(k)) for k in ("C_VOTE", "C_TARGET", "C_STAGING", "C_WAVE", "C_STATE", "C_WD", "C_FT", "C_TICK")}
    return all(counts[k] > 0 for k in ("C_TARGET", "C_WAVE", "C_STATE", "C_TICK")), str(counts)


def intel_new(data: Round):
    return [e for e in data.of("C_INTEL") if e.get("event") == "new"]


def trace_entries(data: Round) -> tuple[bool, str]:
    """Every board entry must come from a real, plausible sighting, scan, player report or loss."""
    bad = []
    counts: dict[str, int] = {}
    for e in intel_new(data):
        src = e.get("src", "?")
        counts[src] = counts.get(src, 0) + 1
        if src == "see":
            if float(e.get("knows", 0)) < 1 or e.get("tnet") == "-" or e.get("reporter") in ("", None):
                bad.append(f"#{e.get('id')} no real target or reporter")
                continue
            if not 0 <= int(e.get("rdist", -1)) <= 2500:
                bad.append(f"#{e.get('id')} reporter {e.get('rdist')} m away")
                continue
            error = math.hypot(float(e["x"]) - float(e["tx"]), float(e["y"]) - float(e["ty"]))
            if error > 400:
                bad.append(f"#{e.get('id')} {error:.0f} m from the real target")
        elif src == "scan":
            if e.get("tnet") == "-":
                bad.append(f"#{e.get('id')} scan without a target")
        elif src == "loss":
            if not e.get("extra"):
                bad.append(f"#{e.get('id')} loss without a destroyed vehicle")
        elif src != "player":
            bad.append(f"#{e.get('id')} unknown source {src}")
    total = sum(counts.values())
    return not bad and total > 0, f"{total} entries {counts}, {len(bad)} untraceable" + ("; " + "; ".join(bad[:8]) if bad else "")


@check("Every board entry traces to a real sighting", gate="gate2")
def check_trace(data: Round) -> tuple[bool, str]:
    return trace_entries(data)


@check("Every board entry traces to a real sighting", gate="phase2soak")
def check_trace_soak(data: Round) -> tuple[bool, str]:
    return trace_entries(data)


def g2(data: Round, event: str):
    return [e for e in data.of("G2") if e.get("event") == event]


@check("Unseen tank never reached the board", gate="gate2")
def check_hidden(data: Round) -> tuple[bool, str]:
    lines = g2(data, "hidden_check")
    hidden = g2(data, "tank_hidden")
    if not lines or not hidden:
        return False, "scenario did not reach the hidden check"
    net = hidden[0]["net"]
    known_at = int(g2(data, "first_known")[0]["t"]) if g2(data, "first_known") else 10**9
    early = [e for e in intel_new(data) if e.get("side") == "WEST" and e.get("tnet") == net and int(e["t"]) < known_at]
    return lines[0].get("on_board") == "false" and not early, f"on_board={lines[0].get('on_board')}, {len(early)} entries before any group knew"


@check("Seen armour on the board and radio within 10 s", gate="gate2")
def check_armour_fast(data: Round) -> tuple[bool, str]:
    first = g2(data, "first_known")
    if not first:
        return False, "no WEST group ever saw the tank"
    t0 = int(first[0]["t"])
    net = first[0]["net"]
    entry = next((e for e in intel_new(data) if e.get("side") == "WEST" and e.get("tnet") == net), None)
    radio = next((e for e in data.of("C_RADIO") if e.get("side") == "WEST" and e.get("type") == "sighting" and int(e["t"]) >= t0), None)
    if entry is None or radio is None:
        return False, f"entry={entry is not None}, radio={radio is not None}"
    board_s = int(entry["t"]) - t0
    radio_s = int(radio["t"]) - t0
    return board_s <= 10 and radio_s <= 10, f"board after {board_s} s, radio after {radio_s} s: {radio.get('text')}"


@check("Next wave's plan changed for the armour", gate="gate2")
def check_plan_changed(data: Round) -> tuple[bool, str]:
    first = g2(data, "first_known")
    plans = [e for e in data.of("C_PLAN") if e.get("side") == "WEST"]
    if not first or not plans:
        return False, "no plan lines"
    t0 = int(first[0]["t"])
    before = [e for e in plans if int(e["t"]) < t0]
    after = [e for e in plans if int(e["t"]) >= t0]
    ok = bool(after) and any(int(e.get("at_wanted", 0)) >= 2 for e in after)
    last_before = before[-1].get("at_wanted") if before else "none"
    return ok, f"at_wanted before {last_before}, after {[e.get('at_wanted') for e in after][:6]}, combat vehicle {[e.get('combat_vehicle') for e in after][:3]}"


def departs(data: Round) -> list[dict[str, str]]:
    return [e for e in data.of("C_WAVE") if e.get("event") == "depart"]


@check("Waves into known armour carry 2 AT launchers per tank", gate="phase3")
def check_at_launchers(data: Round) -> tuple[bool, str]:
    # Each sector's groups kit up separately, so add up the operation.
    ops: dict[tuple[str, str], list[int]] = {}
    for e in departs(data):
        if int(e.get("at_wanted", 0)) >= 2:
            row = ops.setdefault((e["side"], e["wave"]), [0, 0])
            row[0] += int(e["at_launchers"])
            row[1] = max(row[1], int(e["at_wanted"]))
    if not ops:
        return False, "no group left with armour on its plan"
    short = [r for r in ops.values() if r[0] < r[1]]
    return not short, f"{len(ops)} operations, launchers/wanted {list(ops.values())}"


@check("Affordable waves drive", gate="phase3")
def check_affordable_drive(data: Round) -> tuple[bool, str]:
    rows = []
    bad = 0
    for e in departs(data):
        shops = [s for s in data.of("C_SHOP") if s["side"] == e["side"] and s["wave"] == e["wave"]]
        free = (int(shops[-1]["cp"]) - int(shops[-1]["reserve"])) if shops else 0
        riding, walking = int(e["riding"]), int(e["walking"])
        rows.append((e["side"], e["wave"], riding, walking, free))
        if walking > riding and free >= 350 and e.get("worth_driving") == "true":
            bad += 1
    return bool(rows) and bad == 0 and any(r[2] > 0 for r in rows), f"{bad} walked while affordable and worth driving; side/wave/riding/walking/free CP {rows[:10]}"


@check("Mount-up stays within about 90 s", gate="phase3")
def check_mount_time(data: Round) -> tuple[bool, str]:
    times = [int(e["mount_s"]) for e in departs(data)]
    return bool(times) and max(times) <= 95, f"mount times {times}"


@check("No bought vehicle left unused at a muster", gate="phase3")
def check_unused(data: Round) -> tuple[bool, str]:
    unused = [e for e in data.of("C_VEH") if e.get("event") == "left_unused"]
    bought = [e for e in data.of("C_VEH") if e.get("event") == "bought"]
    return bool(bought) and not unused, f"{len(bought)} bought, {len(unused)} left unused"


@check("No vehicle makes a solo trip", gate="phase3")
def check_solo(data: Round) -> tuple[bool, str]:
    last: dict[tuple[str, str], tuple[float, float]] = {}
    solo = []
    for e in data.of("C_VTRK"):
        key = (e["side"], e["id"])
        pos = (float(e["x"]), float(e["y"]))
        if key in last and e["state"] in ("ready", "parked", "arriving"):
            if abs(pos[0] - last[key][0]) + abs(pos[1] - last[key][1]) > 100:
                solo.append((key, e["t"], e["state"]))
        if e["state"] == "moving" and e.get("wave") in (None, "-1"):
            solo.append((key, e["t"], "moving with no wave"))
        last[key] = pos
    return bool(data.of("C_VTRK")) and not solo, f"{len(data.of('C_VTRK'))} samples, {len(solo)} solo moves {solo[:5]}"


@check("Combat vehicles never lead the infantry in", gate="phase3")
def check_combat_lead(data: Round) -> tuple[bool, str]:
    rows = [e for e in data.of("C_VPOS") if e.get("role") == "combat"]
    lead = [e for e in rows if int(e["d_target"]) < 300 and int(e["d_target"]) < int(e["lead_d"]) - 50]
    inside = [e for e in rows if e.get("in_square") == "true" and int(e["d_target"]) < int(e["lead_d"])]
    return not lead and not inside, f"{len(rows)} samples, {len(lead)} ahead near the sector, {len(inside)} inside ahead of infantry"


@check("CP reserve holds on every purchase", gate="phase3")
def check_reserve(data: Round) -> tuple[bool, str]:
    buys = data.of("C_BUY")
    below = [e for e in buys if int(e["cp_after"]) < int(e["reserve"])]
    return bool(buys) and not below, f"{len(buys)} purchases, {len(below)} below reserve"


def def_events(data: Round, side: str = "WEST") -> list[dict[str, str]]:
    return [e for e in data.of("C_DEF") if e.get("side") == side]


def g4(data: Round, event: str) -> list[dict[str, str]]:
    return [e for e in data.of("G4") if e.get("event") == event]


def attack_window(data: Round, spawn: dict[str, str]) -> tuple[int, str]:
    return int(spawn["t"]), spawn["sector"]


@check("A counterattack gets a response within one tick of detection", gate="phase4")
def check_response(data: Round) -> tuple[bool, str]:
    spawns = g4(data, "spawn")
    if not spawns:
        return False, "scenario spawned no attackers"
    rows = []
    ok = True
    for s in spawns:
        t0, sector = attack_window(data, s)
        ev = [e for e in def_events(data) if e.get("sector") == sector and int(e["t"]) >= t0]
        det = next((e for e in ev if e.get("event") == "detect"), None)
        if det is None:
            rows.append((sector, "not detected"))
            ok = False
            continue
        resp = next((e for e in ev if e.get("event") == "respond" and int(e["t"]) >= int(det["t"])), None)
        if resp is None:
            rows.append((sector, "no response"))
            ok = False
            continue
        lag = int(resp["t"]) - int(det["t"])
        rows.append((sector, f"seen after {int(det['t']) - t0} s, response {lag} s after detection by {resp['group']} from {resp['from']}"))
        ok = ok and lag <= 11
    return ok, str(rows)


@check("Defenders stand down once the threat is gone", gate="phase4")
def check_standdown(data: Round) -> tuple[bool, str]:
    killed = g4(data, "killed")
    spawns = g4(data, "spawn")
    if not killed:
        return False, "scenario killed no attackers"
    rows = []
    ok = True
    for s, k in zip(spawns, killed):
        down = next((e for e in def_events(data) if e.get("event") == "stand_down" and e.get("sector") == s["sector"] and int(e["t"]) >= int(k["t"])), None)
        if down is None:
            rows.append((s["sector"], "no stand-down"))
            ok = False
        else:
            rows.append((s["sector"], f"stood down {int(down['t']) - int(k['t'])} s after the kill, why={down.get('why')}"))
            ok = ok and down.get("why") in ("clear", "lost")
    return ok, str(rows)


@check("Mustering groups turn to defend when their sector is attacked", gate="phase4")
def check_staging_abort(data: Round) -> tuple[bool, str]:
    at_staging = [s for s in g4(data, "spawn") if s.get("staging") == "true"]
    aborts = [e for e in def_events(data) if e.get("event") == "staging_abort"]
    if not at_staging:
        return True, "no attack happened at a sector with a muster running, nothing to check"
    return bool(aborts), f"{len(aborts)} staging aborts, groups {[e.get('groups') for e in aborts]}"


@check("Reserve groups are posted", gate="phase4")
def check_reserve_posted(data: Round) -> tuple[bool, str]:
    joins = [e for e in data.of("C_DEF") if e.get("event") == "reserve_join"]
    return bool(joins), f"{len(joins)} reserve postings"


@check("Player request code runs without errors and no players connected", gate="phase4")
def check_player_paths(data: Round) -> tuple[bool, str]:
    done = g4(data, "player_paths_done")
    kinds = sorted({e.get("kind") for e in data.of("C_REQ")})
    return bool(done) and not data.script_errors, f"paths done={bool(done)}, requests logged {kinds}, script errors {len(data.script_errors)}"


def smart(data: Round, behaviour: str, event: str | None = None) -> list[dict[str, str]]:
    return [e for e in data.of("C_SMART") if e.get("behaviour") == behaviour and (event is None or e.get("event") == event)]


def g6(data: Round, event: str) -> list[dict[str, str]]:
    return [e for e in data.of("G6") if e.get("event") == event]


def radio_types(data: Round) -> dict[str, int]:
    counts: dict[str, int] = {}
    for e in data.of("C_RADIO"):
        counts[e.get("type", "?")] = counts.get(e.get("type", "?"), 0) + 1
    return counts


@check("1 Weakened groups retreat and merge", gate="phase6")
def check_break(data: Round) -> tuple[bool, str]:
    retreats = smart(data, "break", "retreat")
    merges = smart(data, "break", "merge")
    moved = [int(e.get("moved", 0)) for e in merges]
    return bool(retreats) and bool(merges), f"{len(g6(data, 'break_forced'))} forced, {len(retreats)} retreats, {len(merges)} merges, men moved {moved}"


@check("2 Heavy-losses and breaking calls reach the radio", gate="phase6")
def check_radio_new(data: Round) -> tuple[bool, str]:
    types = radio_types(data)
    new = {k: types.get(k, 0) for k in ("heavy", "breaking", "cheer", "momentum", "scout", "hunt", "digin", "prepfire", "joinpush", "smoke")}
    return types.get("heavy", 0) > 0 and types.get("breaking", 0) > 0, str(new)


@check("3 Stalled groups move up to the group that broke in", gate="phase6")
def check_reinforce(data: Round) -> tuple[bool, str]:
    forced = g6(data, "reinforce_forced")
    moves = smart(data, "reinforce", "redirect")
    if not forced:
        return False, "the scenario never got two groups on foot in an assault"
    return bool(moves), f"{len(moves)} redirects: {[(e['group'], e['to_group']) for e in moves[:4]]}"


@check("4 Smoke goes out before the push", gate="phase6")
def check_smoke(data: Round) -> tuple[bool, str]:
    thrown = smart(data, "smoke", "thrown")
    screened = [e for e in thrown if e.get("known_enemy") == "true"]
    return bool(thrown), f"{len(thrown)} thrown, {len(screened)} aimed at known enemy positions"


@check("5 Prep fire lands and lifts before the infantry go in", gate="phase6")
def check_prep(data: Round) -> tuple[bool, str]:
    fired = smart(data, "prepfire", "fired")
    if not fired:
        return False, f"no fire mission; other outcomes {[e['event'] for e in smart(data, 'prepfire')][:6]}"
    rows = []
    ok = True
    for e in fired:
        assault = next((w for w in data.of("C_WAVE") if w.get("event") == "assault" and w["side"] == e["side"] and w["wave"] == e["wave"]), None)
        if assault is None:
            rows.append((e["wave"], "no assault yet"))
            continue
        gap = int(assault["t"]) - int(e["t"])
        rows.append((e["wave"], f"assault {gap} s after firing"))
        ok = ok and gap >= 25
    return ok, str(rows)


@check("6 A fast capture pushes on to a weak neighbour", gate="phase6")
def check_momentum(data: Round) -> tuple[bool, str]:
    pushes = smart(data, "momentum", "push")
    scores = g6(data, "momentum_score")
    raised = bool(scores) and int(scores[0]["after"]) > int(scores[0]["before"])
    outcomes = sorted({e["event"] for e in smart(data, "momentum")})
    detail = f"{len(pushes)} pushes, outcomes {outcomes}"
    if scores:
        detail += f", vote score {scores[0]['before']} to {scores[0]['after']} for {scores[0]['sector']}"
    return bool(pushes) and raised, detail


@check("7 A scout leaves while the wave gathers, without delaying the go", gate="phase6")
def check_scout(data: Round) -> tuple[bool, str]:
    sent = smart(data, "scout", "sent")
    waits = rally_waits(data)
    return bool(sent) and (not waits or max(waits) <= 240), f"{len(sent)} scouts, {sum(1 for e in sent if e.get('vehicle') == 'true')} by vehicle, go waits {waits}"


@check("8 A vehicle lost to something unseen draws a sweep", gate="phase6")
def check_hunt(data: Round) -> tuple[bool, str]:
    sent = smart(data, "hunt", "sent")
    return bool(sent), f"{len(g6(data, 'hunt_forced'))} forced, {len(sent)} sweeps, outcomes {sorted({e['event'] for e in smart(data, 'hunt')})}"


@check("9 Groups dig in facing the likely counterattack", gate="phase6")
def check_digin(data: Round) -> tuple[bool, str]:
    spots = smart(data, "digin", "position")
    return bool(spots), f"{len(spots)} positions, facing from {sorted({e.get('from', '?') for e in spots})}"


@check("10 Each commander picks a personality", gate="phase6")
def check_persona(data: Round) -> tuple[bool, str]:
    chosen = {e["side"]: e["name"] for e in smart(data, "personality", "chosen")}
    return set(chosen) == {"WEST", "EAST"}, str(chosen)


@check("11 A costly direction is avoided next time", gate="phase6")
def check_memory(data: Round) -> tuple[bool, str]:
    checks = g6(data, "memory_check")
    if not checks:
        return False, "scenario did not reach the memory check"
    costly = int(checks[0]["costly"])
    bearings = [int(b) for b in checks[0]["bearings"].split("/")]
    diffs = [abs(((b - costly) + 180) % 360 - 180) for b in bearings]
    return min(diffs) >= 29, f"costly bearing {costly}, new bearings {bearings}, smallest gap {min(diffs)}"


@check("12 Join-push code runs with a stand-in and no players", gate="phase6")
def check_join(data: Round) -> tuple[bool, str]:
    attached = smart(data, "joinpush", "attached")
    return bool(attached) and not data.script_errors, f"{len(attached)} groups attached to the stand-in, script errors {len(data.script_errors)}"


def section(title: str) -> None:
    print(f"\n== {title} ==")


def print_header(data: Round) -> None:
    section("Round")
    print(f"Log: {data.path}")
    if data.start is None:
        print("No SWL|START line: the mission did not start, or the observer did not run.")
        return
    print(
        f"Mission {data.start.get('mission')} on {data.start.get('world')}, "
        f"dedicated={data.start.get('dedicated')}, game build {data.start.get('build')}"
    )
    print(f"Observed for {fmt_time(data.last_t)} of mission time, {len(data.ticks)} ticks.")
    if data.round_end:
        print(f"Round ended at {fmt_time(int(data.round_end.get('t', 0)))}, winner {data.round_end.get('winner')}.")
    else:
        print("Round end was not reached in this log.")
    if data.extra_starts:
        print(f"The mission restarted {data.extra_starts} time(s). Only the first round is analysed.")
    players = max((int(t.fields.get("players", 0)) for t in data.ticks), default=0)
    print(f"Most players connected at any tick: {players}")


def print_groups_over_time(data: Round) -> None:
    section("Groups per side over time")
    print(f"{'time':>7} {'W grp':>6} {'E grp':>6} {'W men':>6} {'E men':>6} {'GUER':>6} {'fps':>4}  targets (W / E)")
    if not data.ticks:
        return
    step = max(1, round(300 / max(1, data.ticks[1].t - data.ticks[0].t))) if len(data.ticks) > 1 else 1
    picked = data.ticks[::step]
    if picked[-1] is not data.ticks[-1]:
        picked.append(data.ticks[-1])
    for tick in picked:
        f = tick.fields
        print(
            f"{fmt_time(tick.t):>7} {f.get('west_groups', '?'):>6} {f.get('east_groups', '?'):>6} "
            f"{f.get('west_units', '?'):>6} {f.get('east_units', '?'):>6} {f.get('guer_units', '?'):>6} "
            f"{f.get('fps', '?'):>4}  {f.get('west_target', '?')} / {f.get('east_target', '?')}"
        )


def print_captures(data: Round) -> None:
    section("Sector captures")
    if not data.captures:
        print("None.")
    for c in data.captures:
        print(f"{fmt_time(c.t):>7}  {c.sector}: {c.old} -> {c.new}{'  (BASE)' if c.base else ''}")
    final = [f"{name}={s.owner}" for name, s in data.sectors.items()]
    if final:
        owners = dict(s.split("=", 1) for s in final)
        for c in data.captures:
            owners[c.sector] = c.new
        print("Final ownership: " + ", ".join(f"{k}={v}" for k, v in owners.items()))


def print_targets(data: Round) -> None:
    section("Vote targets and arrivals")
    if not data.targets:
        print("None.")
        return
    for side in SIDES:
        events = [t for t in data.targets if t.side == side]
        for index, target in enumerate(events):
            if target.sector == "-" or target.sector not in data.sectors:
                continue
            end = events[index + 1].t if index + 1 < len(events) else data.last_t
            sector = data.sectors[target.sector]
            groups = [g for g in data.groups_on(side) if g.is_warlord]
            first_arrival = {}
            for group in groups:
                for s in group.samples:
                    if target.t <= s.t <= end and math.hypot(s.x - sector.x, s.y - sector.y) <= sector.radius + 50:
                        first_arrival[group.id] = s.t
                        break
            earliest = min(first_arrival.values()) - target.t if first_arrival else None
            arrived = f"first after {fmt_time(earliest)}" if earliest is not None else "none arrived"
            print(
                f"{side}: {target.sector} chosen {fmt_time(target.t)}, held until {fmt_time(end)}. "
                f"Warlord groups inside the sector: {len(first_arrival)}/{len(groups)}, {arrived}"
            )


def print_idle(data: Round) -> None:
    section(f"Idle groups (stayed within {IDLE_RADIUS_M:.0f} m for {IDLE_MIN_SECONDS // 60}+ minutes)")
    per_group = []
    for group in data.groups.values():
        if not group.is_ai or len(group.samples) < 2:
            continue
        per_group.append((group, idle_stretches(group)))

    idle = [(g, s) for g, s in per_group if s]
    print(f"{len(idle)} of {len(per_group)} AI groups went idle at least once.")
    for side in SIDES:
        count = sum(1 for g, _ in idle if g.side == side)
        total = sum(1 for g, _ in per_group if g.side == side)
        print(f"  {side}: {count}/{total}")

    rows = []
    for group, stretches in idle:
        longest = max(stretches, key=lambda s: s.seconds)
        rows.append((longest.seconds, group, longest, sum(s.seconds for s in stretches), len(stretches)))
    rows.sort(key=lambda r: r[0], reverse=True)

    if rows:
        print(f"\n{'longest':>8} {'total':>7} {'n':>3}  {'group':<14} {'side':<5} {'in combat':>9}  where")
        for seconds, group, longest, total, count in rows:
            print(
                f"{fmt_time(seconds):>8} {fmt_time(total):>7} {count:>3}  {group.name:<14} {group.side:<5} "
                f"{longest.combat_fraction * 100:>8.0f}%  {data.locate(longest.x, longest.y)} "
                f"(from {fmt_time(longest.start)})"
            )

    where: dict[str, int] = {}
    for _, stretches in idle:
        for stretch in stretches:
            place = data.locate(stretch.x, stretch.y)
            if place.startswith("open ground"):
                place = "open ground"
            where[place] = where.get(place, 0) + 1
    if where:
        print("\nIdle stretches by place: " + ", ".join(f"{k}: {v}" for k, v in sorted(where.items(), key=lambda i: -i[1])))


def print_commander(data: Round) -> None:
    if not data.of("C_TICK"):
        return
    section("Commander")
    for side in SIDES:
        waves = [e for e in data.of("C_WAVE") if e.get("side") == side]
        gos = [e for e in waves if e.get("event") == "assault"]
        resolved = {}
        for e in waves:
            if e.get("event") == "resolved":
                resolved[e.get("result")] = resolved.get(e.get("result"), 0) + 1
        print(f"{side}: {len(gos)} assaults, operations ended {resolved}, assaults repelled {sum(1 for e in waves if e.get('event') == 'push_over')}")
    ticks = [float(e["avg_ms"]) for e in data.of("C_TICK")]
    print(f"Tick cost: mean {sum(ticks) / len(ticks):.2f} ms, max {max(ticks):.2f} ms over {len(ticks)} reports")
    print(f"Idle group-minutes per 10-minute window: {raw_idle_by_window(data)}")
    print(f"Vanilla baseline:                        {BASELINE_IDLE_BY_10_MIN}")
    print(f"Guard restores: {len(data.of('C_GUARD'))}, watchdog actions: {len(data.of('C_WD'))}")


def print_jumps(data: Round) -> None:
    section(f"Fast travel (on-foot jumps over {FT_JUMP_M:.0f} m between samples)")
    all_jumps = [(g, j) for g in data.groups.values() for j in jumps(data, g)]
    travel = [(g, j) for g, j in all_jumps if j.kind == "fast_travel"]
    returns = [(g, j) for g, j in all_jumps if j.kind == "base_return"]
    print(f"Fast travels: {len(travel)} by {len({g.id for g, _ in travel})} groups.")
    print(f"Jumps back to own base (respawn or fast travel home): {len(returns)}.")
    for group, jump in travel[:40]:
        print(
            f"  {fmt_time(jump.t_to):>7} {group.side:<5} {group.name:<14} {jump.metres:>6.0f} m "
            f"to {data.locate(jump.x_to, jump.y_to)}"
        )
    if len(travel) > 40:
        print(f"  ... and {len(travel) - 40} more")


def print_errors(data: Round) -> None:
    section("Script errors in the RPT")
    if not data.script_errors:
        print("None.")
    for error in sorted(data.script_errors, key=lambda e: -e.count):
        print(f"{error.count:>5}x {error.detail}  [{error.file}]")
    if data.warnings:
        print("\nEngine warning messages (not counted as script errors):")
        for text, count in sorted(data.warnings.items(), key=lambda i: -i[1]):
            print(f"{count:>5}x {text[:200]}")


def run_checks(data: Round, gate: str | None) -> bool:
    section("Checks")
    all_passed = True
    for name, check_gate, fn in CHECKS:
        if check_gate is not None and check_gate != gate:
            continue
        try:
            passed, detail = fn(data)
        except Exception as exc:  # A broken check must fail visibly, not stop the report.
            passed, detail = False, f"check raised {type(exc).__name__}: {exc}"
        all_passed = all_passed and passed
        print(f"[{'PASS' if passed else 'FAIL'}] {name}: {detail}")
    return all_passed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("log", type=Path, help="Path to the server RPT")
    parser.add_argument("--gate", help="Also run the checks for this gate or scenario, e.g. gate0, phase1")
    args = parser.parse_args()

    data = parse_log(args.log)
    print_header(data)
    if data.start is not None:
        print_groups_over_time(data)
        print_captures(data)
        print_targets(data)
        print_idle(data)
        print_commander(data)
        print_jumps(data)
    print_errors(data)
    return 0 if run_checks(data, args.gate) else 1


if __name__ == "__main__":
    sys.exit(main())
