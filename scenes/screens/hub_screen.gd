extends Control
## The Season Hub: the phase-driven cockpit of the franchise (2K-MyLeague style). It renders only the
## actions valid for GameState.current_phase, funnelling the player through
## regular_season -> playoffs -> draft -> free_agency -> next season with no way to act out of order.
## Reads GameState; advancing mutates it and emits EventBus.world_changed so the shell's chrome
## resyncs. (Actions are rebuilt on every _refresh, since playing/simming a game can change the phase.)

var _sub: Label
var _stats: GridContainer
var _actions: HBoxContainer
var _grid: GridContainer
var _footer: Label

func setup(_ctx: Dictionary = {}) -> void:
	if is_inside_tree() and _stats != null:
		_refresh()

func _ready() -> void:
	if GameState.league == null:
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh()

func _cmp_standings(a, b) -> bool:
	if a.wins != b.wins:
		return a.wins > b.wins
	return a.team_ovr() > b.team_ovr()

func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	margin.add_child(vb)

	_sub = UITheme.cell("", UITheme.MUTED, 20)
	vb.add_child(_sub)

	_stats = GridContainer.new()
	_stats.columns = 6
	_stats.add_theme_constant_override("h_separation", 12)
	vb.add_child(_stats)

	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	vb.add_child(_actions)

	vb.add_child(UITheme.header("STANDINGS"))

	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 26)
	_grid.add_theme_constant_override("v_separation", 7)
	vb.add_child(_grid)

	_footer = UITheme.cell("", UITheme.MUTED, 16)
	vb.add_child(_footer)

func _refresh() -> void:
	if _stats == null:
		return
	var lg: LeagueData = GameState.league
	var you := lg.player_team()
	var ranked := lg.teams.duplicate()
	ranked.sort_custom(_cmp_standings)
	var your_rank := 1
	for i in ranked.size():
		if ranked[i].id == you.id:
			your_rank = i + 1

	_sub.text = _headline(you)
	_build_stats(you, your_rank)
	_build_actions()
	_build_standings(ranked, lg)
	_footer.text = _footer_text()

func _headline(you: TeamData) -> String:
	if GameState.current_phase == "regular_season":
		var p := GameState.season_player_progress()
		var upcoming: int = mini(int(p["played"]) + 1, int(p["total"]))
		return "%s  —  Year %d  ·  Regular Season  ·  Game %d of %d" % [you.name, GameState.current_year, upcoming, int(p["total"])]
	return "%s  —  Year %d  ·  %s" % [you.name, GameState.current_year, String(GameState.current_phase).capitalize()]

func _build_stats(you: TeamData, your_rank: int) -> void:
	_clear(_stats)
	_stats.add_child(UITheme.stat_card("Record", "%d-%d" % [you.wins, you.losses]))
	_stats.add_child(UITheme.stat_card("Rank", "#%d of 8" % your_rank))
	_stats.add_child(UITheme.stat_card("Team OVR", "%.1f" % you.team_ovr(), UITheme.ovr_color(you.team_ovr())))
	_stats.add_child(UITheme.stat_card("Cash", UITheme.moneyf(you.cash)))
	_stats.add_child(UITheme.stat_card("City pop", UITheme.popf(GameState.city.population)))
	_stats.add_child(UITheme.stat_card("Market", "%.2f" % you.market_size))

## The whole gate lives here: only the current phase's progression buttons are offered.
func _build_actions() -> void:
	_clear(_actions)
	match GameState.current_phase:
		"regular_season":
			if GameState.next_player_game_index() >= 0:
				_actions.add_child(_button("▶ Play next game", _on_play_next))
				_actions.add_child(_button("Sim next game", _on_sim_next))
			_actions.add_child(_button("Sim to end of season", _on_sim_season))
		"playoffs":
			_actions.add_child(_button("Continue to off-season →", _on_continue_offseason))
			_actions.add_child(_button("View season", func(): EventBus.screen_requested.emit("season", {})))
		"draft":
			_actions.add_child(_button("▶ Go to the Draft", func(): EventBus.screen_requested.emit("draft", {})))
		"free_agency":
			_actions.add_child(_button("▶ Go to Free Agency", func(): EventBus.screen_requested.emit("fa", {})))
	_actions.add_child(_button("New game", _on_new_game))

func _build_standings(ranked: Array, lg: LeagueData) -> void:
	_clear(_grid)
	for h in ["#", "TEAM", "W-L", "OVR", "TITLES", ""]:
		_grid.add_child(UITheme.header(h))
	var place := 1
	for t in ranked:
		var col := UITheme.INK
		var tag := ""
		if t.id == lg.dynasty_team_id:
			tag = "dynasty"
		if t.is_player_team:
			tag = "you"
			col = UITheme.GOLD
		_grid.add_child(UITheme.cell("%d" % place, UITheme.FAINTER, 18))
		var name_btn := Button.new()
		name_btn.text = t.name
		name_btn.flat = true
		name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_btn.add_theme_color_override("font_color", col)
		name_btn.add_theme_font_size_override("font_size", 18)
		name_btn.pressed.connect(_open_roster.bind(t.id))
		_grid.add_child(name_btn)
		_grid.add_child(UITheme.cell("%d-%d" % [t.wins, t.losses], UITheme.DIM, 18))
		_grid.add_child(UITheme.cell("%.1f" % t.team_ovr(), UITheme.ovr_color(t.team_ovr()), 18))
		_grid.add_child(UITheme.cell("%d" % t.championships, UITheme.DIM, 18))
		_grid.add_child(UITheme.cell(tag, UITheme.MUTED, 14))
		place += 1

func _footer_text() -> String:
	match GameState.current_phase:
		"regular_season":
			return "Play or sim your way through the season.   ·   Click a team to view its roster."
		"playoffs":
			if not GameState.last_season.is_empty():
				return "Playoffs done — champion: %s   ·   MVP: %s.   Continue to the off-season." % [GameState.last_season.get("champion", "-"), GameState.last_season.get("mvp", "-")]
			return "The playoffs are in the books — continue to the off-season."
		"draft":
			return "You're on the clock. Head to the Draft to scout and make your picks."
		"free_agency":
			return "Free agency is open. Make your offers, then finish the off-season to start next year."
	return ""

# --- actions ----------------------------------------------------------------

func _on_play_next() -> void:
	EventBus.screen_requested.emit("game", {"franchise": true})

func _on_sim_next() -> void:
	GameState.sim_next_game()
	EventBus.world_changed.emit()
	_refresh()

func _on_sim_season() -> void:
	GameState.sim_rest_of_season()
	EventBus.world_changed.emit()
	_refresh()

func _on_continue_offseason() -> void:
	GameState.enter_offseason_draft()
	EventBus.world_changed.emit()
	EventBus.screen_requested.emit("draft", {})

func _on_new_game() -> void:
	GameState.new_game()
	EventBus.world_changed.emit()
	_refresh()

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b

func _open_roster(team_id: int) -> void:
	EventBus.screen_requested.emit("roster", {"team_id": team_id})

func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
