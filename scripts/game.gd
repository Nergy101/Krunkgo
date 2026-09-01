extends Node
## Match state + the single event bus every slice talks through.
## HUD, audio and feedback code MUST listen here rather than reaching into
## the player, so the pieces stay independently judgeable.

signal kill_registered(attacker: String, victim: String, weapon: String, headshot: bool)
signal hit_confirmed(headshot: bool, damage: float, world_pos: Vector3, killed: bool)
signal score_changed()
signal match_ended()
## New: a fresh match is live — initial boot, post-intermission auto-restart,
## or a manual F5 restart. main.gd listens here to respawn every actor
## without reloading the scene.
signal match_started()
signal local_spawned(player: Node3D)
signal local_damaged(from_dir: Vector3, damage: float)
signal local_died(killer: String)
signal weapon_changed(def: Dictionary)
signal ammo_changed(mag: int, reserve: int)
signal health_changed(hp: float, max_hp: float)
signal announce(text: String, kind: String)

const TEAM_PLAYER := 0
const TEAM_BOT := 1
const TEAM_BLUE := 0   # Team Deathmatch: friendlies are always blue
const TEAM_RED := 1    # opponents always red

## Game mode is derived from the map: the symmetric standoff arena is a Team
## Deathmatch, Burg is Free For All. Kept as a function (not state) so a mode
## can never drift from the map it is played on.
func is_tdm() -> bool:
	return MapData.mode() == "tdm"

func mode_name() -> String:
	return "TEAM DEATHMATCH" if is_tdm() else "FREE FOR ALL"

func mode_short() -> String:
	return "TDM" if is_tdm() else "FFA"

# Seconds between two kills by the same attacker that still counts as one
# chained "multi-kill" (Krunker: Double/Triple/Multi/Mega Kill).
const MULTI_KILL_WINDOW := 4.0
const STREAK_CALLOUTS := {
	3: "KILLING SPREE", 5: "RAMPAGE", 7: "DOMINATING", 10: "UNSTOPPABLE", 15: "GODLIKE",
}
const MULTI_KILL_NAMES := {2: "DOUBLE KILL", 3: "TRIPLE KILL", 4: "MULTI KILL", 5: "MEGA KILL"}

var scores: Dictionary = {}          # name -> {"kills","deaths","streak","multi_kills","last_kill_time"}
var time_left: float = 0.0
var running: bool = false
var intermission_left: float = 0.0   # counts down after match_ended, then auto-restarts
var _reveal_hold: float = 0.0        # delays running=false so the win callout clears first
var local_player: Node3D = null
var arena: Node3D = null
var fx: Node3D = null                # Fx pool for tracers/impacts, set by main
var actors: Array = []               # every Actor in the match, alive or dead
var rng := RandomNumberGenerator.new()

## (Re)starts a match in place: clears the board, resets the clock, and tells
## main.gd to respawn everyone. Safe to call whether a match is running,
## ended, or this is the very first boot.
func reset_match() -> void:
	scores.clear()
	time_left = Tuning.match_seconds
	running = true
	intermission_left = 0.0
	_reveal_hold = 0.0
	score_changed.emit()
	match_started.emit()

func register_actor(actor_name: String, team: int = 0) -> void:
	if not scores.has(actor_name):
		scores[actor_name] = {"kills": 0, "deaths": 0, "streak": 0,
			"multi_kills": 0, "last_kill_time": -999.0, "team": team}
		score_changed.emit()
	elif int(scores[actor_name].get("team", 0)) != team:
		# Team is authored on spawn; a bot whose team changed (map swap into or
		# out of TDM) must be re-scored under the new team or totals go wrong.
		scores[actor_name]["team"] = team
		score_changed.emit()

func team_of(actor_name: String) -> int:
	return int(scores.get(actor_name, {}).get("team", 0))

func team_total(team: int) -> int:
	var n := 0
	for k in scores:
		if int(scores[k].get("team", 0)) == team:
			n += int(scores[k].get("kills", 0))
	return n

func report_kill(attacker: String, victim: String, weapon: String, headshot: bool) -> void:
	register_actor(attacker)
	register_actor(victim)
	var suicide: bool = attacker == victim
	if not suicide:
		var a: Dictionary = scores[attacker]
		a["kills"] += 1
		a["streak"] += 1
		var now := float(Time.get_ticks_msec()) / 1000.0
		a["multi_kills"] = (a["multi_kills"] + 1) if now - a["last_kill_time"] <= MULTI_KILL_WINDOW else 1
		a["last_kill_time"] = now
		_announce_kill(attacker, victim, headshot, int(a["streak"]), int(a["multi_kills"]))
	else:
		scores[victim]["kills"] -= 1
	scores[victim]["deaths"] += 1
	scores[victim]["streak"] = 0
	kill_registered.emit(attacker, victim, weapon, headshot)
	score_changed.emit()
	if running:
		# In TDM a team wins when its total kills reach the limit; in FFA the
		# individual does.
		if is_tdm():
			if team_total(int(scores[attacker]["team"])) >= Tuning.score_limit:
				end_match()
		elif scores[attacker]["kills"] >= Tuning.score_limit:
			end_match()

## Center-screen callout for the LOCAL player's own kills only — bot-on-bot
## fights already read through the killfeed, a banner for every one of them
## would be noise. Multi-kill chains beat streak milestones beat a plain
## headshot/kill confirmation.
func _announce_kill(attacker: String, victim: String, headshot: bool, streak: int, multi: int) -> void:
	# Also skip during the post-win reveal hold: running is still true there
	# on purpose (see end_match), but a stray kill mid-hold must not stomp
	# the MATCH OVER banner with an ordinary kill callout.
	if attacker != "YOU" or _reveal_hold > 0.0:
		return
	if MULTI_KILL_NAMES.has(multi):
		announce.emit(String(MULTI_KILL_NAMES[multi]), "kill")
	elif STREAK_CALLOUTS.has(streak):
		announce.emit(String(STREAK_CALLOUTS[streak]), "kill")
	elif headshot:
		announce.emit("HEADSHOT KILL — %s" % victim, "kill")
	else:
		announce.emit("YOU KILLED %s" % victim, "kill")

func end_match() -> void:
	if not running or _reveal_hold > 0.0:
		return
	_announce_result()
	match_ended.emit()
	# HUD force-opens the scoreboard the instant `running` goes false and its
	# geometry sits right under the centre announce, so hold the flip until
	# the "MATCH OVER" callout (hud.gd announce_life 2.4s) has fully faded —
	# otherwise the two collide for the first couple of seconds.
	_reveal_hold = 2.6
	intermission_left = Tuning.intermission_seconds

## Who actually won, announced the moment the scoreboard takes over the screen.
func _announce_result() -> void:
	if is_tdm():
		_announce_tdm_result()
		return
	var board := leaderboard()
	if board.is_empty():
		return
	var top: Dictionary = board[0]
	# The `kills > 0` guard meant a genuine 0-0 match skipped the tie branch
	# entirely and crowned whoever happened to sort first as the winner.
	var tied: bool = board.size() > 1 and board[1]["kills"] == top["kills"]
	if tied:
		announce.emit("MATCH OVER — DRAW", "match")
	elif String(top["name"]) == "YOU":
		announce.emit("MATCH OVER — YOU WIN", "match")
	else:
		announce.emit("MATCH OVER — %s WINS" % String(top["name"]), "match")

## TDM crowns the team, not a player. The local player is always blue.
func _announce_tdm_result() -> void:
	var blue := team_total(TEAM_BLUE)
	var red := team_total(TEAM_RED)
	if blue == red:
		announce.emit("MATCH OVER — DRAW", "match")
	elif blue > red:
		announce.emit("MATCH OVER — BLUE TEAM WINS", "match")
	else:
		announce.emit("MATCH OVER — RED TEAM WINS", "match")

func leaderboard() -> Array:
	var rows: Array = []
	for k in scores.keys():
		rows.append({"name": k, "kills": scores[k]["kills"], "deaths": scores[k]["deaths"],
			"team": int(scores[k].get("team", 0))})
	rows.sort_custom(func(a, b):
		if a["kills"] == b["kills"]:
			return a["deaths"] < b["deaths"]
		return a["kills"] > b["kills"])
	return rows

func _process(delta: float) -> void:
	if running:
		if _reveal_hold > 0.0:
			_reveal_hold = maxf(0.0, _reveal_hold - delta)
			if _reveal_hold <= 0.0:
				running = false
			return
		time_left = maxf(0.0, time_left - delta)
		if time_left <= 0.0:
			end_match()
	elif intermission_left > 0.0:
		intermission_left = maxf(0.0, intermission_left - delta)
		if intermission_left <= 0.0:
			reset_match()

