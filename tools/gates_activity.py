"""Is every AI commander actually doing something? Gate name: activity. Run on every soak.

Measured per commander (one AI warlord group), over the time that commander's group was alive:

- job time: seconds in each commander job, from the state on each position sample.
- real idle: the leader stayed within 30 m for 3+ minutes, not in combat, while in a job that should be moving.
- waiting: time in a job whose point is to stand by (muster, rally wait, picket, reserve).
- busy: everything else. Moving, attacking, defending, raiding, probing, in combat.

A commander passes when its longest real idle stretch is short, its total real idle is small, waiting
does not take most of its life, and at some point in the round it went somewhere and did a working job.
"""
from __future__ import annotations

import sys
from dataclasses import dataclass, field

from swl_log import Group, fmt_time, idle_stretches

WAITING_JOBS = ("Mustering", "Waiting", "Picket", "Reserve")
WORKING_JOBS = ("Moving", "Assault", "Attacking", "Reinforcing", "Defending", "Raiding", "Probing", "Borrowed", "Pickup", "Hunting")

MAX_IDLE_STRETCH = 300        # seconds; one stretch longer than this fails the commander
MAX_STILL_IN_COMBAT = 480     # standing still with the group in combat mode this long isn't a fight any more
MIN_JOB_CHANGES = 3           # a commander that stays in one job all round isn't being commanded (commander rounds only)
MAX_IDLE_SHARE = 0.15         # of the time alive
MAX_WAITING_SHARE = 0.60      # of the time alive
MIN_SECONDS_ALIVE = 600       # a group alive for less than this has too little to judge
MIN_TRAVEL_M = 500            # total distance over the round, in hops of at least 10 m
MIN_COMMANDERS_PASSING = 1.0  # share of the judged commanders that must pass for the round to pass
BASELINE_IDLE_RATE = 2.65  # vanilla baseline: idle group-minutes per minute of round


@dataclass
class Activity:
    group: Group
    alive: int = 0
    jobs: dict[str, int] = field(default_factory=dict)
    idle_total: int = 0
    idle_longest: int = 0
    idle_longest_at: int = 0
    idle_job: str = "-"
    still_combat: int = 0
    waiting: int = 0
    combat: int = 0
    travel: float = 0.0
    changes: int = 0
    failures: list[str] = field(default_factory=list)

    @property
    def judged(self) -> bool:
        return self.alive >= MIN_SECONDS_ALIVE

    @property
    def passed(self) -> bool:
        return self.judged and not self.failures


def state_at(group: Group, t: int) -> str:
    state = "-"
    for sample in group.samples:
        if sample.t > t:
            break
        state = sample.state
    return state


def measure(group: Group, changes: int = 0, commander_round: bool = False) -> Activity:
    out = Activity(group, changes=changes)
    previous = None
    anchor = None
    for sample in group.samples:
        if previous is not None and previous.units > 0:
            step = max(0, sample.t - previous.t)
            out.alive += step
            out.jobs[previous.state] = out.jobs.get(previous.state, 0) + step
            if previous.state in WAITING_JOBS:
                out.waiting += step
            if previous.combat:
                out.combat += step
        if sample.units > 0:
            if anchor is None:
                anchor = sample
            else:
                hop = ((sample.x - anchor.x) ** 2 + (sample.y - anchor.y) ** 2) ** 0.5
                # A long hop in one sample is a fast travel or a respawn, not a sign of activity by itself.
                if 10 <= hop <= 400:
                    out.travel += hop
                    anchor = sample
                elif hop > 400:
                    anchor = sample
        previous = sample

    for stretch in idle_stretches(group):
        window = [s for s in group.samples if stretch.start <= s.t <= stretch.end and s.units > 0]
        if window and stretch.combat_fraction >= 0.5:
            out.still_combat = max(out.still_combat, stretch.end - stretch.start)
        if not window or stretch.combat_fraction >= 0.5:
            continue
        # Count only the part of the stretch spent in a job that should be moving.
        unexplained = 0
        last = window[0]
        for sample in window[1:]:
            if last.state not in WAITING_JOBS:
                unexplained += sample.t - last.t
            last = sample
        if unexplained <= 0:
            continue
        out.idle_total += unexplained
        if unexplained > out.idle_longest:
            out.idle_longest = unexplained
            out.idle_longest_at = stretch.start
            out.idle_job = window[0].state

    if out.judged:
        if out.idle_longest > MAX_IDLE_STRETCH:
            out.failures.append(f"idle {fmt_time(out.idle_longest)} at {fmt_time(out.idle_longest_at)} as {out.idle_job}")
        if out.still_combat > MAX_STILL_IN_COMBAT:
            out.failures.append(f"stood still in combat mode for {fmt_time(out.still_combat)}")
        if out.idle_total > out.alive * MAX_IDLE_SHARE:
            out.failures.append(f"idle {out.idle_total / out.alive:.0%} of its life")
        if out.waiting > out.alive * MAX_WAITING_SHARE:
            out.failures.append(f"waiting {out.waiting / out.alive:.0%} of its life")
        if out.travel < MIN_TRAVEL_M:
            out.failures.append(f"only travelled {out.travel:.0f} m")
        if commander_round and changes < MIN_JOB_CHANGES:
            out.failures.append(f"only {changes} job changes")
        if not any(out.jobs.get(job, 0) > 0 for job in WORKING_JOBS) and out.combat == 0 and commander_round:
            out.failures.append("never had a working job or a fight")
    return out


def measure_round(data) -> list[Activity]:
    changes: dict[str, int] = {}
    commander_round = bool(data.of("C_STATE"))
    for row in data.of("C_STATE"):
        changes[row.get("group", "")] = changes.get(row.get("group", ""), 0) + 1
    rows = []
    for group in data.groups.values():
        if group.is_ai and group.is_warlord:
            rows.append(measure(group, changes.get(group.id, changes.get(group.name, 0)), commander_round))
    rows.sort(key=lambda a: (a.group.side, a.group.name))
    return rows


def report(data) -> str:
    """One line per commander, for hand-offs and the final message."""
    lines = ["side   commander     alive  busy%  wait%  idle%  longest idle  travel m  job changes  result"]
    for a in measure_round(data):
        alive = max(a.alive, 1)
        busy = 1 - (a.waiting + a.idle_total) / alive
        result = "too short to judge" if not a.judged else ("PASS" if a.passed else "FAIL: " + "; ".join(a.failures))
        lines.append(
            f"{a.group.side:<6} {a.group.name[-12:]:<12} {fmt_time(a.alive):>6} {busy:>6.0%} {a.waiting / alive:>6.0%} "
            f"{a.idle_total / alive:>6.0%} {fmt_time(a.idle_longest):>13} {a.travel:>9.0f} {a.changes:>12}  {result}"
        )
    return "\n".join(lines)


def register(check) -> None:
    @check("Activity: every commander stays busy", gate="activity")
    def every_commander(data):
        rows = [a for a in measure_round(data) if a.judged]
        if not rows:
            return False, "no commander alive long enough to judge"
        failed = [a for a in rows if not a.passed]
        ok = (len(rows) - len(failed)) / len(rows) >= MIN_COMMANDERS_PASSING
        detail = "; ".join(f"{a.group.side} {a.group.name}: {', '.join(a.failures)}" for a in failed[:16])
        return ok, f"{len(rows) - len(failed)} of {len(rows)} pass" + (f". {detail}" if detail else "")

    @check("Activity: no side leaves a commander idle more than 5 minutes", gate="activity")
    def longest(data):
        rows = [a for a in measure_round(data) if a.judged]
        worst = max(rows, key=lambda a: a.idle_longest, default=None)
        if worst is None:
            return False, "no commander alive long enough to judge"
        return worst.idle_longest <= MAX_IDLE_STRETCH, (
            f"longest {fmt_time(worst.idle_longest)} ({worst.group.side} {worst.group.name}, as {worst.idle_job}, at {fmt_time(worst.idle_longest_at)})"
        )

    @check("Activity: raw idle time is no worse than vanilla's", gate="activity")
    def versus_baseline(data):
        minutes = max(1.0, data.last_t / 60.0)
        idle = sum((s.end - s.start) / 60.0 for g in data.groups.values() if g.is_ai and g.is_warlord for s in idle_stretches(g))
        rate = idle / minutes
        return rate <= BASELINE_IDLE_RATE, f"{idle:.0f} idle group-minutes in {minutes:.0f} minutes ({rate:.2f} a minute), vanilla {BASELINE_IDLE_RATE:.2f}"

    @check("Activity: both sides spend most of the round working", gate="activity")
    def sides(data):
        rows = [a for a in measure_round(data) if a.judged]
        out = []
        ok = bool(rows)
        for side in sorted({a.group.side for a in rows}):
            members = [a for a in rows if a.group.side == side]
            alive = max(sum(a.alive for a in members), 1)
            idle = sum(a.idle_total for a in members) / alive
            waiting = sum(a.waiting for a in members) / alive
            busy = 1 - idle - waiting
            ok = ok and busy >= 0.5
            out.append(f"{side} busy {busy:.0%}, waiting {waiting:.0%}, idle {idle:.0%}")
        return ok, "; ".join(out)


def main(argv: list[str]) -> int:
    from swl_log import parse_log  # local import keeps the gate module light when loaded by analyse_round

    data = parse_log(argv[0])
    print(report(data))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
