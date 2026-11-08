#!/usr/bin/env python3
"""Summarises an automated Warlords round from its RPT and runs named PASS/FAIL checks.

    python tools/analyse_round.py <path-to-rpt>

To add a check, write a function that takes a Round and returns (passed, detail),
and decorate it with @check("name"). Exit code is 0 only if every check passes.
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
    idle_stretches,
    jumps,
    parse_log,
)

SIDES = ("WEST", "EAST")
MOVED_METRES = 100.0

CheckFn = Callable[[Round], "tuple[bool, str]"]
CHECKS: list[tuple[str, CheckFn]] = []


def check(name: str) -> Callable[[CheckFn], CheckFn]:
    def register(fn: CheckFn) -> CheckFn:
        CHECKS.append((name, fn))
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


def run_checks(data: Round) -> bool:
    section("Checks")
    all_passed = True
    for name, fn in CHECKS:
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
    args = parser.parse_args()

    data = parse_log(args.log)
    print_header(data)
    if data.start is not None:
        print_groups_over_time(data)
        print_captures(data)
        print_targets(data)
        print_idle(data)
        print_jumps(data)
    print_errors(data)
    return 0 if run_checks(data) else 1


if __name__ == "__main__":
    sys.exit(main())
