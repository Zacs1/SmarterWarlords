// Radio: how players see the commander thinking. Every line anyone can see is in this file.
// A line is picked at random from its type's list. Cooldowns are per side and per type.
// Lines only ever use what the side knows (the intel board and its own plan).
#include "macros.hpp"

SWLC_radioLines = createHashMapFromArray [
	["sighting", ["Enemy %1 at %2.", "Contact, %1 at %2.", "Eyes on %1, %2.", "Be advised, %1 near %2."]],
	["staging", ["All units, stage at %1 for the push on %2.", "Next objective %2. Form up at %1.", "We're taking %2. Assemble at %1.", "%2 is the target. Rally at %1."]],
	["arrived", ["In position at staging.", "We're at the staging point.", "Staging, standing by.", "Arrived. Ready when you are."]],
	["moveout", ["Move out on %1 approaches.", "All units, go. %1 approaches.", "Wave %2, you're clear. Move out.", "Go go go. Push on %3."]],
	["seized", ["%1 is ours.", "%1 secured.", "We hold %1. Good work.", "%1 has fallen to us."]],
	["mount", ["Mount up. Ninety seconds.", "Load up, we leave in ninety.", "Everyone aboard, we roll shortly.", "Get to your vehicles, moving out soon."]],
	["kit", ["Launchers at the crate, armour expected.", "Draw AT at the crate before we go.", "Armour on the objective. Grab launchers.", "Gear up, AT at the crate."]],
	["stuck", ["Vehicle's stuck, we're on foot.", "We've lost the vehicle, walking from here.", "Vehicle's done, continuing on foot.", "Bogged down. Dismounting."]],
	["defend", ["Contact at %1, %2 from the %3.", "%1 under attack, %2, %3 side.", "Enemy pushing %1. %2 from the %3.", "Need support at %1, %2 inbound from the %3."]],
	["standdown", ["%1 is clear, stand down.", "Threat at %1 is gone. Back to it.", "%1 quiet, reserve stand down.", "All clear at %1."]],
	["stagingattack", ["Staging's under attack, all units defend!", "Contact at staging, turn and fight!", "They're on the staging point, defend it!", "Hold the staging area, enemy inbound!"]],
	["reqok", ["Roger, on it.", "Copy, moving now.", "Understood.", "Acknowledged, we're going."]],
	["reqno", ["Can't do it, nothing spare.", "Negative, no one free right now.", "Not possible at the moment.", "Hold tight, nobody's available."]],
	["report", ["Copy, marked.", "Got it, on the board.", "Thanks, adding that.", "Acknowledged, noted."]],
	["heavy", ["Taking heavy fire!", "We're getting hammered here.", "Heavy losses, need help.", "They've got us pinned, taking casualties."]],
	["breaking", ["We're falling back to staging.", "Too many down, pulling back.", "Breaking contact, returning to staging.", "We can't hold, falling back."]],
	["cheer", ["Sector's ours, well done!", "Yes! We took it!", "That's the way, it's ours!", "Nice work, everyone, it's ours."]],
	["momentum", ["Don't stop, push on %1!", "They're running. On to %1.", "Keep the pressure on, next is %1.", "Next is %1, go now."]],
	["scout", ["Scout element moving ahead to %1.", "Sending eyes forward to %1.", "Recon team heading for %1.", "Scouts going out to %1."]],
	["hunt", ["Hidden AT somewhere near %1, sweep for it.", "Something unseen got a vehicle at %1, hunting it.", "Hunting a hidden shooter at %1.", "Vehicle lost at %1, we're going after them."]],
	["digin", ["Digging in at %1.", "Taking positions at %1, watch for a counterattack.", "Hold %1, expect them back.", "Set up on %1, they'll be back."]],
	["prepfire", ["Fire mission on %1.", "Shells incoming on %1, stay clear.", "Prep fire on %1.", "Mortars on %1, hold at your marks."]],
	["joinpush", ["Moving with you, %1.", "We'll push with you, %1.", "Got your back on this push, %1.", "%1, we're on you, moving up."]],
	["smoke", ["Smoke out!", "Popping smoke, screen the push.", "Smoke going out, move under it.", "Laying smoke, go when it's up."]],
	["failed", ["Pull back to staging and regroup.", "That's enough. Fall back to staging.", "Attack's failed. Regroup at staging.", "Break off, get back to staging."]]
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
