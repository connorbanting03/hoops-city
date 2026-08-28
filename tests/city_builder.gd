extends "res://tests/TestRunner.gd"
## M14 gate: the city is now built by hand. Verify that building/upgrading spends cash and raises
## the city's outputs, that the Population->Market->Budget chain actually responds, and that the
## interactive off-season no longer auto-spends your cash (it's yours to allocate) while the
## quick-sim / auto path still grows the city on its own.

func _autopick_draft() -> void:
	GameState.begin_offseason()
	while GameState.draft_is_player_turn():
		GameState.draft_autopick()

func run_tests() -> void:
	GameState.new_game(2026)
	var city := GameState.city
	var you := GameState.league.player_team()

	# --- building spends cash and adds capacity -----------------------------
	var cap0 := CityManager.housing_capacity(city)
	var cash0: int = you.cash
	var cost := CityManager.build_cost(city, "apartments")
	check(GameState.city_build("apartments"), "you can build housing you can afford")
	check(you.cash == cash0 - cost, "building spent the cash ($%d)" % cost)
	check(CityManager.housing_capacity(city) > cap0, "housing capacity went up")

	# --- can't build what you can't afford ----------------------------------
	you.cash = 0
	var cash_broke: int = you.cash
	check(not GameState.city_build("condo_tower"), "you can't build while broke")
	check(you.cash == cash_broke, "a failed build costs nothing")

	# --- upgrading raises a building's output -------------------------------
	you.cash = 1_000_000_000
	GameState.city_build("shops")
	var shop: BuildingData = null
	for b in city.buildings:
		if b.type == "shops":
			shop = b
	var div0: float = CityManager.building_outputs(shop)["dividend"]
	var ucost := CityManager.upgrade_cost(shop)
	var cash_before_up: int = you.cash
	check(GameState.city_upgrade(shop), "you can upgrade a building")
	check(you.cash == cash_before_up - ucost, "upgrading spent the cash")
	check(CityManager.building_outputs(shop)["dividend"] > div0, "the upgraded building outputs more")

	# --- the flywheel chain responds: build -> grow -> market rises ---------
	var m0 := CityManager.market_size(city)
	you.cash = 2_000_000_000
	for i in 3:
		GameState.city_build("condo_tower")
	for i in 2:
		GameState.city_build("office")
	GameState.city_build("theater")
	GameState.city_build("park")
	CityManager.advance_population(city, 0.7, 10)
	var m1 := CityManager.market_size(city)
	check(m1 > m0 + 0.1, "a bigger, more attractive city raises market size (%.2f -> %.2f)" % [m0, m1])

	# --- the interactive off-season does NOT auto-spend your cash -----------
	GameState.new_game(2026)
	_autopick_draft()
	var cash_pre: int = GameState.league.player_team().cash
	GameState.enter_free_agency()
	check(GameState.league.player_team().cash == cash_pre, "entering free agency left your cash for you to build with ($%d)" % cash_pre)

	# --- the quick-sim / auto path still grows the city by itself -----------
	GameState.new_game(2026)
	var pop0 := GameState.city.population
	GameState.advance_year()
	check(GameState.city.population > pop0, "advance_year still auto-invests and grows the city (%s -> %s)" % [UITheme.popf(pop0), UITheme.popf(GameState.city.population)])

	# --- shell can host the City screen -------------------------------------
	GameState.new_game(2026)
	var app := preload("res://scenes/app_root.tscn").instantiate()
	add_child(app)
	app.boot()
	app.show_screen("city")
	check(app.current_screen() == "city", "the shell opens the City screen")
	app.queue_free()
