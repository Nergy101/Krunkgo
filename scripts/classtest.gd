extends Node
## Regression probe for the class-select state machine.
##
##   godot --path . -- classtest
##
## The picker is the one screen that hands control back to gameplay, so a
## mistake there silently costs you the ability to move. The first version
## restored whatever mouse mode was live when it opened, which at match start
## was MOUSE_MODE_VISIBLE, and Player gates all movement on the mouse being
## captured — so you spawned unable to move and nothing logged an error.

var player: Player
var checks: Array = []

func _ready() -> void:
	name = "ClassTest"
	await get_tree().process_frame
	await get_tree().process_frame
	player = Game.local_player as Player
	var main := get_parent()
	var cs: ClassSelect = main.get("class_select")
	if player == null or cs == null:
		print("CLASSTEST ", JSON.stringify({"error": "missing player or class_select"}))
		get_tree().quit(1)
		return

	# The match is live underneath this probe. Without immunity a bot kills the
	# player mid-test, which reopens the picker and overwrites the queued pick —
	# the probe then fails on its own interference rather than on a real bug.
	Tuning.spawn_protection = 9999.0

	# match-start path: opened before the mouse was ever captured
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cs.show_for("trigger", 0.0)
	_expect("picker opens visible", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	cs._commit("marksman")
	await get_tree().process_frame
	_expect("mouse captured after choosing", Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	_expect("picker closed", not cs.open and not cs.visible)
	_expect("class applied", player.class_id == "marksman")
	_expect("primary is sniper", String(player.loadout[0]) == "sniper")
	_expect("secondary is pistol", String(player.loadout[1]) == WeaponDefs.SECONDARY)
	_expect("player alive", player.alive)
	_expect("physics running", player.is_physics_processing())
	_expect("spawned off origin", player.global_position.length() > 1.0)

	# respawn path: lockout must delay the commit, not lose it
	cs.show_for("marksman", 0.4)
	cs._pick("rungun")
	_expect("pick during lockout is queued", cs.open and cs.pending == "rungun")
	await get_tree().create_timer(0.7).timeout
	checks.append({"check": "observed after lockout: open=%s pending='%s' class='%s'"
		% [cs.open, cs.pending, player.class_id], "ok": true})
	_expect("queued pick fired", not cs.open and player.class_id == "rungun")
	_expect("mouse captured after queued pick", Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)

	var failed: Array = checks.filter(func(c): return not c["ok"])
	print("CLASSTEST ", JSON.stringify({"checks": checks.size(),
		"failed": failed.size(), "detail": checks}))
	get_tree().quit(1 if failed.size() > 0 else 0)

func _expect(what: String, ok: bool) -> void:
	checks.append({"check": what, "ok": ok})
