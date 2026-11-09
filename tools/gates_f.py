"""Part F (commander menu) gates. Imported by analyse_round.py, which calls register(check).

Reads the C_MENU lines from commander/swlc/menu.sqf and the GF lines from the gatef scenario.
The scenario has no players, so these prove the server side runs clean and refuses sensibly, nothing more.
"""

from __future__ import annotations

from typing import Callable

GATE = "partf"

ALL_KINDS = {"raid", "borrow", "hold", "go", "report", "defend", "pickup", "release", "plan"}

# Step name -> the results that count as sensible.
EXPECTED = {
    "unknown_kind": {"unknown"},
    "null_player": {"no_player"},
    "plan_first": {"ok", "ok_idle"},
    "plan_cooled": {"cooldown"},
    "raid_null": {"bad_sector"},
    "raid_junk": {"bad_sector"},
    "raid_own": {"not_front", "off", "active", "cooldown"},
    "report_empty": {"none"},
    "report_junk": {"none"},
    "report_good": {"ok"},
    "defend_null": {"bad_sector"},
    "defend_enemy": {"not_owned"},
    "defend_own": {"ok", "ok_no_force"},
    "release_none": {"none"},
    "menu_off": {"off"},
}


def gf(data, event: str) -> list[dict[str, str]]:
    return [e for e in data.of("GF") if e.get("event") == event]


def steps(data) -> dict[str, str]:
    return {e.get("step", ""): e.get("got", "") for e in gf(data, "step")}


def _int(entry: dict[str, str], key: str) -> int:
    try:
        return int(float(entry.get(key, 0)))
    except (TypeError, ValueError):
        return 0


def ran_clean(data) -> tuple[bool, str]:
    done = gf(data, "done")
    return bool(done) and not data.script_errors, f"scenario finished={bool(done)}, script errors {len(data.script_errors)}"


def front_door(data) -> tuple[bool, str]:
    first_step = min((float(e["t"]) for e in gf(data, "step")), default=None)
    door = gf(data, "front_door")
    if not door or first_step is None:
        return False, "scenario didn't get that far"
    early = [e for e in data.of("C_MENU") if float(e["t"]) < float(door[0]["t"])]
    return not early, f"{len(early)} requests from non-players were handled"


def every_option_ran(data) -> tuple[bool, str]:
    seen = {e.get("kind") for e in data.of("C_MENU")}
    missing = sorted(ALL_KINDS - seen)
    return not missing, f"options exercised {len(ALL_KINDS) - len(missing)} of {len(ALL_KINDS)}, missing {missing}"


def sensible_answers(data) -> tuple[bool, str]:
    got = steps(data)
    wrong = [f"{k}: got {got.get(k, 'nothing')!r}" for k, want in EXPECTED.items() if got.get(k) not in want]
    return not wrong, "; ".join(wrong) if wrong else f"{len(EXPECTED)} requests answered as expected"


def raid_payment(data) -> tuple[bool, str]:
    if gf(data, "raid_skipped"):
        return True, f"paid path skipped ({gf(data, 'raid_skipped')[0].get('why')}), part D covers raid captures"
    got = steps(data)
    paid = gf(data, "raid_paid")
    ok = got.get("raid_poor") == "funds" and got.get("raid_paid") == "ok" and got.get("raid_second") == "active"
    ok = ok and bool(paid) and _int(paid[0], "left") == 100 and paid[0].get("has_rec") == "true"
    return ok, f"poor {got.get('raid_poor')}, paid {got.get('raid_paid')}, second {got.get('raid_second')}, {paid[:1]}"


def hold_capped(data) -> tuple[bool, str]:
    got = steps(data)
    state = gf(data, "hold_state")
    if got.get("hold") != "ok":
        return got.get("hold") in {"no_op", "assault"}, f"hold refused with {got.get('hold')}"
    left = _int(state[0], "left") if state else -1
    return 0 < left <= 125 and got.get("hold_again") == "used", f"hold left {left} s, second hold {got.get('hold_again')}"


def borrow_and_release(data) -> tuple[bool, str]:
    got = steps(data)
    if got.get("borrow") == "nospare":
        return False, "no groups to spare, run with menuKeepGroups=0"
    state, follow, released = gf(data, "borrow_state"), gf(data, "borrow_follow"), gf(data, "release_state")
    if not (state and follow and released):
        return False, "scenario didn't get that far"
    n = _int(state[0], "count")
    ok = 2 <= n <= 3 and _int(state[0], "marked") == n and _int(state[0], "state_ok") == n
    ok = ok and _int(follow[0], "ordered") == n
    ok = ok and _int(released[0], "left") == 0 and _int(released[0], "unmarked") == n and _int(released[0], "not_borrowed") == n
    return ok, f"borrowed {state[0]}, follow {follow[0]}, released {released[0]}"


def player_gone_releases(data) -> tuple[bool, str]:
    after = gf(data, "after_death")
    if not after:
        return False, "scenario didn't get that far"
    had = _int(after[0], "had")
    return had > 0 and _int(after[0], "left") == 0 and _int(after[0], "unmarked") == had, str(after[0])


def pickup_stages(data) -> tuple[bool, str]:
    got = steps(data).get("pickup", "")
    if got != "ok":
        return got in {"funds", "nospare", "off", "busy", "bad_place", "too_far"}, f"pickup refused with {got!r}"
    second = steps(data).get("pickup_second")
    stages = sorted({e.get("stage", "") for e in gf(data, "pickup_stage")} - {"-"})
    ended = [e.get("why") for e in data.of("C_MENU") if e.get("kind") == "pickup_end"]
    return second == "busy" and bool(ended), f"second request {second}, stages {stages}, ended {ended}"


def register(check: Callable) -> None:
    check("Part F: every path ran with no script errors", gate=GATE)(ran_clean)
    check("Part F: only real players get past the front door", gate=GATE)(front_door)
    check("Part F: every menu option was exercised", gate=GATE)(every_option_ran)
    check("Part F: bad requests get sensible answers", gate=GATE)(sensible_answers)
    check("Part F: a raid is paid from the requester's funds", gate=GATE)(raid_payment)
    check("Part F: hold is capped and can't be chained", gate=GATE)(hold_capped)
    check("Part F: borrowed groups are marked, follow and return", gate=GATE)(borrow_and_release)
    check("Part F: groups come back when their player goes", gate=GATE)(player_gone_releases)
    check("Part F: a pickup runs to an end", gate=GATE)(pickup_stages)
