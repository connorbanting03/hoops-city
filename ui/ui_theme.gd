class_name UITheme
extends RefCounted
## Shared presentation helpers + palette for every screen (§7.1: the view layer). Pure builders
## and formatters — no state — so screens stay thin and consistent. Extracted from the old
## franchise_hub so the hub, roster, and later screens all read the same way.

# --- palette ---
const BG       := Color("0e1116")   # app background
const PANEL     := Color("171b22")   # card / panel fill
const PANEL_HI := Color("1d232c")   # hovered / selected panel
const INK       := Color("e6edf3")   # primary text
const DIM       := Color("c9d4de")   # secondary text
const MUTED     := Color("8aa0b4")   # tertiary text
const FAINT     := Color("6f8194")   # labels / headers
const FAINTER   := Color("4a5a6a")   # rank numbers / hairlines
const GOLD       := Color("ffd479")   # the player's franchise
const LINK       := Color("7fb2ff")   # clickable text

# --- text ---
static func cell(txt: String, col: Color = INK, fsize: int = 18) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", fsize)
	return l

static func header(txt: String, fsize: int = 14) -> Label:
	return cell(txt, FAINT, fsize)

# --- color ramps ---
static func ovr_color(o: float) -> Color:
	if o >= 75.0:
		return Color("57d977")
	if o >= 65.0:
		return Color("b6e36a")
	if o >= 55.0:
		return Color("e6d36a")
	if o >= 45.0:
		return Color("e6b05a")
	return Color("d98c6a")

# --- formatters ---
static func popf(n) -> String:
	var p := float(n)
	if p >= 1_000_000_000.0:
		return "%.2fB" % (p / 1e9)
	if p >= 1_000_000.0:
		return "%.2fM" % (p / 1e6)
	if p >= 1_000.0:
		return "%.1fK" % (p / 1e3)
	return "%d" % int(p)

static func moneyf(n) -> String:
	var v := float(n)
	var neg := "-" if v < 0.0 else ""
	v = absf(v)
	if v >= 1_000_000_000.0:
		return "%s$%.2fB" % [neg, v / 1e9]
	if v >= 1_000_000.0:
		return "%s$%.1fM" % [neg, v / 1e6]
	if v >= 1_000.0:
		return "%s$%.0fK" % [neg, v / 1e3]
	return "%s$%d" % [neg, int(v)]

## Height in cm -> readable feet/inches, e.g. 201 -> 6'7".
static func height_label(cm: int) -> String:
	var total_in := int(round(float(cm) / 2.54))
	@warning_ignore("integer_division")
	var ft := total_in / 12
	var inch := total_in % 12
	return "%d'%d\"" % [ft, inch]

# --- panels ---
static func styled_panel(fill: Color = PANEL, radius: int = 8, pad: int = 14) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad + 2
	sb.content_margin_right = pad + 2
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	panel.add_theme_stylebox_override("panel", sb)
	return panel

## A small label-over-value stat chip (Record / Cash / Pop ...).
static func stat_card(label: String, value: String, value_col: Color = INK) -> PanelContainer:
	var panel := styled_panel(PANEL, 8, 14)
	panel.add_theme_constant_override("margin_top", 10)
	var v := VBoxContainer.new()
	v.add_child(cell(label, FAINT, 13))
	v.add_child(cell(value, value_col, 24))
	panel.add_child(v)
	return panel
