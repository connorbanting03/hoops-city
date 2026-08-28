class_name LeagueGenerator
extends RefCounted
## Builds the starting 8-team league (GDD §4.6): you begin as the worst team, and one AI
## franchise is the pre-seeded dynasty with the most banners. Procedural + reproducible.

const TEAM_NAMES := [
	["Riverton", "Otters"], ["Cedar Falls", "Pioneers"], ["Bayview", "Surge"],
	["Mapleton", "Lumberjacks"], ["Fort Casey", "Sentinels"], ["Lake Verde", "Herons"],
	["Sunnydale", "Comets"], ["Granite City", "Quarry"],
]

# A position-balanced 12-man squad: 2 PGs, wings, shooters, and three bigs.
const ROSTER_RECIPE := [
	"Floor General", "Slasher", "Sharpshooter", "3-and-D Wing",
	"Two-Way Star", "Glue Guy", "Stretch Big", "Bruiser",
	"Rim Protector", "Slasher", "Floor General", "Project",
]

const HISTORY_SEASONS := 15
const STARTING_CASH := 50_000_000   # every team opens with a reserve in the bank

# Strength ladders indexed by team slot. Slot 0 = dynasty, last slot = the player (clearly
# the worst). Middle slots form a believable spread.
const TALENT_LADDER := [14.0, 7.0, 4.0, 1.0, -2.0, -4.0, -6.0, -12.0]
const TITLE_LADDER := [7, 3, 2, 1, 1, 1, 0, 0]   # sums to HISTORY_SEASONS; dynasty owns the most
const MARKET_LADDER := [1.7, 1.25, 1.1, 1.0, 0.95, 0.9, 0.85, 0.7]

static func generate_league(rng: RandomNumberGenerator, opts: Dictionary = {}) -> LeagueData:
	var league := LeagueData.new()
	league.season_year = int(opts.get("year", 2026))

	var pid := 0
	for i in TEAM_NAMES.size():
		var t := TeamData.new()
		t.id = i + 1
		t.name = "%s %s" % [TEAM_NAMES[i][0], TEAM_NAMES[i][1]]
		t.abbrev = (TEAM_NAMES[i][1] as String).substr(0, 3).to_upper()
		t.market_size = MARKET_LADDER[i]
		t.cash = STARTING_CASH
		t.championships = TITLE_LADDER[i]
		var talent: float = TALENT_LADDER[i]
		var ros: Array[PlayerData] = []
		for arch in ROSTER_RECIPE:
			ros.append(PlayerGenerator.generate_player(rng, {"archetype": arch, "id": pid + 1, "talent_bonus": talent}))
			pid += 1
		t.roster = ros
		league.teams.append(t)

	league.dynasty_team_id = league.teams[0].id

	var player_team := league.teams[league.teams.size() - 1]
	player_team.is_player_team = true
	player_team.championships = 0
	league.player_team_id = player_team.id

	_seed_history(league, rng)
	return league

static func _seed_history(league: LeagueData, rng: RandomNumberGenerator) -> void:
	# Expand each team's title count into a pool of champion-ids, then deal them across years.
	var pool := []
	for t in league.teams:
		for k in t.championships:
			pool.append(t.id)
	while pool.size() < HISTORY_SEASONS:
		pool.append(league.teams[0].id)
	_shuffle(pool, rng)

	var hist := []
	for s in HISTORY_SEASONS:
		var year := league.season_year - HISTORY_SEASONS + s
		var cid: int = pool[s]
		var champ := league.get_team(cid)
		var cname := "Unknown"
		if champ != null:
			cname = champ.name
			if year > champ.last_title_year:
				champ.last_title_year = year
		hist.append({"year": year, "champion_id": cid, "champion_name": cname})
	league.history = hist

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
