# User addition during the front line run (2026-11-09, about 19:03), verbatim

Addition for the rest of this run: make defence a first-class part of the commander, not an afterthought. Vanilla Warlords' biggest problem is that whoever wins the first big clash steamrolls the other side, because the AI only ever attacks. A lot of what's built already helps (economy, fortress base, pickets, proportionate response, commitment timer and rebuild, and this run's holdouts and defender fast travel), but it's mostly reactive. Fold the work below into your remaining plan where it fits best: build it alongside or after the related parts, reuse their scenario rounds and soaks where you can, and don't redo finished work. Save this text next to the run's prompt so it survives compaction, and log where you slotted each item.

## 1. A stance per side: attack, hold or rebuild
- Each commander picks a stance from relative strength: men alive, CP, armour and AT on each side, and recent wave outcomes. Use only what the side could know for the enemy's strength (the intel board), and its own real numbers.
- Attack: today's behaviour.
- Hold: the side is weaker. It stops throwing waves at a stronger enemy, keeps holdouts and pickets, fortifies its threatened sectors, buys for defence (AT, statics, infantry), and only makes small raids or probes.
- Rebuild: the side is badly beaten. It pulls back to defensible sectors, rebuilds strength and CP, and counterattacks when the balance has recovered.
- Switching needs hysteresis (thresholds plus a minimum time in a stance) so it doesn't flip back and forth. The existing commitment timer and rebuild logic should feed into or become part of this, not run alongside it.
- Show the stance on the commander panel and announce changes on the radio.

## 2. Defence starts when the enemy picks the target
- Warlords tells a side when one of its sectors becomes the enemy's target. Use that warning straight away, minutes before the enemy arrives.
- On the alert, send defenders to the targeted sector (respecting this run's defender fast travel rules), and set them up facing the most likely approach, predicted from the route network and the direction of the enemy's nearest sectors.
- Defenders take positions in buildings, at walls and treelines covering that approach, not in the middle of the sector. With LAMBS loaded, use its garrison.
- Balance against the attack: how many groups go depends on the side's stance and on the sector's value. A side in Attack sends a sensible minimum; a side in Hold or Rebuild defends properly.

## 3. Defenders fortify
- When a sector is threatened, the commander buys statics from Warlords' Defences category (MG, grenade launcher, AT where available and where the capability rules allow), within the CP reserve, and places them covering the predicted approach, on valid ground and facing the right way.
- Crew them from the defending groups, and keep them crewed as men die or rotate.
- AT soldiers in the defence cover roads and open approaches where vehicles will come.
- Don't buy statics for sectors that aren't threatened, and don't exceed a per-sector cap (tunable).

## 4. Defence in depth
Three layers for a threatened sector, all tunable:
- Screen: a small forward element (pickets or one group) on the approach, a few hundred metres out, to spot, report and slow the attack.
- Main position: the defenders in and around the sector, with the statics.
- Counterattack reserve: one or two groups held back out of contact, near the sector. When attackers break into the sector (seizing starts or attackers are inside), the reserve hits them straight away, since attackers who've just broken in are at their most vulnerable.
Fit this with the existing pickets, reserve and proportionate response rather than adding a parallel system.

## 5. Measure the steamroll
- Add to the analyser: which side won the first big clash (the first sector both sides fought over), whether that side won the round, how long the round lasted after it, and sectors lost by each side after it. Also report whether a comeback happened (the side that lost the first clash later retook a sector or held off an attack on one of its own).
- Compute it for every soak this run does, and for the stored vanilla baseline. Don't add soak rounds just for this metric beyond what you'd run anyway; one extra soak at most if there isn't enough data to say anything.
- Goal: comebacks and real defensive holds happen noticeably more than in vanilla, without rounds dragging on forever. Report the numbers either way.

## Same rules as the rest of the run
- Each behaviour gets its own switch and tunables in settings.sqf, default on. These are AI behaviour, so they stay on with the rules variant off, like resilience.
- Applies to both sides, including a side with human players. On a human side, the commander still defends with its own groups but never takes over players or their AI.
- Scenario checks where they're cheap: stance switches when one side is clearly weaker, and switches back when it recovers; defenders reach a newly targeted sector before the attackers and set up facing their approach; statics get bought, placed and crewed on a threatened sector; the counterattack reserve hits attackers who break in. Fold these into the scenario batches you're already running.
- Fold the new code into one of the run's existing code reviews rather than adding a separate one.
- Add the spec to docs/design/rules-variant.md and the decision log, add any new radio lines or panel text to the player-visible text list, and cover it in the hand-off and final message: what was built, gate results, the steamroll numbers against the baseline, and anything I should look out for when playing.
