extends "res://tests/TestRunner.gd"
## M6 gate: buildings raise capacity, population converges to capacity x attractiveness,
## winning makes the city more desirable, costs escalate faster than returns, dividends scale
## with population, and — the keystone — a developed city lifts the team's effective budget.

func _fmt(n) -> String:
	return "$%.1fM" % (float(n) / 1_000_000.0)

func _popf(n) -> String:
	var p := float(n)
	if p >= 1_000_000_000.0:
		return "%.2fB" % (p / 1e9)
	if p >= 1_000_000.0:
		return "%.2fM" % (p / 1e6)
	if p >= 1_000.0:
		return "%.1fK" % (p / 1e3)
	return "%d" % int(p)

func _build_metropolis() -> CityData:
	var c := CityManager.generate_starter_city()
	for i in 120:
		CityManager.build(c, "condo_tower")
	for i in 30:
		CityManager.build(c, "office")
	for i in 15:
		CityManager.build(c, "hotel")
	for i in 12:
		CityManager.build(c, "theater")
	for i in 6:
		CityManager.build(c, "park")
	CityManager.build(c, "monument")
	CityManager.advance_population(c, 0.6, 80)
	return c

func run_tests() -> void:
	# 1. residential raises capacity.
	var c := CityManager.generate_starter_city()
	var cap0 := CityManager.housing_capacity(c)
	CityManager.build(c, "condo_tower")
	check(CityManager.housing_capacity(c) > cap0, "building residential raises housing capacity")

	# 2. population converges to capacity x attractiveness.
	var c2 := CityManager.generate_starter_city()
	CityManager.advance_population(c2, 0.3, 60)
	var target := CityManager.target_population(c2, 0.3)
	check(absf(c2.population - target) < target * 0.02, "population converges to capacity x attractiveness (%.0f ~ %.0f)" % [c2.population, target])

	# 3. a winning team makes the city more attractive.
	var a_lose := CityManager.attractiveness(c2, 0.1)
	var a_win := CityManager.attractiveness(c2, 0.9)
	check(a_win > a_lose, "winning raises attractiveness (%.3f > %.3f)" % [a_win, a_lose])
	check(CityManager.target_population(c2, 0.9) > CityManager.target_population(c2, 0.1), "winning raises the population ceiling")

	# 4. costs escalate faster than returns.
	var b := CityManager.build(c2, "office")
	var cost_t1 := CityManager.upgrade_cost(b)
	var out_t1 := CityManager._out(b, "dividend")
	CityManager.upgrade(b)
	var cost_t2 := CityManager.upgrade_cost(b)
	var out_t2 := CityManager._out(b, "dividend")
	check(cost_t2 > cost_t1 and out_t2 > out_t1, "upgrades cost more and output more")
	check(float(cost_t2) / out_t2 > float(cost_t1) / out_t1, "cost scales faster than output (diminishing returns)")
	check(CityManager.build_cost(c2, "shops") > int(CityManager.CATALOG["shops"]["cost"]), "each added building of a type costs more")

	# 5. dividends scale with population.
	c2.population = 10000.0
	var div_low := CityManager.dividends(c2, 0.5)
	c2.population = 1_000_000.0
	var div_high := CityManager.dividends(c2, 0.5)
	check(div_low > 0.0 and div_high > div_low * 5.0, "building dividends scale up with population")

	# 6. KEYSTONE: a developed city lifts the team's effective budget.
	var cap := EconomyManager.league_cap_for_year(2026)
	var neutral := {"win_pct": 0.45, "made_playoffs": false, "rounds_won": 0, "champion": false}

	var starter := CityManager.generate_starter_city()
	var team_s := TeamData.new()
	team_s.market_size = CityManager.market_size(starter)
	var eff_starter := EconomyManager.effective_budget(team_s, cap, neutral)

	var metro := _build_metropolis()
	var team_m := TeamData.new()
	team_m.market_size = CityManager.market_size(metro)
	var eff_metro := EconomyManager.effective_budget(team_m, cap, neutral)

	check(team_m.market_size > team_s.market_size, "bigger city => bigger market (%.2f > %.2f)" % [team_m.market_size, team_s.market_size])
	check(eff_metro > int(eff_starter * 1.4), "a developed city blows up the roster budget (%s -> %s)" % [_fmt(eff_starter), _fmt(eff_metro)])

	# 7. endless but bounded.
	var mega := CityData.new()
	mega.population = 25_000_000.0
	var giga := CityData.new()
	giga.population = 250_000_000.0
	check(CityManager.market_size(giga) > CityManager.market_size(mega), "market keeps growing with population (endless)")
	var t_giga := TeamData.new()
	t_giga.market_size = CityManager.market_size(giga)
	check(EconomyManager.market_factor(t_giga) < EconomyManager.MARKET_SOFT, "market factor stays bounded even at 250M people")

	# 8. city dividends feed team revenue.
	var lg := LeagueData.new()
	lg.league_cap = cap
	var team_rev := TeamData.new()
	team_rev.market_size = 1.0
	var base_rev := EconomyManager.season_revenue(team_rev, neutral, lg, 0.0)
	var with_div := EconomyManager.season_revenue(team_rev, neutral, lg, 20_000_000.0)
	check(with_div["total"] > base_rev["total"], "city dividends add to team revenue")

	# --- snapshot ---
	print("\n--- metropolis snapshot ---")
	print("  buildings %d   population %s   capacity %s" % [metro.buildings.size(), _popf(metro.population), _popf(CityManager.housing_capacity(metro))])
	print("  attractiveness %.2f   dividends %s/yr" % [CityManager.attractiveness(metro, 0.6), _fmt(CityManager.dividends(metro, 0.6))])
	print("  market_size %.2f -> market_factor %.3f" % [team_m.market_size, EconomyManager.market_factor(team_m)])
	print("  effective budget:  starter %s  ->  metropolis %s" % [_fmt(eff_starter), _fmt(eff_metro)])
