extends "res://tests/TestRunner.gd"
## M7 gate: a hidden-rating rookie class, scouting that reveals truth as you spend, and a
## lottery that gives the worst team the best odds without guaranteeing #1 (anti-tank).

func _width(r: Array) -> int:
	return int(r[1]) - int(r[0])

func run_tests() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var league := LeagueGenerator.generate_league(rng, {"year": 2026})
	league.league_cap = EconomyManager.league_cap_for_year(2026)

	# --- class generation ---
	var draft_class := DraftManager.generate_class(rng, 2026, 16)
	check(draft_class.size() == 16, "draft class has 16 prospects")
	var young_ok := true
	var hidden_ok := true
	for pr in draft_class:
		if pr.player.age < 18 or pr.player.age > 22:
			young_ok = false
		if not is_equal_approx(pr.uncertainty, 1.0):
			hidden_ok = false
	check(young_ok, "prospects are 18-22 years old")
	check(hidden_ok, "prospects start fully unscouted (uncertainty 1.0)")

	var sorted_class := draft_class.duplicate()
	sorted_class.sort_custom(func(a, b): return a.stock > b.stock)
	var top_pot := 0.0
	var bot_pot := 0.0
	for i in 4:
		top_pot += float(sorted_class[i].player.potential)
		bot_pot += float(sorted_class[sorted_class.size() - 1 - i].player.potential)
	check(top_pot > bot_pot, "high-stock prospects carry more upside (avg pot %.0f vs %.0f)" % [top_pot / 4.0, bot_pot / 4.0])

	# --- scouting reveals the truth ---
	var pr0: DraftProspect = draft_class[0]
	var band_before := _width(pr0.attr_range("shooting"))
	DraftManager.scout(pr0, DraftManager.FULL_SCOUT_COST)
	check(is_zero_approx(pr0.uncertainty), "full scouting removes all uncertainty")
	check(pr0.scouted_ovr() == pr0.player.overall(), "fully scouted estimate equals the true overall (%d)" % pr0.player.overall())
	check(_width(pr0.attr_range("shooting")) < band_before, "scouting narrows the estimate band (%d -> %d)" % [band_before, _width(pr0.attr_range("shooting"))])

	var pr1: DraftProspect = draft_class[1]
	var w_before := _width(pr1.attr_range("inside"))
	DraftManager.scout(pr1, DraftManager.FULL_SCOUT_COST * 0.5)
	check(pr1.uncertainty > 0.0 and pr1.uncertainty < 1.0, "partial scouting partially narrows it (uncertainty %.2f)" % pr1.uncertainty)
	check(_width(pr1.attr_range("inside")) < w_before, "partial scouting still narrows the band")

	# --- lottery: best odds to the worst, never guaranteed, never to a playoff team ---
	var season := SeasonManager.simulate_full_season(league, rng)
	var standings: Array = season["standings"]
	var worst_id = standings[7].id
	var playoff_ids := [standings[0].id, standings[1].id, standings[2].id, standings[3].id]
	var bottom4 := [standings[4].id, standings[5].id, standings[6].id, standings[7].id]

	var lr := RandomNumberGenerator.new()
	lr.seed = 99
	var worst_first := 0
	var playoff_top4 := 0
	var ever_first := {}
	for pid in bottom4:
		ever_first[pid] = 0
	var N := 3000
	for n in N:
		var order := DraftManager.run_lottery(standings, lr)
		if order[0] == worst_id:
			worst_first += 1
		ever_first[order[0]] = int(ever_first.get(order[0], 0)) + 1
		var top4 := order.slice(0, 4)
		for pid in playoff_ids:
			if pid in top4:
				playoff_top4 += 1
	var wf := float(worst_first) / float(N)
	check(wf > 0.30 and wf < 0.50, "worst team has the best #1 odds but no guarantee (%.2f)" % wf)
	check(playoff_top4 == 0, "playoff teams never receive a lottery (top-4) pick")
	var all_can := true
	for pid in bottom4:
		if int(ever_first.get(pid, 0)) == 0:
			all_can = false
	check(all_can, "every bottom-4 team can jump to #1")
	var one := DraftManager.run_lottery(standings, lr)
	var uniq := {}
	for x in one:
		uniq[x] = true
	check(one.size() == 8 and uniq.size() == 8, "draft order covers all 8 teams exactly once")

	# --- draft execution ---
	var dr := RandomNumberGenerator.new()
	dr.seed = 7
	var class2 := DraftManager.generate_class(dr, 2026, 16)
	var max_stock := 0
	for pr in class2:
		max_stock = maxi(max_stock, pr.stock)
	var order2 := DraftManager.run_lottery(standings, dr)
	var results := DraftManager.run_draft(league, order2, class2, dr, 2)
	check(results.size() == 16, "a 2-round draft makes 16 picks")
	check(int(results[0]["stock"]) == max_stock, "the #1 overall pick is the top-rated prospect")
	var gained := {}
	for res in results:
		gained[res["team_id"]] = int(gained.get(res["team_id"], 0)) + 1
	var even := true
	for tid in gained:
		if gained[tid] != 2:
			even = false
	check(gained.size() == 8 and even, "every team drafted exactly 2 players")

	# --- snapshot ---
	print("\n--- draft board (top 6 by stock) ---")
	var board := class2.duplicate()
	board.sort_custom(func(a, b): return a.stock > b.stock)
	for i in 6:
		var pr: DraftProspect = board[i]
		print("  %-18s %-2s %-13s stock %2d  (true OVR %2d, pot %2d)  proj: %s" % [
			pr.player.full_name(), pr.player.primary_pos, pr.player.archetype, pr.stock,
			pr.player.overall(), pr.player.potential, pr.projected_range])
	print("\n  #1 lottery odds: worst=%.0f%%, then %.0f/%.0f/%.0f%%" % [
		DraftManager.LOTTERY_WEIGHTS[0], DraftManager.LOTTERY_WEIGHTS[1], DraftManager.LOTTERY_WEIGHTS[2], DraftManager.LOTTERY_WEIGHTS[3]])
