extends Node
## Every number that decides how the game FEELS lives here.
##
## Ownership, so parallel agents do not fight:
##   MOVEMENT / CAMERA  -> movement-feel slice
##   COMBAT / MATCH     -> weapon + match-flow slices
##   BOTS               -> bot-behaviour slice
## Touch only your own block.

# ------------------------------------------------------------------ MOVEMENT
#
# The whole envelope was scaled down about a third after play testing: base
# 11 m/s with a 26 m/s slide-hop peak crossed the 64 m arena in ~2.5 s, which
# read as frantic rather than fast and left no time to aim. The SHAPE is
# unchanged — walking is still brisk, the diagonal strafe bonus is still
# Krunker's documented 1.2x, and chaining slide-hops still roughly doubles
# your speed — everything just happens at a pace you can fight at.
var gravity: float = 22.0
var max_ground_speed: float = 7.5
var ground_accel: float = 70.0
var ground_friction: float = 8.5
var stop_speed: float = 2.5
var air_accel: float = 42.0
var air_speed_cap: float = 1.3          # quake-style strafe accel window
var jump_velocity: float = 6.8          # apex ~1.05 m, still clears a crate
var jump_buffer: float = 0.12
var coyote_time: float = 0.09
var auto_bhop: bool = true
# Krunker has no sprint key. Holding two direction keys is the speed bonus, and
# custom games expose it as "Strafe Speed", default 1.2x.
var strafe_bonus: float = 1.2

var stand_height: float = 1.8
var crouch_height: float = 1.0
var eye_height: float = 1.62
var crouch_eye_height: float = 0.92
var crouch_speed_mult: float = 0.45
var stance_lerp: float = 14.0

var slide_min_speed: float = 4.5
var slide_gain: float = 1.10            # multiplicative, so hops compound
var slide_boost: float = 1.25
# Equal to hard_speed_cap on purpose: the ceiling should be set by how well you
# chain hops, not by a lower constant the chain slams into after three of them.
var slide_speed_cap: float = 16.5
# reference/krunker-movement.md section 4: about a quarter second to re-jump
# out of a slide before friction takes the speed back.
var slide_rejump_window: float = 0.25
var slide_late_penalty: float = 0.88
var slide_friction: float = 0.9
var slide_min_time: float = 0.16
var slide_max_time: float = 1.1
# Short enough that the ~0.25s re-jump window out of a slide stays open.
var slide_cooldown: float = 0.14

# Wall-jump. reference/krunker-movement.md section 6: a class-defining
# traversal mechanic, limited to a few consecutive kicks and reset by touching
# the floor. Charges are restored on landing, never mid-air.
var wall_jump_velocity: float = 6.4
var wall_jump_push: float = 4.4
var wall_jump_charges: int = 2

## Ledges up to this tall are walked over, no jump needed. One map block is
## 1.0, so this clears a single block with margin. Anything taller is a wall
## you have to jump, which keeps stair stacks readable as traversal and walls
## readable as cover.
var step_height: float = 1.05

var hard_speed_cap: float = 16.5

var mouse_sensitivity: float = 0.0022
var pitch_limit: float = 1.5533         # ~89 degrees

# -------------------------------------------------------------------- CAMERA
var fov: float = 90.0
var fov_speed_bonus: float = 9.0
var ads_fov_mult: float = 0.62
var ads_time: float = 0.11
var view_bob_amount: float = 0.015
var view_bob_speed: float = 11.0
var land_kick: float = 0.10
var roll_amount: float = 0.028          # ~1.6 degrees of lean per strafe

# -------------------------------------------------------------------- COMBAT
var max_health: float = 100.0
var regen_delay: float = 5.0
var regen_rate: float = 14.0
var headshot_mult: float = 2.0
var limb_mult: float = 0.85
var melee_damage: float = 100.0
var melee_range: float = 2.6
var melee_cooldown: float = 0.6

# --------------------------------------------------------------------- MATCH
# Krunker's own Free For All is purely time-limited (reference: Game Modes —
# "most points at the end" wins); it exposes no score cap or documented
# respawn/spawn-protection numbers. We keep a score-limit win condition since
# our custom-lobby feel wants a match that can end early on a blowout, and
# choose the undocumented respawn/protection values to match the "everything
# kills fast and cleanly" arcade identity from the Combat feel summary.
var score_limit: int = 30
var match_seconds: float = 240.0        # Krunker Public Game Modes: 4-minute timer
var respawn_delay: float = 1.2
var spawn_protection: float = 1.5       # long enough to get oriented, not to camp
var intermission_seconds: float = 6.0   # final-board hang time before auto-restart
var bot_count: int = 7

# ---------------------------------------------------------------------- BOTS
var bot_reaction_min: float = 0.14
var bot_reaction_max: float = 0.30
var bot_aim_speed: float = 9.0
var bot_aim_error_deg: float = 3.2
var bot_fov_deg: float = 130.0
var bot_sight_range: float = 90.0
var bot_strafe_period: float = 0.85
var bot_leave_cover_chance: float = 0.6
# Below this health fraction a bot breaks contact instead of trading.
var bot_retreat_health: float = 0.34

func _ready() -> void:
	_setup_input()

func _bind(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for e in events:
		InputMap.action_add_event(action, e)

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

func _mb(code: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = code
	return e

func _setup_input() -> void:
	_bind("move_forward", [_key(KEY_W), _key(KEY_UP)])
	_bind("move_back", [_key(KEY_S), _key(KEY_DOWN)])
	_bind("move_left", [_key(KEY_A), _key(KEY_LEFT)])
	_bind("move_right", [_key(KEY_D), _key(KEY_RIGHT)])
	_bind("jump", [_key(KEY_SPACE)])
	_bind("crouch", [_key(KEY_SHIFT), _key(KEY_CTRL), _key(KEY_C)])
	_bind("fire", [_mb(MOUSE_BUTTON_LEFT)])
	_bind("aim", [_mb(MOUSE_BUTTON_RIGHT)])
	_bind("reload", [_key(KEY_R)])
	_bind("melee", [_key(KEY_V), _key(KEY_F)])
	_bind("slot_1", [_key(KEY_1)])
	_bind("slot_2", [_key(KEY_2)])
	_bind("slot_3", [_key(KEY_3)])
	_bind("next_weapon", [_key(KEY_Q)])
	_bind("scoreboard", [_key(KEY_TAB)])
	_bind("ui_pause", [_key(KEY_ESCAPE)])
	_bind("debug_toggle", [_key(KEY_F3)])
	_bind("restart", [_key(KEY_F5)])
