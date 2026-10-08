# A bare monster for the path probe: the shared walking and pathing (monster.gd) with no senses,
# sent from one reachable spot to another, forever. Logs every time it stops getting anywhere.
extends "res://src/monster.gd"

var goal := Vector3.INF
var leg_t := 0.0
var best := INF
var best_t := 0.0
var events: Array = []   # [position, goal, next, what]
var arrivals := 0
var speed := 3.5


func _ready() -> void:
	_setup_body(0.35, 1.6)


func _physics_process(delta: float) -> void:
	if goal == Vector3.INF or leg_t > 40.0:
		if leg_t > 40.0:
			events.append([global_position, goal, dbg_next, "gave up after 40 s"])
		goal = level.wander_point(global_position)
		leg_t = 0.0
		best = INF
		best_t = 0.0
	leg_t += delta
	var before := unstuck_count
	var v := walk_to(goal, speed, delta)
	if unstuck_count != before:
		events.append([unstuck_spots[-1][0], goal, dbg_next, "failsafe"])
	if v == Vector3.ZERO:   # arrived (or as close as the walkable floor gets)
		arrivals += 1
		goal = Vector3.INF
		return
	var d := global_position.distance_to(goal)
	if d < best - 0.5:
		best = d
		best_t = 0.0
	else:
		best_t += delta
		if best_t > 8.0:   # 8 s without getting 0.5 m closer
			events.append([global_position, goal, dbg_next, "no progress 8 s"])
			best_t = 0.0
			best = d
