// Radio: how players see the commander thinking. Every line anyone can see is in this file.
// A line is picked at random from its type's list. Cooldowns are per side and per type.
// Lines only ever use what the side knows (the intel board and its own plan).
#include "macros.hpp"

SWLC_radioLines = createHashMapFromArray [
	["sighting", ["Enemy %1 at %2.", "Contact, %1 at %2.", "Eyes on %1, %2.", "Be advised, %1 near %2."]],
	["staging", ["All units, next is %1. Muster at your sectors, rally at %2.", "Next objective %1. Form up where you are, rally at %2.", "We're taking %1. Muster up, then meet at %2.", "%1 is the target. Rally at %2."]],
	["arrived", ["Mustered up.", "Formed up, ready to move.", "We're together, ready when you are.", "Group's assembled."]],
	["moveout", ["%1 groups, go. Push on %2.", "Go go go. Push on %2.", "All units at the rally, move in on %2.", "We're going in on %2."]],
	["leaving", ["Leaving %1 for the rally.", "Moving out from %1, heading for %2.", "On our way from %1.", "%1 is clear, we're heading to the rally."]],
	["rally", ["At the rally point.", "Reached the rally, holding.", "We're at the rally, waiting on the next group.", "Rally point, standing by."]],
	["reinforce", ["Going in to reinforce at %1.", "Reinforcing the push on %1.", "Heading in to help at %1.", "Joining the fight at %1."]],
	["seized", ["%1 is ours.", "%1 secured.", "We hold %1. Good work.", "%1 has fallen to us."]],
	["mount", ["Mount up.", "Load up, we leave shortly.", "Everyone aboard, we roll shortly.", "Get to your vehicles, moving out soon."]],
	["kit", ["Launchers at the crate, armour expected.", "Draw AT at the crate before we go.", "Armour on the objective. Grab launchers.", "Gear up, AT at the crate."]],
	["stuck", ["Vehicle's stuck, we're on foot.", "We've lost the vehicle, walking from here.", "Vehicle's done, continuing on foot.", "Bogged down. Dismounting."]],
	["defend", ["Contact at %1, %2 from the %3.", "%1 under attack, %2, %3 side.", "Enemy pushing %1. %2 from the %3.", "Need support at %1, %2 inbound from the %3."]],
	["raidorder", ["Raid order placed on %1.", "Raid on %1 is a go. Keep it quiet.", "Raid order: %1. Get in and take it.", "Quiet raid going in on %1."]],
	["raidwon", ["Raid on %1 succeeded, it's ours.", "%1 taken by raid.", "Raid complete, %1 is ours.", "The raid took %1."]],
	["raidstop", ["Raid on %1 is off.", "Calling off the raid on %1.", "Raid on %1 failed, pull out.", "No good at %1. Raid over, get out of there."]],
	["probe", ["Probing %1.", "Taking a look at %1.", "Moving up to probe %1.", "Heading out to test %1."]],
	["probeback", ["Too much at %1, pulling back.", "Resistance at %1, breaking off.", "%1 is held, we're coming back.", "Not getting in at %1, withdrawing."]],
	["probeweak", ["%1 is lightly held.", "%1 looks weak.", "Not much at %1. Worth a go.", "%1 is thin, we could take it."]],
	["econcut", [
		"Supply line cut. %1 is cut off from base.",
		"We've lost the road to %1. Whatever it gave us is gone until we reconnect it.",
		"%1 is isolated. Retake the link to get it back.",
		"Chain broken at %1. Reconnect it."
	]],
	["econcornered", [
		"They're coming for the base. Everything bought here is cheaper now.",
		"Base under attack. Prices are down, use them.",
		"The base is the fight now. Supplies here are discounted.",
		"Last stand at base. Buy what you need, it costs less."
	]],
	["econcounter", [
		"We lost %1. Cheaper units nearby for the next %2 minutes, take it back.",
		"%1 is gone. Counterattack prices near it for %2 minutes.",
		"Hit back at %1. Units near it are discounted for %2 minutes.",
		"%1 has fallen. %2 minutes of cheaper units to retake it."
	]],
	["econdefended", [
		"%1 held. %2 CP for the defence.",
		"They couldn't take %1. %2 CP each.",
		"Good work holding %1, %2 CP.",
		"%1 stays ours. Defence bonus, %2 CP."
	]],
	["econdugin", [
		"%1 is dug in. Sandbags and a gun are up.",
		"Fortifications finished at %1.",
		"%1 has a gun position now.",
		"Engineers are done at %1. It's dug in."
	]],
	["econlimit5", [
		"Five minutes left on the clock. Whoever holds more sectors wins.",
		"Five minutes. Count the sectors.",
		"Clock's at five minutes. Sectors decide this.",
		"Five minutes remain. Hold what you have, take what you can."
	]],
	["econlimit1", [
		"One minute left.",
		"Last minute. Sectors decide it.",
		"One minute on the clock.",
		"Sixty seconds. Hold on."
	]],
	["econsuddendeath", [
		"Dead level. %1 more minutes.",
		"Tied on the clock. Fight on for %1 minutes.",
		"No winner yet. %1 minutes of extra time.",
		"Even at the whistle. %1 minutes more."
	]],
	["econlimitwin", [
		"Time's up. We hold more ground. We've won.",
		"The clock's out and the map is ours.",
		"Time. We win on ground held.",
		"That's time. Victory."
	]],
	["econlimitloss", [
		"Time's up. They hold more ground. We've lost.",
		"The clock's out and they have the map.",
		"Time. We lose on ground held.",
		"That's time. We didn't hold enough."
	]],
	["flank", [
		"Taking heavy fire. One team suppressing, the other going round.",
		"We're pinned. Moving to flank, keep their heads down.",
		"Can't push through this. Flanking now."
	]],
	["raidno_off", ["Raids aren't authorised right now."]],
	["raidno_active", ["We've already got a raid running."]],
	["raidno_cooldown", ["Too soon after the last raid. Give it time."]],
	["raidno_not_front", ["Can't raid %1, it isn't next to anything we hold."]],
	["raidno_funds", ["A raid costs %2 CP and you haven't got it."]],
	["menubad", ["Didn't catch which sector. Say again."]],
	["cancelask", ["Call off the attack on %1? Select Cancel objective again within %2 seconds to confirm."]],
	["cancelok", ["Objective %1 called off. Everyone out, then vote for a new target. %1 is off the table for %2 minutes."]],
	["cancelno_none", ["We've got no objective to call off."]],
	["cancelno_pulling", ["Already pulling out of there."]],
	["cancelno_used", ["We only just called one off. Give it a couple of minutes."]],
	["cancelno_off", ["Can't call that off, the commitment rule is turned off."]],
	["borrowok", ["Groups on their way to you: %1."]],
	["borrowno", ["Can't spare any groups for that right now."]],
	["borrowmax", ["You've got as many groups as I can give you."]],
	["holdok", ["Holding the go signal for up to %1 minutes. Get there."]],
	["holdno_noop", ["There's no attack forming right now."]],
	["holdno_assault", ["Too late, they're already going in."]],
	["holdno_used", ["We held the wave recently. Can't hold it again yet."]],
	["gook", ["Go now. All staged groups, move."]],
	["gono", ["Not enough groups at staging to go yet."]],
	["gono_going", ["The attack's already under way."]],
	["reportno", ["Couldn't place that contact. Nothing added."]],
	["defendok", ["Roger, %1 comes first. Groups moving there."]],
	["defendthin", ["No one free right now, but %1 comes first if it's hit."]],
	["defendbad", ["%1 isn't ours to defend."]],
	["pickupok", ["%1 is bringing a vehicle to you. Stay put."]],
	["pickupno", ["Can't send a pickup right now, nothing to spare."]],
	["pickupbusy", ["A pickup's already running. Wait for it to finish."]],
	["pickupbad", ["Can't get a vehicle to you there."]],
	["pickuphere", ["Your vehicle's here. It's yours."]],
	["pickupfail", ["Pickup's off. We lost it or couldn't reach you."]],
	["releaseok", ["Copy, those groups are back with the commander."]],
	["releasenone", ["You've got no groups on loan."]],
	["plan", ["Target %1, staging at grid %2. %3 %4"]],
	["planidle", ["No attack planned right now. %1"]],
	["ftclose", ["Real fighting at %1. Fast travel there is closed, use the next sector over.", "%1 is a fight now, no more fast travel in. Come in from a neighbouring sector.", "Fast travel to %1 is shut, they're on it.", "%1 is hot. Fast travel closed."]],
	["ftopen", ["%1 has gone quiet. Fast travel there is open again.", "Fast travel to %1 is back open.", "%1 is quiet. You can fast travel in again.", "Fighting's over at %1, fast travel is open."]],
	["seizing", ["They're seizing %1!", "%1 is being taken, respond now!", "Enemy on the flag at %1!", "Losing %1, they're seizing it!"]],
	["escalate", ["More than reported at %1, need more men.", "%1 is worse than we thought. Send help.", "Bigger force at %1, we need backup.", "They've got more at %1 than reported."]],
	["defreturn", ["%1 is secure, heading back to the attack.", "Done at %1, rejoining the push.", "%1 is held, returning to the wave.", "Finished at %1, back to the main effort."]],
	["peelhold", ["Hold at the rally for %1, waiting on the others.", "Not enough to go in on %1 yet. Hold at the rally.", "Wait at the rally, responders are coming back for %1.", "Holding the push on %1 until we've got the numbers."]],
	["standdown", ["%1 is clear, stand down.", "Threat at %1 is gone. Back to it.", "%1 quiet, reserve stand down.", "All clear at %1."]],
	["stagingattack", ["They're on our muster point, defend it!", "Contact at the muster, turn and fight!", "Enemy at the muster point, all groups defend!", "Hold the muster area, enemy inbound!"]],
	["report", ["Copy, marked.", "Got it, on the board.", "Thanks, adding that.", "Acknowledged, noted."]],
	["heavy", ["Taking heavy fire!", "We're getting hammered here.", "Heavy losses, need help.", "They've got us pinned, taking casualties."]],
	["breaking", ["We're falling back to the rally.", "Too many down, pulling back.", "Breaking contact, returning to the rally.", "We can't hold, falling back."]],
	["cheer", ["Sector's ours, well done!", "Yes! We took it!", "That's the way, it's ours!", "Nice work, everyone, it's ours."]],
	["momentum", ["Don't stop, push on %1!", "They're running. On to %1.", "Keep the pressure on, next is %1.", "Next is %1, go now."]],
	["scout", ["Scout element moving ahead to %1.", "Sending eyes forward to %1.", "Recon team heading for %1.", "Scouts going out to %1."]],
	["hunt", ["Hidden AT somewhere near %1, sweep for it.", "Something unseen got a vehicle at %1, hunting it.", "Hunting a hidden shooter at %1.", "Vehicle lost at %1, we're going after them."]],
	["digin", ["Digging in at %1.", "Taking positions at %1, watch for a counterattack.", "Hold %1, expect them back.", "Set up on %1, they'll be back."]],
	["prepfire", ["Fire mission on %1.", "Shells incoming on %1, stay clear.", "Prep fire on %1.", "Mortars on %1, hold at your marks."]],
	["joinpush", ["Moving with you, %1.", "We'll push with you, %1.", "Got your back on this push, %1.", "%1, we're on you, moving up."]],
	["smoke", ["Smoke out!", "Popping smoke, screen the push.", "Smoke going out, move under it.", "Laying smoke, go when it's up."]],
	["commitstay", ["We're close at %1. Stay on it.", "Nearly there at %1, keep the pressure on.", "%1 is almost ours, don't stop now.", "Hold the attack on %1, we're close."]],
	["commitswitch", ["We're getting nowhere at %1. New target: %2.", "Break off from %1. We're going for %2.", "%1 isn't working. Switching to %2.", "Leave %1. All units, %2 is next."]],
	["commitrebuild", ["Pull back from %1. We rebuild, then go again.", "Break off from %1, regroup and refit.", "We can't take %1 like this. Fall back and rebuild.", "All units, leave %1 and reorganise."]],
	["commitvote", ["The attack on %1 has stalled. Vote for a new target. %1 is off the table for %2 minutes.", "%1 has held us too long. Target vote is open, %1 is out for %2 minutes.", "No progress on %1. Pick another target, %1 is locked out for %2 minutes."]],
	["engaged", ["Contact on the way, %1 near %2. Stopping to fight.", "Enemy on our route, %1 near %2. We're fighting here.", "Hit on the move near %2, %1. Engaging.", "%1 near %2, on our road. Stopping to deal with them."]],
	["engagedjoin", ["Moving to help at %1.", "We're closest to %1, going in.", "On our way to the fight at %1.", "Joining the contact at %1."]],
	["engagedclear", ["Contact's dealt with, carrying on.", "Clear here, moving on.", "That's done, back on the road.", "All quiet, resuming."]],
	["engagedfall", ["Too many, %1. Falling back to %2.", "Can't hold this, %1. Back to %2.", "Outnumbered, %1. Pulling back to %2.", "%1, more than we can take. Heading for %2."]],
	["fortbuilt", ["Guns going in at %1, facing their approach.", "Setting up static weapons at %1.", "Digging guns in at %1, they're coming that way.", "%1 is getting guns on the approach."]],
	["failed", ["Pull back to the rally and regroup.","That's enough. Fall back to the rally.", "Attack's failed. Regroup at the rally.", "Break off, get back to the rally."]]
];

SWLC_fnc_radioCatName = {
	params ["_cat"];
	switch (_cat) do {
		case "tank": {"armour"};
		case "apc": {"APCs"};
		case "static": {"static guns"};
		case "heli": {"helicopters"};
		case "jet": {"jets"};
		default {_cat};
	}
};

// _from is a group, or grpNull for HQ. Returns true if the message was sent.
SWLC_fnc_radio = {
	params ["_side", "_type", ["_args", []], ["_from", grpNull]];
	if !(CFG("radioEnabled")) exitWith {false};
	private _lines = SWLC_radioLines getOrDefault [_type, []];
	if (_lines isEqualTo []) exitWith {false};

	private _key = format ["SWLC_radioLast_%1_%2", _side, _type];
	private _last = missionNamespace getVariable [_key, -1e6];
	private _cd = CFG("radioCooldowns") getOrDefault [_type, CFG("radioCooldownDefault")];
	if ((time - _last) < _cd) exitWith {false};
	missionNamespace setVariable [_key, time];

	private _text = format ([selectRandom _lines] + _args);
	private _sender = if (isNull _from) then {"HQ"} else {groupId _from};
	if (isNull _from || {!alive leader _from}) then {
		[[_side, "HQ"], _text] remoteExec ["sideChat", _side];
	} else {
		[leader _from, _text] remoteExec ["sideChat", _side];
	};
	["C_RADIO", [["side", _side], ["type", _type], ["from", _sender], ["text", _text]]] call SWLC_fnc_log;
	true
};
