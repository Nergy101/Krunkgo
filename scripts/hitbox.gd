class_name Hitbox
extends Area3D
## One damage zone on an actor. Hitscan raycasts hit these (layer 3, areas on).
## Damage always arrives through a zone, which is what makes headshots a real,
## judgeable mechanic. The multiplier lives on the WEAPON, not here, because
## Krunker varies it per weapon (the SMG has no headshot bonus at all).

enum Zone { HEAD, BODY, LIMB }

@export var zone: Zone = Zone.BODY
var actor: Node3D

func _init() -> void:
	collision_layer = 4      # bit 3 = hitbox
	collision_mask = 0
	monitoring = false
	monitorable = true
	input_ray_pickable = false

static func make(actor_ref: Node3D, zone_kind: Zone, size: Vector3, offset: Vector3) -> Hitbox:
	var h := Hitbox.new()
	h.zone = zone_kind
	h.actor = actor_ref
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = offset
	h.add_child(cs)
	h.name = "Hitbox_" + ["HEAD", "BODY", "LIMB"][zone_kind]
	return h
