class_name EconomyManager
extends RefCounted
## The money model (GDD §6). Two ledgers: a league salary cap that everyone shares as a
## floor, and each team's cash. The clever bit is the EFFECTIVE budget:
##
##   Effective Budget = League Cap * (1 + Market_Factor + Success_Factor)
##
## Growing your city (Market) and winning (Success) literally raise how much roster you can
## afford — so the two halves of the flywheel feed each other. Market uses a softening curve
## (GDD §6.3) so a huge city helps a lot but never makes money meaningless.

# League cap curve.
const CAP_BASE := 120_000_000          # starting league cap
const CAP_GROWTH := 0.045              # +4.5% / year

# Market factor (saturating): 0 at the smallest market, approaching MARKET_SOFT for a metropolis.
const MIN_MARKET := 0.7
const MARKET_SCALE := 1.5
const MARKET_SOFT := 1.2

# Salaries as a share of the league cap.
const SAL_MIN_FRAC := 0.010           # roughly the minimum contract
const SAL_MAX_FRAC := 0.30            # a max contract

# Revenue tuning.
const ARENA_CAP := 18000.0
const TICKET_PRICE := 110.0
const CONCESSION_PP := 35.0
const FANBASE_PER_MARKET := 15000.0
const HOME_GAMES := 17.5
const PRIZE_PLAYOFFS := 8_000_000.0
const PRIZE_ROUND := 12_000_000.0
const PRIZE_TITLE := 30_000_000.0
const MEDIA_SHARE := 0.85   # league media/sponsorship ~ tracks spending power, so revenue funds payroll

static func league_cap_for_year(year: int, start_year: int = 2026) -> int:
	return int(round(CAP_BASE * pow(1.0 + CAP_GROWTH, float(year - start_year))))

static func market_factor(team) -> float:
	return MARKET_SOFT * (1.0 - exp(-maxf(team.market_size - MIN_MARKET, 0.0) / MARKET_SCALE))

## res = a per-team season result: { win_pct, made_playoffs, rounds_won, champion }.
static func success_factor(team, res: Dictionary) -> float:
	var reg := smoothstep(0.40, 0.80, float(res["win_pct"])) * 0.5
	var deep := 0.12 * float(res["rounds_won"])
	var ring := 0.20 if res["champion"] else 0.0
	var brand := 0.02 * float(mini(team.championships, 12))
	return clampf(reg + deep + ring + brand, 0.0, 1.1)

static func effective_budget(team, league_cap: int, res: Dictionary) -> int:
	return int(round(float(league_cap) * (1.0 + market_factor(team) + success_factor(team, res))))

static func fair_salary(ovr: int, league_cap: int) -> int:
	var min_s := float(league_cap) * SAL_MIN_FRAC
	var max_s := float(league_cap) * SAL_MAX_FRAC
	var share := pow(clampf((float(ovr) - 38.0) / 45.0, 0.0, 1.0), 1.9)
	return int(round((min_s + share * (max_s - min_s)) / 100000.0)) * 100000

static func assign_initial_salaries(league) -> void:
	for t in league.teams:
		for p in t.roster:
			p.salary = fair_salary(p.overall(), league.league_cap)

static func payroll(team) -> int:
	var total := 0
	for p in team.roster:
		total += p.salary
	return total

static func cap_room(team, league_cap: int, res: Dictionary) -> int:
	return effective_budget(team, league_cap, res) - payroll(team)

## Derive each team's season outcome from a SeasonManager.simulate_full_season() result.
static func derive_results(league, season: Dictionary) -> Dictionary:
	var table: Array = season["standings"]
	var champ_id: int = season["champion"].id
	var top4 := []
	for i in 4:
		top4.append(table[i].id)
	var finalist_ids := []
	for f in season["playoffs"]["finalists"]:
		finalist_ids.append(f.id)
	var out := {}
	for t in league.teams:
		var rounds_won := 0
		if t.id in finalist_ids:
			rounds_won = 1
		if t.id == champ_id:
			rounds_won = 2
		out[t.id] = {
			"win_pct": float(t.wins) / 35.0,
			"made_playoffs": t.id in top4,
			"rounds_won": rounds_won,
			"champion": t.id == champ_id,
		}
	return out

static func season_revenue(team, res: Dictionary, league, city_dividends: float = 0.0) -> Dictionary:
	var perf := 0.6 + float(res["win_pct"]) * 0.8
	var fanbase: float = team.market_size * FANBASE_PER_MARKET
	var attendance := minf(ARENA_CAP, fanbase * perf)
	var gate := attendance * TICKET_PRICE * HOME_GAMES
	var concessions := attendance * CONCESSION_PP * HOME_GAMES
	# Media / revenue-sharing scales with the same market+success the cap does, so a team's
	# revenue funds the payroll its cap permits (no structural debt).
	var sponsorship := float(effective_budget(team, league.league_cap, res)) * MEDIA_SHARE
	var prize := 0.0
	if res["made_playoffs"]:
		prize += PRIZE_PLAYOFFS
	prize += PRIZE_ROUND * float(res["rounds_won"])
	if res["champion"]:
		prize += PRIZE_TITLE
	var dividends := city_dividends   # passive income from city buildings (M6)
	return {
		"gate": gate, "concessions": concessions, "sponsorship": sponsorship,
		"prize": prize, "dividends": dividends,
		"total": gate + concessions + sponsorship + prize + dividends,
		"attendance": attendance,
	}

## Apply one season's cash flow (revenue - payroll) to every team's bank.
static func apply_season_economy(league, results: Dictionary) -> void:
	for t in league.teams:
		var rev := season_revenue(t, results[t.id], league)
		t.cash = maxi(0, t.cash + int(round(rev["total"] - float(payroll(t)))))
