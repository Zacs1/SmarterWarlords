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
	["standdown", ["%1 is clear, stand down.", "Threat at %1 is gone. Back to it.", "%1 quiet, reserve stand down.", "All clear at %1."]],
	["stagingattack", ["They're on our muster point, defend it!", "Contact at the muster, turn and fight!", "Enemy at the muster point, all groups defend!", "Hold the muster area, enemy inbound!"]],
	["reqok", ["Roger, on it.", "Copy, moving now.", "Understood.", "Acknowledged, we're going."]],
	["reqno", ["Can't do it, nothing spare.", "Negative, no one free right now.", "Not possible at the moment.", "Hold tight, nobody's available."]],
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
	["failed", ["Pull back to the rally and regroup.", "That's enough. Fall back to the rally.", "Attack's failed. Regroup at the rally.", "Break off, get back to the rally."]]
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
