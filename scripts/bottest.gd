extends Node
## Bot health probe. The mid-air hang was found by eye in a screenshot, which is
## a terrible way to find it and a worse way to confirm it is gone.
##
##   godot --path . -- bottest
##
## Samples every bot every physics tick and prints one JSON line prefixed
## BOTTEST with the things that actually indicate a broken agent: time spent
## airborne, time spent stuck (airborne with no vertical motion), time spent
## not moving at all, and whether anyone left the arena bounds.

const RUN_SECONDS := 14.0
const STUCK_VY := 0.35        # |velocity.y| below this while airborne = hung
const IDLE_SPEED := 0.4

var elapsed: float = 0.0
var samples: int = 0
var stats: Dictionary = {}
## Accuracy is the thing players actually feel, and nothing measured it.
var shots_fired: int = 0
var shots_landed: int = 0
var wound_mode: bool = false
var wound_timer: float = 0.0

func _ready() -> void:
	name = "BotTest"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("wound="):
			wound_mode = arg.split("=")[1] == "1"
	await get_tree().process_frame
	for a in Game.actors:
		var bot := a as Bot
		if bot == null or bot.weapon == null:
			continue
		bot.weapon.fired.connect(func(_d, _m, _dir): shots_fired += 1)
		bot.weapon.landed.connect(func(_z, _dmg, _p, _n, _v, _k): shots_landed += 1)

## Free play almost never drives a bot below bot_retreat_health, so the cover
## and retreat branches went unexercised and the probe reported 0.0 for six of
## seven bots. `bottest wound=1` injects damage on a fixed schedule instead, so
## the mechanic is measured rather than left to RNG.
func _wound(delta: float) -> void:
	wound_timer -= delta
	if wound_timer > 0.0:
		return
	wound_timer = 1.5
	for a in Game.actors:
		var bot := a as Bot
		if bot != null and bot.alive and bot.health > Tuning.max_health * 0.25:
			bot.health -= Tuning.max_health * 0.30

func _physics_process(delta: float) -> void:
	elapsed += delta
	if wound_mode:
		_wound(delta)
	samples += 1
	for a in Game.actors:
		var bot := a as Bot
		if bot == null:
			continue
		var s: Dictionary = stats.get(bot.display_name, {
			"air": 0, "hung": 0, "idle": 0, "oob": 0, "retreat": 0, "cover": 0, "max_y": -1e9,
			"min_y": 1e9, "shots": 0, "engage": 0, "slide": 0, "jump": 0,
		})
		var airborne: bool = not bot.motor.grounded
		if airborne:
			s["air"] += 1
			if absf(bot.velocity.y) < STUCK_VY:
				s["hung"] += 1
		if bot.motor.speed_flat < IDLE_SPEED:
			s["idle"] += 1
		if bot.motor.sliding:
			s["slide"] += 1
		if bot.motor.jumped_this_tick:
			s["jump"] += 1
		if bot.brain.state == BotBrain.State.ENGAGE:
			s["engage"] += 1
		# The retreat and cover branches were added on a critic's note and then
		# went unmeasured, so nothing proved they ever fired in a real match.
		if bot.brain.retreating:
			s["retreat"] += 1
		if bot.brain.in_cover:
			s["cover"] += 1
		var p := bot.global_position
		if absf(p.x) > 34.0 or absf(p.z) > 34.0 or p.y < -6.0 or p.y > 30.0:
			s["oob"] += 1
		s["max_y"] = maxf(s["max_y"], p.y)
		s["min_y"] = minf(s["min_y"], p.y)
		stats[bot.display_name] = s

	if elapsed >= RUN_SECONDS:
		_finish()

func _finish() -> void:
	set_physics_process(false)
	var out: Dictionary = {"samples": samples, "bots": stats.size(), "per_bot": {}}
	var worst_hung := 0.0
	var total_engage := 0.0
	var total_slide := 0
	var total_jump := 0
	var total_oob := 0
	for k in stats.keys():
		var s: Dictionary = stats[k]
		var hung_pct: float = 100.0 * float(s["hung"]) / float(samples)
		worst_hung = maxf(worst_hung, hung_pct)
		total_engage += 100.0 * float(s["engage"]) / float(samples)
		total_slide += int(s["slide"])
		total_jump += int(s["jump"])
		total_oob += int(s["oob"])
		out["per_bot"][k] = {
			"air_pct": snappedf(100.0 * float(s["air"]) / float(samples), 0.1),
			"hung_pct": snappedf(hung_pct, 0.1),
			"idle_pct": snappedf(100.0 * float(s["idle"]) / float(samples), 0.1),
			"engage_pct": snappedf(100.0 * float(s["engage"]) / float(samples), 0.1),
			"jumps": s["jump"], "slide_ticks": s["slide"], "oob_ticks": s["oob"],
			"retreat_pct": snappedf(100.0 * float(s["retreat"]) / float(samples), 0.1),
			"cover_pct": snappedf(100.0 * float(s["cover"]) / float(samples), 0.1),
			"y_range": [snappedf(s["min_y"], 0.01), snappedf(s["max_y"], 0.01)],
		}
	out["worst_hung_pct"] = snappedf(worst_hung, 0.1)
	out["avg_engage_pct"] = snappedf(total_engage / maxf(1.0, float(stats.size())), 0.1)
	out["total_jumps"] = total_jump
	out["total_slide_ticks"] = total_slide
	out["total_oob_ticks"] = total_oob
	out["bot_shots_fired"] = shots_fired
	out["bot_shots_landed"] = shots_landed
	out["bot_hit_rate"] = snappedf(float(shots_landed) / maxf(1.0, float(shots_fired)), 0.001)
	out["bot_jumps_per_sec"] = snappedf(float(total_jump) / RUN_SECONDS, 0.01)
	# What a player actually feels is incoming hits per second, not the ratio.
	out["bot_hits_per_sec"] = snappedf(float(shots_landed) / RUN_SECONDS, 0.01)
	print("BOTTEST ", JSON.stringify(out))
	get_tree().quit(0)
