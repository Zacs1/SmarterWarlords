#!/usr/bin/env python3
"""Part E: where the fighting happens, and whether it stays at the front after a sector falls.

    python tools/gates_front.py <rpt> [<rpt> ...]
    python tools/gates_front.py <rpt> --gate front --baseline-share 0.35
    python tools/gates_front.py <rpt> --gate front --baseline <baseline rpt> [...]
    python tools/gates_front.py --compare <baseline rpts> --variant <variant rpts> [--gate front]
    python tools/analyse_round.py <rpt> --gate front [--baseline-share 0.35 | --baseline <rpt> ...]

Kill classes, for every C_KILL after the first sector clash, in this order:
  contested     inside the capture area of a sector a side is targeting at that moment. The loser of a sector that
                still targets it is covered by this, because its TARGET line still names the sector.
  other_sector  inside any other sector's capture area
  edge          within EDGE_M of the edge of any sector's capture area
  between       everywhere else
The capture area is a square of the sector's size, aligned to the map (fn_WLSectorsSetup.sqf setTriggerArea).
The first sector clash is the earlier of the first capture and the first kill in or at the edge of a targeted sector.

After a sector X falls from one side to the other (GUER sectors have no losing commander, so they are left out), kills
are watched for FALL_WINDOW_S, or until X or Y changes hands or the round ends. A kill belongs to the latest fall whose
window it is in, so it is never counted twice. Zones, in this order:
  at_x          inside X's capture area or within EDGE_M of it
  loser_sector  inside the capture area of a sector the losing side owns at that moment
  other_area    inside any other sector's capture area
  corridor      within CORRIDOR_M of the straight line from X to Y
  elsewhere     everywhere else
Y is the winner's next target if the losing side owned it, otherwise the losing side's nearest owned sector to X.

The gate share is (at_x + corridor) / all kills in the fall windows. It passes at baseline + margin or better.
"""

from __future__ import annotations

import argparse
import math
import re
import statistics
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable

sys.path.insert(0, str(Path(__file__).parent))

from swl_log import Round, Sector, fmt_time, parse_log  # noqa: E402

GATE = "front"

EDGE_M = 200.0            # "at a sector edge"
WINDOW_S = 600            # the reporting windows
FALL_WINDOW_S = 600       # how long after a fall its kills are watched
BIN_S = 120               # the bins for how the fighting moved after a fall
CORRIDOR_M = 300.0        # half width of the ground between X and Y
Y_TARGET_WAIT_S = 180     # how long after a fall the winner's next target can still name Y
REINFORCE_SEARCH_S = 1800 # how long after a fall reinforcements are still put down to it
MARGIN = 0.10             # "clearly longer": the share must beat the baseline by this much
MIN_GATE_KILLS = 20       # fewer kills in the fall windows than this can't be judged
SIDES = ("WEST", "EAST")

CONTESTED = "contested"
OTHER_SECTOR = "other_sector"
EDGE = "edge"
BETWEEN = "between"
CLASSES = (CONTESTED, OTHER_SECTOR, EDGE, BETWEEN)

AT_X = "at_x"
CORRIDOR = "corridor"
LOSER_SECTOR = "loser_sector"
OTHER_AREA = "other_area"
ELSEWHERE = "elsewhere"
ZONES = (AT_X, CORRIDOR, LOSER_SECTOR, OTHER_AREA, ELSEWHERE)

NO_DATA = "no data"


@dataclass
class Kill:
    t: int
    side: str
    by: str
    x: float
    y: float

    @property
    def between_sides(self) -> bool:
        return self.side in SIDES and self.by in SIDES


@dataclass
class Fall:
    t: int
    sector: Sector
    loser: str
    winner: str
    next_sector: Sector | None
    how: str
    end: int
    kills: list[tuple[Kill, str]] = field(default_factory=list)

    @property
    def held(self) -> int:
        return sum(1 for _, zone in self.kills if zone in (AT_X, CORRIDOR))


@dataclass
class Analysis:
    data: Round
    kills: list[Kill]
    skipped: int
    clash: int | None
    classified: list[tuple[Kill, str]]
    falls: list[Fall]

    @property
    def last_t(self) -> int:
        last_kill = self.kills[-1].t if self.kills else 0
        return max(self.data.last_t, last_kill)


@dataclass
class FrontStats:
    falls: int = 0
    falls_with_kills: int = 0
    zones: Counter = field(default_factory=Counter)
    kills_sides: int = 0
    held_sides: int = 0
    held_seconds: list[int] = field(default_factory=list)

    @property
    def kills(self) -> int:
        return sum(self.zones.values())

    @property
    def held(self) -> int:
        return self.zones[AT_X] + self.zones[CORRIDOR]

    @property
    def share(self) -> float | None:
        return self.held / self.kills if self.kills else None

    @property
    def share_sides(self) -> float | None:
        return self.held_sides / self.kills_sides if self.kills_sides else None


def _float(value: str | None) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _t(row: dict[str, str]) -> int:
    return int(_float(row.get("t")) or 0)


def pct(part: float, whole: float) -> str:
    return f"{100.0 * part / whole:.0f}%" if whole else "-"


def share_text(share: float | None) -> str:
    return f"{100.0 * share:.1f}%" if share is not None else NO_DATA


def median_time(values: list[int]) -> str:
    return fmt_time(statistics.median(values)) if values else "-"


def read_kills(data: Round) -> tuple[list[Kill], int]:
    """The C_KILL lines in time order, and how many had no usable position."""
    kills: list[Kill] = []
    skipped = 0
    for row in data.of("C_KILL"):
        x, y = _float(row.get("x")), _float(row.get("y"))
        if x is None or y is None:
            skipped += 1
            continue
        kills.append(Kill(_t(row), row.get("side", "?"), row.get("by", "-"), x, y))
    kills.sort(key=lambda k: k.t)
    return kills, skipped


def sector_name(data: Round, row: dict[str, str]) -> str | None:
    """The row's sector under its round-wide name. A sector can log as Sector_<x>_<y> before it gains its location name."""
    name = row.get("sector")
    if name is None or name in data.sectors:
        return name
    match = re.fullmatch(r"(?i)sector_(\d+)_(\d+)", name)
    if match:
        x, y = float(match.group(1)), float(match.group(2))
        for sector in data.sectors.values():
            if math.hypot(sector.x - x, sector.y - y) < 5:
                return sector.name
    return name


def square_gap(sector: Sector, x: float, y: float) -> float:
    """Metres from a point to the sector's square capture area. 0 is inside."""
    half = sector.radius
    return math.hypot(max(abs(x - sector.x) - half, 0.0), max(abs(y - sector.y) - half, 0.0))


def targets_at(data: Round, t: float) -> list[Sector]:
    """The sectors the two sides are targeting at time t."""
    current: dict[str, str] = {}
    for target in data.targets:
        if target.t > t:
            break
        current[target.side] = target.sector
    return [data.sectors[name] for name in current.values() if name in data.sectors]


def owners_at(data: Round, t: float) -> dict[str, str]:
    owners = {name: sector.owner for name, sector in data.sectors.items()}
    for capture in data.captures:
        if capture.t <= t:
            owners[capture.sector] = capture.new
    return owners


def classify(data: Round, x: float, y: float, contested: list[Sector]) -> str:
    if any(square_gap(sector, x, y) == 0 for sector in contested):
        return CONTESTED
    gaps = [square_gap(sector, x, y) for sector in data.sectors.values()]
    if any(gap == 0 for gap in gaps):
        return OTHER_SECTOR
    return EDGE if any(gap <= EDGE_M for gap in gaps) else BETWEEN


def first_clash(data: Round, kills: list[Kill]) -> int | None:
    times = [capture.t for capture in data.captures[:1]]
    for kill in kills:
        if any(square_gap(sector, kill.x, kill.y) <= EDGE_M for sector in targets_at(data, kill.t)):
            times.append(kill.t)
            break
    return min(times) if times else None


def find_next_sector(data: Round, sector: Sector, t: int, loser: str, winner: str) -> tuple[Sector | None, str]:
    owners = owners_at(data, t)
    for target in data.targets:
        if target.side == winner and t <= target.t <= t + Y_TARGET_WAIT_S and target.sector in data.sectors:
            if owners.get(target.sector) == loser:
                return data.sectors[target.sector], "winner's next target"
    owned = [s for name, s in data.sectors.items() if owners.get(name) == loser and s is not sector]
    if not owned:
        return None, "the losing side owns nothing else"
    return min(owned, key=lambda s: math.hypot(s.x - sector.x, s.y - sector.y)), "losing side's nearest sector"


def along_segment(x: float, y: float, a: Sector, b: Sector) -> tuple[float, float]:
    """Metres along a to b, clamped to the segment, and the distance from the point to the segment."""
    dx, dy = b.x - a.x, b.y - a.y
    length = math.hypot(dx, dy)
    if length == 0:
        return 0.0, math.hypot(x - a.x, y - a.y)
    along = max(0.0, min(length, ((x - a.x) * dx + (y - a.y) * dy) / length))
    return along, math.hypot(x - (a.x + dx * along / length), y - (a.y + dy * along / length))


def zone_of(data: Round, fall: Fall, kill: Kill) -> str:
    if square_gap(fall.sector, kill.x, kill.y) <= EDGE_M:
        return AT_X
    inside = [name for name, sector in data.sectors.items() if square_gap(sector, kill.x, kill.y) == 0]
    if inside:
        owners = owners_at(data, kill.t)
        return LOSER_SECTOR if any(owners.get(name) == fall.loser for name in inside) else OTHER_AREA
    if fall.next_sector is not None and along_segment(kill.x, kill.y, fall.sector, fall.next_sector)[1] <= CORRIDOR_M:
        return CORRIDOR
    return ELSEWHERE


def build_falls(data: Round, kills: list[Kill], last_t: int) -> list[Fall]:
    falls: list[Fall] = []
    for capture in data.captures:
        if capture.old not in SIDES or capture.new not in SIDES or capture.base or capture.sector not in data.sectors:
            continue
        sector = data.sectors[capture.sector]
        next_sector, how = find_next_sector(data, sector, capture.t, capture.old, capture.new)
        watched = {capture.sector} | ({next_sector.name} if next_sector else set())
        changes = [c.t for c in data.captures if c.t > capture.t and c.sector in watched]
        end = min([capture.t + FALL_WINDOW_S, last_t] + changes)
        falls.append(Fall(capture.t, sector, capture.old, capture.new, next_sector, how, end))
    for kill in kills:
        open_falls = [f for f in falls if f.t <= kill.t <= f.end]
        if open_falls:
            fall = open_falls[-1]
            fall.kills.append((kill, zone_of(data, fall, kill)))
    return falls


def analyse(data: Round) -> Analysis:
    kills, skipped = read_kills(data)
    clash = first_clash(data, kills)
    classified: list[tuple[Kill, str]] = []
    if clash is not None:
        classified = [(k, classify(data, k.x, k.y, targets_at(data, k.t))) for k in kills if k.t >= clash]
    last_t = max(data.last_t, kills[-1].t if kills else 0)
    return Analysis(data, kills, skipped, clash, classified, build_falls(data, kills, last_t))


def held_seconds(fall: Fall) -> int:
    """How long the fighting stayed at X and on the ground towards Y.

    Ends at the first BIN_S bin where kills in the losing side's sectors outnumber kills at X and in the corridor.
    If that never happens, it is the time of the last kill at X or in the corridor.
    """
    bins: dict[int, Counter] = {}
    for kill, zone in fall.kills:
        bins.setdefault((kill.t - fall.t) // BIN_S, Counter())[zone] += 1
    for index in sorted(bins):
        counts = bins[index]
        if counts[LOSER_SECTOR] > counts[AT_X] + counts[CORRIDOR]:
            return index * BIN_S
    held = [kill.t - fall.t for kill, zone in fall.kills if zone in (AT_X, CORRIDOR)]
    return max(held) if held else 0


def front_stats(analyses: Iterable[Analysis]) -> FrontStats:
    stats = FrontStats()
    for analysis in analyses:
        for fall in analysis.falls:
            stats.falls += 1
            if not fall.kills:
                continue
            stats.falls_with_kills += 1
            stats.held_seconds.append(held_seconds(fall))
            for kill, zone in fall.kills:
                stats.zones[zone] += 1
                if kill.between_sides:
                    stats.kills_sides += 1
                    stats.held_sides += zone in (AT_X, CORRIDOR)
    return stats


def class_line(label: str, counts: Counter) -> str:
    total = sum(counts.values())
    shares = "  ".join(f"{pct(counts[name], total):>12}" for name in CLASSES)
    return f"  {label:<16} {total:>5}  {shares}"


def class_header() -> str:
    return f"  {'':<16} {'kills':>5}  " + "  ".join(f"{name:>12}" for name in CLASSES)


def report_classes(analysis: Analysis) -> list[str]:
    lines = ["Where the kills happened (after the first sector clash)"]
    if not analysis.kills:
        return lines + [f"  C_KILL: {NO_DATA}"]
    if analysis.clash is None:
        return lines + [f"  {len(analysis.kills)} kills, but no sector clash in this round"]
    before = sum(1 for k in analysis.kills if k.t < analysis.clash)
    lines.append(f"  first clash at {fmt_time(analysis.clash)}; {before} earlier kills left out, {analysis.skipped} without a position")
    windows: dict[int, Counter] = {}
    for kill, label in analysis.classified:
        windows.setdefault((kill.t - analysis.clash) // WINDOW_S, Counter())[label] += 1
    lines.append(class_header())
    for index in sorted(windows):
        start = analysis.clash + index * WINDOW_S
        lines.append(class_line(f"{fmt_time(start)}-{fmt_time(start + WINDOW_S)}", windows[index]))
    lines.append(class_line("whole round", Counter(label for _, label in analysis.classified)))
    return lines


def report_falls(analysis: Analysis) -> list[str]:
    lines = ["After each sector fell from one side to the other"]
    if not analysis.falls:
        return lines + [f"  no sector changed hands between the sides: {NO_DATA}"]
    for fall in analysis.falls:
        y_name = fall.next_sector.name if fall.next_sector else "none"
        lines.append(f"  {fmt_time(fall.t)} {fall.sector.name} fell, {fall.loser} to {fall.winner}; next sector {y_name} ({fall.how}); watched to {fmt_time(fall.end)}")
        if not fall.kills:
            lines.append(f"    kills: {NO_DATA}")
            continue
        zones = Counter(zone for _, zone in fall.kills)
        total = len(fall.kills)
        lines.append("    " + ", ".join(f"{name} {zones[name]} ({pct(zones[name], total)})" for name in ZONES))
        lines.append(f"    at or around it and towards {y_name}: {pct(fall.held, total)} of {total}; stayed there for {fmt_time(held_seconds(fall))}")
        lines += report_progress(fall)
    return lines


def report_progress(fall: Fall) -> list[str]:
    """Median distance along X towards Y of the kills at the front, per bin after the fall."""
    if fall.next_sector is None:
        return []
    length = math.hypot(fall.next_sector.x - fall.sector.x, fall.next_sector.y - fall.sector.y)
    bins: dict[int, list[float]] = {}
    for kill, zone in fall.kills:
        if zone in (AT_X, CORRIDOR) or square_gap(fall.next_sector, kill.x, kill.y) == 0:
            bins.setdefault((kill.t - fall.t) // BIN_S, []).append(along_segment(kill.x, kill.y, fall.sector, fall.next_sector)[0])
    if not bins:
        return [f"    fighting moved towards {fall.next_sector.name}: no kills on that line"]
    parts = [f"{fmt_time(i * BIN_S)}+ {statistics.median(bins[i]):.0f} m ({len(bins[i])})" for i in sorted(bins)]
    return [f"    fighting moved from {fall.sector.name} towards {fall.next_sector.name} ({length:.0f} m), median and kills per {BIN_S} s: " + ", ".join(parts)]


def _matches_fall(data: Round, row: dict[str, str], fall: Fall) -> bool:
    """A helper's line belongs to a fall if its side and sector agree, or it doesn't give them."""
    if row.get("side") not in (None, fall.loser):
        return False
    return sector_name(data, row) in (None, "-", fall.sector.name)


def report_holdouts(analysis: Analysis) -> list[str]:
    """C_HOLD holdout survival and reinforcement timing, measured from the fall."""
    data = analysis.data
    rows = data.of("C_HOLD")
    lines = ["Holdouts and reinforcements"]
    if not rows:
        return lines + [f"  C_HOLD: {NO_DATA}"]
    formed = [r for r in rows if r.get("event") == "formed"]
    wiped = [r for r in rows if r.get("event") == "wiped"]
    survival: list[int] = []
    still_alive = 0
    for row in formed:
        start = _t(row)
        falls = [f for f in analysis.falls if _matches_fall(data, row, f) and f.t <= start]
        if falls:
            start = min(start, falls[-1].t)
        ends = [_t(w) for w in wiped if _t(w) >= start and w.get("side") == row.get("side") and sector_name(data, w) == sector_name(data, row)]
        if ends:
            survival.append(ends[0] - start)
        else:
            still_alive += 1
    lines.append(f"  holdouts formed {len(formed)}, wiped {len(survival)}, not wiped by the end of the log {still_alive}; median survival of those wiped {median_time(survival)}")

    left_all: list[int] = []
    arrived_all: list[int] = []
    for fall in analysis.falls:
        limit = fall.t + REINFORCE_SEARCH_S
        left = [_t(r) for r in rows if r.get("event") == "reinforce_left" and _matches_fall(data, r, fall) and fall.t <= _t(r) <= limit]
        arrived = [_t(r) for r in rows if r.get("event") == "reinforce_arrived" and _matches_fall(data, r, fall) and fall.t <= _t(r) <= limit]
        left_text = fmt_time(left[0] - fall.t) if left else "none"
        arrived_text = fmt_time(arrived[0] - fall.t) if arrived else "none"
        lines.append(f"  {fmt_time(fall.t)} {fall.sector.name}: first reinforcements left after {left_text}, arrived after {arrived_text}")
        if left:
            left_all.append(left[0] - fall.t)
        if arrived:
            arrived_all.append(arrived[0] - fall.t)
    lines.append(f"  median first left {median_time(left_all)}, median first arrived {median_time(arrived_all)}")

    sent = [_t(r) for r in rows if r.get("event") == "resupply_sent"]
    delivered = [_t(r) for r in rows if r.get("event") == "resupply_delivered"]
    gaps = [d - s for s, d in zip(sorted(sent), sorted(delivered)) if d >= s]
    lines.append(f"  resupplies sent {len(sent)}, delivered {len(delivered)}; median time to deliver {median_time(gaps)} (paired in order)")
    return lines


@dataclass
class Closure:
    side: str
    sector: str
    start: int
    end: int | None


def fast_travel_closures(analysis: Analysis) -> list[Closure]:
    closures: list[Closure] = []
    open_now: dict[tuple[str, str], Closure] = {}
    for row in analysis.data.of("C_FRONT"):
        key = (row.get("side", "?"), sector_name(analysis.data, row) or "?")
        state = row.get("state")
        if state == "closed" and key not in open_now:
            closure = Closure(key[0], key[1], _t(row), None)
            open_now[key] = closure
            closures.append(closure)
        elif state == "open" and key in open_now:
            open_now.pop(key).end = _t(row)
    return closures


def report_fast_travel(analysis: Analysis) -> list[str]:
    lines = ["Fast travel to a threatened sector"]
    if not analysis.data.of("C_FRONT"):
        return lines + [f"  C_FRONT: {NO_DATA}"]
    closures = fast_travel_closures(analysis)
    if not closures:
        return lines + ["  never closed"]
    for side in sorted({c.side for c in closures}):
        rows = [c for c in closures if c.side == side]
        spans = [(c.end if c.end is not None else analysis.last_t) - c.start for c in rows]
        still = sum(1 for c in rows if c.end is None)
        lines.append(f"  {side}: closed {len(rows)} time(s) at {len({c.sector for c in rows})} sector(s), total {fmt_time(sum(spans))}, median {median_time(spans)}, longest {fmt_time(max(spans))}; {still} still closed at the end of the log")
    return lines


def report_engaged(analysis: Analysis) -> list[str]:
    lines = ["Engaged contacts in transit"]
    rows = analysis.data.of("C_ENGAGED")
    if not rows:
        return lines + [f"  C_ENGAGED: {NO_DATA}"]
    starts = [r for r in rows if r.get("event") == "start"]
    ends = [r for r in rows if r.get("event") == "end"]
    per_side = Counter(r.get("side", "?") for r in starts)
    sides = ", ".join(f"{side} {count}" for side, count in sorted(per_side.items()))
    lines.append(f"  {len(starts)} started ({sides or 'none'}), {len(ends)} ended")
    return lines


def report(analysis: Analysis) -> str:
    sections = [report_classes(analysis), report_falls(analysis), report_holdouts(analysis), report_fast_travel(analysis), report_engaged(analysis)]
    return "\n\n".join("\n".join(section) for section in sections)


def stats_text(stats: FrontStats) -> str:
    zones = ", ".join(f"{name} {stats.zones[name]}" for name in ZONES)
    return (
        f"{share_text(stats.share)} of {stats.kills} kills across {stats.falls_with_kills} of {stats.falls} falls ({zones}); "
        f"between the two sides only: {share_text(stats.share_sides)}; median time the fight stayed there {median_time(stats.held_seconds)}"
    )


def baseline_from(analyses: list[Analysis]) -> tuple[float | None, str]:
    stats = front_stats(analyses)
    note = f"baseline from {len(analyses)} RPT(s): {stats_text(stats)}"
    if not any(a.kills for a in analyses):
        note += " (no C_KILL lines in the baseline)"
    elif stats.kills < MIN_GATE_KILLS:
        note += f" (only {stats.kills} kills in fall windows, weak baseline)"
    return stats.share, note


def judge(stats: FrontStats, baseline: float | None, baseline_note: str, margin: float) -> tuple[bool, str]:
    lines = [f"variant: {stats_text(stats)}", baseline_note]
    if stats.kills < MIN_GATE_KILLS:
        lines.append(f"cannot judge: fewer than {MIN_GATE_KILLS} kills in fall windows")
        return False, "\n".join(lines)
    if baseline is None:
        lines.append("cannot judge: no baseline share")
        return False, "\n".join(lines)
    needed = baseline + margin
    lines.append(f"needs {share_text(needed)} ({share_text(baseline)} baseline + {margin * 100:.0f} points)")
    return stats.share >= needed, "\n".join(lines)


_config: dict = {"share": None, "paths": None, "margin": MARGIN}


def configure(share: float | None, paths: list[Path] | None, margin: float = MARGIN) -> None:
    """Set the baseline for the registered check. analyse_round.py calls this from its command line."""
    if share is not None and share > 1:
        share /= 100
    _config.update(share=share, paths=paths, margin=margin)


def resolve_baseline() -> tuple[float | None, str]:
    if _config["share"] is not None:
        return _config["share"], f"baseline passed in: {share_text(_config['share'])}"
    if _config["paths"]:
        return baseline_from([analyse(parse_log(p)) for p in _config["paths"]])
    return None, "no baseline given (--baseline-share or --baseline)"


def gate_check(data: Round) -> tuple[bool, str]:
    baseline, note = resolve_baseline()
    return judge(front_stats([analyse(data)]), baseline, note, _config["margin"])


def report_check(data: Round) -> tuple[bool, str]:
    return True, report(analyse(data))


def register(check: Callable) -> None:
    check("Front: where the fighting happened", gate=GATE)(report_check)
    check("Front: after a sector falls the fighting stays there and on the ground towards the next sector", gate=GATE)(gate_check)


def event_counts(analysis: Analysis) -> str:
    hold = Counter(r.get("event", "?") for r in analysis.data.of("C_HOLD"))
    closures = len(fast_travel_closures(analysis))
    starts = sum(1 for r in analysis.data.of("C_ENGAGED") if r.get("event") == "start")
    if not analysis.data.of("C_HOLD") and not analysis.data.of("C_FRONT") and not analysis.data.of("C_ENGAGED"):
        return NO_DATA
    return (
        f"holdouts {hold['formed']}, wiped {hold['wiped']}, reinforcements left {hold['reinforce_left']}, arrived {hold['reinforce_arrived']}, "
        f"resupplies {hold['resupply_sent']}/{hold['resupply_delivered']}, fast travel closed {closures}, engaged {starts}"
    )


def print_group(label: str, paths: list[Path], analyses: list[Analysis]) -> None:
    print(f"== {label} ==")
    for path, analysis in zip(paths, analyses):
        print(f"  {path.name}: {len(analysis.kills)} kills, {len(analysis.falls)} falls; events: {event_counts(analysis)}")
    pooled = Counter(cat for a in analyses for _, cat in a.classified)
    print("  Kills after the first clash, all rounds")
    print(class_header())
    print(class_line("whole", pooled))
    print(f"  After a sector fell: {stats_text(front_stats(analyses))}")
    print()


def run_compare(baseline_paths: list[Path], variant_paths: list[Path], margin: float, gated: bool) -> int:
    baseline = [analyse(parse_log(p)) for p in baseline_paths]
    variant = [analyse(parse_log(p)) for p in variant_paths]
    print_group("Baseline", baseline_paths, baseline)
    print_group("Variant", variant_paths, variant)
    share, note = baseline_from(baseline)
    ok, detail = judge(front_stats(variant), share, note, margin)
    print(detail)
    print(f"Gate {GATE}: {'PASS' if ok else 'FAIL'}")
    return 0 if ok or not gated else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("logs", nargs="*", type=Path, help="RPT files to report on")
    parser.add_argument("--compare", nargs="+", type=Path, help="Baseline RPT files")
    parser.add_argument("--variant", nargs="+", type=Path, help="Variant RPT files")
    parser.add_argument("--gate", choices=[GATE], help="Judge the front gate")
    parser.add_argument("--baseline-share", type=float, help="Baseline share, as 0.35 or 35")
    parser.add_argument("--baseline", nargs="+", type=Path, help="Baseline RPT files to read the share from")
    parser.add_argument("--margin", type=float, default=MARGIN, help=f"Points the variant must beat the baseline by (default {MARGIN})")
    args = parser.parse_args()

    if args.compare or args.variant:
        if not args.compare or not args.variant:
            parser.error("--compare and --variant go together")
        return run_compare(args.compare, args.variant, args.margin, bool(args.gate))
    if not args.logs:
        parser.error("give at least one RPT, or --compare and --variant")

    analyses = [analyse(parse_log(path)) for path in args.logs]
    for path, analysis in zip(args.logs, analyses):
        print(f"== {path.name} ==")
        print(report(analysis))
        print()
    if not args.gate:
        return 0
    configure(args.baseline_share, args.baseline, args.margin)
    baseline, note = resolve_baseline()
    ok, detail = judge(front_stats(analyses), baseline, note, args.margin)
    print(detail)
    print(f"Gate {GATE}: {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
