"""Parser for the SWL| lines the test observer writes to an Arma RPT. Format: tests/README.md."""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, field
from pathlib import Path

IDLE_RADIUS_M = 30.0
IDLE_MIN_SECONDS = 180
FT_JUMP_M = 400.0
FT_MAX_GAP_S = 45
BASE_RADIUS_M = 300.0

_ERROR_START = re.compile(r"Error in expression")
_ERROR_DETAIL = re.compile(r"\bError (?!in expression|position)(.+)$")
_ERROR_FILE = re.compile(r"\bFile (.+?)(?:\.\.\.)?, line (\d+)")
_WARNING_MESSAGE = re.compile(r"Warning Message: (.+)$")
_PLACEHOLDER_NAME = re.compile(r"(?i)^sector_")


def _num(value: str | None) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


@dataclass
class Sample:
    t: int
    x: float
    y: float
    units: int
    combat: bool
    behaviour: str
    vehicle: str
    leader: str
    wp: str
    warlord: bool


@dataclass
class Group:
    id: str
    name: str
    side: str
    samples: list[Sample] = field(default_factory=list)

    @property
    def is_ai(self) -> bool:
        return all(s.leader == "ai" for s in self.samples)

    @property
    def is_warlord(self) -> bool:
        return any(s.warlord for s in self.samples)

    def max_displacement(self) -> float:
        first = self.samples[0]
        return max(dist(first, s) for s in self.samples)


@dataclass
class Sector:
    name: str
    x: float
    y: float
    base: bool
    owner: str
    size: float = -1.0

    @property
    def radius(self) -> float:
        return self.size / 2 if self.size > 0 else 150.0


@dataclass
class Capture:
    t: int
    sector: str
    old: str
    new: str
    x: float
    y: float
    base: bool


@dataclass
class Target:
    t: int
    side: str
    sector: str


@dataclass
class Tick:
    t: int
    fields: dict[str, str]


@dataclass
class Stretch:
    start: int
    end: int
    x: float
    y: float
    combat_fraction: float

    @property
    def seconds(self) -> int:
        return self.end - self.start


@dataclass
class Jump:
    t_from: int
    t_to: int
    x_from: float
    y_from: float
    x_to: float
    y_to: float
    kind: str  # "fast_travel" or "base_return"

    @property
    def metres(self) -> float:
        return math.hypot(self.x_to - self.x_from, self.y_to - self.y_from)


@dataclass
class ScriptError:
    detail: str
    file: str
    count: int = 1


@dataclass
class Round:
    path: Path
    start: dict[str, str] | None = None
    groups: dict[str, Group] = field(default_factory=dict)
    ticks: list[Tick] = field(default_factory=list)
    sectors: dict[str, Sector] = field(default_factory=dict)
    captures: list[Capture] = field(default_factory=list)
    targets: list[Target] = field(default_factory=list)
    round_end: dict[str, str] | None = None
    ended: list[dict[str, str]] = field(default_factory=list)
    script_errors: list[ScriptError] = field(default_factory=list)
    warnings: dict[str, int] = field(default_factory=dict)
    extra_starts: int = 0

    @property
    def last_t(self) -> int:
        return self.ticks[-1].t if self.ticks else 0

    def groups_on(self, side: str) -> list[Group]:
        return [g for g in self.groups.values() if g.side == side]

    def base_of(self, side: str) -> Sector | None:
        owner_at_start = [s for s in self.sectors.values() if s.base and s.owner == side]
        if owner_at_start:
            return owner_at_start[0]
        token = "BLUFOR" if side == "WEST" else "OPFOR"
        named = [s for s in self.sectors.values() if s.base and token in s.name]
        return named[0] if named else None

    def locate(self, x: float, y: float) -> str:
        """Names the sector a point is inside, or gives the coordinates."""
        best = None
        for sector in self.sectors.values():
            d = math.hypot(sector.x - x, sector.y - y)
            if d <= sector.radius + 100 and (best is None or d < best[0]):
                best = (d, sector.name)
        return best[1] if best else f"open ground {round(x)},{round(y)}"


def dist(a, b) -> float:
    return math.hypot(a.x - b.x, a.y - b.y)


def _fields(parts: list[str]) -> dict[str, str]:
    out = {}
    for part in parts:
        key, sep, value = part.partition("=")
        if sep:
            out[key] = value
    return out


def parse_log(path: str | Path) -> Round:
    """Reads one round. If the server restarted the mission, only the first round is kept."""
    path = Path(path)
    data = Round(path=path)
    errors: dict[tuple[str, str], ScriptError] = {}
    by_pos: dict[tuple[float, float], Sector] = {}
    aliases: dict[str, tuple[float, float]] = {}
    in_first_round = True
    pending: dict | None = None
    pending_left = 0

    def close_pending() -> None:
        nonlocal pending
        if pending is None:
            return
        key = (pending["detail"], pending["file"])
        if key in errors:
            errors[key].count += 1
        else:
            errors[key] = ScriptError(pending["detail"], pending["file"])
        pending = None

    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            line = raw.rstrip("\r\n")

            if pending is not None:
                detail = _ERROR_DETAIL.search(line)
                source = _ERROR_FILE.search(line)
                if detail and pending["detail"] == "?":
                    pending["detail"] = detail.group(1).strip()
                if source:
                    pending["file"] = f"{source.group(1)}:{source.group(2)}"
                pending_left -= 1
                if pending_left <= 0:
                    close_pending()

            if _ERROR_START.search(line):
                close_pending()
                pending = {"detail": "?", "file": "?"}
                pending_left = 6
                continue

            warning = _WARNING_MESSAGE.search(line)
            if warning:
                text = warning.group(1).strip()
                data.warnings[text] = data.warnings.get(text, 0) + 1

            index = line.find("SWL|")
            if index < 0:
                continue
            parts = line[index:].split("|")
            if len(parts) < 3:
                continue
            kind = parts[1]
            fields = _fields(parts[2:])

            if kind == "START":
                if data.start is None:
                    data.start = fields
                else:
                    data.extra_starts += 1
                    in_first_round = False
                continue
            if not in_first_round:
                continue

            t = int(_num(fields.get("t")) or 0)

            if kind == "TICK":
                data.ticks.append(Tick(t, fields))
            elif kind == "GRP":
                group = data.groups.get(fields["id"])
                if group is None:
                    group = Group(fields["id"], fields.get("name", "?"), fields.get("side", "?"))
                    data.groups[fields["id"]] = group
                group.samples.append(
                    Sample(
                        t=t,
                        x=_num(fields.get("x")) or 0.0,
                        y=_num(fields.get("y")) or 0.0,
                        units=int(_num(fields.get("units")) or 0),
                        combat=fields.get("combat") == "1",
                        behaviour=fields.get("beh", "?"),
                        vehicle=fields.get("veh", "-"),
                        leader=fields.get("leader", "?"),
                        wp=fields.get("wp", "?"),
                        warlord=fields.get("warlord") == "1",
                    )
                )
            elif kind in ("SECTORINIT", "SEC"):
                # A sector can gain its location name during the round, so position is its identity.
                name = fields["name"]
                pos = (_num(fields.get("x")) or 0.0, _num(fields.get("y")) or 0.0)
                sector = by_pos.get(pos)
                if sector is None:
                    sector = Sector(
                        name=name,
                        x=pos[0],
                        y=pos[1],
                        base=fields.get("base") == "1",
                        owner=fields.get("owner", "?"),
                        size=_num(fields.get("size")) or -1.0,
                    )
                    by_pos[pos] = sector
                if sector.size < 0 and fields.get("size"):
                    sector.size = _num(fields.get("size")) or -1.0
                aliases[name] = pos
                if not _PLACEHOLDER_NAME.match(name):
                    sector.name = name
            elif kind == "CAPTURE":
                pos = (_num(fields.get("x")) or 0.0, _num(fields.get("y")) or 0.0)
                if pos in by_pos:
                    aliases[fields.get("sector", "?")] = pos
                data.captures.append(
                    Capture(
                        t=t,
                        sector=fields.get("sector", "?"),
                        old=fields.get("from", "?"),
                        new=fields.get("to", "?"),
                        x=_num(fields.get("x")) or 0.0,
                        y=_num(fields.get("y")) or 0.0,
                        base=fields.get("base") == "1",
                    )
                )
            elif kind == "TARGET":
                data.targets.append(Target(t, fields.get("side", "?"), fields.get("sector", "-")))
            elif kind == "ROUNDEND":
                if data.round_end is None:
                    data.round_end = fields
            elif kind == "ENDED":
                data.ended.append(fields)

    close_pending()
    data.script_errors = list(errors.values())

    def canonical(name: str) -> str:
        pos = aliases.get(name)
        return by_pos[pos].name if pos is not None else name

    data.sectors = {sector.name: sector for sector in by_pos.values()}
    for capture in data.captures:
        capture.sector = canonical(capture.sector)
        sector = data.sectors.get(capture.sector)
        if sector is not None:
            capture.x, capture.y = sector.x, sector.y
    for target in data.targets:
        target.sector = canonical(target.sector)
    for tick in data.ticks:
        for key in ("west_target", "east_target"):
            if key in tick.fields:
                tick.fields[key] = canonical(tick.fields[key])
    return data


def idle_stretches(group: Group) -> list[Stretch]:
    """Maximal stretches where the leader stays within IDLE_RADIUS_M of the stretch's first sample."""
    samples = group.samples
    out: list[Stretch] = []
    i = 0
    while i < len(samples):
        j = i
        while j + 1 < len(samples) and dist(samples[i], samples[j + 1]) <= IDLE_RADIUS_M:
            j += 1
        seconds = samples[j].t - samples[i].t
        if seconds >= IDLE_MIN_SECONDS:
            window = samples[i : j + 1]
            combat = sum(1 for s in window if s.combat) / len(window)
            out.append(Stretch(samples[i].t, samples[j].t, samples[i].x, samples[i].y, combat))
            i = j + 1
        else:
            i += 1
    return out


def jumps(data: Round, group: Group) -> list[Jump]:
    """On-foot position jumps too long to walk between two samples: fast travel or a return to base."""
    base = data.base_of(group.side)
    out: list[Jump] = []
    for a, b in zip(group.samples, group.samples[1:]):
        if a.vehicle != "-" or b.vehicle != "-":
            continue
        if b.t - a.t > FT_MAX_GAP_S or dist(a, b) < FT_JUMP_M:
            continue
        kind = "fast_travel"
        if base is not None and math.hypot(b.x - base.x, b.y - base.y) <= BASE_RADIUS_M:
            kind = "base_return"
        out.append(Jump(a.t, b.t, a.x, a.y, b.x, b.y, kind))
    return out


def fmt_time(seconds: float) -> str:
    seconds = int(seconds)
    return f"{seconds // 60}:{seconds % 60:02d}"
