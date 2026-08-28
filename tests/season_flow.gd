extends "res://tests/TestRunner.gd"
## Season-progression gate: the 2K-MyLeague phase machine added on top of the existing sim.
## Verifies (1) a game-by-game PLAYED season reproduces the one-shot SIM exactly (the determinism
## the whole refactor rests on), (2) phases advance strictly regular_season -> playoffs -> draft ->
## free_agency -> next regular_season with the year ticking once, and (3) you can't act out of phase.

func _standings_match(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if int(a[i]["team_id"]) != int(b[i]["team_id"]) or int(a[i]["wins"]) != int(b[i]["wins"]):
			return false
	return true

func run_tests() -> void:
	# --- play a single game: it's yours, it counts, it advances ----------------
	GameState.new_game(7)
	check(GameState.current_phase == "regular_season", "a new game opens in the regular season")
	var p0 := GameState.season_player_progress()
	check(int(p0["played"]) == 0 and int(p0["total"]) == 35, "season starts at 0 of 35 played")
	var pid := GameState.league.player_team_id
	var r := GameState.take_player_game(false)
	check(r != null, "you can play your next game")
	check(r.home_team_id == pid or r.away_team_id == pid, "the game played is YOUR game")
	check(int(GameState.season_player_progress()["played"]) == 1, "playing advances your game count")
	var you := GameState.league.player_team()
	check(you.wins + you.losses == 1, "the result counts in the standings")

	# --- a matchday advances EVERY team one game (no front-loaded teams) --------
	GameState.new_game(55)
	GameState.take_player_game(false)
	var lo := 999
	var hi := 0
	for t in GameState.league.teams:
		lo = mini(lo, t.wins + t.losses)
		hi = maxi(hi, t.wins + t.losses)
	check(lo == 1 and hi == 1, "after 1 matchday every team has played exactly 1 game (%d..%d)" % [lo, hi])
	GameState.sim_next_game()
	GameState.sim_next_game()
	lo = 999
	hi = 0
	for t in GameState.league.teams:
		lo = mini(lo, t.wins + t.losses)
		hi = maxi(hi, t.wins + t.losses)
	check(lo == 3 and hi == 3, "after 3 matchdays every team has played exactly 3 (%d..%d)" % [lo, hi])

	# --- watching a game == simming it (log_events never touches the RNG) -------
	GameState.new_game(123)
	var rs := GameState.take_player_game(false)
	GameState.new_game(123)
	var rw := GameState.take_player_game(true)
	check(rs.home_score == rw.home_score and rs.away_score == rw.away_score and rs.winner_id == rw.winner_id,
		"watching a game yields the identical result to simming it")

	# --- a fully PLAYED season reproduces the one-shot SIM (same seed) ----------
	GameState.new_game(777)
	GameState.advance_year()                          # the quick-sim escape path
	var sim_standings: Array = GameState.last_season["standings"]
	var sim_champ := int(GameState.last_season["champion_id"])

	GameState.new_game(777)
	GameState.sim_rest_of_season()                    # the played path, simmed game-by-game
	var play_standings: Array = GameState.last_season["standings"]
	var play_champ := int(GameState.last_season["champion_id"])
	check(play_champ == sim_champ, "played season crowns the same champion as the sim")
	check(_standings_match(play_standings, sim_standings), "played season reproduces the simmed standings exactly")

	# --- the phase machine runs a full cycle in strict order -------------------
	GameState.new_game(42)
	var start_year := GameState.current_year
	check(GameState.current_phase == "regular_season", "cycle: starts in the regular season")
	GameState.sim_rest_of_season()
	check(GameState.current_phase == "playoffs", "cycle: finishing the schedule enters the playoffs")
	check(not GameState.last_season.is_empty(), "cycle: the season is snapshotted for the Season Center")
	GameState.enter_offseason_draft()
	check(GameState.current_phase == "draft" and GameState.draft_active, "cycle: continue opens the draft")
	while GameState.draft_is_player_turn():
		GameState.draft_autopick()
	GameState.enter_free_agency()
	check(GameState.current_phase == "free_agency" and GameState.fa_active, "cycle: after the draft comes free agency")
	GameState.finish_free_agency()
	check(GameState.current_phase == "regular_season", "cycle: finishing FA starts the next season")
	check(GameState.current_year == start_year + 1, "cycle: exactly one year passed")
	check(not GameState.season_schedule.is_empty() and GameState.season_cursor == 0, "cycle: a fresh schedule is laid out")
	check(GameState.league.player_team().wins == 0, "cycle: the new season's standings are reset")

	# --- you can't skip ahead --------------------------------------------------
	GameState.new_game(99)
	GameState.enter_offseason_draft()                 # no playoffs played yet -> must be a no-op
	check(GameState.current_phase == "regular_season" and not GameState.draft_active,
		"enter_offseason_draft is a no-op before the playoffs are done")
