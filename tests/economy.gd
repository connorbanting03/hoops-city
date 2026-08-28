extends "res://tests/TestRunner.gd"
## M5 gate: the league cap rises yearly, Market/Success factors behave (Market diminishes),
## the effective budget lets big-market winners blow past small-market losers, salaries scale
## with talent, and a season's cash flow rewards winning + a big market.

func _fmt(n) -> String:
	return "$%.1fM" % (float(n) / 1_000_000.0)

func run_tests() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var lg := LeagueGenerator.generate_league(rng, {"year": 2026})
	lg.league_cap = EconomyManager.league_cap_for_year(2026)
	EconomyManager.assign_initial_salaries(lg)

	var dyn := lg.dynasty_team()
	var you := lg.player_team()

	# --- league cap rises year over year ---
	var c26 := EconomyManager.league_cap_for_year(2026)
	var c27 := EconomyManager.league_cap_for_year(2027)
	var c36 := EconomyManager.league_cap_for_year(2036)
	check(c27 > c26, "league cap rises each year (%s -> %s)" % [_fmt(c26), _fmt(c27)])
	check(c36 > int(c26 * 1.4), "cap grows meaningfully over a decade (%s -> %s)" % [_fmt(c26), _fmt(c36)])

	# --- market factor: monotonic, diminishing, bounded ---
	var mf_you := EconomyManager.market_factor(you)       # smallest market (0.70)
	var mf_dyn := EconomyManager.market_factor(dyn)       # biggest (1.70)
	check(mf_you >= 0.0 and mf_you < 0.05, "smallest market gets ~no bonus (%.3f)" % mf_you)
	check(mf_dyn > mf_you, "bigger market => bigger factor (%.3f > %.3f)" % [mf_dyn, mf_you])
	var t1 := TeamData.new(); t1.market_size = 1.7
	var t2 := TeamData.new(); t2.market_size = 2.7
	var t3 := TeamData.new(); t3.market_size = 3.7
	var step_a := EconomyManager.market_factor(t2) - EconomyManager.market_factor(t1)
	var step_b := EconomyManager.market_factor(t3) - EconomyManager.market_factor(t2)
	check(step_b < step_a, "market factor has diminishing returns (%.3f < %.3f)" % [step_b, step_a])
	var t_huge := TeamData.new(); t_huge.market_size = 50.0
	check(EconomyManager.market_factor(t_huge) < EconomyManager.MARKET_SOFT, "market factor stays bounded even for a metropolis")

	# --- success factor ---
	var win_res := {"win_pct": 0.86, "made_playoffs": true, "rounds_won": 2, "champion": true}
	var lose_res := {"win_pct": 0.14, "made_playoffs": false, "rounds_won": 0, "champion": false}
	var sf_win := EconomyManager.success_factor(dyn, win_res)
	var sf_lose := EconomyManager.success_factor(you, lose_res)
	check(sf_win > sf_lose + 0.6, "a title season dwarfs a losing one (%.2f vs %.2f)" % [sf_win, sf_lose])
	check(sf_lose < 0.05, "a 5-30 season earns ~no success bonus (%.2f)" % sf_lose)
	check(sf_win <= 1.1, "success factor stays bounded (%.2f)" % sf_win)

	# --- effective budget: the flywheel link ---
	var eff_dyn := EconomyManager.effective_budget(dyn, lg.league_cap, win_res)
	var eff_you := EconomyManager.effective_budget(you, lg.league_cap, lose_res)
	check(eff_you == lg.league_cap, "small-market loser sits at the base cap (%s)" % _fmt(eff_you))
	check(eff_dyn > eff_you * 2, "big-market winner blows past the cap (%s vs %s)" % [_fmt(eff_dyn), _fmt(eff_you)])

	# --- salaries scale with talent ---
	var s_star := EconomyManager.fair_salary(80, lg.league_cap)
	var s_role := EconomyManager.fair_salary(55, lg.league_cap)
	var s_min := EconomyManager.fair_salary(38, lg.league_cap)
	check(s_star > s_role and s_role > s_min, "salary rises with OVR (%s > %s > %s)" % [_fmt(s_star), _fmt(s_role), _fmt(s_min)])
	check(s_star <= int(lg.league_cap * EconomyManager.SAL_MAX_FRAC) + 100000, "max salary respects the cap share (%s)" % _fmt(s_star))
	var sal_bounds_ok := true
	for t in lg.teams:
		for p in t.roster:
			if p.salary < 0 or p.salary > lg.league_cap:
				sal_bounds_ok = false
	check(sal_bounds_ok, "every assigned salary is sane")

	# --- two distinct ledgers + a full season's cash flow ---
	var sim := RandomNumberGenerator.new()
	sim.seed = 70
	var season := SeasonManager.simulate_full_season(lg, sim)
	var results := EconomyManager.derive_results(lg, season)

	var rev_dyn := EconomyManager.season_revenue(dyn, results[dyn.id], lg)
	var rev_you := EconomyManager.season_revenue(you, results[you.id], lg)
	check(rev_you["total"] > 0.0 and rev_dyn["total"] > 0.0, "both teams earn revenue")
	check(rev_dyn["total"] > rev_you["total"] * 1.8, "winning big market earns far more (%s vs %s)" % [_fmt(rev_dyn["total"]), _fmt(rev_you["total"])])

	var cash_before := you.cash
	EconomyManager.apply_season_economy(lg, results)
	check(you.cash != cash_before, "cash ledger updates after a season")
	check(dyn.cash > you.cash, "the dynasty banks more than you (%s vs %s)" % [_fmt(dyn.cash), _fmt(you.cash)])
	# Cap room is a different ledger than cash entirely.
	var room_you := EconomyManager.cap_room(you, lg.league_cap, results[you.id])
	check(room_you != you.cash, "cap room and cash are independent ledgers")

	# --- snapshot ---
	_snapshot("YOU  ", you, lg, results[you.id])
	_snapshot("DYN  ", dyn, lg, results[dyn.id])

func _snapshot(tag: String, team, lg, res: Dictionary) -> void:
	var rev := EconomyManager.season_revenue(team, res, lg)
	print("\n--- %s %s (W%%=%.2f, champ=%s) ---" % [tag, team.name, res["win_pct"], str(res["champion"])])
	print("  market_factor %.3f   success_factor %.3f" % [EconomyManager.market_factor(team), EconomyManager.success_factor(team, res)])
	print("  league cap %s   effective budget %s" % [_fmt(lg.league_cap), _fmt(EconomyManager.effective_budget(team, lg.league_cap, res))])
	print("  payroll %s   cap room %s" % [_fmt(EconomyManager.payroll(team)), _fmt(EconomyManager.cap_room(team, lg.league_cap, res))])
	print("  revenue: gate %s + concessions %s + sponsorship %s + prize %s = %s" % [
		_fmt(rev["gate"]), _fmt(rev["concessions"]), _fmt(rev["sponsorship"]), _fmt(rev["prize"]), _fmt(rev["total"])])
	print("  cash %s" % _fmt(team.cash))
