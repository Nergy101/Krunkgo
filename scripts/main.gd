extends Node3D
## Assembles the whole game: sky, sun, arena, fx, hud, player, bots, and the
## respawn loop. Also registers the harness shot sets so every critic compares
## identical camera angles round to round.

var arena: MapBuilder
var player: Player
var bots: Array[Bot] = []
var fx: Fx
var hud: Hud
var class_select: ClassSelect
var menu: MainMenu = null
var free_cam: Camera3D
var _pending: Array = []          # [{"actor": Actor, "t": float}]
var _paused: bool = false
var _menu_open: bool = false
var _built_map: String = ""       # the map the boot arena was built for

const BOT_NAMES := ["ZANE", "KRUX", "VOLT", "NIKO", "BRIX", "AXEL", "MERC", "ODIN",
	"RUSK", "JETT", "CLAW", "PIKE"]
const VOID_Y := -20.0   # fall below this and it counts as an out-of-bounds death

func _ready() -> void:
	# Keeps running while get_tree().paused so the pause/restart keys still
	# work; every child below gets its own explicit PAUSABLE so pause still
	# freezes the actual game instead of cascading ALWAYS down to them.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Pick the arena before the first build. `map=standoff` from the harness
	# (or whatever the M key last cycled to) is consumed here; nothing is built
	# until arena.build() below, so this must come first.
	if Harness.args.has("map"):
		MapData.select_map(String(Harness.args["map"]))

	# Connect before the first reset_match(): Game.actors is still empty at
	# that call, so the handler no-ops and every actor below gets exactly one
	# spawn from its own creation code. The connection only matters for real
	# restarts (post-intermission, F5), which happen once actors exist.
	Game.match_started.connect(_on_match_started)
	Game.reset_match()

	WorldEnv.build(self)

	arena = MapBuilder.new()
	add_child(arena)
	arena.build()
	await arena.validate_reachability()
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	Game.arena = arena

	fx = Fx.new()
	add_child(fx)
	fx.process_mode = Node.PROCESS_MODE_PAUSABLE
	Game.fx = fx

	hud = Hud.new()
	add_child(hud)
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE

	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.died.connect(_on_actor_died.bind(player))
	Game.actors.append(player)

	class_select = ClassSelect.new()
	add_child(class_select)
	class_select.chosen.connect(_on_class_chosen)

	free_cam = Camera3D.new()
	free_cam.fov = Tuning.fov
	free_cam.far = 400.0
	add_child(free_cam)
	free_cam.process_mode = Node.PROCESS_MODE_PAUSABLE

	player.set_class(player.class_id)
	if _show_menu():
		# Menu path: the arena is built but nothing is spawned yet. Bots and
		# the player are created on Play so the settings apply; the world
		# freezes behind the menu until then.
		_hold_at_menu()
	elif _interactive():
		# opening lockout is 0: at match start there is nothing to wait for
		class_select.show_for(player.class_id, 0.0)
		_spawn_bots()
	else:
		player.respawn(_spawn_point_for(player))
		_spawn_bots()

	Harness.register_shot_set("fx", _shots_fx)
	Harness.register_shot_set("class", _shots_class)
	Harness.register_shot_set("ads", _shots_ads)
	Harness.register_shot_set("map", _shots_map)
	Harness.register_shot_set("menu", _shots_menu)
	Harness.register_shot_set("game", _shots_game)
	Harness.register_shot_set("default", _shots_game)

	if Harness.botfight:
		player.input_enabled = false
	if not _show_menu() and not Harness.active and not Harness.botfight:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Headless probes self-register under a flag. Guarded by ResourceLoader so a
	# probe file that does not exist yet is simply skipped.
	for probe in ["movetest", "bottest", "hittest", "classtest", "menutest", "round2test"]:
		var path := "res://scripts/%s.gd" % probe
		if Harness.want(probe) and ResourceLoader.exists(path):
			add_child(load(path).new())


func _process(delta: float) -> void:
	if _menu_open:
		# On the start menu the tree is paused and nothing should react to
		# the pause/restart keys (they would unpause the frozen world behind
		# the menu). The menu owns all input here.
		return
	if Input.is_action_just_pressed("ui_pause"):
		_toggle_pause()
	if Input.is_action_just_pressed("restart"):
		_restart()
	if _paused:
		return

	if Input.is_action_just_pressed("ui_map_next"):
		_rebuild_map()
		return

	for a in Game.actors:
		if is_instance_valid(a) and a.is_alive() and a.global_position.y < VOID_Y:
			# Fall/out-of-bounds death: no attacker, so Actor._die() credits the
			# kill to the victim itself and report_kill() scores it a suicide.
			a.apply_damage(99999.0, null, Hitbox.Zone.BODY, a.global_position)

	# Nothing respawns once the match is over. The intermission is six seconds
	# long and combat used to run right through it: bots kept fighting under
	# the MATCH OVER scoreboard, and a player who died in that window got the
	# class picker on top of the final standings.
	if not Game.running:
		return

	for entry in _pending:
		entry["t"] -= delta
	var ready_now := _pending.filter(func(e): return e["t"] <= 0.0)
	_pending = _pending.filter(func(e): return e["t"] > 0.0)
	for e in ready_now:
		var a: Actor = e["actor"]
		if is_instance_valid(a):
			a.respawn(_spawn_point_for(a))
			if a == player:
				Audio.play("spawn", 1.0, -10.0)

## Every other tracked actor, so a respawn never scores a candidate against
## itself (its old, about-to-be-overwritten position).
func _living_others(exclude: Actor) -> Array:
	var out: Array = []
	for a in Game.actors:
		if a != exclude and is_instance_valid(a):
			out.append(a)
	return out

func _toggle_pause() -> void:
	_paused = not _paused
	get_tree().paused = _paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _paused else Input.MOUSE_MODE_CAPTURED

## Clean, in-place restart: no scene reload. Unpauses first so a paused
## restart does not leave the game frozen underneath the fresh match.
func _restart() -> void:
	if _paused:
		_toggle_pause()
	Game.reset_match()

## Swap the arena for the other map (M key) and put everyone back in play.
func _rebuild_map() -> void:
	MapData.cycle_map()
	await _apply_map()
	# A map swap can change the mode (standoff<->burg, TDM<->FFA). Kills,
	# deaths, team totals and the clock must not carry across the mode
	# boundary: the HUD chip and the win check would otherwise operate on
	# stale cross-mode numbers (found by the round-2 TDM critic).
	# reset_match() emits match_started, whose handler respawns everyone
	# again — harmless (fresh spawns after _apply_map's own respawn pass),
	# and it is what clears the intermission so play resumes at once.
	Game.reset_match()
	Game.intermission_left = 0.0

## Rebuild the arena for whatever MapData.map_id is now set to, and put every
## actor back in play on the new geometry. The old MapBuilder is freed, a fresh
## one is built and nav-baked, then everyone respawns so nobody is left standing
## inside the old one. Used by the M key and by Play when the settings picked a
## different map.
func _apply_map() -> void:
	if is_instance_valid(arena):
		arena.queue_free()
	await get_tree().process_frame
	arena = MapBuilder.new()
	add_child(arena)
	arena.build()
	await arena.validate_reachability()
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	Game.arena = arena
	# Swapping maps can change the mode (standoff↔burg); re-team/re-colour
	# everyone so friendlies stay blue and opponents red.
	_configure_teams()
	for a in Game.actors:
		if is_instance_valid(a):
			a.respawn(_spawn_point_for(a))
	Audio.play("spawn", 1.0, -10.0)
	Game.announce.emit("MAP — " + MapData.map_display(), "match")

## Fires on every Game.match_started — first boot (no-op, no actors exist
## yet), the post-intermission auto-restart, and a manual F5 restart. Clears
## any respawn timers left over from the old match and puts everyone back in
## play immediately.
func _on_match_started() -> void:
	_pending.clear()
	for a in Game.actors:
		if is_instance_valid(a):
			a.respawn(_spawn_point_for(a))
	if is_instance_valid(player):
		Audio.play("spawn", 1.0, -10.0)

func _on_actor_died(_killer: Actor, who: Actor) -> void:
	if not Game.running:
		return          # match over: no queue, and no picker over the scoreboard
	if who == player and _interactive():
		# Bots respawn on a timer; you respawn when you have picked. The
		# lockout keeps the death penalty honest, but you can choose during it
		# and spawn the instant it expires.
		class_select.show_for(player.class_id, Tuning.respawn_delay)
		return
	_pending.append({"actor": who, "t": Tuning.respawn_delay})

func _on_class_chosen(id: String) -> void:
	player.set_class(id)
	player.respawn(_spawn_point_for(player))
	Audio.play("spawn", 1.0, -10.0)

## Screenshot and probe runs have nobody at the keyboard, so they must never
## sit on a menu waiting for a key that will not come.
func _interactive() -> bool:
	if Harness.want("classtest"):
		return true                      # this probe exists to drive the picker
	return not Harness.active and not Harness.botfight and not Harness.want("movetest") \
		and not Harness.want("bottest") and not Harness.want("hittest")

## Real interactive play (someone at a keyboard) should land on the start menu
## first. The classtest probe drives the class picker directly, so it must
## skip the menu like every other headless path.
func _show_menu() -> bool:
	return _interactive() and not Harness.want("classtest")

## Freeze the freshly-built arena behind the start menu. The world is fully
## built but nothing is spawned yet — bots and the player are created on Play,
## so the settings (bot count, difficulty, match length) are honoured.
func _hold_at_menu() -> void:
	menu = MainMenu.new()
	add_child(menu)
	menu.process_mode = Node.PROCESS_MODE_ALWAYS
	menu.play_pressed.connect(_on_menu_play)
	menu.quit_pressed.connect(_on_menu_quit)
	var overview: Dictionary = MapData.review_cameras()[0]
	_use_free_cam(overview["pos"], overview["look"])
	# The HUD describes a match nobody is playing yet; hide it behind the menu.
	hud.visible = false
	_built_map = MapData.map_id
	_menu_open = true
	get_tree().paused = true

## Create exactly Tuning.bot_count bots. Called at boot on menu-less runs and
## again on Play, so a bot count chosen in the settings is honoured.
## In Team Deathmatch the bots are split evenly between blue (with the player)
## and red, and each wears its team colour; in FFA each keeps a unique tint.
func _spawn_bots() -> void:
	for i in Tuning.bot_count:
		var b := Bot.new()
		b.display_name = BOT_NAMES[i % BOT_NAMES.size()]
		b.team = _bot_team(i)
		b.tint = _bot_tint(i)
		b.name = "Bot_" + b.display_name
		b.loadout_index = i
		add_child(b)
		b.process_mode = Node.PROCESS_MODE_PAUSABLE
		b.respawn(_spawn_point_for(b))
		b.died.connect(_on_actor_died.bind(b))
		bots.append(b)
		Game.actors.append(b)

## TDM team for the i'th bot: the first half are blue (teammates of the local
## player), the rest red. In FFA there are no teams.
func _bot_team(i: int) -> int:
	if not Game.is_tdm():
		return 0
	return 1 if i >= Tuning.bot_count / 2 else 0

func _bot_tint(i: int) -> Color:
	return Blockman.team_color(_bot_team(i)) if Game.is_tdm() else Blockman.team_tint(i)

## Where an actor should respawn. In TDM each actor goes to its own team's side
## of the arena (blue north / red south); in FFA any spawn works.
func _spawn_point_for(a: Actor) -> Vector3:
	if Game.is_tdm():
		return arena.random_team_spawn(a.team, _living_others(a))
	return arena.random_spawn(_living_others(a))

## Re-assign team + colour to everyone already in play. Called on a map swap
## into or out of TDM, when actors already exist with bodies built under the
## old mode. Newly created actors get their appearance set before add_child.
func _configure_teams() -> void:
	for i in bots.size():
		bots[i].set_team_and_tint(_bot_team(i), _bot_tint(i))
	if Game.is_tdm():
		player.set_team_and_tint(Game.TEAM_BLUE, Blockman.team_color(Game.TEAM_BLUE))
	else:
		player.set_team_and_tint(0, Color8(228, 232, 238))

func _on_menu_play() -> void:
	menu.close()
	_menu_open = false
	# The settings write into Tuning; pick up the new match clock (score limit
	# is read live on every kill). The match is already running, just paused.
	Game.time_left = Tuning.match_seconds
	# If the settings picked a different map than the one built at boot, rebuild
	# the arena to it before spawning anyone.
	if MapData.map_id != _built_map:
		await _apply_map()
	_spawn_bots()
	hud.visible = true
	class_select.show_for(player.class_id, 0.0)
	# _hold_at_menu pointed a free camera at the arena and hid the viewmodel
	# layer; hand both back so the player sees from their own POV.
	player.camera.current = true
	viewmodel_visible(true)
	get_tree().paused = false

func _on_menu_quit() -> void:
	get_tree().quit()

# ------------------------------------------------------------------ harness
func _use_free_cam(pos: Vector3, look: Vector3) -> void:
	free_cam.global_position = pos
	free_cam.look_at(look, Vector3.UP)
	free_cam.current = true
	# The viewmodel is a CanvasLayer composite, so it keeps drawing over
	# whichever 3D camera is current. Map shots must not have a gun in them.
	viewmodel_visible(false)

func viewmodel_visible(v: bool) -> void:
	var layer := get_node_or_null("ViewmodelLayer")
	if layer == null and is_instance_valid(player):
		layer = player.get_node_or_null("ViewmodelLayer")
	if layer:
		layer.visible = v

func _shots_map(h) -> void:
	for cam in MapData.review_cameras():
		_use_free_cam(cam["pos"], cam["look"])
		await h.capture("map_" + String(cam["name"]), 4)

## An actual bot mid-fight, chosen fresh for each shot. Under the harness the
## local player has no input (frozen HP/ammo, nothing on screen), so its POV
## is a static picture of a wall — the fight is the only thing worth shooting.
func _pick_engaged_bot() -> Bot:
	var candidates: Array = bots.filter(_is_engaged_bot)
	if candidates.is_empty():
		return null
	return candidates[Game.rng.randi() % candidates.size()]

func _is_engaged_bot(b: Bot) -> bool:
	if not is_instance_valid(b) or not b.alive or b.brain.state != BotBrain.State.ENGAGE:
		return false
	return is_instance_valid(b.brain.target) and b.brain.target.alive

## Shoulder cam: behind and above the bot's eye, pitched down its own aim
## vector, so the frame reads as "this bot, mid-fight" rather than a random
## spectator angle.
func _use_bot_shoulder_cam(a: Actor) -> void:
	var eye := a.eye_position()
	var aim := a.aim_dir()
	free_cam.global_position = eye - aim * 2.2 + Vector3(0, 0.8, 0)
	free_cam.look_at(eye + aim * 6.0, Vector3.UP)
	free_cam.current = true

## First-person, from a player that is actually fighting. A shoulder cam on a
## bot showed combat but paired it with the local player's HUD and viewmodel,
## so the frame lied: dead player, frozen ammo, gun floating over someone
## else's fight. Driving the real player through the real Motor and Weapon
## keeps every overlay honest, which is what the visual critics judge.
## Fire, then capture on the next frame. Transient feedback — muzzle flash,
## tracer in flight, ejecting casing — lives for a few frames by design, so
## captures taken at arbitrary moments always landed after it had expired and
## no screenshot ever proved any of it worked.
func _shots_fx(h) -> void:
	player.camera.current = true
	viewmodel_visible(true)
	player.set_physics_process(false)
	player.global_position = Vector3(-18, 1.0, -21)
	player.yaw = -PI * 0.5
	player.pitch = 0.0
	for key in ["assault", "sniper", "shotgun"]:
		player.loadout = [key, WeaponDefs.SECONDARY]
		player.weapon.equip(key)
		player.weapon.switch_left = 0.0
		player.viewmodel.build_for(key)
		await get_tree().create_timer(0.35).timeout
		player.weapon.cooldown = 0.0
		player.weapon.try_fire()
		await get_tree().process_frame
		await h.capture("fx_%s" % key, 1)

## The class picker, at match start and mid-respawn with the lockout running.
func _shots_class(h) -> void:
	player.camera.current = true
	viewmodel_visible(false)
	class_select.show_for("trigger", 0.0)
	await get_tree().create_timer(0.4).timeout
	await h.capture("class_start", 3)
	class_select.show_for("marksman", Tuning.respawn_delay)
	await get_tree().create_timer(0.3).timeout
	await h.capture("class_respawn", 3)
	class_select.close()

## The start menu: main buttons, then the settings sub-screen. _hold_at_menu
## freezes the freshly-built arena behind it (in real play nothing is spawned
## yet; in a shots run the bots were already created by the boot branch, and
## pausing freezes them — fine for a menu frame).
func _shots_menu(h) -> void:
	_hold_at_menu()
	await h.capture("menu_main", 5)
	menu.screen = MainMenu.Screen.SETTINGS
	await h.capture("menu_settings", 5)

## Locked aim-down-sights, one frame per weapon. The sight has to sit exactly on
## the camera axis, because that is where the bullet goes and the crosshair is
## hidden while aiming. Regression evidence for that alignment.
func _shots_ads(h) -> void:
	player.enable_autopilot()
	player.camera.current = true
	viewmodel_visible(true)
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	for i in mini(5, WeaponDefs.LOADOUT.size()):
		var key: String = WeaponDefs.LOADOUT[i]
		player.weapon.equip(key)
		player.weapon.switch_left = 0.0
		player.viewmodel.build_for(key)
		player.weapon.ads = true
		player.weapon.ads_amount = 1.0
		# let the viewmodel spring settle onto the aim position
		for f in 40:
			player.viewmodel.update_view(1.0 / 60.0, 0.0, true, 1.0, Vector2.ZERO, 0.0)
			await get_tree().process_frame
		await h.capture("ads_%s" % key, 3)

func _shots_game(h) -> void:
	player.enable_autopilot()
	player.camera.current = true
	viewmodel_visible(true)
	for i in 5:
		await get_tree().create_timer(1.4).timeout
		await h.capture("game_%d" % i, 3)
