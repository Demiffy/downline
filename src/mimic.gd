# The Mimic: looks exactly like the rusty barrels everywhere. Get within arm's reach and the lid
# flips open, a tongue lashes out and bites. Then it sprouts legs and scuttles off to hide again
# somewhere else (it's harmless while running). Bait it by stepping in and back out quickly.
# Not shown on the minimap.
extends "res://src/monster.gd"

enum { HIDE, BITE, FLEE }
const REACH := 1.7
const BITE_TIME := 0.4
const RUN := 6.0

var state := HIDE
var _t := 0.0
var _goal := Vector3.ZERO
var _body: Node3D
var _lid: Node3D
var _tongue: Node3D
var _legs: Array[Node3D] = []
var _twitch := 0.0


func _ready() -> void:
	_setup_body(0.36, 1.0)
	add_to_group("hide_on_map")
	_body = Node3D.new()
	add_child(_body)
	# The same barrel everyone walks past... with a slightly dented lid.
	var tints := [Color(0.45, 0.55, 0.7), Color(0.75, 0.35, 0.25), Color(0.5, 0.6, 0.35), Color(0.8, 0.7, 0.4)]
	var t: Color = tints[randi() % tints.size()]
	A.cyl(_body, 0.33, 0.85, Vector3(0, 0.45, 0), "rust", t)
	for y in [0.18, 0.72]:
		A.cyl(_body, 0.345, 0.04, Vector3(0, y, 0), "metal", Color(0.6, 0.6, 0.6))
	A.cyl(_body, 0.3, 0.02, Vector3(0, 0.87, 0), "flesh", Color(0.25, 0.05, 0.05))   # dark wet inside
	for i in 14:
		var a := TAU * i / 14.0
		A.box(_body, Vector3(0.05, 0.1, 0.04), Vector3(sin(a) * 0.29, 0.86, cos(a) * 0.29), "cream", Color(0.95, 0.92, 0.8), false, 0.3, Vector3(0, a, 0))
	_lid = Node3D.new()
	_body.add_child(_lid)
	_lid.position = Vector3(0, 0.89, 0.33)
	A.cyl(_lid, 0.335, 0.05, Vector3(0, 0, -0.33), "rust", t.darkened(0.1))
	_tongue = Node3D.new()
	_body.add_child(_tongue)
	_tongue.position = Vector3(0, 0.8, 0)
	for i in 6:
		A.sphere(_tongue, 0.09 - i * 0.008, Vector3(0, 0, -0.14 * i), "flesh", Color(1, 0.55, 0.6), 0.2)
	_tongue.scale = Vector3(1, 1, 0.01)
	_tongue.visible = false
	for i in 2:
		var leg := Node3D.new()
		_body.add_child(leg)
		leg.position = Vector3(-0.16 + i * 0.32, 0.12, 0)
		A.cyl(leg, 0.06, 0.6, Vector3(0, -0.3, 0), "flesh", Color(0.9, 0.55, 0.55), false, "y", 0.04)
		A.sphere(leg, 0.08, Vector3(0, -0.6, -0.04), "flesh", Color(0.8, 0.45, 0.45))
		leg.scale = Vector3(1, 0.01, 1)
		_legs.append(leg)
	_twitch = randf_range(8.0, 20.0)


func _physics_process(delta: float) -> void:
	_t += delta
	match state:
		HIDE:
			stand_still(delta)
			_twitch -= delta
			if _twitch <= 0.0:
				_twitch = randf_range(10.0, 25.0)
				var tw := create_tween()
				tw.tween_property(_lid, "rotation:x", 0.12, 0.08)
				tw.tween_property(_lid, "rotation:x", 0.0, 0.12)
			var p = nearest_player(REACH)
			if p != null:
				_bite_start()
		BITE:
			stand_still(delta)
			var p = nearest_player(REACH + 0.6)
			if p != null:
				face(p.global_position, delta, 20.0)
			if _t >= BITE_TIME and _tongue.visible:
				if p != null:
					p.hurt(85.0, "Eaten by a barrel. It was a mimic.")
					Sfx.play(self, "snap", global_position + Vector3.UP, 4.0, 0.7)
				_tongue.visible = false
			if _t >= BITE_TIME + 0.5:
				_flee_start()
		FLEE:
			var v := walk_to(_goal, RUN, delta, 12.0)
			_body.position.y = 0.55 + absf(sin(_anim * 3.0)) * 0.08
			_body.rotation.z = sin(_anim * 3.0) * 0.12
			for i in 2:
				_legs[i].rotation.x = sin(_anim * 3.0 + PI * i) * 0.8
			_lid.rotation.x = 0.4 + absf(sin(_anim * 6.0)) * 0.5
			if v == Vector3.ZERO or _t > 12.0:
				_hide()


func _bite_start() -> void:
	state = BITE
	_t = 0.0
	Sfx.play(self, "hiss", global_position + Vector3.UP, 2.0)
	_tongue.visible = true
	var tw := create_tween().set_parallel()
	tw.tween_property(_lid, "rotation:x", 1.9, 0.12).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_tongue, "scale:z", 1.6, BITE_TIME * 0.8).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)


func _flee_start() -> void:
	state = FLEE
	_t = 0.0
	_goal = level.facility.random_point(level.rng, true) if level and level.facility else global_position + Vector3(8, 0, 8)
	_tongue.scale.z = 0.01
	for leg in _legs:
		create_tween().tween_property(leg, "scale:y", 1.0, 0.25)


func _hide() -> void:
	state = HIDE
	_t = 0.0
	stand_still(0.016)
	_body.position.y = 0.0
	_body.rotation.z = 0.0
	_lid.rotation.x = 0.0
	for leg in _legs:
		leg.scale.y = 0.01
		leg.rotation.x = 0.0
