#!/usr/bin/env python3
"""Does whoever wins the first big clash steamroll the other side? Report only, there is no pass threshold.

    python tools/gates_steamroll.py <rpt> [<rpt> ...]
    python tools/gates_steamroll.py --compare <baseline rpts> --variant <variant rpts>
    python tools/analyse_round.py <rpt> --gate steamroll

The definitions are in DEFINITIONS just below the settings, and every report prints them.
"""

from __future__ import annotations

import argparse
import statistics
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).parent))

from gates_front import NO_DATA, read_kills, square_gap  # noqa: E402
from swl_log import Capture, Round, Sector, fmt_time, parse_log  # noqa: E402

GATE = "steamroll"
SIDES = ("WEST", "EAST")

NEAR_M = 200.0          # "in or near" a sector: within this of its square capture area
PASS_GAP_S = 5          # the observer writes one GRP pass over a second or two; samples this close are one pass
TARGET_MERGE_S = 120    # a side that drops a target and picks the same one again this soon never stopped attacking it
TARGET_SETTLE_S = 30    # a capture this soon after the target line is still that attack's capture
SUSTAIN_WINDOW_S = 90   # contact counts if a second pass, or a capture of the sector, follows within this
MIN_CONTACT_PASSES = 2
HOLD_MIN_S = 300        # how long the enemy must have been targeting a sector for it to count as an attack
HOLD_MIN_PASSES = 4     # how many GRP passes (about 30 s each) the attackers must have been near it

DEFINITIONS = f"""Definitions (from TARGET, CAPTURE, SEC, GRP and ROUNDEND, so a log with no C_KILL is judged the same way):
  stake        a side has a stake in a sector while it owns it or is targeting it. A target dropped and picked again
               within {TARGET_MERGE_S} s is one continuous attack.
  contact      one GRP pass with a living group of each side within {NEAR_M:.0f} m of the sector's square, and both sides
               having a stake in it. It counts if another contact pass or a capture of the sector follows within {SUSTAIN_WINDOW_S} s.
  clash        starts at the first contact on a sector, and is decided by, in this order:
                 the sector is captured by a side during the attack: that side wins;
                 the sector belonged to a side and the attacker's target moved on: the owner wins;
                 otherwise it is undecided (no capture, or the log ended first).
  first clash  the earliest decided clash. Earlier undecided ones are listed, not used. A clash needs both sides there,
               so one side capturing a neutral sector alone is not a clash, however hard the garrison fought.
  after it     times and losses count from the moment the clash was decided, and the clash's own capture isn't counted.
  sector lost  a CAPTURE from that side. A base that falls at ROUNDEND counts as one, because no CAPTURE is logged for it.
  retook       the first-clash loser captures a sector from the first-clash winner, whoever held it before.
  held off     a sector the first-clash loser owned was the winner's target for at least {HOLD_MIN_S} s after the clash, with
               the attackers near it in at least {HOLD_MIN_PASSES} GRP passes, the attack ended, and the sector did not fall
               with it. An attack still going when the log stops is not a hold.
  comeback     retook or held off at least once, after the clash.
  no data      said in place of any number the log can't support. C_KILL, when present, is shown for reference only."""

NO_WINNER = "no winner"
YES = "yes"
NO = "no"


@dataclass
class Spell:
    """One side's continuous attack on one sector. end is None if it was still going when the log stopped."""
    side: str
    sector: str
    start: int
    end: int | None


@dataclass
class Clash:
    sector: str
    start: int
    decided: int | None
    winner: str | None
    how: str

    @property
    def loser(self) -> str | None:
        return next((s for s in SIDES if s != self.winner), None) if self.winner else None


@dataclass
class Hold:
    sector: str
    start: int
    end: int
    attacker_passes: int
    defender_passes: int


@dataclass
class Analysis:
    data: Round
    captures: list[Capture]
    end_t: int
    winner: str | None
    clashes: list[Clash] = field(default_factory=list)
    first: Clash | None = None
    lost: dict[str, list[Capture]] = field(default_factory=dict)
    retakes: list[Capture] = field(default_factory=list)
    holds: list[Hold] = field(default_factory=list)
    still_attacked: list[str] = field(default_factory=list)
    kills_at_clash: int | None = None

    @property
    def comeback(self) -> bool | None:
        return None if self.first is None else bool(self.retakes or self.holds)

    @property
    def time_after(self) -> int | None:
        return None if self.first is None else self.end_t - self.first.decided

    @property
    def winner_won(self) -> str:
        if self.first is None:
            return NO_DATA
        if self.winner is None:
            return NO_WINNER
        return YES if self.winner == self.first.winner else NO


def all_captures(data: Round, end_t: int, winner: str | None) -> list[Capture]:
    """The CAPTURE lines, plus the loser's base falling at ROUNDEND, which has no CAPTURE line of its own."""
    captures = sorted(data.captures, key=lambda c: c.t)
    if winner in SIDES:
        loser = next(s for s in SIDES if s != winner)
        base = data.base_of(loser)
        if base is not None and not any(c.sector == base.name and c.new == winner for c in captures):
            captures.append(Capture(end_t, base.name, loser, winner, base.x, base.y, True))
    return captures


def build_spells(data: Round) -> list[Spell]:
    spells: list[Spell] = []
    for side in SIDES:
        lines = sorted((t for t in data.targets if t.side == side), key=lambda t: t.t)
        current: Spell | None = None
        for index, line in enumerate(lines):
            until = lines[index + 1].t if index + 1 < len(lines) else None
            if line.sector == "-":
                continue
            if current is not None and current.sector == line.sector and line.t - current.end <= TARGET_MERGE_S:
                current.end = until
            else:
                current = Spell(side, line.sector, line.t, until)
                spells.append(current)
    return spells


def spell_at(spells: list[Spell], side: str, sector: str, t: int) -> Spell | None:
    for spell in spells:
        if spell.side == side and spell.sector == sector and spell.start <= t and (spell.end is None or t <= spell.end):
            return spell
    return None


def owner_at(data: Round, captures: list[Capture], sector: str, t: int) -> str:
    owner = data.sectors[sector].owner
    for capture in captures:
        if capture.t <= t and capture.sector == sector:
            owner = capture.new
    return owner


def group_passes(data: Round) -> list[tuple[int, list[tuple[str, float, float]]]]:
    """One GRP pass after another: its time, and each living group's side and position in it."""
    samples = sorted(((s.t, g.side, s.x, s.y) for g in data.groups.values() for s in g.samples if s.units > 0), key=lambda s: s[0])
    passes: list[tuple[int, list[tuple[str, float, float]]]] = []
    for t, side, x, y in samples:
        if not passes or t - passes[-1][0] > PASS_GAP_S:
            passes.append((t, []))
        passes[-1][1].append((side, x, y))
    return passes


def near(sector: Sector, entries: list[tuple[str, float, float]], side: str) -> bool:
    return any(s == side and square_gap(sector, x, y) <= NEAR_M for s, x, y in entries)


def decide(data: Round, captures: list[Capture], spells: list[Spell], sector: str, start: int) -> Clash:
    """How the clash on this sector that began at start came out."""
    owner = owner_at(data, captures, sector, start)
    fall = next((c for c in captures if c.sector == sector and c.t >= start), None)
    attackers = [side for side in SIDES if side != owner]
    open_spells = [spell_at(spells, side, sector, start) for side in attackers]
    ends = [s.end for s in open_spells if s is not None]
    still_open = any(s is not None and s.end is None for s in open_spells)
    last_end = None if still_open or not ends else max(ends)
    if fall is not None and (last_end is None or fall.t <= last_end + TARGET_SETTLE_S):
        if fall.new in SIDES:
            return Clash(sector, start, fall.t, fall.new, f"{fall.new} captured it from {fall.old}")
        return Clash(sector, start, fall.t, None, f"it went to {fall.new}, undecided")
    if last_end is None:
        return Clash(sector, start, None, None, "undecided when the log stopped")
    if owner in SIDES:
        return Clash(sector, start, last_end, owner, f"{attackers[0]} moved its target on, {owner} kept the sector")
    return Clash(sector, start, None, None, f"undecided: both sides moved on by {fmt_time(last_end)} with neither capturing it")


def find_clashes(data: Round, captures: list[Capture], spells: list[Spell], passes: list) -> list[Clash]:
    clashes: list[Clash] = []
    for name, sector in data.sectors.items():
        contacts = []
        for t, entries in passes:
            both_near = all(near(sector, entries, side) for side in SIDES)
            if both_near and all(owner_at(data, captures, name, t) == side or spell_at(spells, side, name, t) for side in SIDES):
                contacts.append(t)
        after = None
        for index, t in enumerate(contacts):
            if after is not None and t <= after:
                continue
            followed = sum(1 for other in contacts[index:] if other - t <= SUSTAIN_WINDOW_S) >= MIN_CONTACT_PASSES
            captured = any(c.sector == name and 0 <= c.t - t <= SUSTAIN_WINDOW_S for c in captures)
            if not followed and not captured:
                continue
            clash = decide(data, captures, spells, name, t)
            clashes.append(clash)
            after = clash.decided
            if after is None:
                gave_up = [s.end for s in spells if s.sector == name and s.start <= t and s.end is not None]
                if not gave_up or any(s.sector == name and s.start <= t and s.end is None for s in spells):
                    break
                after = max(gave_up)
    return sorted(clashes, key=lambda c: c.start)


def find_holds(data: Round, captures: list[Capture], spells: list[Spell], passes: list, first: Clash) -> tuple[list[Hold], list[str]]:
    holds: list[Hold] = []
    still: list[str] = []
    for spell in spells:
        if spell.side != first.winner or spell.sector not in data.sectors:
            continue
        begin = max(spell.start, first.decided)
        if spell.end is not None and spell.end <= begin:
            continue
        if owner_at(data, captures, spell.sector, begin) != first.loser:
            continue
        if spell.end is None:
            if not any(c.sector == spell.sector and c.t > begin for c in captures):
                still.append(spell.sector)
            continue
        if spell.end - begin < HOLD_MIN_S:
            continue
        if any(c.sector == spell.sector and begin < c.t <= spell.end + TARGET_SETTLE_S for c in captures):
            continue
        sector = data.sectors[spell.sector]
        window = [entries for t, entries in passes if begin <= t <= spell.end]
        attackers = sum(1 for entries in window if near(sector, entries, first.winner))
        if attackers < HOLD_MIN_PASSES:
            continue
        defenders = sum(1 for entries in window if near(sector, entries, first.loser))
        holds.append(Hold(spell.sector, begin, spell.end, attackers, defenders))
    return holds, still


def count_kills(data: Round, clash: Clash) -> int | None:
    """Kills between the two sides at the clash sector while it was being fought over. None with no C_KILL lines."""
    kills, _ = read_kills(data)
    if not kills:
        return None
    sector = data.sectors[clash.sector]
    return sum(
        1 for k in kills
        if k.between_sides and k.side != k.by and clash.start <= k.t <= clash.decided and square_gap(sector, k.x, k.y) <= NEAR_M
    )


def analyse(data: Round) -> Analysis:
    winner = data.round_end.get("winner") if data.round_end else None
    if data.round_end:
        end_t = int(float(data.round_end.get("t", data.last_t)))
    else:
        end_t = max([data.last_t] + [s.t for g in data.groups.values() for s in g.samples])
    captures = all_captures(data, end_t, winner)
    result = Analysis(data, captures, end_t, winner if winner in SIDES else None)
    spells = build_spells(data)
    passes = group_passes(data)
    result.clashes = find_clashes(data, captures, spells, passes)
    result.first = next((c for c in result.clashes if c.winner is not None), None)
    if result.first is None:
        return result
    first = result.first
    result.lost = {side: [c for c in captures if c.old == side and c.t > first.decided] for side in SIDES}
    result.retakes = [c for c in result.lost[first.winner] if c.new == first.loser]
    result.holds, result.still_attacked = find_holds(data, captures, spells, passes, first)
    result.kills_at_clash = count_kills(data, first)
    return result


def near_without_stake(analysis: Analysis) -> dict[str, tuple[int, int]]:
    """Sectors both sides' groups were near with no clash there: how many GRP passes, and the first one's time."""
    data = analysis.data
    clashed = {c.sector for c in analysis.clashes}
    found: dict[str, tuple[int, int]] = {}
    for t, entries in group_passes(data):
        for name, sector in data.sectors.items():
            if name not in clashed and all(near(sector, entries, side) for side in SIDES):
                count, start = found.get(name, (0, t))
                found[name] = (count + 1, start)
    return found


def round_line(analysis: Analysis) -> str:
    if analysis.winner:
        return f"round: {fmt_time(analysis.end_t)}, won by {analysis.winner}"
    return f"round: log ends at {fmt_time(analysis.end_t)}, no winner recorded"


def report(analysis: Analysis) -> str:
    data = analysis.data
    if data.start is None or not data.groups or not data.sectors:
        return f"no data: this log has no usable round (start {'found' if data.start else 'missing'}, {len(data.groups)} groups, {len(data.sectors)} sectors)"
    lines = [round_line(analysis)]
    if data.extra_starts:
        lines[0] += f" ({data.extra_starts} later mission start(s) in this log ignored, first round only)"
    first = analysis.first
    undecided = [c for c in analysis.clashes if c.winner is None and (first is None or c.start < first.start)]
    for clash in undecided:
        lines.append(f"undecided contact: {clash.sector} from {fmt_time(clash.start)} ({clash.how})")
    if first is None:
        if analysis.clashes:
            lines.append(f"first clash: {NO_DATA}, no clash in this round was decided")
        else:
            lines.append(f"first clash: {NO_DATA}, both sides were never in contact over a sector they both had a stake in")
        for name, (count, start) in near_without_stake(analysis).items():
            lines.append(f"  for reference: groups of both sides were near {name} in {count} GRP passes from {fmt_time(start)}, but never in sustained contact while both had a stake in it")
        lines += [
            f"first clash winner: {NO_DATA}",
            f"winner of the first clash won the round: {NO_DATA}",
            f"time after the clash: {NO_DATA}",
            f"sectors lost after the clash: {NO_DATA}",
            f"comeback: {NO_DATA}",
        ]
        return "\n".join(lines)
    lines += [
        f"first clash: {first.sector}, contact from {fmt_time(first.start)}, decided at {fmt_time(first.decided)} ({first.how})",
        f"first clash winner: {first.winner}, loser {first.loser}",
        f"winner of the first clash won the round: {analysis.winner_won}",
        f"time after the clash: {fmt_time(analysis.time_after)}" + ("" if analysis.winner else " (to the end of the log, the round had not finished)"),
    ]
    lost_parts = []
    for side in SIDES:
        rows = analysis.lost[side]
        names = ", ".join(f"{c.sector} {fmt_time(c.t)}" for c in rows)
        lost_parts.append(f"{side} {len(rows)}" + (f" ({names})" if names else ""))
    lines.append("sectors lost after the clash: " + "; ".join(lost_parts))
    lines.append(f"comeback: {YES if analysis.comeback else NO}")
    for capture in analysis.retakes:
        lines.append(f"  retook {capture.sector} at {fmt_time(capture.t)}, from {capture.old}")
    for hold in analysis.holds:
        lines.append(f"  held off an attack on {hold.sector}, {fmt_time(hold.start)} to {fmt_time(hold.end)}: attackers near it in {hold.attacker_passes} passes, defenders in {hold.defender_passes}")
    for sector in analysis.still_attacked:
        lines.append(f"  {sector} was still the enemy's target when the log stopped, so it doesn't count either way")
    if analysis.kills_at_clash is None:
        lines.append(f"reference, kills between the sides at the clash: {NO_DATA} (no C_KILL lines)")
    else:
        note = "" if analysis.kills_at_clash else " (none, so treat this clash with care: the groups were near each other but the log shows no kills between them there)"
        lines.append(f"reference, kills between the sides at the clash: {analysis.kills_at_clash}{note}")
    return "\n".join(lines)


def rate_text(part: int, whole: int) -> str:
    return f"{part}/{whole} ({100.0 * part / whole:.0f}%)" if whole else NO_DATA


def print_group(label: str, paths: list[Path], analyses: list[Analysis]) -> None:
    judged = [a for a in analyses if a.first is not None]
    decided_rounds = [a for a in judged if a.winner]
    comebacks = sum(1 for a in judged if a.comeback)
    wins = sum(1 for a in decided_rounds if a.winner_won == YES)
    times = [a.time_after for a in judged]
    unfinished = sum(1 for a in judged if not a.winner)
    losses = [len(a.lost[a.first.loser]) for a in judged]
    print(f"== {label} ==")
    for path, analysis in zip(paths, analyses):
        first = analysis.first
        summary = f"first clash {first.sector}, won by {first.winner}" if first else f"first clash {NO_DATA}"
        print(f"  {path.name}: {summary}; comeback {NO_DATA if analysis.comeback is None else (YES if analysis.comeback else NO)}")
    print(f"  rounds: {len(analyses)}, with a first clash verdict: {len(judged)}")
    print(f"  comeback rate: {rate_text(comebacks, len(judged))}")
    print(f"  winner of the first clash won the round: {rate_text(wins, len(decided_rounds))}, of rounds that had a winner; rounds with no winner {unfinished}")
    if times:
        print(f"  median round length after the clash: {fmt_time(statistics.median(times))}" + (f" ({unfinished} of {len(times)} stop at the end of the log, so they are minimum lengths)" if unfinished else ""))
    else:
        print(f"  median round length after the clash: {NO_DATA}")
    print(f"  median sectors lost by the first-clash loser: {statistics.median(losses):g}" if losses else f"  median sectors lost by the first-clash loser: {NO_DATA}")
    print()


def run_compare(baseline_paths: list[Path], variant_paths: list[Path]) -> int:
    print(DEFINITIONS)
    print()
    print_group("Baseline", baseline_paths, [analyse(parse_log(p)) for p in baseline_paths])
    print_group("Variant", variant_paths, [analyse(parse_log(p)) for p in variant_paths])
    print("No pass threshold: these are reported either way.")
    return 0


def report_check(data: Round) -> tuple[bool, str]:
    return True, f"\n{report(analyse(data))}\n\n{DEFINITIONS}"


def register(check: Callable) -> None:
    check("Steamroll numbers (report only: PASS means they were produced, not that a comeback happened)", gate=GATE)(report_check)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("logs", nargs="*", type=Path, help="RPT files to report on")
    parser.add_argument("--compare", nargs="+", type=Path, help="Baseline RPT files")
    parser.add_argument("--variant", nargs="+", type=Path, help="Variant RPT files")
    parser.add_argument("--gate", choices=[GATE], help="Accepted for consistency with analyse_round.py; the report is the same")
    args = parser.parse_args()

    if args.compare or args.variant:
        if not args.compare or not args.variant:
            parser.error("--compare and --variant go together")
        return run_compare(args.compare, args.variant)
    if not args.logs:
        parser.error("give at least one RPT, or --compare and --variant")

    print(DEFINITIONS)
    print()
    for path in args.logs:
        print(f"== {path.name} ==")
        print(report(analyse(parse_log(path))))
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
