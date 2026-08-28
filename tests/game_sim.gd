extends "res://tests/TestRunner.gd"
## M3 gate: the possession sim yields believable box scores (realistic scoring, FG%/3P%/FT%),
## internally consistent stat lines, the better team usually wins, and runs reproducibly.

func _league(seed_val: int) -> LeagueData:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return LeagueGenerator.generate_league(rng, {"year": 2026})

## Win rate of team `a` over `games`, alternating home/away to cancel home-court edge.
func _win_rate(a: TeamData, b: TeamData, games: int, seed_val: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var a_wins := 0
	for g in games:
		var r: GameResult = (GameSimulator.simulate_game(a, b, rng) if g % 2 == 0 else GameSimulator.simulate_game(b, a, rng))
		if r.winner_id == a.id:
			a_wins += 1
	return float(a_wins) / float(games)

func run_tests() -> void:
	var lg := _league(2026)
	var dyn := lg.dynasty_team()
	var you := lg.player_team()

	# Aggregate a big sample across varied matchups.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9000
	var games := 0
	var pts_sum := 0
	var fgm := 0
	var fga := 0
	var tpm := 0
	var tpa := 0
	var ftm := 0
	var fta := 0
	var identity_ok := true
	var nonneg_ok := true
	var totals_ok := true
	var mvp_valid := true

	for n in 400:
		var i := rng.randi() % lg.teams.size()
		var j := rng.randi() % lg.teams.size()
		if i == j:
			continue
		var r: GameResult = GameSimulator.simulate_game(lg.teams[i], lg.teams[j], rng)
		games += 1
		# Box integrity.
		var home_pts := 0
		var away_pts := 0
		for pid in r.box.keys():
			var s: Dictionary = r.box[pid]
			pts_sum += s["pts"]
			fgm += s["fgm"]; fga += s["fga"]; tpm += s["tpm"]; tpa += s["tpa"]; ftm += s["ftm"]; fta += s["fta"]
			if s["pts"] != s["ftm"] + 2 * s["fgm"] + s["tpm"]:
				identity_ok = false
			if s["fga"] < s["fgm"] or s["tpa"] < s["tpm"] or s["fta"] < s["ftm"] or s["tpm"] > s["fgm"]:
				nonneg_ok = false
			if r.team_of[pid] == r.home_team_id:
				home_pts += s["pts"]
			else:
				away_pts += s["pts"]
		if home_pts != r.home_score or away_pts != r.away_score:
			totals_ok = false
		if not r.box.has(r.mvp_id):
			mvp_valid = false

	var team_games := games * 2
	var avg_team_score := float(pts_sum) / float(team_games)
	var fg_pct := float(fgm) / float(fga)
	var tp_pct := float(tpm) / float(tpa)
	var ft_pct := float(ftm) / float(fta)

	check(identity_ok, "every box line obeys pts = ftm + 2*fgm + tpm")
	check(nonneg_ok, "attempts >= makes, threes <= field goals")
	check(totals_ok, "team score == sum of its players' points")
	check(mvp_valid, "every game names a valid MVP")
	check(avg_team_score > 88.0 and avg_team_score < 125.0, "avg team score realistic (%.1f)" % avg_team_score)
	check(fg_pct > 0.42 and fg_pct < 0.52, "league FG%% realistic (%.3f)" % fg_pct)
	check(tp_pct > 0.31 and tp_pct < 0.40, "league 3P%% realistic (%.3f)" % tp_pct)
	check(ft_pct > 0.68 and ft_pct < 0.86, "league FT%% realistic (%.3f)" % ft_pct)

	# Even a 30-OVR gap is never a lock — the underdog always has a puncher's chance.
	var dyn_wr := _win_rate(dyn, you, 500, 123)
	check(dyn_wr > 0.78 and dyn_wr < 0.99, "dynasty dominates but you always have a chance (%.2f)" % dyn_wr)

	# A modest favorite wins often but NOT always — variance creates upsets.
	var fav_wr := _win_rate(lg.teams[1], lg.teams[3], 300, 321)
	check(fav_wr > 0.58 and fav_wr < 0.88, "clear favorite wins often, upsets happen (%.2f)" % fav_wr)

	# Two close teams play near a coin flip.
	var close_wr := _win_rate(lg.teams[3], lg.teams[4], 300, 456)
	check(close_wr > 0.40 and close_wr < 0.70, "close teams are competitive (%.2f)" % close_wr)

	# MVP usually comes from the winning side.
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 77
	var mvp_on_winner := 0
	var mvp_total := 0
	for n in 200:
		var r: GameResult = GameSimulator.simulate_game(dyn, lg.teams[2], rng2)
		mvp_total += 1
		if r.team_of[r.mvp_id] == r.winner_id:
			mvp_on_winner += 1
	check(float(mvp_on_winner) / float(mvp_total) > 0.55, "MVP usually on the winning team (%.2f)" % (float(mvp_on_winner) / float(mvp_total)))

	# Determinism.
	var ra := RandomNumberGenerator.new()
	ra.seed = 555
	var g1: GameResult = GameSimulator.simulate_game(dyn, you, ra)
	var rb := RandomNumberGenerator.new()
	rb.seed = 555
	var g2: GameResult = GameSimulator.simulate_game(dyn, you, rb)
	check(g1.home_score == g2.home_score and g1.away_score == g2.away_score, "same seed reproduces the game (%d-%d)" % [g1.home_score, g1.away_score])

	_print_sample_box(dyn, you)

func _print_sample_box(home: TeamData, away: TeamData) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260614
	var r: GameResult = GameSimulator.simulate_game(home, away, rng, {"log_events": true})
	print("\n--- sample game: %s %d @ %s %d ---" % [away.name, r.away_score, home.name, r.home_score])
	print("  %-18s %3s %4s %4s %4s %4s %4s %4s %4s %4s" % ["PLAYER", "PTS", "FG", "3P", "FT", "REB", "AST", "STL", "BLK", "TOV"])
	for pid in r.home_pids:
		_print_line(r, pid)
	print("  MVP: %s" % r.names.get(r.mvp_id, "?"))

func _print_line(r: GameResult, pid: int) -> void:
	var s: Dictionary = r.box[pid]
	print("  %-18s %3d %4s %4s %4s %4d %4d %4d %4d %4d" % [
		r.names[pid], s["pts"],
		"%d/%d" % [s["fgm"], s["fga"]], "%d/%d" % [s["tpm"], s["tpa"]], "%d/%d" % [s["ftm"], s["fta"]],
		s["oreb"] + s["dreb"], s["ast"], s["stl"], s["blk"], s["tov"],
	])
