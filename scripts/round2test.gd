extends Node
## Round-2 gap-closure regression probe: the three fixes the critics' gaps
## demanded, each asserted headlessly.
##   godot --path . -- round2test
func _ready() -> void:
	var main := get_parent()
	var checks := {}
	await get_tree().process_frame

	# --- 1. menu keyboard nav: simulating a keypress must own the highlight
	var menu: MainMenu = main.menu
	if menu != null:
		# Round-2 test registers as a probe, so the interactive boot branch
		# never built the menu; build it directly and put it in MAIN state.
		checks["menu exists"] = true
		menu.screen = MainMenu.Screen.MAIN
		menu.active = true
		menu._build_elements(menu.get_viewport().get_visible_rect().size)
		menu.hovered = -1        # start from no selection, like a fresh menu
		menu._keyboard_nav = false
		# simulate DOWN key through the same path _input uses
		var ev := InputEventKey.new()
		ev.keycode = KEY_DOWN
		ev.pressed = true
		menu._input(ev)
		checks["keyboard down selects row 0"] = menu.hovered == 0
		menu._input(ev)
		checks["keyboard down again selects row 1"] = menu.hovered == 1
		# _process() with the mouse away must NOT wipe the keyboard selection
		menu._process(0.016)
		checks["mouse position does not wipe keyboard selection"] = menu.hovered == 1
		menu.close()
	else:
		checks["menu exists"] = false

	# --- 2. map swap resets the match
	Tuning.bot_count = 3
	var before_mode: String = Game.mode_name()
	checks["boot mode is FFA on burg"] = before_mode == "FREE FOR ALL"
	Game.register_actor("R2TEST", 0)
	Game.report_kill("R2TEST", "R2VICTIM", "assault", false)
	checks["score registered before swap"] = Game.team_total(0) == 1
	await main._rebuild_map()
	await get_tree().process_frame
	checks["map cycled to standoff"] = MapData.map_id == "standoff"
	checks["mode switched to TDM"] = Game.is_tdm()
	checks["scores cleared by map swap"] = Game.scores.is_empty()
	checks["clock reset by map swap"] = Game.time_left == Tuning.match_seconds

	# --- 3. standoff spawns remain side-separated after the rebuild
	var blue: Vector3 = main.arena.random_team_spawn(0)
	var red: Vector3 = main.arena.random_team_spawn(1)
	checks["blue spawns north"] = blue.z > 0.0
	checks["red spawns south"] = red.z < 0.0

	print("ROUND2TEST ", JSON.stringify(checks))
	var fails := 0
	for k in checks:
		if checks[k] != true:
			fails += 1
	get_tree().quit(1 if fails > 0 else 0)
