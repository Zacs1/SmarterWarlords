# Part C: integration notes

New files, none yet wired in: `commander/swlc/economy.sqf`, `commander/swlc/economy_client.sqf`, `tests/mission_overlay/swl/scenarios/gatec.sqf`, `tools/gates_c.py`.

## settings.sqf

Add inside the `createHashMapFromArray` list, after the Part B block. No key clashes with the current file.

```sqf
	// Part C: economy and capabilities. Each rule has its own switch.
	["ruleIncome", true],             // flat base income plus a falling bonus per sector
	["incomeFlatBase", 40],           // the base sector's value, the same for both sides
	["incomeSectorCurve", [1, 1, 1, 0.75, 0.5, 0.35, 0.25]], // multiplier by rank, richest sector first; the last repeats
	["ruleCombatIncome", true],       // kills, squad wipes, captures, defended sectors
	["incomeKillInfantry", 10],
	["incomeKillLight", 50],          // cars, boats, statics
	["incomeKillArmour", 250],        // tanks and APCs
	["incomeKillAir", 300],
	["incomeSquadWipe", 100],         // on top of the kill, for the last man of a group of two or more
	["incomeSquadWipeCooldown", 120], // a warlord group respawns, so one group can't pay twice quickly
	["incomeCaptureBonus", 0],        // per warlord, on top of Warlords' own capture payout
	["incomeDefencePayout", 150],     // per warlord
	["defenceSuccessQuietSeconds", 60], // the enemy countdown has to stay stopped this long

	["ruleCapabilities", true],       // sector types unlock things
	["sectorTypes", []],              // per map: [[x, y, ["type", ...]], ...]; airfield harbour military industrial town radio
	["sectorTypeMatchMetres", 100],
	["sectorTypeDefault", "town"],    // for sectors not listed; "" gives nothing
	["industrialVehicleDiscount", 0.8],
	["townSquadBonus", 2],
	["townRespawnTime", 10],          // seconds, for dying near a connected town
	["townRespawnRadius", 500],
	["radioScanDiscount", 0.5],
	["contactPublishSeconds", 15],
	["contactMaxAge", 180],
	["contactMaxRows", 30],

	["ruleSupplyLines", true],        // a capability counts only while connected to the base

	["ruleFortressBase", true],       // full infantry kit at home, and static defences
	["fortressStaticsWEST", ["B_HMG_01_high_F", "B_static_AT_F", "B_static_AA_F", "B_HMG_01_high_F"]],
	["fortressStaticsEAST", ["O_HMG_01_high_F", "O_static_AT_F", "O_static_AA_F", "O_HMG_01_high_F"]],
	["fortressArcDegrees", 40],       // spacing between guns, centred on the enemy base
	["fortressRebuildSeconds", 240],  // lost guns come back after this, but not during an attack on the base

	["ruleCornered", true],           // cheaper at your own base while it is under attack
	["corneredDiscount", 0.6],
	["corneredBaseMargin", 100],      // metres beyond the base square that still count as at the base
	["priceMultFloor", 0.4],          // discounts together never go below this

	["ruleStretchedSupply", true],    // rearm and repair only near your own ground
	["supplyBaseRadius", 800],        // around the base and connected industrial sectors
	["stretchedSupplyRange", 400],    // around any other owned sector
	["supplyCheckSeconds", 30],

	["ruleSectorFort", true],         // a sector held for a while gains sandbags and one gun
	["sectorFortHoldSeconds", 480],
	["sectorFortStaticWEST", "B_HMG_01_high_F"],
	["sectorFortStaticEAST", "O_HMG_01_high_F"],

	["ruleCounterattack", true],      // cheaper near a sector just lost
	["counterattackSeconds", 300],
	["counterattackRadius", 500],
	["counterattackDiscount", 0.7],

	["ruleScaleAI", true],            // an all-AI side gets more CP for each human opponent
	["scaleCpPerHumanPerMin", 10],    // per AI warlord
	["scaleMaxHumans", 4],
	["scaleFakeHumans", 0],           // tests only: count this many humans on the other side

	["roundTimeLimitMinutes", 0],     // 0 is off; the lobby parameter overrides this
	["roundSuddenDeathSeconds", 300], // a dead level result extends the round by this much
	["roundSuddenDeathMax", 2],
```

`radioCooldowns`: add `["econcut", 120], ["econcornered", 300], ["econcounter", 60], ["econdefended", 120], ["econdugin", 60], ["econlimit5", 0], ["econlimit1", 0], ["econsuddendeath", 0], ["econlimitwin", 0], ["econlimitloss", 0]`.

## Maps

`maps/Tanoa.sqf` (returns an array of pairs, currently `[]`):

```sqf
[
	["sectorTypes", [
		[1715, 6128, ["industrial"]],
		[3411, 6704, ["town"]],
		[983, 7656, ["town"]],
		[2665, 7345, ["military"]],
		[2341, 8183, ["radio"]]
	]]
]
```

`maps/default.sqf` needs no change: with `sectorTypes` empty, every sector gets `sectorTypeDefault`.

### Tanoa classification (for the user to check)

The evidence is the 7.5 m/px picture map and the mission data only. No object in the world was checked, and no tower or depot was confirmed. Positions, not names, are the key, because two sectors have no usable name in the logs.

| Sector | Position | Type | Why |
|---|---|---|---|
| (unnamed, logs as `Sector_1715_6128`) | 1715, 6128 | industrial | White round storage tanks on a small peninsula, on BLUFOR's side |
| Rautake (logs as `grid 034067`) | 3411, 6704 | town | Small settlement on the main road, BLUFOR's side |
| Tavu | 983, 7656 | town | Largest built-up area, end of the paved road, OPFOR's side, size 300 |
| Balavu | 2665, 7345 | military | No military objects visible. A design choice: central junction, highest value (50), size 300, so armour is won at the centre |
| Leqa (logs as `grid 023081`) | 2341, 8183 | radio | Hamlet among fields on OPFOR's side. No tower seen. Chosen so each side has a nearby non-town type |

The map has no runway, so no airfield type. Every sector already gives naval purchases natively, so no harbour type either.

## Hook points in existing files

**`commander/swlc/init.sqf`**
- Module list: add `"economy"` before `"commander"`.
- In the `commanderEnabled` block, before `[west] call SWLC_fnc_startCommander`: `[] call SWLC_fnc_econInit;`. Call it with rules off too, so clients get `SWLC_econCfg` and stop waiting.

**`commander/initPlayerLocal.sqf`**: add `execVM "swlc\economy_client.sqf";`.

**`commander/swlc/commander.sqf`**: add `"econTick"` to `SWLC_cmdStages` straight after `"cmdTarget"`, so capabilities are current before anything buys.

**`commander/swlc/logistics.sqf`**
- `SWLC_fnc_logBuy`, after `params`/`_side`: `_cost = ceil (_cost * ([_side, _classes # 0, getPosATL _buyer] call SWLC_fnc_econPriceMult));`. Applies to every commander purchase including vehicles, if `vehBuy` goes through `logBuy` (not checked).
- Lines 64 and 72 of `shopTick`: replace `[] call SWLC_fnc_adScanCost` with `[_side] call SWLC_fnc_econScanCost`.
- Line 106 of `shopInfantry`: replace `CFG("shopGroupSize")` with `([_side] call SWLC_fnc_econSquadCap)`.
- `kitTick`, after `_table`: `private _kitOk = [_cmd get "side", getPosATL (_units # 0)] call SWLC_fnc_econKitAllowed;` then add `&& {_kitOk}` to the AT condition (line 141) and the AA condition (line 148). Smoke and ammo stay unconditional.

**`commander/swlc/vehicles.sqf`**
- `vehShop` line 68: `private _catalog = (_cmd get "catalog") select {[_side, _x # 0, _musterPos] call SWLC_fnc_econAssetAllowed};`.
- `vehCheapestTransport` (reads the catalogue near line 19) needs the same filter with a position, otherwise the budget sums can count a vehicle that can't be bought. Transport rarely is armour, so this is low risk.

**`commander/swlc/adapter.sqf`**: line 498, inside the scan function: `[_side] call SWLC_fnc_econScanCost`. `adSideIncome` needs no change because it reads `BIS_WL_value` live.

**Part H**: `[_side, _pos] call SWLC_fnc_econResupplyAllowed` before any crate rearm. True when the rule is off.

**`commander/swlc/radio.sqf`**: the lines listed below.

**`tools/analyse_round.py`**: nothing required. `gates_c.py` stands alone.

### Lobby parameter

In `tools/build-playable.ps1`, add to the `$difficulty` here-string, after `SWLC_RulesVariant`:

```
class SWLC_RoundTimeLimit
{
	title = "Round time limit";
	values[] = {0, 30, 45, 60, 90, 120};
	texts[] = {"Off", "30 minutes", "45 minutes", "60 minutes", "90 minutes", "120 minutes"};
	default = 0;
};
```

`econInit` reads it with `["SWLC_RoundTimeLimit", -1] call BIS_fnc_getParamValue` and overrides `roundTimeLimitMinutes`. A build without the class keeps the setting.

## Rules that aren't obvious

- Income follows sector ownership regardless of connection. Only capabilities depend on the chain, as the prompt says.
- With `ruleCapabilities` off, `econHasCapability` returns true and all bonuses are off.
- A cut-off sector's `BIS_WL_sectorSpecial` is `[]`, including its native W, so stranded sectors stop offering boats too.
- Tie rule for the time limit: more sectors wins, then higher total original sector value, then up to two 5-minute extensions, then more living men, then a coin toss.
- Vanilla's capture payout reads the sector's current `BIS_WL_value`, so capturing a sector the enemy holds low on its curve pays less. `incomeCaptureBonus` is there if that needs offsetting.
- AI warlord respawn time can't be changed, so the town respawn bonus reaches players only.
- "More groups" for scaling is not implemented, because warlord slots are fixed by the mission. It pays CP only.

## Player-visible strings

Lobby: `Round time limit`; `Off`, `30 minutes` to `120 minutes`.

Map markers: `Contact: %1` (category name), `Banned: %1` (sector name).

Buy menu notes:
- `Needs a military sector connected to your base.`
- `Needs a military sector connected to your base, or being at your own base.`
- `Out of supply range. Move closer to your base, an industrial sector or a held sector.`

A blocked asset also shows Warlords' own restriction text.

Radio lines for `SWLC_radioLines`:

```sqf
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
```

## Log lines

`C_ECON` with `event=` one of: `sectortype`, `caps`, `income`, `kill`, `capture`, `defended`, `counteropen`, `cornered`, `fortress`, `fortrebuilt`, `fort`, `fortfailed`, `supply`, `scale`, `snapshot`, `roundlimit`. The scenario adds `GC` lines.

## Testing

- Scenario: `tools\run-round.ps1 -Scenario gatec`, then `python tools/gates_c.py <rpt> --gate gatec`.
- One soak round: `python tools/gates_c.py <rpt> --gate soak`.
- Comparison: `python tools/gates_c.py --compare <vanilla rpts> --variant <variant rpts>`. Vanilla logs have no snapshots, so those columns read n/a; base fight length and leader wins work on both.

## Only a live round can prove

- `group _unit` is still valid at `EntityKilled`, and `units` on it reflects who is dead. Squad-wipe bounties depend on it.
- `EntityKilled` fires on the server for units local to a player. If it doesn't, kills of a host's or client's bought units pay nothing.
- Rewriting `BIS_WL_value` and `BIS_WL_sectorSpecial` disturbs nothing else in Warlords, including the sector info display and the voting UI.
- Warlords' clients pick up a changed `BIS_WL_sectorSpecial` when `BIS_fnc_WLrecalculateServices` is called outside its usual moments, and on a hosting player.
- The buy menu reads patched requirements and prices. An open category stays stale until reselected.
- Every player-side gate is client-enforced. Nothing on the server re-checks a human's purchase.
- `createVehicleCrew` static crews survive Warlords' zone loops and how they change the seize calculation at bases and dug-in sectors. Crews inside a sector may count towards holding it.
- `setAmmoCargo`, `setRepairCargo` and `setFuelCargo` through `remoteExecCall` work on vehicles a player owns. Crate rearming can't be controlled this way.
- Server writes to `BIS_WL_funds` can race a client's purchase deduction, which reads then writes.
- `setPlayerRespawnTime` during a Warlords respawn, and that restoring the mission delay afterwards is right.
- `BIS_WL_maxSubordinates` and `BIS_WL_scanCost` are written on the client. On a host they are the server's globals too, so vanilla's AI code on that machine would see them. The commander uses its own nominal scan cost, so only vanilla code is affected.
- Writing the loser's base `BIS_WL_sectorSide` ends the round when `MissionEnd` is set, as the code suggests. Tanoa sets it.
- `gatec` writes `BIS_WL_sectorSide` directly, and assumes Warlords doesn't fight that within a two-minute window.
