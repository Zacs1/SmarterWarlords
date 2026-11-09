# Player-visible text

Read from the code in `commander/swlc/` and `tools/build-playable.ps1` on 2026-11-09, at commit 085d38f. `%1`, `%2` and so on are filled in by the game. The radio section is generated directly from `radio.sqf` and the cooldowns in `settings.sqf`.

A sector name is the name Warlords gives it, or `grid` plus six digits when that is empty, which happens on dedicated servers. Warlords' own interface text is not listed, and neither are its lobby parameter titles.

## Radio (side chat)

`SWLC_fnc_radio` picks one line at random for the message type and sends it in side chat to the whole side. It comes from the named group's leader, or from HQ when there is no group or the leader is dead. Each type has a cooldown per side; a message inside its cooldown isn't sent at all. `radioEnabled` set to false silences every line here except the "Wait a moment" reply below.

### Attack cycle

**`staging`** (from HQ, cooldown 20 s). A new operation starts. `%1` target sector name, `%2` rally grid.

- "All units, next is %1. Muster at your sectors, rally at %2."
- "Next objective %1. Form up where you are, rally at %2."
- "We're taking %1. Muster up, then meet at %2."
- "%1 is the target. Rally at %2."

**`arrived`** (from group, cooldown 20 s). A group reaches its muster.

- "Mustered up."
- "Formed up, ready to move."
- "We're together, ready when you are."
- "Group's assembled."

**`kit`** (from HQ, cooldown 30 s). Men are sent to the crate for AT launchers.

- "Launchers at the crate, armour expected."
- "Draw AT at the crate before we go."
- "Armour on the objective. Grab launchers."
- "Gear up, AT at the crate."

**`mount`** (from HQ, cooldown 20 s). Groups with vehicles start boarding.

- "Mount up."
- "Load up, we leave shortly."
- "Everyone aboard, we roll shortly."
- "Get to your vehicles, moving out soon."

**`leaving`** (from group, cooldown 15 s). A muster's groups leave. `%1` muster sector name, `%2` target sector name (only the second line uses `%2`).

- "Leaving %1 for the rally."
- "Moving out from %1, heading for %2."
- "On our way from %1."
- "%1 is clear, we're heading to the rally."

**`rally`** (from group, cooldown 15 s). A group reaches the rally.

- "At the rally point."
- "Reached the rally, holding."
- "We're at the rally, waiting on the next group."
- "Rally point, standing by."

**`peelhold`** (from HQ, cooldown 30 s). The wave holds at the rally for responders coming back. `%1` target sector name.

- "Hold at the rally for %1, waiting on the others."
- "Not enough to go in on %1 yet. Hold at the rally."
- "Wait at the rally, responders are coming back for %1."
- "Holding the push on %1 until we've got the numbers."

**`moveout`** (from HQ, cooldown 10 s). The go at the rally. `%1` number of groups (only the first line uses it), `%2` target sector name.

- "%1 groups, go. Push on %2."
- "Go go go. Push on %2."
- "All units at the rally, move in on %2."
- "We're going in on %2."

**`reinforce`** (from group, cooldown 20 s). A late group goes straight in to a running fight. `%1` target sector name.

- "Going in to reinforce at %1."
- "Reinforcing the push on %1."
- "Heading in to help at %1."
- "Joining the fight at %1."

**`stuck`** (from group, cooldown 30 s). A vehicle is abandoned and its group walks.

- "Vehicle's stuck, we're on foot."
- "We've lost the vehicle, walking from here."
- "Vehicle's done, continuing on foot."
- "Bogged down. Dismounting."

**`flank`** (from group, cooldown 45 s). A pinned squad suppresses and flanks.

- "Taking heavy fire. One team suppressing, the other going round."
- "We're pinned. Moving to flank, keep their heads down."
- "Can't push through this. Flanking now."

**`failed`** (from HQ, cooldown 20 s). A push fails on losses or no progress.

- "Pull back to the rally and regroup."
- "That's enough. Fall back to the rally."
- "Attack's failed. Regroup at the rally."
- "Break off, get back to the rally."

**`seized`** (from HQ, cooldown 5 s). The sector falls. `%1` sector name.

- "%1 is ours."
- "%1 secured."
- "We hold %1. Good work."
- "%1 has fallen to us."

### Phase 6 calls

**`heavy`** (from group, cooldown 25 s). A group has lost 40% of the men it launched with. Once per group per wave.

- "Taking heavy fire!"
- "We're getting hammered here."
- "Heavy losses, need help."
- "They've got us pinned, taking casualties."

**`breaking`** (from group, cooldown 15 s). A group breaks and falls back.

- "We're falling back to the rally."
- "Too many down, pulling back."
- "Breaking contact, returning to the rally."
- "We can't hold, falling back."

**`cheer`** (from group, cooldown 5 s). A sector falls (a random nearby group).

- "Sector's ours, well done!"
- "Yes! We took it!"
- "That's the way, it's ours!"
- "Nice work, everyone, it's ours."

**`smoke`** (from group, cooldown 20 s). Smoke is laid at the go.

- "Smoke out!"
- "Popping smoke, screen the push."
- "Smoke going out, move under it."
- "Laying smoke, go when it's up."

**`prepfire`** (from HQ, cooldown 30 s). Prep fire is fired. `%1` target sector name.

- "Fire mission on %1."
- "Shells incoming on %1, stay clear."
- "Prep fire on %1."
- "Mortars on %1, hold at your marks."

**`momentum`** (from HQ, cooldown 30 s). A follow-on push is picked. `%1` next sector name.

- "Don't stop, push on %1!"
- "They're running. On to %1."
- "Keep the pressure on, next is %1."
- "Next is %1, go now."

**`scout`** (from group, cooldown 30 s). A scout group leaves. `%1` target sector name.

- "Scout element moving ahead to %1."
- "Sending eyes forward to %1."
- "Recon team heading for %1."
- "Scouts going out to %1."

**`hunt`** (from group, cooldown 30 s). A group is sent after a hidden shooter. `%1` map grid digits only, for example 023081.

- "Hidden AT somewhere near %1, sweep for it."
- "Something unseen got a vehicle at %1, hunting it."
- "Hunting a hidden shooter at %1."
- "Vehicle lost at %1, we're going after them."

**`digin`** (from group, cooldown 30 s). A group digs in after a capture. `%1` sector name.

- "Digging in at %1."
- "Taking positions at %1, watch for a counterattack."
- "Hold %1, expect them back."
- "Set up on %1, they'll be back."

**`joinpush`** (from group, cooldown 30 s). A group attaches to a human's push. `%1` player's name.

- "Moving with you, %1."
- "We'll push with you, %1."
- "Got your back on this push, %1."
- "%1, we're on you, moving up."

### Commitment timer

**`commitstay`** (from HQ, cooldown 60 s). The stalled target is close enough to stay on. `%1` sector name.

- "We're close at %1. Stay on it."
- "Nearly there at %1, keep the pressure on."
- "%1 is almost ours, don't stop now."
- "Hold the attack on %1, we're close."

**`commitswitch`** (from HQ, cooldown 30 s). The commander switches target. `%1` old sector name, `%2` new sector name.

- "We're getting nowhere at %1. New target: %2."
- "Break off from %1. We're going for %2."
- "%1 isn't working. Switching to %2."
- "Leave %1. All units, %2 is next."

**`commitrebuild`** (from HQ, cooldown 30 s). The side pulls back to rebuild. `%1` sector name.

- "Pull back from %1. We rebuild, then go again."
- "Break off from %1, regroup and refit."
- "We can't take %1 like this. Fall back and rebuild."
- "All units, leave %1 and reorganise."

**`commitvote`** (from HQ, cooldown 30 s). A human side is asked to vote again. `%1` sector name, `%2` minutes banned (15 by default).

- "The attack on %1 has stalled. Vote for a new target. %1 is off the table for %2 minutes."
- "%1 has held us too long. Target vote is open, %1 is out for %2 minutes."
- "No progress on %1. Pick another target, %1 is locked out for %2 minutes."

### Intel

**`sighting`** (from reporting group, or HQ if none, cooldown 15 s). New armour, APC, static, helicopter or jet on the board. `%1` is one of: armour, APCs, static guns, helicopters, jets. `%2` is a sector name, or `grid` plus digits.

- "Enemy %1 at %2."
- "Contact, %1 at %2."
- "Eyes on %1, %2."
- "Be advised, %1 near %2."

**`report`** (from the reporting player's group, cooldown 15 s). A player's Report contact was accepted.

- "Copy, marked."
- "Got it, on the board."
- "Thanks, adding that."
- "Acknowledged, noted."

### Defence

**`defend`** (from HQ, cooldown 20 s). A new threat at an owned sector. `%1` sector name, `%2` is one of: armour, vehicles, infantry, `%3` is one of: north, north-east, east, south-east, south, south-west, west, north-west.

- "Contact at %1, %2 from the %3."
- "%1 under attack, %2, %3 side."
- "Enemy pushing %1. %2 from the %3."
- "Need support at %1, %2 inbound from the %3."

**`seizing`** (from HQ, cooldown 30 s). An enemy capture is running on an owned sector. `%1` sector name.

- "They're seizing %1!"
- "%1 is being taken, respond now!"
- "Enemy on the flag at %1!"
- "Losing %1, they're seizing it!"

**`escalate`** (from group, cooldown 30 s). The threat is bigger than the first response. `%1` sector name.

- "More than reported at %1, need more men."
- "%1 is worse than we thought. Send help."
- "Bigger force at %1, we need backup."
- "They've got more at %1 than reported."

**`stagingattack`** (from HQ, cooldown 20 s). A muster comes under threat.

- "They're on our muster point, defend it!"
- "Contact at the muster, turn and fight!"
- "Enemy at the muster point, all groups defend!"
- "Hold the muster area, enemy inbound!"

**`defreturn`** (from HQ, cooldown 30 s). Responders head back to the attack. `%1` sector name.

- "%1 is secure, heading back to the attack."
- "Done at %1, rejoining the push."
- "%1 is held, returning to the wave."
- "Finished at %1, back to the main effort."

**`standdown`** (from HQ, cooldown 20 s). A threat has cleared. `%1` sector name.

- "%1 is clear, stand down."
- "Threat at %1 is gone. Back to it."
- "%1 quiet, reserve stand down."
- "All clear at %1."

### Raids and probes

**`raidorder`** (from HQ, cooldown 30 s). A raid is ordered. `%1` sector name.

- "Raid order placed on %1."
- "Raid on %1 is a go. Keep it quiet."
- "Raid order: %1. Get in and take it."
- "Quiet raid going in on %1."

**`raidwon`** (from HQ, cooldown 30 s). A raid takes its sector. `%1` sector name.

- "Raid on %1 succeeded, it's ours."
- "%1 taken by raid."
- "Raid complete, %1 is ours."
- "The raid took %1."

**`raidstop`** (from HQ, cooldown 30 s). A raid is called off. `%1` sector name.

- "Raid on %1 is off."
- "Calling off the raid on %1."
- "Raid on %1 failed, pull out."
- "No good at %1. Raid over, get out of there."

**`probe`** (from group, cooldown 30 s). A probe sets out. `%1` sector name.

- "Probing %1."
- "Taking a look at %1."
- "Moving up to probe %1."
- "Heading out to test %1."

**`probeback`** (from group, cooldown 30 s). A probe breaks off. `%1` sector name.

- "Too much at %1, pulling back."
- "Resistance at %1, breaking off."
- "%1 is held, we're coming back."
- "Not getting in at %1, withdrawing."

**`probeweak`** (from group, cooldown 30 s). A probe finds a weak sector. `%1` sector name.

- "%1 is lightly held."
- "%1 looks weak."
- "Not much at %1. Worth a go."
- "%1 is thin, we could take it."

### Economy and round clock

**`econcut`** (from HQ, cooldown 120 s). A sector is cut off from the base. `%1` sector name.

- "Supply line cut. %1 is cut off from base."
- "We've lost the road to %1. Whatever it gave us is gone until we reconnect it."
- "%1 is isolated. Retake the link to get it back."
- "Chain broken at %1. Reconnect it."

**`econcornered`** (from HQ, cooldown 300 s). The base is under attack and prices drop.

- "They're coming for the base. Everything bought here is cheaper now."
- "Base under attack. Prices are down, use them."
- "The base is the fight now. Supplies here are discounted."
- "Last stand at base. Buy what you need, it costs less."

**`econcounter`** (from HQ, cooldown 60 s). A sector was just lost and counterattack prices apply. `%1` sector name, `%2` minutes (5 by default).

- "We lost %1. Cheaper units nearby for the next %2 minutes, take it back."
- "%1 is gone. Counterattack prices near it for %2 minutes."
- "Hit back at %1. Units near it are discounted for %2 minutes."
- "%1 has fallen. %2 minutes of cheaper units to retake it."

**`econdefended`** (from HQ, cooldown 120 s). A defended sector pays out. `%1` sector name, `%2` CP (150 by default).

- "%1 held. %2 CP for the defence."
- "They couldn't take %1. %2 CP each."
- "Good work holding %1, %2 CP."
- "%1 stays ours. Defence bonus, %2 CP."

**`econdugin`** (from HQ, cooldown 60 s). A held sector gets sandbags and a gun. `%1` sector name.

- "%1 is dug in. Sandbags and a gun are up."
- "Fortifications finished at %1."
- "%1 has a gun position now."
- "Engineers are done at %1. It's dug in."

**`econlimit5`** (from HQ, cooldown 0 s). Five minutes left on the round limit.

- "Five minutes left on the clock. Whoever holds more sectors wins."
- "Five minutes. Count the sectors."
- "Clock's at five minutes. Sectors decide this."
- "Five minutes remain. Hold what you have, take what you can."

**`econlimit1`** (from HQ, cooldown 0 s). One minute left.

- "One minute left."
- "Last minute. Sectors decide it."
- "One minute on the clock."
- "Sixty seconds. Hold on."

**`econsuddendeath`** (from HQ, cooldown 0 s). A tied round goes to extra time. `%1` minutes (5 by default).

- "Dead level. %1 more minutes."
- "Tied on the clock. Fight on for %1 minutes."
- "No winner yet. %1 minutes of extra time."
- "Even at the whistle. %1 minutes more."

**`econlimitwin`** (from HQ, cooldown 0 s). Time runs out, this side wins.

- "Time's up. We hold more ground. We've won."
- "The clock's out and the map is ours."
- "Time. We win on ground held."
- "That's time. Victory."

**`econlimitloss`** (from HQ, cooldown 0 s). Time runs out, this side loses.

- "Time's up. They hold more ground. We've lost."
- "The clock's out and they have the map."
- "Time. We lose on ground held."
- "That's time. We didn't hold enough."

### Replies to the Commander menu

**`raidno_off`** (from HQ, cooldown 3 s). Raid refused: raids are off.

- "Raids aren't authorised right now."

**`raidno_active`** (from HQ, cooldown 3 s). Raid refused: one is running.

- "We've already got a raid running."

**`raidno_cooldown`** (from HQ, cooldown 3 s). Raid refused: too soon.

- "Too soon after the last raid. Give it time."

**`raidno_not_front`** (from HQ, cooldown 3 s). Raid refused: not a front-line sector. `%1` sector name.

- "Can't raid %1, it isn't next to anything we hold."

**`raidno_funds`** (from HQ, cooldown 3 s). Raid refused: not enough CP. `%2` raid cost (300 by default).

- "A raid costs %2 CP and you haven't got it."

**`menubad`** (from HQ, cooldown 3 s). The request named no valid sector.

- "Didn't catch which sector. Say again."

**`borrowok`** (from HQ, cooldown 3 s). Send groups with me accepted. `%1` number of groups.

- "Groups on their way to you: %1."

**`borrowno`** (from HQ, cooldown 3 s). Nothing to spare.

- "Can't spare any groups for that right now."

**`borrowmax`** (from HQ, cooldown 3 s). The player already has the most groups allowed.

- "You've got as many groups as I can give you."

**`releaseok`** (from HQ, cooldown 3 s). Release my groups accepted.

- "Copy, those groups are back with the commander."

**`releasenone`** (from HQ, cooldown 3 s). No groups on loan.

- "You've got no groups on loan."

**`holdok`** (from HQ, cooldown 3 s). Hold the wave accepted. `%1` minutes (2 by default).

- "Holding the go signal for up to %1 minutes. Get there."

**`holdno_noop`** (from HQ, cooldown 3 s). No attack is forming. Also the reply to Go now.

- "There's no attack forming right now."

**`holdno_assault`** (from HQ, cooldown 3 s). Hold refused: already going in.

- "Too late, they're already going in."

**`holdno_used`** (from HQ, cooldown 3 s). Hold refused: used recently.

- "We held the wave recently. Can't hold it again yet."

**`gook`** (from HQ, cooldown 3 s). Go now accepted.

- "Go now. All staged groups, move."

**`gono`** (from HQ, cooldown 3 s). Go now refused: nobody staged.

- "Not enough groups at staging to go yet."

**`gono_going`** (from HQ, cooldown 3 s). Go now refused: already going.

- "The attack's already under way."

**`reportno`** (from HQ, cooldown 3 s). Report contact placed nothing.

- "Couldn't place that contact. Nothing added."

**`defendok`** (from HQ, cooldown 3 s). Defend this sector accepted. `%1` sector name.

- "Roger, %1 comes first. Groups moving there."

**`defendthin`** (from HQ, cooldown 3 s). Accepted, but nobody is free. `%1` sector name.

- "No one free right now, but %1 comes first if it's hit."

**`defendbad`** (from HQ, cooldown 3 s). The sector isn't the side's. `%1` sector name.

- "%1 isn't ours to defend."

**`pickupok`** (from HQ, cooldown 3 s). Pickup accepted. `%1` the group's callsign.

- "%1 is bringing a vehicle to you. Stay put."

**`pickupno`** (from HQ, cooldown 3 s). Pickup refused: nothing to spare, or no money.

- "Can't send a pickup right now, nothing to spare."

**`pickupbusy`** (from HQ, cooldown 3 s). Pickup refused: one is running.

- "A pickup's already running. Wait for it to finish."

**`pickupbad`** (from HQ, cooldown 3 s). Pickup refused: bad spot or too far.

- "Can't get a vehicle to you there."

**`pickuphere`** (from group, cooldown 3 s). The vehicle has arrived.

- "Your vehicle's here. It's yours."

**`pickupfail`** (from HQ, cooldown 3 s). The pickup timed out or was lost.

- "Pickup's off. We lost it or couldn't reach you."

**`plan`** (from HQ, cooldown 5 s). What's the plan? `%1` target sector name, `%2` rally grid, `%3` one of the timer texts below, `%4` the raid text below or nothing.

- "Target %1, staging at grid %2. %3 %4"

**`planidle`** (from HQ, cooldown 5 s). What's the plan? with no attack. `%1` the raid text below or nothing.

- "No attack planned right now. %1"

### Fragments used in the plan reply

`%3` of `plan`, one of (`menu.sqf`):

- "Attack under way."
- "Holding for you, %1 left." (`%1` is m:ss)
- "Going in within %1." (`%1` is m:ss)
- "Waiting for groups at the rally."

`%4` of `plan` and `%1` of `planidle`, or nothing:

- "Raid on %1, %2 left." (`%1` sector name, `%2` m:ss)

### Sent outside the radio function

- "Wait a moment before asking again." HQ, side chat, only to the player who pressed the button, at most once every 5 seconds (`menu.sqf`).

## Commander panel

Opened with the Insert key or the last menu entry. It shows the player's own side, and the enemy side too while the debug overlay is on. Text is in `status.sqf`, `client.sqf` and `rules.sqf`.

Header (`%1` is the side, shown as WEST or EAST):

- `AI COMMANDERS - %1` then `target: %2`, then the capture status. `%2` is a sector name or `none`.
- `AI COMMANDERS - %1: no data yet`

Capture status (`rules.sqf`): `seizing %1%`, or `holding %1%`, with the number as a whole percentage. Blank when there is no capture running.

Each group takes two lines: its callsign, job word, place and an m:ss clock, then the reason.

| State in the code | Job word | Place | Reason |
|---|---|---|---|
| Unassigned | Idle | nearest sector | `getting orders` or `no target yet, waiting for the vote` |
| Travelling | Moving | `to %1` (muster name, or `to muster`) | `joining the muster, %1 m out` |
| Mustering | Mustering | muster name, or `-` | `waiting for %1 to arrive` (a callsign), `leaving in %1` (m:ss), or `waiting for bought men to land` |
| Mounting | Boarding | muster name, or `-` | `drawing kit at the crate`, `getting into the vehicle` or `ready to leave` |
| Advancing | Moving | `to rally` | `on foot, %1 m out` or `driving, %1 m out` |
| Waiting | Waiting | `rally point` | `regrouping after falling back`, `needs %1 more group to go, or alone in %2` (m:ss), or `going in now` |
| Assaulting | Attacking | target name | `pushing with a player`, `%1 groups in, %2 enemy known` (`group` when it's one), or `combat vehicle, behind the infantry` |
| Regrouping | Falling back | `rally point` | `down to %1 men, %2 m out` |
| Reserve | Defending | nearest sector | `reserve, no threat right now` |
| Defending | Defending | nearest sector | `dug in, watching for a counterattack` or `responding to enemy near this sector` |
| Borrowed | With player | player's name, or `-` | `on loan to a player until released` |
| Pickup | Pickup | nearest sector | `bringing a vehicle to a player` |
| Picket | Picket | nearest sector | `watching the front line, will report and delay` |
| Raiding | Raiding | nearest sector | `raid order, seizing it quietly` |
| Probing | Scouting | nearest sector | `probing an enemy sector` |
| Recon | Scouting | target name | `looking ahead of the attack` |
| Hunting | Hunting | map grid | `hidden shooter hit a vehicle here` |

## Menu

The scroll action is `Commander...`. It opens a list titled `Commander`, and number keys pick the entries (`menu_client.sqf`):

1. `Order raid on sector`
2. `Send groups with me`
3. `Hold the wave for us`
4. `Go now`
5. `Report contact`
6. `Defend this sector`
7. `Request a pickup`
8. `Release my groups`
9. `What's the plan?`
0. `AI commanders panel (Insert)`

## Hints

All in `menu_client.sqf`.

- "No enemy to report." Report contact found nothing to send.
- "Click on a sector." A map click wasn't near a sector.
- "Request sent to the commander." A sector was picked.
- "Finish what you're selecting on the map first." Warlords is waiting for a map click.
- "Click the owned sector to defend. Close the map to cancel."
- "Click an enemy front-line sector to raid. Close the map to cancel."
- "Cancelled." The map was closed while picking.

## Map markers

Drawn locally for the player's own side.

| Text | Marker | Colour | Shown |
|---|---|---|---|
| `Target: %1` | mil_objective | Red | The plan's target |
| `Rally`, or `Rally (alone in %1)` (m:ss) | mil_arrow | Orange | The plan's rally |
| `Muster: %1` | mil_flag | Blue | Each muster sector |
| `Raid: %1 (%2)` (sector, m:ss) | mil_warning | Orange | An active raid |
| `Raid: %1` | mil_warning | Yellow | Sectors that can be raided, while picking on the map |
| `Contact: %1` | mil_warning | Side colour | Recent board entries, when the side holds a connected radio sector |
| `Banned: %1` | mil_objective | Grey | A sector the side can't vote for |

`%1` on the `Contact` marker is the raw category word from the code, not a radio-style word: `infantry`, `static`, `heli`, `jet`, `boat`, `apc`, `tank`, `light` or `unknownAT`.

Debug overlay, only while `SWLC_debug` is true. These are global markers, so every player sees them (`debug.sqf`, `%1` is the side unless noted):

- `%1 TARGET`, `%1 RALLY`, `%1 MUSTER %2` (`%2` sector name)
- `%1 %2 %3s` (group callsign, the internal state name such as `Unassigned`, seconds in that state)
- `%1: %2`, meant to show the last decision. `lastDecision` is set to empty at startup and nothing ever updates it, so this marker only ever shows the side and a colon.

## Buy menu notes

Added in amber under an entry's text in Warlords' buy menu (`economy_client.sqf`):

- "Needs a military sector connected to your base."
- "Needs a military sector connected to your base, or being at your own base."
- "Out of supply range. Move closer to your base, an industrial sector or a held sector."

## Other strings

- `the Commander`: the name Warlords' vote reset popup shows on human clients as who reset the vote (`adapter.sqf`).
- `Smarter Warlords`: the scenario's name in the host list (`build-playable.ps1`, set as `briefingName`).

## Lobby parameters

Added by `tools/build-playable.ps1`, after Warlords' own parameters:

| Title | Values | Default |
|---|---|---|
| `AI commander difficulty` | `Easy`, `Normal`, `Hard` | `Normal` |
| `Round time limit` | `Off`, `30 minutes`, `45 minutes`, `60 minutes`, `90 minutes`, `120 minutes` | `Off` |
| `Rules variant` | `On`, `Off` | `On` |

The build also changes two of Warlords' own defaults, without changing their text: `BIS_WLFTEnabled` to 4 and `BIS_WLAIVoting` to 1.

## Tanoa sector classification

From `commander/swlc/maps/Tanoa.sqf`, matched by position within 100 m. Any sector not listed would default to town, and bases get no type. None fell to the default in the logged round (`tests/server/runs/2026-11-09_16-09-27_sabotage1`, the `sectortype` lines). The names come from `docs/runs/2026-11-08-rules-variant/notes/economy-integration.md`. The "name in that round" column shows why sector names can't be keyed on: dedicated server rounds log some as grid references.

| Sector | Position | Type | Letter | Name in that round |
|---|---|---|---|---|
| Unnamed (`Sector_1715_6128` in older logs) | 1715, 6128 | industrial | I | `grid 017061` |
| Rautake | 3411, 6704 | town | T | `grid 034067` |
| Tavu | 983, 7656 | town | T | `grid 009076` |
| Balavu | 2665, 7345 | military | M | `grid 026073` |
| Leqa | 2341, 8183 | radio | R | `Leqa` |
| BLUFOR Base | set by Warlords | none | | `BLUFOR Base` |
| OPFOR Base | set by Warlords | none | | `OPFOR Base` |

Balavu as military and Leqa as radio are design choices; no military site or tower was confirmed on the map (`docs/design/rules-variant.md`).
