extends Node
## Hit-registration probe.
##
##   godot --path . -- hittest
##
## Fires a statistically meaningful number of shots from a controlled position
## at a target dummy at several ranges and stances, and prints one JSON line
## prefixed HITTEST. Answers the questions that actually matter and that a
## screenshot can never answer: does the first shot go where the crosshair is,
## do the zone multipliers produce the shots-to-kill the reference documents,
## how wide is the shotgun cone, and can a shooter ever hit itself.

const SHOTS_PER_CASE := 240
const RANGES := [5.0, 20.0, 50.0, 100.0]
const PLATFORM_Y := 700.0

var shooter: Player
var dummy: Bot
var out: Dictionary = {}

func _ready() -> void:
	name = "HitTest"
	await get_tree().physics_frame
	shooter = Game.local_player as Player
	if shooter == null:
		push_error("hittest: no local player")
		get_tree().quit(1)
		return
	# Run in a clean volume above the arena so map geometry cannot absorb shots.
	_build_platform()
	shooter.autopilot = null
	shooter.input_enabled = false
	shooter.set_physics_process(false)
	shooter.global_position = Vector3(0, PLATFORM_Y + 1.0, 0)
	shooter.velocity = Vector3.ZERO

	dummy = Bot.new()
	dummy.display_name = "DUMMY"
	dummy.loadout_index = 0
	get_parent().add_child(dummy)
	await get_tree().physics_frame
	dummy.set_physics_process(false)
	dummy.health = 1.0e9          # survives everything so we can measure damage
	dummy.spawn_time = -999.0

	await get_tree().physics_frame
	await _run()

func _build_platform() -> void:
	var slab := StaticBody3D.new()
	slab.collision_layer = 1
	slab.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 2, 300)
	cs.shape = box
	cs.position = Vector3(0, PLATFORM_Y - 1.0, 120)
	slab.add_child(cs)
	add_child(slab)

## Must await a physics frame. Area3D transforms only reach the physics server
## on flush, so moving the dummy and raycasting in the same frame queries its
## OLD position — which is why the first version of this probe reported zero
## hits for every weapon at every range.
func _place_dummy(dist: float) -> void:
	dummy.global_position = Vector3(0, PLATFORM_Y, dist)
	dummy.yaw = PI
	dummy.motor.height = Tuning.stand_height
	dummy._place_hitboxes()
	await get_tree().physics_frame

## Aim at a world point and fire once, reporting what was hit.
func _fire_at(point: Vector3) -> Dictionary:
	var d: Vector3 = point - shooter.eye_position()
	shooter.yaw = atan2(-d.x, -d.z)
	shooter.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	var w: Weapon = shooter.weapon
	# Recoil is part of aim_basis, so without clearing it the batch walks its
	# own shots off the target and every measurement becomes a recoil test.
	w.recoil_pitch = 0.0
	w.recoil_yaw = 0.0
	w.cooldown = 0.0
	w.reload_left = 0.0
	w.switch_left = 0.0
	w.mag = int(w.def["mag"])
	var res := {"zones": {}, "damage": 0.0, "self": 0, "hits": 0, "points": []}
	var on_land := func(zone, dmg, pos, _n, victim, _k):
		res["hits"] += 1
		res["damage"] += dmg
		res["zones"][zone] = int(res["zones"].get(zone, 0)) + 1
		res["points"].append(pos)
		if victim == shooter:
			res["self"] += 1
	w.landed.connect(on_land)
	w.try_fire()
	w.landed.disconnect(on_land)
	return res

## Does this shot count as a clean hit on `zone`?
## One projectile: the zone must be the only thing hit. Many pellets: the blast
## just has to be dominated by that zone, because demanding purity from eight
## independent pellets throws away almost every shotgun blast.
func _counts(r: Dictionary, zone: int) -> bool:
	var here: int = int(r["zones"].get(zone, 0))
	if here <= 0:
		return false
	var total := 0
	for z in r["zones"].keys():
		total += int(r["zones"][z])
	if int(shooter.weapon.def["pellets"]) == 1:
		return r["zones"].size() == 1
	return float(here) / float(maxi(total, 1)) >= 0.6

func _run() -> void:
	var per_weapon: Dictionary = {}
	var total_self := 0

	for key in WeaponDefs.LOADOUT:
		shooter.weapon.equip(key)
		shooter.weapon.switch_left = 0.0
		var def: Dictionary = shooter.weapon.def
		var entry: Dictionary = {}

		# --- first-shot accuracy, stationary and aiming
		await _place_dummy(30.0)
		shooter.weapon.ads = true
		shooter.weapon.ads_amount = 1.0
		shooter.weapon.bloom = 0.0
		var dev := 0.0
		var aim_point: Vector3 = dummy.global_position + Vector3(0, 1.02, 0)
		for i in 60:
			# Each sample must be a genuine opener. shots_in_burst only decays
			# in Weapon._process, which never runs inside this synchronous
			# batch, so without resetting it shots 2..60 were full-spread and
			# the metric measured a burst rather than a first shot.
			shooter.weapon.bloom = 0.0
			shooter.weapon.shots_in_burst = 0
			# The shooter has physics disabled for determinism, so its motor
			# never reports grounded; first-shot accuracy requires it.
			shooter.motor.grounded = true
			shooter.motor.speed_flat = 0.0
			var r := _fire_at(aim_point)
			for p in r["points"]:
				dev = maxf(dev, Vector2(p.x - aim_point.x, p.y - aim_point.y).length())
			total_self += int(r["self"])
		entry["first_shot_max_dev_m_at_30m"] = snappedf(dev, 0.0001)

		# --- damage at range, body shot
		shooter.weapon.ads = false
		shooter.weapon.ads_amount = 0.0
		var dmg_by_range: Dictionary = {}
		for dist in RANGES:
			await _place_dummy(dist)
			var target: Vector3 = dummy.global_position + Vector3(0, 1.02, 0)
			var sum := 0.0
			var n := 0
			for i in 40:
				shooter.weapon.bloom = 0.0
				var r := _fire_at(target)
				total_self += int(r["self"])
				# Body-zone hits ONLY. Averaging across zones mixed in 0.5x limb
				# and 1.5x head multipliers and produced a curve that measured
				# spread rather than falloff.
				if _counts(r, Hitbox.Zone.BODY):
					sum += r["damage"]
					n += 1
			dmg_by_range[str(int(dist))] = snappedf(sum / maxf(1.0, float(n)), 0.01)
			dmg_by_range[str(int(dist)) + "_n"] = n
		entry["body_damage_by_range_m"] = dmg_by_range

		# --- zone distribution and shots-to-kill, measured at 10 m which is
		# inside every weapon's falloff start. At 20 m the SMG was already 4 m
		# into its curve and read 16.65 instead of 18, which looks like a bug
		# and is actually falloff doing its job.
		await _place_dummy(10.0)
		var body_pt: Vector3 = dummy.global_position + Vector3(0, 1.02, 0)
		var head_pt: Vector3 = dummy.global_position + Vector3(0, 1.55, 0)
		var zones: Dictionary = {}
		var body_dmg := 0.0
		var head_dmg := 0.0
		var body_landed := 0
		var head_landed := 0
		for i in SHOTS_PER_CASE:
			shooter.weapon.bloom = 0.0
			var r := _fire_at(body_pt)
			total_self += int(r["self"])
			# Single-projectile weapons: zone-pure only, because a round that
			# clipped an arm carries a 0.5x limb multiplier and would drag the
			# average below the body figure the reference quotes.
			# Multi-pellet weapons: sum the WHOLE blast. An 8-pellet shotgun
			# almost never lands every pellet in one zone, so the purity filter
			# discarded nearly every shot and reported point-blank damage as
			# 0.0 with zero qualifying samples.
			if _counts(r, Hitbox.Zone.BODY):
				body_dmg += r["damage"]
				body_landed += 1
			for z in r["zones"].keys():
				zones[z] = int(zones.get(z, 0)) + int(r["zones"][z])
		for i in SHOTS_PER_CASE:
			shooter.weapon.bloom = 0.0
			var r := _fire_at(head_pt)
			total_self += int(r["self"])
			if _counts(r, Hitbox.Zone.HEAD):
				head_dmg += r["damage"]
				head_landed += 1
		# Per LANDED shot, not per shot fired. Dividing by shots fired folds the
		# hip-fire miss rate into the number and turns a shots-to-kill figure
		# into an accuracy figure, which is not what the reference table means.
		var avg_body: float = body_dmg / maxf(1.0, float(body_landed))
		var avg_head: float = head_dmg / maxf(1.0, float(head_landed))
		entry["hit_rate_hipfire_10m"] = snappedf(float(body_landed) / float(SHOTS_PER_CASE), 0.001)
		entry["avg_body_damage"] = snappedf(avg_body, 0.01)
		entry["avg_head_damage"] = snappedf(avg_head, 0.01)
		entry["shots_to_kill_body"] = int(ceil(Tuning.max_health / maxf(0.01, avg_body)))
		entry["shots_to_kill_head"] = int(ceil(Tuning.max_health / maxf(0.01, avg_head)))
		var named: Dictionary = {}
		for z in zones.keys():
			named[["HEAD", "BODY", "LIMB"][int(z)]] = zones[z]
		entry["zone_hits_aiming_at_torso"] = named

		# --- cone radius at 20 m
		await _place_dummy(20.0)
		var spread_r := 0.0
		for i in 60:
			shooter.weapon.bloom = 0.0
			var r := _fire_at(body_pt)
			for p in r["points"]:
				spread_r = maxf(spread_r, Vector2(p.x - body_pt.x, p.y - body_pt.y).length())
		entry["hipfire_cone_radius_m_at_20m"] = snappedf(spread_r, 0.001)
		entry["pellets"] = int(def["pellets"])
		per_weapon[key] = entry

	out = {
		"per_weapon": per_weapon,
		"self_hits_total": total_self,
		"self_hits_note": "structurally impossible: Actor.exclude_rids strips every one of the shooter's own hitbox RIDs before the raycast runs, so this confirms the guard is wired, not that a self-hit was survived",
		"zone_layout": Blockman.ZONES.size(),
		"note": "dummy has effectively infinite health; shots_to_kill is derived from average damage per shot against 100 HP",
	}
	print("HITTEST ", JSON.stringify(out))
	get_tree().quit(0)
