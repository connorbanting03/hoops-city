class_name SeasonScreen
extends Control
## Season Center: the season just played — final standings, your 35-game schedule (every game's
## box score one click away), and the playoff bracket. Reads GameState.last_season (a snapshot
## taken by FranchiseManager each year). Pure `schedule_rows`/`series_wins` view-models are
## gate-asserted; the Control renders them and opens the BoxScore overlay.

var _body: VBoxContainer
var _show_all: bool = false

## Pure: the player's games from `last_season`, in schedule order. Gate-asserted.
static func schedule_rows(last_season: Dictionary, team_id: int) -> Array:
	var out := []
	for r in last_season.get("games", []):
		if r.home_team_id != team_id and r.away_team_id != team_id:
			continue
		var home: bool = r.home_team_id == team_id
		out.append({
			"result": r, "home": home,
			"opp_id": r.away_team_id if home else r.home_team_id,
			"won": r.winner_id == team_id,
			"your_score": r.home_score if home else r.away_score,
			"opp_score": r.away_score if home else r.home_score,
		})
	return out

## Pure: games won by each side of a playoff series.
static func series_wins(entry: Dictionary) -> Dictionary:
	var hw := 0
	var lw := 0
	for g in entry["games"]:
		if g.winner_id == int(entry["high_id"]):
			hw += 1
		else:
			lw += 1
	return {"high": hw, "low": lw}

func setup(_ctx: Dictionary = {}) -> void:
	if is_inside_tree() and _body != null:
		_refresh()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 20)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_body)
	scroll.add_child(margin)
	_refresh()

func _refresh() -> void:
	if _body == null:
		return
	_clear(_body)
	var ls := GameState.last_season
	if ls.is_empty():
		_body.add_child(UITheme.cell("No season played yet.", UITheme.INK, 22))
		_body.add_child(UITheme.cell("Head to the Hub and press \"Advance year\" to play a season — it'll show up here.", UITheme.MUTED, 16))
		return

	_body.add_child(UITheme.cell("Season %d" % int(ls["year"]), UITheme.INK, 28))
	_body.add_child(UITheme.cell("Champion:  %s        ·        MVP:  %s" % [ls["champion"], ls.get("mvp", "-")], UITheme.GOLD, 17))

	_section("FINAL STANDINGS")
	_build_standings(ls)
	_section("PLAYOFFS")
	_build_bracket(ls)
	_build_schedule(ls)

# --- standings --------------------------------------------------------------

func _build_standings(ls: Dictionary) -> void:
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 6)
	for h in ["#", "TEAM", "W-L", "PT DIFF", "", ""]:
		grid.add_child(UITheme.header(h))
	var place := 1
	for row in ls["standings"]:
		var col := UITheme.GOLD if row["is_player"] else UITheme.INK
		grid.add_child(UITheme.cell("%d" % place, UITheme.FAINTER, 17))
		var nb := Button.new()
		nb.text = row["name"]
		nb.flat = true
		nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nb.add_theme_color_override("font_color", col)
		nb.add_theme_font_size_override("font_size", 17)
		nb.pressed.connect(func(): EventBus.screen_requested.emit("roster", {"team_id": row["team_id"]}))
		grid.add_child(nb)
		grid.add_child(UITheme.cell("%d-%d" % [row["wins"], row["losses"]], UITheme.DIM, 17))
		var pd: int = row["pdiff"]
		grid.add_child(UITheme.cell("%+d" % pd, Color("57d977") if pd >= 0 else Color("d98c6a"), 17))
		grid.add_child(UITheme.cell("PLAYOFFS" if row["made_playoffs"] else "", UITheme.MUTED, 13))
		var tag := ""
		if row["is_dynasty"]:
			tag = "dynasty"
		if row["is_player"]:
			tag = "you"
		grid.add_child(UITheme.cell(tag, UITheme.MUTED, 13))
		place += 1
	_body.add_child(grid)

# --- bracket ----------------------------------------------------------------

func _build_bracket(ls: Dictionary) -> void:
	for entry in ls["series"]:
		var high: TeamData = GameState.league.get_team(int(entry["high_id"]))
		var low: TeamData = GameState.league.get_team(int(entry["low_id"]))
		var w := series_wins(entry)
		var high_won: bool = int(entry["winner_id"]) == int(entry["high_id"])

		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.add_child(UITheme.cell(String(entry["round"]).to_upper(), UITheme.FAINT, 13))
		line.add_child(UITheme.cell("%s %d" % [high.abbrev if high else "?", w["high"]], UITheme.GOLD if high_won else UITheme.DIM, 18))
		line.add_child(UITheme.cell("–", UITheme.FAINTER, 18))
		line.add_child(UITheme.cell("%d %s" % [w["low"], low.abbrev if low else "?"], UITheme.GOLD if not high_won else UITheme.DIM, 18))
		# Per-game chips, clickable to the box score.
		var g := 1
		for game in entry["games"]:
			var b := Button.new()
			b.text = "G%d  %d-%d" % [g, game.home_score, game.away_score]
			b.flat = true
			b.add_theme_font_size_override("font_size", 12)
			b.add_theme_color_override("font_color", UITheme.LINK)
			b.pressed.connect(_open_box.bind(game))
			line.add_child(b)
			g += 1
		row.add_child(line)
		_body.add_child(row)

# --- schedule ---------------------------------------------------------------

func _build_schedule(ls: Dictionary) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.add_child(UITheme.header("SCHEDULE — %s" % ("ALL GAMES" if _show_all else "YOUR GAMES")))
	var toggle := Button.new()
	toggle.text = "Show all games" if not _show_all else "Show only my games"
	toggle.pressed.connect(func():
		_show_all = not _show_all
		_refresh()
	)
	head.add_child(toggle)
	_body.add_child(head)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 5)
	for h in ["#", "MATCHUP", "SCORE", ""]:
		grid.add_child(UITheme.header(h))

	if _show_all:
		var n := 1
		for r in ls["games"]:
			var home: TeamData = GameState.league.get_team(r.home_team_id)
			var away: TeamData = GameState.league.get_team(r.away_team_id)
			grid.add_child(UITheme.cell("%d" % n, UITheme.FAINTER, 14))
			grid.add_child(UITheme.cell("%s @ %s" % [away.abbrev if away else "?", home.abbrev if home else "?"], UITheme.DIM, 16))
			grid.add_child(_score_button(r, "%d - %d" % [r.away_score, r.home_score]))
			grid.add_child(UITheme.cell("", UITheme.MUTED, 13))
			n += 1
	else:
		var you := GameState.league.player_team()
		var n := 1
		for row in schedule_rows(ls, you.id):
			var opp: TeamData = GameState.league.get_team(int(row["opp_id"]))
			var matchup := "%s %s" % ["vs" if row["home"] else "@", opp.abbrev if opp else "?"]
			grid.add_child(UITheme.cell("%d" % n, UITheme.FAINTER, 14))
			grid.add_child(UITheme.cell(matchup, UITheme.DIM, 16))
			grid.add_child(_score_button(row["result"], "%d - %d" % [row["your_score"], row["opp_score"]]))
			grid.add_child(UITheme.cell("W" if row["won"] else "L", Color("57d977") if row["won"] else Color("d98c6a"), 16))
			n += 1
	_body.add_child(grid)

func _score_button(r: GameResult, label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_color_override("font_color", UITheme.LINK)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(_open_box.bind(r))
	return b

# --- helpers ----------------------------------------------------------------

func _section(title: String) -> void:
	_body.add_child(UITheme.header(title))

func _open_box(r: GameResult) -> void:
	var bs := BoxScore.new()
	add_child(bs)
	bs.show_result(r)

func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
