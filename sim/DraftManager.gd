class_name DraftManager
extends RefCounted
## The draft (GDD §4.5): a fresh rookie class each year with hidden true ratings, scouting
## that spends money to narrow the uncertainty, and a LOTTERY so the worst team has the best
## odds at #1 but isn't guaranteed it — removing the incentive to tank.

const CLASS_SIZE := 16
const FULL_SCOUT_COST := 2_000_000.0                # base reference (~the cost at the starting cap)
const SCOUT_CAP_FRAC := 0.0167                       # a full scout costs ~1.67% of the league cap, so it scales with the economy
const LOTTERY_WEIGHTS := [40.0, 30.0, 20.0, 10.0]   # #1 odds for the bottom 4, worst team first

## What a full scout costs this year — a share of the league cap (rounded to $100k), so it stays
## meaningful as the cap inflates over the decades. ~$2.0M at the $120M starting cap.
static func full_scout_cost(league_cap: int) -> int:
	return int(round(float(league_cap) * SCOUT_CAP_FRAC / 100000.0)) * 100000

static func generate_class(rng: RandomNumberGenerator, year: int, size: int = CLASS_SIZE) -> Array[DraftProspect]:
	var out: Array[DraftProspect] = []
	for i in size:
		var p := PlayerGenerator.generate_player(rng, {"age": rng.randi_range(18, 22), "id": year * 1000 + i})
		var pr := DraftProspect.new()
		pr.player = p
		pr.uncertainty = 1.0
		var errs := {}
		for k in PlayerData.ATTRS:
			errs[k] = rng.randfn(0.0, 1.0)
		pr.errors = errs
		# Stock blends current ability and upside, plus public-consensus noise.
		pr.stock = clampi(int(round(0.4 * p.overall() + 0.6 * float(p.potential) + rng.randfn(0.0, 4.0))), 1, 99)
		pr.projected_range = _range_label(pr.stock)
		out.append(pr)
	return out

static func _range_label(stock: int) -> String:
	if stock >= 70:
		return "Lottery"
	if stock >= 62:
		return "Mid first"
	if stock >= 54:
		return "Late first"
	if stock >= 46:
		return "Second round"
	return "Undrafted fringe"

## Spend scouting dollars on one prospect: lowers its uncertainty toward 0. `full_cost` is the
## price of a complete scout (so `dollars == full_cost` fully reveals); defaults to the base.
static func scout(prospect: DraftProspect, dollars: float, full_cost: float = FULL_SCOUT_COST) -> void:
	prospect.uncertainty = clampf(prospect.uncertainty - dollars / full_cost, 0.0, 1.0)

## Draft order for all 8 teams. The bottom 4 enter a weighted lottery for picks 1-4; the
## playoff teams take picks 5-8 in reverse seeding. standings is best (0) to worst (last).
static func run_lottery(standings: Array, rng: RandomNumberGenerator) -> Array:
	var lottery_teams := [standings[7].id, standings[6].id, standings[5].id, standings[4].id]
	var order := _weighted_draw(lottery_teams, LOTTERY_WEIGHTS.duplicate(), rng)
	order.append(standings[3].id)
	order.append(standings[2].id)
	order.append(standings[1].id)
	order.append(standings[0].id)
	return order

static func _weighted_draw(items: Array, weights: Array, rng: RandomNumberGenerator) -> Array:
	var pool := items.duplicate()
	var w := weights.duplicate()
	var out := []
	while pool.size() > 0:
		var tot := 0.0
		for x in w:
			tot += x
		var t := rng.randf() * tot
		var idx := 0
		for i in pool.size():
			t -= w[i]
			if t <= 0.0:
				idx = i
				break
		out.append(pool[idx])
		pool.remove_at(idx)
		w.remove_at(idx)
	return out

## The AI's pick: the best available prospect by public stock (no RNG). Shared by the auto draft
## and the interactive draft so AI teams behave identically either way.
static func ai_pick(available: Array) -> DraftProspect:
	var best: DraftProspect = available[0]
	for pr in available:
		if pr.stock > best.stock:
			best = pr
	return best

## Commit one pick: remove the prospect from the board, add the rookie to the team, return the
## board entry. Used for both AI and player picks.
static func commit_pick(league, tid: int, pr: DraftProspect, available: Array, pick_num: int) -> Dictionary:
	available.erase(pr)
	var team = league.get_team(tid)
	team.roster.append(pr.player)
	return {
		"pick": pick_num, "team_id": tid, "team": team.name,
		"name": pr.player.full_name(), "pos": pr.player.primary_pos, "stock": pr.stock,
		"true_ovr": pr.player.overall(), "pot": pr.player.potential,
	}

## Run the whole draft automatically (worst-first order, best stock available). Returns a
## pick-by-pick board.
static func run_draft(league, order: Array, prospects: Array, _rng: RandomNumberGenerator, rounds: int = 2) -> Array:
	var available := prospects.duplicate()
	var results := []
	var pick_num := 1
	for r in rounds:
		for tid in order:
			if available.is_empty():
				break
			results.append(commit_pick(league, tid, ai_pick(available), available, pick_num))
			pick_num += 1
	return results
