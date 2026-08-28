extends "res://tests/TestRunner.gd"
## M9 gate: the whole game as one continuous franchise. Integrity over many years, full-world
## save/load, determinism, and the verdict that decides whether the vertical slice is fun —
## starting 5-30, can you draft + develop + grow the city and actually climb?

func _max_ovr(league) -> float:
	var m := 0.0
	for t in league.teams:
		m = maxf(m, t.team_ovr())
	return m

func _popf(n) -> String:
	var p := float(n)
	if p >= 1_000_000.0:
		return "%.2fM" % (p / 1e6)
	if p >= 1_000.0:
		return "%.1fK" % (p / 1e3)
	return "%d" % int(p)

func run_tests() -> void:
	GameState.new_game(2026)
	check(GameState.league.player_team().cash > 0, "you start with a cash reserve ($%.0fM)" % (float(GameState.league.player_team().cash) / 1_000_000.0))
	var start_ovr := GameState.league.player_team().team_ovr()
	var start_pop := GameState.city.population
	var start_max := _max_ovr(GameState.league)
	var start_hist := GameState.league.history.size()
	var start_cap := GameState.league.league_cap

	var traj := []
	var ever_po := false
	var min_cash := 1 << 62
	for y in 15:
		var r := GameState.advance_year()
		traj.append(r)
		if r["made_playoffs"]:
			ever_po = true
		min_cash = mini(min_cash, int(r["cash"]))

	var end_ovr := GameState.league.player_team().team_ovr()
	var end_max := _max_ovr(GameState.league)
	var end_pop := GameState.city.population

	# --- integrity: the loop runs for years without breaking ---
	check(GameState.league.teams.size() == 8, "league still has 8 teams after 15 years")
	var rosters_ok := true
	for t in GameState.league.teams:
		if t.roster.size() < 8:
			rosters_ok = false
	check(rosters_ok, "every team keeps a viable roster")
	check(GameState.league.history.size() == start_hist + 15, "a champion is crowned every year")
	check(GameState.league.league_cap > start_cap, "league cap rose over the run")

	# --- the verdict: you can climb ---
	check(end_ovr > start_ovr + 3.0, "you climbed: team OVR %.1f -> %.1f" % [start_ovr, end_ovr])
	check(ever_po, "you reached the playoffs at least once")
	check((start_max - start_ovr) > (end_max - end_ovr), "gap to the best team narrowed (%.1f -> %.1f)" % [start_max - start_ovr, end_max - end_ovr])
	var first5 := 0.0
	var last5 := 0.0
	for i in 5:
		first5 += float(traj[i]["your_rank"])
	for i in range(10, 15):
		last5 += float(traj[i]["your_rank"])
	check(last5 / 5.0 < first5 / 5.0, "your average standing improved (#%.1f -> #%.1f)" % [first5 / 5.0, last5 / 5.0])
	check(end_pop > start_pop * 1.5, "your city grew (%s -> %s)" % [_popf(start_pop), _popf(end_pop)])
	check(min_cash >= 0, "you never fall into debt (lowest cash $%.1fM)" % (float(min_cash) / 1_000_000.0))

	# --- full-world save / load ---
	check(GameState.save_world(), "world saves to disk")
	var saved_year := GameState.current_year
	var saved_ovr := GameState.league.player_team().team_ovr()
	GameState.advance_year()
	check(GameState.load_world(), "world loads from disk")
	check(GameState.current_year == saved_year, "loaded year matches saved (%d)" % saved_year)
	check(absf(GameState.league.player_team().team_ovr() - saved_ovr) < 0.01, "loaded roster matches the saved snapshot")

	# --- determinism ---
	GameState.new_game(2026)
	for y in 15:
		GameState.advance_year()
	check(absf(GameState.league.player_team().team_ovr() - end_ovr) < 0.01, "same seed reproduces the 15-year arc")

	# --- trajectory ---
	print("\n--- your 15-year climb (Granite City Quarry) ---")
	print("  yr  record   rank  teamOVR   cash       city pop   champion")
	for i in traj.size():
		var r = traj[i]
		print("  %2d  %-7s  #%d    %5.1f    $%5.0fM    %-8s  %s" % [i + 1, r["your_record"], r["your_rank"], r["your_ovr"], float(r["cash"]) / 1_000_000.0, _popf(r["population"]), r["champion"]])
