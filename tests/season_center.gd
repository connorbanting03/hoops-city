extends "res://tests/TestRunner.gd"
## M11 gate: the season is no longer discarded. After advancing a year, GameState.last_season
## holds the full schedule (every box score), final standings, and the playoff bracket. We verify
## retention + the pure view-models the Season Center renders (box_model, schedule_rows,
## series_wins), and that every point is attributed in the box score.

const AppRootScene := preload("res://scenes/app_root.tscn")

func run_tests() -> void:
	GameState.new_game(2026)
	check(GameState.last_season.is_empty(), "no season is stored before you play one")

	var summary := GameState.advance_year()
	check(summary.has("season"), "advance_year returns a season snapshot")
	var ls := GameState.last_season
	check(not ls.is_empty(), "the season is retained after advancing")

	# --- retention ----------------------------------------------------------
	check(ls["games"].size() == 140, "all 140 regular-season games are kept (%d)" % ls["games"].size())
	check(ls["standings"].size() == 8, "standings snapshot has all 8 teams")
	check(ls["series"].size() == 3, "the playoff bracket has 2 semis + a final")

	# --- box score (pure) ---------------------------------------------------
	var r: GameResult = ls["games"][0]
	var bm := BoxScore.box_model(r, GameState.league)
	check(int(bm["home_score"]) == r.home_score and int(bm["away_score"]) == r.away_score, "box score keeps the final score")
	var hsum := 0
	for line in bm["home"]["rows"]:
		hsum += int(line["pts"])
	var asum := 0
	for line in bm["away"]["rows"]:
		asum += int(line["pts"])
	check(hsum == r.home_score and asum == r.away_score, "every point is attributed to a player (%d/%d)" % [hsum, asum])
	var sorted_ok := true
	for i in range(1, bm["home"]["rows"].size()):
		if int(bm["home"]["rows"][i - 1]["pts"]) < int(bm["home"]["rows"][i]["pts"]):
			sorted_ok = false
	check(sorted_ok, "box score is sorted by points")
	check(bm["mvp"] is String and bm["mvp"] != "-", "the game has a player of the game (%s)" % bm["mvp"])
	check(bm["home"]["rows"][0].has("fg") and bm["home"]["rows"][0].has("reb"), "lines carry shooting splits + rebounds")

	# --- your schedule (pure) -----------------------------------------------
	var you := GameState.league.player_team()
	var your_row := {}
	for row in ls["standings"]:
		if row["is_player"]:
			your_row = row
	var sched := SeasonScreen.schedule_rows(ls, you.id)
	check(sched.size() == 35, "your schedule has all 35 games (%d)" % sched.size())
	var wins := 0
	for g in sched:
		if g["won"]:
			wins += 1
	check(wins == int(your_row["wins"]), "schedule wins match the standings (%d-%d)" % [wins, sched.size() - wins])

	# --- playoff series (pure) ----------------------------------------------
	var final_series: Dictionary = ls["series"][2]
	check(String(final_series["round"]) == "Final", "the third series is the Final")
	var fw := SeasonScreen.series_wins(final_series)
	check(maxi(int(fw["high"]), int(fw["low"])) == 4, "the Final is a best-of-7 (winner reaches 4)")
	check(int(final_series["winner_id"]) == int(ls["champion_id"]), "the Final's winner is the champion")
	var semi_wins := SeasonScreen.series_wins(ls["series"][0])
	check(maxi(int(semi_wins["high"]), int(semi_wins["low"])) == 3, "semifinals are best-of-5 (winner reaches 3)")

	# --- shell wiring -------------------------------------------------------
	var app := AppRootScene.instantiate()
	add_child(app)
	app.boot()
	app.show_screen("season")
	check(app.current_screen() == "season", "the shell can open the Season screen")
	app.queue_free()

	# --- a fresh year refreshes the snapshot --------------------------------
	var y1: int = ls["year"]
	GameState.advance_year()
	check(int(GameState.last_season["year"]) == y1 + 1, "advancing replaces the snapshot with the new season")
