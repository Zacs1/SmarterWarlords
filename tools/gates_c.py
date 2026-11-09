#!/usr/bin/env python3
"""Part C checks (economy and capabilities) and the soak comparison against a vanilla baseline.

    python tools/gates_c.py <rpt> --gate gatec     scenario: income curve and supply chain
    python tools/gates_c.py <rpt> --gate soak      one soak round: snapshots, forts, payouts
    python tools/gates_c.py --compare base1.rpt base2.rpt --variant var1.rpt var2.rpt

Checks follow tools/analyse_round.py: each takes a Round and returns (passed, detail).
Exit code is 0 only if every check that ran passes.
"""

from __future__ import annotations

import argparse
import statistics
import sys
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).parent))

from swl_log import Round, fmt_time, parse_log  # noqa: E402

CheckFn = Callable[[Round], tuple[bool, str]]
CHECKS: list[tuple[str, str | None, CheckFn]] = []

FINAL_FIGHT_MIN_S = 120  # below this the final base fight counts as a walkover
LEAD_WIN_RATE_MIN = 0.6  # a clear leader should win at least this share of rounds


def check(name: str, gate: str | None = None) -> Callable[[CheckFn], CheckFn]:
    def wrap(fn: CheckFn) -> CheckFn:
        CHECKS.append((name, gate, fn))
        return fn

    return wrap


def econ(data: Round, event: str, side: str | None = None) -> list[dict[str, str]]:
    rows = [e for e in data.of("C_ECON") if e.get("event") == event]
    return [e for e in rows if e.get("side") == side] if side else rows


def scenario(data: Round, event: str) -> list[dict[str, str]]:
    return [e for e in data.of("GC") if e.get("event") == event]


def numbers(text: str) -> list[float]:
    return [] if text in ("", "-") else [float(v) for v in text.split(",")]


# Scenario checks


@check("gatec_finished", gate="gatec")
def gatec_finished(data: Round) -> tuple[bool, str]:
    done = scenario(data, "done")
    skipped = scenario(data, "skip")
    return bool(done) and not skipped, f"done={len(done)}, skipped={[e.get('reason') for e in skipped]}"


@check("income_flat_base", gate="gatec")
def income_flat_base(data: Round) -> tuple[bool, str]:
    curve = scenario(data, "curve")
    if not curve:
        return False, "no curve lines"
    bases = {e["base"] for e in curve}
    return len(bases) == 1, f"base value at every step: {sorted(bases)}"


@check("income_diminishes", gate="gatec")
def income_diminishes(data: Round) -> tuple[bool, str]:
    curve = sorted(scenario(data, "curve"), key=lambda e: int(e["n"]))
    if len(curve) < 2:
        return False, f"only {len(curve)} steps"
    income = [float(e["income"]) for e in curve]
    steps = [b - a for a, b in zip(income, income[1:])]
    # Later sectors must add less than their full value, and income must never fall.
    last = curve[-1]
    paid, full = sum(numbers(last["values"])), sum(numbers(last["originals"]))
    return all(s >= 0 for s in steps) and paid < full, f"income {income}, paid {paid:g} of {full:g} full value"


def chain(data: Round, stage: str) -> dict[str, str] | None:
    rows = [e for e in scenario(data, "chain") if e.get("stage") == stage]
    return rows[-1] if rows else None


@check("caps_off_when_cut", gate="gatec")
def caps_off_when_cut(data: Round) -> tuple[bool, str]:
    before, cut = chain(data, "before"), chain(data, "cut")
    if not before or not cut:
        return False, "no chain lines"
    unique = [u for u in before["unique"].split("+") if u]
    caps_before, caps_cut = before["caps"].split("+"), cut["caps"].split("+")
    gone = all(u in caps_before and u not in caps_cut for u in unique)
    return (
        cut["special"] == "none" and before["special"] != "none" and bool(unique) and gone,
        f"cut {cut['cut']}, stranded {cut['stranded']}, unique {unique}, "
        f"caps {before['caps']} -> {cut['caps']}, special {before['special']} -> {cut['special']}",
    )


@check("caps_back_when_restored", gate="gatec")
def caps_back_when_restored(data: Round) -> tuple[bool, str]:
    before, restored = chain(data, "before"), chain(data, "restored")
    if not before or not restored:
        return False, "no chain lines"
    return (
        restored["caps"] == before["caps"] and restored["special"] == before["special"],
        f"caps {before['caps']} -> {restored['caps']}, special {restored['special']}",
    )


@check("econ_caps_logged", gate="gatec")
def econ_caps_logged(data: Round) -> tuple[bool, str]:
    rows = econ(data, "caps")
    cut = [e for e in rows if e.get("cut") not in (None, "-")]
    return bool(cut), f"{len(rows)} changes, {len(cut)} with a sector cut off"


# Soak checks


@check("fortress_built", gate="soak")
def fortress_built(data: Round) -> tuple[bool, str]:
    rows = econ(data, "fortress")
    built = {e["side"]: int(e["statics"]) for e in rows}
    return set(built) == {"WEST", "EAST"} and all(built.values()), str(built)


@check("snapshots_present", gate="soak")
def snapshots_present(data: Round) -> tuple[bool, str]:
    rows = econ(data, "snapshot")
    return len(rows) >= 4, f"{len(rows)} snapshots"


@check("combat_income_paid", gate="soak")
def combat_income_paid(data: Round) -> tuple[bool, str]:
    kills = econ(data, "kill")
    wipes = [e for e in kills if e.get("wipe") == "1"]
    return bool(kills), f"{len(kills)} kills paid, {len(wipes)} squad wipes"


@check("sectors_dug_in", gate="soak")
def sectors_dug_in(data: Round) -> tuple[bool, str]:
    forts = econ(data, "fort")
    failed = econ(data, "fortfailed")
    return bool(forts), f"{len(forts)} built, {len(failed)} found no ground"


@check("trailing_side_afloat", gate="soak")
def trailing_side_afloat(data: Round) -> tuple[bool, str]:
    late = trailing_late(data)
    if late is None:
        return False, "no snapshots in the last third of the round"
    return late["cp"] > 0 and (late["at"] > 0 or late["vehicles"] > 0), str(late)


@check("final_fight_not_walkover", gate="soak")
def final_fight_not_walkover(data: Round) -> tuple[bool, str]:
    length = final_fight_seconds(data)
    if length is None:
        return False, "round did not end on a base fight"
    return length >= FINAL_FIGHT_MIN_S, f"{fmt_time(length)} (minimum {fmt_time(FINAL_FIGHT_MIN_S)})"


# Soak measurements. These also work on a vanilla baseline, except the snapshot-based ones.


def winner(data: Round) -> str | None:
    if data.round_end is None:
        return None
    w = data.round_end.get("winner")
    return w if w in ("WEST", "EAST") else None


def round_end_t(data: Round) -> int:
    return int(data.round_end.get("t", data.last_t)) if data.round_end else data.last_t


def owners_at(data: Round, t: int) -> dict[str, str]:
    owners = {name: s.owner for name, s in data.sectors.items()}
    for c in data.captures:
        if c.t <= t:
            owners[c.sector] = c.new
    return owners


def sector_counts(data: Round, t: int) -> dict[str, int]:
    owners = list(owners_at(data, t).values())
    return {s: owners.count(s) for s in ("WEST", "EAST")}


def final_fight_seconds(data: Round) -> int | None:
    """From the winner's last vote on the loser's base to the end of the round."""
    w = winner(data)
    if w is None:
        return None
    losing_base = data.base_of("EAST" if w == "WEST" else "WEST")
    if losing_base is None:
        return None
    on_base = [t.t for t in data.targets if t.side == w and t.sector == losing_base.name]
    return round_end_t(data) - max(on_base) if on_base else None


def leader_at_two_thirds(data: Round) -> str | None:
    counts = sector_counts(data, round_end_t(data) * 2 // 3)
    if counts["WEST"] == counts["EAST"]:
        return None
    return "WEST" if counts["WEST"] > counts["EAST"] else "EAST"


def trailing_late(data: Round) -> dict[str, float] | None:
    """Trailing side's average CP, AT launchers and crewed vehicles in the last third of the round."""
    start = round_end_t(data) * 2 // 3
    rows = [e for e in econ(data, "snapshot") if int(e["t"]) >= start]
    picked: list[dict[str, str]] = []
    for t in sorted({int(e["t"]) for e in rows}):
        counts = sector_counts(data, t)
        if counts["WEST"] == counts["EAST"]:
            continue
        side = "EAST" if counts["WEST"] > counts["EAST"] else "WEST"
        picked += [e for e in rows if int(e["t"]) == t and e["side"] == side]
    if not picked:
        return None
    return {k: round(statistics.fmean(float(e[k]) for e in picked), 1) for k in ("cp", "at", "vehicles")}


def summarise(path: Path) -> dict[str, object]:
    data = parse_log(path)
    return {
        "path": path.name,
        "length": round_end_t(data),
        "winner": winner(data),
        "leader": leader_at_two_thirds(data),
        "final_fight": final_fight_seconds(data),
        "trailing": trailing_late(data),
        "buys_late": sum(1 for e in data.of("C_BUY") if int(e["t"]) >= round_end_t(data) * 2 // 3),
    }


def print_group(label: str, rows: list[dict[str, object]]) -> dict[str, float | None]:
    print(f"\n{label}")
    for r in rows:
        print(
            f"  {r['path']}: {fmt_time(int(r['length']))}, winner {r['winner']}, leader at 2/3 {r['leader']}, "
            f"final fight {fmt_time(r['final_fight']) if r['final_fight'] is not None else 'n/a'}, "
            f"trailing late {r['trailing'] or 'n/a'}, late buys {r['buys_late']}"
        )
    fights = [r["final_fight"] for r in rows if r["final_fight"] is not None]
    led = [r for r in rows if r["leader"] and r["winner"]]
    held = [r for r in led if r["leader"] == r["winner"]]
    lengths = [r["length"] for r in rows]
    trailing = [r["trailing"] for r in rows if r["trailing"]]
    summary = {
        "rounds": len(rows),
        "median_length": statistics.median(lengths) if lengths else None,
        "median_final_fight": statistics.median(fights) if fights else None,
        "leader_win_rate": len(held) / len(led) if led else None,
        "trailing_cp": statistics.fmean(t["cp"] for t in trailing) if trailing else None,
        "trailing_at": statistics.fmean(t["at"] for t in trailing) if trailing else None,
        "trailing_vehicles": statistics.fmean(t["vehicles"] for t in trailing) if trailing else None,
    }
    print(f"  summary: {summary}")
    return summary


def compare(baseline: list[Path], variant: list[Path]) -> int:
    base = print_group("Vanilla baseline", [summarise(p) for p in baseline])
    var = print_group("Rules variant", [summarise(p) for p in variant])
    print()
    all_passed = True

    def report(name: str, passed: bool | None, detail: str) -> None:
        nonlocal all_passed
        if passed is None:
            print(f"[N/A ] {name}: {detail}")
            return
        all_passed = all_passed and passed
        print(f"[{'PASS' if passed else 'FAIL'}] {name}: {detail}")

    afford = var["trailing_at"] is not None and var["trailing_vehicles"] is not None
    report(
        "trailing_side_can_still_buy",
        (var["trailing_at"] > 0 and var["trailing_vehicles"] > 0) if afford else None,
        f"late AT launchers {var['trailing_at']}, crewed vehicles {var['trailing_vehicles']}, CP {var['trailing_cp']}",
    )
    fights = base["median_final_fight"], var["median_final_fight"]
    report(
        "final_base_fight_longer",
        (fights[1] > fights[0] and fights[1] >= FINAL_FIGHT_MIN_S) if None not in fights else None,
        f"median {fights[0]} s vanilla, {fights[1]} s variant",
    )
    rate = var["leader_win_rate"]
    report(
        "leader_still_wins",
        rate >= LEAD_WIN_RATE_MIN if rate is not None else None,
        f"variant {rate}, vanilla {base['leader_win_rate']}, minimum {LEAD_WIN_RATE_MIN}",
    )
    return 0 if all_passed else 1


def run_checks(data: Round, gate: str | None) -> bool:
    all_passed = True
    for name, check_gate, fn in CHECKS:
        if check_gate != gate:
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
    parser.add_argument("log", type=Path, nargs="?", help="Path to the server RPT")
    parser.add_argument("--gate", choices=["gatec", "soak"], help="Which checks to run")
    parser.add_argument("--compare", type=Path, nargs="+", default=[], metavar="RPT", help="Vanilla baseline rounds")
    parser.add_argument("--variant", type=Path, nargs="+", default=[], metavar="RPT", help="Rules variant rounds")
    args = parser.parse_args()

    if args.compare or args.variant:
        if not args.compare or not args.variant:
            parser.error("--compare and --variant go together")
        return compare(args.compare, args.variant)
    if args.log is None or args.gate is None:
        parser.error("give an RPT and --gate, or --compare with --variant")
    return 0 if run_checks(parse_log(args.log), args.gate) else 1


if __name__ == "__main__":
    sys.exit(main())
