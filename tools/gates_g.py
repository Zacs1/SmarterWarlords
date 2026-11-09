"""Part G gates, read from a soak round's log. Gate name: partg."""
from __future__ import annotations


def register(check) -> None:
    @check("G Choices favour capability and supply sectors over chance", gate="partg")
    def choices(data):
        targets = data.of("C_TARGET")

        def became_target(r):
            return any(t.get("side") == r.get("side") and t.get("target") == r.get("sector") and 0 <= int(t["t"]) - int(r["t"]) <= 90 for t in targets)

        rows = [r for r in data.of("C_STRAT") if r.get("event") == "choice" and int(r.get("options", "0")) >= 2]
        # A vote where every option is worth the same says nothing, and a pick the side never took wasn't a choice.
        rows = [r for r in rows if float(r["max"]) > float(r["mean"]) + 0.05 and became_target(r)]
        if len(rows) < 3:
            return False, f"only {len(rows)} real choices between sectors of different worth, need 3"
        above = sum(1 for r in rows if float(r["worth"]) > float(r["mean"]))
        at_top = sum(1 for r in rows if float(r["worth"]) >= float(r["max"]) - 0.05)
        chance_above = sum(float(r.get("share_above", "0.5")) for r in rows)
        chance_top = sum(float(r.get("share_top", "0.5")) for r in rows)
        ok = at_top > chance_top * 1.25 or above > chance_above * 1.25
        return ok, f"{len(rows)} choices: {at_top} the most valuable on offer (chance {chance_top:.1f}), {above} above the mean (chance {chance_above:.1f})"

    @check("G Raids and probes happen at a sensible rate", gate="partg")
    def rate(data):
        raids = [r for r in data.of("C_RAID") if r.get("event") == "start"]
        probes = [r for r in data.of("C_PROBE") if r.get("event") == "sent"]
        minutes = max(1.0, data.last_t / 60.0)
        ok = len(probes) >= 1 and (minutes < 30 or len(raids) >= 1) and len(raids) <= minutes / 8 + 2 and len(probes) <= minutes / 2
        return ok, f"{len(raids)} raids and {len(probes)} probes in {minutes:.0f} minutes"

    @check("G No deadlock outlasts the commitment timer", gate="partg")
    def deadlock(data):
        # Measured from when each target was set, so a target nobody ever decided about still counts.
        sieges = {(r.get("side"), r.get("target")) for r in data.of("C_COMMIT") if r.get("decision") == "stay_no_alternative"}
        longest = 0
        which = "-"
        for side in ("WEST", "EAST"):
            rows = [r for r in data.of("C_TARGET") if r.get("side") == side]
            for i, row in enumerate(rows):
                if row.get("target") == "-" or (side, row.get("target")) in sieges:
                    continue
                end = int(rows[i + 1]["t"]) if i + 1 < len(rows) else data.last_t
                if end - int(row["t"]) > longest:
                    longest = end - int(row["t"])
                    which = f"{side} on {row.get('target')}"
        limit = 660 + 2 * 180 + 30
        return longest <= limit, f"longest on one target {longest} s ({which}), limit {limit} s; final sieges with no alternative are exempt: {len(sieges)}"
