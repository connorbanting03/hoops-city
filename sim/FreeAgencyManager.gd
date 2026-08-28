class_name FreeAgencyManager
extends RefCounted
## Free agency (GDD §4.4). Free agents weigh offers by money, the team's projected success,
## their role/minutes, and the market. Stars chase rings + big markets; role players chase
## money + minutes. Contested FAs get bid up (salary inflation), every offer is bounded by
## cap room, and teams cut their weakest player back into the pool — keeping the market alive.

const POOL_SIZE := 24
const MIN_YEARS := 1
const MAX_YEARS := 4

static func generate_pool(rng: RandomNumberGenerator, year: int, size: int = POOL_SIZE) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for i in size:
		var p := PlayerGenerator.generate_player(rng, {"age": rng.randi_range(28, 36), "id": 900000 + year * 100 + i, "talent_bonus": rng.randf_range(-10.0, 2.0)})
		p.salary = 0
		p.years_left = 0
		out.append(p)
	return out

static func team_appeal(team: TeamData) -> float:
	return clampf((team.team_ovr() - 45.0) / 35.0, 0.0, 1.0)

static func team_pos_strength(team: TeamData, pos: String) -> int:
	var best := 0
	for p in team.roster:
		if p.primary_pos == pos:
			best = maxi(best, p.overall_for(pos))
	return best

static func cap_room(team: TeamData, league_cap: int) -> int:
	var budget := int(round(float(league_cap) * (1.0 + EconomyManager.market_factor(team) + 0.6 * team_appeal(team))))
	return budget - EconomyManager.payroll(team)

## Preference weights (normalized). Stars (high OVR) tilt toward success + market; lesser
## players tilt toward money + minutes.
static func fa_preferences(fa: PlayerData, rng: RandomNumberGenerator) -> Dictionary:
	var star := clampf((float(fa.overall()) - 50.0) / 30.0, 0.0, 1.0)
	var w_money := (1.0 - star) * 1.2 + rng.randf_range(0.1, 0.6)
	var w_success := star * 1.4 + rng.randf_range(0.1, 0.5)
	var w_role := (1.0 - star) * 0.8 + rng.randf_range(0.1, 0.5)
	var w_market := star * 0.8 + rng.randf_range(0.0, 0.4)
	var tot := w_money + w_success + w_role + w_market
	return {"money": w_money / tot, "success": w_success / tot, "role": w_role / tot, "market": w_market / tot}

## How appealing one offer is to a FA, blending the four preference axes.
static func offer_score(fa: PlayerData, prefs: Dictionary, team: TeamData, salary: int, league_cap: int) -> float:
	var market_val := EconomyManager.fair_salary(fa.overall(), league_cap)
	var money := clampf(float(salary) / (float(market_val) * 1.5), 0.0, 1.2)
	var success := team_appeal(team)
	var role := clampf((float(fa.overall() - team_pos_strength(team, fa.primary_pos)) + 8.0) / 20.0, 0.0, 1.0)
	var market := clampf((team.market_size - 0.7) / 1.5, 0.0, 1.0)
	return prefs["money"] * money + prefs["success"] * success + prefs["role"] * role + prefs["market"] * market

## What a team will pay: base market value boosted by how much the FA upgrades the position,
## hard-capped by available cap room.
static func valuation(team: TeamData, fa: PlayerData, league_cap: int) -> int:
	var base := EconomyManager.fair_salary(fa.overall(), league_cap)
	var upgrade := clampf(float(fa.overall() - team_pos_strength(team, fa.primary_pos)) / 35.0, 0.0, 0.8)
	var want := int(round(float(base) * (1.0 + upgrade)))
	return mini(want, maxi(0, cap_room(team, league_cap)))

## Resolve the market: process the best FAs first; for each, an auction sets the price from the
## second-highest bidder (a real bidding war), and the FA picks the matching team he likes most.
## Mutates pool (signed FAs removed, cut players added) and rosters. Returns the signing log.
static func resolve(teams: Array, pool: Array, league_cap: int, rng: RandomNumberGenerator, allow_churn: bool = true) -> Array:
	var signings := []
	var fas := pool.duplicate()
	fas.sort_custom(func(a, b): return a.overall() > b.overall())
	for fa in fas:
		var prefs := fa_preferences(fa, rng)
		var ask := EconomyManager.fair_salary(fa.overall(), league_cap)
		var bidders := []
		for t in teams:
			var val := valuation(t, fa, league_cap)
			if val >= ask and team_pos_strength(t, fa.primary_pos) <= fa.overall() + 4:
				bidders.append({"team": t, "val": val})
		if bidders.is_empty():
			continue
		bidders.sort_custom(func(a, b): return a["val"] > b["val"])
		var price := ask
		if bidders.size() >= 2:
			price = clampi(int(bidders[1]["val"]), ask, int(bidders[0]["val"]))
		var eligible := []
		for bd in bidders:
			if int(bd["val"]) >= price:
				eligible.append(bd["team"])
		var best_team = eligible[0]
		var best_score := -1.0
		for t in eligible:
			var s := offer_score(fa, prefs, t, price, league_cap)
			if s > best_score:
				best_score = s
				best_team = t
		var salary := mini(price, cap_room(best_team, league_cap))
		fa.salary = salary
		fa.years_left = rng.randi_range(MIN_YEARS, MAX_YEARS)
		if allow_churn and best_team.roster.size() >= 12:
			var worst_i := 0
			for i in best_team.roster.size():
				if best_team.roster[i].overall() < best_team.roster[worst_i].overall():
					worst_i = i
			var cut = best_team.roster[worst_i]
			best_team.roster.remove_at(worst_i)
			cut.salary = 0
			pool.append(cut)
		best_team.roster.append(fa)
		pool.erase(fa)
		signings.append({
			"fa": fa.full_name(), "ovr": fa.overall(), "pos": fa.primary_pos,
			"team": best_team.name, "salary": salary, "bidders": bidders.size(),
			"contested": bidders.size() >= 2,
		})
	return signings

# --- interactive day-based market (M13) -------------------------------------
# The same economics as resolve(), but stretched over N days so the player competes offer-by-offer.
# Each day, every free agent weighs the standing offers (AI valuations + the player's bid) by
# offer_score; the strongest matches sign first (a falling daily threshold), and on the last day
# everyone with an offer signs. To land a target you must out-SCORE the field — and since a low
# market/poor record drag your score down, a small-market rebuild has to pay more to win. resolve()
# above is untouched (the quick-sim / AI path).

const FA_DAYS := 5

## Precompute each free agent's (stable) preference weights so the market reads consistently
## across days. Returns fa_id -> prefs.
static func market_prefs(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for fa in pool:
		out[fa.id] = fa_preferences(fa, rng)
	return out

## Best-offer score a free agent demands to sign on a given day: high early (only great fits go),
## falling so the rest settle as the window closes.
static func sign_threshold(day: int, total_days: int) -> float:
	var f := float(day - 1) / float(maxi(total_days - 1, 1))
	return lerpf(0.78, 0.45, f)

## Standing offers for one FA: every fitting AI team at its valuation, plus the player's bid (if
## placed and still affordable under the cap). Each entry: {team, salary, is_player}.
static func candidates(teams: Array, fa: PlayerData, player_team: TeamData, league_cap: int, player_offers: Dictionary) -> Array:
	var ask := EconomyManager.fair_salary(fa.overall(), league_cap)
	var out := []
	for t in teams:
		if t.id == player_team.id:
			continue
		var val := valuation(t, fa, league_cap)
		if val >= ask and team_pos_strength(t, fa.primary_pos) <= fa.overall() + 4:
			out.append({"team": t, "salary": val, "is_player": false})
	if player_offers.has(fa.id):
		var sal := int(player_offers[fa.id]["salary"])
		if sal >= int(round(float(ask) * 0.6)) and cap_room(player_team, league_cap) >= sal and team_pos_strength(player_team, fa.primary_pos) <= fa.overall() + 4:
			out.append({"team": player_team, "salary": sal, "is_player": true})
	return out

## Run one day of the market. Mutates pool + rosters + signings; returns the fa_ids that signed.
static func resolve_day(teams: Array, pool: Array, player_team: TeamData, league_cap: int, player_offers: Dictionary, prefs_by_id: Dictionary, rng: RandomNumberGenerator, day: int, total_days: int, signings: Array) -> Array:
	var signed := []
	var fas := pool.duplicate()
	fas.sort_custom(func(a, b): return a.overall() > b.overall())
	var thresh := sign_threshold(day, total_days)
	var force: bool = day >= total_days
	for fa in fas:
		var cands := candidates(teams, fa, player_team, league_cap, player_offers)
		if cands.is_empty():
			continue
		var prefs: Dictionary = prefs_by_id.get(fa.id, fa_preferences(fa, rng))
		var best: Dictionary = cands[0]
		var best_s := -1.0
		for c in cands:
			var s := offer_score(fa, prefs, c["team"], int(c["salary"]), league_cap)
			if s > best_s:
				best_s = s
				best = c
		if force or best_s >= thresh:
			_sign(best["team"], fa, int(best["salary"]), rng, pool, signings, bool(best.get("is_player", false)))
			signed.append(fa.id)
	return signed

static func _sign(team: TeamData, fa: PlayerData, salary: int, rng: RandomNumberGenerator, pool: Array, signings: Array, is_player: bool) -> void:
	fa.salary = salary
	fa.years_left = rng.randi_range(MIN_YEARS, MAX_YEARS)
	if team.roster.size() >= 12:
		var worst_i := 0
		for i in team.roster.size():
			if team.roster[i].overall() < team.roster[worst_i].overall():
				worst_i = i
		var cut: PlayerData = team.roster[worst_i]
		team.roster.remove_at(worst_i)
		cut.salary = 0
		pool.append(cut)
	team.roster.append(fa)
	pool.erase(fa)
	signings.append({
		"fa": fa.full_name(), "ovr": fa.overall(), "pos": fa.primary_pos,
		"team": team.name, "salary": salary, "you": is_player,
	})
