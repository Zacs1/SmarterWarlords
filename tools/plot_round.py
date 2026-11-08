#!/usr/bin/env python3
"""Draws group positions over time for an automated Warlords round.

    python tools/plot_round.py <path-to-rpt> [--out plot.png] [--panels 6]

The left map shows the whole round, with time running from faint to solid along each track.
The panels on the right split the round into equal time windows so stalls and wandering show up.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
from matplotlib.collections import LineCollection  # noqa: E402
from matplotlib.gridspec import GridSpec  # noqa: E402
from matplotlib.lines import Line2D  # noqa: E402
from matplotlib.patches import Circle  # noqa: E402
from PIL import Image  # noqa: E402

sys.path.insert(0, str(Path(__file__).parent))

from swl_log import Round, fmt_time, idle_stretches, jumps, parse_log  # noqa: E402

SURFACE = "#fcfcfb"
INK = "#2b2a27"
MUTED = "#73716b"
GRID = "#e6e4df"
SIDE_COLOURS = {"WEST": "#2a78d6", "EAST": "#eb6834", "GUER": "#8a8882"}
SIDE_LABELS = {"WEST": "BLUFOR", "EAST": "OPFOR", "GUER": "Independent"}
TRACK_SIDES = ("WEST", "EAST")
WORLD_SIZE_M = 15360


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


def draw_sectors(ax, data: Round, t: float, labels: bool, capture_times: bool) -> None:
    owners = owners_at(data, t)
    for name, sector in data.sectors.items():
        colour = SIDE_COLOURS.get(owners.get(name, "GUER"), SIDE_COLOURS["GUER"])
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


def load_terrain():
    """The game's Tanoa overview from tools/extract-tanoa-map.ps1, or None if it hasn't been extracted."""
    path = Path(__file__).parent.parent / "reference" / "map" / "tanoa_picturemap.png"
    if not path.exists():
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("log", type=Path)
    parser.add_argument("--out", type=Path, default=None, help="Output PNG. Default: next to the log.")
    parser.add_argument("--panels", type=int, default=6, help="Number of time windows (default 6)")
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
    return 0


if __name__ == "__main__":
    sys.exit(main())
