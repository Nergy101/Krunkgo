class_name Viewmodel
extends Node3D
## The gun you actually look at.
##
## Per reference/krunker-look.md and direct inspection of
## reference/bar/krunker_citadel_viewmodel_01.jpg, the Krunker signature is a
## big, CANTED gun sitting LOW-RIGHT that stays visible through ADS.
##
## It renders through its own SubViewport with its own World3D, composited over
## the main view. That is what stops a long barrel from punching through a wall
## when you back into one — the first pass drew the gun in world space and it
## clipped through the tunnel walls constantly. A separate world also means the
## gun keeps its own consistent key light regardless of where you stand.

const VM_FOV := 62.0

var rest_pos := Vector3(0.215, -0.170, -1.06)
var ads_pos := Vector3(0.0, -0.088, -0.62)
var rest_rot := Vector3(0.035, 0.130, -0.185)     # the cant
var ads_rot := Vector3(0.0, 0.0, 0.0)

var kick: float = 0.0
var kick_rot: float = 0.0
var bob_t: float = 0.0
var sway := Vector2.ZERO
var _model: Node3D
var _muzzle: Node3D
var viewport: SubViewport

## Builds the whole composited rig and returns the Viewmodel inside it.
static func build_rig(parent: Node) -> Viewmodel:
	var layer := CanvasLayer.new()
	layer.name = "ViewmodelLayer"
	layer.layer = 5                       # under the HUD, over the world
	parent.add_child(layer)

	var container := SubViewportContainer.new()
	container.name = "ViewmodelContainer"
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(container)

	var vp := SubViewport.new()
	vp.name = "ViewmodelViewport"
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.handle_input_locally = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	container.add_child(vp)

	var cam := Camera3D.new()
	cam.name = "ViewmodelCamera"
	cam.fov = VM_FOV
	cam.near = 0.01
	cam.far = 8.0
	cam.current = true
	vp.add_child(cam)

	# Its own key light: a fixed three-quarter fill so the gun reads the same in
	# a dark tunnel as in the open, which is how Krunker's viewmodel behaves.
	var key := DirectionalLight3D.new()
	key.light_energy = 1.9
	key.light_color = Color8(255, 246, 226)
	key.rotation_degrees = Vector3(-32, 38, 0)
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.7
	fill.light_color = Color8(186, 202, 226)
	fill.rotation_degrees = Vector3(14, -140, 0)
	vp.add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CANVAS
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color8(150, 148, 142)
	e.ambient_light_energy = 0.9
	env.environment = e
	vp.add_child(env)

	var vm := Viewmodel.new()
	vp.add_child(vm)
	vm.viewport = vp
	return vm

func _ready() -> void:
	name = "Viewmodel"
	_muzzle = Node3D.new()
	add_child(_muzzle)

func sync_size(px: Vector2i) -> void:
	if viewport and viewport.size != px:
		viewport.size = px

## World-space muzzle is meaningless for a gun that lives in its own viewport.
## Tracers and flashes must originate from Weapon.muzzle_position() instead;
## this is only used to place the flash sprite inside the viewmodel world.
func muzzle_local() -> Vector3:
	return _muzzle.global_position

func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.72
	m.metallic_specular = 0.30
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func build_for(key: String) -> void:
	if _model:
		_model.queue_free()
	_model = Node3D.new()
	add_child(_model)
	# Scaled up hard versus the first pass. In the reference shot the gun eats
	# roughly the lower-right third of the screen; ours was a distant twig.
	var gun := Color8(58, 61, 68)
	var dark := Color8(34, 35, 40)
	var wood := Color8(122, 82, 46)
	var wood_d := Color8(92, 60, 33)
	var brass := Color8(198, 156, 74)
	var muzzle_z := -0.5

	match key:
		"assault":
			_box(_model, Vector3(0.105, 0.125, 0.78), Vector3(0, 0, -0.16), gun)
			_box(_model, Vector3(0.062, 0.062, 0.42), Vector3(0, 0.012, -0.72), dark)
			_box(_model, Vector3(0.05, 0.05, 0.10), Vector3(0, 0.012, -0.95), gun)
			_box(_model, Vector3(0.085, 0.26, 0.14), Vector3(0, -0.19, -0.02), dark)   # magazine
			_box(_model, Vector3(0.075, 0.17, 0.10), Vector3(0, -0.15, 0.19), gun)     # grip
			_box(_model, Vector3(0.07, 0.10, 0.30), Vector3(0, 0.005, 0.32), dark)     # stock
			_box(_model, Vector3(0.035, 0.075, 0.16), Vector3(0, 0.10, -0.34), dark)   # sight block
			_box(_model, Vector3(0.02, 0.05, 0.02), Vector3(0, 0.145, -0.55), brass)   # front post
			_box(_model, Vector3(0.11, 0.035, 0.22), Vector3(0, -0.075, -0.44), dark)  # handguard
			muzzle_z = -1.00
		"sniper":
			_box(_model, Vector3(0.09, 0.10, 1.00), Vector3(0, 0, -0.22), wood_d)
			_box(_model, Vector3(0.052, 0.052, 0.52), Vector3(0, 0.010, -0.92), gun)
			_box(_model, Vector3(0.085, 0.085, 0.34), Vector3(0, 0.125, -0.14), dark)  # scope
			_box(_model, Vector3(0.05, 0.05, 0.10), Vector3(0, 0.125, -0.33), gun)
			_box(_model, Vector3(0.10, 0.10, 0.03), Vector3(0, 0.125, -0.32), Color8(96, 178, 206))
			_box(_model, Vector3(0.035, 0.06, 0.06), Vector3(0, 0.075, -0.02), dark)   # bolt
			_box(_model, Vector3(0.06, 0.045, 0.14), Vector3(0.075, 0.055, 0.06), gun) # bolt handle
			_box(_model, Vector3(0.08, 0.23, 0.13), Vector3(0, -0.17, 0.02), wood)     # grip
			_box(_model, Vector3(0.08, 0.14, 0.36), Vector3(0, -0.02, 0.38), wood)     # stock
			muzzle_z = -1.20
		"shotgun":
			_box(_model, Vector3(0.135, 0.14, 0.74), Vector3(0, 0, -0.14), wood)
			_box(_model, Vector3(0.095, 0.095, 0.46), Vector3(0, 0.028, -0.70), dark)
			_box(_model, Vector3(0.105, 0.075, 0.30), Vector3(0, -0.082, -0.46), gun)  # pump
			_box(_model, Vector3(0.08, 0.22, 0.12), Vector3(0, -0.16, 0.04), dark)
			_box(_model, Vector3(0.085, 0.13, 0.30), Vector3(0, -0.02, 0.34), wood_d)
			_box(_model, Vector3(0.03, 0.03, 0.03), Vector3(0, 0.075, -0.90), brass)
			muzzle_z = -0.95
		"smg":
			_box(_model, Vector3(0.095, 0.115, 0.50), Vector3(0, 0, -0.06), gun)
			_box(_model, Vector3(0.055, 0.055, 0.24), Vector3(0, 0.010, -0.41), dark)
			_box(_model, Vector3(0.07, 0.30, 0.095), Vector3(0, -0.21, -0.04), dark)   # long mag
			_box(_model, Vector3(0.07, 0.16, 0.095), Vector3(0, -0.13, 0.17), gun)
			_box(_model, Vector3(0.05, 0.075, 0.22), Vector3(0, 0.0, 0.28), dark)      # wire stock
			_box(_model, Vector3(0.03, 0.055, 0.10), Vector3(0, 0.088, -0.24), dark)
			muzzle_z = -0.56
		_:
			_box(_model, Vector3(0.08, 0.145, 0.34), Vector3(0, 0, -0.05), gun)
			_box(_model, Vector3(0.048, 0.048, 0.12), Vector3(0, 0.02, -0.26), dark)
			_box(_model, Vector3(0.072, 0.19, 0.105), Vector3(0, -0.16, 0.045), dark)
			_box(_model, Vector3(0.025, 0.04, 0.03), Vector3(0, 0.078, -0.16), brass)
			muzzle_z = -0.34
	_muzzle.position = Vector3(0, 0.012, muzzle_z)

func punch(amount: float) -> void:
	kick = maxf(kick, amount)
	kick_rot = maxf(kick_rot, amount * 2.4)

func update_view(delta: float, speed_ratio: float, grounded: bool, ads_amount: float,
		look_delta: Vector2, reload_t: float) -> void:
	bob_t += delta * Tuning.view_bob_speed * clampf(speed_ratio, 0.0, 1.5)
	var bob := Vector3.ZERO
	if grounded:
		bob.x = sin(bob_t) * Tuning.view_bob_amount * 2.1 * speed_ratio
		bob.y = -absf(cos(bob_t)) * Tuning.view_bob_amount * 2.4 * speed_ratio

	sway = sway.lerp(look_delta * -0.030, clampf(delta * 11.0, 0.0, 1.0))
	sway = sway.limit_length(0.055)

	kick = move_toward(kick, 0.0, delta * 2.4)
	kick_rot = move_toward(kick_rot, 0.0, delta * 7.5)

	var target_pos: Vector3 = rest_pos.lerp(ads_pos, ads_amount)
	var target_rot: Vector3 = rest_rot.lerp(ads_rot, ads_amount)
	var bob_scale: float = 1.0 - 0.8 * ads_amount

	# reload dips the gun out of frame and rolls it, then brings it back
	var dip: float = sin(clampf(reload_t, 0.0, 1.0) * PI)

	var w: float = clampf(delta * 17.0, 0.0, 1.0)
	position = position.lerp(target_pos
		+ bob * bob_scale
		+ Vector3(sway.x, sway.y, 0.0)
		+ Vector3(0, -dip * 0.20, kick * 0.34), w)
	rotation = Vector3(
		lerpf(rotation.x, target_rot.x + kick_rot * 0.14 - dip * 0.9, w),
		lerpf(rotation.y, target_rot.y + sway.x * 1.5, w),
		lerpf(rotation.z, target_rot.z - sway.x * 2.0 + dip * 0.5, w))
