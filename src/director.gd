# The horror director (host; level.gd ticks it): it watches how frightened the crew is and paces
# the dark to suit, the way a good haunted house does: quiet stretches, a slow build of small
# wrongnesses, the real thing, then a breather.
#   stress   per player underground: recent damage, how near something hunting is, being alone
#   CALM     nothing on purpose; after a while of it, BUILD
#   BUILD    every 9-16 s a small scare aimed at one of you (the one alone, the least frightened):
#            steps or a knock behind you, a whisper, a door two rooms over slamming, the lights
#            round you dying for a moment with something screeching far off; then PRESSURE: a
#            noise where you are, and whatever hunts by ear comes to look
#   PEAK     the crew's frightened (stress high): it leaves you to it
#   RELAX    after a peak, 40-70 s of nothing, and no extra creatures sent down (`quiet`)
# Scares go to every machine as net event "director" and play where they happen.
extends Node

const Sfx = preload("res://src/sfx.gd")

var main
var level
var fac
var mood := "RELAX"
var quiet := true           # (level.gd's spawn director holds off while this is set)
var stress := {}            # player -> 0..1
var intensity := 0.0        # the crew's, smoothed
var rng := RandomNumberGenerator.new()
var _t := 60.0              # time left in RELAX, or the wait before the next scare in BUILD
var _calm := 0.0
var _step := 0
var _hp := {}               # player -> hp at the last look
var _hurt := {}             # player -> recent damage, decaying
var _tick := 0.0


func _ready() -> void:
	rng.randomize()


func tick(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	var dt := 1.0 - _tick
	_tick = 1.0
	var below: Array = main.players().filter(func(p): return not p.dead and p.global_position.y < main.UNDERGROUND_Y)
	var top := 0.0
	for p in below:
		var s := _stress_of(p, below, dt)
		stress[p] = s
		top = maxf(top, s)
	intensity = lerpf(intensity, top, 0.35)
	if below.is_empty():
		mood = "RELAX"
		quiet = true
		_t = maxf(_t, 20.0)
		return
	match mood:
		"RELAX":
			quiet = true
			_t -= dt
			if _t <= 0.0:
				mood = "CALM"
				_calm = 0.0
				quiet = false
		"CALM":
			_calm = _calm + dt if intensity < 0.3 else 0.0
			if intensity > 0.7:
				mood = "PEAK"
			elif _calm > rng.randf_range(35.0, 70.0):
				mood = "BUILD"
				_step = 0
				_t = rng.randf_range(4.0, 8.0)
		"BUILD":
			if intensity > 0.7:
				mood = "PEAK"
				return
			_t -= dt
			if _t <= 0.0:
				_scare(_target(below))
				_step += 1
				_t = rng.randf_range(9.0, 16.0)
				if _step > rng.randi_range(3, 5):
					mood = "CALM"
					_calm = 0.0
		"PEAK":
			if intensity < 0.35:
				mood = "RELAX"
				quiet = true
				_t = rng.randf_range(40.0, 70.0)


## How frightened one player is: what's been hurting them, what's hunting near them, being alone.
func _stress_of(p, below: Array, dt: float) -> float:
	var hp: float = p.hp
	var was: float = _hp.get(p, hp)
	_hp[p] = hp
	_hurt[p] = _hurt.get(p, 0.0) * pow(0.92, dt) + maxf(was - hp, 0.0)
	var threat := 0.0
	for m in get_tree().get_nodes_in_group("monsters"):
		if m.has_method("is_hunting") and m.is_hunting():
			var d: float = m.global_position.distance_to(p.global_position)
			threat = maxf(threat, clampf(1.0 - d / 16.0, 0.0, 1.0))
	var alone := true
	for q in below:
		if q != p and q.global_position.distance_to(p.global_position) < 10.0:
			alone = false
	return clampf(_hurt[p] / 40.0 + threat * 0.8 + (0.12 if alone else 0.0), 0.0, 1.0)


## Who it goes after: whoever's alone and least frightened.
func _target(below: Array):
	var best = below[0]
	var score := INF
	for p in below:
		var near := below.filter(func(q): return q != p and q.global_position.distance_to(p.global_position) < 10.0).size()
		var sc: float = stress.get(p, 0.0) + near * 0.4 + rng.randf() * 0.15
		if sc < score:
			score = sc
			best = p
	return best


## One scare, worse each step: something behind you, then closer, then the lights, then pressure.
func _scare(p) -> void:
	var back := Vector3(sin(p.rotation.y), 0, cos(p.rotation.y))   # (the way they're not looking)
	var pos: Vector3 = p.global_position + back * rng.randf_range(5.0, 9.0) + Vector3(rng.randf_range(-2, 2), 1.0, rng.randf_range(-2, 2))
	match mini(_step, 3):
		0:
			_say(["sound", ["far_steps", "pipe_knock", "far_bang", "groan"][rng.randi() % 4], pos, rng.randf_range(-6.0, -2.0)])
		1:
			var door = _door_near(p.global_position)
			if door != null and rng.randf() < 0.6:
				_say(["slam", door.net_key()])
			else:
				_say(["sound", "whisper", p.global_position + back * 2.5 + Vector3(0, 1.4, 0), -6.0])
		2:
			_say(["lights", p.global_position])
		3:
			main.noise(p.global_position + back * 3.0, 20.0)   # whatever hunts by ear comes to look
			_say(["sound", "far_screech", pos + back * 10.0, -4.0])


## A swing door in a neighbouring room, standing open, that the player isn't looking at.
func _door_near(at: Vector3):
	var best = null
	var bd := INF
	for d in fac.get_children():
		if d.has_method("set_wedged") and d.has_method("set_open") and d.get("open") == true:
			var dist: float = d.global_position.distance_to(at)
			if dist > 6.0 and dist < 16.0 and dist < bd:
				bd = dist
				best = d
	return best


func _say(args: Array) -> void:
	if main.net.active:
		main.net.event("director", args)
	net_event(args)


## Everyone: play it where it happens.
func net_event(args: Array) -> void:
	match args[0]:
		"sound":
			Sfx.play(level, args[1], args[2], args[3], rng.randf_range(0.85, 1.05))
		"slam":
			var d = main._door_by_key(args[1])
			if d != null and d.has_method("set_open"):
				d.set_open(false)
				Sfx.play(level, "door_shut", d.global_position, 2.0, 0.85)
		"lights":   # every lamp round here dies, stutters, and comes back
			var at: Vector3 = args[1]
			var lamps: Array = fac.find_children("*", "Light3D", true, false).filter(func(l): return l.global_position.distance_to(at) < 11.0 and l.visible)
			for l in lamps:
				fac.haunt(l, 0.0)
			Sfx.play(level, "power_down", at + Vector3(0, 2.5, 0), -8.0, 1.4)
			var tw := create_tween()
			tw.tween_interval(1.6)
			tw.tween_callback(func():
				for l in lamps:
					if is_instance_valid(l):
						fac.haunt(l, 0.6))
			tw.tween_interval(0.12)
			tw.tween_callback(func():
				for l in lamps:
					if is_instance_valid(l):
						fac.haunt(l, 0.05))
			tw.tween_interval(0.35)
			tw.tween_callback(func():
				for l in lamps:
					if is_instance_valid(l) and level.powered():   # (not if the power's gone meanwhile)
						fac.haunt(l, 1.0)
				Sfx.play(level, "far_screech", at + Vector3(14, 0, 0), -10.0, 0.9))
