class_name SeasonManager
extends RefCounted
## Turns a league of rosters into a season (GDD §4.3): a balanced 35-game schedule (every
## team plays the other 7 five times), standings with tiebreakers, and a top-4 playoff
## bracket — BO5 semis, BO7 final. Pure data + RNG; a whole season is milliseconds.

const GAMES_VS_EACH := 5
const SCHEDULE_GAMES := 35   # 7 opponents * 5

## One round-robin laid out by the circle method: n-1 rounds, every team plays exactly once per
## round (n/2 games per round), every pair exactly once across the rounds. The base the full
## schedule repeats. Returns Array[round]; each round is Array of {a, b} team-INDEX pairs (a < b).
static func _round_robin_rounds(teams: Array) -> Array:
	var n := teams.size()
	@warning_ignore("integer_division")
	var half := n / 2
	var idx: Array[int] = []
	for i in n:
		idx.append(i)
	var rounds := []
	for _r in (n - 1):
		var pairs := []
		for i in half:
			var a: int = idx[i]
			var b: int = idx[n - 1 - i]
			pairs.append({"a": mini(a, b), "b": maxi(a, b)})
		rounds.append(pairs)
		# Circle method: pin idx[0], rotate the rest one step.
		var last: int = idx[n - 1]
		for i in range(n - 1, 1, -1):
			idx[i] = idx[i - 1]
		idx[1] = last
	return rounds

## A balanced 35-game season laid out as matchday "rounds" of n/2 games each — every team plays once
## per round — so the season advances matchday-by-matchday with all teams level on games played (GDD
## §4.3). The base round-robin repeats GAMES_VS_EACH times (each pair meets 5 times); across those
## meetings the designated host plays 3 home and the other 2, so each team's home total stays 17-18.
## The set of games (and home/away split per pair) is identical to a pair-grouped schedule — only the
## ORDER is interleaved by round.
static func build_schedule(teams: Array) -> Array:
	var games := []
	var base_rounds := _round_robin_rounds(teams)
	for cycle in GAMES_VS_EACH:
		for rnd in base_rounds:
			for pair in rnd:
				var ai: int = pair["a"]
				var bi: int = pair["b"]
				var ti: TeamData = teams[ai]
				var tj: TeamData = teams[bi]
				var host3: TeamData = ti if (ai + bi) % 2 == 0 else tj
				var host2: TeamData = tj if host3 == ti else ti
				if cycle < 3:
					games.append({"home": host3.id, "away": host2.id})
				else:
					games.append({"home": host2.id, "away": host3.id})
	return games

## Reset every team's record and an empty point-diff map — the state simulate_regular_season (and
## the played, game-by-game franchise season in GameState) accumulate into.
static func reset_standings(league: LeagueData) -> Dictionary:
	var pdiff := {}
	for t in league.teams:
		t.wins = 0
		t.losses = 0
		pdiff[t.id] = 0
	return pdiff

## Simulate ONE scheduled game ({home, away} team-ids), apply the result to the teams' W/L and the
## pdiff map, and return the GameResult. The atomic unit a season is built from — whether all at
## once (simulate_regular_season) or one game at a time (GameState's played season). `opts` is
## passed through to the simulator (e.g. {"log_events": true} to capture a play-by-play); logging
## never touches the RNG, so a watched game and a simmed one are bit-identical for the same seed.
static func apply_game(league: LeagueData, g: Dictionary, pdiff: Dictionary, rng: RandomNumberGenerator, opts: Dictionary = {}) -> GameResult:
	var home := league.get_team(g["home"])
	var away := league.get_team(g["away"])
	var r := GameSimulator.simulate_game(home, away, rng, opts)
	if r.winner_id == home.id:
		home.wins += 1
		away.losses += 1
	else:
		away.wins += 1
		home.losses += 1
	pdiff[home.id] += r.home_score - r.away_score
	pdiff[away.id] += r.away_score - r.home_score
	return r

static func simulate_regular_season(league: LeagueData, rng: RandomNumberGenerator) -> Dictionary:
	var pdiff := reset_standings(league)
	var games: Array[GameResult] = []   # kept in schedule order for the Season Center (M11)
	for g in build_schedule(league.teams):
		games.append(apply_game(league, g, pdiff, rng))
	return {"pdiff": pdiff, "games": games}

## Sorted best-to-worst. Tiebreak: point differential. (Head-to-head as a first tiebreak
## is a later refinement; integer point-diff ties are rare.)
static func standings(league: LeagueData, pdiff: Dictionary) -> Array:
	var arr := league.teams.duplicate()
	arr.sort_custom(func(a, b):
		if a.wins != b.wins:
			return a.wins > b.wins
		return int(pdiff.get(a.id, 0)) > int(pdiff.get(b.id, 0))
	)
	return arr

## Best-of series; the higher seed hosts the odd-numbered games. Returns {winner, games} so the
## playoff bracket can show each game's score and box (M11).
static func simulate_series_detailed(higher, lower, best_of: int, rng: RandomNumberGenerator) -> Dictionary:
	@warning_ignore("integer_division")
	var need := best_of / 2 + 1
	var hw := 0
	var lw := 0
	var game := 0
	var games: Array[GameResult] = []
	while hw < need and lw < need:
		game += 1
		var r: GameResult
		if game % 2 == 1:
			r = GameSimulator.simulate_game(higher, lower, rng)
		else:
			r = GameSimulator.simulate_game(lower, higher, rng)
		if r.winner_id == higher.id:
			hw += 1
		else:
			lw += 1
		games.append(r)
	return {"winner": higher if hw > lw else lower, "games": games}

## Back-compat thin wrapper: just the winner.
static func simulate_series(higher, lower, best_of: int, rng: RandomNumberGenerator):
	return simulate_series_detailed(higher, lower, best_of, rng)["winner"]

static func simulate_playoffs(seeds: Array, rng: RandomNumberGenerator) -> Dictionary:
	var s1 := simulate_series_detailed(seeds[0], seeds[3], 5, rng)   # 1 vs 4
	var s2 := simulate_series_detailed(seeds[1], seeds[2], 5, rng)   # 2 vs 3
	var semi1 = s1["winner"]
	var semi2 = s2["winner"]
	var f_high = semi1 if seeds.find(semi1) < seeds.find(semi2) else semi2
	var f_low = semi2 if f_high == semi1 else semi1
	var sf := simulate_series_detailed(f_high, f_low, 7, rng)
	var champ = sf["winner"]
	var series := [
		{"round": "Semifinal", "high_id": seeds[0].id, "low_id": seeds[3].id, "winner_id": semi1.id, "games": s1["games"]},
		{"round": "Semifinal", "high_id": seeds[1].id, "low_id": seeds[2].id, "winner_id": semi2.id, "games": s2["games"]},
		{"round": "Final", "high_id": f_high.id, "low_id": f_low.id, "winner_id": champ.id, "games": sf["games"]},
	]
	return {"champion": champ, "finalists": [f_high, f_low], "semifinalists": seeds.duplicate(), "series": series}

static func simulate_full_season(league: LeagueData, rng: RandomNumberGenerator) -> Dictionary:
	var rs := simulate_regular_season(league, rng)
	var table := standings(league, rs["pdiff"])
	var po := simulate_playoffs(table.slice(0, 4), rng)
	return {"standings": table, "champion": po["champion"], "playoffs": po, "pdiff": rs["pdiff"], "games": rs["games"]}
