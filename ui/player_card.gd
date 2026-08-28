class_name PlayerCard
extends Control
## A reusable player detail overlay: identity, OVR at every position, all ten attribute bars,
## and contract. The data is produced by the pure static `card_model()` so the gate can verify
## it headlessly; the Control only renders that model. M12/M13 will add a `prospect_model()`
## sibling that feeds scouted ranges into the same layout.

signal closed

## Pure view-model — everything the card displays, as plain data. Gate-asserted.
static func card_model(p: PlayerData) -> Dictionary:
	var pos_ovr := {}
	for pos in PlayerData.POSITIONS:
		pos_ovr[pos] = p.overall_for(pos)
	var attrs := []
	for k in PlayerData.ATTRS:
		attrs.append({"key": k, "name": PlayerData.ATTR_NAMES.get(k, k), "val": p.get_attr(k)})
	return {
		"name": p.full_name(),
		"age": p.age,
		"height_cm": p.height_cm,
		"height_label": UITheme.height_label(p.height_cm),
		"pos": p.primary_pos,
		"archetype": p.archetype,
		"ovr": p.overall(),
		"pos_ovr": pos_ovr,
		"attrs": attrs,                       # 10, in PlayerData.ATTRS order
		"salary": p.salary,
		"salary_label": UITheme.moneyf(p.salary),
		"years_left": p.years_left,
		"morale": p.morale,
		"upside": upside_band(p),             # coarse — the hidden ceiling stays hidden (§4.1)
	}

## Coarse upside tier from (potential - current OVR). Never exposes the raw potential int.
static func upside_band(p: PlayerData) -> String:
	var gap := p.potential - p.overall()
	if p.age >= 30 or gap <= 1:
		return "Proven"
	if gap >= 12:
		return "Elite"
	if gap >= 7:
		return "High"
	if gap >= 3:
		return "Moderate"
	return "Low"

# --- render -----------------------------------------------------------------

## Builds the backdrop + centered card and returns the inner VBox to fill.
func _scaffold(min_w: float) -> VBoxContainer:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.62)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := UITheme.styled_panel(UITheme.PANEL, 12, 24)
	card.custom_minimum_size = Vector2(min_w, 0)
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	card.add_child(col)
	return col

func _title_row(col: VBoxContainer, title: String) -> void:
	var row := HBoxContainer.new()
	var name_lbl := UITheme.cell(title, UITheme.INK, 30)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.pressed.connect(_close)
	row.add_child(close)
	col.add_child(row)

func show_player(p: PlayerData) -> void:
	var m := card_model(p)
	var col := _scaffold(620)
	_title_row(col, m["name"])

	# Identity sub-line.
	col.add_child(UITheme.cell("Age %d   ·   %s   ·   %s   ·   %s" % [m["age"], m["height_label"], m["pos"], m["archetype"]], UITheme.MUTED, 17))

	# Position OVR chips.
	var ovr_row := HBoxContainer.new()
	ovr_row.add_theme_constant_override("separation", 8)
	for pos in PlayerData.POSITIONS:
		ovr_row.add_child(_ovr_chip(pos, int(m["pos_ovr"][pos]), pos == m["pos"]))
	col.add_child(ovr_row)

	# Contract / upside line.
	col.add_child(UITheme.cell("Contract  %s · %d yr     ·     Upside  %s     ·     Morale  %d" % [m["salary_label"], m["years_left"], m["upside"], m["morale"]], UITheme.DIM, 16))

	col.add_child(HSeparator.new())

	# Ten attribute bars, two columns.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 9)
	for a in m["attrs"]:
		grid.add_child(_attr_row(a["name"], int(a["val"])))
	col.add_child(grid)

func _ovr_chip(pos: String, val: int, primary: bool) -> Control:
	var fill := UITheme.PANEL_HI if not primary else UITheme.GOLD
	var panel := UITheme.styled_panel(fill, 6, 10)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var pos_col := UITheme.FAINT if not primary else Color("3a2f12")
	var val_col := UITheme.ovr_color(val) if not primary else Color("3a2f12")
	var pl := UITheme.cell(pos, pos_col, 12)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var vl := UITheme.cell("%d" % val, val_col, 22)
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(pl)
	v.add_child(vl)
	panel.add_child(v)
	return panel

func _attr_row(attr_name: String, val: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var nl := UITheme.cell(attr_name, UITheme.DIM, 15)
	nl.custom_minimum_size = Vector2(140, 0)
	row.add_child(nl)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 99
	bar.value = val
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(150, 14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.ovr_color(val)
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = UITheme.BG
	bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	row.add_child(bar)
	var vl := UITheme.cell("%d" % val, UITheme.ovr_color(val), 15)
	vl.custom_minimum_size = Vector2(26, 0)
	row.add_child(vl)
	return row

# --- draft prospect (M12): the scouted view — estimates + ranges, not exact truth ----------

## Pure: the prospect's public scouting picture. Ranges tighten toward the truth as you scout.
static func prospect_model(pr: DraftProspect) -> Dictionary:
	var p: PlayerData = pr.player
	var attrs := []
	for k in PlayerData.ATTRS:
		var band: Array = pr.attr_range(k)
		attrs.append({"key": k, "name": PlayerData.ATTR_NAMES.get(k, k), "lo": int(band[0]), "hi": int(band[1]), "est": pr.estimate(k)})
	return {
		"name": p.full_name(), "age": p.age,
		"height_label": UITheme.height_label(p.height_cm),
		"pos": p.primary_pos, "archetype": p.archetype,
		"scouted_ovr": pr.scouted_ovr(), "range": pr.projected_range, "stock": pr.stock,
		"confidence": int(round((1.0 - pr.uncertainty) * 100.0)),
		"attrs": attrs,
	}

func show_prospect(pr: DraftProspect) -> void:
	var m := prospect_model(pr)
	var col := _scaffold(620)
	_title_row(col, m["name"])
	col.add_child(UITheme.cell("Age %d   ·   %s   ·   %s   ·   %s" % [m["age"], m["height_label"], m["pos"], m["archetype"]], UITheme.MUTED, 17))
	col.add_child(UITheme.cell("Projected: %s     ·     Scouted OVR ~%d     ·     Scouting %d%%" % [m["range"], m["scouted_ovr"], m["confidence"]], UITheme.DIM, 16))
	col.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 9)
	for a in m["attrs"]:
		grid.add_child(_prospect_row(a))
	col.add_child(grid)

func _prospect_row(a: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var nl := UITheme.cell(a["name"], UITheme.DIM, 15)
	nl.custom_minimum_size = Vector2(140, 0)
	row.add_child(nl)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 99
	bar.value = a["est"]
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(150, 14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.ovr_color(a["est"])
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = UITheme.BG
	bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	row.add_child(bar)
	var txt := "%d–%d" % [a["lo"], a["hi"]] if a["lo"] != a["hi"] else "%d" % a["est"]
	var vl := UITheme.cell(txt, UITheme.MUTED, 14)
	vl.custom_minimum_size = Vector2(56, 0)
	row.add_child(vl)
	return row

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
