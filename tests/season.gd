extends "res://tests/TestRunner.gd"
## M4 gate: a correct 35-game schedule, sane standings, a resolving playoff bracket, and
## — across many seasons — the dynasty wins titles far above chance while you rarely break
## through yet (but it's never impossible).

func _league(seed_val: int) -> LeagueData:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return LeagueGenerator.generate_league(rng, {"year": 2026})

func run_tests() -> void:
	var lg := _league(2026)

	# --- schedule structure ---
	var sched := SeasonManager.build_schedule(lg.teams)
	check(sched.size() == 140, "season has 140 games (got %d)" % sched.size())

	var per_team := {}
	var home_count := {}
	var pair_count := {}
	for t in lg.teams:
		per_team[t.id] = 0
		home_count[t.id] = 0
	for g in sched:
		per_team[g["home"]] += 1
		per_team[g["away"]] += 1
		home_count[g["home"]] += 1
		var key := "%d-%d" % [mini(int(g["home"]), int(g["away"])), maxi(int(g["home"]), int(g["away"]))]
		pair_count[key] = int(pair_count.get(key, 0)) + 1

	var all35 := true
	for tid in per_team:
		if per_team[tid] != 35:
			all35 = false
	check(all35, "every team plays exactly 35 games")

	var all5 := true
	for k in pair_count:
		if pair_count[k] != 5:
			all5 = false
	check(all5 and pair_count.size() == 28, "every pair meets exactly 5 times")

	var hmin := 99
	var hmax := 0
	for tid in home_count:
		hmin = mini(hmin, int(home_count[tid]))
		hmax = maxi(hmax, int(home_count[tid]))
	check(hmax - hmin <= 2, "home games balanced (%d..%d)" % [hmin, hmax])

	# --- one full season ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 50
	var res := SeasonManager.simulate_full_season(lg, rng)

	var total_w := 0
	var total_l := 0
	var rec_ok := true
	for t in lg.teams:
		total_w += t.wins
		total_l += t.losses
		if t.wins + t.losses != 35:
			rec_ok = false
	check(rec_ok, "every team's record sums to 35")
	check(total_w == 140 and total_l == 140, "wins and losses each total 140 (%d/%d)" % [total_w, total_l])

	var table: Array = res["standings"]
	var sorted_ok := true
	for i in range(table.size() - 1):
		if table[i].wins < table[i + 1].wins:
			sorted_ok = false
	check(sorted_ok, "standings sorted by wins")

	var champ = res["champion"]
	var top4 := []
	for i in 4:
		top4.append(table[i].id)
	check(champ.id in top4, "champion came from the top-4 seeds")

	# Determinism.
	var lg2 := _league(2026)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 50
	var res2 := SeasonManager.simulate_full_season(lg2, rng2)
	check(res2["champion"].id == champ.id, "same seed reproduces the champion")

	# --- many seasons: dynasty dominates, you rarely break through (but it's not impossible) ---
	var seasons := 150
	var dyn_titles := 0
	var you_titles := 0
	var dyn_po := 0
	var you_po := 0
	for s in seasons:
		var league := _league(2026)
		var r := RandomNumberGenerator.new()
		r.seed = 1000 + s
		var rr := SeasonManager.simulate_full_season(league, r)
		var st: Array = rr["standings"]
		var seeds := []
		for i in 4:
			seeds.append(st[i].id)
		if rr["champion"].id == league.dynasty_team_id:
			dyn_titles += 1
		if rr["champion"].id == league.player_team_id:
			you_titles += 1
		if league.dynasty_team_id in seeds:
			dyn_po += 1
		if league.player_team_id in seeds:
			you_po += 1

	var dr := float(dyn_titles) / float(seasons)
	var yr := float(you_titles) / float(seasons)
	check(dr > 0.35, "dynasty wins titles far above 1/8 chance (%.2f)" % dr)
	check(yr < 0.06, "you almost never win it all yet (%.2f)" % yr)
	check(float(dyn_po) / float(seasons) > 0.85, "dynasty almost always makes the playoffs (%.2f)" % (float(dyn_po) / float(seasons)))
	check(float(you_po) / float(seasons) < 0.35, "you rarely reach the playoffs yet (%.2f)" % (float(you_po) / float(seasons)))

	# --- print one season's table ---
	print("\n--- final standings (seed 50) ---")
	var place := 1
	for t in table:
		var tag := ""
		if t.id == lg.dynasty_team_id:
			tag = "   [dynasty]"
		elif t.is_player_team:
			tag = "   [you]"
		print("  %d. %-22s %2d-%2d   pd %+5d%s" % [place, t.name, t.wins, t.losses, int(res["pdiff"].get(t.id, 0)), tag])
		place += 1
	print("  CHAMPION: %s" % champ.name)
