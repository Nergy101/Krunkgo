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

var rest_pos := Vector3(0.285, -0.205, -1.02)
## Filled per weapon in build_for(): where that model's sight sits in local
## space. ADS then places the gun so this point lands exactly on the camera
## axis, i.e. dead centre of the screen, which is where the bullet goes.
var sight_local := Vector3(0.0, 0.10, 0.0)
## Arms live under their own node so ADS can slide them out of frame. Held at
## the rest offset they became a featureless brown wedge under the sight the
## moment the gun came up to the camera axis.
var _arms: Node3D          # support arm: stays on the gun under ADS
var _arms_trigger: Node3D  # trigger arm: leaves the frame under ADS
## How far forward the gun sits when aimed. Pushed out from -0.56: at that
## depth the camera sat right behind the stock, so aiming filled the bottom
## third of the screen with one featureless slab of receiver and butt. Moving
## along z keeps the sight on the camera axis, so alignment is unaffected.
## How far forward each gun sits when aimed. This was ONE global constant, and
## it was tuned until the assault rifle's stock cleared the frame — every other
## weapon still filled the lower third with a featureless slab, because a
## sniper's stock is 0.36 long and a pistol's barely exists. Moving along z
## keeps the sight on the camera axis, so alignment is unaffected either way.
const ADS_DEPTH := -0.86
## More negative is FURTHER from the lens. The first per-weapon pass had this
## backwards for the short guns and pushed the pistol to -0.52, which made it
## cover MORE of the frame than the single global value it replaced.
const ADS_DEPTH_BY_KEY := {
	"assault": -0.86, "sniper": -1.10, "shotgun": -1.02, "smg": -0.94, "pistol": -0.98,
}
## Only the TRIGGER arm leaves the frame when aiming. Dropping both meant ADS
## showed a gun held by nobody, which is the other half of what the critic was
## looking at: the support hand sits forward on the handguard, near the sight
## line, and stays visible in real aim-down-sights views.
const ADS_ARM_DROP := {
	"assault": 0.34, "sniper": 0.30, "shotgun": 0.32, "smg": 0.36, "pistol": 0.40,
}
var _ads_arm_drop: float = 0.34
var _near_z: float = 0.0
## Minimum clearance between the lens and the gun's nearest geometry when
## aimed. The reference keeps an aimed weapon under about a third of frame
## height; hand-tuned per-weapon depths put ours at half and swallowed the
## crosshair.
const ADS_NEAR_CLEAR := 0.92
var ads_pos := Vector3(0.0, -0.10, ADS_DEPTH)
var rest_rot := Vector3(0.045, 0.150, -0.235)     # the cant
## Krunker's signature is a CANTED, off-centre gun, and zeroing the cant on ADS
## threw that away at exactly the moment the sight picture matters. The cant is
## kept at ~40% while aimed; ads_pos below then solves for the ROTATED sight
## position, so alignment survives the tilt instead of being bought by
## flattening the gun into a vertical pillar.
## ~68% of the rest cant. At 40% the maths said "canted" and the frame still
## read dead-vertical, because the two arms sat near-symmetric about the
## centreline at that scale and the eye takes symmetry as upright.
var ads_rot := Vector3(0.026, 0.085, -0.160)

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
	if parent == _model:
		# Nearest-to-lens bound of the gun itself (arms excluded). ADS depth is
		# solved against this, because tuning depth purely for sight alignment
		# left the stock half a metre from the camera filling the frame.
		var reach: float = pos.z + size.z * 0.5 + absf(size.y * sin(rot.x)) * 0.5
		_near_z = maxf(_near_z, reach)
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
	_near_z = 0.0
	_arms = Node3D.new()
	_model.add_child(_arms)
	_arms_trigger = Node3D.new()
	_model.add_child(_arms_trigger)
	# Scaled up hard versus the first pass. In the reference shot the gun eats
	# roughly the lower-right third of the screen; ours was a distant twig.
	var gun := Color8(58, 61, 68)
	var dark := Color8(34, 35, 40)
	var wood := Color8(122, 82, 46)
	var wood_d := Color8(92, 60, 33)
	var brass := Color8(198, 156, 74)
	var grip_c := Color8(86, 74, 62)   # warm dark, reads apart from the receiver
	var muzzle_z := -0.5

	match key:
		"assault":
			# Slimmer receiver than the first pass. At 0.105 x 0.125 it was a
			# solid wedge that hid the magazine, grip and stock behind it, so
			# the gun did not parse as a gun at all — just a grey mass.
			_box(_model, Vector3(0.072, 0.088, 0.72), Vector3(0, 0, -0.16), gun)
			_box(_model, Vector3(0.046, 0.046, 0.40), Vector3(0, 0.010, -0.70), dark)
			_box(_model, Vector3(0.038, 0.038, 0.09), Vector3(0, 0.010, -0.92), brass)
			# magazine and grip pushed BELOW and canted so they clear the
			# receiver silhouette instead of hiding inside it
			_box(_model, Vector3(0.062, 0.24, 0.115), Vector3(0, -0.155, -0.02), dark,
				Vector3(0.20, 0, 0))
			_box(_model, Vector3(0.058, 0.16, 0.085), Vector3(0, -0.135, 0.20), grip_c,
				Vector3(-0.28, 0, 0))
			_box(_model, Vector3(0.055, 0.085, 0.28), Vector3(0, 0.004, 0.32), grip_c)  # stock
			_box(_model, Vector3(0.030, 0.062, 0.13), Vector3(0, 0.075, -0.32), dark)   # sight block
			# Stubby post on a wider base: a bare 0.016 column read as an
			# antenna once ADS magnified it.
			_box(_model, Vector3(0.030, 0.016, 0.026), Vector3(0, 0.098, -0.52), dark)
			_box(_model, Vector3(0.022, 0.030, 0.020), Vector3(0, 0.112, -0.52), brass)
			sight_local = Vector3(0, 0.118, -0.45)
			_box(_model, Vector3(0.082, 0.030, 0.24), Vector3(0, -0.058, -0.42), grip_c)
			_hands(Vector3(0, -0.135, 0.20), Vector3(0, -0.058, -0.40))
			muzzle_z = -0.96
		"sniper":
			_box(_model, Vector3(0.09, 0.10, 1.00), Vector3(0, 0, -0.22), wood_d)
			_box(_model, Vector3(0.052, 0.052, 0.52), Vector3(0, 0.010, -0.92), gun)
			# Scope as a hollow tube rather than a solid block, so you can
			# actually see through the bore. Four walls around a 0.05 bore; the
			# SubViewport has a transparent background, so the opening shows
			# the world behind it instead of a painted-on lens.
			_scope_tube(_model, Vector3(0, 0.125, -0.14), 0.34, 0.05, 0.019, dark, gun)
			_box(_model, Vector3(0.028, 0.05, 0.03), Vector3(0, 0.075, -0.26), gun)  # front mount
			_box(_model, Vector3(0.028, 0.05, 0.03), Vector3(0, 0.075, -0.02), gun)  # rear mount
			sight_local = Vector3(0, 0.125, -0.30)
			_box(_model, Vector3(0.035, 0.06, 0.06), Vector3(0, 0.075, -0.02), dark)   # bolt
			_box(_model, Vector3(0.06, 0.045, 0.14), Vector3(0.075, 0.055, 0.06), gun) # bolt handle
			_box(_model, Vector3(0.08, 0.23, 0.13), Vector3(0, -0.17, 0.02), wood)     # grip
			_box(_model, Vector3(0.08, 0.14, 0.36), Vector3(0, -0.02, 0.38), wood)     # stock
			_hands(Vector3(0, -0.17, 0.02), Vector3(0, -0.06, -0.44))
			muzzle_z = -1.20
		"shotgun":
			_box(_model, Vector3(0.135, 0.14, 0.74), Vector3(0, 0, -0.14), wood)
			_box(_model, Vector3(0.095, 0.095, 0.46), Vector3(0, 0.028, -0.70), dark)
			_box(_model, Vector3(0.105, 0.075, 0.30), Vector3(0, -0.082, -0.46), gun)  # pump
			_box(_model, Vector3(0.08, 0.22, 0.12), Vector3(0, -0.16, 0.04), dark)
			_box(_model, Vector3(0.085, 0.13, 0.30), Vector3(0, -0.02, 0.34), wood_d)
			_box(_model, Vector3(0.03, 0.03, 0.03), Vector3(0, 0.075, -0.90), brass)
			sight_local = Vector3(0, 0.075, -0.90)
			_hands(Vector3(0, -0.16, 0.04), Vector3(0, -0.082, -0.44))
			muzzle_z = -0.95
		"smg":
			_box(_model, Vector3(0.095, 0.115, 0.50), Vector3(0, 0, -0.06), gun)
			_box(_model, Vector3(0.055, 0.055, 0.24), Vector3(0, 0.010, -0.41), dark)
			_box(_model, Vector3(0.07, 0.30, 0.095), Vector3(0, -0.21, -0.04), dark)   # long mag
			_box(_model, Vector3(0.07, 0.16, 0.095), Vector3(0, -0.13, 0.17), gun)
			_box(_model, Vector3(0.05, 0.075, 0.22), Vector3(0, 0.0, 0.28), dark)      # wire stock
			_box(_model, Vector3(0.03, 0.055, 0.10), Vector3(0, 0.088, -0.24), dark)
			sight_local = Vector3(0, 0.088, -0.24)
			_hands(Vector3(0, -0.13, 0.17), Vector3(0, -0.115, -0.16))
			muzzle_z = -0.56
		_:
			_box(_model, Vector3(0.08, 0.145, 0.34), Vector3(0, 0, -0.05), gun)
			_box(_model, Vector3(0.048, 0.048, 0.12), Vector3(0, 0.02, -0.26), dark)
			_box(_model, Vector3(0.072, 0.19, 0.105), Vector3(0, -0.16, 0.045), dark)
			_box(_model, Vector3(0.025, 0.04, 0.03), Vector3(0, 0.078, -0.16), brass)
			sight_local = Vector3(0, 0.078, -0.16)
			_hands(Vector3(0, -0.16, 0.045), Vector3(0, -0.15, -0.02))
			muzzle_z = -0.34
	_muzzle.position = Vector3(0, 0.012, muzzle_z)
	# Put the sight on the camera axis when aimed. Previously ads_pos was a
	# hand-picked constant, so the sight picture sat well above the crosshair
	# and the two disagreed about where the bullet was going.
	# Solve depth so the nearest gun geometry clears the lens, then take the
	# further of that and the per-weapon hint. ADS_DEPTH_BY_KEY is now a floor,
	# not the answer.
	var solved: float = -(ADS_NEAR_CLEAR + _near_z)
	var depth: float = minf(float(ADS_DEPTH_BY_KEY.get(key, ADS_DEPTH)), solved)
	_ads_arm_drop = float(ADS_ARM_DROP.get(key, 0.34))
	# Solve for where the sight ends up AFTER the ADS cant is applied. Using the
	# unrotated sight_local only lands on the camera axis if the gun is
	# perfectly upright, which is why the cant had to be zeroed before.
	var aimed: Vector3 = Basis.from_euler(ads_rot) * sight_local
	ads_pos = Vector3(-aimed.x, -aimed.y, depth)
## Hands on the weapon. Every reference viewmodel shows forearms holding the
## gun; ours floated in the SubViewport with nothing gripping it, which is the
## loudest "not Krunker" tell left once the gun itself reads as a gun.
##
## Krunker's arms are CHUNKY and light tan, entering from the bottom-left and
## bottom-centre and filling a real share of the lower frame (see
## krunker_parkour_viewmodel_01.jpg). Two earlier attempts here used thin dark
## sticks that read as detached debris floating beside the receiver.
func _hands(grip: Vector3, fore: Vector3) -> void:
	const SKIN := Color8(206, 152, 106)
	const SKIN_D := Color8(170, 120, 82)
	const CUFF := Color8(58, 60, 66)
	# Support arm: up from the lower left into the handguard. The fist is built
	# from a palm, a knuckle row and a thumb rather than one block: under ADS
	# only this arm stays, and a single cube read as a detached lump of flesh.
	_box(_arms, Vector3(0.118, 0.100, 0.126), fore + Vector3(-0.016, -0.082, 0.016), SKIN)
	_box(_arms, Vector3(0.122, 0.038, 0.118), fore + Vector3(-0.018, -0.030, 0.020), SKIN_D)
	_box(_arms, Vector3(0.046, 0.062, 0.052), fore + Vector3(0.040, -0.058, -0.030), SKIN)
	_box(_arms, Vector3(0.108, 0.116, 0.330),
		fore + Vector3(-0.070, -0.300, 0.226), SKIN_D, Vector3(0.72, 0.0, 0.26))
	_box(_arms, Vector3(0.124, 0.128, 0.062),
		fore + Vector3(-0.036, -0.156, 0.082), CUFF, Vector3(0.72, 0.0, 0.26))
	# Trigger arm: up from the lower right into the grip. Kept clearly apart
	# from the support arm — at full size the two merged into one brown slab
	# across the bottom third of the frame.
	_box(_arms, Vector3(0.104, 0.112, 0.118), grip + Vector3(0.008, -0.036, 0.008), SKIN)
	_box(_arms, Vector3(0.100, 0.110, 0.320),
		grip + Vector3(0.086, -0.246, 0.176), SKIN_D, Vector3(0.58, 0.0, -0.38))
	_box(_arms, Vector3(0.116, 0.120, 0.060),
		grip + Vector3(0.038, -0.120, 0.054), CUFF, Vector3(0.58, 0.0, -0.38))

## A square-section optic you can see through: four walls around an open bore,
## with a slightly proud ring at each end so it reads as a scope and not a
## length of pipe.
func _scope_tube(parent: Node3D, centre: Vector3, length: float, bore: float,
		wall: float, body: Color, rim: Color) -> void:
	var off: float = bore * 0.5 + wall * 0.5
	var outer: float = bore + wall * 2.0
	_box(parent, Vector3(outer, wall, length), centre + Vector3(0, off, 0), body)
	_box(parent, Vector3(outer, wall, length), centre + Vector3(0, -off, 0), body)
	_box(parent, Vector3(wall, bore, length), centre + Vector3(-off, 0, 0), body)
	_box(parent, Vector3(wall, bore, length), centre + Vector3(off, 0, 0), body)
	for z in [-length * 0.5, length * 0.5]:
		var r: float = outer + 0.012
		var t: float = wall + 0.012
		var ro: float = bore * 0.5 + t * 0.5
		_box(parent, Vector3(r, t, 0.02), centre + Vector3(0, ro, z), rim)
		_box(parent, Vector3(r, t, 0.02), centre + Vector3(0, -ro, z), rim)
		_box(parent, Vector3(t, bore, 0.02), centre + Vector3(-ro, 0, z), rim)
		_box(parent, Vector3(t, bore, 0.02), centre + Vector3(ro, 0, z), rim)

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

	sway = sway.lerp(look_delta * -0.020, clampf(delta * 11.0, 0.0, 1.0))
	sway = sway.limit_length(0.038)

	kick = move_toward(kick, 0.0, delta * 2.4)
	kick_rot = move_toward(kick_rot, 0.0, delta * 7.5)

	var target_pos: Vector3 = rest_pos.lerp(ads_pos, ads_amount)
	var target_rot: Vector3 = rest_rot.lerp(ads_rot, ads_amount)
	var bob_scale: float = 1.0 - 0.8 * ads_amount
	# Sway has to fall away with ADS too. It was applied at full strength while
	# aimed, which walked the sight off the camera axis and put the sight
	# picture somewhere other than where the bullet was going.
	var steady: float = 1.0 - ads_amount
	# Slide the arms down and back as the gun comes up. At the rest offset they
	# sat right under the sight during ADS and read as one featureless brown
	# wedge; real aim-down-sights animations take the forearms out of frame.
	if _arms and _arms_trigger:
		# Break the left-right symmetry as well as dropping: two mirrored arms
		# under the receiver read as a centred pillar however much the gun is
		# actually canted. The trigger arm goes down and OUT to the right, the
		# support hand tucks slightly left and forward.
		_arms_trigger.position = Vector3(0.055 * ads_amount,
			-_ads_arm_drop * ads_amount, 0.18 * ads_amount)
		_arms.position = Vector3(-0.030 * ads_amount, -0.05 * ads_amount,
			0.05 * ads_amount)

	# reload dips the gun out of frame and rolls it, then brings it back
	var dip: float = sin(clampf(reload_t, 0.0, 1.0) * PI)

	var w: float = clampf(delta * 17.0, 0.0, 1.0)
	position = position.lerp(target_pos
		+ bob * bob_scale
		+ Vector3(sway.x, sway.y, 0.0) * steady
		+ Vector3(0, -dip * 0.20, kick * 0.34 * (0.35 + 0.65 * steady)), w)
	rotation = Vector3(
		lerpf(rotation.x, target_rot.x + kick_rot * 0.14 * (0.4 + 0.6 * steady) - dip * 0.9, w),
		lerpf(rotation.y, target_rot.y + sway.x * 1.5 * steady, w),
		lerpf(rotation.z, target_rot.z - sway.x * 2.0 * steady + dip * 0.5, w))
