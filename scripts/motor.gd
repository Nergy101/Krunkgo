class_name Motor
extends RefCounted
## Quake-lineage movement shared by the player and the bots, so improving the
## feel improves the enemies too. The caller supplies intent each physics tick;
## the motor owns all physics.
##
## Krunker's movement identity, per reference/krunker-movement.md:
##   - no sprint key; the speed bonus comes from holding two direction keys
##   - slide converts jump momentum into ground speed and can be re-launched
##   - the re-jump window out of a slide is about a quarter second
##   - chaining jump -> slide -> jump compounds speed well above base
##   - all of it is framerate independent (they fixed that in v2.8.4)
##
## `wish_dir` is deliberately NOT normalised by the caller. Its LENGTH carries
## the diagonal-strafe bonus: holding W+A gives a vector of length 1.414, which
## we clamp to Tuning.strafe_bonus. That is the same physical origin as
## Krunker's 1.2x "Strafe Speed", rather than a special case bolted on top.

var body: CharacterBody3D
var shape: CollisionShape3D
var capsule: CapsuleShape3D

var grounded: bool = false
var was_grounded: bool = false
var sliding: bool = false
var crouching: bool = false
var slide_time: float = 0.0
var slide_cd: float = 0.0
var coyote: float = 0.0
var jump_buffered: float = 0.0
var height: float = 1.8
var landed_hard: float = 0.0        # >0 on the tick we land; magnitude = impact
var jumped_this_tick: bool = false
var slid_this_tick: bool = false
var speed_flat: float = 0.0
var wall_charges: int = 0
var wall_jumped_this_tick: bool = false
## Seconds since we last touched the floor. Krunker's slide re-jump window is
## documented at roughly a quarter second; this is what enforces it explicitly
## rather than leaning on the generic coyote/buffer timers.
var since_landing: float = 999.0

func setup(b: CharacterBody3D, s: CollisionShape3D) -> void:
	body = b
	shape = s
	capsule = s.shape as CapsuleShape3D
	height = Tuning.stand_height

func step(wish_dir: Vector3, want_jump: bool, want_crouch: bool, delta: float) -> void:
	landed_hard = 0.0
	jumped_this_tick = false
	slid_this_tick = false
	wall_jumped_this_tick = false
	was_grounded = grounded
	grounded = body.is_on_floor()

	if grounded:
		since_landing = 0.0 if not was_grounded else since_landing + delta
		# Touching the floor restores the whole wall-jump allowance, which is
		# what stops a player chaining wall-jumps forever up a single corner.
		wall_charges = Tuning.wall_jump_charges
	else:
		since_landing += delta
	if grounded and not was_grounded:
		landed_hard = clampf(-body.velocity.y / 18.0, 0.0, 1.0)
	coyote = Tuning.coyote_time if grounded else maxf(0.0, coyote - delta)
	jump_buffered = Tuning.jump_buffer if want_jump else maxf(0.0, jump_buffered - delta)
	slide_cd = maxf(0.0, slide_cd - delta)

	# The diagonal bonus lives in the length of the intent vector.
	var wish_speed_mult: float = minf(wish_dir.length(), Tuning.strafe_bonus)
	var dir: Vector3 = wish_dir.normalized() if wish_speed_mult > 0.001 else Vector3.ZERO

	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	speed_flat = flat.length()

	_update_stance(want_crouch, delta)

	# Jump is resolved BEFORE friction. Applying a tick of ground friction on the
	# frame you leave the floor is what silently ate every slide-hop: the chain
	# only compounds if the speed you built survives the launch untaxed.
	var launching: bool = jump_buffered > 0.0 and coyote > 0.0
	if launching:
		_jump()
	elif jump_buffered > 0.0 and not grounded and wall_charges > 0 and body.is_on_wall():
		# Wall-jump. reference/krunker-movement.md section 6: several classes
		# get a limited number of consecutive wall-jumps, and it is a
		# class-defining traversal mechanic, not a nicety.
		_wall_jump()

	if grounded and not launching:
		_friction(Tuning.slide_friction if sliding else Tuning.ground_friction, delta)
		var target: float = Tuning.max_ground_speed * wish_speed_mult
		if crouching and not sliding:
			target *= Tuning.crouch_speed_mult
		if sliding:
			# Steering during a slide must not re-accelerate you up to walk
			# speed, or sliding would be a free speed floor instead of a
			# decaying burst you have to keep re-earning.
			target = minf(target, speed_flat)
		_accelerate(dir, target, Tuning.ground_accel, delta)
	else:
		# Airborne: the wish speed is a tiny window, so only turning your view
		# and strafing into the turn adds speed. Running straight gains nothing.
		_accelerate(dir, Tuning.air_speed_cap * wish_speed_mult, Tuning.air_accel, delta)
		body.velocity.y -= Tuning.gravity * delta

	var v := body.velocity
	var f := Vector3(v.x, 0.0, v.z)
	if f.length() > Tuning.hard_speed_cap:
		f = f.normalized() * Tuning.hard_speed_cap
		body.velocity = Vector3(f.x, v.y, f.z)

	body.move_and_slide()
	var nv := body.velocity
	speed_flat = Vector3(nv.x, 0.0, nv.z).length()

## Kick off a wall: vertical impulse, cancel whatever speed was driving us into
## the surface, then push out along its normal. Cancelling the inward component
## is what stops the player sticking and sliding down the face.
func _wall_jump() -> void:
	var n: Vector3 = body.get_wall_normal()
	n.y = 0.0
	if n.length_squared() < 0.0001:
		return
	n = n.normalized()
	jump_buffered = 0.0
	wall_charges -= 1
	jumped_this_tick = true
	wall_jumped_this_tick = true
	sliding = false
	body.velocity.y = Tuning.wall_jump_velocity
	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var into: float = flat.dot(-n)
	if into > 0.0:
		flat += n * into
	flat += n * Tuning.wall_jump_push
	if flat.length() > Tuning.hard_speed_cap:
		flat = flat.normalized() * Tuning.hard_speed_cap
	body.velocity.x = flat.x
	body.velocity.z = flat.z

func _jump() -> void:
	jump_buffered = 0.0
	coyote = 0.0
	jumped_this_tick = true
	body.velocity.y = Tuning.jump_velocity
	# Launching out of a slide banks its speed — but only if you leave inside the
	# documented re-jump window, about a quarter second after touchdown. Late and
	# you keep the slide's speed minus a bite, which is what makes the timing a
	# skill rather than a formality. This is what `since_landing` is for.
	if sliding:
		sliding = false
		slide_cd = Tuning.slide_cooldown
		if since_landing > Tuning.slide_rejump_window:
			var v := Vector3(body.velocity.x, 0.0, body.velocity.z)
			v *= Tuning.slide_late_penalty
			body.velocity.x = v.x
			body.velocity.z = v.z

func _update_stance(want_crouch: bool, delta: float) -> void:
	if want_crouch and grounded and not sliding and slide_cd <= 0.0 \
			and speed_flat >= Tuning.slide_min_speed:
		_start_slide()
	if sliding:
		slide_time += delta
		var too_slow: bool = speed_flat < Tuning.slide_min_speed * 0.55
		var released: bool = not want_crouch and slide_time > Tuning.slide_min_time
		if slide_time > Tuning.slide_max_time or released \
				or (too_slow and slide_time > Tuning.slide_min_time):
			sliding = false
			slide_cd = Tuning.slide_cooldown
	crouching = want_crouch or sliding

	var target_h: float = Tuning.crouch_height if crouching else Tuning.stand_height
	height = move_toward(height, target_h, Tuning.stance_lerp * delta * 2.0)
	capsule.height = maxf(height, capsule.radius * 2.0 + 0.01)
	shape.position.y = capsule.height * 0.5

func _start_slide() -> void:
	sliding = true
	slid_this_tick = true
	slide_time = 0.0
	var v := body.velocity
	var f := Vector3(v.x, 0.0, v.z)
	if f.length() < 0.01:
		return
	# Multiplicative, so each hop in a chain pays out more than the last until
	# the cap. A flat additive boost makes the second hop pointless.
	var boosted: float = minf(f.length() * Tuning.slide_gain + Tuning.slide_boost,
		Tuning.slide_speed_cap)
	f = f.normalized() * boosted
	body.velocity = Vector3(f.x, v.y, f.z)

func _friction(amount: float, delta: float) -> void:
	var v := body.velocity
	var f := Vector3(v.x, 0.0, v.z)
	var speed := f.length()
	if speed < 0.001:
		body.velocity = Vector3(0, v.y, 0)
		return
	var control: float = maxf(speed, Tuning.stop_speed)
	var drop: float = control * amount * delta
	var newspeed: float = maxf(speed - drop, 0.0) / speed
	body.velocity = Vector3(f.x * newspeed, v.y, f.z * newspeed)

func _accelerate(dir: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	if dir.length_squared() < 0.0001 or wish_speed <= 0.0:
		return
	var current: float = body.velocity.dot(dir)
	var add: float = wish_speed - current
	if add <= 0.0:
		return
	var accel_speed: float = minf(accel * delta * wish_speed, add)
	body.velocity += dir * accel_speed

func eye_offset() -> float:
	var t: float = inverse_lerp(Tuning.crouch_height, Tuning.stand_height, height)
	return lerpf(Tuning.crouch_eye_height, Tuning.eye_height, clampf(t, 0.0, 1.0))
