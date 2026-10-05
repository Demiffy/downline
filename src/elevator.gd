# A real elevator: a shaft from the surface (y=0) down to the facility, a grate cage cab with
# sliding doors, call buttons at both landings, and a ride that carries players + loot.
# Placed by level.gd at the elevator building; local y=0 is ground level.
extends Node3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")

const RIDE_SECS := 9.0
const HALF := 1.8          # cab half-width
const SHAFT := 2.15        # shaft wall offset
const GATE_DOWN := 1.5
const GATE_UP := 4.4
const INSIDE := AABB(Vector3(-1.75, -0.4, -1.75), Vector3(3.5, 3.3, 3.5))

var level
var bottom := -60.0
var cab: Node3D
var at_top := true
var moving := false
var _doors: Array[Node3D] = []
var _doors_open := true
var _travel := false
var _t := 0.0
var _from := 0.0
var _to := 0.0
var _riders: Array = []
var _cargo: Array = []
var _motor: AudioStreamPlayer3D
var _music: AudioStreamPlayer3D


func build(level_ref, bottom_y: float, facility_h: float) -> void:
	level = level_ref
	bottom = bottom_y
	process_physics_priority = -10  # move the cab before players run their physics
	_shaft(facility_h)
	cab = Node3D.new()
	add_child(cab)
	_cab()
	for y in [0.0, bottom]:
		_landing(y)
	_motor = _loop("motor", -4.0)
	_music = _loop("muzak", -10.0)


func _loop(sound: String, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = Sfx.stream(sound)
	p.volume_db = db
	p.unit_size = 4.0
	cab.add_child(p)
	p.position.y = 2.5
	return p


func inside(pos: Vector3) -> bool:
	return INSIDE.has_point(cab.to_local(pos))


# --- geometry ------------------------------------------------------------------------

func _shaft(facility_h: float) -> void:
	var lo := bottom
	var hi := 6.0
	var h := hi - lo
	var mid := (lo + hi) / 2.0
	var tint := Color(0.75, 0.72, 0.68)
	A.box(self, Vector3(0.3, h, 2 * SHAFT + 0.3), Vector3(-SHAFT, mid, 0), "concrete", tint)
	A.box(self, Vector3(0.3, h, 2 * SHAFT + 0.3), Vector3(SHAFT, mid, 0), "concrete", tint)
	A.box(self, Vector3(2 * SHAFT + 0.3, h, 0.3), Vector3(0, mid, SHAFT), "concrete", tint)
	# Front wall has an opening at each landing.
	var front_lo := bottom + 3.3
	A.box(self, Vector3(2 * SHAFT + 0.3, -0.2 - front_lo, 0.3), Vector3(0, (front_lo - 0.2) / 2.0, -SHAFT), "concrete", tint)
	A.box(self, Vector3(2 * SHAFT + 0.3, hi - 3.3, 0.3), Vector3(0, (hi + 3.3) / 2.0, -SHAFT), "concrete", tint)
	A.box(self, Vector3(2 * SHAFT + 0.3, 0.3, 2 * SHAFT + 0.3), Vector3(0, hi, 0), "concrete", tint)
	# Guide rails and shaft lamps so you can see the ride happening.
	for x in [-SHAFT + 0.2, SHAFT - 0.2]:
		A.box(self, Vector3(0.1, h, 0.15), Vector3(x, mid, 0), "metal", Color(0.6, 0.6, 0.6), false)
	var y := bottom + facility_h + 3.0
	var i := 0
	while y < -1.0:
		A.glow(self, Vector3(0.3, 0.12, 0.05), Vector3(0, y, SHAFT - 0.17), Color(1, 0.7, 0.4), 4.0)
		if i % 2 == 0:
			B.omni(self, Vector3(0, y, SHAFT - 0.6), Color(1, 0.7, 0.45), 0.8, 6.0)
		y += 6.0
		i += 1


func _cab() -> void:
	var g := Color(0.85, 0.8, 0.75)
	A.box(cab, Vector3(3.6, 0.1, 3.6), Vector3(0, 0.01, 0), "grate", g, true, 0.6)
	A.box(cab, Vector3(3.5, 0.03, 3.5), Vector3(0, -0.06, 0), "metal", Color(0.3, 0.3, 0.3), false)
	A.box(cab, Vector3(0.05, 3.0, 3.6), Vector3(-HALF + 0.03, 1.5, 0), "grate", g, true, 0.6)
	A.box(cab, Vector3(0.05, 3.0, 3.6), Vector3(HALF - 0.03, 1.5, 0), "grate", g, true, 0.6)
	A.box(cab, Vector3(3.6, 3.0, 0.05), Vector3(0, 1.5, HALF - 0.03), "grate", g, true, 0.6)
	A.box(cab, Vector3(3.6, 0.12, 3.6), Vector3(0, 3.06, 0), "metal", Color(0.45, 0.42, 0.4), true)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			A.box(cab, Vector3(0.1, 3.1, 0.1), Vector3(sx * HALF, 1.55, sz * HALF), "rust", Color.WHITE, false, 1.0)
	for y in [0.06, 1.1, 3.0]:
		A.box(cab, Vector3(3.6, 0.08, 0.08), Vector3(0, y, HALF), "rust", Color.WHITE, false, 1.0)
	# Stash shelves.
	for y in [0.95, 1.75]:
		A.box(cab, Vector3(0.5, 0.05, 3.2), Vector3(-HALF + 0.3, y, 0), "metal", Color(0.7, 0.7, 0.7), true)
	# Lamp + button panel.
	A.sphere(cab, 0.1, Vector3(0, 2.92, 0), "cream", Color(1, 0.85, 0.6), 5.0)
	B.omni(cab, Vector3(0, 2.6, 0), Color(1, 0.8, 0.55), 1.0, 5.0)
	A.box(cab, Vector3(0.05, 0.6, 0.3), Vector3(HALF - 0.08, 1.35, -1.2), "metal", Color(0.3, 0.3, 0.3), false)
	B.interactable(cab, Vector3(0.08, 0.14, 0.14), Vector3(HALF - 0.12, 1.45, -1.2), Color(1, 0.75, 0.1), "Ride elevator", ride, 0.0, 2.0)
	# Freight-style grate gate on the -z side; it lifts up into the frame.
	var gate := A.box(cab, Vector3(3.5, 2.9, 0.05), Vector3(0, GATE_DOWN, -HALF + 0.05), "grate", g, true, 0.6)
	for y in [-1.4, 0.0, 1.4]:
		A.box(gate, Vector3(3.5, 0.08, 0.08), Vector3(0, y, 0), "rust", Color.WHITE, false, 1.0)
	_doors.append(gate)
	_doors_open = false
	gate.position.y = GATE_UP


func _landing(y: float) -> void:
	var c := Color(0.55, 0.5, 0.45)
	for s in [-1, 1]:
		A.box(self, Vector3(0.25, 3.3, 0.25), Vector3(s * (SHAFT - 0.05), y + 1.65, -SHAFT - 0.15), "hazard", Color.WHITE, false, 0.6)
	A.box(self, Vector3(2 * SHAFT + 0.2, 0.4, 0.3), Vector3(0, y + 3.3, -SHAFT - 0.15), "metal", c, false)
	var lift_sign := B.label(self, "LIFT", Vector3(0, y + 3.3, -SHAFT - 0.32), 64, Color(1, 0.75, 0.3), false)
	lift_sign.rotation.y = PI
	A.box(self, Vector3(0.25, 0.4, 0.08), Vector3(SHAFT + 0.45, y + 1.3, -SHAFT - 0.2), "metal", Color(0.3, 0.3, 0.3), false)
	B.interactable(self, Vector3(0.12, 0.12, 0.06), Vector3(SHAFT + 0.45, y + 1.35, -SHAFT - 0.26), Color(1, 0.4, 0.1),
		"Call elevator", call_to.bind(y == 0.0), 0.0, 2.0)


# --- behaviour ------------------------------------------------------------------------

func call_to(top: bool) -> void:
	if moving:
		return
	if at_top == top:
		if not _doors_open:
			_set_doors(true)
		return
	ride()


func ride() -> void:
	if moving:
		return
	moving = true
	await _set_doors(false)
	_riders.clear()
	_cargo.clear()
	for n in get_tree().get_nodes_in_group("movable"):
		if inside(n.global_position):
			if n is RigidBody3D:
				n.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				n.freeze = true
				n.reparent(cab)
				_cargo.append(n)
			else:
				_riders.append(n)
	_from = cab.position.y
	_to = bottom if at_top else 0.0
	_t = 0.0
	_travel = true
	_motor.play()
	_music.play()


func _physics_process(delta: float) -> void:
	if not _travel:
		return
	_t = minf(1.0, _t + delta / RIDE_SECS)
	var y := lerpf(_from, _to, smoothstep(0.0, 1.0, _t))
	var dy := y - cab.position.y
	cab.position.y = y
	for r in _riders:
		if is_instance_valid(r):
			r.global_position.y += dy
			if r.has_method("shake"):
				r.shake(0.004)
	if _t >= 1.0:
		_arrive()


func _arrive() -> void:
	_travel = false
	_motor.stop()
	_music.stop()
	at_top = not at_top
	Sfx.play(self, "ding", cab.global_position + Vector3(0, 2.5, 0))
	for c in _cargo:
		if is_instance_valid(c):
			c.reparent(level)
			c.freeze = false
	_cargo.clear()
	_riders.clear()
	await _set_doors(true)
	moving = false


func _set_doors(open: bool) -> void:
	if _doors_open == open:
		return
	_doors_open = open
	Sfx.play(self, "door", cab.global_position + Vector3(0, 1.5, -HALF), -2.0, 1.4)
	var tw := create_tween()
	tw.tween_property(_doors[0], "position:y", GATE_UP if open else GATE_DOWN, 1.0).set_trans(Tween.TRANS_SINE)
	await tw.finished
