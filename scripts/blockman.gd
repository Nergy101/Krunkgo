class_name Blockman
extends RefCounted
## Boxy character built from cubes. Owned by the block-art slice.
## Returns a Node3D whose parts are named so the animation code can find them:
## Head, Torso, ArmL, ArmR, LegL, LegR.

static func _part(parent: Node3D, part_name: String, size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.name = part_name
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	m.metallic_specular = 0.05
	mi.material_override = m
	parent.add_child(mi)
	return mi

static func build(tint: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Body"
	var skin := Color8(226, 178, 140)
	var dark := tint.darkened(0.35)

	# pivots let limbs swing from the shoulder/hip instead of the centre
	var torso := Node3D.new()
	torso.name = "TorsoPivot"
	torso.position = Vector3(0, 1.02, 0)
	root.add_child(torso)
	_part(torso, "Torso", Vector3(0.62, 0.72, 0.34), Vector3.ZERO, tint)

	var head_pivot := Node3D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position = Vector3(0, 1.52, 0)
	root.add_child(head_pivot)
	_part(head_pivot, "Head", Vector3(0.42, 0.42, 0.42), Vector3.ZERO, skin)
	_part(head_pivot, "Cap", Vector3(0.46, 0.10, 0.46), Vector3(0, 0.24, 0), dark)

	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "ArmR" if side > 0.0 else "ArmL"
		arm.position = Vector3(0.42 * side, 1.32, 0)
		root.add_child(arm)
		_part(arm, "Mesh", Vector3(0.2, 0.62, 0.2), Vector3(0, -0.31, 0), tint)

		var leg := Node3D.new()
		leg.name = "LegR" if side > 0.0 else "LegL"
		leg.position = Vector3(0.16 * side, 0.66, 0)
		root.add_child(leg)
		_part(leg, "Mesh", Vector3(0.24, 0.66, 0.26), Vector3(0, -0.33, 0), dark)
	return root

static func team_tint(index: int) -> Color:
	const TINTS := [
		Color8(214, 96, 60), Color8(70, 140, 210), Color8(120, 190, 90),
		Color8(200, 170, 70), Color8(160, 100, 200), Color8(220, 130, 180),
		Color8(90, 200, 190), Color8(230, 150, 70),
	]
	return TINTS[index % TINTS.size()]

## Damage zones, derived from the box geometry built above rather than guessed.
## Head sits at 1.52 with a 0.42 cube plus a 0.10 cap; the torso pivot is at
## 1.02 with a 0.62x0.72x0.34 box; arms hang from 1.32 and legs from 0.66.
## Everything is expressed at stand height 1.8 and scaled by the live capsule
## height, so crouching and sliding shrink the zones with the visible body.
## `zone` values are Hitbox.Zone: 0 HEAD, 1 BODY, 2 LIMB.
const ZONES := [
	{"zone": 0, "size": Vector3(0.48, 0.52, 0.48), "y": 1.55},   # head + cap
	{"zone": 1, "size": Vector3(0.64, 0.74, 0.36), "y": 1.02},   # torso
	{"zone": 2, "size": Vector3(0.60, 0.68, 0.30), "y": 0.34},   # legs
	{"zone": 2, "size": Vector3(1.06, 0.62, 0.22), "y": 1.01},   # arms
]
