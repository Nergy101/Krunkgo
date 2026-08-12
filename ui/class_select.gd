class_name ClassSelect
extends CanvasLayer
## Pick your primary before you spawn.
##
## Shown once at match start and again on every death. A class is only a
## primary weapon; the pistol is always the secondary, so no pick can leave you
## defenceless. Number keys choose, a click chooses, and Space keeps whatever
## you had — which is what you want ninety-nine respawns out of a hundred, so it
## must be the fastest thing on the screen.

signal chosen(class_id: String)

const CARD := Vector2(230, 300)
const GAP := 18.0

var root: Control
var font: Font
var open: bool = false
var current: String = "trigger"
var wait_left: float = 0.0          # respawn lockout; you may pick during it
var pending: String = ""
var hovered: int = -1
var _prev_mouse_mode: int = Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
	layer = 20                       # above the HUD
	font = ThemeDB.fallback_font
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.draw.connect(_draw_ui)
	add_child(root)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func show_for(current_id: String, lockout: float) -> void:
	current = current_id
	wait_left = maxf(0.0, lockout)
	pending = ""
	hovered = -1
	open = true
	visible = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	open = false
	visible = false
	Input.mouse_mode = _prev_mouse_mode

func _card_rect(i: int, size: Vector2) -> Rect2:
	var n: int = WeaponDefs.CLASSES.size()
	var total: float = n * CARD.x + (n - 1) * GAP
	var x: float = (size.x - total) * 0.5 + i * (CARD.x + GAP)
	return Rect2(Vector2(x, size.y * 0.5 - CARD.y * 0.5), CARD)

func _process(delta: float) -> void:
	if not open:
		return
	wait_left = maxf(0.0, wait_left - delta)
	var mp := root.get_global_mouse_position()
	var size := get_viewport().get_visible_rect().size
	hovered = -1
	for i in WeaponDefs.CLASSES.size():
		if _card_rect(i, size).has_point(mp):
			hovered = i
	# a pick made during the lockout fires the moment it expires
	if pending != "" and wait_left <= 0.0:
		_commit(pending)
	root.queue_redraw()

func _input(event: InputEvent) -> void:
	if not open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_SPACE:
			_pick(current)                      # keep what you had
			get_viewport().set_input_as_handled()
			return
		for i in WeaponDefs.CLASSES.size():
			if k.keycode == KEY_1 + i:
				_pick(String(WeaponDefs.CLASSES[i]["id"]))
				get_viewport().set_input_as_handled()
				return
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and hovered >= 0:
			_pick(String(WeaponDefs.CLASSES[hovered]["id"]))
			get_viewport().set_input_as_handled()

func _pick(id: String) -> void:
	if wait_left > 0.0:
		pending = id                            # queued until the lockout ends
		return
	_commit(id)

func _commit(id: String) -> void:
	current = id
	close()
	chosen.emit(id)

# ------------------------------------------------------------------- drawing
func _text(pos: Vector2, s: String, size_px: int, col: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var p := pos
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px).x
		p.x -= w if align == HORIZONTAL_ALIGNMENT_RIGHT else w * 0.5
	for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		root.draw_string(font, p + d * 2.0, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px,
			Color(0, 0, 0, 0.85))
	root.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px, col)

func _draw_ui() -> void:
	var size := get_viewport().get_visible_rect().size
	root.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.04, 0.78))
	_text(Vector2(size.x * 0.5, size.y * 0.5 - CARD.y * 0.5 - 58), "CHOOSE YOUR CLASS", 40,
		Color8(255, 196, 66), HORIZONTAL_ALIGNMENT_CENTER)

	for i in WeaponDefs.CLASSES.size():
		var c: Dictionary = WeaponDefs.CLASSES[i]
		var r: Rect2 = _card_rect(i, size)
		var is_current: bool = String(c["id"]) == current
		var hot: bool = hovered == i
		root.draw_rect(Rect2(r.position + Vector2(4, 4), r.size), Color(0, 0, 0, 0.5))
		root.draw_rect(r, Color(0.10, 0.11, 0.13, 0.96) if not hot else Color(0.17, 0.18, 0.21, 0.98))
		var edge: Color = Color8(255, 196, 66) if (hot or is_current) else Color(1, 1, 1, 0.22)
		root.draw_rect(Rect2(r.position, Vector2(r.size.x, 5)), edge)

		_text(r.position + Vector2(16, 46), "[%d]" % (i + 1), 26, edge)
		_text(r.position + Vector2(16, 88), String(c["name"]), 25, Color(1, 1, 1))
		var prim: Dictionary = WeaponDefs.get_def(String(c["primary"]))
		_text(r.position + Vector2(16, 128), String(prim["display"]), 18, Color8(255, 196, 66))
		_text(r.position + Vector2(16, 154), "+ PISTOL", 16, Color(1, 1, 1, 0.5))
		_wrap(String(c["blurb"]), r.position + Vector2(16, 196), r.size.x - 32, 15)
		if is_current:
			_text(r.position + Vector2(16, r.size.y - 18), "CURRENT", 15, Color8(255, 196, 66))

	var foot: Vector2 = Vector2(size.x * 0.5, size.y * 0.5 + CARD.y * 0.5 + 46)
	if wait_left > 0.0:
		var msg: String = "RESPAWN IN %.1f" % wait_left
		if pending != "":
			msg += "   —   %s READY" % String(WeaponDefs.class_by_id(pending)["name"])
		_text(foot, msg, 24, Color8(255, 196, 66), HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_text(foot, "SPACE to keep %s   ·   1-%d or click to change"
			% [String(WeaponDefs.class_by_id(current)["name"]), WeaponDefs.CLASSES.size()],
			22, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)

## Crude greedy wrap. Enough for a one-line blurb, and it avoids pulling in a
## RichTextLabel just to break two sentences.
func _wrap(text: String, pos: Vector2, width: float, size_px: int) -> void:
	var line := ""
	var y := 0.0
	for word in text.split(" "):
		var trial: String = word if line == "" else line + " " + word
		if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px).x > width:
			_text(pos + Vector2(0, y), line, size_px, Color(1, 1, 1, 0.62))
			y += size_px + 5.0
			line = word
		else:
			line = trial
	if line != "":
		_text(pos + Vector2(0, y), line, size_px, Color(1, 1, 1, 0.62))
