# Steamroll analyser (prompt-defence.md section 5)

`tools/gates_steamroll.py`, registered with `tools/analyse_round.py` as `--gate steamroll`.

    python tools/gates_steamroll.py <rpt> [<rpt> ...]
    python tools/gates_steamroll.py --compare <baseline rpts> --variant <variant rpts>
    python tools/analyse_round.py <rpt> --gate steamroll

There is no pass threshold. The registered check always passes when the numbers were produced, and its name says so. The comeback result is in the detail. A check that failed on "no comeback" would make `--gate steamroll` exit 1 on a round the user only wanted numbers for.

## Definitions

These are printed by every report, and live in `DEFINITIONS` at the top of the file.

- **stake**: a side owns the sector or is targeting it. A target dropped and picked again within 120 s is one attack.
- **contact**: one GRP pass with a living group of each side within 200 m of the sector's square, both with a stake. It counts if another contact pass or a capture of the sector follows within 90 s.
- **clash**: starts at the first contact on a sector. Decided by, in order: a side captures it during the attack (that side wins); the sector belonged to a side and the attacker's target moved on (the owner wins); otherwise undecided.
- **first clash**: the earliest decided clash. Earlier undecided ones are listed, not used.
- **after it**: counted from the moment the clash was decided. The clash's own capture isn't counted.
- **sector lost**: a CAPTURE from that side, plus a base that falls at ROUNDEND, because no CAPTURE is logged for it.
- **retook**: the first-clash loser captures a sector from the first-clash winner, whoever held it before.
- **held off**: a sector the loser owned was the winner's target for at least 300 s after the clash, with attackers near it in at least 4 GRP passes, and the attack ended without the sector falling. An attack still going at the end of the log is not a hold.
- **comeback**: retook or held off at least once, after the clash.

C_KILL is not part of any definition, so a log without it is judged the same way as one with it. When present, kills between the sides at the clash are printed for reference.

## Output on the four real logs

Run on 2026-11-09, definitions block left out.

```
== arma3server_x64_2026-11-08_19-26-57.rpt ==   (2026-11-08_19-26-56_baseline, stored vanilla baseline)
round: 70:26, won by WEST (1 later mission start(s) in this log ignored, first round only)
first clash: Balavu, contact from 9:03, decided at 50:14 (WEST captured it from GUER)
first clash winner: WEST, loser EAST
winner of the first clash won the round: yes
time after the clash: 20:12
sectors lost after the clash: WEST 0; EAST 2 (Leqa 58:10, OPFOR Base 70:26)
comeback: no
reference, kills between the sides at the clash: no data (no C_KILL lines)

== arma3server_x64_2026-11-09_17-00-36.rpt ==   (2026-11-09_17-00-36_soakfinal)
round: log ends at 89:51, no winner recorded
first clash: Balavu, contact from 49:42, decided at 63:59 (WEST moved its target on, EAST kept the sector)
first clash winner: EAST, loser WEST
winner of the first clash won the round: no winner
time after the clash: 25:52 (to the end of the log, the round had not finished)
sectors lost after the clash: WEST 1 (Rautake 76:46); EAST 0
comeback: no
  Laikoro was still the enemy's target when the log stopped, so it doesn't count either way
reference, kills between the sides at the clash: no data (no C_KILL lines)

== arma3server_x64_2026-11-09_18-30-51.rpt ==   (2026-11-09_18-30-51_basevanilla)
round: log ends at 29:36, no winner recorded
first clash: no data, both sides were never in contact over a sector they both had a stake in
first clash winner: no data
winner of the first clash won the round: no data
time after the clash: no data
sectors lost after the clash: no data
comeback: no data

== arma3server_x64_2026-11-09_18-31-01.rpt ==   (2026-11-09_18-31-01_basecurrent)
round: log ends at 29:37, no winner recorded
first clash: no data, both sides were never in contact over a sector they both had a stake in
  for reference: groups of both sides were near Sector_2665_7345 in 8 GRP passes from 23:36, but never in sustained contact while both had a stake in it
first clash winner: no data
winner of the first clash won the round: no data
time after the clash: no data
sectors lost after the clash: no data
comeback: no data
```

Compare mode, baseline and basevanilla against soakfinal and basecurrent, to show the format only:

```
== Baseline ==
  rounds: 2, with a first clash verdict: 1
  comeback rate: 0/1 (0%)
  winner of the first clash won the round: 1/1 (100%), of rounds that had a winner; rounds with no winner 0
  median round length after the clash: 20:12
  median sectors lost by the first-clash loser: 2

== Variant ==
  rounds: 2, with a first clash verdict: 1
  comeback rate: 0/1 (0%)
  winner of the first clash won the round: no data, of rounds that had a winner; rounds with no winner 1
  median round length after the clash: 25:52 (1 of 1 stop at the end of the log, so they are minimum lengths)
  median sectors lost by the first-clash loser: 1
```

## Checks on the results

- soakfinal: a capture-only reading would put the first clash at Rautake (76:46, the only change between the sides). The real first fight is WEST's attack on EAST-held Balavu from 49:42: 1 to 5 WEST groups against 5 to 10 EAST groups, and at the last contact pass 1 against 10.
- soakfinal: EAST targeted BLUFOR Base from 77:02 to 88:20 and is correctly not a hold for WEST. No EAST group came within 200 m of its square in any GRP pass of that attack.
- basecurrent: "no data" is deliberate. EAST dropped Sector_2665_7345 at 20:25 and picked another target at 20:43, so the 1 or 2 EAST groups near WEST's attack from 23:36 no longer had a stake. C_KILL fits this: no WEST-EAST kills anywhere in that log.
- basevanilla: groups of the two sides never came near the same sector, and C_KILL also has no WEST-EAST kills.
- The observer writes one GRP pass across a second or two (t=92 and t=93), so samples within 5 s are treated as one pass. Matching on exact t would miss contacts.
- Comeback paths aren't reached by any of the four real logs, so they were exercised with synthetic RPTs in the session scratchpad (not committed): retake, hold, a too-short attack that isn't a hold, target re-picked within the merge gap, defender win, undecided, a pass split across seconds, a single-pass drive-by, and an empty log. All gave the expected result.

## Limits

- Four logs is too few to say anything about steamrolling. Two have no verdict, and the numbers above show the analyser works, nothing more.
- 30-minute rounds usually end before the sides meet. They'll mostly report "no data", so comparisons need the longer soaks.
- Rounds with no winner have a "time after the clash" that is only a minimum, because the log stops. Compare mode says how many of those are in the median.
- GRP gives the leader's position every 30 s or so, so "near" means groups were close, not that they fought. Where C_KILL exists its kill count is printed beside the clash, and a clash with none is flagged.
- A "won" clash on a neutral sector means that side captured it. It doesn't say who won the firefight.
- A hold doesn't require defenders to be there. The defender pass count is printed so a reader can discount a hold where the attackers simply left.
- "retook" includes the winner's base falling at ROUNDEND, and any sector taken from the winner even if the loser never held it.
- Only the first round in an RPT is read (`parse_log` behaviour). The report says when a log held more.
- A second attack on the same sector more than 120 s after the first is a separate attack. In soakfinal, WEST's return to Balavu at 68:18 is not part of the first clash.
- `analyse_round.py`'s exit code also reflects its other checks, so a non-zero exit there isn't about this gate.
