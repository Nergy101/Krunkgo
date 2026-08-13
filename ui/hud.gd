class_name Hud
extends CanvasLayer
## Everything drawn over the world.
##
## Layout is taken from direct inspection of
## reference/bar/krunker_citadel_viewmodel_01.jpg, which overrules the written
## research where they disagree:
##   top-left      timer chip, with game mode and map name underneath
##   bottom-left   health: value plus a SEGMENTED bar, not one continuous fill
##   bottom-right  ammo as "mag | reserve" in heavy digits with round pips
##   right edge    weapon list with [E] / [Q] hints
##   centre        four dashes with a wide gap and NO centre dot
##   under centre  movement speed readout
## Krunker's UI is heavy and outlined. We cannot ship a font, so the weight
## comes from a thick dark outline drawn as eight offset copies.

const WHITE := Color(1, 1, 1)
const DIM := Color(1, 1, 1, 0.55)
const OUTLINE := Color(0, 0, 0, 0.85)
const PANEL := Color(0.04, 0.05, 0.07, 0.62)
const HP_HIGH := Color8(126, 217, 87)
const HP_MID := Color8(232, 196, 66)
const HP_LOW := Color8(226, 66, 52)
const ACCENT := Color8(255, 196, 66)
const KILL_RED := Color8(232, 74, 58)

var root: Control
var font: Font
var player: Player

var hitmarker: float = 0.0
var hitmarker_head: bool = false
var hitmarker_kill: bool = false
var damage_dirs: Array = []
var killfeed: Array = []
var announce_text: String = ""
var announce_life: float = 0.0
var flash: float = 0.0
var hp: float = 100.0
var hp_max: float = 100.0
var hp_display: float = 100.0
var mag: int = 0
var reserve: int = 0
var mag_size: int = 1
var weapon_name: String = ""
var weapon_key: String = ""
var show_scoreboard: bool = false
var dead_time: float = 0.0
var match_over: bool = false
var my_kills: int = 0
var leader: Dictionary = {}

func _ready() -> void:
	layer = 10
	font = ThemeDB.fallback_font
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.draw.connect(_draw_hud)
	add_child(root)

	Game.hit_confirmed.connect(_on_hit)
	Game.health_changed.connect(func(h, m): hp = h; hp_max = m)
	Game.ammo_changed.connect(func(m, r): mag = m; reserve = r)
	Game.weapon_changed.connect(_on_weapon)
	Game.local_damaged.connect(_on_damaged)
	Game.kill_registered.connect(_on_kill)
	Game.local_spawned.connect(func(p): player = p; dead_time = 0.0)
	Game.local_died.connect(func(_k): dead_time = Tuning.respawn_delay)
	Game.announce.connect(func(t, _k): announce_text = t; announce_life = 2.4)
	# game.gd's header says feedback MUST listen on the bus, then the HUD polled
	# Game.running and Game.scores every frame and left these two emitted-but-
	# unconnected. Cached here so _draw runs off state, not per-frame lookups.
	Game.match_ended.connect(_on_match_ended)
	Game.score_changed.connect(_on_score_changed)
	_on_score_changed()

func _on_match_ended() -> void:
	match_over = true
	announce_text = "MATCH OVER"
	announce_life = 4.0

func _on_score_changed() -> void:
	my_kills = int(Game.scores.get("YOU", {}).get("kills", 0))
	var board := Game.leaderboard()
	leader = board[0] if board.size() > 0 else {}

func _on_weapon(d: Dictionary) -> void:
	weapon_name = String(d.get("display", ""))
	weapon_key = String(d.get("key", ""))
	mag_size = maxi(1, int(d.get("mag", 1)))

func _process(delta: float) -> void:
	hitmarker = maxf(0.0, hitmarker - delta * 2.6)
	flash = maxf(0.0, flash - delta * 3.0)
	announce_life = maxf(0.0, announce_life - delta)
	dead_time = maxf(0.0, dead_time - delta)
	hp_display = lerpf(hp_display, hp, clampf(delta * 9.0, 0.0, 1.0))
	var i := damage_dirs.size() - 1
	while i >= 0:
		damage_dirs[i]["life"] -= delta
		if damage_dirs[i]["life"] <= 0.0:
			damage_dirs.remove_at(i)
		i -= 1
	i = killfeed.size() - 1
	while i >= 0:
		killfeed[i]["life"] -= delta
		if killfeed[i]["life"] <= 0.0:
			killfeed.remove_at(i)
		i -= 1
	show_scoreboard = Input.is_action_pressed("scoreboard") or match_over
	root.queue_redraw()

func _on_hit(head: bool, _dmg: float, _pos: Vector3, killed: bool) -> void:
	hitmarker = 1.0
	hitmarker_head = head
	hitmarker_kill = killed

func _on_damaged(from_dir: Vector3, amount: float) -> void:
	damage_dirs.append({"dir": from_dir, "life": 1.2})
	flash = maxf(flash, clampf(amount / 60.0, 0.2, 0.9))

func _on_kill(attacker: String, victim: String, _weapon: String, head: bool) -> void:
	killfeed.append({"a": attacker, "v": victim, "life": 5.5, "head": head})
	if killfeed.size() > 6:
		killfeed.pop_front()

# ---------------------------------------------------------------------- text
## Krunker's HUD type is heavy and hard-outlined. Eight offset copies is the
## only way to fake that weight without shipping a font file.
func _text(pos: Vector2, s: String, size: int, col: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, outline := 2.0) -> void:
	var p := pos
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
		p.x -= w if align == HORIZONTAL_ALIGNMENT_RIGHT else w * 0.5
	if outline > 0.0:
		for d in [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0),
				Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]:
			root.draw_string(font, p + d * outline, s, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, size, OUTLINE)
	root.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, col)

func _text_w(s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x

# ---------------------------------------------------------------------- draw
func _draw_hud() -> void:
	var size := get_viewport().get_visible_rect().size
	var c := size * 0.5

	if flash > 0.0:
		root.draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.05, 0.05, flash * 0.26))

	# The scope surround is opaque and covers the whole screen bar the aperture,
	# so it has to go down before the HUD or it hides the match chip.
	_draw_scope(size, c)
	_draw_match_chip()
	_draw_crosshair(c)
	_draw_hitmarker(c)
	_draw_speed(c)
	_draw_health(size)
	_draw_ammo(size)
	_draw_weapon_list(size)
	_draw_killfeed(size)
	_draw_damage_dirs(c)
	if show_scoreboard:
		_draw_scoreboard(size)
	if dead_time > 0.0:
		_text(Vector2(c.x, c.y - 70), "RESPAWNING", 36, ACCENT, HORIZONTAL_ALIGNMENT_CENTER, 3.0)
	if announce_life > 0.0:
		var a: float = clampf(announce_life, 0.0, 1.0)
		_text(Vector2(c.x, size.y * 0.28), announce_text, 42,
			Color(ACCENT.r, ACCENT.g, ACCENT.b, a), HORIZONTAL_ALIGNMENT_CENTER, 3.0)

## Top-left, matching the reference: a dark chip holding the clock, with the
## mode and map underneath in small dim text.
func _draw_match_chip() -> void:
	var mins := int(Game.time_left) / 60
	var secs := int(Game.time_left) % 60
	var clock := "%d:%02d" % [mins, secs]
	var w: float = _text_w(clock, 34) + 34.0
	root.draw_rect(Rect2(Vector2(22, 18), Vector2(w, 42)), PANEL)
	root.draw_rect(Rect2(Vector2(22, 18), Vector2(4, 42)), ACCENT)
	_text(Vector2(38, 50), clock, 34, WHITE)
	_text(Vector2(24, 76), "FREE FOR ALL", 16, WHITE)
	_text(Vector2(24, 94), "on BURG", 15, DIM)
	_text(Vector2(24, 122), "%d / %d" % [my_kills, Tuning.score_limit], 20, ACCENT)

## Four dashes, wide gap, no centre dot. The gap tracks real weapon spread, so
## the crosshair doubles as the accuracy readout.
##
## Sizes are measured off the reference shots, not guessed. At 576h Krunker
## rests at a 36px gap with 10px dashes (16% of screen height) and opens to a
## 110px gap at full spread. Normalised to our 900h that is a 56px resting gap
## with 16px dashes. The first pass used 7 and 7, roughly a quarter of the
## real footprint, which read as a generic engine crosshair.
func _draw_crosshair(c: Vector2) -> void:
	# Clamped to Krunker's measured open radius (109 px at 576h -> 170 at 900h).
	# Unclamped this reached 116 on the rifle and ~313 on a moving shotgun, and
	# the bottom dash then collided with the speed readout.
	if player == null or not player.alive:
		return
	var gap := 22.0
	var fade := 1.0
	if player and player.weapon:
		gap = minf(20.0 + player.weapon.spread_degrees() * 12.0, 170.0)
		# Aiming replaces the crosshair with the weapon's own sights, which now
		# sit on the camera axis. Leaving both up gave two competing aim points.
		# Was faded to nothing on ADS, which left the iron-sight frames with no
		# reticle at all. Krunker keeps its crosshair up while aiming; only a
		# scope replaces it, and the scope draws its own.
		var scoped: bool = bool(player.weapon.def.get("scoped", false))
		fade = 0.0 if scoped else 1.0 - 0.45 * clampf(player.weapon.ads_amount, 0.0, 1.0)
	if fade <= 0.01:
		return
	var length := 16.0
	var line := Color(WHITE.r, WHITE.g, WHITE.b, fade)
	# The dark edge is what makes the reticle readable on bright stone. Dimming it
	# with the crosshair dropped contrast faster than opacity and partly undid
	# the ADS-visibility fix it was part of, so it keeps a floor.
	var edge := Color(OUTLINE.r, OUTLINE.g, OUTLINE.b, OUTLINE.a * maxf(fade, 0.8))
	for v in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		var a: Vector2 = c + v * gap
		var b: Vector2 = c + v * (gap + length)
		root.draw_line(a + Vector2(1.5, 1.5), b + Vector2(1.5, 1.5), edge, 5.0)
		root.draw_line(a, b, line, 2.6)

## Looking through the sniper optic. The crosshair is hidden while aiming, so a
## scoped weapon has to supply its own aim point or you are firing blind.
## The surround is drawn as one very thick arc: Godot cannot punch a hole in a
## filled rect, but a ring whose inner edge is the aperture and whose outer edge
## runs past the corners gets there in a single call.
func _draw_scope(size: Vector2, c: Vector2) -> void:
	if player == null or player.weapon == null or not player.alive:
		return
	if not bool(player.weapon.def.get("scoped", false)):
		return
	var t: float = clampf(player.weapon.ads_amount * 1.25, 0.0, 1.0)
	if t <= 0.01:
		return
	var r: float = minf(size.x, size.y) * 0.345
	var band: float = size.length()
	root.draw_arc(c, r + band * 0.5, 0.0, TAU, 96, Color(0, 0, 0, t), band)

	# fine reticle: four hairlines with a gap, a centre dot, and range ticks
	var line := Color(0.06, 0.06, 0.06, t)
	for v in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		root.draw_line(c + v * 26.0, c + v * r, line, 1.5)
	for i in range(1, 4):
		var y: float = c.y + float(i) * 26.0
		var half: float = 9.0 - float(i) * 2.0
		root.draw_line(Vector2(c.x - half, y), Vector2(c.x + half, y), line, 1.5)
	root.draw_circle(c, 2.0, line)
	# soft inner edge so the aperture does not read as a hard cut-out
	root.draw_arc(c, r - 3.0, 0.0, TAU, 96, Color(0, 0, 0, t * 0.5), 6.0)

func _draw_hitmarker(c: Vector2) -> void:
	if hitmarker <= 0.0:
		return
	var col: Color = KILL_RED if hitmarker_kill else (ACCENT if hitmarker_head else WHITE)
	col.a = clampf(hitmarker, 0.0, 1.0)
	var r: float = 8.0 + (1.0 - hitmarker) * 6.0
	var w: float = 3.0 if hitmarker_kill else 2.2
	for d in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		root.draw_line(c + d * r * 0.55, c + d * (r + 6.0), col, w)

func _draw_speed(c: Vector2) -> void:
	if player == null:
		return
	var spd: float = player.motor.speed_flat
	var over: bool = spd > Tuning.max_ground_speed + 0.5
	# clear of the 186 px maximum dash extent, not merely below the resting one
	_text(Vector2(c.x, c.y + 200), "%d" % int(round(spd * 10.0)), 19,
		ACCENT if over else DIM, HORIZONTAL_ALIGNMENT_CENTER)

## Bottom-left. Segmented, because you can count remaining chunks at a glance
## in a fight in a way you cannot read a continuous bar.
func _draw_health(size: Vector2) -> void:
	const SEGMENTS := 5
	var pad := 26.0
	var bw := 30.0
	var bh := 30.0
	var gap := 5.0
	var pos := Vector2(pad, size.y - pad - bh)
	var frac: float = clampf(hp_display / maxf(1.0, hp_max), 0.0, 1.0)
	var col: Color = HP_LOW if frac < 0.3 else (HP_MID if frac < 0.6 else HP_HIGH)
	for i in SEGMENTS:
		var seg := Rect2(pos + Vector2(i * (bw + gap), 0), Vector2(bw, bh))
		root.draw_rect(Rect2(seg.position + Vector2(2, 2), seg.size), OUTLINE)
		root.draw_rect(seg, Color(0, 0, 0, 0.5))
		var lo: float = float(i) / SEGMENTS
		var fill: float = clampf((frac - lo) * SEGMENTS, 0.0, 1.0)
		if fill > 0.0:
			root.draw_rect(Rect2(seg.position, Vector2(seg.size.x * fill, seg.size.y)), col)
	_text(pos + Vector2(0, -12), "%d" % int(ceil(hp)), 34, WHITE)
	_text(pos + Vector2(_text_w("%d" % int(ceil(hp)), 34) + 10, -14), "| %d" % int(hp_max), 18, DIM)

## Bottom-right. Krunker draws "mag | reserve" in heavy digits with the round
## pips INLINE to their right — measured off krunker_citadel_viewmodel_01.jpg,
## where the whole chip is 85x38 in a 1025x576 frame, flush to the right edge
## and 13 px clear of the bottom. Ours stacked the pips underneath the digits
## and ran them off the bottom of the screen entirely.
func _draw_ammo(size: Vector2) -> void:
	var pad := 26.0
	var pips: int = mini(mag_size, 12)
	var pitch: float = 10.0
	var pip_h: float = 26.0
	var digit_px: int = 40

	# Lay the row out from the right edge inward, then wrap the chip around it,
	# so nothing can spill past a hard-coded panel again.
	var right: float = size.x - pad
	var bottom: float = size.y - pad
	var pip_left: float = right - float(pips) * pitch
	var text_right: float = pip_left - 14.0
	var mag_s := str(mag)
	var reserve_s := "| %d" % reserve
	var text_w: float = _text_w(mag_s, digit_px) + _text_w(reserve_s, 24) + 12.0
	# chip_l is derived from text_w, so both strings must be measured before it
	var chip_l: float = text_right - text_w - 12.0
	var chip_t: float = bottom - float(digit_px) - 20.0
	root.draw_rect(Rect2(Vector2(chip_l, chip_t),
		Vector2(right + 10.0 - chip_l, bottom - chip_t)), PANEL)

	var mid: float = chip_t + (bottom - chip_t) * 0.5
	var low: bool = mag <= maxi(1, mag_size / 4)
	var mag_col: Color = KILL_RED if mag == 0 else (ACCENT if low else WHITE)
	var text_y: float = mid + float(digit_px) * 0.36
	# Reference order is mag then reserve, left to right ("3|3"); ours had the
	# reserve on the left, which reads as the wrong number being the big one.
	_text(Vector2(text_right, text_y - 4.0), reserve_s, 24, DIM,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(text_right - _text_w(reserve_s, 24) - 12.0, text_y), mag_s,
		digit_px, mag_col, HORIZONTAL_ALIGNMENT_RIGHT, 3.0)

	var shown: int = int(round(float(mag) / float(mag_size) * pips))
	for i in pips:
		var r := Rect2(Vector2(pip_left + float(i) * pitch, mid - pip_h * 0.5),
			Vector2(pitch - 3.0, pip_h))
		root.draw_rect(Rect2(r.position + Vector2(2, 2), r.size), OUTLINE)
		root.draw_rect(r, ACCENT if i < shown else Color(1, 1, 1, 0.20))

	if player and player.weapon and player.weapon.reload_left > 0.0:
		var t: float = 1.0 - player.weapon.reload_left / maxf(0.01, float(player.weapon.def["reload"]))
		var bar := Rect2(Vector2(size.x * 0.5 - 90, size.y * 0.60), Vector2(180, 8))
		root.draw_rect(Rect2(bar.position + Vector2(2, 2), bar.size), OUTLINE)
		root.draw_rect(bar, Color(0, 0, 0, 0.55))
		root.draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), ACCENT)
		_text(Vector2(size.x * 0.5, size.y * 0.60 - 10), "RELOADING", 20, WHITE,
			HORIZONTAL_ALIGNMENT_CENTER)

## Right edge: which gun is up, and the keys for the others.
func _draw_weapon_list(size: Vector2) -> void:
	var y := size.y * 0.74
	var hints := ["[1]", "[2]", "[3]"]
	var slots: Array = player.loadout if player else [WeaponDefs.SECONDARY]
	for i in mini(3, slots.size()):
		var key: String = String(slots[i])
		var active: bool = key == weapon_key
		var label: String = String(WeaponDefs.LIST[key]["display"])
		var col: Color = WHITE if active else Color(1, 1, 1, 0.32)
		if active:
			root.draw_rect(Rect2(Vector2(size.x - 200, y - 15), Vector2(178, 24)),
				Color(0, 0, 0, 0.35))
			root.draw_rect(Rect2(Vector2(size.x - 200, y - 15), Vector2(3, 24)), ACCENT)
		_text(Vector2(size.x - 30, y), label, 15, col, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(Vector2(size.x - 196, y), hints[i], 14,
			ACCENT if active else Color(1, 1, 1, 0.3))
		y += 30.0

func _draw_killfeed(size: Vector2) -> void:
	var y := 42.0
	for k in killfeed:
		var a: float = clampf(k["life"], 0.0, 1.0)
		var mine: bool = k["a"] == "YOU"
		var killed: bool = k["v"] == "YOU"
		var col: Color = ACCENT if mine else (KILL_RED if killed else WHITE)
		col.a = a
		var mark: String = " >> " if not k["head"] else " >X> "
		_text(Vector2(size.x - 26, y), String(k["a"]) + mark + String(k["v"]), 17, col,
			HORIZONTAL_ALIGNMENT_RIGHT)
		y += 25.0

func _draw_damage_dirs(c: Vector2) -> void:
	if player == null:
		return
	for d in damage_dirs:
		var v: Vector3 = d["dir"]
		var ang: float = atan2(v.x, v.z) - player.yaw + PI
		var a: float = clampf(d["life"], 0.0, 1.0)
		var col := Color(0.95, 0.22, 0.16, a)
		var out := Vector2(sin(ang), -cos(ang))
		var tan := Vector2(out.y, -out.x)
		# a filled arc-wedge reads instantly; two crossed lines did not
		var tip: Vector2 = c + out * 74.0
		root.draw_colored_polygon(PackedVector2Array([
			tip, c + out * 104.0 + tan * 26.0, c + out * 104.0 - tan * 26.0]), col)

func _draw_scoreboard(size: Vector2) -> void:
	var board := Game.leaderboard()
	var w := 480.0
	var h: float = 64.0 + board.size() * 30.0
	var pos := Vector2((size.x - w) * 0.5, (size.y - h) * 0.38)
	root.draw_rect(Rect2(pos, Vector2(w, h)), Color(0.03, 0.04, 0.06, 0.86))
	root.draw_rect(Rect2(pos, Vector2(w, 4)), ACCENT)
	_text(pos + Vector2(20, 38), "FREE FOR ALL", 20, ACCENT)
	_text(pos + Vector2(w - 130, 38), "K", 18, DIM)
	_text(pos + Vector2(w - 60, 38), "D", 18, DIM)
	var y := 68.0
	for row in board:
		var mine: bool = row["name"] == "YOU"
		if mine:
			root.draw_rect(Rect2(pos + Vector2(8, y - 18), Vector2(w - 16, 26)),
				Color(1, 0.77, 0.26, 0.14))
		var col: Color = ACCENT if mine else WHITE
		_text(pos + Vector2(20, y), String(row["name"]), 19, col)
		_text(pos + Vector2(w - 130, y), str(row["kills"]), 19, col)
		_text(pos + Vector2(w - 60, y), str(row["deaths"]), 19, col)
		y += 30.0
