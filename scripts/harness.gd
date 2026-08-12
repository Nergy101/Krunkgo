extends Node
## Automated verification harness. Without it nobody can judge anything.
##
##   godot --path . -- bench=8                 -> fps stats as JSON, then quit
##   godot --path . -- shots=out/dir           -> scripted screenshots, then quit
##   godot --path . -- shots=out/dir shotset=map
##   godot --path . -- botfight                -> no local input, camera on a bot
##   godot --path . -- seed=7 bots=7
##
## Screenshot sets are declared by whichever slice owns the thing being shot,
## via Harness.register_shot_set(name, callable) during _ready.

var args: Dictionary = {}
var bench_seconds: float = 0.0
var shot_dir: String = ""
var shot_set: String = "default"
var botfight: bool = false
var active: bool = false

var _frame_times: PackedFloat32Array = PackedFloat32Array()
var _elapsed: float = 0.0
var _shot_sets: Dictionary = {}
var _warmup: float = 1.0

func _ready() -> void:
	process_priority = 1000
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0].lstrip("-")] = kv[1]
		else:
			args[a.lstrip("-")] = "1"
	bench_seconds = float(args.get("bench", "0"))
	shot_dir = String(args.get("shots", ""))
	shot_set = String(args.get("shotset", "default"))
	botfight = args.has("botfight")
	active = bench_seconds > 0.0 or shot_dir != ""
	if args.has("seed"):
		Game.rng.seed = int(args["seed"])
		# Seed the GLOBAL rng too. 24 call sites across player.gd, fx.gd,
		# audio.gd and palette.gd use the bare randf() family, which Godot
		# auto-seeds from the clock, so `seed=7` controlled the AI and nothing
		# else — even the baked textures differed between runs of the same
		# seed. Any probe that reports one run as authoritative was reporting
		# a lottery ticket.
		seed(int(args["seed"]))
	else:
		Game.rng.randomize()
	if args.has("bots"):
		Tuning.bot_count = int(args["bots"])
	# vsync must be disabled AFTER the window exists; doing it in _ready pinned
	# every bench to exactly 60.0 fps and hid all the headroom.
	if bench_seconds > 0.0:
		Engine.max_fps = 0
		call_deferred("_unlock_framerate")

func _unlock_framerate() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

func want(flag: String) -> bool:
	return args.has(flag)

func register_shot_set(set_name: String, fn: Callable) -> void:
	_shot_sets[set_name] = fn

func _process(delta: float) -> void:
	if not active:
		return
	_elapsed += delta
	if _elapsed < _warmup:
		return
	if bench_seconds > 0.0:
		_frame_times.append(delta)
		if _elapsed >= _warmup + bench_seconds:
			_finish_bench()
	elif shot_dir != "":
		set_process(false)
		_run_shots()

func _finish_bench() -> void:
	active = false
	var arr: Array = Array(_frame_times)
	arr.sort()
	var n := arr.size()
	if n == 0:
		print("BENCH {}")
		get_tree().quit(0)
		return
	var total := 0.0
	for t in arr:
		total += t
	var mean := total / n
	var out := {
		"frames": n,
		"avg_fps": 1.0 / maxf(mean, 0.000001),
		"p50_ms": arr[int(n * 0.50)] * 1000.0,
		"p95_ms": arr[mini(n - 1, int(n * 0.95))] * 1000.0,
		"p99_ms": arr[mini(n - 1, int(n * 0.99))] * 1000.0,
		"worst_ms": arr[n - 1] * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	}
	print("BENCH ", JSON.stringify(out))
	get_tree().quit(0)

func _run_shots() -> void:
	await _capture_all()
	get_tree().quit(0)

func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	var fn: Callable = _shot_sets.get(shot_set, Callable())
	if not fn.is_valid():
		push_warning("Harness: no shot set '%s', capturing viewport once" % shot_set)
		await capture("frame")
		return
	await fn.call(self)

## Saves the current viewport. Await this; it settles the frame first.
func capture(shot_name: String, settle_frames: int = 3) -> void:
	for i in settle_frames:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [shot_dir, shot_name]
	img.save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))
