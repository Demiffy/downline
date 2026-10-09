# A Husk: a dead employee's body that lay too long in the dark, and got up again. It looks exactly
# like one of the crew (it is one: their suit, their name over the helmet), walks like one, makes
# the same footsteps. No glow, no mist, no sound of its own. It wanders. When it sees you it comes
# to arm's length and stands there, looking at you, for a few long seconds; then it goes for you.
# It backs off and stares again. Kill it and it falls, just a body again.
extends "res://src/monster.gd"

const Suit = preload("res://src/suit.gd")

enum { WANDER, APPROACH, STARE, ATTACK }
const SIGHT := 18.0
const STARE_AT := 2.4
const DAMAGE := 40.0

var state := WANDER
var prey
var _t := 0.0
var _stare := 5.0
var _goal := Vector3.ZERO
var _wander := 0.0
var _parts := {}
var who := ""
var _tag: Label3D
var _step := 0.0


func _ready() -> void:
	_setup_body(0.32, 1.8)
	health = 90.0
	hit_kind = "cloth"
	var body := Node3D.new()
	add_child(body)
	body.name = "Body"
	_parts = Suit.standing(body)   # (just as they were)
	_tag = Label3D.new()   # their name, as over any crewmate's helmet
	_tag.font_size = 22
	_tag.pixel_size = 0.0011
	_tag.fixed_size = true
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.modulate = Color(1.0, 0.85, 0.55, 0.9)
	_tag.outline_size = 8
	_tag.visible = false
	add_child(_tag)
	_tag.position.y = 2.05
	_goal = global_position


## Whose body it was (the host says): their name goes over the helmet.
func set_who(n: String) -> void:
	who = n
	_tag.text = n


func net_event(ev: String, args: Array) -> void:
	if ev == "who":
		set_who(args[0])
	else:
		super.net_event(ev, args)


func _physics_process(delta: float) -> void:
	_t += delta
	match state:
		WANDER:
			_wander -= delta
			if _wander <= 0.0 or global_position.distance_to(_goal) < 1.0:
				_wander = randf_range(5.0, 10.0)
				_goal = level.wander_point(global_position) if level else global_position
			walk_to(_goal, 1.1, delta, 3.0)
			var p = nearest_player(SIGHT, true)
			if p != null:
				prey = p
				state = APPROACH
		APPROACH:
			if not _valid():
				return
			var d: float = global_position.distance_to(prey.global_position)
			var v := walk_to(prey.global_position, 1.6, delta, 5.0) if d > STARE_AT else Vector3.ZERO
			if d <= STARE_AT or (v == Vector3.ZERO and d < STARE_AT + 1.6):   # (or as close as the way gets)
				state = STARE
				_t = 0.0
				_stare = randf_range(4.0, 6.0)
		STARE:   # standing there, close, looking at you
			if not _valid():
				return
			stand_still(delta)
			face(prey.global_position, delta, 6.0)
			if global_position.distance_to(prey.global_position) > STARE_AT + 3.0:
				state = APPROACH
			elif _t > _stare:
				state = ATTACK
				_t = 0.0
				show_act("attack")   # (nothing to hear: it just comes at you)
		ATTACK:
			if not _valid():
				return
			var v := walk_to(prey.global_position, 5.0, delta, 14.0)
			var dd: float = global_position.distance_to(prey.global_position)
			if dd < 1.2 or (v == Vector3.ZERO and dd < 2.2):
				prey.hurt(DAMAGE, "Your old crewmate didn't recognise you.")
				Sfx.play(self, "thud", global_position + Vector3.UP * 1.2, 0.0, 1.1)
				state = APPROACH   # back off to arm's length, and stare again
				_t = 0.0
			elif _t > 2.0:
				state = APPROACH
	_animate(delta)


func _valid() -> bool:
	if prey == null or not is_instance_valid(prey) or prey.dead or not sees(prey):
		_t = 0.0 if state != WANDER else _t
		if prey == null or not is_instance_valid(prey) or prey.dead or global_position.distance_to(prey.global_position) > SIGHT:
			state = WANDER
			prey = null
			return false
	return true


func is_hunting() -> bool:
	return state != WANDER


func act(_what: String, _args: Array) -> void:
	pass


## It walks like any of the crew: legs and arms swinging, the same footsteps on the same floors.
## Staring, it just stands there, square on, head level. Going for you, its arms come up.
func _animate(delta: float) -> void:
	var g := _anim * 2.6
	var speed := velocity.length()
	var amt := clampf(speed / 4.0, 0.0, 1.0)
	var s := sin(g)
	_parts.thigh_l.rotation.x = s * 0.6 * amt
	_parts.thigh_r.rotation.x = -s * 0.6 * amt
	_parts.shin_l.rotation.x = -maxf(0.0, -s) * 0.9 * amt
	_parts.shin_r.rotation.x = -maxf(0.0, s) * 0.9 * amt
	var reach := 1.2 if state == ATTACK else 0.06
	_parts.upper_arm_l.rotation.x = lerpf(_parts.upper_arm_l.rotation.x, reach - s * 0.45 * amt, minf(1.0, delta * 8.0))
	_parts.upper_arm_r.rotation.x = lerpf(_parts.upper_arm_r.rotation.x, reach + s * 0.45 * amt, minf(1.0, delta * 8.0))
	_parts.torso.rotation.x = -0.08 * amt
	_parts.head.rotation = Vector3.ZERO
	(get_node("Body") as Node3D).position.y = absf(cos(g)) * 0.03 * amt
	if speed > 0.4 and level != null and main.net.authority():   # footsteps, as a crewmate's (the crew hear the host's)
		_step += speed * delta
		if _step > 0.75:
			_step = 0.0
			Sfx.play(self, "step_" + main.surface_at(global_position), global_position, -9.0, randf_range(0.88, 1.12))
	var cam := get_viewport().get_camera_3d()
	_tag.visible = who != "" and cam != null and cam.global_position.distance_to(global_position) < 14.0 and not dead


func net_visual(delta: float) -> void:
	_t += delta
	super.net_visual(delta)


## It drops: a body again.
func death_anim() -> void:
	if main and main.net.authority() and level != null:
		var r = main.spawn_item("REMAINS", global_position + Vector3(0, 0.3, 0), -1.0, level)
		if r:
			r.set_meta("no_possess", true)
	queue_free()
