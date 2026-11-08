// SmarterWarlords commander: every tunable value lives here.
// Map-specific values go in maps\<worldName>.sqf, which overrides these keys.
// Values are starting points and are tuned by testing; see the design doc.

SWLC_settings = createHashMapFromArray [
	// Master switch
	["commanderEnabled", true],

	// A group a human was in within this many seconds is never ordered
	["playerGroupGrace", 120],

	// Timing
	["tickSeconds", 10],              // commander decision tick
	["guardSeconds", 3],              // waypoint guard (re-asserts orders Warlords overwrote)

	// Debug overlay (map markers). Off by default. Toggle: set SWLC_debug = true on the server.
	["debugOverlay", false],
	["debugRefreshSeconds", 5],

	// Fast travel (adapter enforces Warlords' rules; see design doc Integration section)
	["ftAllowedParamValues", [1, 3, 4]],
	["ftChargeCost", true],           // charge BIS_WL_FTCost like vanilla AI; false = free
	["ftEnemyCheckRadius", 200],
	["ftMinDistance", 300],           // never fast travel a group closer than this
	["ftGroupCooldown", 60],
	["ftLandingScatter", 10],

	// Voting
	["voteOnPlayerSide", false],      // cast the AI's votes on a side with human players
	["voteEnemyBaseBonus", 25],
	["voteValueWeight", 1],
	["voteUnlockWeight", 3],
	["voteDistancePer100m", 0.35],
	["voteRecentFailPenalty", 40],
	["voteDefenderWeight", 0.5],      // per enemy soldier on the board
	["voteArmourWeight", 6],
	["voteUnscoutedFactor", 1.5],
	["voteRecentFailSeconds", 600],
	["deadlockSeconds", 720],         // force a new vote if a target hasn't fallen after this long

	// Staging
	["stagingMaxDist", 2500],
	["stagingFallbackMin", 600],
	["stagingFallbackMax", 900],
	["stagingPlaceExpr", "(1 + houses * 2 + trees) * (1 - sea)"],
	["stagingSpotSeparation", 18],
	["stagingEnemyPenalty", 2],       // score lost per enemy on the board within 500 m
	["stagingFarThreshold", 500],     // farther than this from staging: fast travel if allowed
	["arriveRadius", 75],

	// Go signal
	["goMinGroups", 3],
	["goMaxWait", 230],             // 4 minutes minus tick length, so the 4-minute cap holds

	// Launch
	["approachSpreadMin", 60],
	["approachSpreadMax", 120],
	["holdDistMin", 300],
	["holdDistMax", 400],
	["holdArriveRadius", 60],
	["holdWaitMax", 60],
	["toHoldTimeout", 420],
	["sweepPoints", 3],
	["sweepInset", 0.75],

	// Resolve
	["waveFailStrength", 0.35],
	["waveNoProgressSeconds", 300],

	// Watchdog
	["progressWindow", 120],
	["progressMinMetres", 50],
	["stuckTravelSeconds", 180],
	["stuckAssaultSeconds", 240],
	["stuckRegroupSeconds", 180],
	["stuckReconSeconds", 300],
	["postContactQuietSeconds", 45],
	["escalateAfterResets", 2],

	// Intel board
	["intelPollSeconds", 5],
	["intelMaxKnowAge", 30],          // ignore what a group last saw longer ago than this
	["intelMinKnows", 1.0],           // knowsAbout needed to report a sighting
	["intelMergeInfantry", 75],
	["intelMergeVehicle", 150],
	["intelHalfLifeInfantry", 180],
	["intelHalfLifeVehicle", 300],
	["intelHalfLifeStatic", 900],
	["intelDecayMultiplier", 1],      // set by difficulty: above 1, the AI remembers for longer
	["intelDropConf", 0.15],
	["intelSectorRadius", 600],
	["intelAirRadius", 1500],
	["intelNegativeRadius", 100],     // a group this close that sees nothing doubts the report
	["intelNegativeMinAge", 30],
	["intelNegativeFactor", 0.75],
	["intelLossConf", 0.4],
	["intelThreatMinConf", 0.2],
	["intelScoutedSeconds", 300],

	// Radio
	["radioEnabled", true],
	["radioCooldownDefault", 30],
	["radioCooldowns", createHashMapFromArray [["sighting", 15], ["arrived", 20], ["staging", 20], ["seized", 5], ["moveout", 10], ["failed", 20], ["mount", 20], ["kit", 30], ["stuck", 30], ["defend", 20], ["standdown", 20], ["stagingattack", 20], ["reqok", 5], ["reqno", 5], ["report", 15], ["heavy", 25], ["breaking", 15], ["cheer", 5], ["momentum", 30], ["scout", 30], ["hunt", 30], ["digin", 30], ["prepfire", 30], ["joinpush", 30], ["smoke", 20]]],

	// The wave's plan comes from the threat summary
	["planAtPerArmour", 2],
	["planAtPerLightGroup", 1],

	// CP and shopping
	["replaceVanillaBuying", true],   // the commander does all AI buying
	["cpReserveMinutes", 1.5],        // reserve = this many minutes of side income...
	["cpReserveMax", 1500],           // ...capped here, so it never stops a poor side buying cheap transport
	["cpPlentiful", 3000],            // CP above the reserve at which combat vehicles are bought without a threat reason
	["cpCombatFraction", 0.6],        // most of the spare CP one combat vehicle may use
	["shopGroupSize", 3],
	["shopMaxInfantryPerTick", 6],
	["goMinGatherSeconds", 40],       // hold the go this long after the first arrival while men can still be bought
	["scanBuying", true],
	["scanStampSeconds", 130],        // blocks Warlords' own random AI scan on an all-AI side

	// Kit
	["kitEnabled", true],
	["kitWalkTimeout", 45],           // a man who hasn't reached the crate by then gets his kit where he is
	["kitCrateRadius", 6],
	["kitRounds", 2],
	["kitSmokePerGroup", 2],
	["kitExtraMags", 2],
	["kitExtraGrenades", 2],
	["kitHeavyInfantryFactor", 2],

	// Vehicles
	["vehiclesEnabled", true],
	["vehMinDriveDist", 300],         // drives shorter than this aren't worth buying for
	["vehReuseRadius", 500],
	["vehBuyPerTick", 8],
	["vehSeatForFullGroupCP", 1200],  // with this much spare CP, buy seats for a full group, not just the men present
	["vehMaxFleet", 12],
	["vehMaxCombatPerWave", 1],
	["dismountDistMin", 500],
	["dismountDistMax", 800],
	["dismountThreatRange", 900],     // stay this far from known AT and static weapons
	["dismountRoadSnap", 120],
	["dismountArriveRadius", 50],
	["mountCapSeconds", 85],          // about 90 s with the tick
	["mountLateExtra", 45],           // a group not ready at the cap is a second element, this long at most
	["vehStuckWindow", 40],
	["vehStuckMinMetres", 15],
	["vehStuckLimit", 2],
	["combatFollowDist", 75],         // metres behind the lead infantry (50 to 100 in the design)
	["combatReorderDist", 50],
	["combatNudgeSeconds", 100],      // keeps Warlords' stuck check from abandoning a holding crew

	// Defence
	["defenceEnabled", true],
	["reserveBySectors", [[5, 1], [10, 2], [1000000, 3]]],  // up to N sectors owned -> reserve groups
	["reservePatrolSeconds", 150],    // a waiting group moves this often, or Warlords treats its leader as stuck
	["defenceRadius", 400],           // metres outside the sector square that count as near it
	["defenceMinInfantry", 4],
	["defenceSightAge", 90],          // only sightings this recent count as a live threat
	["defenceStandDownSeconds", 120],
	["defenceMenPerGroup", 5],
	["defenceMaxGroups", 3],
	["defenceValueStaging", 100],     // a staging or base sector is always worth pulling attackers for
	["defenceValueBase", 100],

	// Players
	["playerReportRange", 2500],
	["playerReportConf", 0.9],
	["playerReportMax", 8],
	["requestGoMinGroups", 2],
	["requestDefendRange", 600],
	["requestDefendSeconds", 300],
	["planPublishSeconds", 20],
	["planAlwaysPublish", false],     // test switch: publish the plan with no players connected

	// Difficulty. The lobby parameter wins over "difficulty" in hosted games. A preset sets the keys listed.
	["difficulty", "normal"],         // "easy", "normal" or "hard"
	["reactionDelay", 0],             // seconds before a new sighting affects plans and defence (radio is not delayed)
	["difficultyPresets", createHashMapFromArray [
		["easy", [["intelDecayMultiplier", 0.6], ["goMinGroups", 2], ["shopGroupSize", 2], ["reactionDelay", 20], ["scanBuying", false]]],
		["normal", [["intelDecayMultiplier", 1], ["goMinGroups", 3], ["shopGroupSize", 3], ["reactionDelay", 0], ["scanBuying", true]]],
		["hard", [["intelDecayMultiplier", 1.5], ["goMinGroups", 4], ["shopGroupSize", 4], ["reactionDelay", 0], ["scanBuying", true]]]
	]],
	["verboseLog", true],             // per-vehicle and per-guard lines for the test analyser; the playable build turns them off
	["profileStages", false],         // test switch: log the cost of each stage of the commander tick

	// Phase 6 behaviours: each one can be switched off here
	["smartBreak", true],
	["breakFraction", 0.34],          // a group at or below this share of its launch strength breaks off
	["breakMinLaunchMen", 3],
	["mergeRadius", 150],
	["mergeMaxMen", 3],
	["smartRadio", true],
	["radioHeavyFraction", 0.4],      // share of a group lost that draws a "taking heavy fire" call
	["smartReinforce", true],
	["reinforceStallSeconds", 100],
	["reinforceMinMetres", 40],
	["smartSmoke", true],
	["smokeThrowDist", 40],
	["smokeGroupsPerApproach", 1],
	["smartPrepFire", true],
	["prepRounds", 6],
	["prepFireLeadSeconds", 30],      // infantry wait this long after the fire mission, so it lifts before they arrive
	["prepMinFriendlyDist", 150],
	["smartMomentum", true],
	["momentumFastSeconds", 420],
	["momentumMinStrength", 0.6],
	["momentumWeakMen", 6],
	["momentumHoldSeconds", 120],
	["momentumGoWait", 20],
	["momentumGoWindow", 120],        // the short go-wait only applies for this long after the vote window closes
	["smartScout", true],
	["scoutMinGroups", 4],
	["scoutDist", 300],
	["scoutMaxSeconds", 150],         // at least this long; more when the walk needs it
	["scoutCapSeconds", 360],
	["footSpeedEstimate", 4],         // metres per second, for time limits on walking orders
	["scoutVehicleSpareCP", 300],
	["scoutVehicleWait", 70],         // extra time allowed for a bought vehicle to land before the scout gives up
	["smartHunt", true],
	["huntRadius", 800],
	["huntOffset", 150],              // metres from the wreck towards the objective; AT teams fire from about this far
	["huntSeconds", 150],             // time at the spot, on top of the walk
	["smartDigIn", true],
	["digInGroups", 1],
	["digInSeconds", 90],
	["smartPersonality", true],
	["personalityForce", ""],         // "aggressive", "cautious" or "sneaky" forces one
	["smartMemory", true],
	["memoryLossFraction", 0.5],
	["memoryMinMen", 3],
	["memoryAvoidDegrees", 40],
	["smartJoinPush", true],
	["joinPushRange", 900],           // only players this close to the target count as pushing it
	["joinPushMinMetres", 20],        // closer by this much since the last tick counts as moving towards it
	["joinPushRadius", 500],
	["joinPushGroups", 2],
	["joinPushSeconds", 240],
	["joinPushCooldown", 240]
];
