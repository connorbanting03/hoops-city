extends "res://tests/TestRunner.gd"
## M13 sim/driver gate: the interactive, day-based free-agency market. The one-shot resolve() and
## the auto advance_year() are untouched; this verifies the parallel day-market and the off-season
## driver that now runs draft -> free agency -> finalize. Keystone re-checked: auto-completing the
## off-season (finish_offseason) still reproduces advance_year exactly after the phase split.

func _autopick_draft() -> void:
	GameState.begin_offseason()
	while GameState.draft_is_player_turn():
		GameState.draft_autopick()

func run_tests() -> void:
	# --- keystone survives the FranchiseManager phase split ------------------
	GameState.new_game(2026)
	GameState.advance_year()
	var a_ovr: float = GameState.league.player_team().team_ovr()
	var a_cash: int = GameState.league.player_team().cash
	var a_pop: float = GameState.city.population

	GameState.new_game(2026)
	_autopick_draft()
	GameState.finish_offseason()
	check(absf(GameState.league.player_team().team_ovr() - a_ovr) < 0.001, "auto-finish still reproduces advance_year OVR")
	check(GameState.league.player_team().cash == a_cash, "...and the exact cash")
	check(absf(GameState.city.population - a_pop) < 0.01, "...and the exact city population")

	# --- entering free agency opens the market ------------------------------
	GameState.new_game(2026)
	_autopick_draft()
	GameState.enter_free_agency()
	check(GameState.fa_active and GameState.current_phase == "free_agency", "after the draft you enter free agency")
	check(GameState.fa_pool.size() == FreeAgencyManager.POOL_SIZE, "a free-agent pool is generated (%d)" % GameState.fa_pool.size())
	check(GameState.fa_day == 1, "the window opens on day 1")
	check(GameState.fa_cap_room() > 0, "you have cap room to spend (%s)" % UITheme.moneyf(GameState.fa_cap_room()))

	# --- a day signs free agents; the window closes -------------------------
	var before: int = GameState.fa_pool.size()
	GameState.fa_advance_day()
	check(GameState.fa_day == 2, "advancing a day moves the clock")
	check(GameState.fa_pool.size() <= before, "free agents come off the board as they sign")
	GameState.fa_sim_rest()
	check(GameState.fa_complete(), "the market closes after the window")
	check(GameState.fa_signings.size() > 0, "free agents signed across the window (%d)" % GameState.fa_signings.size())

	# --- a strong offer lets YOU win a free agent ---------------------------
	GameState.new_game(2026)
	_autopick_draft()
	GameState.enter_free_agency()
	var you := GameState.league.player_team()
	var cr: int = GameState.fa_cap_room()
	# Overpay several role players you can use (positions you're not already deep at).
	var elig := []
	for fa in GameState.fa_pool:
		if FreeAgencyManager.team_pos_strength(you, fa.primary_pos) <= fa.overall() + 4:
			elig.append(fa)
	elig.sort_custom(func(x, y): return x.overall() < y.overall())   # cheapest, most money-driven first
	var offered_ids := {}
	for fa in elig:
		if offered_ids.size() >= 6:
			break
		var ask := EconomyManager.fair_salary(fa.overall(), GameState.league.league_cap)
		GameState.fa_place_offer(fa, mini(cr, ask * 2), 3)
		offered_ids[fa.id] = true
	check(offered_ids.size() > 0, "there are free agents you're eligible to chase (%d)" % offered_ids.size())
	GameState.fa_sim_rest()
	var you_signed := 0
	for s in GameState.fa_signings:
		if s.get("you", false):
			you_signed += 1
	check(you_signed >= 1, "your offers landed at least one free agent (%d)" % you_signed)
	# Churn means a signing replaces your worst player rather than growing the roster, so check by id.
	var on_roster := false
	for p in GameState.league.player_team().roster:
		if offered_ids.has(p.id):
			on_roster = true
	check(on_roster, "a free agent you signed is on your roster")
	check(you_signed < GameState.fa_signings.size(), "the AI signed free agents too — it's a real market")

	# --- finishing closes the year ------------------------------------------
	var summary := GameState.finish_free_agency()
	check(GameState.current_phase == "regular_season" and not GameState.fa_active, "free agency ended and the year advanced")
	check(GameState.current_year == 2027, "the clock moved to the next season")
	check(summary.has("fa_signings") and summary.has("draft_board"), "the summary carries the draft + free-agency results")
	check(not GameState.last_season.is_empty(), "the Season Center still has the season you played")
	var viable := true
	for t in GameState.league.teams:
		if t.roster.size() < 8 or t.roster.size() > FranchiseManager.MAX_ROSTER:
			viable = false
	check(viable, "every team is left with a legal roster (8..%d)" % FranchiseManager.MAX_ROSTER)

	# --- shell can host the FA screen mid-window ----------------------------
	GameState.new_game(2026)
	_autopick_draft()
	GameState.enter_free_agency()
	var app := preload("res://scenes/app_root.tscn").instantiate()
	add_child(app)
	app.boot()
	app.show_screen("fa")
	check(app.current_screen() == "fa", "the shell opens the Free Agency screen while the window is open")
	app.queue_free()
