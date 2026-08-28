class_name BoxScore
extends Control
## Reusable box-score reveal: tap any game in the Season Center to see both teams' full lines —
## the GDD's hedge against "it's just a spreadsheet" (§4.2). Data comes from the pure static
## `box_model()` (gate-asserted); the overlay only renders it. Reads a GameResult, which is
## fully self-contained (per-player box keyed by pid, names captured at sim time).

signal closed

const BOX_COLS := [
	{"label": "PLAYER", "w": 190, "key": "name", "kind": "name"},
	{"label": "PTS", "w": 46, "key": "pts", "kind": "hi"},
	{"label": "REB", "w": 46, "key": "reb", "kind": "num"},
	{"label": "AST", "w": 46, "key": "ast", "kind": "num"},
	{"label": "STL", "w": 44, "key": "stl", "kind": "num"},
	{"label": "BLK", "w": 44, "key": "blk", "kind": "num"},
	{"label": "FG", "w": 58, "key": "fg", "kind": "txt"},
	{"label": "3P", "w": 58, "key": "tp", "kind": "txt"},
	{"label": "FT", "w": 56, "key": "ft", "kind": "txt"},
	{"label": "TO", "w": 42, "key": "tov", "kind": "num"},
]

## Pure view-model: both teams' box scores + the final line + MVP. Gate-asserted.
static func box_model(r: GameResult, league: LeagueData) -> Dictionary:
	var home := _team_box(r, r.home_pids, r.home_team_id, league)
	var away := _team_box(r, r.away_pids, r.away_team_id, league)
	return {
		"home": home, "away": away,
		"home_score": r.home_score, "away_score": r.away_score,
		"winner_id": r.winner_id,
		"mvp": r.names.get(r.mvp_id, "-"),
		"final": "%s %d  @  %s %d" % [away["abbrev"], r.away_score, home["abbrev"], r.home_score],
	}

static func _team_box(r: GameResult, pids: Array, team_id: int, league: LeagueData) -> Dictionary:
	var t: TeamData = league.get_team(team_id)
	var rows := []
	for pid in pids:
		var s: Dictionary = r.box[pid]
		rows.append({
			"pid": pid, "name": r.names.get(pid, "?"),
			"pts": int(s["pts"]), "reb": int(s["oreb"]) + int(s["dreb"]),
			"ast": int(s["ast"]), "stl": int(s["stl"]), "blk": int(s["blk"]), "tov": int(s["tov"]),
			"fg": "%d-%d" % [s["fgm"], s["fga"]],
			"tp": "%d-%d" % [s["tpm"], s["tpa"]],
			"ft": "%d-%d" % [s["ftm"], s["fta"]],
		})
	rows.sort_custom(func(a, b): return int(a["pts"]) > int(b["pts"]))
	var score := r.home_score if team_id == r.home_team_id else r.away_score
	return {
		"team_id": team_id,
		"name": t.name if t != null else "?",
		"abbrev": t.abbrev if t != null else "?",
		"score": score, "rows": rows,
	}

# --- render -----------------------------------------------------------------

func show_result(r: GameResult) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := box_model(r, GameState.league)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.66)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := UITheme.styled_panel(UITheme.PANEL, 12, 22)
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	# Title row: final score (winner highlighted) + close.
	var title_row := HBoxContainer.new()
	var aw: Dictionary = m["away"]
	var hm: Dictionary = m["home"]
	var score_lbl := UITheme.cell("%s %d   @   %s %d" % [aw["abbrev"], m["away_score"], hm["abbrev"], m["home_score"]], UITheme.INK, 26)
	score_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(score_lbl)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.pressed.connect(_close)
	title_row.add_child(close)
	col.add_child(title_row)
	col.add_child(UITheme.cell("Player of the game:  %s" % m["mvp"], UITheme.GOLD, 15))
	col.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 540)
	col.add_child(scroll)
	var tables := VBoxContainer.new()
	tables.add_theme_constant_override("separation", 16)
	scroll.add_child(tables)
	tables.add_child(_team_table(m["away"], m["winner_id"]))
	tables.add_child(_team_table(m["home"], m["winner_id"]))

func _team_table(team: Dictionary, winner_id: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var won: bool = int(team["team_id"]) == winner_id
	box.add_child(UITheme.cell("%s  —  %d%s" % [team["name"], team["score"], "   ▸ WIN" if won else ""], UITheme.GOLD if won else UITheme.INK, 19))
	var grid := GridContainer.new()
	grid.columns = BOX_COLS.size()
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 5)
	for c in BOX_COLS:
		var h := UITheme.header(c["label"], 12)
		h.custom_minimum_size = Vector2(c["w"], 0)
		grid.add_child(h)
	for row in team["rows"]:
		for c in BOX_COLS:
			grid.add_child(_box_cell(c, row))
	box.add_child(grid)
	return box

func _box_cell(col: Dictionary, row: Dictionary) -> Control:
	var val = row[col["key"]]
	match col["kind"]:
		"name":
			var l := UITheme.cell(str(val), UITheme.DIM, 15)
			l.custom_minimum_size = Vector2(col["w"], 0)
			return l
		"hi":
			return UITheme.cell(str(val), UITheme.INK, 16)
		"txt":
			return UITheme.cell(str(val), UITheme.MUTED, 14)
		_:
			return UITheme.cell(str(val), UITheme.DIM, 15)

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
