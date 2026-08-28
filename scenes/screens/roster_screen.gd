class_name RosterScreen
extends Control
## Roster screen: inspect ANY team's roster as a sortable table, click a player for the full
## card. Pure `roster_rows()` builds the table data so the gate can verify sorting headlessly;
## the Control only renders it and opens the PlayerCard overlay. Reads GameState; owns nothing.

const COLS := [
	{"key": "name", "label": "PLAYER", "w": 210, "kind": "name"},
	{"key": "pos", "label": "POS", "w": 52, "kind": "text"},
	{"key": "age", "label": "AGE", "w": 52, "kind": "num"},
	{"key": "ovr", "label": "OVR", "w": 58, "kind": "ovr"},
	{"key": "inside", "label": "IN", "w": 46, "kind": "attr"},
	{"key": "shooting", "label": "SH", "w": 46, "kind": "attr"},
	{"key": "playmaking", "label": "PM", "w": 46, "kind": "attr"},
	{"key": "perimeter_d", "label": "PD", "w": 46, "kind": "attr"},
	{"key": "interior_d", "label": "ID", "w": 46, "kind": "attr"},
	{"key": "rebounding", "label": "RB", "w": 46, "kind": "attr"},
	{"key": "athleticism", "label": "AT", "w": 46, "kind": "attr"},
	{"key": "salary", "label": "SALARY", "w": 96, "kind": "money"},
]

var _team: TeamData
var _sort_key: String = "ovr"
var _sort_desc: bool = true
var _header: VBoxContainer
var _table: GridContainer

## Pure view-model: one row dict per player (all attrs + derived), sorted. Gate-asserted.
static func roster_rows(team: TeamData, sort_key: String = "ovr", desc: bool = true) -> Array:
	var rows := []
	for p in team.roster:
		var row := {
			"id": p.id, "name": p.full_name(), "pos": p.primary_pos,
			"age": p.age, "ovr": p.overall(), "salary": p.salary, "player": p,
		}
		for k in PlayerData.ATTRS:
			row[k] = p.get_attr(k)
		rows.append(row)
	rows.sort_custom(func(a, b):
		var av = a.get(sort_key, 0)
		var bv = b.get(sort_key, 0)
		if av == bv:
			return int(a["ovr"]) > int(b["ovr"])
		return av > bv if desc else av < bv
	)
	return rows

func setup(ctx: Dictionary = {}) -> void:
	if GameState.league == null:
		return
	if ctx.has("team_id"):
		var t := GameState.league.get_team(int(ctx["team_id"]))
		if t != null:
			_team = t
	if _team == null:
		_team = GameState.league.player_team()
	if is_inside_tree():
		_refresh()

func _ready() -> void:
	if GameState.league == null:
		return
	if _team == null:
		_team = GameState.league.player_team()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh()

func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	margin.add_child(vb)

	# Team selector.
	var sel := HBoxContainer.new()
	sel.add_theme_constant_override("separation", 10)
	var prev := Button.new()
	prev.text = "◀"
	prev.pressed.connect(_cycle.bind(-1))
	sel.add_child(prev)
	var next := Button.new()
	next.text = "▶"
	next.pressed.connect(_cycle.bind(1))
	sel.add_child(next)
	sel.add_child(UITheme.cell("(browse all 8 teams)", UITheme.FAINT, 13))
	vb.add_child(sel)

	_header = VBoxContainer.new()
	_header.add_theme_constant_override("separation", 4)
	vb.add_child(_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	_table = GridContainer.new()
	_table.columns = COLS.size()
	_table.add_theme_constant_override("h_separation", 16)
	_table.add_theme_constant_override("v_separation", 7)
	scroll.add_child(_table)

func _refresh() -> void:
	if _team == null or _header == null:
		return
	_clear(_header)
	var title := UITheme.cell(_team.name, UITheme.GOLD if _team.is_player_team else UITheme.INK, 30)
	_header.add_child(title)
	var counts := ""
	for pos in PlayerData.POSITIONS:
		counts += "%s%d  " % [pos, _team.count_position(pos)]
	var cap := GameState.league.league_cap
	var pay := EconomyManager.payroll(_team)
	var sub := "Record %d-%d    ·    Team OVR %.1f    ·    Payroll %s / Cap %s    ·    %s    ·    %s" % [
		_team.wins, _team.losses, _team.team_ovr(),
		UITheme.moneyf(pay), UITheme.moneyf(cap), counts.strip_edges(), UITheme.moneyf(_team.cash),
	]
	_header.add_child(UITheme.cell(sub, UITheme.MUTED, 16))

	_clear(_table)
	for c in COLS:
		var h := Button.new()
		h.text = c["label"] + (" ▾" if c["key"] == _sort_key and _sort_desc else (" ▴" if c["key"] == _sort_key else ""))
		h.flat = true
		h.custom_minimum_size = Vector2(c["w"], 0)
		h.add_theme_font_size_override("font_size", 13)
		h.add_theme_color_override("font_color", UITheme.FAINT)
		h.alignment = HORIZONTAL_ALIGNMENT_LEFT
		h.pressed.connect(_sort_by.bind(c["key"]))
		_table.add_child(h)

	for row in roster_rows(_team, _sort_key, _sort_desc):
		for c in COLS:
			_table.add_child(_render_cell(c, row))

func _render_cell(col: Dictionary, row: Dictionary) -> Control:
	var key: String = col["key"]
	match col["kind"]:
		"name":
			var b := Button.new()
			b.text = row["name"]
			b.flat = true
			b.custom_minimum_size = Vector2(col["w"], 0)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_color_override("font_color", UITheme.LINK)
			b.add_theme_font_size_override("font_size", 17)
			b.pressed.connect(_open_card.bind(row["player"]))
			return b
		"ovr":
			return UITheme.cell("%d" % int(row[key]), UITheme.ovr_color(float(row[key])), 18)
		"attr":
			return UITheme.cell("%d" % int(row[key]), UITheme.ovr_color(float(row[key])), 16)
		"money":
			return UITheme.cell(UITheme.moneyf(row[key]), UITheme.DIM, 16)
		_:
			return UITheme.cell(str(row[key]), UITheme.DIM, 17)

func _sort_by(key: String) -> void:
	if _sort_key == key:
		_sort_desc = not _sort_desc
	else:
		_sort_key = key
		_sort_desc = not (key == "name")   # text ascending, numbers descending by default
	_refresh()

func _cycle(dir: int) -> void:
	var teams := GameState.league.teams
	var idx := teams.find(_team)
	idx = (idx + dir + teams.size()) % teams.size()
	_team = teams[idx]
	_refresh()

func _open_card(p: PlayerData) -> void:
	var card := PlayerCard.new()
	add_child(card)
	card.show_player(p)

func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
