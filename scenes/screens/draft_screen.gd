extends Control
## Draft night (GDD §4.5): the lottery has set your slot, a rookie class sits on the board with
## hidden true ratings, and you're on the clock. Scout to narrow a prospect's ranges (it spends
## the cash you'd otherwise pour into the city — a real three-way pull), then pick. AI teams take
## the best stock available. Drives the GameState interactive-draft API; reads its state.

var _root: VBoxContainer

func setup(_ctx: Dictionary = {}) -> void:
	if is_inside_tree() and _root != null:
		_refresh()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 14)
	margin.add_child(_root)
	_refresh()

func _refresh() -> void:
	if _root == null:
		return
	_clear(_root)
	if not GameState.draft_active:
		_root.add_child(UITheme.cell("No draft in progress.", UITheme.INK, 22))
		_root.add_child(UITheme.cell("Finish the season, then \"Continue to off-season\" from the Hub to open the draft.", UITheme.MUTED, 16))
		return

	var you := GameState.league.player_team()
	_root.add_child(UITheme.cell("DRAFT %d" % GameState.current_year, UITheme.INK, 28))

	# Status / on-the-clock.
	if GameState.draft_complete():
		_root.add_child(UITheme.cell("Draft complete — %d picks made." % GameState.draft_board.size(), UITheme.DIM, 18))
	else:
		var clock_tid := GameState.draft_on_clock_team_id()
		var on := GameState.league.get_team(clock_tid)
		if GameState.draft_is_player_turn():
			_root.add_child(UITheme.cell("🟢 YOU'RE ON THE CLOCK — Round %d, pick %d of %d" % [GameState.draft_round(), GameState.draft_pick_index + 1, GameState.draft_total], UITheme.GOLD, 20))
		else:
			_root.add_child(UITheme.cell("Round %d · Pick %d of %d · On the clock: %s" % [GameState.draft_round(), GameState.draft_pick_index + 1, GameState.draft_total, on.name if on else "?"], UITheme.MUTED, 17))

	_root.add_child(UITheme.cell("Your slots: %s        ·        Scouting budget: %s" % [_slots_text(), UITheme.moneyf(you.cash)], UITheme.DIM, 15))

	# Your picks so far.
	var mine := []
	for e in GameState.draft_board:
		if int(e["team_id"]) == you.id:
			mine.append("%s (%s)" % [e["name"], e["pos"]])
	if not mine.is_empty():
		_root.add_child(UITheme.cell("Your picks: %s" % ", ".join(mine), UITheme.GOLD, 15))

	# Actions.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	if GameState.draft_complete():
		actions.add_child(_btn("Play free agency →", _on_play_fa))
		actions.add_child(_btn("Sim free agency & finish", _on_sim_finish))
	else:
		if GameState.draft_is_player_turn():
			actions.add_child(_btn("Auto-pick best available", _on_autopick))
		actions.add_child(_btn("Sim rest of draft", _on_sim_rest))
	_root.add_child(actions)
	_root.add_child(HSeparator.new())

	if not GameState.draft_complete():
		_build_board(you)

func _build_board(you: TeamData) -> void:
	var scout_cost := DraftManager.full_scout_cost(GameState.league.league_cap)
	_root.add_child(UITheme.header("ON THE BOARD"))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	for h in ["PROJECTED", "~OVR", "PROSPECT", "POS / ARCHETYPE", "", ""]:
		grid.add_child(UITheme.header(h))

	var sorted := GameState.draft_available.duplicate()
	sorted.sort_custom(func(a, b): return a.stock > b.stock)
	var my_turn := GameState.draft_is_player_turn()
	for pr in sorted:
		grid.add_child(UITheme.cell(pr.projected_range, UITheme.MUTED, 15))
		grid.add_child(UITheme.cell("~%d" % pr.scouted_ovr(), UITheme.ovr_color(pr.scouted_ovr()), 16))
		var nb := Button.new()
		nb.text = pr.player.full_name()
		nb.flat = true
		nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nb.add_theme_color_override("font_color", UITheme.LINK)
		nb.add_theme_font_size_override("font_size", 16)
		nb.pressed.connect(_open_prospect.bind(pr))
		grid.add_child(nb)
		grid.add_child(UITheme.cell("%s · %s" % [pr.player.primary_pos, pr.player.archetype], UITheme.DIM, 15))
		# Scout button.
		var sb := Button.new()
		var conf := int(round((1.0 - pr.uncertainty) * 100.0))
		sb.text = "Scouted ✓" if pr.uncertainty <= 0.001 else "Scout %s (%d%%)" % [UITheme.moneyf(scout_cost), conf]
		sb.disabled = pr.uncertainty <= 0.001 or you.cash <= 0
		sb.pressed.connect(_on_scout.bind(pr))
		grid.add_child(sb)
		# Draft button (only your turn).
		var db := Button.new()
		db.text = "DRAFT"
		db.disabled = not my_turn
		db.pressed.connect(_on_draft.bind(pr))
		grid.add_child(db)
	_root.add_child(grid)

# --- actions ----------------------------------------------------------------

func _on_scout(pr: DraftProspect) -> void:
	GameState.scout_prospect(pr)
	EventBus.world_changed.emit()
	_refresh()

func _on_draft(pr: DraftProspect) -> void:
	GameState.draft_pick(pr)
	EventBus.world_changed.emit()
	_refresh()

func _on_autopick() -> void:
	GameState.draft_autopick()
	EventBus.world_changed.emit()
	_refresh()

func _on_sim_rest() -> void:
	GameState.draft_sim_rest()
	_refresh()

func _on_play_fa() -> void:
	GameState.enter_free_agency()
	EventBus.world_changed.emit()
	EventBus.screen_requested.emit("fa", {})

func _on_sim_finish() -> void:
	GameState.finish_offseason()
	EventBus.world_changed.emit()
	EventBus.screen_requested.emit("hub", {})

func _open_prospect(pr: DraftProspect) -> void:
	var card := PlayerCard.new()
	add_child(card)
	card.show_prospect(pr)

# --- helpers ----------------------------------------------------------------

func _slots_text() -> String:
	var s := []
	for n in GameState.draft_player_slots():
		s.append("#%d" % n)
	return ", ".join(s)

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b

func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
