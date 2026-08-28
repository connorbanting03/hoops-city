extends Control
## Free agency (GDD §4.4): a day-based bidding war. Each free agent shows his asking price; you
## place an offer (salary x years) bounded by your cap room, then advance the day and watch the
## market move. To land a target you have to out-appeal the field — and a small-market rebuild has
## to overpay to beat a contender's pull. Drives the GameState FA API; reads its state.

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
	if not GameState.fa_active:
		_root.add_child(UITheme.cell("Free agency isn't open.", UITheme.INK, 22))
		_root.add_child(UITheme.cell("Reach it by playing through the draft from the Hub.", UITheme.MUTED, 16))
		return

	var you := GameState.league.player_team()
	_root.add_child(UITheme.cell("FREE AGENCY %d" % GameState.current_year, UITheme.INK, 28))

	var complete := GameState.fa_complete()
	if complete:
		_root.add_child(UITheme.cell("The window has closed.", UITheme.DIM, 18))
	else:
		_root.add_child(UITheme.cell("Day %d of %d" % [GameState.fa_day, FreeAgencyManager.FA_DAYS], UITheme.GOLD, 20))
	_root.add_child(UITheme.cell("Cap room: %s     ·     Cash: %s     ·     Roster: %d" % [UITheme.moneyf(GameState.fa_cap_room()), UITheme.moneyf(you.cash), you.roster.size()], UITheme.DIM, 16))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	if complete:
		actions.add_child(_btn("Finish free agency →", _on_finish))
	else:
		actions.add_child(_btn("Advance day ▶", _on_advance_day))
		actions.add_child(_btn("Sim rest of window", _on_sim_rest))
		# Signed who you wanted? Skip the remaining days and move on.
		actions.add_child(_btn("Done — finish off-season →", _on_finish))
	_root.add_child(actions)

	_build_signings()
	_root.add_child(HSeparator.new())
	if not complete:
		_build_pool()

func _build_signings() -> void:
	if GameState.fa_signings.is_empty():
		return
	_root.add_child(UITheme.header("SIGNINGS"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var recent: Array = GameState.fa_signings.slice(maxi(0, GameState.fa_signings.size() - 10), GameState.fa_signings.size())
	for s in recent:
		var mine: bool = s.get("you", false)
		var txt := "%s (%s %d) → %s  ·  %s%s" % [s["fa"], s["pos"], s["ovr"], s["team"], UITheme.moneyf(s["salary"]), "   ⭐ YOU" if mine else ""]
		box.add_child(UITheme.cell(txt, UITheme.GOLD if mine else UITheme.MUTED, 15))
	_root.add_child(box)

func _build_pool() -> void:
	_root.add_child(UITheme.header("AVAILABLE FREE AGENTS"))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	for h in ["PLAYER", "POS", "AGE", "OVR", "ASKING", "YOUR OFFER", ""]:
		grid.add_child(UITheme.header(h))

	var sorted := GameState.fa_pool.duplicate()
	sorted.sort_custom(func(a, b): return a.overall() > b.overall())
	var cap := GameState.league.league_cap
	for fa in sorted:
		var nb := Button.new()
		nb.text = fa.full_name()
		nb.flat = true
		nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nb.add_theme_color_override("font_color", UITheme.LINK)
		nb.add_theme_font_size_override("font_size", 16)
		nb.pressed.connect(_open_card.bind(fa))
		grid.add_child(nb)
		grid.add_child(UITheme.cell(fa.primary_pos, UITheme.DIM, 15))
		grid.add_child(UITheme.cell("%d" % fa.age, UITheme.DIM, 15))
		grid.add_child(UITheme.cell("%d" % fa.overall(), UITheme.ovr_color(fa.overall()), 16))
		grid.add_child(UITheme.cell(UITheme.moneyf(EconomyManager.fair_salary(fa.overall(), cap)), UITheme.MUTED, 15))
		var off_txt := "—"
		if GameState.fa_offers.has(fa.id):
			off_txt = "%s · %dyr" % [UITheme.moneyf(GameState.fa_offers[fa.id]["salary"]), GameState.fa_offers[fa.id]["years"]]
		grid.add_child(UITheme.cell(off_txt, UITheme.GOLD if GameState.fa_offers.has(fa.id) else UITheme.FAINTER, 15))
		grid.add_child(_btn("Edit offer" if GameState.fa_offers.has(fa.id) else "Make offer", _open_offer.bind(fa)))
	_root.add_child(grid)

# --- actions ----------------------------------------------------------------

func _on_advance_day() -> void:
	GameState.fa_advance_day()
	EventBus.world_changed.emit()
	_refresh()

func _on_sim_rest() -> void:
	GameState.fa_sim_rest()
	EventBus.world_changed.emit()
	_refresh()

func _on_finish() -> void:
	GameState.finish_free_agency()
	EventBus.world_changed.emit()
	EventBus.screen_requested.emit("hub", {})

func _open_card(fa: PlayerData) -> void:
	var card := PlayerCard.new()
	add_child(card)
	card.show_player(fa)

# --- offer overlay ----------------------------------------------------------

func _open_offer(fa: PlayerData) -> void:
	var cap := GameState.league.league_cap
	var ask := EconomyManager.fair_salary(fa.overall(), cap)
	var cap_room: int = maxi(GameState.fa_cap_room(), 0)
	# If editing, factor the existing offer back into the budget you can move.
	var existing: int = int(GameState.fa_offers[fa.id]["salary"]) if GameState.fa_offers.has(fa.id) else 0
	var max_offer: int = maxi(cap_room + existing, 0)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.62)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: overlay.queue_free())
	overlay.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var card := UITheme.styled_panel(UITheme.PANEL, 12, 24)
	card.custom_minimum_size = Vector2(520, 0)
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)

	col.add_child(UITheme.cell("Offer to %s" % fa.full_name(), UITheme.INK, 24))
	col.add_child(UITheme.cell("%s · Age %d · OVR %d     ·     Asking ~%s" % [fa.primary_pos, fa.age, fa.overall(), UITheme.moneyf(ask)], UITheme.MUTED, 15))
	col.add_child(UITheme.cell("Your cap room: %s" % UITheme.moneyf(max_offer), UITheme.DIM, 15))

	var years := [3]   # mutable holder
	var salary_lbl := UITheme.cell("", UITheme.GOLD, 22)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = maxf(float(max_offer), float(ask))
	slider.step = 100000
	slider.value = float(clampi(existing if existing > 0 else mini(max_offer, ask), 0, max_offer))
	slider.custom_minimum_size = Vector2(440, 0)
	var update_lbl := func(): salary_lbl.text = "%s  ·  %d yr" % [UITheme.moneyf(slider.value), years[0]]
	slider.value_changed.connect(func(_v): update_lbl.call())
	col.add_child(salary_lbl)
	col.add_child(slider)

	var yr_row := HBoxContainer.new()
	yr_row.add_theme_constant_override("separation", 8)
	yr_row.add_child(UITheme.cell("Years:", UITheme.MUTED, 15))
	for y in [1, 2, 3, 4]:
		var yb := Button.new()
		yb.text = "%d" % y
		yb.pressed.connect(func(): years[0] = y; update_lbl.call())
		yr_row.add_child(yb)
	col.add_child(yr_row)
	update_lbl.call()

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	btns.add_child(_btn("Submit offer", func():
		GameState.fa_place_offer(fa, int(slider.value), years[0])
		overlay.queue_free()
		EventBus.world_changed.emit()
		_refresh()
	))
	if GameState.fa_offers.has(fa.id):
		btns.add_child(_btn("Withdraw", func():
			GameState.fa_cancel_offer(fa)
			overlay.queue_free()
			_refresh()
		))
	btns.add_child(_btn("Cancel", func(): overlay.queue_free()))
	col.add_child(btns)

# --- helpers ----------------------------------------------------------------

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b

func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
