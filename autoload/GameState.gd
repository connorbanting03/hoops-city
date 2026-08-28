extends Node
## GameState — the single, savable source of truth for the whole world (§7.1, §7.2).
## Systems mutate this; the UI only reads it. Serialized to JSON with a version field
## so saves survive schema changes across patches (§7.5).

const SAVE_VERSION := 1
const SAVE_PATH := "user://hoops_city.save.json"

# --- World clock: cozy, player-paced time progression (§5.4) ---
const DEFAULT_YEAR := 2026
var current_year: int = DEFAULT_YEAR
var current_phase: String = "preseason"  # preseason / regular_season / playoffs / awards / draft / free_agency
var current_day: int = 0

# Source-of-truth containers, populated by later milestones:
#   league  -> M2 (LeagueData / TeamData)
#   economy -> M5 (EconomyManager state)
#   city    -> M6 (CityManager state)
# Held as a plain Dictionary for now so this skeleton stays parse-clean and
# JSON-serializable before those types exist.
var data: Dictionary = {}

# --- Full world (M9): the league + city, driven by FranchiseManager ---
const WORLD_PATH := "user://hoops_city_world.tres"
var league: LeagueData = null
var city: CityData = null
var last_season: Dictionary = {}   # most recent season's standings/games/bracket for the Season Center (M11); transient, not saved
var _rng := RandomNumberGenerator.new()

# --- interactive draft (M12): mid-offseason state while the player drafts ---
var draft_active: bool = false
var draft_order: Array = []          # team_ids, pick order
var draft_available: Array = []      # Array[DraftProspect] still on the board
var draft_board: Array = []          # picks made so far
var draft_pick_index: int = 0        # 0-based index into the pick sequence (rounds x order)
var draft_total: int = 0
var _offseason: Dictionary = {}      # carry data to finish the year after the draft

# --- interactive free agency (M13): day-based bidding after the draft ---
var fa_active: bool = false
var fa_pool: Array = []              # Array[PlayerData] still available
var fa_offers: Dictionary = {}       # fa_id -> {salary, years} — the player's standing bids
var fa_prefs: Dictionary = {}        # fa_id -> preference weights (stable across days)
var fa_day: int = 1
var fa_signings: Array = []          # running log of who signed where

# --- played, game-by-game regular season (the "play or sim" path) -----------
# The 2K-MyLeague backbone: the schedule is laid out once, then advanced one game at a time
# (watched or simmed) with standings building live, until it hands off to the playoffs. NOT yet
# serialized (v1) — a reload restarts the current season.
var season_schedule: Array = []      # flat [{home, away}] team-ids, in play order (SeasonManager.build_schedule)
var season_cursor: int = 0           # index of the next game to play
var season_pdiff: Dictionary = {}    # team_id -> running point differential
var season_games: Array = []         # Array[GameResult] played so far, in schedule order
var _played_season: Dictionary = {}  # the assembled full-season dict once the playoffs resolve (-> setup_offseason)

func new_game(seed_val: int = -1) -> void:
	if seed_val >= 0:
		_rng.seed = seed_val
	else:
		_rng.randomize()
	var w := FranchiseManager.new_game(_rng)
	league = w["league"]
	city = w["city"]
	last_season = {}
	_reset_draft()
	current_year = int(w["year"])
	current_day = 0
	start_regular_season()

func _reset_draft() -> void:
	draft_active = false
	draft_order = []
	draft_available = []
	draft_board = []
	draft_pick_index = 0
	draft_total = 0
	_offseason = {}
	fa_active = false
	fa_pool = []
	fa_offers = {}
	fa_prefs = {}
	fa_day = 1
	fa_signings = []

func advance_year() -> Dictionary:
	var res := FranchiseManager.advance_year(league, city, current_year, _rng)
	last_season = res.get("season", {})
	current_year += 1
	return res

# --- played regular season (the 2K-MyLeague phase machine) ------------------
# regular_season -> (35 games) -> playoffs -> draft -> free_agency -> (next year) regular_season.
# Playing each game and simming it draw from _rng in the SAME order, so a played season reproduces
# a simmed one exactly (advance_year stays the quick-sim escape used by the determinism tests).

## Lay out a fresh season and open the regular-season phase. Called by new_game, on load, and when
## the off-season closes. Sets the year's league cap and clears every team's record. No RNG.
func start_regular_season() -> void:
	if league == null:
		return
	league.league_cap = EconomyManager.league_cap_for_year(current_year)
	season_pdiff = SeasonManager.reset_standings(league)
	season_schedule = SeasonManager.build_schedule(league.teams)
	season_cursor = 0
	season_games = []
	_played_season = {}
	current_phase = "regular_season"
	EventBus.phase_changed.emit(current_phase)
	EventBus.world_changed.emit()

func season_complete() -> bool:
	return not season_schedule.is_empty() and season_cursor >= season_schedule.size()

## The player's progress through their own 35 games (the schedule holds all 140 league games).
func season_player_progress() -> Dictionary:
	var pid := league.player_team_id
	var played := 0
	var total := 0
	for i in season_schedule.size():
		var g: Dictionary = season_schedule[i]
		if int(g["home"]) == pid or int(g["away"]) == pid:
			total += 1
			if i < season_cursor:
				played += 1
	return {"played": played, "total": total}

## Index in the schedule of the player's next game, or -1 if they have none left.
func next_player_game_index() -> int:
	var pid := league.player_team_id
	for i in range(season_cursor, season_schedule.size()):
		var g: Dictionary = season_schedule[i]
		if int(g["home"]) == pid or int(g["away"]) == pid:
			return i
	return -1

func _play_game_at_cursor(opts: Dictionary = {}) -> GameResult:
	var r := SeasonManager.apply_game(league, season_schedule[season_cursor], season_pdiff, _rng, opts)
	season_games.append(r)
	season_cursor += 1
	return r

## Advance ONE matchday: the whole current round (n/2 games) is resolved, so every team plays exactly
## one more game and the standings stay level. The player's game in the round is played (watch=true
## logs the play-by-play for game_screen) and returned; the rest of the round is simmed the same day.
## Returns the player's GameResult (null if the season is already over). Enters the playoffs after the
## final round. The schedule is round-ordered (SeasonManager.build_schedule) and we only ever advance
## whole rounds, so season_cursor always sits on a round boundary.
func take_player_game(watch: bool) -> GameResult:
	if season_complete():
		return null
	@warning_ignore("integer_division")
	var rsize := league.teams.size() / 2
	var round_end := mini(season_cursor + rsize, season_schedule.size())
	var pid := league.player_team_id
	var player_result: GameResult = null
	while season_cursor < round_end:
		var g: Dictionary = season_schedule[season_cursor]
		var mine := int(g["home"]) == pid or int(g["away"]) == pid
		var r := _play_game_at_cursor({"log_events": true} if (mine and watch) else {})
		if mine:
			player_result = r
	_maybe_enter_playoffs()
	return player_result

## Sim one full matchday including the player's game (no watching).
func sim_next_game() -> void:
	take_player_game(false)

func sim_rest_of_season() -> void:
	while not season_complete():
		_play_game_at_cursor()
	_maybe_enter_playoffs()

func _maybe_enter_playoffs() -> void:
	if season_complete():
		enter_playoffs()

## Seed the top 4, simulate the bracket, and assemble the full-season dict the off-season feeds on.
## Snapshots the Season Center now (before development churns rosters). Moves to the playoffs phase;
## the player reviews the result, then enter_offseason_draft() runs the actual off-season.
func enter_playoffs() -> void:
	var table := SeasonManager.standings(league, season_pdiff)
	var po := SeasonManager.simulate_playoffs(table.slice(0, 4), _rng)
	_played_season = {
		"standings": table, "champion": po["champion"], "playoffs": po,
		"pdiff": season_pdiff, "games": season_games,
	}
	last_season = FranchiseManager.season_snapshot(_played_season, league, current_year)
	current_phase = "playoffs"
	EventBus.phase_changed.emit(current_phase)
	EventBus.world_changed.emit()

## Close the season just played: bank revenue, grow the city, develop everyone, set the draft order
## and rookie class, then open the draft on the clock — exactly the off-season begin_offseason runs,
## but fed by the season the player actually played.
func enter_offseason_draft() -> void:
	if _played_season.is_empty():
		return
	var ctx := FranchiseManager.setup_offseason(league, city, current_year, _rng, _played_season)
	draft_order = ctx["order"]
	draft_available = ctx["draft_class"].duplicate()
	draft_board = []
	draft_pick_index = 0
	draft_total = draft_order.size() * FranchiseManager.DRAFT_ROUNDS
	_offseason = {"carry": ctx["carry"], "season_view": ctx["season_view"], "summary": ctx["summary"]}
	last_season = ctx["season_view"]
	_played_season = {}
	draft_active = true
	current_phase = "draft"
	EventBus.phase_changed.emit(current_phase)
	EventBus.world_changed.emit()
	_draft_sim_to_player()

# --- interactive draft driver (M12) -----------------------------------------
# begin_offseason() plays the season and pauses on the clock at the draft; the player scouts and
# picks; finish_offseason() runs free agency and closes the year. Picking nothing / not scouting
# reproduces advance_year() exactly (the auto path).

func begin_offseason() -> Dictionary:
	var ctx := FranchiseManager.play_to_draft(league, city, current_year, _rng)
	draft_order = ctx["order"]
	draft_available = ctx["draft_class"].duplicate()
	draft_board = []
	draft_pick_index = 0
	draft_total = draft_order.size() * FranchiseManager.DRAFT_ROUNDS
	_offseason = {"carry": ctx["carry"], "season_view": ctx["season_view"], "summary": ctx["summary"]}
	last_season = ctx["season_view"]
	draft_active = true
	current_phase = "draft"
	EventBus.phase_changed.emit(current_phase)
	_draft_sim_to_player()
	return ctx

func draft_on_clock_team_id() -> int:
	if draft_pick_index >= draft_total or draft_order.is_empty():
		return -1
	return int(draft_order[draft_pick_index % draft_order.size()])

func draft_round() -> int:
	if draft_order.is_empty():
		return 1
	@warning_ignore("integer_division")
	var r := draft_pick_index / draft_order.size() + 1
	return r

func draft_is_player_turn() -> bool:
	return draft_active and draft_on_clock_team_id() == league.player_team_id

func draft_complete() -> bool:
	return draft_pick_index >= draft_total or draft_available.is_empty()

## Team ids of the player's upcoming pick slots (for the "you pick at #N" hint).
func draft_player_slots() -> Array:
	var slots := []
	for i in draft_total:
		if int(draft_order[i % draft_order.size()]) == league.player_team_id:
			slots.append(i + 1)
	return slots

func scout_prospect(pr: DraftProspect) -> bool:
	var cost := DraftManager.full_scout_cost(league.league_cap)
	var you := league.player_team()
	var spend := mini(cost, you.cash)
	if spend <= 0:
		return false
	you.cash -= spend
	DraftManager.scout(pr, float(spend), float(cost))
	return true

func draft_pick(pr: DraftProspect) -> bool:
	if not draft_is_player_turn() or not (pr in draft_available):
		return false
	_take(draft_on_clock_team_id(), pr)
	_draft_sim_to_player()
	return true

func draft_autopick() -> void:
	if draft_is_player_turn():
		_take(draft_on_clock_team_id(), DraftManager.ai_pick(draft_available))
		_draft_sim_to_player()

func draft_sim_rest() -> void:
	while not draft_complete():
		_take(draft_on_clock_team_id(), DraftManager.ai_pick(draft_available))

func finish_offseason() -> Dictionary:
	draft_sim_rest()
	var res := FranchiseManager.finish_after_draft(league, city, current_year, _rng, _offseason["carry"])
	var summary: Dictionary = (_offseason["summary"] as Dictionary).duplicate()
	summary.merge(res, true)
	summary["draft_board"] = draft_board
	summary["season"] = _offseason["season_view"]
	last_season = _offseason["season_view"]
	draft_active = false
	_offseason = {}
	draft_available = []
	current_year += 1
	start_regular_season()
	return summary

func _take(tid: int, pr: DraftProspect) -> void:
	draft_board.append(DraftManager.commit_pick(league, tid, pr, draft_available, draft_pick_index + 1))
	draft_pick_index += 1

func _draft_sim_to_player() -> void:
	while not draft_complete() and not draft_is_player_turn():
		_take(draft_on_clock_team_id(), DraftManager.ai_pick(draft_available))

# --- interactive free agency driver (M13) -----------------------------------
# After the draft, the player can play through free agency day by day. enter_free_agency() runs
# the deferred city investment then opens the market; fa_advance_day() steps it; finish_free_agency()
# trims rosters and closes the year. (Quick-simmers use finish_offseason() instead, which one-shots
# free agency the auto way.)

func enter_free_agency() -> void:
	draft_sim_rest()
	# Don't auto-spend the player's cash — the city is theirs to build (M14, City screen).
	FranchiseManager.post_draft_city(league, city, _rng, _offseason["carry"], false)
	fa_pool = FreeAgencyManager.generate_pool(_rng, current_year)
	fa_prefs = FreeAgencyManager.market_prefs(fa_pool, _rng)
	fa_offers = {}
	fa_signings = []
	fa_day = 1
	fa_active = true
	draft_active = false
	current_phase = "free_agency"
	EventBus.phase_changed.emit(current_phase)

func fa_cap_room() -> int:
	return FreeAgencyManager.cap_room(league.player_team(), league.league_cap)

func fa_place_offer(fa: PlayerData, salary: int, years: int) -> void:
	fa_offers[fa.id] = {"salary": maxi(0, salary), "years": clampi(years, 1, 4)}

func fa_cancel_offer(fa: PlayerData) -> void:
	fa_offers.erase(fa.id)

func fa_complete() -> bool:
	return fa_day > FreeAgencyManager.FA_DAYS or fa_pool.is_empty()

func fa_advance_day() -> Array:
	if fa_complete():
		return []
	var signed := FreeAgencyManager.resolve_day(league.teams, fa_pool, league.player_team(), league.league_cap, fa_offers, fa_prefs, _rng, fa_day, FreeAgencyManager.FA_DAYS, fa_signings)
	for fid in signed:
		fa_offers.erase(fid)
	fa_day += 1
	return signed

func fa_sim_rest() -> void:
	while not fa_complete():
		fa_advance_day()

func finish_free_agency() -> Dictionary:
	fa_sim_rest()
	FranchiseManager.finalize_offseason(league)
	var summary: Dictionary = (_offseason["summary"] as Dictionary).duplicate()
	summary.merge({
		"year": current_year, "your_ovr": league.player_team().team_ovr(),
		"population": city.population, "cash": league.player_team().cash,
		"draft_board": draft_board, "fa_signings": fa_signings, "season": _offseason["season_view"],
	}, true)
	last_season = _offseason["season_view"]
	_offseason = {}
	fa_active = false
	draft_active = false
	current_year += 1
	start_regular_season()
	return summary

# --- city building (M14): spend cash to grow the city, year-round --------------------------

func city_build(type: String) -> bool:
	if not CityManager.CATALOG.has(type):
		return false
	var cost := CityManager.build_cost(city, type)
	var you := league.player_team()
	if you.cash < cost:
		return false
	you.cash -= cost
	CityManager.build(city, type)
	return true

func city_upgrade(b: BuildingData) -> bool:
	var cost := CityManager.upgrade_cost(b)
	var you := league.player_team()
	if you.cash < cost:
		return false
	you.cash -= cost
	CityManager.upgrade(b)
	return true

func save_world(path: String = WORLD_PATH) -> bool:
	if league == null or city == null:
		return false
	var bundle := WorldSave.new()
	bundle.version = SAVE_VERSION
	bundle.year = current_year
	bundle.league = league
	bundle.city = city
	return ResourceSaver.save(bundle, path) == OK

func load_world(path: String = WORLD_PATH) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var bundle = ResourceLoader.load(path)
	if bundle == null:
		return false
	current_year = int(bundle.year)
	league = bundle.league
	city = bundle.city
	# Mid-season play state isn't serialized yet (v1) — a loaded world opens a fresh season.
	start_regular_season()
	return true

func reset() -> void:
	current_year = DEFAULT_YEAR
	current_phase = "preseason"
	current_day = 0
	data = {}

func to_save_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"current_year": current_year,
		"current_phase": current_phase,
		"current_day": current_day,
		"data": data,
	}

func from_save_dict(d: Dictionary) -> void:
	var v := int(d.get("version", 0))
	if v != SAVE_VERSION:
		# Migration hook: when SAVE_VERSION bumps, translate older shapes here.
		push_warning("Save version %d != current %d; loaded as-is (no migration yet)." % [v, SAVE_VERSION])
	current_year = int(d.get("current_year", DEFAULT_YEAR))
	current_phase = String(d.get("current_phase", "preseason"))
	current_day = int(d.get("current_day", 0))
	data = d.get("data", {})

func save_game(path: String = SAVE_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("save_game: cannot open %s (err %d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(to_save_dict(), "\t"))
	f.close()
	return true

func load_game(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("load_game: cannot open %s (err %d)" % [path, FileAccess.get_open_error()])
		return false
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("load_game: %s is not a JSON object" % path)
		return false
	from_save_dict(parsed)
	return true
