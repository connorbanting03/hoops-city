extends "res://tests/TestRunner.gd"
## M2 gate: an 8-team league with full rosters — you start as the unique worst, one
## dynasty owns the most banners, the seeded past is internally consistent, and every
## team is positionally sane.

func _league(seed_val: int) -> LeagueData:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return LeagueGenerator.generate_league(rng, {"year": 2026})

func run_tests() -> void:
	var lg := _league(2026)

	check(lg.teams.size() == 8, "league has 8 teams (got %d)" % lg.teams.size())

	var rosters_ok := true
	for t in lg.teams:
		if t.roster.size() != 12:
			rosters_ok = false
	check(rosters_ok, "every team carries a 12-man roster")

	# You are the unique weakest team.
	var pt := lg.player_team()
	check(pt != null and pt.is_player_team, "player team is flagged")
	var weakest := true
	for t in lg.teams:
		if t.id != pt.id and t.team_ovr() <= pt.team_ovr():
			weakest = false
	check(weakest, "player team is the unique worst (ovr %.1f)" % pt.team_ovr())
	check(pt.championships == 0, "player team starts with 0 rings")

	# The dynasty owns the most titles, strictly, and out-classes you on the floor.
	var dyn := lg.dynasty_team()
	var dyn_top := true
	for t in lg.teams:
		if t.id != dyn.id and t.championships >= dyn.championships:
			dyn_top = false
	check(dyn_top, "dynasty owns the most titles (%d)" % dyn.championships)
	check(dyn.team_ovr() > pt.team_ovr() + 8.0, "dynasty out-classes you (%.1f vs %.1f)" % [dyn.team_ovr(), pt.team_ovr()])

	# Seeded history is consistent with the title counts.
	var title_sum := 0
	for t in lg.teams:
		title_sum += t.championships
	check(lg.history.size() == 15, "15 seasons of history seeded (got %d)" % lg.history.size())
	check(title_sum == lg.history.size(), "title counts match seeded history (%d == %d)" % [title_sum, lg.history.size()])
	var years_ok := true
	for h in lg.history:
		if int(h["year"]) < 2011 or int(h["year"]) >= 2026:
			years_ok = false
	check(years_ok, "history years fall in the 15 seasons before 2026")

	# Strength band + position sanity.
	var band_ok := true
	var pos_ok := true
	for t in lg.teams:
		var o := t.team_ovr()
		if o < 30.0 or o > 95.0:
			band_ok = false
		if t.count_position("PG") < 1 or t.count_position("C") < 1:
			pos_ok = false
	check(band_ok, "all team OVRs sit in a sane band")
	check(pos_ok, "every team has at least one PG and one C")

	# Determinism.
	var lg2 := _league(2026)
	check(lg2.player_team().team_ovr() == pt.team_ovr() and lg2.dynasty_team().championships == dyn.championships, "same seed reproduces the league")

	# Standings-style print.
	print("\n--- league (by rotation OVR) ---")
	var ranked := lg.teams.duplicate()
	ranked.sort_custom(func(a, b): return a.team_ovr() > b.team_ovr())
	for t in ranked:
		var tag := ""
		if t.id == dyn.id:
			tag = "   [dynasty]"
		elif t.is_player_team:
			tag = "   [you]"
		print("  %-24s OVR %4.1f   titles %d   market %.2f%s" % [t.name, t.team_ovr(), t.championships, t.market_size, tag])
