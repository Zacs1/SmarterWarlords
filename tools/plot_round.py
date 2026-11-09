#!/usr/bin/env python3
"""Draws group positions over time for an automated Warlords round.

    python tools/plot_round.py <path-to-rpt> [--out plot.png] [--panels 6] [--heat] [--heat-out kills.png]

The left map shows the whole round, with time running from faint to solid along each track.
The panels on the right split the round into equal time windows so stalls and wandering show up.
--heat also writes a heat map of the kills (C_KILL lines) over the sectors and links, next to the log unless --heat-out is given.
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
from matplotlib.collections import LineCollection  # noqa: E402
from matplotlib.gridspec import GridSpec  # noqa: E402
from matplotlib.lines import Line2D  # noqa: E402
from matplotlib.colors import LinearSegmentedColormap, Normalize  # noqa: E402
from matplotlib.patches import Circle, Rectangle  # noqa: E402
from PIL import Image  # noqa: E402

sys.path.insert(0, str(Path(__file__).parent))

from gates_front import Kill, read_kills  # noqa: E402
from swl_log import Round, Sector, fmt_time, idle_stretches, jumps, parse_log  # noqa: E402

SURFACE = "#fcfcfb"
INK = "#2b2a27"
MUTED = "#73716b"
GRID = "#e6e4df"
SIDE_COLOURS = {"WEST": "#2a78d6", "EAST": "#eb6834", "GUER": "#8a8882"}
SIDE_LABELS = {"WEST": "BLUFOR", "EAST": "OPFOR", "GUER": "Independent"}
TRACK_SIDES = ("WEST", "EAST")
WORLD_SIZE_M = 15360
HEAT_CELL_M = 100.0
HEAT_RAMP = LinearSegmentedColormap.from_list("kills", ["#f0e3f5", "#b57ccb", "#7a3d96", "#3f1659"])
STOCK_MISSIONS = {"Tanoa": "MP_Warlords_03.Tanoa"}


def bounds(data: Round, margin: float = 250.0) -> tuple[float, float, float, float]:
    xs = [s.x for g in data.groups.values() for s in g.samples] + [s.x for s in data.sectors.values()]
    ys = [s.y for g in data.groups.values() for s in g.samples] + [s.y for s in data.sectors.values()]
    x0, x1, y0, y1 = min(xs) - margin, max(xs) + margin, min(ys) - margin, max(ys) + margin
    span = max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    return cx - span / 2, cx + span / 2, cy - span / 2, cy + span / 2


def owners_at(data: Round, t: float) -> dict[str, str]:
    owners = {name: sector.owner for name, sector in data.sectors.items()}
    for capture in data.captures:
        if capture.t <= t:
            owners[capture.sector] = capture.new
    return owners


def draw_sectors(ax, data: Round, t: float, labels: bool, capture_times: bool, square: bool = False) -> None:
    owners = owners_at(data, t)
    for name, sector in data.sectors.items():
        colour = SIDE_COLOURS.get(owners.get(name, "GUER"), SIDE_COLOURS["GUER"])
        if square:
            corner = (sector.x - sector.radius, sector.y - sector.radius)
            side = 2 * sector.radius
            ax.add_patch(Rectangle(corner, side, side, fill=False, edgecolor=colour, linewidth=1.4, zorder=4))
        else:
            ax.add_patch(Circle((sector.x, sector.y), sector.radius, facecolor=colour, alpha=0.14, edgecolor="none", zorder=1))
            ax.add_patch(Circle((sector.x, sector.y), sector.radius, fill=False, edgecolor=colour, linewidth=1.4, zorder=2))
        ax.plot(sector.x, sector.y, marker="s" if sector.base else "o", markersize=7 if sector.base else 5, color=colour, zorder=5)
        if labels:
            text = name
            if capture_times:
                taken = [c for c in data.captures if c.sector == name]
                if taken:
                    text += "\n" + ", ".join(f"{SIDE_LABELS.get(c.new, c.new)} {fmt_time(c.t)}" for c in taken)
            ax.annotate(
                text,
                (sector.x, sector.y),
                xytext=(0, 10),
                textcoords="offset points",
                ha="center",
                va="bottom",
                fontsize=8,
                color=INK,
                zorder=6,
                bbox=dict(boxstyle="round,pad=0.2", facecolor=SURFACE, edgecolor="none", alpha=0.8),
            )


def track_segments(group, t0: float, t1: float, split_jumps) -> list[np.ndarray]:
    """Consecutive on-map segments in the window, cut at fast-travel jumps so they are not drawn as walking."""
    jump_starts = {j.t_from for j in split_jumps}
    segments: list[list[tuple[float, float, float]]] = [[]]
    for sample in group.samples:
        if t0 <= sample.t <= t1:
            segments[-1].append((sample.x, sample.y, sample.t))
            if sample.t in jump_starts:
                segments.append([])
    return [np.array(s) for s in segments if len(s) >= 2]


def draw_tracks(ax, data: Round, t0: float, t1: float, fade: bool, line_width: float) -> None:
    for group in data.groups.values():
        if group.side not in TRACK_SIDES:
            continue
        colour = SIDE_COLOURS[group.side]
        group_jumps = jumps(data, group)
        for segment in track_segments(group, t0, t1, group_jumps):
            points = segment[:, :2].reshape(-1, 1, 2)
            parts = np.concatenate([points[:-1], points[1:]], axis=1)
            collection = LineCollection(parts, colors=colour, linewidths=line_width, zorder=3, capstyle="round")
            if fade:
                span = max(1.0, data.last_t)
                collection.set_alpha(list(0.2 + 0.8 * (segment[1:, 2] / span)))
            else:
                collection.set_alpha(0.85)
            ax.add_collection(collection)

        for jump in group_jumps:
            if t0 <= jump.t_to <= t1:
                ax.plot(
                    [jump.x_from, jump.x_to],
                    [jump.y_from, jump.y_to],
                    color=colour,
                    linewidth=0.8,
                    linestyle=(0, (1.5, 2.5)),
                    alpha=0.55,
                    zorder=2,
                )

        last = [s for s in group.samples if t0 <= s.t <= t1]
        if last:
            end = last[-1]
            ax.plot(end.x, end.y, marker="o", markersize=4.5, color=colour, markeredgecolor=SURFACE, markeredgewidth=0.8, zorder=4)

        for stretch in idle_stretches(group):
            overlap = min(stretch.end, t1) - max(stretch.start, t0)
            if overlap >= 180:
                size = 5 + min(overlap / 60.0, 20) * 0.9
                ax.plot(
                    stretch.x,
                    stretch.y,
                    marker="X",
                    markersize=size,
                    color=colour,
                    markeredgecolor=INK,
                    markeredgewidth=0.7,
                    alpha=0.9,
                    zorder=5,
                )


def reference_dir() -> Path | None:
    """The gitignored reference folder. A git worktree doesn't have one, so this looks up to the main checkout."""
    for folder in Path(__file__).resolve().parents:
        if (folder / "reference").is_dir():
            return folder / "reference"
    return None


def load_terrain():
    """The game's Tanoa overview from tools/extract-tanoa-map.ps1, or None if it hasn't been extracted."""
    root = reference_dir()
    path = root / "map" / "tanoa_picturemap.png" if root else None
    if path is None or not path.exists():
        return None
    return np.asarray(Image.open(path).convert("RGB"))


def draw_terrain(ax, terrain) -> None:
    if terrain is not None:
        ax.imshow(terrain, extent=(0, WORLD_SIZE_M, 0, WORLD_SIZE_M), origin="upper", alpha=0.45, zorder=0, interpolation="bilinear")


def style_axis(ax, limits, small: bool) -> None:
    ax.set_xlim(limits[0], limits[1])
    ax.set_ylim(limits[2], limits[3])
    ax.set_aspect("equal")
    ax.set_facecolor(SURFACE)
    ax.grid(True, color=GRID, linewidth=0.6, zorder=0)
    ax.set_axisbelow(True)
    for spine in ax.spines.values():
        spine.set_color(GRID)
    ax.tick_params(colors=MUTED, labelsize=6.5 if small else 8, length=0)
    if small:
        ax.set_xticklabels([])
        ax.set_yticklabels([])


def legend_handles() -> list[Line2D]:
    return [
        Line2D([], [], color=SIDE_COLOURS["WEST"], linewidth=2, label="BLUFOR group track"),
        Line2D([], [], color=SIDE_COLOURS["EAST"], linewidth=2, label="OPFOR group track"),
        Line2D([], [], color=INK, linewidth=0.9, linestyle=(0, (1.5, 2.5)), label="Fast travel or return to base"),
        Line2D([], [], color=INK, marker="o", markersize=4.5, linestyle="none", label="Last position"),
        Line2D([], [], color=INK, marker="X", markersize=8, linestyle="none", label="Idle 3+ min (bigger is longer)"),
        Line2D([], [], color=SIDE_COLOURS["GUER"], marker="o", markersize=5, linestyle="none", label="Sector (colour = owner)"),
        Line2D([], [], color=SIDE_COLOURS["GUER"], marker="s", markersize=6, linestyle="none", label="Base"),
    ]


def sector_links(data: Round) -> list[tuple[Sector, Sector]]:
    """Warlords' sector links, read from the stock mission's editor syncs. Empty if that mission isn't available."""
    root = reference_dir()
    world = (data.start or {}).get("world", "")
    if root is None or world not in STOCK_MISSIONS:
        return []
    path = root / "missions_f_warlords" / "MPScenarios" / STOCK_MISSIONS[world] / "mission.sqm"
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8", errors="replace")
    by_id: dict[str, Sector] = {}
    for module in re.finditer(r'type="ModuleWL(?:Sector|Base)_F"', text):
        before = text[max(0, module.start() - 400) : module.start()]
        position = re.findall(r"position\[\]=\{([-\d.]+),[-\d.]+,([-\d.]+)\}", before)
        ids = re.findall(r"\bid=(\d+);", before)
        if not position or not ids:
            continue
        x, y = float(position[-1][0]), float(position[-1][1])
        near = [s for s in data.sectors.values() if math.hypot(s.x - x, s.y - y) < 30]
        if near:
            by_id[ids[-1]] = near[0]
    pairs = re.findall(r'item0=(\d+);\s*item1=(\d+);\s*class CustomData\s*\{\s*type="Sync";', text)
    return [(by_id[a], by_id[b]) for a, b in pairs if a in by_id and b in by_id]


def draw_links(ax, links: list[tuple[Sector, Sector]]) -> None:
    for a, b in links:
        ax.plot([a.x, b.x], [a.y, b.y], color=INK, linewidth=1.0, alpha=0.55, zorder=2, solid_capstyle="round")


def heat_bounds(data: Round, kills: list[Kill], margin: float = 350.0) -> tuple[float, float, float, float]:
    xs = [k.x for k in kills] + [s.x for s in data.sectors.values()]
    ys = [k.y for k in kills] + [s.y for s in data.sectors.values()]
    span = max(max(xs) - min(xs), max(ys) - min(ys)) + 2 * margin
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    return cx - span / 2, cx + span / 2, cy - span / 2, cy + span / 2


def heat_cells(ax, kills: list[Kill], limits, **style):
    """Counts kills per hexagon about HEAT_CELL_M across, on one lattice for every panel. Empty cells stay clear."""
    size = max(1, int((limits[1] - limits[0]) / HEAT_CELL_M))
    return ax.hexbin([k.x for k in kills], [k.y for k in kills], gridsize=size, extent=limits, mincnt=1, **style)


def draw_heat(ax, kills: list[Kill], limits, vmax: float) -> None:
    if kills:
        heat_cells(ax, kills, limits, cmap=HEAT_RAMP, norm=Normalize(vmin=1, vmax=vmax), linewidths=0, zorder=3)


def peak_count(kills: list[Kill], limits) -> int:
    """The count in the busiest cell, so one colour scale fits a group of panels."""
    if not kills:
        return 1
    figure, ax = plt.subplots()
    peak = int(heat_cells(ax, kills, limits).get_array().max())
    plt.close(figure)
    return max(peak, 2)


def heat_colourbar(figure, axes, vmax: int, label: str, fraction: float) -> None:
    bar = figure.colorbar(plt.cm.ScalarMappable(norm=Normalize(vmin=1, vmax=vmax), cmap=HEAT_RAMP), ax=axes, fraction=fraction, pad=0.01)
    bar.set_label(label, fontsize=8, color=MUTED)
    bar.ax.tick_params(colors=MUTED, labelsize=7, length=0)
    bar.outline.set_visible(False)


def write_heat_map(data: Round, kills: list[Kill], out: Path, panels: int) -> None:
    end = max(data.last_t, kills[-1].t, 1)
    limits = heat_bounds(data, kills)
    links = sector_links(data)
    terrain = load_terrain()
    window = end / panels
    slices = [[k for k in kills if index * window <= k.t < (index + 1) * window or (index == panels - 1 and k.t >= end)] for index in range(panels)]
    whole_peak = peak_count(kills, limits)
    panel_peak = max(peak_count(chunk, limits) for chunk in slices)

    columns = max(1, round(panels / 2))
    figure = plt.figure(figsize=(10 + 3.2 * columns, 9.6), facecolor=SURFACE)
    # The narrow third column keeps the whole-round colour bar and its label clear of the panels.
    grid = GridSpec(2, 3 + columns, figure=figure, width_ratios=[1.45, 1.45, 0.22] + [1] * columns, wspace=0.08, hspace=0.12)

    def base(ax, t: float, small: bool, labels: bool) -> None:
        draw_terrain(ax, terrain)
        style_axis(ax, limits, small=small)
        draw_links(ax, links)
        draw_sectors(ax, data, t, labels=labels, capture_times=labels, square=True)

    main_ax = figure.add_subplot(grid[:, :2])
    base(main_ax, end, small=False, labels=True)
    draw_heat(main_ax, kills, limits, whole_peak)
    main_ax.set_title(f"Whole round: {len(kills)} kills, cells about {HEAT_CELL_M:.0f} m across", fontsize=10, color=INK, loc="left")
    main_ax.set_xlabel("Tanoa x (m)", fontsize=8, color=MUTED)
    main_ax.set_ylabel("Tanoa y (m)", fontsize=8, color=MUTED)
    main_ax.legend(
        handles=[
            Line2D([], [], color=INK, linewidth=1.0, alpha=0.55, label="Sector link"),
            Line2D([], [], color=SIDE_COLOURS["GUER"], marker="s", markersize=9, markerfacecolor="none", linestyle="none", label="Capture area (colour = owner)"),
        ],
        loc="upper center",
        bbox_to_anchor=(0.5, -0.07),
        ncol=2,
        fontsize=7.5,
        frameon=False,
    )
    heat_colourbar(figure, main_ax, whole_peak, "Kills per cell, whole round", 0.035)

    panel_axes = []
    for index, chunk in enumerate(slices):
        t0, t1 = index * window, (index + 1) * window
        ax = figure.add_subplot(grid[index % 2, 3 + index // 2])
        base(ax, t1, small=True, labels=False)
        draw_heat(ax, chunk, limits, panel_peak)
        ax.set_title(f"{fmt_time(t0)} to {fmt_time(t1)}: {len(chunk)} kills", fontsize=9, color=INK, loc="left")
        panel_axes.append(ax)
    heat_colourbar(figure, panel_axes, panel_peak, "Kills per cell, each window", 0.02)

    mission = data.start.get("mission") if data.start else "?"
    figure.suptitle(f"Where the kills happened: {mission}, {fmt_time(end)}", fontsize=12, color=INK, x=0.5, y=0.97)
    figure.savefig(out, dpi=130, facecolor=SURFACE, bbox_inches="tight")
    plt.close(figure)
    print(f"Kill heat map: {out}" + ("" if links else " (no sector links available)"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("log", type=Path)
    parser.add_argument("--out", type=Path, default=None, help="Output PNG. Default: next to the log.")
    parser.add_argument("--panels", type=int, default=6, help="Number of time windows (default 6)")
    parser.add_argument("--heat", action="store_true", help="Also write a heat map of the kills over the sectors and links")
    parser.add_argument("--heat-out", type=Path, default=None, help="Output PNG for the heat map. Default: next to the log.")
    args = parser.parse_args()

    data = parse_log(args.log)
    if not data.groups or not data.sectors:
        print("No group or sector data in this log, so there is nothing to plot.")
        return 1

    out = args.out or args.log.with_suffix(".plot.png")
    limits = bounds(data)
    end = max(data.last_t, 1)

    columns = max(1, round(args.panels / 2))
    rows = 2
    figure = plt.figure(figsize=(9 + 3.2 * columns, 9.6), facecolor=SURFACE)
    grid = GridSpec(rows, 2 + columns, figure=figure, width_ratios=[1.45, 1.45] + [1] * columns, wspace=0.08, hspace=0.12)

    terrain = load_terrain()

    main_ax = figure.add_subplot(grid[:, :2])
    draw_terrain(main_ax, terrain)
    style_axis(main_ax, limits, small=False)
    draw_sectors(main_ax, data, end, labels=True, capture_times=True)
    draw_tracks(main_ax, data, 0, end, fade=True, line_width=1.3)
    main_ax.set_title("Whole round: track fades from faint (early) to solid (late)", fontsize=10, color=INK, loc="left")
    main_ax.set_xlabel("Tanoa x (m)", fontsize=8, color=MUTED)
    main_ax.set_ylabel("Tanoa y (m)", fontsize=8, color=MUTED)
    main_ax.legend(
        handles=legend_handles(),
        loc="upper center",
        bbox_to_anchor=(0.5, -0.07),
        ncol=4,
        fontsize=7.5,
        frameon=False,
    )

    window = end / args.panels
    for index in range(args.panels):
        t0, t1 = index * window, (index + 1) * window
        ax = figure.add_subplot(grid[index % rows, 2 + index // rows])
        draw_terrain(ax, terrain)
        style_axis(ax, limits, small=True)
        draw_sectors(ax, data, t1, labels=False, capture_times=False)
        draw_tracks(ax, data, t0, t1, fade=False, line_width=1.1)
        ax.set_title(f"{fmt_time(t0)} to {fmt_time(t1)}", fontsize=9, color=INK, loc="left")

    outcome = f"winner {data.round_end.get('winner')}" if data.round_end else "no round end in log"
    figure.suptitle(
        f"Warlords round: {data.start.get('mission') if data.start else '?'} on Tanoa, "
        f"{fmt_time(end)} observed, {len(data.captures)} captures, {outcome}",
        fontsize=12,
        color=INK,
        x=0.5,
        y=0.97,
    )
    figure.savefig(out, dpi=130, facecolor=SURFACE, bbox_inches="tight")
    print(f"Plot: {out}")

    if args.heat or args.heat_out:
        kills, _ = read_kills(data)
        if kills:
            write_heat_map(data, kills, args.heat_out or args.log.with_suffix(".kills.png"), args.panels)
        else:
            print("Kill heat map: no data (no C_KILL lines in this log)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
