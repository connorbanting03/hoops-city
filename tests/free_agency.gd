extends "res://tests/TestRunner.gd"
## M8 gate: the FA market — pool generation, preference-driven choices (stars chase winning,
## role players chase money), bidding-war salary inflation, cap-bounded offers, roster churn,
## and the payoff: the best free agent lands with a winning/big-market team.

var _cap := 0

func _team(rng: RandomNumberGenerator, tname: String, talent: float, market: float, n: int) -> TeamData:
	const RECIPE := ["Floor General", "Slasher", "Sharpshooter", "3-and-D Wing", "Two-Way Star", "Rim Protector", "Stretch Big", "Bruiser", "Glue Guy"]
	var t := TeamData.new()
	t.name = tname
	t.market_size = market
	var ros: Array[PlayerData] = []
	for i in n:
		var p := PlayerGenerator.generate_player(rng, {"archetype": RECIPE[i % RECIPE.size()], "talent_bonus": talent})
		p.salary = EconomyManager.fair_salary(p.overall(), _cap)
		ros.append(p)
	t.roster = ros
	return t

func _avg(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0.0
	for x in arr:
		s += float(x)
	return s / float(arr.size())

func run_tests() -> void:
	_cap = EconomyManager.league_cap_for_year(2026)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026

	# --- pool generation ---
	var pool := FreeAgencyManager.generate_pool(rng, 2026, 24)
	check(pool.size() == 24, "pool has 24 free agents")
	var unsigned_ok := true
	var age_ok := true
	for fa in pool:
		if fa.salary != 0:
			unsigned_ok = false
		if fa.age < 28 or fa.age > 36:
			age_ok = false
	check(unsigned_ok, "free agents start unsigned (salary 0)")
	check(age_ok, "free agents are aging vets (28-36)")

	# --- preferences: stars vs role players ---
	var star := PlayerGenerator.generate_player(rng, {"archetype": "Two-Way Star", "talent_bonus": 18.0})
	var role := PlayerGenerator.generate_player(rng, {"archetype": "Glue Guy", "talent_bonus": -10.0})
	var pr := RandomNumberGenerator.new()
	pr.seed = 5
	var star_pref := FreeAgencyManager.fa_preferences(star, pr)
	var role_pref := FreeAgencyManager.fa_preferences(role, pr)
	check(star_pref["success"] + star_pref["market"] > star_pref["money"], "stars prioritize winning + market over money")
	check(role_pref["money"] + role_pref["role"] > role_pref["success"] + role_pref["market"], "role players prioritize money + minutes")

	# --- offer scoring respects preferences ---
	var contender := _team(rng, "Contender", 12.0, 1.6, 9)
	var rebuilder := _team(rng, "Rebuilder", -12.0, 0.7, 9)
	var money_pref := {"money": 0.85, "success": 0.05, "role": 0.05, "market": 0.05}
	var succ_pref := {"money": 0.10, "success": 0.70, "role": 0.10, "market": 0.10}
	var high := 25_000_000
	var low := 18_000_000
	check(FreeAgencyManager.offer_score(star, money_pref, rebuilder, high, _cap) > FreeAgencyManager.offer_score(star, money_pref, contender, low, _cap), "a money-driven FA chases the bigger check")
	check(FreeAgencyManager.offer_score(star, succ_pref, contender, low, _cap) > FreeAgencyManager.offer_score(star, succ_pref, rebuilder, high, _cap), "a winning-driven FA chases the contender")
	# the payoff: at EQUAL pay, a star picks the winner / big market.
	check(FreeAgencyManager.offer_score(star, star_pref, contender, 22_000_000, _cap) > FreeAgencyManager.offer_score(star, star_pref, rebuilder, 22_000_000, _cap), "at equal pay the star picks the winner + big market")

	# --- offers bounded by cap room ---
	var capped := _team(rng, "Capped", 14.0, 1.5, 12)   # stacked + expensive => little room
	var room := FreeAgencyManager.cap_room(capped, _cap)
	check(FreeAgencyManager.valuation(capped, star, _cap) <= maxi(0, room), "a team never values a FA above its cap room")
	var roomy := _team(rng, "Roomy", 0.0, 1.0, 7)        # short roster => room to spend
	check(FreeAgencyManager.valuation(roomy, star, _cap) > 0, "a roomy team can bid")

	# --- full market resolution ---
	var fr := RandomNumberGenerator.new()
	fr.seed = 41
	var teams := [
		_team(fr, "Hawks", 13.0, 1.7, 9), _team(fr, "Kings", 8.0, 1.3, 9),
		_team(fr, "Bolts", 0.0, 1.0, 9), _team(fr, "Miners", -6.0, 0.9, 9),
		_team(fr, "Bisons", -12.0, 0.7, 9),
	]
	var market_pool := FreeAgencyManager.generate_pool(fr, 2027, 18)
	var signings := FreeAgencyManager.resolve(teams, market_pool, _cap, fr, true)
	check(signings.size() > 0, "free agents sign with teams (%d signings)" % signings.size())

	var contested_extra := []
	var uncontested_extra := []
	var contested_above := false
	var bound_ok := true
	for s in signings:
		var ask := EconomyManager.fair_salary(int(s["ovr"]), _cap)
		var extra := float(s["salary"]) - float(ask)
		if s["contested"]:
			contested_extra.append(extra)
			if int(s["salary"]) > ask:
				contested_above = true
		else:
			uncontested_extra.append(extra)
		if int(s["salary"]) > int(_cap * 0.5):
			bound_ok = false
	check(contested_above, "contested free agents get bid up above their base ask")
	check(_avg(contested_extra) > _avg(uncontested_extra), "bidding wars inflate salaries vs uncontested signings (+%s vs +%s)" % [int(_avg(contested_extra)), int(_avg(uncontested_extra))])
	check(bound_ok, "no signing exceeds a sane share of the cap")

	# the best FA lands with an appealing team.
	var best = signings[0]
	for s in signings:
		if int(s["ovr"]) > int(best["ovr"]):
			best = s
	var appeals := []
	for t in teams:
		appeals.append(FreeAgencyManager.team_appeal(t))
	var best_team_appeal := 0.0
	for t in teams:
		if t.name == best["team"]:
			best_team_appeal = FreeAgencyManager.team_appeal(t)
	check(best_team_appeal >= _avg(appeals), "the top free agent signs with an above-average team (%.2f vs avg %.2f)" % [best_team_appeal, _avg(appeals)])

	# --- churn: a full roster cuts a player back into the pool ---
	var cr := RandomNumberGenerator.new()
	cr.seed = 88
	var full := _team(cr, "FullHouse", -6.0, 1.2, 12)   # cheap roster => plenty of cap room
	var before_ids := {}
	for p in full.roster:
		before_ids[p.id] = true
	var upgrade := PlayerGenerator.generate_player(cr, {"archetype": "Two-Way Star", "talent_bonus": 28.0})
	upgrade.salary = 0
	var churn_pool: Array[PlayerData] = [upgrade]
	var s3 := FreeAgencyManager.resolve([full], churn_pool, _cap, cr, true)
	check(s3.size() == 1, "the upgrade free agent signs with the full team")
	var churned := false
	for p in churn_pool:
		if before_ids.has(p.id):
			churned = true
	check(churned, "signing onto a full roster cuts a player back into the pool (churn)")

	# --- snapshot ---
	print("\n--- free agency results ---")
	for s in signings:
		var flag := "  <- bidding war" if s["contested"] else ""
		print("  %-18s %-2s OVR %2d -> %-8s $%4.1fM (%d bidders)%s" % [s["fa"], s["pos"], s["ovr"], s["team"], float(s["salary"]) / 1_000_000.0, s["bidders"], flag])
