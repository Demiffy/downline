# One of the two levers that open a twin-key blast door (facility.gd places a pair on opposite walls
# of the room in front of it). Pull one and it holds down for a couple of seconds on its spring,
# its lamp amber; if the other's pulled while it's down, the door opens and both lamps go green.
# Alone, jam one down with a door wedge (player.gd's wedge works on these as on swing doors).
extends Node3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")

const HOLD := 2.5        # seconds a pulled lever stays down
const UP := 0.6          # the handle's angle, up
const DOWN := -0.9

var fac
var code := ""
var other                # the lever's partner
var wedged := false
var held := 0.0
var _pivot: Node3D
var _lamp: StandardMaterial3D
var _wedge: Node3D


func build() -> void:
	var steel := Color(0.36, 0.4, 0.38)
	A.box(self, Vector3(0.5, 0.7, 0.14), Vector3(0, 0, 0.07), "riveted", steel, false, 0.5)
	A.box(self, Vector3(0.56, 0.06, 0.18), Vector3(0, 0.38, 0.09), "metal", steel.darkened(0.3), false)
	A.box(self, Vector3(0.44, 0.08, 0.01), Vector3(0, 0.24, 0.145), "hazard", Color.WHITE, false, 0.3)
	B.label(self, "PULL WITH THE OTHER", Vector3(0, -0.28, 0.146), 16, Color(0.92, 0.88, 0.75), "stencil", 0.0035)
	for k in 7:   # the quadrant's teeth
		var a := UP - (UP - DOWN) * k / 6.0
		A.box(self, Vector3(0.03, 0.025, 0.03), Vector3(0.18, 0, 0.16) + Vector3(0, cos(a), sin(a)) * 0.22, "metal", Color(0.6, 0.6, 0.56), false, 0.3, Vector3(a, 0, 0))
	_lamp = StandardMaterial3D.new()
	_lamp.albedo_color = Color(0.5, 0.05, 0.05)
	_lamp.emission_enabled = true
	_lamp.emission = Color(1, 0.12, 0.08)
	_lamp.emission_energy_multiplier = 2.5
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.06
	lamp.mesh = sm
	lamp.material_override = _lamp
	add_child(lamp)
	lamp.position = Vector3(-0.15, 0.27, 0.16)
	A.cyl(self, 0.055, 0.03, Vector3(-0.15, 0.27, 0.145), "metal", Color(0.7, 0.7, 0.68), false, "z")
	_pivot = Node3D.new()
	add_child(_pivot)
	_pivot.position = Vector3(0.18, 0, 0.18)
	_pivot.rotation.x = UP
	A.cyl(_pivot, 0.05, 0.08, Vector3.ZERO, "metal", Color(0.3, 0.3, 0.3), false, "x")
	A.box(_pivot, Vector3(0.04, 0.5, 0.04), Vector3(0, 0.25, 0), "metal", Color(0.65, 0.65, 0.62), false, 0.4)
	A.sphere(_pivot, 0.06, Vector3(0, 0.52, 0), "plastic", Color(0.85, 0.08, 0.06))
	var it := B.interactable(_pivot, Vector3(0.16, 0.6, 0.16), Vector3(0, 0.3, 0), Color(0, 0, 0, 0), "Pull the lever (both at once)", pull, 0.0)
	it.set_meta("twin", true)
	_wedge = Node3D.new()   # the wedge, when one's jammed in under the handle
	add_child(_wedge)
	_wedge.visible = false
	A.box(_wedge, Vector3(0.09, 0.05, 0.14), Vector3(0.18, -0.24, 0.22), "rubber", Color(0.75, 0.3, 0.1), false, 0.3, Vector3(0.4, 0, 0))


## (net.gd runs this on every machine; the host opens the door.)
func pull() -> void:
	if _open():
		return
	held = HOLD
	_move(DOWN, 0.15)
	Sfx.play(self, "ratchet", global_position, -2.0, 0.9)
	Sfx.play(self, "clunk", global_position, -2.0, 0.8)
	_lamp.emission = Color(1, 0.6, 0.1)
	if fac.main and fac.main.net.authority() and other != null and other.down():
		fac.set_door(code, true, true)


func down() -> bool:
	return wedged or held > 0.0


## A wedge jammed under the handle: it stays down for good (player.gd's wedge; main.wedge_door).
func set_wedged(on: bool, _quiet := false) -> void:
	wedged = on
	_wedge.visible = on
	if on:
		_move(DOWN, 0.2)
		_lamp.emission = Color(1, 0.6, 0.1)
		Sfx.play(self, "thunk", global_position, -4.0, 1.2)
		if fac.main and fac.main.net.authority() and other != null and other.down():
			fac.set_door(code, true, true)


func _open() -> bool:
	return fac.doors.has(code) and fac.doors[code].get_meta("open")


func _move(a: float, t: float) -> void:
	var tw := _pivot.create_tween()
	tw.tween_property(_pivot, "rotation:x", a, t).set_trans(Tween.TRANS_QUAD)


func _process(delta: float) -> void:
	if _open():
		if _lamp.emission != Color(0.2, 1, 0.3):
			_lamp.emission = Color(0.2, 1, 0.3)
			_move(DOWN, 0.2)
		return
	if held > 0.0:
		held -= delta
		if held <= 0.0 and not wedged:   # the spring takes it back up
			_move(UP, 0.4)
			Sfx.play(self, "clack", global_position, -6.0, 0.8)
			_lamp.emission = Color(1, 0.12, 0.08)


## The net key the wedge travels by (the lever's own interactable).
func net_key() -> String:
	for it in _pivot.get_children():
		if it.has_meta("twin"):
			return it.net_key()
	return ""
