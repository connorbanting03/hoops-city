extends Control
## The app shell (§7.2): a persistent top bar (your franchise at a glance) + a nav strip + a
## content area that swaps screens. Screens are dumb views instanced on demand; navigation flows
## through EventBus.screen_requested so any screen can jump to another without knowing about it.
## New screens are added to SCREENS + NAV per milestone.

const SCREENS := {
	"plaza": preload("res://scenes/screens/plaza_screen.tscn"),
	"hub": preload("res://scenes/screens/hub_screen.tscn"),
	"roster": preload("res://scenes/screens/roster_screen.tscn"),
	"season": preload("res://scenes/screens/season_screen.tscn"),
	"city": preload("res://scenes/screens/city_screen.tscn"),
	"draft": preload("res://scenes/screens/draft_screen.tscn"),   # contextual phase screens, not in the nav
	"fa": preload("res://scenes/screens/fa_screen.tscn"),
	"game": preload("res://scenes/screens/game_screen.tscn"),
}
const NAV := [["plaza", "Plaza"], ["hub", "Hub"], ["roster", "Roster"], ["season", "Season"], ["city", "City"]]
# The on-rails progression, shown as a stepper so the player always knows where the year stands.
const PHASE_STEPS := [["regular_season", "Season"], ["playoffs", "Playoffs"], ["draft", "Draft"], ["free_agency", "Free Agency"]]

var _content: Control
var _topbar: HBoxContainer
var _stepper: HBoxContainer
var _nav_buttons: Dictionary = {}
var _current: String = ""

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return   # the M10 gate drives boot()/show_screen() explicitly
	boot()

## Idempotent startup: ensure a world exists, build the chrome, show the hub. Called by _ready
## (windowed) or directly by the gate (headless).
func boot() -> void:
	if GameState.league == null:
		GameState.new_game()
	if _content == null:
		_build_ui()
	if not EventBus.screen_requested.is_connected(_on_screen_requested):
		EventBus.screen_requested.connect(_on_screen_requested)
	if not EventBus.world_changed.is_connected(_refresh_topbar):
		EventBus.world_changed.connect(_refresh_topbar)
	if not EventBus.phase_changed.is_connected(_on_phase_changed):
		EventBus.phase_changed.connect(_on_phase_changed)
	show_screen("plaza")

func _on_phase_changed(_phase: String) -> void:
	_refresh_topbar()

func current_screen() -> String:
	return _current

func _on_screen_requested(screen: String, ctx: Dictionary) -> void:
	show_screen(screen, ctx)

func show_screen(screen_name: String, ctx: Dictionary = {}) -> void:
	if not SCREENS.has(screen_name) or _content == null:
		return
	_clear(_content)
	var screen: Control = SCREENS[screen_name].instantiate()
	_content.add_child(screen)
	if screen.has_method("setup"):
		screen.setup(ctx)
	_current = screen_name
	_refresh_topbar()
	_refresh_nav()

# --- chrome -----------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var brand := UITheme.cell("HOOPS CITY", UITheme.INK, 30)
	root.add_child(brand)

	# Top bar: franchise at a glance.
	var bar_panel := UITheme.styled_panel(UITheme.PANEL, 10, 14)
	root.add_child(bar_panel)
	_topbar = HBoxContainer.new()
	_topbar.add_theme_constant_override("separation", 30)
	bar_panel.add_child(_topbar)

	# Nav strip.
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	root.add_child(nav)
	for entry in NAV:
		var b := Button.new()
		b.text = entry[1]
		b.focus_mode = Control.FOCUS_NONE   # so arrow keys drive the avatar, not button focus
		b.pressed.connect(show_screen.bind(entry[0]))
		nav.add_child(b)
		_nav_buttons[entry[0]] = b

	# Phase stepper: Season ▸ Playoffs ▸ Draft ▸ Free Agency, current phase lit.
	_stepper = HBoxContainer.new()
	_stepper.add_theme_constant_override("separation", 8)
	root.add_child(_stepper)

	root.add_child(HSeparator.new())

	# Content area: fills the rest; screens anchor full-rect inside it.
	_content = Control.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_content)

func _refresh_topbar() -> void:
	_refresh_stepper()
	if _topbar == null or GameState.league == null:
		return
	_clear(_topbar)
	var you := GameState.league.player_team()
	_topbar.add_child(_chip(you.name, "Year %d" % GameState.current_year, UITheme.GOLD))
	_topbar.add_child(_chip("Phase", String(GameState.current_phase).capitalize(), UITheme.INK))
	_topbar.add_child(_chip("Cash", UITheme.moneyf(you.cash), UITheme.INK))
	_topbar.add_child(_chip("Payroll", UITheme.moneyf(EconomyManager.payroll(you)), UITheme.DIM))
	_topbar.add_child(_chip("League Cap", UITheme.moneyf(GameState.league.league_cap), UITheme.DIM))
	if GameState.city != null:
		_topbar.add_child(_chip("City", UITheme.popf(GameState.city.population), UITheme.INK))

func _refresh_nav() -> void:
	for key in _nav_buttons:
		var b: Button = _nav_buttons[key]
		b.add_theme_color_override("font_color", UITheme.GOLD if key == _current else UITheme.MUTED)

func _refresh_stepper() -> void:
	if _stepper == null:
		return
	_clear(_stepper)
	var cur := String(GameState.current_phase)
	for i in PHASE_STEPS.size():
		var on: bool = PHASE_STEPS[i][0] == cur
		_stepper.add_child(UITheme.cell(PHASE_STEPS[i][1], UITheme.GOLD if on else UITheme.FAINT, 15 if on else 14))
		if i < PHASE_STEPS.size() - 1:
			_stepper.add_child(UITheme.cell("▸", UITheme.FAINTER, 13))

func _chip(label: String, value: String, value_col: Color) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_child(UITheme.cell(label, UITheme.FAINT, 12))
	v.add_child(UITheme.cell(value, value_col, 19))
	return v

func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
