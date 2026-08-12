class_name Fx
extends Node3D
## Pooled visual feedback: tracers, muzzle flash, impacts, shell casings,
## damage numbers, death bursts. Everything is boxes and flat colour so it never
## fights the art direction, and nothing allocates after _ready.

const TRACER_POOL := 40
const NUMBER_POOL := 24
const BURST_POOL := 14
const SHELL_POOL := 32
const FLASH_POOL := 8

## Visible travel speed, deliberately far below a bullet. At 420 m/s a 20 m
## shot's tracer lived under 50 ms — three frames at 60 fps — so it was
## effectively invisible and never appeared in a single captured frame. A
## tracer exists to be seen; the round has already landed either way.
const TRACER_SPEED := 140.0
const TRACER_LEN := 11.0

var _tracers: Array[MeshInstance3D] = []
var _tr_from: PackedVector3Array = PackedVector3Array()
var _tr_to: PackedVector3Array = PackedVector3Array()
var _tr_t: PackedFloat32Array = PackedFloat32Array()
var _tr_total: PackedFloat32Array = PackedFloat32Array()
var _t_next: int = 0

var _numbers: Array[Label3D] = []
var _num_life: PackedFloat32Array = PackedFloat32Array()
var _num_vel: PackedVector3Array = PackedVector3Array()
var _n_next: int = 0

var _bursts: Array[CPUParticles3D] = []
var _b_next: int = 0

var _shells: Array[MeshInstance3D] = []
var _sh_vel: PackedVector3Array = PackedVector3Array()
var _sh_spin: PackedVector3Array = PackedVector3Array()
var _sh_life: PackedFloat32Array = PackedFloat32Array()
var _s_next: int = 0

var _flashes: Array[MeshInstance3D] = []
var _fl_life: PackedFloat32Array = PackedFloat32Array()
var _f_next: int = 0

var _light: OmniLight3D

func _ready() -> void:
	name = "Fx"

	var tracer_mat := StandardMaterial3D.new()
	tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_mat.albedo_color = Color(1.0, 0.90, 0.55, 1.0)
	tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tracer_mat.disable_receive_shadows = true
	for i in TRACER_POOL:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.05, 1.0)
		mi.mesh = bm
		mi.material_override = tracer_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_tracers.append(mi)
	_tr_from.resize(TRACER_POOL)
	_tr_to.resize(TRACER_POOL)
	_tr_t.resize(TRACER_POOL)
	_tr_total.resize(TRACER_POOL)

	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1.0, 0.86, 0.52, 1.0)
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# Godot's billboard shader DISCARDS the node's scale unless this is set, so
	# every resize was silently ignored and the 1x1 quad rendered at full size
	# half a metre from the lens — a pale slab over most of the screen.
	flash_mat.billboard_keep_scale = true
	for i in FLASH_POOL:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1, 1)
		q.mesh = qm
		q.material_override = flash_mat
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.visible = false
		add_child(q)
		_flashes.append(q)
	_fl_life.resize(FLASH_POOL)

	for i in SHELL_POOL:
		var sh := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.035, 0.035, 0.09)
		sh.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color8(200, 158, 76)
		mat.metallic = 0.6
		mat.roughness = 0.35
		sh.material_override = mat
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sh.visible = false
		add_child(sh)
		_shells.append(sh)
	_sh_vel.resize(SHELL_POOL)
	_sh_spin.resize(SHELL_POOL)
	_sh_life.resize(SHELL_POOL)

	for i in NUMBER_POOL:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0016
		l.font_size = 96
		l.outline_size = 24
		l.outline_modulate = Color(0, 0, 0, 0.85)
		l.visible = false
		add_child(l)
		_numbers.append(l)
	_num_life.resize(NUMBER_POOL)
	_num_vel.resize(NUMBER_POOL)

	for i in BURST_POOL:
		var p := CPUParticles3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(0.085, 0.085, 0.085)
		p.mesh = cube
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = 14
		p.lifetime = 0.55
		p.spread = 70.0
		p.gravity = Vector3(0, -16, 0)
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.4
		var pm := StandardMaterial3D.new()
		pm.vertex_color_use_as_albedo = true
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		p.material_override = pm
		add_child(p)
		_bursts.append(p)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.88, 0.6)
	_light.omni_range = 8.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)

## A tracer that travels. The first version drew the whole flight path as one
## static rod for 70 ms, which reads as a laser beam, not a bullet.
func tracer(from: Vector3, to: Vector3, width: float = 1.0) -> void:
	var d := to - from
	var dist := d.length()
	if dist < 0.2:
		return
	var i := _t_next
	_t_next = (_t_next + 1) % TRACER_POOL
	_tr_from[i] = from
	_tr_to[i] = to
	_tr_t[i] = 0.0
	_tr_total[i] = dist / TRACER_SPEED
	var mi: MeshInstance3D = _tracers[i]
	mi.scale = Vector3(width, width, minf(TRACER_LEN, dist))
	mi.visible = true
	_orient(mi, from, to)

func _orient(mi: Node3D, a: Vector3, b: Vector3) -> void:
	var dir := (b - a).normalized()
	var up: Vector3 = Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	mi.look_at_from_position(mi.global_position, mi.global_position + dir, up)

func muzzle_flash(pos: Vector3, strength: float) -> void:
	_light.global_position = pos
	_light.light_energy = 4.5 * strength
	var i := _f_next
	_f_next = (_f_next + 1) % FLASH_POOL
	var q: MeshInstance3D = _flashes[i]
	q.global_position = pos
	# Scale with distance to the camera so the flash always subtends about the
	# same screen angle. It is a world-space billboard and the local player's
	# muzzle sits ~0.5 m from the lens, so a fixed world size that looked right
	# on a distant bot covered half the screen when it was your own gun.
	var cam := get_viewport().get_camera_3d()
	var dist: float = cam.global_position.distance_to(pos) if cam else 1.0
	q.scale = Vector3.ONE * clampf(dist * 0.11, 0.05, 0.55) * (0.7 + 0.5 * strength)
	q.rotation.z = randf() * TAU
	q.visible = true
	_fl_life[i] = 0.085

## Brass out of the breech. Uses the shooter's basis so casings fly to the
## right and slightly back, the way an ejection port throws them.
func eject_shell(pos: Vector3, basis_aim: Basis, col: Color, size_mult: float) -> void:
	var i := _s_next
	_s_next = (_s_next + 1) % SHELL_POOL
	var sh: MeshInstance3D = _shells[i]
	sh.global_position = pos
	sh.scale = Vector3.ONE * size_mult
	sh.visible = true
	(sh.material_override as StandardMaterial3D).albedo_color = col
	_sh_vel[i] = basis_aim.x * randf_range(2.2, 3.4) \
		+ basis_aim.y * randf_range(1.6, 2.6) \
		+ basis_aim.z * randf_range(0.4, 1.1)
	_sh_spin[i] = Vector3(randf_range(-18, 18), randf_range(-18, 18), randf_range(-18, 18))
	_sh_life[i] = 1.9

func impact(pos: Vector3, normal: Vector3, col: Color) -> void:
	var p: CPUParticles3D = _bursts[_b_next]
	_b_next = (_b_next + 1) % BURST_POOL
	p.global_position = pos + normal * 0.05
	p.direction = normal
	p.spread = 55.0
	p.amount = 8
	p.color = col
	p.initial_velocity_min = 1.8
	p.initial_velocity_max = 4.4
	p.restart()

func death_burst(pos: Vector3, col: Color) -> void:
	var p: CPUParticles3D = _bursts[_b_next]
	_b_next = (_b_next + 1) % BURST_POOL
	p.global_position = pos
	p.direction = Vector3.UP
	p.spread = 80.0
	p.amount = 24
	p.color = col
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.5
	p.restart()

func damage_number(pos: Vector3, amount: float, headshot: bool) -> void:
	var i := _n_next
	_n_next = (_n_next + 1) % NUMBER_POOL
	var l: Label3D = _numbers[i]
	_num_life[i] = 0.85
	_num_vel[i] = Vector3(randf_range(-0.5, 0.5), 2.4, randf_range(-0.5, 0.5))
	l.text = str(int(round(amount)))
	l.modulate = Color(1.0, 0.35, 0.30) if headshot else Color(1.0, 1.0, 1.0)
	l.font_size = 128 if headshot else 96
	l.global_position = pos
	l.visible = true

func _process(delta: float) -> void:
	for i in TRACER_POOL:
		if not _tracers[i].visible:
			continue
		_tr_t[i] += delta
		var total: float = maxf(_tr_total[i], 0.0001)
		var u: float = _tr_t[i] / total
		if u >= 1.0:
			_tracers[i].visible = false
			continue
		_tracers[i].global_position = _tr_from[i].lerp(_tr_to[i], u)

	for i in FLASH_POOL:
		if _fl_life[i] > 0.0:
			_fl_life[i] -= delta
			if _fl_life[i] <= 0.0:
				_flashes[i].visible = false

	for i in SHELL_POOL:
		if _sh_life[i] <= 0.0:
			continue
		_sh_life[i] -= delta
		var sh: MeshInstance3D = _shells[i]
		if _sh_life[i] <= 0.0:
			sh.visible = false
			continue
		var v: Vector3 = _sh_vel[i]
		v.y -= 22.0 * delta
		var next: Vector3 = sh.global_position + v * delta
		if next.y < 0.03:
			next.y = 0.03
			v.y = -v.y * 0.32
			v.x *= 0.6
			v.z *= 0.6
			_sh_spin[i] *= 0.4
		_sh_vel[i] = v
		sh.global_position = next
		sh.rotation += _sh_spin[i] * delta

	for i in NUMBER_POOL:
		if _num_life[i] <= 0.0:
			continue
		_num_life[i] -= delta
		var l: Label3D = _numbers[i]
		_num_vel[i] += Vector3(0, -4.5, 0) * delta
		l.global_position += _num_vel[i] * delta
		l.modulate.a = clampf(_num_life[i] / 0.45, 0.0, 1.0)
		if _num_life[i] <= 0.0:
			l.visible = false

	if _light.light_energy > 0.0:
		_light.light_energy = maxf(0.0, _light.light_energy - delta * 60.0)
