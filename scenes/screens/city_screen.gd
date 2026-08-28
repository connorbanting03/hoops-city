extends Control
## City builder (GDD §5): the other half of the flywheel. Spend cash on housing, jobs, amenities,
## and civic landmarks; population trends toward capacity x attractiveness, and population drives
## market size, which raises your effective roster budget. The "Population -> Market -> Budget"
## chain is shown explicitly so the payoff to building is legible (§5.2). Year-round — build
## whenever you have cash. Reads GameState.city; spends via GameState.city_build / city_upgrade.

const TITLES := {"residential": "Residential", "commercial": "Commercial", "tourism": "Tourism", "entertainment": "Entertainment", "civic": "Civic"}

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
	_root.add_theme_constant_override("separation", 16)
	margin.add_child(_root)
	_refresh()

func _refresh() -> void:
	if _root == null or GameState.city == null:
		return
	_clear(_root)
	var city := GameState.city
	var you := GameState.league.player_team()
	var success := clampf(float(you.wins) / 35.0, 0.0, 1.0)

	_root.add_child(UITheme.cell(city.name, UITheme.INK, 28))

	# The legible flywheel chain (§5.2).
	var res := {"win_pct": success, "made_playoffs": false, "rounds_won": 0, "champion": false}
	var budget := EconomyManager.effective_budget(you, GameState.league.league_cap, res)
	var chain := UITheme.styled_panel(UITheme.PANEL, 10, 16)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 14)
	_chain_step(crow, "Population", UITheme.popf(city.population))
	_chain_arrow(crow)
	_chain_step(crow, "Market size", "%.2f" % CityManager.market_size(city))
	_chain_arrow(crow)
	_chain_step(crow, "Effective budget", UITheme.moneyf(budget), UITheme.GOLD)
	chain.add_child(crow)
	_root.add_child(chain)

	# Stat cards.
	var cap := CityManager.housing_capacity(city)
	var att := CityManager.attractiveness(city, success)
	var stats := GridContainer.new()
	stats.columns = 6
	stats.add_theme_constant_override("h_separation", 12)
	stats.add_theme_constant_override("v_separation", 12)
	stats.add_child(UITheme.stat_card("Population", UITheme.popf(city.population)))
	stats.add_child(UITheme.stat_card("Housing cap", UITheme.popf(cap)))
	stats.add_child(UITheme.stat_card("Attractiveness", "%d%%" % int(round(att * 100.0))))
	stats.add_child(UITheme.stat_card("Jobs", UITheme.popf(CityManager.jobs(city))))
	stats.add_child(UITheme.stat_card("Amenities", "%d" % int(CityManager.amenities(city))))
	stats.add_child(UITheme.stat_card("Civic", "%d" % int(CityManager.civic_points(city))))
	stats.add_child(UITheme.stat_card("Dividends/yr", UITheme.moneyf(CityManager.dividends(city, success))))
	stats.add_child(UITheme.stat_card("Cash to build", UITheme.moneyf(you.cash), UITheme.GOLD))
	_root.add_child(stats)
	_root.add_child(UITheme.cell("Population trends toward housing capacity × attractiveness — build homes AND make the city worth living in.", UITheme.FAINT, 13))

	_build_menu(you)
	_owned(city, you)

func _build_menu(you: TeamData) -> void:
	_root.add_child(UITheme.header("BUILD"))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	for h in ["BUILDING", "DISTRICT", "PROVIDES", "COST", ""]:
		grid.add_child(UITheme.header(h))
	for type in CityManager.CATALOG:
		var cost := CityManager.build_cost(GameState.city, type)
		grid.add_child(UITheme.cell(_pretty(type), UITheme.INK, 16))
		grid.add_child(UITheme.cell(TITLES.get(CityManager.category(type), CityManager.category(type)), UITheme.MUTED, 14))
		grid.add_child(UITheme.cell(_outputs_text(CityManager.type_outputs(type)), UITheme.DIM, 14))
		grid.add_child(UITheme.cell(UITheme.moneyf(cost), UITheme.MUTED, 15))
		var b := Button.new()
		b.text = "Build"
		b.disabled = you.cash < cost
		b.pressed.connect(_on_build.bind(type))
		grid.add_child(b)
	_root.add_child(grid)

func _owned(city: CityData, you: TeamData) -> void:
	if city.buildings.is_empty():
		return
	_root.add_child(UITheme.header("YOUR CITY"))
	# Group buildings by type; offer to upgrade the lowest-tier one of each.
	var by_type := {}
	for b in city.buildings:
		by_type.get_or_add(b.type, []).append(b)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	for h in ["BUILDING", "COUNT", "TOTAL OUTPUT", "UPGRADE", ""]:
		grid.add_child(UITheme.header(h))
	for type in by_type:
		var list: Array = by_type[type]
		grid.add_child(UITheme.cell(_pretty(type), UITheme.INK, 16))
		grid.add_child(UITheme.cell("×%d" % list.size(), UITheme.DIM, 15))
		grid.add_child(UITheme.cell(_outputs_text(_total_output(list)), UITheme.DIM, 14))
		var low: BuildingData = list[0]
		for b in list:
			if b.tier < low.tier:
				low = b
		var ucost := CityManager.upgrade_cost(low)
		grid.add_child(UITheme.cell("T%d → T%d  ·  %s" % [low.tier, low.tier + 1, UITheme.moneyf(ucost)], UITheme.MUTED, 14))
		var ub := Button.new()
		ub.text = "Upgrade"
		ub.disabled = you.cash < ucost
		ub.pressed.connect(_on_upgrade.bind(low))
		grid.add_child(ub)
	_root.add_child(grid)

# --- actions ----------------------------------------------------------------

func _on_build(type: String) -> void:
	if GameState.city_build(type):
		EventBus.world_changed.emit()
		_refresh()

func _on_upgrade(b: BuildingData) -> void:
	if GameState.city_upgrade(b):
		EventBus.world_changed.emit()
		_refresh()

# --- helpers ----------------------------------------------------------------

func _total_output(list: Array) -> Dictionary:
	var out := {}
	for b in list:
		for k in CityManager.building_outputs(b):
			out[k] = float(out.get(k, 0.0)) + float(CityManager.building_outputs(b)[k])
	return out

func _outputs_text(outs: Dictionary) -> String:
	var parts := []
	for k in outs:
		if k == "dividend":
			parts.append("+%s %s" % [UITheme.moneyf(outs[k]), CityManager.OUTPUT_LABELS[k]])
		else:
			parts.append("+%s %s" % [_numf(outs[k]), CityManager.OUTPUT_LABELS[k]])
	return ", ".join(parts) if not parts.is_empty() else "—"

func _numf(v) -> String:
	var f := float(v)
	if f >= 1000.0:
		return UITheme.popf(f)
	return "%d" % int(round(f))

func _pretty(type: String) -> String:
	return String(type).capitalize()

func _chain_step(row: HBoxContainer, label: String, value: String, value_col: Color = UITheme.INK) -> void:
	var v := VBoxContainer.new()
	v.add_child(UITheme.cell(label, UITheme.FAINT, 12))
	v.add_child(UITheme.cell(value, value_col, 22))
	row.add_child(v)

func _chain_arrow(row: HBoxContainer) -> void:
	var a := UITheme.cell("→", UITheme.FAINTER, 22)
	row.add_child(a)

func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
