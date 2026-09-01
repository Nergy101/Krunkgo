extends Node
## Boots into the start menu (tree paused, nothing spawned), changes a setting
## through the menu, presses Play, and checks the world actually starts: the
## tree unpauses, bots spawn to the chosen count, the HUD comes back, and the
## class picker opens.
##
## Runs whenever the `menutest` flag is set:
##   godot --path . -- menutest

func _ready() -> void:
	var checks := {}
	var main := get_parent()

	# Let the menu layer settle after main._ready builds it.
	await get_tree().process_frame

	var menu: MainMenu = main.menu
	checks["menu exists"] = menu != null
	checks["tree paused at menu"] = get_tree().paused
	checks["hud hidden at menu"] = main.hud.visible == false

	# Tune through the menu and confirm it reaches the Tuning/MapData autoloads.
	menu.screen = MainMenu.Screen.SETTINGS
	menu.map_index = 1                   # STANDOFF
	menu.bot_count = 3
	menu.difficulty_index = 0            # EASY
	menu._apply_settings()
	checks["bot_count applied"] = Tuning.bot_count == 3
	checks["difficulty applied"] = Tuning.bot_aim_error_deg > 8.0
	checks["map selection applied"] = MapData.map_id == "standoff"

	# Press Play: unpause, spawn bots, bring the HUD back, open the picker.
	# The chosen map differs from the boot-built one, so the arena is rebuilt.
	await main._on_menu_play()
	await get_tree().process_frame
	checks["unpaused after play"] = not get_tree().paused
	checks["bots spawned to count"] = main.bots.size() == 3
	checks["hud visible after play"] = main.hud.visible == true
	checks["class picker open"] = main.class_select.open
	checks["chosen map still active after play"] = MapData.map_id == "standoff"
	checks["arena rebuilt to chosen map"] = is_instance_valid(main.arena)
	# _hold_at_menu steals the camera to a free overview cam and hides the
	# viewmodel layer; Play must hand both back to the player.
	checks["player camera current after play"] = main.player.camera.current == true
	var vl: Node = main.get_node_or_null("ViewmodelLayer")
	if vl == null and is_instance_valid(main.player):
		vl = main.player.get_node_or_null("ViewmodelLayer")
	checks["viewmodel visible after play"] = vl != null and vl.visible

	print("MENUTEST ", JSON.stringify(checks))
	get_tree().quit(0)
