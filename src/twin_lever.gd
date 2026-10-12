# One of the two levers that open a twin-key blast door (facility.gd places a pair on opposite walls
# of the room in front of it). Pull one and it holds down for a couple of seconds on its spring,
# its lamp amber; if the other's pulled while it's down, the door opens and both lamps go green.
# Alone, jam one down with a door wedge (player.gd's wedge works on these as on swing doors).
extends Node3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")

const HOLD := 2.5        # seconds a pulled lever stays down
const UP := 0.12         # the handle's angle: up, leaning a touch off the wall...
const DOWN := 2.3        # ...pulled down and out toward whoever's pulling it (never into the wall)
const R := 0.3           # the quadrant's radius
const PZ := 0.12         # the pivot, out from the wall

var fac
var code := ""
var other                # the lever's partner
var wedged := false
var held := 0.0
var _pivot: Node3D
var _lamp: StandardMaterial3D
var _wedge: Node3D


## Local +z is out of the wall, the pivot at the origin. A riveted backplate bolted to the wall, a
## pair of quadrant cheek plates standing out from it with notches round their rims, the handle
## between them on a heavy boss (a flat bar, a T grip in red rubber, the latch rod and its trigger),
## a caged lamp on top, hazard stripes where the handle comes down, the stencilled plate under it.
func build() -> void:
	var steel := Color(0.34, 0.39, 0.37)
	var dark := steel.darkened(0.45)
	A.box(self, Vector3(0.5, 1.02, 0.03), Vector3(0, -0.06, 0.015), "riveted", steel, false, 0.5)   # the backplate
	A.box(self, Vector3(0.54, 1.06, 0.012), Vector3(0, -0.06, 0.004), "metal", dark, false, 0.5)
	for x in [-0.2, 0.2]:
		for y in [0.38, -0.5]:
			A.cyl(self, 0.022, 0.03, Vector3(x, y, 0.035), "metal", Color(0.62, 0.6, 0.55), false, "z")   # bolt heads
	A.box(self, Vector3(0.4, 0.09, 0.006), Vector3(0, -0.36, 0.033), "hazard", Color.WHITE, false, 0.3)   # where it comes down
	for sx in [-0.055, 0.055]:   # the quadrant: two cheek plates over the handle's swing, a notched rail round each
		var a0 := UP - 0.15
		var a1 := DOWN + 0.15
		for k in 8:   # the plate, in slices from the pivot out
			var a := lerpf(a0, a1, (k + 0.5) / 8.0)
			A.box(self, Vector3(0.014, R * (a1 - a0) / 8.0 + 0.012, R), Vector3(sx, cos(a) * R / 2.0, PZ + sin(a) * R / 2.0), "metal", steel.darkened(0.15), false, 0.3, Vector3(a - PI / 2.0, 0, 0))
		for k in 12:   # the rail
			var a := lerpf(a0, a1, (k + 0.5) / 12.0)
			A.box(self, Vector3(0.03, R * (a1 - a0) / 12.0 + 0.01, 0.025), Vector3(sx, cos(a) * R, PZ + sin(a) * R), "metal", dark, false, 0.3, Vector3(a + PI / 2.0, 0, 0))
		for k in 6:   # its notches, where the latch drops in
			var a := lerpf(UP, DOWN, k / 5.0)
			A.box(self, Vector3(0.032, 0.014, 0.02), Vector3(sx, cos(a) * (R - 0.022), PZ + sin(a) * (R - 0.022)), "metal", Color(0.08, 0.08, 0.08), false, 0.3, Vector3(a, 0, 0))
	A.box(self, Vector3(0.13, 0.12, PZ + 0.04), Vector3(0, -0.02, (PZ + 0.04) / 2.0), "metal", dark, false, 0.3)   # the hub block between them
	A.cyl(self, 0.06, 0.17, Vector3(0, 0, PZ), "metal", Color(0.22, 0.22, 0.22), false, "x")   # the boss
	for sx in [-0.09, 0.09]:
		A.cyl(self, 0.03, 0.012, Vector3(sx, 0, PZ), "metal", Color(0.65, 0.62, 0.55), false, "x")   # the pin's ends
	# The lamp, caged, on top.
	var lp := Vector3(-0.15, 0.36, 0.06)   # (off to the side: the handle doesn't hide it)
	A.box(self, Vector3(0.12, 0.05, 0.08), lp + Vector3(0, -0.06, 0), "metal", dark, false, 0.3)
	_lamp = StandardMaterial3D.new()
	_lamp.albedo_color = Color(0.5, 0.05, 0.05)
	_lamp.emission_enabled = true
	_lamp.emission = Color(1, 0.12, 0.08)
	_lamp.emission_energy_multiplier = 2.5
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.08
	lamp.mesh = sm
	lamp.material_override = _lamp
	add_child(lamp)
	lamp.position = lp
	for k in 3:   # the cage's bars
		var a := PI * k / 3.0
		A.box(self, Vector3(0.008, 0.008, 0.1), lp, "metal", Color(0.2, 0.2, 0.2), false, 0.3, Vector3(0, a, 0))
	A.ring(self, 0.055, 0.048, lp, "metal", Color(0.2, 0.2, 0.2))
	B.label(self, "PULL WITH THE OTHER", Vector3(0, -0.47, 0.035), 15, Color(0.92, 0.88, 0.75), "stencil", 0.0033)
	# The handle.
	_pivot = Node3D.new()
	add_child(_pivot)
	_pivot.position.z = PZ
	_pivot.rotation.x = UP
	A.box(_pivot, Vector3(0.04, 0.5, 0.05), Vector3(0, 0.25, 0), "metal", Color(0.6, 0.6, 0.57), false, 0.4)   # the bar
	A.cyl(_pivot, 0.012, 0.36, Vector3(0, 0.25, 0.04), "metal", Color(0.5, 0.5, 0.48))   # the latch rod
	A.box(_pivot, Vector3(0.05, 0.07, 0.03), Vector3(0, 0.44, 0.045), "metal", Color(0.45, 0.45, 0.43), false, 0.3)   # its trigger, under the grip
	A.cyl(_pivot, 0.035, 0.24, Vector3(0, 0.52, 0), "rubber", Color(0.78, 0.1, 0.07), false, "x")   # the T grip
	for sx in [-0.125, 0.125]:
		A.cyl(_pivot, 0.04, 0.02, Vector3(sx, 0.52, 0), "metal", Color(0.2, 0.2, 0.2), false, "x")
	var it := B.interactable(_pivot, Vector3(0.3, 0.62, 0.2), Vector3(0, 0.3, 0), Color(0, 0, 0, 0), "Pull the lever (both at once)", pull, 0.0)
	it.set_meta("twin", true)
	_wedge = Node3D.new()   # the wedge, when one's jammed in behind the handle
	add_child(_wedge)
	_wedge.visible = false
	A.box(_wedge, Vector3(0.14, 0.05, 0.12), Vector3(0, cos(DOWN - 0.35) * 0.2, PZ + sin(DOWN - 0.35) * 0.2), "rubber", Color(0.75, 0.3, 0.1), false, 0.3, Vector3(DOWN - 0.35, 0, 0))


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
