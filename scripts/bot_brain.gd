class_name BotBrain
extends RefCounted
## Decision layer for a bot. Deliberately imperfect: reaction delay, aim error
## that shrinks the longer it tracks you, burst discipline, and it loses you
## when line of sight breaks. A bot that snaps to your head is not a better
## bot, it is a worse game.

enum State { ROAM, ENGAGE, HUNT }

var bot: Actor
var state: int = State.ROAM
var target: Actor = null
var last_seen_pos := Vector3.ZERO
var reaction_left: float = 0.0
var tracking_time: float = 0.0
var lost_timer: float = 0.0
var strafe_dir: float = 1.0
var strafe_timer: float = 0.0
var retreating: bool = false
var in_cover: bool = false
var cover_point := Vector3.ZERO
var cover_hold: float = 0.0
var cover_cd: float = 0.0     # stops cover becoming a permanent hiding place
var cover_travel: float = 0.0 # how long we have been walking to cover_point
var jump_timer: float = 0.0
var burst_left: int = 0
var burst_pause: float = 0.0
var skill: float = 1.0            # 0.6 (fodder) .. 1.3 (sweaty)

func think(delta: float, candidates: Array) -> void:
	strafe_timer -= delta
	jump_timer -= delta
	cover_hold = maxf(0.0, cover_hold - delta)
	cover_cd = maxf(0.0, cover_cd - delta)
	burst_pause = maxf(0.0, burst_pause - delta)

	var seen := _pick_target(candidates)
	if seen:
		if target != seen:
			target = seen
			reaction_left = lerpf(Tuning.bot_reaction_max, Tuning.bot_reaction_min,
				clampf(skill - 0.6, 0.0, 1.0)) * Game.rng.randf_range(0.8, 1.25)
			tracking_time = 0.0
		state = State.ENGAGE
		last_seen_pos = seen.global_position
		lost_timer = 0.0
		tracking_time += delta
		reaction_left = maxf(0.0, reaction_left - delta)
	elif state == State.ENGAGE:
		state = State.HUNT
		lost_timer = 2.2
	elif state == State.HUNT:
		lost_timer -= delta
		if lost_timer <= 0.0:
			state = State.ROAM
			target = null

	if strafe_timer <= 0.0:
		strafe_timer = Tuning.bot_strafe_period * Game.rng.randf_range(0.6, 1.5)
		if Game.rng.randf() < 0.75:
			strafe_dir = -strafe_dir

func _pick_target(candidates: Array) -> Actor:
	var best: Actor = null
	var best_d := 1e9
	var eye: Vector3 = bot.eye_position()
	var fwd: Vector3 = bot.aim_dir()
	for c in candidates:
		var a := c as Actor
		if a == null or a == bot or not a.alive or a.protected():
			continue
		# Team Deathmatch: never engage a teammate.
		if Game.is_tdm() and a.team == bot.team:
			continue
		var to: Vector3 = a.eye_position() - eye
		var d := to.length()
		if d > Tuning.bot_sight_range:
			continue
		# already-engaged targets stay tracked through a wider arc
		var cone: float = 200.0 if target == a else Tuning.bot_fov_deg
		if rad_to_deg(fwd.angle_to(to.normalized())) > cone * 0.5:
			continue
		if not bot.has_los(a):
			continue
		if d < best_d:
			best_d = d
			best = a
	return best

func wants_to_shoot() -> bool:
	if state != State.ENGAGE or target == null or reaction_left > 0.0 or burst_pause > 0.0:
		return false
	var to: Vector3 = target.eye_position() - bot.eye_position()
	var err := rad_to_deg(bot.aim_dir().angle_to(to.normalized()))
	# Generous up close, strict at range: mirrors how a human trades accuracy
	# for volume in a brawl. Widened from 3.0/6.0 — with a tight gate the bots
	# held fire until they were perfectly lined up, so they fired half as often
	# but a HIGHER share of those shots landed. Humans pull the trigger when
	# roughly on target and miss a lot; that is what makes them survivable.
	var allow: float = 4.0 + 7.0 / maxf(1.0, to.length() * 0.15)
	return err < allow

func note_shot(def: Dictionary) -> void:
	if not bool(def["auto"]):
		burst_pause = Game.rng.randf_range(0.25, 0.55) / skill
		return
	burst_left -= 1
	if burst_left <= 0:
		# Shorter bursts with longer gaps. Continuous fire from seven bots is
		# what made the lobby feel like a firing squad.
		burst_left = int(Game.rng.randi_range(3, 7) * skill)
		burst_pause = Game.rng.randf_range(0.32, 0.75) / skill

## Aim error in degrees, shrinking the longer this bot has tracked its target.
func aim_error() -> float:
	# Converges slower (0.9 instead of 1.6) and never below 45% of the base
	# error. At a 0.15 floor a bot that had tracked you for half a second was
	# accurate to under half a degree, which reads as an aimbot rather than an
	# opponent.
	var settle: float = clampf(1.0 - tracking_time * 0.9, 0.45, 1.0)
	return Tuning.bot_aim_error_deg * settle / skill
