extends "res://tests/TestRunner.gd"
## M10 gate: the app shell + roster view. The simulation is untouched here — this verifies the
## presentation layer reads it correctly. We assert on the PURE view-models (card_model,
## roster_rows) so the checks need no window, then do a headless smoke of the shell's screen
## swapping and EventBus navigation.

const AppRootScene := preload("res://scenes/app_root.tscn")

func run_tests() -> void:
	GameState.new_game(2026)
	var you := GameState.league.player_team()

	# --- UITheme formatters -------------------------------------------------
	check(UITheme.moneyf(50_000_000) == "$50.0M", "money formats millions ($50.0M)")
	check(UITheme.moneyf(-2_000_000) == "-$2.0M", "money formats negatives")
	check(UITheme.popf(1500) == "1.5K", "population formats thousands (1.5K)")
	check(UITheme.popf(2_400_000) == "2.40M", "population formats millions")
	check(UITheme.height_label(201).contains("'"), "height renders feet/inches (%s)" % UITheme.height_label(201))

	# --- PlayerCard.card_model (pure) ---------------------------------------
	var p: PlayerData = you.rotation(1)[0]
	var m := PlayerCard.card_model(p)
	check(m["attrs"].size() == 10, "card shows all 10 attributes")
	var keys_ok := true
	for i in PlayerData.ATTRS.size():
		if m["attrs"][i]["key"] != PlayerData.ATTRS[i]:
			keys_ok = false
	check(keys_ok, "card attributes are in canonical order")
	check(int(m["ovr"]) == p.overall(), "card OVR matches the player (%d)" % p.overall())
	check(m["pos_ovr"].size() == 5, "card grades OVR at all 5 positions")
	check(int(m["pos_ovr"][p.primary_pos]) == p.overall_for(p.primary_pos), "primary-position OVR is correct")
	check(m["salary_label"].begins_with("$"), "salary is money-formatted (%s)" % m["salary_label"])
	check(m["upside"] is String and m["upside"] in ["Proven", "Elite", "High", "Moderate", "Low"], "upside is a coarse band, not the raw potential (%s)" % m["upside"])
	check(not m["upside"].is_valid_int(), "upside never leaks the hidden potential number")

	# --- RosterScreen.roster_rows (pure) ------------------------------------
	var rows := RosterScreen.roster_rows(you)
	check(rows.size() == you.roster.size(), "roster_rows covers the whole roster (%d)" % rows.size())
	var sorted_desc := true
	for i in range(1, rows.size()):
		if int(rows[i - 1]["ovr"]) < int(rows[i]["ovr"]):
			sorted_desc = false
	check(sorted_desc, "default sort is OVR descending")
	var has_attrs := true
	for k in PlayerData.ATTRS:
		if not rows[0].has(k):
			has_attrs = false
	check(has_attrs, "each row carries all 10 attribute columns")
	var byname := RosterScreen.roster_rows(you, "name", false)
	check(byname.size() >= 2 and String(byname[0]["name"]) <= String(byname[1]["name"]), "rows re-sort by name ascending")
	var byage := RosterScreen.roster_rows(you, "age", true)
	check(int(byage[0]["age"]) >= int(byage[byage.size() - 1]["age"]), "rows re-sort by age descending")

	# --- shell smoke: boot, screen swap, EventBus nav -----------------------
	var app := AppRootScene.instantiate()
	add_child(app)            # _ready() returns early under headless; we drive boot() ourselves
	app.boot()
	check(app.current_screen() == "plaza", "shell boots into the Plaza (avatar front door)")
	app.show_screen("roster", {"team_id": you.id})
	check(app.current_screen() == "roster", "shell switches to the Roster screen")
	check(app.get_child_count() > 0, "shell built its chrome")
	# Navigation via the bus (what a clicked standings row fires):
	EventBus.screen_requested.emit("hub", {})
	check(app.current_screen() == "hub", "EventBus.screen_requested drives navigation")
	app.show_screen("roster", {"team_id": GameState.league.dynasty_team_id})
	check(app.current_screen() == "roster", "can open another team's roster from the bus")
	app.queue_free()

	# --- the world is untouched (no sim ran) --------------------------------
	check(GameState.current_year == 2026, "viewing rosters did not advance the world")
