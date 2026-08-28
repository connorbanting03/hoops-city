extends "res://tests/TestRunner.gd"
## M15 gate: the play-by-play feed. The event log now covers every outcome, and the feed's running
## score must reconcile exactly to the final box score. Critically, logging adds NO RNG draws, so a
## logged game and an unlogged game from the same seed are identical — the season sim is untouched.

func _league(seed_val: int) -> LeagueData:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return LeagueGenerator.generate_league(rng, {"year": 2026})

func run_tests() -> void:
	var lg := _league(7)
	var home: TeamData = lg.teams[0]
	var away: TeamData = lg.teams[7]

	# --- logging does not perturb the simulation ----------------------------
	var r1 := RandomNumberGenerator.new(); r1.seed = 99
	var logged := GameSimulator.simulate_game(home, away, r1, {"log_events": true})
	var r2 := RandomNumberGenerator.new(); r2.seed = 99
	var plain := GameSimulator.simulate_game(home, away, r2)
	check(logged.home_score == plain.home_score and logged.away_score == plain.away_score, "logged & unlogged games match (%d-%d)" % [logged.home_score, logged.away_score])
	check(logged.winner_id == plain.winner_id, "the winner is unchanged by logging")

	# --- the event log is populated -----------------------------------------
	check(logged.events.size() > 50, "a full game logs plenty of plays (%d)" % logged.events.size())
	var types := {}
	for e in logged.events:
		types[e["type"]] = true
	check(types.has("fg2") and types.has("fg3"), "the feed logs two- and three-pointers")
	check(types.has("tov"), "the feed logs turnovers")
	check(types.size() >= 4, "the feed covers a variety of play types (%d)" % types.size())

	# --- the feed reconciles to the final score -----------------------------
	var feed := PlayByPlay.feed(logged)
	check(feed.size() == logged.events.size(), "every event becomes a feed line")
	var last: Dictionary = feed[feed.size() - 1]
	check(int(last["home"]) == logged.home_score and int(last["away"]) == logged.away_score, "the running score reconciles to the final (%d-%d)" % [logged.home_score, logged.away_score])
	# Running score never exceeds the final and is monot_increasing.
	var mono := true
	var prev_h := 0
	var prev_a := 0
	for line in feed:
		if int(line["home"]) < prev_h or int(line["away"]) < prev_a:
			mono = false
		prev_h = int(line["home"])
		prev_a = int(line["away"])
	check(mono, "the running score only ever goes up")
	var scored := 0
	for line in feed:
		if line["scored"]:
			scored += 1
	check(scored > 0, "the feed flags scoring plays (%d)" % scored)
	check(not String(feed[0]["text"]).is_empty(), "feed lines have readable text")

	# --- shell can host the Game Day screen ---------------------------------
	GameState.new_game(2026)
	var app := preload("res://scenes/app_root.tscn").instantiate()
	add_child(app)
	app.boot()
	app.show_screen("game")
	check(app.current_screen() == "game", "the shell opens the Game Day screen")
	app.queue_free()
