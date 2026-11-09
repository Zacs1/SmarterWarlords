// SmarterWarlords commander: every tunable value lives here.
// Map-specific values go in maps\<worldName>.sqf, which overrides these keys.
// Values are starting points and are tuned by testing; see the design doc.

SWLC_settings = createHashMapFromArray [
	// Master switch
	["commanderEnabled", true],
	// Defenders fortify (fortify.sqf). Works in vanilla rules and the rules variant alike.
	["fortifyEnabled", true],
	["fortifyMaxPerSector", 4],          // hard cap per sector, whatever the stance says
	["fortifyBuyPerTick", 1],            // guns bought per 10 s tick, so a threatened sector fills up over a minute or so
	["fortifyStaticsAttack", 2],         // guns per sector while the commander is attacking, it needs the CP for the attack
	["fortifyStaticsHold", 4],
	["fortifyStaticsRebuild", 4],
	["fortifyCpFractionAttack", 0.25],   // a gun may cost at most this share of free CP (CP above the reserve)
	["fortifyCpFractionHold", 0.6],
	["fortifyCpFractionRebuild", 0.6],
	["fortifyMix", ["MG", "AT", "GL", "MG"]], // what to buy, in order; a kind that can't be had gives way to the next
	["fortifyPreferHigh", true],         // the raised tripod versions of the MG and GL, to see over grass and walls
	["fortifyEdgeFraction", 0.4],        // how far out along the approach, as a share of the sector's width (0.5 is the edge)
	["fortifyMinCentreDist", 40],        // metres. Never closer to the sector centre than this
	["fortifySpacing", 30],              // metres between guns at one sector
	["fortifyRoadClear", 8],             // metres clear of any road
	["fortifyMaxGradient", 0.4],
	["fortifyCoverRange", 200],          // metres of open terrain wanted along the line of fire. Any valid spot if none has it
	["fortifyNoSpotRetry", 60],          // seconds before looking again at a sector with no valid ground
	["fortifyRespectEnemyNear", true],   // no buying with an enemy near, as Warlords refuses a player placing a defence
	["fortifyReplaceSeconds", 240],      // a destroyed gun still counts against the cap for this long
	["fortifyCrewReach", 300],           // metres. Men further than this from a gun or road spot aren't sent
	["fortifyMaxCrewPerGroup", 2],       // the rest of the group keeps its normal job
	["fortifyCrewWalkSeconds", 30],      // time allowed to reach a gun is this...
	["fortifyCrewWalkSpeed", 2.5],       // ...plus the distance at this many metres a second
	["fortifyCrewSeatDist", 12],         // metres. Beside the gun when the time runs out: seated directly rather than given up on
	["fortifyATMen", 2],                 // AT soldiers covering the approach road, per alert
	["fortifyATReachFraction", 0.75],    // road points further from the centre than this share of the sector's width are ignored
	["fortifyATRoadOffset", 12],         // metres off the road
	["fortifyATLookRange", 150],
	["fortifyATArrive", 6],              // metres from the spot that counts as arrived
	["fortifyATWalkSeconds", 120],
	["fortifyATDrift", 25],              // pushed further than this off the spot and he is sent back...
	["fortifyATDriftMax", 2],            // ...this many times, then released
	["fortifyRefuseLogSeconds", 60],     // one log line per sector and reason in this long
	["killLog", true],                // one C_KILL line per man killed, with position and sides, for the front-line analysis

	// A group a human was in within this many seconds is never ordered
	["playerGroupGrace", 120],

	// Timing
	["tickYieldSeconds", 0.01],       // pause between the slices of a tick, enough to reach the next frame
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
	["voteStuckSeconds", 120],        // nudge Warlords' vote after this long with no target; 0 is off
	["voteStuckRepeatSeconds", 60],   // gap between nudges
	["deadlockSeconds", 720],         // force a new vote if a target hasn't fallen after this long

	// Rules variant: "rulesVariant" is the lobby's on/off. Each rule below also has its own switch.
	["rulesVariant", true],

	// Part B: breaking deadlocks
	["ruleCapturePause", true],       // capture progress pauses, then decays, instead of resetting
	["capturePollSeconds", 0.5],
	["captureHoldSeconds", 30],       // progress holds this long after attackers are pushed off
	["captureDecayPerSecond", 0.25],  // then this many seconds of the countdown come back per second
	["captureMinRemaining", 5],       // a countdown is never shorter than this
	["ruleNoRespawnSeized", true],    // AI warlords that respawn inside a sector being seized are moved out
	["respawnCheckSeconds", 8],
	["respawnSectorMargin", 50],
	["ruleCommitTimer", true],        // a target that has stalled gets a decision
	// Parts A and C: holding a lost sector. See holdouts.sqf.
	["ruleHoldouts", true],           // groups still inside a sector the side loses stay and fight, and reinforcements go to them first
	["holdoutCheckSeconds", 3],
	["holdoutMargin", 60],            // a group this far outside the square still counts as inside when the sector falls
	["holdoutVoteGrace", 150],        // how long the side may be without the sector as its target (a Warlords vote) before the holdouts give up
	["holdoutUnprotectGrace", 60],    // a sector added to the conquered list comes off this long after the holdouts are done
	["holdoutCoverRadius", 120],      // where holdouts look for cover around the sector
	["holdoutGarrison", true],        // with LAMBS, holdouts garrison the buildings
	["holdoutSettleSeconds", 20],     // at their spot this long before garrisoning
	["holdoutBreakFraction", 0.34],   // at or below this share of its men a holdout group falls back
	["holdoutFallbackBeyond", 40],    // the fallback point is this far outside the square, on the way to the nearest owned sector
	["holdoutFallbackMax", 300],      // and never further than this from the sector centre
	["holdoutCoverSearch", 60],       // cover is searched this close to the fallback point
	["holdoutArriveMargin", 30],      // a reinforcement has arrived when it is this close to the square
	["holdoutResupply", true],        // buy a crate for holdouts who are low
	["holdoutResupplyCost", 200],     // CP, only out of what is above the reserve
	["holdoutResupplyCooldown", 240],
	["holdoutResupplyFirstDelay", 30],
	["holdoutResupplyDelay", 30],     // seconds from paying to the crate landing
	["holdoutRestock", true],         // a holdout in combat or garrisoned takes from a delivered crate where he stands
	["holdoutRestockSeconds", 15],
	["holdoutSwitching", true],       // part C: the goal switches to defending the next sector when fighting starts there
	["holdClearSeconds", 120],        // that sector counts as clear after this long with no fighting and no enemy known inside
	["holdNearXMetres", 350],         // a group fighting this close to the lost sector is not pulled away
	["holdDefendNearMetres", 150],    // a group this far outside the threatened sector's square turns to defend it
	["commitSeconds", 660],           // 11 minutes on one target
	["commitExtendSeconds", 180],     // staying buys this much more time
	["commitMaxExtensions", 2],
	["commitStayProgress", 0.5],      // capture progress that always counts as close to winning
	["commitStayProgressRecent", 0.25], // lower bar when the countdown was running recently
	["commitRecentSeconds", 90],
	["commitLossRatio", 2],           // own men lost per enemy killed that counts as clearly losing
	["commitFailedPushes", 2],
	["commitRebuildMenPerGroup", 2],  // losing and below this average: pull back rather than switch
	["commitProbeWeakBonus", 40],     // vote score bonus for a sector a probe found weak

	// Front line part B: defenders keep fast travel to their own sector until real fighting reaches it
	["ruleDefenderFT", true],
	["frontAreaMargin", 175],         // the area: the capture square plus this many metres
	["frontPollSeconds", 5],
	["frontWindowSeconds", 30],       // sustained: this many seconds per window...
	["frontWindowsTotal", 3],         // ...looking at this many finished windows...
	["frontWindowsNeeded", 2],        // ...and this many had real fighting in them
	["frontExchangeSeconds", 8],      // both sides fired, or someone died, within this long counts as an exchange now
	["frontWindowMinHits", 2],        // polls with an exchange before a window counts, so one burst can't fill two windows
	["frontSeizeMinMen", 3],          // enemy men in the capture square for a seize to count; a lone infiltrator never closes fast travel
	["frontMinAttackers", 3],         // attackers who fired, came under fire or died here
	["frontInvolvedSeconds", 90],     // how far back an attacker still counts as involved
	["frontQuietSeconds", 120],       // real fighting or a seize gone this long lifts it
	["frontRadioCooldown", 30],       // per side, between "closed" lines and between "open" lines
	["rebuildSeconds", 240],
	["abandonBanSeconds", 900],       // an abandoned target can't be picked again for this long
	["switchWithdrawSeconds", 60],    // longest wait for attackers to leave the old target
	["switchClearMargin", 25],

	// Muster: groups form up at their own sector, then leave for the rally
	["rollingMuster", true],          // each group leaves as soon as it is ready, instead of waiting for the others at the sector
	["musterGroupSeconds", 15],       // rolling muster: a group spends this long at the sector to buy and pick up kit
	["musterSeconds", 30],            // the short wait after the first group arrives at a sector
	["musterMaxSeconds", 70],         // longer only while men just bought are still landing
	["musterHopGain", 800],           // fast travel to a sector this much closer to the target, if the group has one
	["stagingPlaceExpr", "(1 + houses * 2 + trees) * (1 - sea)"],
	["stagingSpotSeparation", 18],
	["stagingFarThreshold", 500],     // farther than this from a muster or defence spot: fast travel if allowed
	["arriveRadius", 75],

	// Rally and go
	["goMinGroups", 2],               // groups ready at the rally that go in together
	["rallyLoneWait", 60],            // a lone group with nobody fighting waits this long, then goes in anyway
	["rallyOutside", 200],            // metres outside the sector square
	["rallyJoinRadius", 500],         // a group this close to the rally skips the muster
	["rallyMinAgreement", 0.3],       // how much the groups' directions must agree before their average is used
	["holdArriveRadius", 60],
	["waveNearRadius", 700],          // groups this close count as having taken part when a sector falls
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
	["escalateAfterResets", 2],       // only used with resLadder off

	// Resilience. Not part of rulesVariant: stays on when that's off.
	["resilience", true],             // master switch for everything in this section
	["testHooks", false],             // lets a test sabotage a group's handling. Never on in a real game

	// The sweep: every group has a task, an order and a goal that still makes sense
	["resSweep", true],
	["resSweepGraceSeconds", 15],     // a job this new hasn't had time to get its order or settle
	["resNotAtGoalMetres", 150],      // order finished this far from the goal means it stopped short
	["resHuntOverdueSeconds", 30],    // past the hunt's end by this long and nothing has ended it
	["resLostScanSeconds", 30],       // how often to look for groups the commander has lost track of
	["resFixWindowSeconds", 120],
	["resFixesToLadder", 3],          // this many fixes inside the window and the group goes to the ladder
	["resWaterRescue", true],         // a group swimming in deep water is fast travelled out instead of swimming for minutes
	// Fights on the way (engaged.sqf). AI behaviour, so it stays on with the rules variant off, like resilience.
	["behEngaged", true],             // a group in transit that meets the enemy stops and fights
	["fightingWindow", 90],           // seconds since a man last fired or was fired on before his group stops counting as fighting
	["contactAttachSeconds", 5],      // how often new units get the fire-tracking handlers
	["engagedStates", ["Travelling", "Advancing"]],  // the jobs that count as in transit
	["engagedObjectiveMargin", 300],  // this close to the objective's square, the wave's own rally and go rules apply instead
	["engagedRange", 300],            // a group that is fighting stops for enemy known this close
	["engagedCloseRange", 120],       // any group in transit stops for enemy known this close, shot at or not
	["engagedContactAge", 60],        // a sighting older than this doesn't count
	["engagedMergeMetres", 250],      // contacts this close together are one fight
	["engagedReorderMetres", 80],     // the fight order moves when the contact has moved this far
	["engagedClearSeconds", 40],      // no enemy known near and this long without a shot: the fight is over
	["engagedRetriggerSeconds", 30],  // after a fight, how long before the group can stop for another
	["engagedJoin", true],            // nearby free groups can join
	["engagedJoinRadius", 600],
	["engagedJoinStates", ["Reserve", "Unassigned", "Waiting", "Advancing", "Travelling"]],
	["engagedFallback", true],        // a much bigger enemy sends the fight back to the nearest owned sector
	["engagedFallbackRatio", 2.5],    // enemy strength this many times the men on hand (a combat vehicle counts as 5 more)
	["engagedFallbackMinMen", 10],    // never fall back from a force smaller than this
	["engagedFallbackHoldSeconds", 150], // how long that sector stays on the threat list with nothing sighted near it
	["engagedVehicles", true],        // transports dismount short of the contact and pull back
	["engagedTransportBack", 200],    // how far the transport drives back
	["engagedPullBackSeconds", 45],   // longest the driver takes before he gets out and walks in
	// The water rescue, continued
	["waterRescueSeconds", 20],       // in deep water this long before the rescue
	["waterRescueDepth", 1.5],        // metres of water under the leader that count as deep

	// The ladder: re-issue, another route, dismount, fast travel, respawn at base
	["resLadder", true],
	["ladderRungSeconds", 25],        // how long a rung gets to work before the next
	["ladderProgressMetres", 30],     // closer to the goal by this much since the last rung ends the climb
	["ladderSameGoalMetres", 100],    // a goal moved further than this is a new job, and the climb starts over
	["ladderFTCandidates", 3],        // owned sectors to try for the fast travel rung
	["ladderLandRadius", 30],         // how far to look for safe ground for an order
	["ladderRespawn", true],          // the last rung
	["ladderMinClimbSeconds", 75],    // the last rung waits this long after the first, however fast the others fell through
	["ladderRefundFactor", 1],        // share of the bought men's list price paid back
	["ladderRespawnVerifySeconds", 15],
	["ladderRespawnMax", 4],          // most last-rung replacements per side inside the window; past that the group gets a reachable job
	["ladderRespawnWindowSeconds", 600],
	["ladderJobHoldSeconds", 180],    // a group sent to hold because it can't reach the operation isn't sent back to it for this long

	// Idle cap: too much of a side standing about means a new plan
	["resIdleCap", true],
	["idleCapShare", 0.20],           // above this share of the side's groups
	["idleCapMinGroups", 3],          // a side this small isn't judged
	["idleCapCooldownSeconds", 180],
	["idleGraceSeconds", 30],         // Unassigned this long counts as idle
	["idleMusterMargin", 30],         // past musterMaxSeconds by this much
	["idleWaitingMargin", 60],        // past the rally's lone wait by this much

	// Protecting the commander from one group's script error, and from the loop dying
	["resGroupGuard", true],
	["resSupervisor", true],
	["supervisorPollSeconds", 5],
	["supervisorStaleSeconds", 45],   // no heartbeat for this long and the loop is restarted. Keep well above tickSeconds
	["quarantineSeconds", 60],        // a group whose handling failed stays out of the commander's list this long
	["quarantineRepeatWindow", 600],
	["quarantineRepeatLimit", 2],     // this many failures inside the window and the group goes straight to the last rung
	["stageFaultGroups", 3],          // this many groups failing in one stage inside the window: the stage is blamed, not the groups
	["stageFaultWindowSeconds", 30],

	// Locality
	["resLocality", true],

	// Resilience: "resilience" gates every behaviour below. It stays active when the rules variant is off.

	// Route network: long moves follow roads and tracks in short hops
	["routeNetwork", true],
	["routeHopMetres", 350],          // grid square used to thin the network, and the spacing of hops
	["routeMinMetres", 700],          // moves shorter than this stay direct
	["routeHopRadius", 40],           // a hop counts as reached this close
	["routeAttachMetres", 600],       // how far a position can be from the network and still join it
	["routeMaxDetour", 2.5],          // a road this many times the straight line is ignored if the straight line is open ground
	["routeOffRouteMetres", 800],     // further than this from every remaining hop and the group gets a new route
	["routeAvoidPenalty", 6],         // how much dearer an avoided node is when finding another route
	["routeAvoidSeconds", 300],       // how long a route that failed stays avoided
	["routeGoalMatchMetres", 200],    // a route counts for progress only if it ends this close to the group's goal
	["routeMaxExpansions", 3000],     // limit on one path search
	["routeSectorRoadRadius", 1000],  // furthest a sector can be from its nearest road and still seed the network
	["routeGapJoinMetres", 25],       // a road's dead end joins any road this close, for breaks in the road data
	["routeBuildBatch", 50],          // road segments or loop steps handled per frame while building
	["routeMaxSegments", 80000],      // safety limit on road segments read while building
	["routeLogNetwork", true],        // write a generated network to the RPT for tools/extract_routes.py
	["routeCacheMax", 4096],          // entries per route cache before it's emptied

	// No land moves across water
	["noWaterMoves", true],
	["routeWaterSample", 25],         // metres between water samples on a straight line
	["routeOriginSnapMetres", 80],    // a point in the water counts from dry ground this close to it
	["routeFTNearMetres", 300],       // an owned sector this close to a destination is good enough to fast travel to
	["routeBlockedRetrySeconds", 20], // how often a group with no land route retries, fast travel included

	// Every destination goes to open ground
	["validateDestinations", true],
	["routeSafeSearchMetres", 120],   // how far a destination can be moved to reach open ground
	["routeSafeStep", 8],             // spacing of the rings searched
	["routeSafeMargin", 2],           // metres kept clear of a building or rock
	["routeSafeMaxSlopeDeg", 40],     // ground steeper than this isn't open
	["routeSafeSkipNearMetres", 30],  // a destination this close to the leader is left alone

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
	["radioCooldowns", createHashMapFromArray [["sighting", 15], ["arrived", 20], ["leaving", 15], ["rally", 15], ["reinforce", 20], ["staging", 20], ["seized", 5], ["moveout", 10], ["failed", 20], ["mount", 20], ["kit", 30], ["stuck", 30], ["defend", 20], ["standdown", 20], ["stagingattack", 20], ["reqok", 5], ["reqno", 5], ["report", 15], ["heavy", 25], ["breaking", 15], ["cheer", 5], ["momentum", 30], ["scout", 30], ["hunt", 30], ["digin", 30], ["prepfire", 30], ["joinpush", 30], ["smoke", 20], ["commitstay", 60], ["commitswitch", 30], ["commitrebuild", 30], ["commitvote", 30], ["econcut", 120], ["econcornered", 300], ["econcounter", 60], ["econdefended", 120], ["econdugin", 60], ["econlimit5", 0], ["econlimit1", 0], ["econsuddendeath", 0], ["econlimitwin", 0], ["econlimitloss", 0], ["flank", 45], ["raidno_off", 3], ["raidno_active", 3], ["raidno_cooldown", 3], ["raidno_not_front", 3], ["raidno_funds", 3], ["menubad", 3], ["borrowok", 3], ["borrowno", 3], ["borrowmax", 3], ["holdok", 3], ["holdno_noop", 3], ["holdno_assault", 3], ["holdno_used", 3], ["gook", 3], ["gono", 3], ["gono_going", 3], ["reportno", 3], ["defendok", 3], ["defendthin", 3], ["defendbad", 3], ["pickupok", 3], ["pickupno", 3], ["pickupbusy", 3], ["pickupbad", 3], ["pickuphere", 3], ["pickupfail", 3], ["releaseok", 3], ["releasenone", 3], ["plan", 5], ["planidle", 5]]],

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
	["mountCapSeconds", 60],          // after the muster ends
	["mountLateExtra", 45],           // a group not ready at the cap is a second element, this long at most
	["vehStuckWindow", 25],
	["vehStuckMinMetres", 15],
	["vehStuckLimit", 2],
	["vehUnstick", true],             // a stuck vehicle travelling well away from any fight is lifted to a clear spot nearby and carries on
	["vehUnstickEnemyRadius", 300],   // no lift with an enemy this close
	["vehUnstickPlayerRadius", 150],  // nor a player close enough to watch it happen
	["vehUnstickZoneRadius", 350],    // nor this close to the edge of a sector either side is attacking
	["vehUnstickAhead", 60],          // looks for a road this far ahead, towards where it was going
	["vehUnstickCooldown", 45],
	["vehUnstickMax", 3],             // lifts before the men get out and walk
	["vehUnstickResetMetres", 100],   // driving this far in one check counts as recovered, and the lifts are forgotten
	["vehReclaimSeconds", 180],       // a vehicle men gave up on can't be claimed again for this long
	["vehDepartGap", 8],              // seconds between vehicles pulling out of the same sector
	["vehSlowNearby", true],          // slow down near other vehicles and sectors, where the pile-ups happen
	["vehSlowRadius", 40],            // another vehicle this close ahead
	["vehSlowSectorRadius", 120],     // metres from a sector's edge
	["vehSlowSpeed", 8],              // metres per second
	["combatFollowDist", 75],         // metres behind the lead infantry (50 to 100 in the design)
	["combatReorderDist", 50],
	["combatNudgeSeconds", 100],      // keeps Warlords' stuck check from abandoning a holding crew

	// Defence
	["defenceEnabled", true],
	["reserveBySectors", [[5, 1], [10, 2], [1000000, 3]]],  // up to N sectors owned -> reserve groups
	["reserveRotate", true],          // reserve duty goes round: the group that has served least is kept, and nobody stays for good
	["reserveStintSeconds", 360],     // held back this long with a wave out, a group goes to join the attack
	["reserveRestSeconds", 420],      // and can't be picked for the reserve again for this long
	["reservePatrolSeconds", 150],    // a waiting group moves this often, or Warlords treats its leader as stuck
	["defenceRadius", 400],           // metres outside the sector square that count as near it
	["defenceMinInfantry", 4],
	["defenceSightAge", 90],          // only sightings this recent count as a live threat
	["defenceStandDownSeconds", 120],
	["defenceMenPerGroup", 5],
	["defenceMaxGroups", 3],
	["defenceValueStaging", 100],     // a sector with a muster running, or a base, is always worth pulling attackers for
	["defenceValueBase", 100],

	// Players
	["playerReportRange", 2500],
	["playerReportConf", 0.9],
	["playerReportMax", 8],
	["requestGoMinGroups", 1],
	["requestDefendSeconds", 300],
	["planPublishSeconds", 20],
	["statusPublishSeconds", 10],     // the commander panel's data
	["planAlwaysPublish", false],     // test switch: publish the plan with no players connected

	// Difficulty. The lobby parameter wins over "difficulty" in hosted games. A preset sets the keys listed.
	["difficulty", "normal"],         // "easy", "normal" or "hard"
	["reactionDelay", 0],             // seconds before a new sighting affects plans and defence (radio is not delayed)
	["difficultyPresets", createHashMapFromArray [
		["easy", [["intelDecayMultiplier", 0.6], ["shopGroupSize", 2], ["reactionDelay", 20], ["scanBuying", false]]],
		["normal", [["intelDecayMultiplier", 1], ["shopGroupSize", 3], ["reactionDelay", 0], ["scanBuying", true]]],
		["hard", [["intelDecayMultiplier", 1.5], ["shopGroupSize", 4], ["reactionDelay", 0], ["scanBuying", true]]]
	]],
	["verboseLog", true],             // per-vehicle and per-guard lines for the test analyser; the playable build turns them off
	["profileStages", false],         // test switch: log the cost of each stage of the commander tick

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
	["defencePayoutCooldown", 300],   // seconds before the same sector can pay for a defence again
	["defencePayoutMinEnemies", 3],   // most enemy men seen in the sector during the countdown must reach this

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

	// Part H: smarter squads. One switch per behaviour.
	["squadPosture", true],           // formation, speed and stance by situation
	["squadBounding", true],          // two fire teams leapfrog from the rally inward
	["squadFlank", true],             // pinned squads suppress and flank (always off while LAMBS is loaded)
	["squadRearm", true],             // soldiers low on ammo restock nearby
	["squadLambs", true],             // hand garrison and building clearing to LAMBS when it's loaded
	["squadSlices", 2],               // groups are worked through over this many commander ticks

	["squadPostureStates", ["Travelling", "Advancing", "Assaulting", "Borrowed"]],
	["squadPostureHoldSeconds", 30],  // minimum time in a posture before leaving it, except to go careful
	["squadRoadTarget", 800],         // column on roads only further than this from the target
	["squadRoadContact", 600],        // and further than this from any recent sighting
	["squadRoadRadius", 30],          // how close a road has to be to count
	["squadRoadBehaviour", "AWARE"],
	["squadOpenFormation", "WEDGE"],
	["squadCarefulTarget", 350],      // slow down this close to the target
	["squadCarefulContact", 250],     // or this close to a recent sighting
	["squadCarefulExitExtra", 100],   // extra distance before leaving careful, so it doesn't flip
	["squadCarefulSpeed", "NORMAL"],

	["bpMinMen", 3],                  // too small to split below this
	["bpMinMetres", 50],              // length of one bound
	["bpMaxMetres", 100],
	["bpStartExtra", 100],            // starts this far outside the rally's distance to the target
	["bpStartMetres", 400],           // start distance if the op has no rally
	["bpInsideFraction", 0.5],        // ends this far into the sector, as a share of its half-size
	["bpCoverRadius", 25],            // cover this close to a bound's end point is used
	["bpReachMetres", 15],
	["bpPhaseSeconds", 30],           // a bound ends after this even if the team hasn't arrived
	["bpMaxSeconds", 180],
	["bpCooldownSeconds", 60],
	["bpCqbDist", 40],                // normal movement with a sighting this close
	["bpCqbRadius", 40],              // normal movement with this many buildings this close
	["bpCqbBuildings", 4],

	["pinnedSuppression", 0.25],      // average getSuppression that counts as pinned
	["pinnedSeconds", 45],            // and no progress for this long
	["pinnedMoveMetres", 15],         // what counts as progress
	["flankMinMen", 4],
	["flankOffset", 100],
	["flankMaxSeconds", 150],
	["flankGiveUpLoss", 0.5],         // gives up after losing this share of the squad
	["flankSuppressSeconds", 9],
	["flankCooldownSeconds", 120],

	["rearmCheckSeconds", 45],
	["rearmRadius", 60],              // how far a soldier will go for ammo
	["rearmReach", 4],
	["rearmTripSeconds", 45],
	["rearmPrimaryMags", 1],          // rifle magazines left that counts as low
	["rearmTakeRockets", 2],
	["rearmTakeRifle", 3],

	["lambsIntelMinKnows", 1.5],      // replaces intelMinKnows while LAMBS is loaded, see section 4
	["lambsLeaderMoveSeconds", 240],  // a holding leader takes a short walk this often, because Warlords kills AI warlords that never move
	["rearmBackoffSeconds", 120],     // after a failed or impossible rearm, the group leaves it this long
	["rearmTriesPerCheck", 4],        // men looked at per check before giving up
	["rearmRifleMinRounds", 4],       // magazines smaller than this are grenades and flares, not rifle ammo
	["lambsBusyHoldSeconds", 12],     // keep treating a group as busy this long after LAMBS lets go
	["lambsMaxCqb", 2],               // groups clearing buildings at once, per side
	["lambsClearRadius", 150],
	["lambsMinBuildings", 2],
	["lambsCqbCycle", 21],
	["lambsCqbSeconds", 240],
	["lambsCheckSeconds", 12],
	["lambsRetrySeconds", 60],
	["lambsHoldDelay", 45],           // a defending group settles this long before garrisoning
	["lambsHoldReach", 40],           // and has to be this close to its spot
	["lambsHoldRadius", 75],

	// Part F: the commander menu
	["ruleCommanderMenu", true],
	["menuTestAllowAI", false],          // lets the gatef scenario's AI stand-in count as a requester; never on in play
	["menuCooldownSeconds", 15],         // per player, per option
	["menuCooldowns", createHashMapFromArray [["plan", 10], ["release", 5], ["report", 10], ["raid", 10]]],
	["menuKeepGroups", 2],               // attack groups the commander never lends out
	["menuBorrowGroups", 3],             // most one player can have
	["menuBorrowMinGroups", 2],          // fewer than this spare and a first request is refused
	["menuFollowFar", 700],              // further than this and a borrowed group fast travels if that helps
	["menuFollowFTSeconds", 120],
	["menuFollowFTGain", 300],           // the hop must bring it this much closer
	["menuFollowDist", 40],              // reissue the order once the player has moved this far
	["menuFollowRefresh", 60],           // reissue anyway this often, or Warlords treats a waiting leader as stuck
	["menuFollowCombatDist", 200],       // in a fight, only reissue beyond this
	["menuHoldSeconds", 120],
	["menuHoldSideCooldown", 300],
	["menuDefendValue", 100],            // added to the sector's worth while a request lasts
	["menuPickupMaxActive", 1],
	["menuPickupBoardSeconds", 90],
	["menuPickupArriveDist", 60],
	["menuPickupRefreshMetres", 100],
	["menuPickupTimeoutSeconds", 420],   // each of the two stages, getting aboard and the drive, gets this long
	["menuPickupMaxDistance", 1500],     // spare groups further than this from the player can't bring a vehicle

	// Rules variant, part G: what the commander values
	["ruleStrategy", true],           // sectors are worth what they unlock and what they connect
	["stratLetterWeights", createHashMapFromArray [["A", 25], ["M", 25], ["I", 15], ["R", 12], ["T", 10], ["W", 6]]],
	["stratHaveFactor", 0.5],         // a capability the side already has counts for this much
	["stratCutWeight", 10],           // per sector that would lose its road home
	["stratCutLetterFactor", 0.5],    // and this share of each capability the owner would lose outright
	["stratMomentumWeight", 0.2],     // when pressing on, this many men's worth of leeway per point of sector worth
	["stratBaseLoneWaitMult", 2],     // a lone group waits this much longer before going in on the enemy base
	["ruleFortressAware", true],      // the enemy base is a hard final fight
	["stratBaseGoExtra", 1],          // extra groups ready at the rally before going in on the base
	["stratBaseAtWanted", 2],         // launchers the final attack brings at least
	["stratBaseMinMen", 20],          // below this many men the base is a poor target
	["stratBaseEarlyPenalty", 40],

	// Rules variant, part E: pickets and proportionate response
	["rulePickets", true],
	["picketMaxFraction", 0.34],      // no more than this share of the side's groups on picket duty
	["picketKeepAttackers", 3],       // pickets can't take the attack below this many groups
	["picketRotateSeconds", 480],     // a picket hands over after this long, so no commander stands watch all round
	["picketRestSeconds", 300],       // and can't be put on picket again for this long
	["picketBases", false],           // whether a base counts as a front-line sector
	["ruleProportionate", true],
	["responseMargin", 1.25],         // sends enough to beat the reported force by this much
	["responseCapFraction", 0.34],    // no more than this share of the main attack peels off for one raid
	["responseCounterattackMen", 12], // a force this strong is a counterattack: the full defence rules apply
	["peelWorkableGroups", 3],        // below this many groups the wave waits at the rally for the responders
	["peelHoldMaxSeconds", 240],      // how long it waits for them
	["peelReturnGrace", 120],         // responders count as on their way back for this long after standing down
	["defHopMinGain", 150],           // a responder only fast travels if that brings it this much closer

	// Rules variant, part D: raids and probes
	["ruleRaids", true],
	["raidCostCP", 300],              // a raid order costs this, for players and AI alike
	["raidSeizeMult", 2.5],           // a raid takes this many times as long to seize as a main target
	["raidCooldownSeconds", 600],     // after a raid ends, how long before the side can order another
	["raidExpirySeconds", 480],       // a raid not finished by then is called off
	["raidExpiryTravelSeconds", 360], // on a big sector, at least this long on top of the capture itself
	["raidGraceExtraSeconds", 60],    // the sector stays open this much longer while raiders are still inside
	["raidGraceSeconds", 60],         // raiders have this long to leave a called-off raid before Warlords' kill zone returns
	["raidDisabledSeconds", 100000],  // the raid trigger's countdown during the grace period
	["raidDecideSeconds", 45],        // how often an AI commander considers ordering one
	["raidAIOnPlayerSide", false],    // AI commanders on a side with players don't spend on raids unless this is on
	["raidKeepGroups", 3],            // attack groups a raid or probe can't take the side below
	["raidAIMinGroups", 1],
	["raidAIGroups", 2],              // groups the AI commander sends on a raid
	["raidMaxDefenders", 3],          // weighted enemy strength the AI will raid
	["raidMaxDefendersStuck", 8],     // the same when the main attack is going badly: a raid that draws defenders away is useful
	["raidStuckAfterSeconds", 300],   // the main attack counts as going badly after this long, or after a failed push
	["raidDefenderWeight", 5],
	["raidUnscoutedPenalty", 20],
	["ruleProbes", true],
	["probeEverySeconds", 270],
	["probeEveryBadSeconds", 150],    // the interval when the main attack is going badly
	["probeMinMen", 12],              // below this many men the side doesn't probe
	["probeRepeatSeconds", 300],      // the same sector isn't probed again for this long
	["probeObserveDist", 250],        // how far from the sector the probe stops to look
	["probeArriveDist", 200],         // further than this from its spot and the probe never got there
	["probeObserveSeconds", 40],
	["probeBreakFraction", 0.6],      // breaks off below this share of the men it left with
	["probeOutmatchRatio", 1.5],      // or when known enemy strength is this many times its own men
	["probeLightlyHeldMen", 3],       // weighted enemy strength that counts as lightly held
	["probeWeakSeconds", 300],        // a sector found weak keeps the bonus for the commitment timer this long

	// Phase 6 behaviours: each one can be switched off here
	["smartBreak", true],
	["breakFraction", 0.34],          // a group at or below this share of its launch strength breaks off
	["breakMinLaunchMen", 3],
	["breakRestSeconds", 60],         // a group that fell back waits at least this long at the rally
	["mergeRadius", 150],
	["mergeMaxMen", 3],
	["smartRadio", true],
	["radioHeavyFraction", 0.4],      // share of a group lost that draws a "taking heavy fire" call
	["smartReinforce", true],
	["reinforceStallSeconds", 100],
	["reinforceMinMetres", 40],
	["smartSmoke", true],
	["smokeThrowDist", 40],
	["smokeGroupsPerPush", 1],
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
	["memoryAvoidDegrees", 25],
	["smartJoinPush", true],
	["joinPushRange", 900],           // only players this close to the target count as pushing it
	["joinPushMinMetres", 20],        // closer by this much since the last tick counts as moving towards it
	["joinPushRadius", 500],
	["joinPushGroups", 2],
	["joinPushSeconds", 240],
	["joinPushCooldown", 240],

	// Resilience. Master switch for the whole part; not tied to rulesVariant.

	// Upkeep (upkeep.sqf). Group repairs that run every tick.
	["upkeepSlices", 2],              // the heavier checks take this many ticks to go round every group
	["upkeepRoomExtra", 3],           // men a receiving group can hold above the side's squad size
	["upkeepNoFlee", true],           // commander groups never flee; the commander's own fall-back rules decide retreats
	["upkeepLeader", true],           // a group with a dead leader gets a new one and its orders again
	["leaderWarlordMetres", 150],     // a respawned warlord this close to the group's stand-in leader takes it back
	["upkeepStragglers", true],
	["stragglerMetres", 200],         // further than this from the leader counts as straggling
	["stragglerGraceSeconds", 30],    // must still be that far after this long
	["stragglerRecheckSeconds", 60],  // time between recalls of the same man
	["stragglerJoin", true],          // a straggler nearer another group joins it instead of walking back
	["stragglerJoinMetres", 500],     // furthest a straggler goes to join another group
	["upkeepRemnants", true],
	["remnantMaxMen", 2],             // a group with no living warlord and this few men merges into another
	["remnantMergeMetres", 400],      // furthest a remnant goes to merge
	["remnantGraceSeconds", 60],      // time for a dead warlord to respawn beside his men first
	["upkeepLeftovers", true],
	["leftoverSeconds", 45]           // men out of their vehicle, or left sitting in one, this long get picked up
];
