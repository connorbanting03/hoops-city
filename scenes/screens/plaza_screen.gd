extends Control
## The city ground — free-roam foundation (first art pass). Your GM avatar walks around an
## isometric grass plot with WASD / arrow keys; a follow-camera keeps them centered. This is the
## base the city builds on: a Node2D world of iso tiles (later: placed buildings you walk up to to
## trigger systems). For now, the management systems are reached from the top nav tabs.

const TILE_W := 256.0
const TILE_H := 128.0
const HALF_W := TILE_W * 0.5
const HALF_H := TILE_H * 0.5
const GRID := 14            # ground extent (cells per side)
const SPEED := 300.0        # avatar walk speed, px/s
const FOOT := 56.0          # sprite-center -> feet offset
const ANIM_STEP := 0.08     # seconds per walk frame
const IDLE_DELAY := 0.5     # stand still after this long with no input
const IDLE_FRAME := {"down": 3, "up": 3, "side": 2}   # the flat-footed standing pose per facing

const DOWN := [
	preload("res://assets/avatar/exec_walk_down_0.png"), preload("res://assets/avatar/exec_walk_down_1.png"),
	preload("res://assets/avatar/exec_walk_down_2.png"), preload("res://assets/avatar/exec_walk_down_3.png"),
	preload("res://assets/avatar/exec_walk_down_4.png"), preload("res://assets/avatar/exec_walk_down_5.png"),
	preload("res://assets/avatar/exec_walk_down_6.png"), preload("res://assets/avatar/exec_walk_down_7.png"),
]
const UP := [
	preload("res://assets/avatar/exec_walk_up_0.png"), preload("res://assets/avatar/exec_walk_up_1.png"),
	preload("res://assets/avatar/exec_walk_up_2.png"), preload("res://assets/avatar/exec_walk_up_3.png"),
	preload("res://assets/avatar/exec_walk_up_4.png"), preload("res://assets/avatar/exec_walk_up_5.png"),
	preload("res://assets/avatar/exec_walk_up_6.png"), preload("res://assets/avatar/exec_walk_up_7.png"),
]
const SIDE := [   # the original "normal" walk set — used for left/right (flipped for left)
	preload("res://assets/avatar/exec_walk_0.png"), preload("res://assets/avatar/exec_walk_1.png"),
	preload("res://assets/avatar/exec_walk_2.png"), preload("res://assets/avatar/exec_walk_3.png"),
	preload("res://assets/avatar/exec_walk_4.png"), preload("res://assets/avatar/exec_walk_5.png"),
	preload("res://assets/avatar/exec_walk_6.png"), preload("res://assets/avatar/exec_walk_7.png"),
]
const TEX_GRASS := preload("res://assets/city/ground_grass.png")

var _world: Node2D
var _avatar: Sprite2D
var _pos: Vector2            # avatar feet, in world coordinates
var _bounds: Rect2          # where the feet may roam (tile centers)
var _ground: Rect2          # full drawn ground extent (for the camera clamp)
var _cur: Array = DOWN       # current facing's frame set
var _facing: String = "down"
var _frame: int = 0
var _anim_t: float = 0.0
var _idle_t: float = 0.0

static func _cell_world(gx: int, gy: int) -> Vector2:
	return Vector2(float(gx - gy) * HALF_W, float(gx + gy) * HALF_H)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_contents = true

	var bg := ColorRect.new()
	bg.color = Color("0b2a1a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_world = Node2D.new()
	add_child(_world)
	for gx in GRID:
		for gy in GRID:
			var t := Sprite2D.new()
			t.texture = TEX_GRASS
			t.position = _cell_world(gx, gy)
			_world.add_child(t)

	_avatar = Sprite2D.new()
	_avatar.texture = DOWN[0]
	_world.add_child(_avatar)          # added last -> drawn above the ground

	# Roam bounds = the span of tile centers (with a small inset so you stay on the grass).
	var lo := _cell_world(0, 0)
	var hi := _cell_world(GRID - 1, GRID - 1)
	var left := _cell_world(0, GRID - 1).x
	var right := _cell_world(GRID - 1, 0).x
	_bounds = Rect2(Vector2(left, lo.y), Vector2(right - left, hi.y - lo.y))
	# Full drawn extent = tile centers grown by a half-tile on every side.
	_ground = Rect2(left - HALF_W, lo.y - HALF_H, (right - left) + TILE_W, (hi.y - lo.y) + TILE_H)
	@warning_ignore("integer_division")
	var mid := GRID / 2
	_pos = _cell_world(mid, mid)

	var hint := UITheme.cell("Use WASD / arrow keys to walk around your city.", UITheme.MUTED, 16)
	hint.position = Vector2(6, 4)
	add_child(hint)

	set_process(true)
	_update_camera()

func setup(_ctx: Dictionary = {}) -> void:
	pass

func _process(delta: float) -> void:
	if _avatar == null:
		return
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0

	if dir != Vector2.ZERO:
		_idle_t = 0.0
		# Face the way we're walking: up/down use their own sets; left/right flip the side set.
		if absf(dir.y) > absf(dir.x):
			_cur = UP if dir.y < 0.0 else DOWN
			_facing = "up" if dir.y < 0.0 else "down"
			_avatar.flip_h = false
		else:
			_cur = SIDE
			_facing = "side"
			_avatar.flip_h = dir.x < 0.0
		_pos += dir.normalized() * SPEED * delta
		_pos.x = clampf(_pos.x, _bounds.position.x, _bounds.position.x + _bounds.size.x)
		_pos.y = clampf(_pos.y, _bounds.position.y, _bounds.position.y + _bounds.size.y)
		_anim_t += delta
		if _anim_t >= ANIM_STEP:
			_anim_t = 0.0
			_frame = (_frame + 1) % _cur.size()
		_avatar.texture = _cur[_frame]
	else:
		# Just stopped: hold the current stride briefly (so a tap/turn keeps the cadence), then
		# settle onto the flat-footed standing pose. _frame is preserved so resuming continues.
		_idle_t += delta
		if _idle_t >= IDLE_DELAY:
			_avatar.texture = _cur[int(IDLE_FRAME[_facing])]
		else:
			_avatar.texture = _cur[_frame]

	_update_camera()

func _update_camera() -> void:
	_avatar.position = _pos - Vector2(0, FOOT)
	# Follow-camera, clamped so the view never scrolls past the edge of the ground. (When the
	# avatar nears an edge it walks toward the screen edge instead of the camera centering on void.)
	var target := (size * 0.5) - _pos
	target.x = _clamp_axis(target.x, size.x, _ground.position.x, _ground.end.x)
	target.y = _clamp_axis(target.y, size.y, _ground.position.y, _ground.end.y)
	_world.position = target

## Clamp a camera offset on one axis so the visible [0, view] window stays inside [lo, hi]. If the
## ground is smaller than the view on that axis, center it instead.
func _clamp_axis(offset: float, view: float, lo: float, hi: float) -> float:
	var min_off := view - hi   # offset that pins the ground's far edge to the view's far edge
	var max_off := -lo         # offset that pins the ground's near edge to the view's near edge
	if min_off <= max_off:
		return clampf(offset, min_off, max_off)
	return (min_off + max_off) * 0.5
