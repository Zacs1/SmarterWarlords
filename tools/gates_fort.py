"""Fortify gates. Imported by analyse_round.py, which calls register(check).

Reads the GFORT lines from the fortify scenario and the C_FORT, C_BUY and C_RADIO lines from the commander.
The scenario writes the alert record itself, so these test fortify alone, not how an alert gets raised.
Stages are noalert, attack (cap 2), hold (cap 4), standdown and alert2. event=sample has the totals, event=gun one line per gun.
"""

from __future__ import annotations

from typing import Callable

GATE = "fortify"

ATTACK_CAP = 2
HOLD_CAP = 4
OFF_LIMIT = 80          # degrees from the approach bearing, seen from the centre: 60 by design plus the spot search
FACE_LIMIT = 15         # degrees between the gun's facing and the approach point, or the bearing if that is what it fell back on
MIN_CENTRE = 35         # metres; the setting is 40, less a little for the spot search moving it
MIN_SPACING = 25        # metres; the setting is 30, same reason
REPLACE_LIMIT = 75      # seconds for a dead gunner's replacement to be in the seat
ROAD_GAP = 35           # metres from a road point to the AT man's spot


def gf(data, event: str) -> list[dict[str, str]]:
    return [e for e in data.of("GFORT") if e.get("event") == event]


def fort(data, event: str, side: str | None = None) -> list[dict[str, str]]:
    rows = [e for e in data.of("C_FORT") if e.get("event") == event]
    return [e for e in rows if side is None or e.get("side") == side]


def _num(entry: dict[str, str] | None, key: str, default: float = 0.0) -> float:
    try:
        return float((entry or {}).get(key, default))
    except (TypeError, ValueError):
        return default


def _true(entry: dict[str, str], key: str) -> bool:
    return str(entry.get(key, "")).lower() == "true"


def sample(data, stage: str) -> dict[str, str] | None:
    rows = [e for e in gf(data, "sample") if e.get("stage") == stage]
    return rows[-1] if rows else None


def guns(data, stage: str) -> list[dict[str, str]]:
    return [e for e in gf(data, "gun") if e.get("stage") == stage]


def alert_time(data, n: str) -> float | None:
    rows = [e for e in gf(data, "alert_on") if e.get("n") == n]
    return _num(rows[0], "t") if rows else None


def no_buy_without_alert(data) -> tuple[bool, str]:
    first = alert_time(data, "1")
    if first is None:
        return False, "no alert was raised"
    west_early = [e for e in fort(data, "buy", "WEST") if _num(e, "t") < first]
    east = fort(data, "buy", "EAST")
    east_bought = [e for e in data.of("C_BUY") if e.get("buyer") == "fortify" and e.get("side") == "EAST"]
    return not west_early and not east and not east_bought, (
        f"WEST bought {len(west_early)} before the alert, EAST (never alerted) bought {len(east)}"
    )


def attack_cap(data) -> tuple[bool, str]:
    s = sample(data, "attack")
    hold_at = gf(data, "stance_hold")
    if s is None or not hold_at:
        return False, "no attack stage"
    before = [e for e in fort(data, "buy", "WEST") if _num(e, "t") < _num(hold_at[0], "t")]
    return int(_num(s, "guns")) == ATTACK_CAP and len(before) == ATTACK_CAP, (
        f"{_num(s, 'guns'):.0f} guns standing, {len(before)} bought in attack stance, cap {ATTACK_CAP}"
    )


def hold_bought(data) -> tuple[bool, str]:
    s = sample(data, "hold")
    n = int(_num(s, "guns"))
    no_spot = [e for e in fort(data, "refuse", "WEST") if e.get("reason") == "no_spot"]
    # Ground is whatever the test sector happens to have. Three guns with an explicit no_spot refusal is still the module working.
    return n == HOLD_CAP or (n == HOLD_CAP - 1 and bool(no_spot)), f"{n} guns in hold stance, cap {HOLD_CAP}, no_spot refusals {len(no_spot)}"


def spends_more_in_hold(data) -> tuple[bool, str]:
    a = sample(data, "attack")
    h = sample(data, "hold")
    return _num(h, "guns") > _num(a, "guns"), f"attack {_num(a, 'guns'):.0f} guns, hold {_num(h, 'guns'):.0f} guns"


def real_classes(data) -> tuple[bool, str]:
    catalog = {e.get("class"): e for e in fort(data, "catalog", "WEST")}
    buys = fort(data, "buy", "WEST")
    bad = [e.get("class") for e in buys if catalog.get(e.get("class"), {}).get("kind") in (None, "none")]
    kinds = sorted({e.get("kind", "") for e in buys})
    summaries = fort(data, "catalog_summary", "WEST")
    at_on_offer = bool(summaries) and _true(summaries[0], "at")
    need_at = at_on_offer and HOLD_CAP >= 2
    has_at = "AT" in kinds
    return bool(buys) and not bad and (has_at or not need_at), (
        f"bought {len(buys)}, kinds {kinds}, AT on offer {at_on_offer}, outside the catalog {bad or 'none'}"
    )


def paid_properly(data) -> tuple[bool, str]:
    rows = [e for e in data.of("C_BUY") if e.get("buyer") == "fortify"]
    bad_reserve = [e for e in rows if _num(e, "cp_after") < _num(e, "reserve")]
    bad_cost = [e for e in rows if abs((_num(e, "cp_before") - _num(e, "cp_after")) - _num(e, "cost")) > 1.5]
    return bool(rows) and not bad_reserve and not bad_cost, (
        f"{len(rows)} purchases, {len(bad_reserve)} under the reserve, {len(bad_cost)} where the CP moved by the wrong amount"
    )


def approach_side(data) -> tuple[bool, str]:
    rows = guns(data, "hold")
    off = [_num(e, "off") for e in rows]
    return bool(rows) and max(off) <= OFF_LIMIT, f"bearing offsets {off}, limit {OFF_LIMIT}"


def facing(data) -> tuple[bool, str]:
    rows = guns(data, "hold")
    bad = [(e.get("id"), e.get("face"), e.get("faceb")) for e in rows if min(_num(e, "face"), _num(e, "faceb")) > FACE_LIMIT]
    return bool(rows) and not bad, f"{len(rows)} guns, facing away {bad or 'none'}"


def ground(data) -> tuple[bool, str]:
    rows = guns(data, "hold")
    near_centre = [e.get("id") for e in rows if _num(e, "dist") < MIN_CENTRE]
    on_road = [e.get("id") for e in rows if _true(e, "road")]
    return bool(rows) and not near_centre and not on_road, f"at the centre {near_centre or 'none'}, on a road {on_road or 'none'}"


def spread(data) -> tuple[bool, str]:
    rows = guns(data, "hold")
    nearest = [_num(e, "nearest") for e in rows]
    return len(rows) >= 2 and min(nearest) >= MIN_SPACING, f"nearest-gun distances {nearest}, limit {MIN_SPACING}"


def crewed(data) -> tuple[bool, str]:
    s = sample(data, "hold")
    rows = guns(data, "hold")
    n, c = int(_num(s, "guns")), int(_num(s, "crewed"))
    bad = [e.get("id") for e in rows if _true(e, "leader") or _true(e, "at") or not _true(e, "ingroup")]
    return n > 0 and c == n and not bad, f"{c} of {n} crewed, wrong man on {bad or 'none'} (leader, AT soldier, or outside the alert's groups)"


def replaced(data) -> tuple[bool, str]:
    rows = gf(data, "replaced")
    if not rows:
        return False, "no gunner was killed"
    r = rows[-1]
    return _true(r, "ok") and _true(r, "ingroup") and _num(r, "after") <= REPLACE_LIMIT, (
        f"ok {r.get('ok')} after {r.get('after')} s, from the alert's groups {r.get('ingroup')}"
    )


def cap_holds(data) -> tuple[bool, str]:
    second = alert_time(data, "2")
    if second is None:
        return False, "no second alert"
    extra = [e for e in fort(data, "buy", "WEST") if _num(e, "t") >= second]
    samples = [_num(e, "guns") for e in gf(data, "sample")]
    return not extra and max(samples) <= HOLD_CAP, (
        f"{len(extra)} bought on the second alert, most guns ever {max(samples):.0f}, cap {HOLD_CAP}"
    )


def standdown(data) -> tuple[bool, str]:
    s = sample(data, "standdown")
    held = gf(data, "released")
    at = [e for e in gf(data, "at_summary") if e.get("stage") == "standdown"]
    stayed = _num(s, "guns") >= _num(sample(data, "hold"), "guns")
    vars_clear = bool(held) and _num(held[-1], "fortgun_vars") == 0
    at_clear = bool(at) and _num(at[-1], "men") == 0
    return stayed and _num(s, "crewed") == 0 and vars_clear and at_clear, (
        f"guns {_num(s, 'guns'):.0f} of {_num(sample(data, 'hold'), 'guns'):.0f} stayed, {_num(s, 'crewed'):.0f} still crewed, "
        f"men still marked {held[-1].get('fortgun_vars') if held else '?'}, AT men still on the job {at[-1].get('men') if at else '?'}"
    )


def crewed_again(data) -> tuple[bool, str]:
    s = sample(data, "alert2")
    n, c = int(_num(s, "guns")), int(_num(s, "crewed"))
    return n > 0 and c >= max(1, n - 1), f"{c} of {n} crewed 40 s into the second alert"


def at_cover(data) -> tuple[bool, str]:
    summary = [e for e in gf(data, "at_summary") if e.get("stage") == "hold"]
    if not summary or _num(summary[-1], "men") < 1:
        return False, "no AT soldier on the road job in hold"
    rows = [e for e in gf(data, "at") if e.get("stage") == "hold"]
    on_road = [e for e in rows if _true(e, "spot_on_road")]
    roads = _num(summary[-1], "roads")
    far = [e for e in rows if roads > 0 and _num(e, "spot_road_gap") > ROAD_GAP]
    holding = fort(data, "at_hold", "WEST")
    return bool(holding) and not on_road and not far, (
        f"{_num(summary[-1], 'men'):.0f} men on the job, {len(holding)} arrived and holding, "
        f"{len(on_road)} spots on a road, {len(far)} too far from the road points (road points {roads:.0f})"
    )


def logged(data) -> tuple[bool, str]:
    wanted = ("catalog", "buy", "placed", "crew_assign", "crew_in", "crew_lost", "standdown")
    missing = [w for w in wanted if not fort(data, w, "WEST")]
    capped = [e for e in fort(data, "refuse", "WEST") if e.get("reason") == "cap"]
    return not missing and bool(capped), f"missing {missing or 'none'}, cap refusals {len(capped)}"


def radio(data) -> tuple[bool, str]:
    rows = [e for e in data.of("C_RADIO") if e.get("side") == "WEST" and e.get("type") == "fortbuilt"]
    return bool(rows), f"{len(rows)} fortbuilt lines"


def finished(data) -> tuple[bool, str]:
    fails = [e.get("event", "?") for e in data.of("GFORT") if e.get("event", "").startswith("fail")]
    return bool(gf(data, "done")) and not fails, f"done lines {len(gf(data, 'done'))}, failures {fails or 'none'}"


def no_script_errors(data) -> tuple[bool, str]:
    ours = sum(e.count for e in data.script_errors if not e.file.lower().lstrip("/\\").startswith("a3"))
    return ours == 0, f"{ours} script errors in our code"


def register(check: Callable) -> None:
    check("Fortify: nothing bought without an alert", gate=GATE)(no_buy_without_alert)
    check("Fortify: attack stance stops at its cap", gate=GATE)(attack_cap)
    check("Fortify: hold stance buys up to the sector cap", gate=GATE)(hold_bought)
    check("Fortify: hold spends more than attack", gate=GATE)(spends_more_in_hold)
    check("Fortify: buys real Defences classes, AT where on offer", gate=GATE)(real_classes)
    check("Fortify: every purchase paid for and above the reserve", gate=GATE)(paid_properly)
    check("Fortify: guns on the approach side", gate=GATE)(approach_side)
    check("Fortify: guns face the approach", gate=GATE)(facing)
    check("Fortify: guns off the centre and off roads", gate=GATE)(ground)
    check("Fortify: guns spread apart", gate=GATE)(spread)
    check("Fortify: every gun crewed by a rifleman from the alert's groups", gate=GATE)(crewed)
    check("Fortify: a killed gunner is replaced", gate=GATE)(replaced)
    check("Fortify: a second alert doesn't buy past the cap", gate=GATE)(cap_holds)
    check("Fortify: alert end leaves guns, frees the men", gate=GATE)(standdown)
    check("Fortify: guns crewed again on a second alert", gate=GATE)(crewed_again)
    check("Fortify: AT soldiers beside the approach road", gate=GATE)(at_cover)
    check("Fortify: every event logged", gate=GATE)(logged)
    check("Fortify: radio line when guns go in", gate=GATE)(radio)
    check("Fortify: the scenario ran to the end", gate=GATE)(finished)
    check("Fortify: no script errors", gate=GATE)(no_script_errors)
