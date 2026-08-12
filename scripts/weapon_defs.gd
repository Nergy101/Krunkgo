class_name WeaponDefs
extends RefCounted
## Weapon table. Plain dictionaries, not .tres, so parallel agents can edit it
## without resource-uid conflicts. Owned by the weapon-feedback slice.
##
## Numbers are anchored to sourced Krunker values in reference/krunker-weapons.md
## (krunkerio.fandom.com + community datamine). Where Krunker publishes only a
## unitless multiplier we pick a concrete value and say so.
##
## damage       per pellet, before zone multiplier
## hs_mult      headshot multiplier (Krunker varies this PER WEAPON; SMG is 1.0)
## limb_mult    arm/leg multiplier (0.5 across the board in Krunker)
## interval     seconds between shots (Krunker publishes ms, not rpm)
## spread_*     degrees of cone
## recoil       {"up": deg, "side": deg, "recover": deg/s}
## falloff      [start_m, end_m, min_mult]
## ads_fov      multiplier on Tuning.fov while aimed. 0.62 is the ~1.9x that
##              iron sights give; the sniper's 0.33 is a true optic, twice
##              again as tight, and `scoped` swaps its reticle for a scope.
## -- everything below this line is FEEDBACK ONLY, not sourced ballistics --
## muzzle_flash strength fed to Fx.muzzle_flash() (light energy + flash quad size)
## shake        camera-shake magnitude read by player.gd
## kick         viewmodel recoil-impulse magnitude (Viewmodel.punch())
## tone         Audio bank key for the per-shot gunshot; each weapon owns its
##              own synthesised waveform, not just a pitch-shifted shared one
## pitch        playback pitch multiplier for `tone`
## has_bolt     bolt-action mechanical layer (post-shot cycle sound) in Audio
## shell_color  ejected-casing tint in Fx (brass vs shotgun hull)
## shell_scale  ejected-casing size multiplier in Fx
## vm_snap      Viewmodel per-shot rotational-impulse strength
## vm_stiff     Viewmodel recoil-spring stiffness (higher = snaps back faster)
## vm_damp      Viewmodel recoil-spring damping (lower = more overshoot/bounce)
## vm_twist     Viewmodel side-twist (roll) mixed into the recoil snap

const LIST := {
	"assault": {
		"ads_fov": 0.62,
		"display": "ASSAULT RIFLE",
		"damage": 23.0, "hs_mult": 1.5, "limb_mult": 0.5, "pellets": 1,
		"interval": 0.130, "mag": 28, "reserve": 140, "reload": 1.50, "switch": 0.40,
		"spread_hip": 1.8, "spread_ads": 0.45, "spread_move": 0.9,
		"recoil": {"up": 0.55, "side": 0.28, "recover": 7.5},
		"falloff": [26.0, 68.0, 0.6],
		"auto": true, "move_mult": 1.05,
		"muzzle_flash": 0.95, "shake": 0.34, "kick": 0.052,
		"tone": "crack_ar", "pitch": 1.0,
		"shell_color": Color8(200, 158, 76), "shell_scale": 1.0,
		"vm_snap": 6.0, "vm_stiff": 260.0, "vm_damp": 22.0, "vm_twist": 0.30,
	},
	"sniper": {
		"ads_fov": 0.33, "scoped": true,
		"display": "SNIPER RIFLE",
		"damage": 100.0, "hs_mult": 1.5, "limb_mult": 0.5, "pellets": 1,
		"interval": 1.000, "mag": 3, "reserve": 24, "reload": 1.90, "switch": 0.70,
		"spread_hip": 5.0, "spread_ads": 0.0, "spread_move": 2.6,
		"recoil": {"up": 3.2, "side": 0.5, "recover": 3.0},
		"falloff": [200.0, 240.0, 1.0],
		"auto": false, "move_mult": 1.0,
		"muzzle_flash": 1.9, "shake": 1.15, "kick": 0.24,
		"tone": "boom_sniper", "pitch": 0.68, "has_bolt": true,
		"shell_color": Color8(184, 140, 64), "shell_scale": 1.7,
		"vm_snap": 11.0, "vm_stiff": 85.0, "vm_damp": 7.2, "vm_twist": 0.95,
	},
	"smg": {
		"ads_fov": 0.7,
		"display": "SUBMACHINE GUN",
		"damage": 18.0, "hs_mult": 1.0, "limb_mult": 0.5, "pellets": 1,
		"interval": 0.075, "mag": 30, "reserve": 180, "reload": 1.40, "switch": 0.32,
		"spread_hip": 2.4, "spread_ads": 1.1, "spread_move": 0.9,
		"recoil": {"up": 0.40, "side": 0.32, "recover": 9.0},
		"falloff": [16.0, 42.0, 0.5],
		"auto": true, "move_mult": 1.18,
		"muzzle_flash": 0.55, "shake": 0.15, "kick": 0.024,
		"tone": "buzz_smg", "pitch": 1.08,
		"shell_color": Color8(202, 162, 82), "shell_scale": 0.72,
		"vm_snap": 3.6, "vm_stiff": 480.0, "vm_damp": 44.0, "vm_twist": 0.14,
	},
	"shotgun": {
		"ads_fov": 0.85,
		"display": "SHOTGUN",
		# 5 pellets at 10 = 50 total, per the datamined "~50 total/shot at close
		# range" and the 1.25x head multiplier (post-v5.6.9, down from 1.5).
		# Was 8 x 15 = 120, which one-shot a 100 HP target point-blank where the
		# reference needs two. Nothing caught it because the probe derived its
		# expectations from these same numbers.
		"damage": 10.0, "hs_mult": 1.25, "limb_mult": 0.5, "pellets": 5,
		"interval": 0.800, "mag": 6, "reserve": 36, "reload": 2.40, "switch": 0.55,
		"spread_hip": 6.0, "spread_ads": 4.2, "spread_move": 3.0,
		"recoil": {"up": 2.2, "side": 0.8, "recover": 4.5},
		"falloff": [9.0, 24.0, 0.15],
		"auto": false, "move_mult": 1.0,
		"muzzle_flash": 1.7, "shake": 0.9, "kick": 0.21,
		"tone": "boom_shotgun", "pitch": 0.85,
		"shell_color": Color8(198, 72, 42), "shell_scale": 1.35,
		"vm_snap": 10.0, "vm_stiff": 95.0, "vm_damp": 8.0, "vm_twist": 1.1,
	},
	"pistol": {
		"ads_fov": 0.7,
		"display": "PISTOL",
		# 20 damage, 1.5x head, per datamine: 5 shots to kill body, 4 to head.
		# Was 34, which killed in 3.
		"damage": 20.0, "hs_mult": 1.5, "limb_mult": 0.5, "pellets": 1,
		"interval": 0.150, "mag": 12, "reserve": 72, "reload": 1.30, "switch": 0.28,
		"spread_hip": 1.4, "spread_ads": 0.28, "spread_move": 0.8,
		"recoil": {"up": 1.1, "side": 0.35, "recover": 8.0},
		"falloff": [20.0, 50.0, 0.6],
		"auto": false, "move_mult": 1.1,
		"muzzle_flash": 0.85, "shake": 0.33, "kick": 0.078,
		"tone": "pop_pistol", "pitch": 1.1,
		"shell_color": Color8(204, 166, 86), "shell_scale": 0.68,
		"vm_snap": 6.4, "vm_stiff": 300.0, "vm_damp": 24.0, "vm_twist": 0.45,
	},
}

const LOADOUT := ["assault", "sniper", "shotgun", "smg", "pistol"]

## A class is just a primary. Everyone carries the pistol as a secondary, so
## no class can ever be left without an answer at close range.
const SECONDARY := "pistol"

const CLASSES := [
	{"id": "trigger", "name": "TRIGGERMAN", "primary": "assault",
		"blurb": "All-rounder. Punishes at any range."},
	{"id": "rungun", "name": "RUN N GUN", "primary": "smg",
		"blurb": "Fastest gun up close. Bring movement."},
	{"id": "marksman", "name": "MARKSMAN", "primary": "sniper",
		"blurb": "One shot, one kill. Hold the long lane."},
	{"id": "spray", "name": "SPRAY N PRAY", "primary": "shotgun",
		"blurb": "Devastating inside a room. Useless outside one."},
]

static func class_by_id(id: String) -> Dictionary:
	for c in CLASSES:
		if c["id"] == id:
			return c
	return CLASSES[0]

static func class_primary(id: String) -> String:
	return String(class_by_id(id)["primary"])

static func get_def(key: String) -> Dictionary:
	var d: Dictionary = LIST.get(key, LIST["assault"]).duplicate(true)
	d["key"] = key
	return d

static func zone_mult(def: Dictionary, zone: int) -> float:
	match zone:
		Hitbox.Zone.HEAD:
			return float(def["hs_mult"])
		Hitbox.Zone.LIMB:
			return float(def["limb_mult"])
		_:
			return 1.0

static func falloff_mult(def: Dictionary, dist: float) -> float:
	var f: Array = def["falloff"]
	if dist <= float(f[0]):
		return 1.0
	var t: float = clampf(inverse_lerp(float(f[0]), float(f[1]), dist), 0.0, 1.0)
	return lerpf(1.0, float(f[2]), t)
