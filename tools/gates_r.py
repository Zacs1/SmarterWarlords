"""Part R (resilience) gates. Imported by analyse_round.py, which calls register(check).

Two gates:

partr: reads the GS lines from the sabotage scenario. Each case logs event=sabotage once and event=track every
10 s. A case passes when the group is moving purposefully again within RECOVERY_SECONDS. Any one of these counts:
  - the leader walked or drove at least MOVE_METRES in a job, with a live waypoint or a job that holds on purpose;
  - C_STATE put the group in a working job, and a later sample shows a live waypoint;
  - the ladder moved it (a fast travel or respawn that shows as a long hop), and it then shows up in a job;
  - a group that was holding on purpose before a case that doesn't move it is still holding after it.
Scatter must also have its men recalled or joined, and the script error case must have a C_GROUPERR line.

soakr: over the whole round, no commander group goes more than SOAK_MAX_NO_PROGRESS seconds without progress.
Commander groups and positions come from the GRP tracks (every 30 s) and job changes from C_STATE, the same
data gates_activity.py uses. C_VPOS only covers a wave's combat vehicles, so it can't judge groups. Progress is any of:
  - moving meaningfully: the leader is PROGRESS_METRES or more from where the current stretch began. That is the
    idle radius, so a shuffle on the spot doesn't count, and a fast travel does;
  - changing job: a C_STATE change, except into Unassigned or -, which are bookkeeping, and except a change that
    just reverses the previous one within FLIP_FLOP_SECONDS, so bouncing between two jobs can't reset the clock;
  - fighting: combat=1 on the sample, for up to MAX_COMBAT_CREDIT seconds in a row. gates_activity.py uses the same
    limit: standing still in combat mode longer than that isn't a fight any more.
Time within a stretch is charged to the job the group was in. Jobs that hold on purpose (Mustering, Waiting, Picket,
Reserve, Defending with no contact) go to their own list and are not failed unless they pass that job's own limit
in HOLD_LIMITS. A group in contact shows combat=1 and is credited as fighting, so what reaches the Defending limit
is a group that stayed on after the threat went. Borrowed groups follow a player and are not judged. A group is
judged from its first commander job. A gap in its track means it was dead, and a new stretch starts when it returns.
Times are only as fine as the 30 s samples, so a stretch can read up to 30 s long. The holding limits allow for that
(SAMPLE_SLACK_SECONDS). The hard no-progress limit does not, so a group at exactly the limit can read as just over.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Callable

from swl_log import FT_JUMP_M, Group, Round, Sample, fmt_time

GATE = "partr"
SOAK_GATE = "soakr"

RECOVERY_SECONDS = 180        # a sabotaged group must be moving purposefully again within this
MOVE_METRES = 25              # what counts as moving in a case, measured from the first sample after the sabotage
SCATTER_RECOVERED_M = 250     # the squad counts as gathered when its furthest man is this close to the leader
HOP_MATCH_SECONDS = 20        # a long hop is put down to a logged fast travel or rung this close in time
ALLOWED_INJECTED_ERRORS = 1   # the one script error the sabotage hook throws on purpose

SOAK_MAX_NO_PROGRESS = 240    # hard gate: no commander group goes this long without progress
PROGRESS_METRES = 30.0        # the idle radius in swl_log
MAX_COMBAT_CREDIT = 480       # seconds in a row that combat mode counts as fighting (MAX_STILL_IN_COMBAT in gates_activity)
FLIP_FLOP_SECONDS = 120       # a job change undoing the last one within this isn't progress
SAMPLE_GAP_SECONDS = 65       # more than two samples missing: the group was dead
SAMPLE_SLACK_SECONDS = 30     # one sample of slack on the holding limits
NOT_PROGRESS_JOBS = ("Unassigned", "-", "released")

WORKING_JOBS = ("Travelling", "Mounting", "Advancing", "Assaulting", "Regrouping", "Defending", "Raiding", "Probing", "Recon", "Pickup", "Hunting")
HOLDING_JOBS = ("Mustering", "Waiting", "Picket", "Reserve")
EXEMPT_JOBS = ("Borrowed",)

# Longest a group may stand still in a holding job, each from its own settings in commander/swlc/settings.sqf.
HOLD_LIMITS = {
    "Mustering": 180,   # musterMaxSeconds 70, plus a tick or two and men still landing
    "Waiting": 720,     # rallyLoneWait 180, x1.2 for the slowest persona, x2 at the enemy base, plus peelHoldMaxSeconds 240 and the last man arriving
    "Picket": 540,      # picketRotateSeconds 480, plus a minute for the handover
    "Reserve": 420,     # reservePatrolSeconds 150, so two missed walks and a margin
    "Defending": 420,   # defenceStandDownSeconds 120 after the last sighting, plus five minutes of a threat seen but not fought
}
# Defending is a working job for the sabotage cases and a holding job for the soak: both are about what the group is
# doing when it stands still, and a defender standing still is only legitimate while the threat lasts.
SOAK_HOLD_JOBS = tuple(HOLD_LIMITS)

LADDER_RUNGS = ("reissue", "reroute", "dismount", "fasttravel", "respawn")
RELOCATING_RUNGS = ("fasttravel", "respawn")   # the rungs that take a group out of where it was put

CASES = (
    ("kill_leader", "a squad's leader is killed"),
    ("kill_leader2", "another squad's leader is killed"),
    ("no_waypoints", "all waypoints deleted"),
    ("no_order", "waypoints and the remembered order deleted"),
    ("sea", "teleported into the sea"),
    ("forest", "teleported into dense forest"),
    ("rocks", "teleported into rocks"),
    ("flip", "crewed vehicle flipped"),
    ("immobilise", "crewed vehicle immobilised"),
    ("scatter", "squad scattered 500 m apart"),
    ("script_error", "script error inside one group's handling"),
)
# These leave a group where it is, so a group that was holding can simply go on holding.
STAYS_PUT_CASES = ("kill_leader", "kill_leader2", "no_waypoints", "no_order", "script_error")


def _num(entry: dict[str, str], key: str, default: float = 0.0) -> float:
    try:
        return float(entry.get(key, default))
    except (TypeError, ValueError):
        return default


def _t(entry: dict[str, str]) -> float:
    return _num(entry, "t")


def gs(data: Round, event: str) -> list[dict[str, str]]:
    return [e for e in data.of("GS") if e.get("event") == event]


def _ours(errors) -> list:
    return [e for e in errors if not e.file.lower().lstrip("/\\").startswith("a3")]


@dataclass
class Point:
    t: float
    x: float
    y: float
    state: str
    men: int
    wp: str
    spread: float
    gone: bool
    located: bool
    wet: bool | None = None   # None in a log from before the scenario reported it

    @property
    def has_waypoint(self) -> bool:
        index, _, count = self.wp.partition("/")
        try:
            return int(index) < int(count)
        except ValueError:
            return False

    @property
    def in_job(self) -> bool:
        return self.state not in ("-", "", "Unassigned", "released")


def _points(data: Round, case: str, t0: float) -> list[Point]:
    points = []
    for e in gs(data, "track"):
        if e.get("case") != case or _t(e) < t0:
            continue
        points.append(Point(_t(e), _num(e, "x"), _num(e, "y"), e.get("state", "-"), int(_num(e, "men")), e.get("wp", "0/0"), _num(e, "spread"), e.get("gone") == "1", "x" in e, e.get("wet") == "1" if "wet" in e else None))
    return sorted(points, key=lambda p: p.t)


def _bare(name: str | None) -> str:
    """A group's id without the side letter that `str group` adds, so either spelling in a log line matches."""
    text = name or ""
    return text[2:] if text[:2] in ("B ", "O ", "I ") else text


def _group_rows(data: Round, kind: str, side: str | None, group: str | None, t0: float, t1: float) -> list[dict[str, str]]:
    wanted = _bare(group)
    return [e for e in data.of(kind) if e.get("side") == side and _bare(e.get("group")) == wanted and t0 <= _t(e) <= t1]


def _near(rows: list[dict[str, str]], t: float) -> dict[str, str] | None:
    close = [e for e in rows if abs(_t(e) - t) <= HOP_MATCH_SECONDS]
    return close[0] if close else None


def recovery(case: str, info: dict[str, str], points: list[Point], data: Round) -> tuple[float | None, str]:
    """Seconds from the sabotage until the group was working again, and how it got there. None if it never did."""
    t0 = _t(info)
    deadline = t0 + RECOVERY_SECONDS
    side, group = info.get("side"), info.get("group")
    ladder = _group_rows(data, "C_LADDER", side, group, t0, deadline)
    ft = _group_rows(data, "C_FT", side, group, t0, deadline)
    states = _group_rows(data, "C_STATE", side, group, t0, deadline)
    found: list[tuple[float, str]] = []

    anchor: Point | None = None
    hop: str | None = None
    for p in points:
        if p.t > deadline:
            break
        if p.gone or p.men <= 0 or not p.located:
            continue  # no position to measure: the group is gone, or its leader is dead and not yet replaced
        if anchor is None:
            anchor = p
            continue
        metres = math.hypot(p.x - anchor.x, p.y - anchor.y)
        if metres >= FT_JUMP_M:
            source = _near(ladder, p.t) or _near(ft, p.t)
            anchor = p
            if source is not None:
                hop = f"rung {source['rung']}" if "rung" in source else f"fast travel to {source.get('sector', '?')}"
                if p.in_job:
                    found.append((p.t - t0, f"{hop}, then {p.state}"))
                    hop = None
            continue
        if hop is not None and p.in_job:
            found.append((p.t - t0, f"{hop}, then {p.state}"))
            hop = None
        if metres >= MOVE_METRES and p.in_job and (p.has_waypoint or p.state in HOLDING_JOBS):
            found.append((p.t - t0, f"moved {metres:.0f} m as {p.state}, waypoint {p.wp}"))
            break

    for row in states:
        if row.get("to") not in WORKING_JOBS:
            continue
        after = [p for p in points if _t(row) <= p.t <= deadline and p.men > 0 and p.located]
        if not after:
            continue
        # A new job on paper isn't a recovery: the group has to go somewhere because of it.
        start = after[0]
        follow = next((p for p in after if p.has_waypoint and math.hypot(p.x - start.x, p.y - start.y) >= MOVE_METRES), None)
        if follow is not None:
            found.append((follow.t - t0, f"new job {row.get('to')} ({row.get('reason', '?')}), then moved with waypoint {follow.wp}"))
            break

    respawned = next((e for e in ladder if e.get("rung") == "respawn"), None)
    if respawned is not None and any(p.gone for p in points):
        found.append((_t(respawned) - t0, "last rung: the group was deleted and respawned at base"))

    if case in STAYS_PUT_CASES and info.get("state") in HOLDING_JOBS:
        seen = [p for p in points if p.t <= deadline and p.men > 0]
        if seen and seen[-1].state == info.get("state"):
            found.append((seen[-1].t - t0, f"was holding as {info.get('state')} and still is"))

    if not found:
        last = next((p for p in reversed(points) if p.t <= deadline and p.men > 0), None)
        where = f"last seen as {last.state}, waypoint {last.wp}, {last.men} men" if last else "never seen alive after it"
        return None, where
    if case == "sea":
        # Swimming about with a waypoint isn't recovering: it has to reach dry land, or be taken out by a logged move.
        dry = [p.t for p in points if t0 <= p.t <= deadline and p.men > 0 and p.located and p.wet is False]
        lifted = [_t(e) for e in ft] + [_t(e) for e in ladder if e.get("rung") in RELOCATING_RUNGS]
        out_at = min(dry + lifted, default=None)
        if out_at is None:
            return None, "still in the water, and no fast travel or relocating rung logged"
        found = [(max(seconds, out_at - t0), how) for seconds, how in found]
    found.sort(key=lambda f: f[0])
    return found[0]


def judge(data: Round, case: str) -> tuple[bool, str]:
    runs = [e for e in gs(data, "sabotage") if e.get("case") == case]
    if not runs:
        skipped = [e for e in gs(data, "skipped") if e.get("case") == case]
        return False, f"skipped: {skipped[0].get('why')}" if skipped else "the scenario never ran this case"
    info = runs[0]
    t0 = _t(info)
    side, group = info.get("side"), info.get("group")
    points = _points(data, case, t0)
    if not points:
        return False, f"{side} {group}: no track lines after t={t0:.0f}"
    seconds, how = recovery(case, info, points, data)
    deadline = t0 + RECOVERY_SECONDS
    ladder = [e.get("rung", "?") for e in _group_rows(data, "C_LADDER", side, group, t0, deadline)]
    head = f"{side} {group} (was {info.get('state')}, {info.get('men')} men) at t={t0:.0f}"
    tail = f"; rungs {ladder}" if ladder else ""
    if seconds is None:
        return False, f"{head}: not working again within {RECOVERY_SECONDS} s, {how}{tail}"
    ok = seconds <= RECOVERY_SECONDS
    extra = ""
    if case == "scatter":
        stragglers = _group_rows(data, "C_STRAGGLER", side, group, t0, deadline)
        spreads = [p.spread for p in points if p.men > 0 and p.located and p.t <= deadline]
        tightest = min(spreads, default=0)
        if not stragglers and tightest > SCATTER_RECOVERED_M:
            ok = False
        extra = f"; {len(stragglers)} straggler orders, furthest man closed to {tightest:.0f} m"
    if case == "script_error":
        logged = _group_rows(data, "C_GROUPERR", side, group, t0, deadline)
        if not logged:
            ok = False
        extra = f"; C_GROUPERR {len(logged)}, supervisor restarts {len(data.of('C_SUP'))}"
    return ok, f"{head}: working again after {seconds:.0f} s, {how}{tail}{extra}"


def finished(data: Round) -> tuple[bool, str]:
    done = gs(data, "done")
    ran = len(gs(data, "sabotage"))
    skipped = [e.get("case") for e in gs(data, "skipped")]
    return bool(done), f"{ran} of {len(CASES)} cases ran, skipped {skipped}, finished={bool(done)}"


def no_script_errors(data: Round) -> tuple[bool, str]:
    ours = _ours(data.script_errors)
    total = sum(e.count for e in ours)
    hook = [e for e in gs(data, "sabotage") if e.get("case") == "script_error"]
    fired = bool(hook) and bool(_group_rows(data, "C_GROUPERR", hook[0].get("side"), hook[0].get("group"), 0, 10**9))
    allowed = ALLOWED_INJECTED_ERRORS if fired else 0
    shown = "; ".join(f"{e.count}x {e.detail[:80]} [{e.file}]" for e in ours[:6])
    return total <= allowed, f"{total} errors in our scripts, {allowed} expected from the injected one" + (f": {shown}" if shown else "")


def ladder_counts(data: Round) -> str:
    rows = data.of("C_LADDER")
    if not rows:
        return "no C_LADDER lines"
    parts = []
    for side in sorted({e.get("side", "?") for e in rows}):
        counts = [f"{rung} {sum(1 for e in rows if e.get('side') == side and e.get('rung') == rung)}" for rung in LADDER_RUNGS]
        parts.append(f"{side}: " + ", ".join(counts))
    other = sorted({e.get("rung", "?") for e in rows} - set(LADDER_RUNGS))
    return "; ".join(parts) + (f"; other rungs logged {other}" if other else "")


def rungs_used(data: Round) -> tuple[bool, str]:
    sweeps = len([e for e in data.of("C_RES") if e.get("action") == "sweep"])
    return True, f"{ladder_counts(data)}; sweeps {sweeps}, supervisor restarts {len(data.of('C_SUP'))}, per-group errors {len(data.of('C_GROUPERR'))}"


# ---- soakr ----


@dataclass
class Stretch:
    """Time between two signs of progress, charged to the job the group was in."""

    start: int
    end: int
    x: float
    y: float
    job: str
    active: int = 0
    holds: dict[str, int] = field(default_factory=dict)


@dataclass
class SoakRow:
    group: Group
    stretches: list[Stretch]
    worst: Stretch | None = None
    worst_holds: dict[str, Stretch] = field(default_factory=dict)

    @property
    def stalled(self) -> bool:
        return self.worst is not None and self.worst.active > SOAK_MAX_NO_PROGRESS

    @property
    def over_limit(self) -> list[str]:
        return [job for job, s in self.worst_holds.items() if s.holds[job] > HOLD_LIMITS[job] + SAMPLE_SLACK_SECONDS]


def _state_rows(data: Round, group: Group) -> list[tuple[int, str, str]]:
    name = group.name.split(" ", 1)[-1]
    rows = [e for e in data.of("C_STATE") if e.get("side") == group.side and e.get("group") == name]
    return sorted(((int(_t(e)), e.get("from", "-"), e.get("to", "-")) for e in rows), key=lambda r: r[0])


def _distance(a: Sample, b: Sample) -> float:
    return math.hypot(a.x - b.x, a.y - b.y)


def stretches_for(data: Round, group: Group) -> list[Stretch]:
    """The group's life cut into stretches at every sign of progress."""
    samples = [s for s in group.samples if s.units > 0]
    while samples and samples[0].state == "-":
        samples = samples[1:]  # before the commander has picked the group up
    rows = _state_rows(data, group)
    out: list[Stretch] = []
    if not samples:
        return out

    def start(s: Sample) -> Stretch:
        return Stretch(s.t, s.t, s.x, s.y, s.state)

    current = start(samples[0])
    anchor = samples[0]
    combat_from = samples[0].t if samples[0].combat else None
    last_credit: tuple[int, str, str] | None = None
    previous = samples[0]
    for s in samples[1:]:
        if s.t - previous.t > SAMPLE_GAP_SECONDS:
            # Dead or gone between these two samples: that time isn't the group's fault.
            out.append(current)
            current, anchor, previous = start(s), s, s
            combat_from = s.t if s.combat else None
            continue
        step = s.t - previous.t
        job = previous.state
        if job in SOAK_HOLD_JOBS:
            current.holds[job] = current.holds.get(job, 0) + step
        elif job not in EXEMPT_JOBS:
            current.active += step

        credited = False
        for when, was, now in rows:
            if not previous.t < when <= s.t or now in NOT_PROGRESS_JOBS:
                continue
            bounced = last_credit is not None and now == last_credit[1] and was == last_credit[2] and when - last_credit[0] <= FLIP_FLOP_SECONDS
            if not bounced:
                credited = True
                last_credit = (when, was, now)

        if s.combat:
            combat_from = s.t if combat_from is None else combat_from
            fighting = s.t - combat_from <= MAX_COMBAT_CREDIT
        else:
            combat_from = None
            fighting = False

        current.end = s.t
        if credited or fighting or _distance(s, anchor) >= PROGRESS_METRES:
            out.append(current)
            current, anchor = start(s), s
        previous = s
    out.append(current)
    return [r for r in out if r.end > r.start]


def measure_soak(data: Round) -> list[SoakRow]:
    rows = []
    for group in data.groups.values():
        if not (group.is_ai and group.is_warlord) or all(s.state == "-" for s in group.samples):
            continue
        row = SoakRow(group, stretches_for(data, group))
        for stretch in row.stretches:
            if row.worst is None or stretch.active > row.worst.active:
                row.worst = stretch
            for job, seconds in stretch.holds.items():
                if job not in row.worst_holds or seconds > row.worst_holds[job].holds[job]:
                    row.worst_holds[job] = stretch
        rows.append(row)
    rows.sort(key=lambda r: (r.group.side, r.group.name))
    return rows


def _soak_line(data: Round, row: SoakRow) -> str:
    s = row.worst
    worst = "no judged time" if s is None else f"worst {fmt_time(s.active):>6} from {fmt_time(s.start)} to {fmt_time(s.end)} as {s.job} at {data.locate(s.x, s.y)}"
    return f"  {row.group.side:<5} {row.group.name:<14} {worst}  {'FAIL' if row.stalled else 'PASS'}"


def soak_no_stalls(data: Round) -> tuple[bool, str]:
    rows = measure_soak(data)
    if not rows:
        return False, "no commander groups in this round"
    bad = [r for r in rows if r.stalled]
    head = f"{len(rows) - len(bad)} of {len(rows)} commander groups never went {SOAK_MAX_NO_PROGRESS} s without progress"
    return not bad, "\n".join([head] + [_soak_line(data, r) for r in rows])


def soak_holds(data: Round) -> tuple[bool, str]:
    rows = measure_soak(data)
    if not rows:
        return False, "no commander groups in this round"
    lines = []
    bad = 0
    for row in rows:
        over = row.over_limit
        bad += bool(over)
        if row.worst_holds:
            jobs = ", ".join(f"{job} {fmt_time(s.holds[job])} from {fmt_time(s.start)}" + (" OVER" if job in over else "") for job, s in sorted(row.worst_holds.items()))
            lines.append(f"  {row.group.side:<5} {row.group.name:<14} {jobs}")
    limits = ", ".join(f"{job} {fmt_time(limit)}" for job, limit in HOLD_LIMITS.items())
    return bad == 0, "\n".join([f"longest hold per job per group, limits {limits} plus {SAMPLE_SLACK_SECONDS} s of sample slack; {bad} over"] + lines)


def respawn_rungs(data: Round) -> tuple[bool, str]:
    rows = data.of("C_LADDER")
    spawns = [e for e in rows if e.get("rung") == "respawn"]
    sides: dict[str, int] = {}
    refund = 0.0
    for e in spawns:
        sides[e.get("side", "?")] = sides.get(e.get("side", "?"), 0) + 1
        refund += _num(e, "refund")
    per_side = ", ".join(f"{side} {count}" for side, count in sorted(sides.items())) or "none"
    return True, f"respawn rungs used per side: {per_side}, {refund:.0f} CP refunded; all rungs: {ladder_counts(data)}"


def soak_overall(data: Round) -> tuple[bool, str]:
    stalls, _ = soak_no_stalls(data)
    holds, _ = soak_holds(data)
    ok = stalls and holds
    return ok, f"OVERALL {'PASS' if ok else 'FAIL'}: no-progress {'pass' if stalls else 'FAIL'}, holding limits {'pass' if holds else 'FAIL'}"


def _case_check(case: str) -> Callable[[Round], tuple[bool, str]]:
    def run(data: Round) -> tuple[bool, str]:
        return judge(data, case)

    return run


def register(check: Callable) -> None:
    for case, label in CASES:
        check(f"Part R: {label} ({case})", gate=GATE)(_case_check(case))
    check("Part R: the scenario ran to the end", gate=GATE)(finished)
    check("Part R: no script errors apart from the injected one", gate=GATE)(no_script_errors)
    check("Part R: ladder rungs and sweeps used", gate=GATE)(rungs_used)

    check(f"Soak R: no commander group goes {SOAK_MAX_NO_PROGRESS} s without progress", gate=SOAK_GATE)(soak_no_stalls)
    check("Soak R: groups holding on purpose stay inside their own limits", gate=SOAK_GATE)(soak_holds)
    check("Soak R: respawn rungs used", gate=SOAK_GATE)(respawn_rungs)
    check("Soak R: overall", gate=SOAK_GATE)(soak_overall)
