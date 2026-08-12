class_name Weapon
extends Node3D
## Hitscan gun logic shared by player and bots. Owns ammo, cadence, spread,
## recoil and the raycast. Feedback (tracer, flash, shake, sound) is fired
## through signals so the weapon-feedback slice can change look without
## touching ballistics, and the hit-registration slice can change the raycast
## without touching feel.

signal fired(def: Dictionary, muzzle_pos: Vector3, dir: Vector3)
signal landed(zone: int, damage: float, pos: Vector3, normal: Vector3, victim: Actor, killed: bool)
signal missed(pos: Vector3, normal: Vector3)
signal ammo_changed(mag: int, reserve: int)
signal reload_started(seconds: float)
signal switched(def: Dictionary)

var owner_actor: Actor
var def: Dictionary = {}
var slot: int = 0
var mag: int = 0
var reserve: int = 0
var cooldown: float = 0.0
var reload_left: float = 0.0
var switch_left: float = 0.0
var recoil_pitch: float = 0.0
var recoil_yaw: float = 0.0
var bloom: float = 0.0                 # extra spread from sustained fire
var ads: bool = false
var ads_amount: float = 0.0
var shots_in_burst: int = 0

func _ready() -> void:
	equip(WeaponDefs.LOADOUT[0])

func equip(key: String) -> void:
	def = WeaponDefs.get_def(key)
	mag = int(def["mag"])
	reserve = int(def["reserve"])
	reload_left = 0.0
	switch_left = float(def["switch"])
	bloom = 0.0
	shots_in_burst = 0
	switched.emit(def)
	ammo_changed.emit(mag, reserve)

func refill() -> void:
	mag = int(def["mag"])
	reserve = int(def["reserve"])
	reload_left = 0.0
	ammo_changed.emit(mag, reserve)

func busy() -> bool:
	return cooldown > 0.0 or reload_left > 0.0 or switch_left > 0.0

func can_fire() -> bool:
	return mag > 0 and not busy() and owner_actor and owner_actor.alive

func _process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	switch_left = maxf(0.0, switch_left - delta)
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			var need: int = int(def["mag"]) - mag
			var take: int = mini(need, reserve)
			mag += take
			reserve -= take
			ammo_changed.emit(mag, reserve)
	var rec := float(def["recoil"]["recover"])
	recoil_pitch = move_toward(recoil_pitch, 0.0, rec * delta)
	recoil_yaw = move_toward(recoil_yaw, 0.0, rec * delta)
	bloom = maxf(0.0, bloom - delta * 3.0)
	if shots_in_burst > 0 and cooldown <= 0.0:
		shots_in_burst = maxi(0, shots_in_burst - 1)
	ads_amount = move_toward(ads_amount, 1.0 if ads else 0.0, delta / maxf(0.01, Tuning.ads_time))

func start_reload() -> void:
	if reload_left > 0.0 or mag >= int(def["mag"]) or reserve <= 0:
		return
	reload_left = float(def["reload"])
	reload_started.emit(reload_left)

## True when this shot is a disciplined opener: stationary, aimed, no residual
## bloom and not continuing a burst. Only then does the cone collapse to zero.
func is_first_shot() -> bool:
	if owner_actor == null or not ads or ads_amount < 0.85:
		return false
	if shots_in_burst > 0 or bloom > 0.01:
		return false
	return owner_actor.motor.speed_flat < 0.6 and owner_actor.motor.grounded

## Current cone half-angle in degrees, before random sampling.
func spread_degrees() -> float:
	var base: float = lerpf(float(def["spread_hip"]), float(def["spread_ads"]), ads_amount)
	var move: float = 0.0
	if owner_actor:
		var s: float = owner_actor.motor.speed_flat / maxf(1.0, Tuning.max_ground_speed)
		move = float(def["spread_move"]) * clampf(s, 0.0, 1.6)
		if not owner_actor.motor.grounded:
			move *= 1.8
	return base + move + bloom

func try_fire() -> bool:
	if not can_fire():
		if mag <= 0 and reload_left <= 0.0:
			start_reload()
		return false
	# Evaluate the opener BEFORE bookkeeping: shots_in_burst is incremented on
	# this shot, so asking afterwards always reported "mid-burst" and the
	# first-shot path could never trigger.
	var opener: bool = is_first_shot()
	cooldown = float(def["interval"])
	mag -= 1
	shots_in_burst += 1
	ammo_changed.emit(mag, reserve)

	var eye: Vector3 = owner_actor.eye_position()
	var basis_aim: Basis = owner_actor.aim_basis()
	var dir: Vector3 = -basis_aim.z
	fired.emit(def, muzzle_position(), dir)

	# First-shot accuracy: standing still, aimed, and not already mid-burst, the
	# round goes exactly where the crosshair is. Krunker rewards the disciplined
	# opening shot, and a cone that never closes makes precision weapons feel
	# broken no matter how well you aim. Shotguns keep their cone regardless.
	var cone := deg_to_rad(spread_degrees())
	if int(def["pellets"]) == 1 and opener:
		cone = 0.0
	for i in int(def["pellets"]):
		_shoot_one(eye, basis_aim, cone)

	var r: Dictionary = def["recoil"]
	recoil_pitch += deg_to_rad(float(r["up"])) * (1.0 - 0.35 * ads_amount)
	recoil_yaw += deg_to_rad(float(r["side"])) * Game.rng.randf_range(-1.0, 1.0)
	bloom = minf(bloom + float(def["spread_hip"]) * 0.22, float(def["spread_hip"]) * 1.6)
	if mag <= 0:
		start_reload()
	return true

func _shoot_one(eye: Vector3, basis_aim: Basis, cone: float) -> void:
	var dir: Vector3 = -basis_aim.z
	if cone > 0.0:
		var a := Game.rng.randf_range(0.0, TAU)
		var r := sqrt(Game.rng.randf()) * cone
		dir = (basis_aim * Vector3(sin(r) * cos(a), sin(r) * sin(a), -cos(r))).normalized()
	var to := eye + dir * 400.0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye, to, Actor.SHOOT_MASK, owner_actor.exclude_rids)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var pos: Vector3 = hit["position"]
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var collider = hit["collider"]
	if collider is Hitbox:
		var hb: Hitbox = collider
		var victim: Actor = hb.actor as Actor
		if victim == null or not victim.alive:
			return
		var dist := eye.distance_to(pos)
		var dmg: float = float(def["damage"]) \
			* WeaponDefs.zone_mult(def, hb.zone) \
			* WeaponDefs.falloff_mult(def, dist)
		var killed: bool = victim.apply_damage(dmg, owner_actor, hb.zone, pos)
		landed.emit(hb.zone, dmg, pos, normal, victim, killed)
	else:
		missed.emit(pos, normal)

func muzzle_position() -> Vector3:
	if owner_actor == null:
		return global_position
	var b: Basis = owner_actor.aim_basis()
	return owner_actor.eye_position() + (-b.z) * 0.55 + b.x * 0.16 - b.y * 0.12

func try_melee() -> void:
	if owner_actor == null or not owner_actor.alive:
		return
	var eye: Vector3 = owner_actor.eye_position()
	var dir: Vector3 = owner_actor.aim_dir()
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * Tuning.melee_range,
		Actor.SHOOT_MASK, owner_actor.exclude_rids)
	q.collide_with_areas = true
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var collider = hit["collider"]
	if collider is Hitbox:
		var hb: Hitbox = collider
		var victim: Actor = hb.actor as Actor
		if victim and victim.alive:
			var killed: bool = victim.apply_damage(Tuning.melee_damage, owner_actor, hb.zone, hit["position"])
			landed.emit(hb.zone, Tuning.melee_damage, hit["position"], hit.get("normal", Vector3.UP), victim, killed)
