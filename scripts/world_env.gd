class_name WorldEnv
extends RefCounted
## Sky, sun, fog, ambient shading. Split out of main.gd so art and match-flow
## never edit the same file.
##
## Tuned against reference/bar/krunker_burg_overview_01.webp. Three things that
## screenshot does and our first pass did not:
##   1. a pale warm near-white horizon, not a saturated blue gradient
##   2. hard, clearly-directional sun so a cube shows three distinct face
##      brightnesses — that separation is what makes blocky forms read
##   3. visible darkening where surfaces meet, which Krunker exposes as its
##      "Ambient Shading" toggle. Without it a village of cubes turns to mush.

static func build(parent: Node3D) -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()

	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Palette.SKY_TOP
	mat.sky_horizon_color = Palette.SKY_HORIZON
	mat.sky_curve = 0.34   # thinner blue band, horizon haze carries further up
	mat.ground_bottom_color = Palette.FOG_COLOR.darkened(0.15)
	mat.ground_horizon_color = Palette.SKY_HORIZON
	mat.ground_curve = 0.05
	mat.sun_angle_max = 8.0
	mat.sun_curve = 0.08
	sky.sky_material = mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Pure sky ambient tints every upward-facing surface blue, which fought the
	# neutral stone the art pass is aiming for. Blend some flat white back in.
	env.ambient_light_sky_contribution = 0.5
	env.ambient_light_color = Color8(226, 222, 214)
	# Enough sky fill that building interiors read as rooms rather than black
	# voids, without flattening lit and shadowed faces to the same value.
	env.ambient_light_energy = 0.95

	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.7
	env.ssao_power = 2.0
	env.ssao_detail = 0.4
	env.ssao_horizon = 0.1

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 3.4
	env.tonemap_exposure = 1.05
	# Krunker leaves edges hard: no bloom, minimal post.
	env.glow_enabled = false

	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.06

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Palette.FOG_COLOR
	env.fog_light_energy = 1.0
	env.fog_depth_begin = 110.0
	env.fog_depth_end = 220.0
	env.fog_density = 0.25
	env.fog_sky_affect = 0.0
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Palette.SUN_COLOR
	sun.light_energy = 2.6
	sun.light_angular_distance = 0.15     # hard shadow edges, as in the bar
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# The arena is 64 m across, so 120 m of shadow range was paying for empty
	# sky. Fixing the face winding made every surface a real shadow caster for
	# the first time and halved the frame rate; this buys it back.
	sun.directional_shadow_max_distance = 62.0
	sun.directional_shadow_split_1 = 0.12
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.8
	# Low-ish western sun: long shadows across the lanes give the blocks depth
	# and make the terracotta roofs glow the way they do in the bar shot.
	sun.rotation_degrees = Vector3(-38, 143, 0)
	parent.add_child(sun)

	var bounce := DirectionalLight3D.new()
	bounce.name = "Bounce"
	# Cheap stand-in for the warm ground bounce visible on shaded walls in the
	# reference. No shadows: it is fill, not a second sun.
	bounce.light_color = Color8(206, 198, 186)
	bounce.light_energy = 0.35
	bounce.shadow_enabled = false
	bounce.rotation_degrees = Vector3(28, -40, 0)
	parent.add_child(bounce)
