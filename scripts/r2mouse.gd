extends Node
## Verifies the mouse-wipe guard in isolation: a keyboard selection must
## survive _process() when the mouse pointer is parked over empty UI space.
## Prints one JSON line ROUND2MOUSE.

func _ready() -> void:
	var main := get_parent()
	await get_tree().process_frame
	var menu: MainMenu = main.menu
	if menu == null:
		menu = MainMenu.new()
		main.add_child(menu)
	menu.screen = MainMenu.Screen.MAIN
	menu.active = true
	menu._keyboard_nav = false
	menu.hovered = -1
	menu._build_elements(menu.get_viewport().get_visible_rect().size)
	var ev := InputEventKey.new()
	ev.keycode = KEY_DOWN
	ev.pressed = true
	menu._input(ev)
	var after_key: int = menu.hovered
	# park the pointer where no button is (top-left corner of a 1280x720 view)
	Input.warp_mouse(Vector2(5, 5))
	await get_tree().process_frame
	menu._process(0.016)
	var after_process: int = menu.hovered
	print("ROUND2MOUSE ", JSON.stringify({
		"after_key": after_key,
		"after_process": after_process,
		"survives": after_key == 0 and after_process == 0,
	}))
	get_tree().quit(0)
