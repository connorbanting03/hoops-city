class_name FranchiseManager
extends RefCounted
## Ties all eight systems into one continuous year (GDD §4.3 off-season flow): regular season
## + playoffs -> awards -> economy/city growth -> player development & aging -> draft -> free
## agency. This is the loop that lets a 5-30 team climb: high draft picks + development grow a
## young core while the dynasty's vets age out, and a growing city raises the budget to keep up.

const MAX_ROSTER := 14
const ROOKIE_AGE_MAX := 22
const DRAFT_ROUNDS := 2

static func new_game(rng: RandomNumberGenerator) -> Dictionary:
	var league := LeagueGenerator.generate_league(rng, {"year": 2026})
	league.league_cap = EconomyManager.league_cap_for_year(2026)
	EconomyManager.assign_initial_salaries(league)
	var city := CityManager.generate_starter_city()
	league.player_team().market_size = CityManager.market_size(city)
	return {"league": league, "city": city, "year": 2026}

## Advance one full year. Mutates league + city. Returns a summary of what happened.
static func advance_year(league: LeagueData, city: CityData, year: int, rng: RandomNumberGenerator) -> Dictionary:
	league.league_cap = EconomyManager.league_cap_for_year(year)
	var pteam := league.player_team()

	# 1. Regular season + playoffs.
	var season := SeasonManager.simulate_full_season(league, rng)
	var standings: Array = season["standings"]
	var champ: TeamData = season["champion"]
	var results := EconomyManager.derive_results(league, season)
	champ.championships += 1
	champ.last_title_year = year
	league.history.append({"year": year, "champion_id": champ.id, "champion_name": champ.name})
	var mvp := _league_mvp(league)
	var your_rank := _rank_of(standings, pteam.id)
	var your_record := "%d-%d" % [pteam.wins, pteam.losses]
	var made_playoffs: bool = results[pteam.id]["made_playoffs"]
	# Snapshot the season for the Season Center BEFORE development/draft/FA mutate the rosters.
	var season_view := _season_snapshot(season, league, year, mvp)

	# 2. Economy: your market comes from the city; everyone banks revenue minus payroll.
	pteam.market_size = CityManager.market_size(city)
	var your_success: float = results[pteam.id]["win_pct"]
	var your_div := CityManager.dividends(city, your_success)
	for t in league.teams:
		var d := your_div if t.id == pteam.id else 0.0
		var rev := EconomyManager.season_revenue(t, results[t.id], league, d)
		t.cash = maxi(0, t.cash + int(round(rev["total"] - float(EconomyManager.payroll(t)))))

	# 3. City grows with team success, then you reinvest cash into it.
	CityManager.advance_population(city, your_success, 1)
	_invest_city(city, pteam, rng)
	CityManager.advance_population(city, your_success, 1)
	pteam.market_size = CityManager.market_size(city)

	# 4. Development, aging, retirements.
	for t in league.teams:
		_develop_and_age(t, rng)

	# 5. Draft (lottery order) — fills rosters with youth.
	var order := DraftManager.run_lottery(standings, rng)
	var draft_class := DraftManager.generate_class(rng, year)
	DraftManager.run_draft(league, order, draft_class, rng, 2)

	# 6. Free agency.
	var pool := FreeAgencyManager.generate_pool(rng, year)
	FreeAgencyManager.resolve(league.teams, pool, league.league_cap, rng, true)

	# 7. Trim to roster cap (protecting promising youth), then price unsigned rookies.
	for t in league.teams:
		_trim_roster(t)
		for p in t.roster:
			if p.salary <= 0:
				p.salary = EconomyManager.fair_salary(p.overall(), league.league_cap)

	return {
		"year": year, "champion": champ.name, "mvp": mvp,
		"your_record": your_record, "your_rank": your_rank, "made_playoffs": made_playoffs,
		"your_ovr": pteam.team_ovr(), "population": city.population, "cash": pteam.cash,
		"season": season_view,
	}

## Compact, self-contained view of the season just played (standings rows + every GameResult +
## the playoff series), for the Season Center. Snapshots W-L now so it survives roster churn.
static func _season_snapshot(season: Dictionary, league: LeagueData, year: int, mvp: String) -> Dictionary:
	var standings: Array = season["standings"]
	var rows := []
	for i in standings.size():
		var t: TeamData = standings[i]
		rows.append({
			"team_id": t.id, "name": t.name, "abbrev": t.abbrev,
			"wins": t.wins, "losses": t.losses,
			"pdiff": int(season["pdiff"].get(t.id, 0)),
			"made_playoffs": i < 4,
			"is_player": t.is_player_team,
			"is_dynasty": t.id == league.dynasty_team_id,
		})
	var champ: TeamData = season["champion"]
	return {
		"year": year, "mvp": mvp,
		"champion": champ.name, "champion_id": champ.id,
		"standings": rows,
		"games": season["games"],            # Array[GameResult], regular season, schedule order
		"series": season["playoffs"]["series"],
	}

# --- interactive offseason (M12) --------------------------------------------
# The same year, split so the player can play through the DRAFT. Phase order differs from the
# atomic advance_year ONLY in that city investment is deferred until AFTER the draft, so the
# player's cash is available as a real scouting budget (GDD §4.5's three-way pull). The RNG draw
# order (season -> development -> lottery -> class -> FA) is identical, so an auto-picked,
# un-scouted offseason reproduces advance_year exactly.

## Phases 1-5a: play the season, bank revenue, grow the city once, develop everyone, and set up
## the draft (lottery order + rookie class). Returns everything the driver needs to pause here.
static func play_to_draft(league: LeagueData, city: CityData, year: int, rng: RandomNumberGenerator) -> Dictionary:
	league.league_cap = EconomyManager.league_cap_for_year(year)
	var season := SeasonManager.simulate_full_season(league, rng)
	return setup_offseason(league, city, year, rng, season)

## Phases 2-5a over an ALREADY-PLAYED season: bank revenue, grow the city once, develop everyone,
## crown the champion, and set up the draft (lottery order + rookie class). Split out of
## play_to_draft so the game-by-game played season (GameState) and the one-shot sim feed the exact
## same offseason. Takes a SeasonManager full-season dict ({standings, champion, playoffs, pdiff,
## games}); the league_cap must already be set for `year` (start_regular_season does this). The RNG
## is only touched here for development -> lottery -> class, in that order, exactly as before.
static func setup_offseason(league: LeagueData, city: CityData, year: int, rng: RandomNumberGenerator, season: Dictionary) -> Dictionary:
	var pteam := league.player_team()
	var standings: Array = season["standings"]
	var champ: TeamData = season["champion"]
	var results := EconomyManager.derive_results(league, season)
	champ.championships += 1
	champ.last_title_year = year
	league.history.append({"year": year, "champion_id": champ.id, "champion_name": champ.name})
	var mvp := _league_mvp(league)
	var season_view := _season_snapshot(season, league, year, mvp)

	pteam.market_size = CityManager.market_size(city)
	var your_success: float = results[pteam.id]["win_pct"]
	var your_div := CityManager.dividends(city, your_success)
	for t in league.teams:
		var d := your_div if t.id == pteam.id else 0.0
		var rev := EconomyManager.season_revenue(t, results[t.id], league, d)
		t.cash = maxi(0, t.cash + int(round(rev["total"] - float(EconomyManager.payroll(t)))))

	CityManager.advance_population(city, your_success, 1)
	for t in league.teams:
		_develop_and_age(t, rng)

	var order := DraftManager.run_lottery(standings, rng)
	var draft_class := DraftManager.generate_class(rng, year)
	return {
		"order": order, "draft_class": draft_class, "season_view": season_view,
		"summary": {
			"year": year, "champion": champ.name, "mvp": mvp,
			"your_record": "%d-%d" % [pteam.wins, pteam.losses],
			"your_rank": _rank_of(standings, pteam.id),
			"made_playoffs": bool(results[pteam.id]["made_playoffs"]),
		},
		"carry": {"your_success": your_success},
	}

## A Season Center snapshot taken the moment the playoffs end — before development/draft churn the
## rosters. Lets the played path show the season recap during the "playoffs" phase, mirroring the
## season_view setup_offseason records. (mvp is RNG-free, so calling this then setup_offseason is
## deterministic.)
static func season_snapshot(season: Dictionary, league: LeagueData, year: int) -> Dictionary:
	return _season_snapshot(season, league, year, _league_mvp(league))

## Phase 5b: (optionally auto-invest leftover cash in the city, for the quick-sim path) then grow
## the city and refresh the market. When the player is building the city by hand (M14), the auto
## investment is skipped so their cash is theirs to allocate.
static func post_draft_city(league: LeagueData, city: CityData, rng: RandomNumberGenerator, carry: Dictionary, auto_invest: bool = true) -> void:
	var pteam := league.player_team()
	var your_success: float = carry["your_success"]
	if auto_invest:
		_invest_city(city, pteam, rng)
	CityManager.advance_population(city, your_success, 1)
	pteam.market_size = CityManager.market_size(city)

## Phase 7: trim to the roster cap (protecting youth) and price any unsigned rookies.
static func finalize_offseason(league: LeagueData) -> void:
	for t in league.teams:
		_trim_roster(t)
		for p in t.roster:
			if p.salary <= 0:
				p.salary = EconomyManager.fair_salary(p.overall(), league.league_cap)

## Phases 5b-7 in one shot (the quick path): city, then a one-shot free-agency auction, then
## finalize. Identical to the relevant tail of advance_year, so an auto-completed interactive
## off-season reproduces a quick-simmed one exactly.
static func finish_after_draft(league: LeagueData, city: CityData, year: int, rng: RandomNumberGenerator, carry: Dictionary) -> Dictionary:
	post_draft_city(league, city, rng, carry)
	var pool := FreeAgencyManager.generate_pool(rng, year)
	FreeAgencyManager.resolve(league.teams, pool, league.league_cap, rng, true)
	finalize_offseason(league)
	var pteam := league.player_team()
	return {"year": year, "your_ovr": pteam.team_ovr(), "population": city.population, "cash": pteam.cash}

# --- development -------------------------------------------------------------

static func _develop_and_age(team: TeamData, rng: RandomNumberGenerator) -> void:
	var keep: Array[PlayerData] = []
	for p in team.roster:
		p.age += 1
		var ovr := p.overall()
		if p.age <= 26:
			var gap := p.potential - ovr
			if gap > 0:
				_bump(p, clampi(int(round(float(gap) * 0.22 + rng.randf_range(0.0, 1.5))), 0, gap))
		elif p.age >= 31:
			_bump(p, -int(round(float(p.age - 30) * 0.5 + rng.randf_range(0.0, 1.0))))
		if p.age >= 39 or (p.age >= 35 and p.overall() < 48):
			continue   # retires
		keep.append(p)
	team.roster = keep

static func _bump(p: PlayerData, delta: int) -> void:
	if delta == 0:
		return
	for k in PlayerData.ATTRS:
		p.attributes[k] = clampi(p.get_attr(k) + delta, 1, 99)

static func _keep_score(p: PlayerData) -> float:
	var youth := clampf((25.0 - float(p.age)) / 7.0, 0.0, 1.0)
	return float(p.overall()) + float(p.potential - p.overall()) * youth * 0.6

static func _trim_roster(team: TeamData) -> void:
	if team.roster.size() <= MAX_ROSTER:
		return
	var scored := team.roster.duplicate()
	scored.sort_custom(func(a, b): return _keep_score(a) > _keep_score(b))
	var keep: Array[PlayerData] = []
	for i in mini(MAX_ROSTER, scored.size()):
		keep.append(scored[i])
	team.roster = keep

# --- city investment ---------------------------------------------------------

static func _invest_city(city: CityData, pteam: TeamData, _rng: RandomNumberGenerator) -> void:
	var budget := pteam.cash
	var plan := ["condo_tower", "office", "theater", "apartments", "park", "shops", "hotel"]
	var safety := 0
	while safety < 300:
		safety += 1
		var built := false
		for type in plan:
			var cost := CityManager.build_cost(city, type)
			if cost <= budget:
				CityManager.build(city, type)
				budget -= cost
				built = true
				break
		if not built:
			break
	pteam.cash = budget

# --- helpers -----------------------------------------------------------------

static func _league_mvp(league: LeagueData) -> String:
	var best: PlayerData = null
	var best_score := -1.0
	for t in league.teams:
		var app := clampf(float(t.wins) / 35.0, 0.0, 1.0)
		for p in t.roster:
			var sc := float(p.overall()) + app * 12.0
			if sc > best_score:
				best_score = sc
				best = p
	return best.full_name() if best != null else "-"

static func _rank_of(standings: Array, team_id: int) -> int:
	for i in standings.size():
		if standings[i].id == team_id:
			return i + 1
	return -1
