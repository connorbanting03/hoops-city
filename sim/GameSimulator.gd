class_name GameSimulator
extends RefCounted
## The heart (GDD §4.2): a pure function over data, no scene nodes. ~100 possessions per
## side, each resolved from attribute matchups + seeded RNG, yielding believable box scores.
## One game is milliseconds, so a season — or decades of league history — is cheap.

const POSSESSIONS := 100
const HCA := 0.015   # home-court edge on shot probability

static func simulate_game(home: TeamData, away: TeamData, rng: RandomNumberGenerator, opts: Dictionary = {}) -> GameResult:
	var r := GameResult.new()
	r.home_team_id = home.id
	r.away_team_id = away.id
	r.possessions = POSSESSIONS
	var log_events: bool = bool(opts.get("log_events", false))

	var hl := home.rotation(8)
	var al := away.rotation(8)
	_init_box(r, hl, home.id, true)
	_init_box(r, al, away.id, false)

	var hd := _team_def(hl)
	var ad := _team_def(al)
	var hu := _usage(hl)
	var au := _usage(al)
	var ho := _avg(hl, "rebounding")
	var ao := _avg(al, "rebounding")

	var home_edge := HCA + _form(rng)
	var away_edge := _form(rng)
	for i in POSSESSIONS:
		_possess(r, hl, hu, ho, ad, rng, home_edge, log_events)
		_possess(r, al, au, ao, hd, rng, away_edge, log_events)

	_finalize(r)
	return r

static func _form(rng: RandomNumberGenerator) -> float:
	# Per-game shooting form. Most nights a small swing; ~7% of nights a team runs hot or cold
	# (fat tails), so on any given night an underdog can steal one — no game is a foregone lock.
	if rng.randf() < 0.12:
		return rng.randfn(0.0, 0.13)
	return rng.randfn(0.0, 0.045)

# --- one possession ---------------------------------------------------------

static func _possess(r: GameResult, off: Array, use: Array, off_reb: float, dfn: Dictionary, rng: RandomNumberGenerator, edge: float, log_events: bool) -> void:
	var shooter = _wpick(off, use, rng)
	var sid: int = shooter.id

	# Turnover?
	var p_tov := clampf(0.135 - (float(shooter.get_attr("playmaking") + shooter.get_attr("iq")) - 100.0) / 700.0 + (dfn["perimeter"] - 50.0) / 700.0, 0.06, 0.22)
	if rng.randf() < p_tov:
		_add(r, sid, "tov")
		var steal_id := -1
		if rng.randf() < 0.55:
			steal_id = _pick_attr(dfn["lineup"], "perimeter_d", rng).id
			_add(r, steal_id, "stl")
		if log_events:
			r.events.append({"type": "tov", "pid": sid, "steal_pid": steal_id})
		return

	# Shot zone.
	var p_three := clampf(0.18 + float(shooter.get_attr("shooting") - shooter.get_attr("inside")) / 220.0 + (float(shooter.get_attr("shooting")) - 55.0) / 260.0, 0.02, 0.72)
	var is_three := rng.randf() < p_three

	# Shooting foul -> free throws (kept off the FG ledger so FG% stays clean).
	var p_foul := (0.06 if is_three else 0.12) + (float(shooter.get_attr("athleticism")) - 50.0) / 900.0
	if rng.randf() < p_foul:
		var nft := 3 if is_three else 2
		var ftp := _ft_pct(shooter)
		var ft_made := 0
		for k in nft:
			_add(r, sid, "fta")
			if rng.randf() < ftp:
				_add(r, sid, "ftm")
				_add(r, sid, "pts")
				ft_made += 1
		_add(r, _pick_attr(dfn["lineup"], "interior_d" if not is_three else "perimeter_d", rng).id, "pf")
		if log_events:
			r.events.append({"type": "ft", "pid": sid, "made": ft_made, "att": nft})
		return

	# Field goal attempt.
	_add(r, sid, "fga")
	if is_three:
		_add(r, sid, "tpa")
	var make_p: float
	if is_three:
		make_p = clampf(0.330 + float(shooter.get_attr("shooting") - dfn["perimeter"]) / 490.0 + edge, 0.20, 0.52)
	else:
		make_p = clampf(0.485 + float(shooter.get_attr("inside") - dfn["interior"]) / 440.0 + edge, 0.28, 0.76)

	if rng.randf() < make_p:
		var pts := 3 if is_three else 2
		_add(r, sid, "fgm")
		_add(r, sid, "pts", pts)
		if is_three:
			_add(r, sid, "tpm")
		var assist_id := -1
		if rng.randf() < 0.56:
			var a = _pick_attr_excl(off, "playmaking", sid, rng)
			if a != null:
				assist_id = a.id
				_add(r, a.id, "ast")
		var had_and1 := false
		var and1_made := false
		if not is_three and rng.randf() < 0.07:   # and-one
			had_and1 = true
			_add(r, sid, "fta")
			if rng.randf() < _ft_pct(shooter):
				_add(r, sid, "ftm")
				_add(r, sid, "pts")
				and1_made = true
		if log_events:
			r.events.append({"type": "fg3" if is_three else "fg2", "pid": sid, "assist_pid": assist_id})
			if had_and1:
				r.events.append({"type": "and1", "pid": sid, "made": and1_made})
		return

	# Miss -> maybe a block, then the rebound battle.
	var blk_id := -1
	if not is_three and rng.randf() < clampf((dfn["interior"] - 40.0) / 300.0, 0.02, 0.16):
		blk_id = _pick_attr(dfn["lineup"], "interior_d", rng).id
		_add(r, blk_id, "blk")
	if log_events and blk_id >= 0:
		r.events.append({"type": "blk", "pid": blk_id, "on_pid": sid})

	var p_oreb := clampf(0.54 * off_reb / (off_reb + dfn["reb"]), 0.12, 0.42)
	if rng.randf() < p_oreb:
		var ro = _pick_attr(off, "rebounding", rng)
		_add(r, ro.id, "oreb")
		_add(r, ro.id, "fga")   # immediate put-back
		var putback := false
		if rng.randf() < 0.5:
			_add(r, ro.id, "fgm")
			_add(r, ro.id, "pts", 2)
			putback = true
		else:
			_add(r, _pick_attr(dfn["lineup"], "rebounding", rng).id, "dreb")
		if log_events:
			r.events.append({"type": "oreb", "pid": ro.id, "putback": putback})
	else:
		_add(r, _pick_attr(dfn["lineup"], "rebounding", rng).id, "dreb")

# --- helpers ----------------------------------------------------------------

static func _init_box(r: GameResult, lineup: Array, team_id: int, is_home: bool) -> void:
	for p in lineup:
		var s := {}
		for k in GameResult.STAT_KEYS:
			s[k] = 0
		r.box[p.id] = s
		r.names[p.id] = p.full_name()
		r.team_of[p.id] = team_id
		if is_home:
			r.home_pids.append(p.id)
		else:
			r.away_pids.append(p.id)

static func _add(r: GameResult, pid: int, key: String, n: int = 1) -> void:
	r.box[pid][key] += n

static func _finalize(r: GameResult) -> void:
	for pid in r.home_pids:
		r.home_score += r.box[pid]["pts"]
	for pid in r.away_pids:
		r.away_score += r.box[pid]["pts"]
	if r.home_score >= r.away_score:
		r.winner_id = r.home_team_id
		r.loser_id = r.away_team_id
	else:
		r.winner_id = r.away_team_id
		r.loser_id = r.home_team_id
	# MVP: best game score, nudged toward the winning side.
	var best := -1.0e9
	for pid in r.box.keys():
		var gs := _gamescore(r.box[pid])
		if r.team_of[pid] == r.winner_id:
			gs += 3.0
		if gs > best:
			best = gs
			r.mvp_id = pid

static func _gamescore(s: Dictionary) -> float:
	return float(s["pts"]) + 0.4 * s["fgm"] - 0.7 * s["fga"] + 0.7 * (s["oreb"] + s["dreb"]) + float(s["ast"]) + 0.7 * (s["stl"] + s["blk"]) - float(s["tov"])

static func _ft_pct(p) -> float:
	return clampf(0.50 + float(p.get_attr("shooting")) / 300.0 + float(p.get_attr("iq")) / 600.0, 0.45, 0.92)

static func _team_def(lineup: Array) -> Dictionary:
	return {
		"interior": _avg(lineup, "interior_d"),
		"perimeter": _avg(lineup, "perimeter_d"),
		"reb": _avg(lineup, "rebounding"),
		"lineup": lineup,
	}

static func _avg(lineup: Array, key: String) -> float:
	var s := 0.0
	for p in lineup:
		s += float(p.get_attr(key))
	return s / float(lineup.size())

static func _usage(lineup: Array) -> Array:
	var w := []
	for p in lineup:
		var off: float = 0.42 * p.get_attr("inside") + 0.42 * p.get_attr("shooting") + 0.16 * p.get_attr("playmaking")
		w.append(pow(maxf(off - 32.0, 3.0), 1.6))
	return w

static func _wpick(arr: Array, weights: Array, rng: RandomNumberGenerator):
	var tot := 0.0
	for x in weights:
		tot += x
	var t := rng.randf() * tot
	for i in arr.size():
		t -= weights[i]
		if t <= 0.0:
			return arr[i]
	return arr[arr.size() - 1]

static func _pick_attr(lineup: Array, key: String, rng: RandomNumberGenerator):
	var w := []
	for p in lineup:
		w.append(maxf(float(p.get_attr(key)) - 25.0, 1.0))
	return _wpick(lineup, w, rng)

static func _pick_attr_excl(lineup: Array, key: String, exclude_id: int, rng: RandomNumberGenerator):
	var w := []
	var any := false
	for p in lineup:
		if p.id == exclude_id:
			w.append(0.0)
		else:
			w.append(maxf(float(p.get_attr(key)) - 25.0, 1.0))
			any = true
	if not any:
		return null
	return _wpick(lineup, w, rng)
