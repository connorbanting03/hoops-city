extends Control
## Game Day (GDD §4.2): watch your team play a full game as a live play-by-play feed, then reveal
## the box score. The game is simulated once with logging on its OWN rng (so watching never touches
## the franchise seed), then the event log is streamed line-by-line. The cozy "it's not a
## spreadsheet" moment. Pick / re-roll the opponent; skip to the result any time.

const STEP := 0.18   # seconds between plays

var _home: TeamData
var _away: TeamData
var _result: GameResult
var _feed: Array = []
var _idx: int = 0
var _rng := RandomNumberGenerator.new()
var _timer: Timer
var _franchise: bool = false   # true = this is a real scheduled franchise game (committed to standings)

var _score_lbl: Label
var _feed_box: VBoxContainer
var _scroll: ScrollContainer
var _actions: HBoxContainer

func setup(ctx: Dictionary = {}) -> void:
	if not is_inside_tree():
		return
	if bool(ctx.get("franchise", false)):
		_franchise = true
		_begin_franchise_game()
	else:
		_franchise = false
		_tip_off(int(ctx.get("opp_id", -1)))

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rng.randomize()
	_timer = Timer.new()
	_timer.wait_time = STEP
	_timer.timeout.connect(_reveal_next)
	add_child(_timer)
	_build()
	if _result == null:
		_tip_off(-1)

func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 8)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)

	_score_lbl = UITheme.cell("", UITheme.INK, 30)
	vb.add_child(_score_lbl)

	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	vb.add_child(_actions)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_scroll)
	_feed_box = VBoxContainer.new()
	_feed_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feed_box.add_theme_constant_override("separation", 3)
	_scroll.add_child(_feed_box)

func _tip_off(opp_id: int) -> void:
	# Exhibition: the player always hosts a one-off game on this screen's OWN rng (never the
	# franchise seed), so re-rolling opponents here can't disturb the season.
	if GameState.league == null:
		return
	_home = GameState.league.player_team()
	_away = _pick_opponent(opp_id)
	_result = GameSimulator.simulate_game(_home, _away, _rng, {"log_events": true})
	_begin_from_result()

## Franchise mode: play the player's next scheduled game. GameState sims it on the FRANCHISE rng and
## commits it to the standings; we just replay the log. The player may be home OR away, so the teams
## come off the result, not from player_team().
func _begin_franchise_game() -> void:
	if GameState.league == null:
		return
	var r := GameState.take_player_game(true)
	if r == null:
		EventBus.screen_requested.emit("hub", {})   # nothing left to play — back to the season hub
		return
	_result = r
	_home = GameState.league.get_team(r.home_team_id)
	_away = GameState.league.get_team(r.away_team_id)
	_begin_from_result()

## Stream the already-simulated _result as a live play-by-play feed.
func _begin_from_result() -> void:
	_feed = PlayByPlay.feed(_result)
	_idx = 0
	if _feed_box != null:
		for c in _feed_box.get_children():
			c.queue_free()
	_update_score(0, 0)
	_rebuild_actions(false)
	if _feed_box != null:
		_feed_box.add_child(UITheme.cell("Tip-off! %s host the %s." % [_home.name, _away.name], UITheme.FAINT, 15))
	if _timer != null and DisplayServer.get_name() != "headless":
		_timer.start()

func _pick_opponent(opp_id: int) -> TeamData:
	if opp_id > 0:
		var t := GameState.league.get_team(opp_id)
		if t != null and t.id != _home.id:
			return t
	var others := []
	for t in GameState.league.teams:
		if t.id != _home.id:
			others.append(t)
	return others[_rng.randi() % others.size()]

func _reveal_next() -> void:
	if _idx >= _feed.size():
		_finish()
		return
	var line: Dictionary = _feed[_idx]
	_idx += 1
	_update_score(int(line["home"]), int(line["away"]))
	var col := UITheme.MUTED
	if line["scored"]:
		col = UITheme.GOLD if line["home_play"] else UITheme.DIM
	var prefix := "%2d–%-2d" % [int(line["home"]), int(line["away"])]
	_feed_box.add_child(UITheme.cell("%s   %s" % [prefix, line["text"]], col, 15))
	_scroll.set_deferred("scroll_vertical", 1 << 30)
	if _idx >= _feed.size():
		_finish()

func _finish() -> void:
	if _timer != null:
		_timer.stop()
	_update_score(_result.home_score, _result.away_score)
	_rebuild_actions(true)

func _skip() -> void:
	if _timer != null:
		_timer.stop()
	while _idx < _feed.size():
		var line: Dictionary = _feed[_idx]
		_idx += 1
		var col := UITheme.MUTED
		if line["scored"]:
			col = UITheme.GOLD if line["home_play"] else UITheme.DIM
		_feed_box.add_child(UITheme.cell("%2d–%-2d   %s" % [int(line["home"]), int(line["away"]), line["text"]], col, 15))
	_scroll.set_deferred("scroll_vertical", 1 << 30)
	_finish()

func _rebuild_actions(done: bool) -> void:
	for c in _actions.get_children():
		c.queue_free()
	if done:
		_actions.add_child(_btn("Box score", func():
			var bs := BoxScore.new()
			add_child(bs)
			bs.show_result(_result)
		))
		if _franchise:
			_actions.add_child(_btn("Back to season →", func(): EventBus.screen_requested.emit("hub", {})))
		else:
			_actions.add_child(_btn("Watch another", func(): _tip_off(-1)))
	else:
		_actions.add_child(_btn("Skip to result", _skip))

func _update_score(h: int, a: int) -> void:
	if _score_lbl != null and _home != null:
		_score_lbl.text = "%s %d   —   %d %s" % [_home.abbrev, h, a, _away.abbrev]

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b
