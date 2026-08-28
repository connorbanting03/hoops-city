extends "res://tests/TestRunner.gd"
## M12 sim/driver gate: the interactive off-season. The atomic advance_year() is untouched; this
## verifies the parallel begin/finish flow. The keystone check: auto-picking every slot with no
## scouting must reproduce advance_year() EXACTLY (same seed -> identical roster/cash/city), proving
## the refactor didn't disturb the simulation. Then we verify scouting, picking, and integrity.

func _autoplay_offseason() -> Dictionary:
	GameState.begin_offseason()
	while GameState.draft_is_player_turn():
		GameState.draft_autopick()
	return GameState.finish_offseason()

func run_tests() -> void:
	# --- keystone: auto offseason == advance_year (same seed) ----------------
	GameState.new_game(2026)
	var a := GameState.advance_year()
	var a_ovr: float = GameState.league.player_team().team_ovr()
	var a_cash: int = GameState.league.player_team().cash
	var a_pop: float = GameState.city.population

	GameState.new_game(2026)
	var b := _autoplay_offseason()
	check(absf(GameState.league.player_team().team_ovr() - a_ovr) < 0.001, "auto-draft reproduces advance_year OVR (%.2f)" % a_ovr)
	check(GameState.league.player_team().cash == a_cash, "...and the exact cash ($%d)" % a_cash)
	check(absf(GameState.city.population - a_pop) < 0.01, "...and the exact city population")
	check(int(b["year"]) == int(a["year"]) and GameState.current_year == 2027, "the year advanced once, like advance_year")
	check(not GameState.draft_active, "the off-season closed out")

	# --- pause point + pick order -------------------------------------------
	GameState.new_game(2026)
	var ctx := GameState.begin_offseason()
	check(GameState.draft_active and GameState.current_phase == "draft", "begin_offseason pauses on the clock at the draft")
	check(ctx["draft_class"].size() == DraftManager.CLASS_SIZE, "a rookie class was generated (%d)" % ctx["draft_class"].size())
	check(GameState.draft_total == 16, "the draft is 2 rounds x 8 teams (%d picks)" % GameState.draft_total)
	check(GameState.draft_is_player_turn(), "it stops at YOUR pick (you're a lottery team)")
	var slots := GameState.draft_player_slots()
	check(slots.size() == 2, "you have a pick in each round (%s)" % str(slots))
	# every AI pick before your slot took the best stock still on the board
	var board_ok := true
	for entry in GameState.draft_board:
		if int(entry["team_id"]) != int(GameState.draft_order[(int(entry["pick"]) - 1) % 8]):
			board_ok = false
	check(board_ok, "picks follow the lottery order")

	# --- scouting spends cash + narrows uncertainty -------------------------
	var you := GameState.league.player_team()
	var pr: DraftProspect = GameState.draft_available[0]
	var u0: float = pr.uncertainty
	var cash0: int = you.cash
	var cost := DraftManager.full_scout_cost(GameState.league.league_cap)
	check(cost == 2_000_000, "a full scout costs ~$2M at the starting cap (got $%d)" % cost)
	check(DraftManager.full_scout_cost(240_000_000) > cost, "scout cost scales up as the league cap inflates")
	var spend: int = mini(cost, cash0)
	var ok := GameState.scout_prospect(pr)
	check(ok == (spend > 0), "scouting succeeds when you can afford it")
	check(you.cash == cash0 - spend, "scouting spent the budget ($%d)" % spend)
	check(pr.uncertainty < u0 + 0.0001 and absf(pr.uncertainty - (1.0 - float(spend) / float(cost))) < 0.001, "uncertainty fell toward the truth (%.2f -> %.2f)" % [u0, pr.uncertainty])

	# --- the player's pick lands a rookie on the roster ---------------------
	var size_before: int = you.roster.size()
	var my_guy: DraftProspect = GameState.draft_available[0]
	var picked := GameState.draft_pick(my_guy)
	check(picked, "you drafted a prospect")
	check(you.roster.size() == size_before + 1, "your rookie joined the roster")
	check(my_guy.player in you.roster, "...and it's the player you selected")
	check(not (my_guy in GameState.draft_available), "the prospect left the board")

	# --- finishing closes the year ------------------------------------------
	var summary := GameState.finish_offseason()
	check(not GameState.draft_active and GameState.current_phase == "regular_season", "free agency ran and the off-season ended")
	check(summary.has("draft_board") and summary["draft_board"].size() == 16, "the summary carries the full draft board")
	check(not GameState.last_season.is_empty(), "the Season Center has the season you just played")
	check(GameState.league.player_team().roster.size() >= 8, "you still field a viable roster")

	# --- shell can host the draft screen mid-offseason ----------------------
	GameState.new_game(2026)
	GameState.begin_offseason()
	var app := preload("res://scenes/app_root.tscn").instantiate()
	add_child(app)
	app.boot()
	app.show_screen("draft")
	check(app.current_screen() == "draft", "the shell opens the Draft screen while a draft is live")
	app.queue_free()
