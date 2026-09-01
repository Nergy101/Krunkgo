class_name Player
extends Actor
## Local player: input, camera, viewmodel, and every piece of feedback that
## makes a shot feel like it connected.

var camera: Camera3D
var viewmodel: Viewmodel
var input_enabled: bool = true

var shake: float = 0.0
var land_dip: float = 0.0
var roll: float = 0.0
var look_delta := Vector2.ZERO
var _mouse_accum := Vector2.ZERO
var _fov_current: float = 90.0
var _reload_total: float = 0.0
var _step_dist: float = 0.0
var _melee_cd: float = 0.0
var _slot: int = 0
## Primary from the chosen class, plus the pistol everyone carries.
var loadout: Array = ["assault", WeaponDefs.SECONDARY]
var class_id: String = "trigger"

func _ready() -> void:
	display_name = "YOU"
	# In Team Deathmatch the local player is always on the blue team and wears
	# blue; set it here, before super._ready() builds the body from tint.
	if Game.is_tdm():
		team = Game.TEAM_BLUE
		tint = Blockman.team_color(Game.TEAM_BLUE)
	else:
		tint = Color8(228, 232, 238)
	super._ready()
	hide_body_from_own_camera()

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = Tuning.fov
	camera.near = 0.03
	camera.far = 400.0
	camera.cull_mask = 0xFFFFF & ~LAYER_SELF_BODY
	camera.current = true
	add_child(camera)
	_fov_current = Tuning.fov

	# The viewmodel renders through its own SubViewport rather than sitting in
	# the world as a child of the camera, so a long barrel can never clip
	# through the wall you are standing against.
	viewmodel = Viewmodel.build_rig(self)
	viewmodel.build_for(loadout[_slot])

	weapon.equip(loadout[_slot])
	weapon.fired.connect(_on_fired)
	weapon.landed.connect(_on_landed)
	weapon.missed.connect(_on_missed)
	weapon.ammo_changed.connect(func(m, r): Game.ammo_changed.emit(m, r))
	weapon.reload_started.connect(_on_reload_started)
	weapon.switched.connect(func(d): Game.weapon_changed.emit(d))

	damaged.connect(_on_damaged)
	health_changed.connect(func(hp): Game.health_changed.emit(hp, Tuning.max_health))
	died.connect(func(_k): Game.local_died.emit(killer_name))

	Game.local_player = self
	Game.local_spawned.emit(self)
	Game.weapon_changed.emit(weapon.def)
	Game.ammo_changed.emit(weapon.mag, weapon.reserve)
	Game.health_changed.emit(health, Tuning.max_health)

## Applied on spawn. The primary comes from the class; the pistol is constant.
func set_class(id: String) -> void:
	class_id = id
	loadout = [WeaponDefs.class_primary(id), WeaponDefs.SECONDARY]
	_slot = 0
	if weapon:
		weapon.equip(loadout[0])
		weapon.switch_left = 0.0
	if viewmodel:
		viewmodel.build_for(loadout[0])

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_mouse_accum += mm.relative
		# Scale with the zoom, or a 3.8x scope would swing 3.8x too fast and be
		# unusable. This is the standard zoom-proportional model.
		var sens: float = Tuning.mouse_sensitivity * (_fov_current / Tuning.fov)
		yaw -= mm.relative.x * sens
		pitch = clampf(pitch - mm.relative.y * sens, -Tuning.pitch_limit, Tuning.pitch_limit)

## Harness autopilot. Screenshots of a first-person shooter have to be taken
## from a first-person view that is actually fighting; with no input the player
## just stared at a wall with frozen HP and ammo, which made every visual
## critique worthless. This drives the real player through the real Motor and
## Weapon, so the HUD, viewmodel, recoil and feedback are all genuine.
var autopilot: BotBrain = null
var _auto_strafe: float = 1.0
var _auto_timer: float = 0.0

func enable_autopilot() -> void:
	autopilot = BotBrain.new()
	autopilot.bot = self
	autopilot.skill = 1.15
	autopilot.burst_left = 6

func _autopilot_step(delta: float) -> void:
	autopilot.think(delta, Game.actors)
	_auto_timer -= delta
	if _auto_timer <= 0.0:
		_auto_timer = randf_range(0.6, 1.6)
		_auto_strafe = -_auto_strafe

	var wish := Vector3.ZERO
	var t: Actor = autopilot.target
	if autopilot.state == BotBrain.State.ENGAGE and is_instance_valid(t):
		var to: Vector3 = t.global_position - global_position
		to.y = 0.0
		var fwd := to.normalized()
		var side := Vector3(-fwd.z, 0, fwd.x) * _auto_strafe
		wish = fwd * clampf((to.length() - 11.0) / 9.0, -1.0, 1.0) + side
		var aim_at: Vector3 = t.eye_position() + t.velocity * 0.04
		var d: Vector3 = aim_at - eye_position()
		yaw = lerp_angle(yaw, atan2(-d.x, -d.z), clampf(delta * 11.0, 0.0, 1.0))
		pitch = lerpf(pitch, atan2(d.y, Vector2(d.x, d.z).length()), clampf(delta * 11.0, 0.0, 1.0))
		# Aim down sights at range like a player would; this is also what puts
		# ADS into the captured screenshots so it can be reviewed at all.
		weapon.ads = to.length() > 12.0
		if autopilot.wants_to_shoot() and weapon.try_fire():
			autopilot.note_shot(weapon.def)
	else:
		var arena := Game.arena as MapBuilder
		if arena and _auto_timer > 1.4:
			var goal: Vector3 = arena.spawn_points[Game.rng.randi() % arena.spawn_points.size()]
			var d2: Vector3 = goal - global_position
			d2.y = 0.0
			if d2.length() > 2.0:
				yaw = lerp_angle(yaw, atan2(-d2.x, -d2.z), clampf(delta * 3.0, 0.0, 1.0))
		wish = Basis.from_euler(Vector3(0, yaw, 0)) * Vector3(0.35 * _auto_strafe, 0, -1)
		pitch = lerpf(pitch, 0.0, clampf(delta * 3.0, 0.0, 1.0))
	if weapon.mag <= 0:
		weapon.start_reload()
	var moving_fast: bool = motor.speed_flat > Tuning.slide_min_speed
	motor.step(wish, moving_fast, moving_fast and autopilot.state != BotBrain.State.ENGAGE, delta)
	_place_hitboxes()

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if autopilot:
		_autopilot_step(delta)
		return
	var wish := Vector3.ZERO
	var active: bool = input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if active:
		# Deliberately NOT Input.get_vector: that normalises, which would throw
		# away the diagonal length the motor reads as Krunker's strafe bonus.
		var ax := Vector3(
			float(Input.is_action_pressed("move_right")) - float(Input.is_action_pressed("move_left")),
			0.0,
			float(Input.is_action_pressed("move_back")) - float(Input.is_action_pressed("move_forward")))
		wish = Basis.from_euler(Vector3(0, yaw, 0)) * ax
	var want_jump: bool = active and (Input.is_action_pressed("jump") if Tuning.auto_bhop
		else Input.is_action_just_pressed("jump"))
	var want_crouch: bool = active and Input.is_action_pressed("crouch")

	var was_air := not motor.grounded
	motor.step(wish, want_jump, want_crouch, delta)
	_place_hitboxes()

	if motor.jumped_this_tick:
		Audio.play("jump", randf_range(0.95, 1.05), -14.0)
	if motor.landed_hard > 0.0 and was_air:
		land_dip = Tuning.land_kick * (0.4 + motor.landed_hard)
		Audio.play("land", randf_range(0.9, 1.1), -10.0 + motor.landed_hard * 6.0)
	if motor.grounded and motor.speed_flat > 1.0 and not motor.sliding:
		_step_dist += motor.speed_flat * delta
		if _step_dist > 2.0:
			_step_dist = 0.0
			Audio.play("step", randf_range(0.85, 1.2), -19.0)

func _process(delta: float) -> void:
	_melee_cd = maxf(0.0, _melee_cd - delta)
	var active: bool = alive and input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if active:
		_handle_actions()
	if autopilot == null:
		weapon.ads = active and Input.is_action_pressed("aim")
	_update_camera(delta)
	_animate_body(delta)
	_regen(delta)
	look_delta = _mouse_accum
	_mouse_accum = Vector2.ZERO

func _handle_actions() -> void:
	var pressed: bool = Input.is_action_pressed("fire") if bool(weapon.def["auto"]) \
		else Input.is_action_just_pressed("fire")
	if pressed and not weapon.try_fire() and weapon.mag <= 0 and weapon.reload_left <= 0.0:
		Audio.play("dryfire", randf_range(0.96, 1.05), -12.0)
	if Input.is_action_just_pressed("reload"):
		weapon.start_reload()
	if Input.is_action_just_pressed("melee") and _melee_cd <= 0.0:
		_melee_cd = Tuning.melee_cooldown
		viewmodel.punch(0.5)
		Audio.play("switch", 0.8, -10.0)
		weapon.try_melee()
	for i in mini(3, loadout.size()):
		if Input.is_action_just_pressed("slot_%d" % (i + 1)):
			_switch(i)
	if Input.is_action_just_pressed("next_weapon"):
		_switch((_slot + 1) % loadout.size())

func _switch(i: int) -> void:
	if i == _slot or i >= loadout.size():
		return
	_slot = i
	var key: String = String(loadout[i])
	weapon.equip(key)
	viewmodel.build_for(key)
	Audio.play("switch", 1.0, -8.0)

func _update_camera(delta: float) -> void:
	var b := aim_basis()
	var eu := b.get_euler()
	land_dip = move_toward(land_dip, 0.0, delta * 0.55)
	shake = move_toward(shake, 0.0, delta * 3.2)

	var strafe: float = clampf(velocity.dot(b.x) / maxf(1.0, Tuning.max_ground_speed), -1.0, 1.0)
	var slide_lean: float = Tuning.roll_amount * 2.4 if motor.sliding else 0.0
	roll = lerpf(roll, -strafe * Tuning.roll_amount + slide_lean, clampf(delta * 9.0, 0.0, 1.0))

	var shake_off := Vector3.ZERO
	if shake > 0.001:
		shake_off = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.02

	camera.position = Vector3(0, motor.eye_offset() - land_dip, 0) + shake_off
	camera.rotation = Vector3(eu.x, eu.y, roll + shake * 0.01)

	var speed_ratio: float = motor.speed_flat / maxf(1.0, Tuning.max_ground_speed)
	var over: float = (motor.speed_flat - Tuning.max_ground_speed) \
		/ maxf(1.0, Tuning.hard_speed_cap - Tuning.max_ground_speed)
	var target_fov: float = Tuning.fov + Tuning.fov_speed_bonus * clampf(over, 0.0, 1.0)
	var ads_mult: float = float(weapon.def.get("ads_fov", Tuning.ads_fov_mult))
	target_fov = lerpf(target_fov, Tuning.fov * ads_mult, weapon.ads_amount)
	_fov_current = lerpf(_fov_current, target_fov, clampf(delta * 12.0, 0.0, 1.0))
	camera.fov = _fov_current

	var reload_t: float = 0.0
	if weapon.reload_left > 0.0 and _reload_total > 0.0:
		reload_t = 1.0 - (weapon.reload_left / _reload_total)
	viewmodel.update_view(delta, speed_ratio, motor.grounded, weapon.ads_amount,
		look_delta, reload_t)
	# Fully scoped, the optic body would sit in the middle of its own sight
	# picture. Once the scope overlay has taken over, drop the weapon entirely
	# so the aperture shows clean world, which is what looking through a scope
	# looks like.
	var scoped: bool = bool(weapon.def.get("scoped", false))
	# Dead players hold no gun. Leaving the viewmodel and crosshair up while the
	# respawn timer runs reads as though you are still in the fight.
	viewmodel.visible = alive and not (scoped and weapon.ads_amount > 0.55)
	viewmodel.sync_size(Vector2i(get_viewport().get_visible_rect().size))

# ------------------------------------------------------------------ feedback
func _on_fired(d: Dictionary, _muzzle: Vector3, _dir: Vector3) -> void:
	viewmodel.punch(float(d["kick"]))
	shake = maxf(shake, float(d["shake"]))
	Audio.play(String(d["tone"]), float(d["pitch"]) * randf_range(0.97, 1.03), -4.0)
	if Game.fx:
		var mp: Vector3 = weapon.muzzle_position()
		Game.fx.muzzle_flash(mp, float(d["muzzle_flash"]))
		Game.fx.eject_shell(mp - aim_dir() * 0.25, aim_basis(),
			d.get("shell_color", Color8(200, 158, 76)), float(d.get("shell_scale", 1.0)))
	if bool(d.get("has_bolt", false)):
		# bolt cycles after the shot, not with it
		Audio.play("bolt", randf_range(0.95, 1.06), -11.0)
	if weapon.mag > 0 and weapon.mag <= maxi(1, int(d["mag"]) / 5):
		Audio.play("low_ammo", 1.0, -16.0)

func _on_landed(zone: int, dmg: float, pos: Vector3, normal: Vector3, _victim: Actor, killed: bool) -> void:
	var head: bool = zone == Hitbox.Zone.HEAD
	if Game.fx:
		Game.fx.tracer(weapon.muzzle_position(), pos, 1.0)
		Game.fx.impact(pos, normal, Color8(240, 90, 80))
		Game.fx.damage_number(pos + Vector3(0, 0.25, 0), dmg, head)
	Audio.play("hit_head" if head else "hit", randf_range(0.98, 1.02), -6.0)
	if killed:
		Audio.play("kill", 1.0, -4.0)
	Game.hit_confirmed.emit(head, dmg, pos, killed)

func _on_missed(pos: Vector3, normal: Vector3) -> void:
	if Game.fx:
		Game.fx.tracer(weapon.muzzle_position(), pos, 1.0)
		Game.fx.impact(pos, normal, Color8(210, 205, 195))
	Audio.play_at("impact", pos, randf_range(0.9, 1.15), -16.0)

func _on_reload_started(seconds: float) -> void:
	_reload_total = seconds
	Audio.play("mag_out", randf_range(0.96, 1.04), -9.0)
	await get_tree().create_timer(seconds * 0.55).timeout
	Audio.play("mag_in", randf_range(0.96, 1.04), -8.0)
	await get_tree().create_timer(seconds * 0.30).timeout
	Audio.play("bolt", randf_range(0.98, 1.06), -13.0)

func _on_damaged(amount: float, from_dir: Vector3) -> void:
	shake = maxf(shake, clampf(amount / 40.0, 0.15, 0.9))
	Audio.play("hurt", randf_range(0.95, 1.05), -8.0)
	Game.local_damaged.emit(from_dir, amount)
