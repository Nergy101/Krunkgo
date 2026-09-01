class_name Actor
extends CharacterBody3D
## Shared base for the player and the bots: capsule, hitboxes, blocky body,
## health, death, respawn, and a weapon. Both sides of every fight run the same
## simulation, so a bot is never cheating and never handicapped.

signal died(killer: Actor)
signal damaged(amount: float, from_dir: Vector3)
signal health_changed(hp: float)

const WORLD_MASK := 1
const SHOOT_MASK := 5        # world + hitbox
const LAYER_SELF_BODY := 4   # render layer 3: hidden from our own camera

var display_name: String = "ACTOR"
var team: int = 0
var tint: Color = Color.WHITE
var health: float = 100.0
var alive: bool = true
var spawn_time: float = -999.0
var last_hurt_time: float = -999.0
var killer_name: String = ""

var motor := Motor.new()
var weapon: Weapon
var body_root: Node3D
var hit_root: Node3D
var shape: CollisionShape3D
var hitboxes: Array[Hitbox] = []
var exclude_rids: Array[RID] = []

var yaw: float = 0.0
var pitch: float = 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.35
	slide_on_ceiling = true

	shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = Tuning.stand_height
	shape.shape = cap
	shape.position.y = Tuning.stand_height * 0.5
	add_child(shape)
	motor.setup(self, shape)

	body_root = Blockman.build(tint)
	add_child(body_root)

	hit_root = Node3D.new()
	hit_root.name = "Hitboxes"
	add_child(hit_root)
	_build_hitboxes()

	weapon = Weapon.new()
	weapon.name = "Weapon"
	weapon.owner_actor = self
	add_child(weapon)

	exclude_rids = [get_rid()]
	for h in hitboxes:
		exclude_rids.append(h.get_rid())

	health = Tuning.max_health
	Game.register_actor(display_name, team)

## Zones come straight from Blockman.ZONES, so what you see really is what you
## hit. The previous version positioned three boxes by eyeballed ratios of
## capsule height (0.845 / 0.567 / 0.183) that matched no part of the model,
## and had no zone for the arms at all.
func _build_hitboxes() -> void:
	for spec in Blockman.ZONES:
		var hb := Hitbox.make(self, spec["zone"], spec["size"], Vector3.ZERO)
		hit_root.add_child(hb)
		hitboxes.append(hb)
	_place_hitboxes()

func _place_hitboxes() -> void:
	# Crouching and sliding shrink the visible body, so the zones shrink with it
	# by the same factor rather than drifting apart from the silhouette.
	var k: float = motor.height / Tuning.stand_height
	for i in hitboxes.size():
		var spec: Dictionary = Blockman.ZONES[i]
		var hb: Hitbox = hitboxes[i]
		hb.position.y = float(spec["y"]) * k
		hb.scale = Vector3(1.0, k, 1.0)
	hit_root.rotation.y = yaw

func eye_position() -> Vector3:
	return global_position + Vector3(0, motor.eye_offset(), 0)

## Aim includes live weapon recoil, so the camera, the tracer and the bullet
## can never disagree about where the gun is pointing.
func aim_basis() -> Basis:
	var rp: float = weapon.recoil_pitch if weapon else 0.0
	var ry: float = weapon.recoil_yaw if weapon else 0.0
	var p: float = clampf(pitch + rp, -Tuning.pitch_limit, Tuning.pitch_limit)
	return Basis.from_euler(Vector3(p, yaw + ry, 0.0))

## Clear line of sight to another actor, ignoring hitboxes and our own body.
## Lives on Actor rather than Bot because the player's autopilot needs it too.
func has_los(other: Actor) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye_position(), other.eye_position(),
		WORLD_MASK, exclude_rids)
	q.collide_with_areas = false
	return space.intersect_ray(q).is_empty()

func aim_dir() -> Vector3:
	return -aim_basis().z

func is_alive() -> bool:
	return alive

func protected() -> bool:
	return (float(Time.get_ticks_msec()) / 1000.0) - spawn_time < Tuning.spawn_protection

## Returns true if this damage was the killing blow.
func apply_damage(amount: float, attacker: Actor, zone: int, _hit_pos: Vector3) -> bool:
	if not alive or protected():
		return false
	# Team Deathmatch: shots between teammates deal no damage. The bots already
	# avoid targeting their own team; this is the safety net that also stops a
	# friendly player from hurting their own side.
	if Game.is_tdm() and is_instance_valid(attacker) and attacker != self \
			and attacker.team == team:
		return false
	health -= amount
	last_hurt_time = float(Time.get_ticks_msec()) / 1000.0
	var from_dir := Vector3.FORWARD
	if is_instance_valid(attacker):
		from_dir = (attacker.global_position - global_position).normalized()
	damaged.emit(amount, from_dir)
	health_changed.emit(health)
	if health <= 0.0:
		_die(attacker, zone == Hitbox.Zone.HEAD)
		return true
	return false

func _die(killer: Actor, headshot: bool) -> void:
	alive = false
	health = 0.0
	killer_name = killer.display_name if is_instance_valid(killer) else display_name
	var wname: String = ""
	if is_instance_valid(killer) and killer.weapon:
		wname = String(killer.weapon.def.get("display", ""))
	Game.report_kill(killer_name, display_name, wname, headshot)
	if Game.fx:
		Game.fx.death_burst(global_position + Vector3(0, 0.9, 0), tint)
	Audio.play_at("hurt", global_position, 0.7)
	visible = false
	set_physics_process(false)
	for h in hitboxes:
		h.monitorable = false
	died.emit(killer)

func respawn(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	health = Tuning.max_health
	alive = true
	visible = true
	spawn_time = float(Time.get_ticks_msec()) / 1000.0
	set_physics_process(true)
	for h in hitboxes:
		h.monitorable = true
	if weapon:
		weapon.refill()
	health_changed.emit(health)

## Re-team and re-colour an actor, rebuilding the body mesh so the change is
## visible immediately. Used on map swap (into or out of Team Deathmatch) where
## actors already exist with bodies built from their old tint. Hitboxes are a
## separate node and are untouched.
func set_team_and_tint(t: int, c: Color) -> void:
	team = t
	if c != tint and body_root:
		var old: Node3D = body_root
		body_root = Blockman.build(c)
		add_child(body_root)
		old.free()
		if self is Player:
			hide_body_from_own_camera()
	tint = c
	Game.register_actor(display_name, team)

func _regen(delta: float) -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	if health < Tuning.max_health and now - last_hurt_time > Tuning.regen_delay:
		health = minf(Tuning.max_health, health + Tuning.regen_rate * delta)
		health_changed.emit(health)

func hide_body_from_own_camera() -> void:
	for child in body_root.get_children():
		_set_layers_recursive(child, LAYER_SELF_BODY)

func _set_layers_recursive(n: Node, layers: int) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).layers = layers
	for c in n.get_children():
		_set_layers_recursive(c, layers)

func _animate_body(delta: float) -> void:
	if not body_root:
		return
	body_root.rotation.y = yaw
	var swing: float = 0.0
	if motor.grounded and motor.speed_flat > 0.5:
		swing = sin(float(Time.get_ticks_msec()) * 0.001 * Tuning.view_bob_speed) \
			* clampf(motor.speed_flat / Tuning.max_ground_speed, 0.0, 1.4) * 0.55
	var arm_l := body_root.get_node_or_null("ArmL")
	var arm_r := body_root.get_node_or_null("ArmR")
	var leg_l := body_root.get_node_or_null("LegL")
	var leg_r := body_root.get_node_or_null("LegR")
	if leg_l:
		leg_l.rotation.x = lerpf(leg_l.rotation.x, swing, 20.0 * delta)
	if leg_r:
		leg_r.rotation.x = lerpf(leg_r.rotation.x, -swing, 20.0 * delta)
	if arm_l:
		arm_l.rotation.x = lerpf(arm_l.rotation.x, -1.25 + pitch * 0.6, 18.0 * delta)
	if arm_r:
		arm_r.rotation.x = lerpf(arm_r.rotation.x, -1.35 + pitch * 0.6, 18.0 * delta)
	var head := body_root.get_node_or_null("HeadPivot")
	if head:
		head.rotation.x = lerpf(head.rotation.x, clampf(pitch, -0.7, 0.7), 25.0 * delta)
	# crouch squashes the visible body; hitboxes are repositioned separately so
	# the two never drift apart.
	var sy: float = motor.height / Tuning.stand_height
	body_root.scale.y = lerpf(body_root.scale.y, sy, 18.0 * delta)
