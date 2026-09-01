class_name MainMenu
extends CanvasLayer
## Minecraft-style start menu. A blocky title over a dimmed panorama of the
## freshly-built arena, three stacked flat buttons (Play / Settings / Quit
## Game) in the classic gray-button-with-white-text / white-button-with-black-
## text hover treatment, and a settings sub-screen that tunes the bots before
## you launch.
##
## The world is fully built and frozen (tree paused) behind this layer, but
## nothing is spawned yet: Play creates the bots and drops you into the class
## picker, so whatever the settings say is honoured. Every value here writes
## straight into the Tuning autoload the game reads live.

signal play_pressed
signal quit_pressed

enum Screen { MAIN, SETTINGS }

const BTN := Vector2(340, 62)      # main-menu button size
const BTN_GAP := 22.0

const ROW_W := 600.0               # settings row (label + stepper)
const ROW_H := 66.0
const ROW_GAP := 18.0

const DIFFICULTIES := ["EASY", "NORMAL", "HARD"]
const MAX_BOTS := 12               # BOT_NAMES has 12 entries in main.gd
const MAX_PER_TEAM := 6            # TDM: bots split across two teams
const MAPS := ["burg", "standoff"] # ids MapData understands

## Chunky synthesised 5x7 display face (ui/pixel_font.gd) — replaces the
## fallback font for the title, headers and setting values, which is what
## gives Krunker's menus their identity (round-2 critic's biggest gap).
const PixelFace := preload("res://ui/pixel_font.gd")

var root: Control
var font: Font
var screen: int = Screen.MAIN
var active: bool = false
var hovered: int = -1

# Settings state (mirrored into Tuning on every change).
var difficulty_index: int = 1
var bot_count: int = Tuning.bot_count
var match_minutes: int = int(Tuning.match_seconds / 60.0)
var score_limit: int = Tuning.score_limit
var map_index: int = 0             # index into MAPS

# Interactive elements for the current screen, rebuilt every frame:
# {rect, action, data}
var _buttons: Array = []


func _ready() -> void:
	layer = 30                       # above the HUD and class picker
	font = ThemeDB.fallback_font
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.draw.connect(_draw_ui)
	add_child(root)
	active = true
	process_mode = Node.PROCESS_MODE_ALWAYS   # works while the tree is paused
	map_index = MAPS.find(MapData.map_id)
	if map_index < 0:
		map_index = 0
	_apply_settings()


## Difficulty presets map onto the live bot-tuning knobs. NORMAL is the game's
## own defaults; EASY/HARD push each knob from there.
func _difficulty_preset() -> Dictionary:
	match difficulty_index:
		0:
			return {"reaction_min": 0.32, "reaction_max": 0.62, "aim_error": 14.0,
				"leave_cover": 0.4, "retreat_health": 0.45}
		2:
			return {"reaction_min": 0.12, "reaction_max": 0.30, "aim_error": 4.0,
				"leave_cover": 0.8, "retreat_health": 0.25}
		_:
			return {"reaction_min": 0.22, "reaction_max": 0.48, "aim_error": 8.0,
				"leave_cover": 0.6, "retreat_health": 0.34}


func _apply_settings() -> void:
	var p := _difficulty_preset()
	Tuning.bot_reaction_min = p.reaction_min
	Tuning.bot_reaction_max = p.reaction_max
	Tuning.bot_aim_error_deg = p.aim_error
	Tuning.bot_leave_cover_chance = p.leave_cover
	Tuning.bot_retreat_health = p.retreat_health
	Tuning.bot_count = bot_count
	Tuning.match_seconds = float(match_minutes * 60)
	Tuning.score_limit = score_limit
	# The map is applied to MapData here too, so the menu selection is live;
	# main.gd rebuilds the arena on Play when it differs from the boot build.
	MapData.select_map(MAPS[map_index])


func close() -> void:
	active = false
	visible = false


# ------------------------------------------------------------------ geometry

func _main_rects(size: Vector2) -> Array:
	var total: float = 3.0 * BTN.y + 2.0 * BTN_GAP
	var x: float = (size.x - BTN.x) * 0.5
	var y0: float = size.y * 0.46
	var out: Array = []
	for i in 3:
		out.append(Rect2(Vector2(x, y0 + i * (BTN.y + BTN_GAP)), BTN))
	return out


func _settings_rows(size: Vector2) -> Array:
	# Fit, don't clip: at 1280x720 the fixed ROW_H/ROW_GAP stack pushed the BACK
	# button past the bottom edge (verified in a captured shot at 720p; at 1080p
	# and 800p it fit fine). Shrink rows and gaps proportionally to the height
	# actually available below the title so every resolution keeps the whole
	# panel on screen.
	var avail: float = size.y * (1.0 - 0.34) - BTN.y - ROW_GAP * 2.0 - 70.0
	var rh: float = minf(ROW_H, (avail - 4.0 * ROW_GAP) / 5.0)
	var gap: float = minf(ROW_GAP, (avail - 5.0 * rh) / 4.0)
	var rows: Array = []
	var x: float = (size.x - ROW_W) * 0.5
	var y: float = size.y * 0.34
	for i in 5:
		rows.append(Rect2(Vector2(x, y), Vector2(ROW_W, rh)))
		y += rh + gap
	return rows


func _back_rect(size: Vector2) -> Rect2:
	var rows: Array = _settings_rows(size)
	var last: Rect2 = rows[rows.size() - 1]
	return Rect2(Vector2((size.x - BTN.x) * 0.5, last.position.y + ROW_H + ROW_GAP * 2), BTN)


func _stepper_geo(row: Rect2, value: String) -> Dictionary:
	var vw: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26).x
	var s := Vector2(52, ROW_H - 12)
	var pad := 12.0
	var right := Rect2(Vector2(row.end.x - pad - s.x, row.position.y + (ROW_H - s.y) * 0.5), s)
	var left := Rect2(Vector2(right.position.x - pad - vw - pad - s.x, right.position.y), s)
	return {"left": left, "right": right,
		"vx": (left.position.x + left.size.x + pad + right.position.x - pad) * 0.5}


func _row_value(i: int) -> String:
	match i:
		0: return MapData.map_display() + " · " + Game.mode_short()
		1: return String(DIFFICULTIES[difficulty_index])
		# The one knob, two meanings: in Team Deathmatch it is the size of
		# EACH team's bot squad (total lobby = 2x + you); in FFA it is the
		# plain bot count. The label spells this out so the number is honest.
		2: return "%d  (LOBBY %d)" % [bot_count, _lobby_size()] if Game.is_tdm() else str(bot_count)
		3: return "%d MIN" % match_minutes
		_: return str(score_limit)

## Total actors that will spawn: TDM = bots per team x 2 + the player;
## FFA = bots + the player. BOT_NAMES has 12 entries, so clamp at 6 per team.
func _lobby_size() -> int:
	return bot_count * 2 + 1 if Game.is_tdm() else bot_count + 1


func _build_elements(size: Vector2) -> void:
	_buttons.clear()
	if screen == Screen.MAIN:
		var rects := _main_rects(size)
		for i in 3:
			_buttons.append({"rect": rects[i], "action": "main", "data": i})
		return
	for i in 5:
		var geo := _stepper_geo(_settings_rows(size)[i], _row_value(i))
		_buttons.append({"rect": geo["left"], "action": "dec", "data": i})
		_buttons.append({"rect": geo["right"], "action": "inc", "data": i})
	_buttons.append({"rect": _back_rect(size), "action": "back", "data": 0})


# ------------------------------------------------------------------- updates

## True while a key selection is live and the mouse is not touching a button.
## Without this, _process() recomputed `hovered` from the mouse every frame and
## instantly wiped a keyboard ↑↓ selection the moment the cursor wasn't over a
## button — the footer's "↑↓ to select · ENTER to confirm" was a lie (found by
## the round-2 menu critic). Keyboard selection now owns `hovered` until the
## mouse actually moves onto (or the mouse moves at all over) an element.
var _keyboard_nav := false

func _process(_delta: float) -> void:
	if not active:
		return
	var size := get_viewport().get_visible_rect().size
	_build_elements(size)
	var mp := root.get_global_mouse_position()
	if not _keyboard_nav:
		hovered = -1
	for i in _buttons.size():
		if Rect2(_buttons[i]["rect"]).has_point(mp):
			hovered = i
			_keyboard_nav = false
			break
	root.queue_redraw()


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		# Real mouse movement cancels keyboard ownership of the highlight;
		# _process() re-derives the hover on the next frame.
		_keyboard_nav = false
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if screen == Screen.SETTINGS and k.keycode == KEY_ESCAPE:
			screen = Screen.MAIN
			root.queue_redraw()
			get_viewport().set_input_as_handled()
			return
		var count := _buttons.size()
		if screen == Screen.MAIN and count == 3:
			if k.keycode in [KEY_DOWN, KEY_S, KEY_UP, KEY_W]:
				var step: int = 1 if (k.keycode == KEY_DOWN or k.keycode == KEY_S) else -1
				hovered = wrapi(hovered + step, 0, 3)
				_keyboard_nav = true
				get_viewport().set_input_as_handled()
				return
			if k.keycode == KEY_ENTER and hovered >= 0:
				_activate()
				get_viewport().set_input_as_handled()
				return
		elif screen == Screen.SETTINGS and count > 0:
			# Settings keyboard parity: ←/→ step the focused row's value,
			# ↑/↓ move focus between rows, ENTER activates the BACK row.
			if k.keycode in [KEY_DOWN, KEY_S, KEY_UP, KEY_W]:
				var step: int = 1 if (k.keycode == KEY_DOWN or k.keycode == KEY_S) else -1
				hovered = wrapi(hovered + step, 0, count)
				_keyboard_nav = true
				get_viewport().set_input_as_handled()
				return
			if k.keycode in [KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D] and hovered >= 0 \
					and hovered < count - 1:
				var b: Dictionary = _buttons[hovered]
				if b["action"] in ["dec", "inc"]:
					_step(int(b["data"]), 1 if (k.keycode == KEY_RIGHT or k.keycode == KEY_D) else -1)
					get_viewport().set_input_as_handled()
					return
			if k.keycode == KEY_ENTER:
				if hovered == count - 1:      # BACK
					_activate()
				get_viewport().set_input_as_handled()
				return
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and hovered >= 0:
			_activate()
			get_viewport().set_input_as_handled()


func _activate() -> void:
	if hovered < 0 or hovered >= _buttons.size():
		return
	var b: Dictionary = _buttons[hovered]
	if screen == Screen.MAIN:
		match int(b["data"]):
			0: _play()
			1: screen = Screen.SETTINGS
			2: quit_pressed.emit()
		root.queue_redraw()
		return
	if b["action"] == "dec":
		_step(int(b["data"]), -1)
	elif b["action"] == "inc":
		_step(int(b["data"]), 1)
	else:                              # back
		screen = Screen.MAIN
	root.queue_redraw()


func _step(row: int, dir: int) -> void:
	match row:
		0: map_index = wrapi(map_index + dir, 0, MAPS.size())
		1: difficulty_index = wrapi(difficulty_index + dir, 0, DIFFICULTIES.size())
		# Clamp tighter in TDM: bots are split across two teams and BOT_NAMES
		# only has 12 entries, so at most 6 per team.
		2: bot_count = clampi(bot_count + dir, 1, MAX_PER_TEAM if Game.is_tdm() else MAX_BOTS)
		3: match_minutes = clampi(match_minutes + dir, 1, 10)
		4: score_limit = clampi(score_limit + dir * 10, 10, 100)
	_apply_settings()
	Audio.play("switch", 0.8, -6.0)


func _play() -> void:
	close()
	play_pressed.emit()


# ------------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, size_px: int, col: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var p := pos
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px).x
		p.x -= w if align == HORIZONTAL_ALIGNMENT_RIGHT else w * 0.5
	for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		root.draw_string(font, p + d * 2.0, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px,
			Color(0, 0, 0, 0.9))
	root.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px, col)

## Draw a string in the pixel display face. `px` is the cell size; cap height
## is 7*px. Same 4-direction shadow as _text, then a per-cell fill in `col`.
func _pixel_text(pos: Vector2, s: String, px: int, col: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var w := PixelFace.measure(s) * px
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= w
	for d in [Vector2(-px, -px), Vector2(px, -px), Vector2(-px, px), Vector2(px, px)]:
		PixelFace.draw(func(r: Rect2): root.draw_rect(Rect2(r.position + d, r.size),
			Color(0, 0, 0, 0.9)), p, s, px)
	PixelFace.draw(func(r: Rect2): root.draw_rect(r, col), p, s, px)


## The classic Minecraft button: flat gray fill + white text, flipping to a
## bright fill + black text when hovered, with a drop shadow and thin top /
## bottom bevels (not a full-height gradient).
func _draw_button(r: Rect2, label: String, hot: bool) -> void:
	root.draw_rect(Rect2(r.position + Vector2(4, 4), r.size), Color(0, 0, 0, 0.5))
	root.draw_rect(r, Color(0, 0, 0, 0.9))
	var inner := Rect2(r.position + Vector2(2, 2), r.size - Vector2(4, 4))
	root.draw_rect(inner, Color(0.80, 0.80, 0.80) if hot else Color(0.31, 0.31, 0.31))
	root.draw_rect(Rect2(inner.position, Vector2(inner.size.x, 5)),
		Color(1, 1, 1, 0.40 if hot else 0.20))
	root.draw_rect(Rect2(inner.position + Vector2(0, inner.size.y - 5),
		Vector2(inner.size.x, 5)), Color(0, 0, 0, 0.30))
	var col: Color = Color(0, 0, 0) if hot else Color(1, 1, 1)
	var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30).x
	_text(r.position + Vector2((r.size.x - w) * 0.5, r.size.y * 0.5 + 11), label, 30, col)


func _draw_arrow(r: Rect2, glyph: String, hot: bool) -> void:
	root.draw_rect(Rect2(r.position + Vector2(3, 3), r.size), Color(0, 0, 0, 0.45))
	root.draw_rect(r, Color(0, 0, 0, 0.9))
	var inner := Rect2(r.position + Vector2(2, 2), r.size - Vector2(4, 4))
	root.draw_rect(inner, Color(0.80, 0.80, 0.80) if hot else Color(0.31, 0.31, 0.31))
	root.draw_rect(Rect2(inner.position, Vector2(inner.size.x, 5)),
		Color(1, 1, 1, 0.40 if hot else 0.20))
	root.draw_rect(Rect2(inner.position + Vector2(0, inner.size.y - 5),
		Vector2(inner.size.x, 5)), Color(0, 0, 0, 0.30))
	var col: Color = Color(0, 0, 0) if hot else Color(1, 1, 1)
	var w: float = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30).x
	_text(r.position + Vector2((r.size.x - w) * 0.5, r.size.y * 0.5 + 11), glyph, 30, col)


func _draw_ui() -> void:
	var size := get_viewport().get_visible_rect().size
	# dim the frozen arena panorama behind the menu
	root.draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.07, 0.78))

	if screen == Screen.MAIN:
		_draw_title(size, "BLOCKSHOT", 9, size.y * 0.28)
		var rects := _main_rects(size)
		var labels := ["PLAY", "SETTINGS", "QUIT GAME"]
		for i in 3:
			_draw_button(rects[i], labels[i], hovered == i)
		_text(Vector2(22, size.y - 20), "BLOCKSHOT  v0.9  ·  Godot 4.7", 18,
			Color(1, 1, 1, 0.5))
		_text(Vector2(size.x * 0.5, size.y - 20),
			"↑↓ to select   ·   ENTER to confirm", 18, Color(1, 1, 1, 0.4),
			HORIZONTAL_ALIGNMENT_CENTER)
		return

	_draw_title(size, "SETTINGS", 5, size.y * 0.18)
	var rows := _settings_rows(size)
	var labels := ["MAP", "BOT DIFFICULTY", "BOTS PER TEAM", "MATCH LENGTH", "SCORE LIMIT"]
	for i in 5:
		var r: Rect2 = rows[i]
		root.draw_rect(Rect2(r.position + Vector2(3, 3), r.size), Color(0, 0, 0, 0.35))
		root.draw_rect(r, Color(0.06, 0.08, 0.10, 0.6))
		_text(r.position + Vector2(20, r.size.y * 0.5 + 9), labels[i], 24, Color(1, 1, 1, 0.92))
		var geo := _stepper_geo(r, _row_value(i))
		var hot_left: bool = hovered >= 0 and _buttons[hovered]["rect"] == geo["left"]
		var hot_right: bool = hovered >= 0 and _buttons[hovered]["rect"] == geo["right"]
		_draw_arrow(geo["left"], "<", hot_left)
		_draw_arrow(geo["right"], ">", hot_right)
		_text(Vector2(geo["vx"], r.position.y + r.size.y * 0.5 + 9), _row_value(i), 26,
			Color8(255, 196, 66))
	var back := _back_rect(size)
	var back_idx: int = _buttons.size() - 1
	_draw_button(back, "BACK", hovered == back_idx)
	_text(Vector2(size.x * 0.5, back.position.y + BTN.y + 34),
		"ESC to return", 18, Color(1, 1, 1, 0.4), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_title(size: Vector2, s: String, px: int, cy: float) -> void:
	# Pixel display face: blocky white logo over a hard black slab shadow.
	# `px` is the cell size (cap height is 7*px): 9 -> 63px logo, 5 -> 35px header.
	_pixel_text(Vector2(size.x * 0.5 + px * 1.5, cy + px), s, px, Color(0, 0, 0, 0.85),
		HORIZONTAL_ALIGNMENT_CENTER)
	_pixel_text(Vector2(size.x * 0.5, cy), s, px, Color(1, 1, 1),
		HORIZONTAL_ALIGNMENT_CENTER)
