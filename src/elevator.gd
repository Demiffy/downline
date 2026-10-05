# Mine-shaft elevator: steel headframe tower with turning sheave wheels and a cable, a shaft down to
# the facility, sliding doors on both landings and on the cab, call buttons, and a ride that carries
# players + loot. Placed by level.gd; local y=0 is ground level.
extends Node3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")

const RIDE_SECS := 9.0
const HALF := 1.8          # cab half-width
const SHAFT := 2.15        # shaft wall offset (inner face at 2.0)
const DW := 2.0            # door opening width
const DH := 2.6            # door opening height
const SHEAVE_Y := 16.0
const SHEAVE_R := 1.2
const INSIDE := AABB(Vector3(-1.75, -0.4, -1.7), Vector3(3.5, 3.3, 3.45))

var level
var bottom := -60.0
var cab: Node3D
var at_top := true
var moving := false
var _cab_doors: Array[Node3D] = []
var _landing_doors := {}   # true (top) / false (bottom) -> [left, right]
var _doors_open := false
var _travel := false
var _t := 0.0
var _from := 0.0
var _to := 0.0
var _riders: Array = []
var _cargo: Array = []
var _motor: AudioStreamPlayer3D
var _music: AudioStreamPlayer3D
var _sheaves: Array[Node3D] = []
var _cable: Node3D
var _floor_label: Label3D


func build(level_ref, bottom_y: float, facility_h: float) -> void:
	level = level_ref
	bottom = bottom_y
	process_physics_priority = -10  # move the cab before players run their physics
	_shaft(facility_h)
	_headframe()
	cab = Node3D.new()
	add_child(cab)
	_cab()
	for top in [true, false]:
		_landing(top)
	_motor = _loop("motor", -4.0)
	_music = _loop("muzak", -10.0)
	_update_cable()
	_set_doors(true)


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
	var under := -bottom
	var tint := Color(0.75, 0.72, 0.68)
	# Below ground: concrete, with the bottom landing's opening in the front wall.
	A.box(self, Vector3(0.3, under, 2 * SHAFT + 0.3), Vector3(-SHAFT, bottom / 2, 0), "concrete", tint)
	A.box(self, Vector3(0.3, under, 2 * SHAFT + 0.3), Vector3(SHAFT, bottom / 2, 0), "concrete", tint)
	A.box(self, Vector3(2 * SHAFT + 0.3, under, 0.3), Vector3(0, bottom / 2, SHAFT), "concrete", tint)
	A.wall(self, -SHAFT - 0.15, SHAFT + 0.15, -SHAFT, under, 0.3, [[0.0, DW, 0.0, DH]], "concrete", tint, true, bottom)
	# Above ground: an open steel cage up to the headframe deck.
	var top := 6.0
	for s in [-1, 1]:
		A.box(self, Vector3(0.05, top, 2 * SHAFT), Vector3(s * SHAFT, top / 2, 0), "grate", Color.WHITE, true, 0.7)
	A.box(self, Vector3(2 * SHAFT, top, 0.05), Vector3(0, top / 2, SHAFT), "grate", Color.WHITE, true, 0.7)
	A.wall(self, -SHAFT, SHAFT, -SHAFT, top, 0.05, [[0.0, DW, 0.0, DH]], "grate", Color.WHITE, true, 0.0, true, 0.7)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			A.box(self, Vector3(0.2, top, 0.2), Vector3(sx * SHAFT, top / 2, sz * SHAFT), "rust", Color.WHITE, true, 1.0)
	for y in [2.0, 4.0, 6.0]:
		for s in [-1, 1]:
			A.box(self, Vector3(2 * SHAFT + 0.2, 0.12, 0.12), Vector3(0, y, s * SHAFT), "rust", Color.WHITE, false, 1.0)
			A.box(self, Vector3(0.12, 0.12, 2 * SHAFT + 0.2), Vector3(s * SHAFT, y, 0), "rust", Color.WHITE, false, 1.0)
	# Guide rails + lamps down the shaft so the ride visibly moves.
	for x in [-SHAFT + 0.2, SHAFT - 0.2]:
		A.box(self, Vector3(0.1, under + top, 0.15), Vector3(x, (bottom + top) / 2, 0), "metal", Color(0.6, 0.6, 0.6), false)
	var y := bottom + facility_h + 3.0
	var i := 0
	while y < -1.0:
		A.glow(self, Vector3(0.3, 0.12, 0.05), Vector3(0, y, SHAFT - 0.17), Color(1, 0.7, 0.4), 4.0)
		if i % 2 == 0:
			B.omni(self, Vector3(0, y, SHAFT - 0.6), Color(1, 0.7, 0.45), 0.8, 6.0)
		y += 6.0
		i += 1


## A steel beam between two points (any direction).
func _beam(a: Vector3, b: Vector3, thick := 0.3, solid := false) -> void:
	var mid := (a + b) / 2.0
	var beam := A.box(self, Vector3(thick, thick, a.distance_to(b)), mid, "rust", Color.WHITE, solid, 1.0)
	var up := Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.FORWARD
	beam.look_at_from_position(to_global(mid), to_global(b), up)


func _headframe() -> void:
	var base := 4.8
	var tip := 1.7
	var h := SHEAVE_Y - 1.0
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_beam(Vector3(sx * base, 0, sz * base), Vector3(sx * tip, h, sz * tip), 0.45, true)
			A.box(self, Vector3(1.2, 0.6, 1.2), Vector3(sx * base, 0.3, sz * base), "concrete", Color(0.8, 0.75, 0.7), true)
	for frac in [0.33, 0.66]:
		var w: float = lerpf(base, tip, frac)
		var y: float = h * frac
		for s in [-1, 1]:
			_beam(Vector3(-w, y, s * w), Vector3(w, y, s * w), 0.22)
			_beam(Vector3(s * w, y, -w), Vector3(s * w, y, w), 0.22)
	var w1 := lerpf(base, tip, 0.33)
	for s in [-1, 1]:
		_beam(Vector3(-base, 0.5, s * base), Vector3(w1, h * 0.33, s * w1), 0.15)
		_beam(Vector3(base, 0.5, s * base), Vector3(-w1, h * 0.33, s * w1), 0.15)
	# Deck + railing + sheave wheels.
	A.box(self, Vector3(2 * tip + 1.0, 0.15, 2 * tip + 1.0), Vector3(0, h, 0), "grate", Color.WHITE, false, 0.6)
	for s in [-1, 1]:
		A.railing(self, Vector3(-tip - 0.5, h, s * (tip + 0.5)), Vector3(tip + 0.5, h, s * (tip + 0.5)), 1.0, "rust")
	for z in [-0.25, 0.25]:
		var pivot := Node3D.new()
		add_child(pivot)
		pivot.position = Vector3(0, SHEAVE_Y, z)
		A.cyl(pivot, SHEAVE_R, 0.12, Vector3.ZERO, "rust", Color.WHITE, false, "z")
		A.cyl(pivot, SHEAVE_R * 0.25, 0.25, Vector3.ZERO, "metal", Color(0.4, 0.4, 0.4), false, "z")
		for k in 4:
			var spoke := A.box(pivot, Vector3(SHEAVE_R * 1.9, 0.12, 0.1), Vector3.ZERO, "metal", Color(0.6, 0.6, 0.6), false)
			spoke.rotation.z = k * PI / 4
		_sheaves.append(pivot)
	for s in [-1, 1]:
		A.box(self, Vector3(0.25, SHEAVE_Y - h + 0.3, 0.25), Vector3(s * 0.9, (SHEAVE_Y + h) / 2, 0), "rust", Color.WHITE, false, 1.0)
	A.box(self, Vector3(2.0, 0.2, 0.25), Vector3(0, SHEAVE_Y + 0.2, 0), "rust", Color.WHITE, false, 1.0)
	A.glow(self, Vector3(0.25, 0.25, 0.25), Vector3(0, SHEAVE_Y + 1.5, 0), Color(1, 0.15, 0.1), 6.0)
	# The cable from the sheave down to the cab roof (resized as the cab moves).
	_cable = B.box(self, Vector3(0.05, 1.0, 0.05), Vector3.ZERO, Color(0.15, 0.13, 0.12), false)
	# Winch house with the haul cable running up to the sheave.
	var wx := 9.0
	A.box(self, Vector3(4, 3, 3.5), Vector3(wx, 1.5, 0), "corrugated", Color(0.7, 0.5, 0.4), true, 1.5)
	A.box(self, Vector3(4.3, 0.15, 3.8), Vector3(wx, 3.05, 0), "rust", Color.WHITE, false, 1.5)
	var drum := Node3D.new()
	add_child(drum)
	drum.position = Vector3(wx - 2.1, 1.5, 0)
	A.cyl(drum, 0.6, 1.4, Vector3.ZERO, "rust", Color.WHITE, false, "z")
	for k in 3:
		var bar := A.box(drum, Vector3(1.3, 0.1, 1.45), Vector3.ZERO, "metal", Color(0.4, 0.4, 0.4), false)
		bar.rotation.z = k * PI / 3
	_sheaves.append(drum)
	_beam(Vector3(wx - 2.1, 2.1, 0), Vector3(SHEAVE_R, SHEAVE_Y, 0), 0.05)


func _cab() -> void:
	var g := Color(0.85, 0.8, 0.75)
	A.box(cab, Vector3(3.6, 0.1, 3.6), Vector3(0, 0.01, 0), "grate", g, true, 0.6)
	A.box(cab, Vector3(3.5, 0.03, 3.5), Vector3(0, -0.06, 0), "metal", Color(0.3, 0.3, 0.3), false)
	A.box(cab, Vector3(0.05, 3.0, 3.6), Vector3(-HALF + 0.03, 1.5, 0), "grate", g, true, 0.6)
	A.box(cab, Vector3(0.05, 3.0, 3.6), Vector3(HALF - 0.03, 1.5, 0), "grate", g, true, 0.6)
	A.box(cab, Vector3(3.6, 3.0, 0.05), Vector3(0, 1.5, HALF - 0.03), "grate", g, true, 0.6)
	A.wall(cab, -HALF, HALF, -HALF + 0.03, 3.0, 0.05, [[0.0, DW, 0.0, DH]], "grate", g, true, 0.0, true, 0.6)
	A.box(cab, Vector3(3.6, 0.12, 3.6), Vector3(0, 3.06, 0), "metal", Color(0.45, 0.42, 0.4), true)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			A.box(cab, Vector3(0.1, 3.1, 0.1), Vector3(sx * HALF, 1.55, sz * HALF), "rust", Color.WHITE, false, 1.0)
	for y in [0.06, 1.1, 3.0]:
		A.box(cab, Vector3(3.6, 0.08, 0.08), Vector3(0, y, HALF), "rust", Color.WHITE, false, 1.0)
	# Stash shelves, handrail, lamp, button panel with a floor display.
	for y in [0.95, 1.75]:
		A.box(cab, Vector3(0.5, 0.05, 3.2), Vector3(-HALF + 0.3, y, 0), "metal", Color(0.7, 0.7, 0.7), true)
	A.box(cab, Vector3(3.2, 0.05, 0.05), Vector3(0, 1.0, HALF - 0.15), "metal", Color(0.75, 0.72, 0.65), false)
	A.sphere(cab, 0.1, Vector3(0, 2.92, 0), "cream", Color(1, 0.85, 0.6), 5.0)
	B.omni(cab, Vector3(0, 2.6, 0), Color(1, 0.8, 0.55), 1.0, 5.0)
	A.box(cab, Vector3(0.05, 0.7, 0.35), Vector3(HALF - 0.08, 1.35, -1.25), "metal", Color(0.3, 0.3, 0.3), false)
	B.interactable(cab, Vector3(0.08, 0.14, 0.14), Vector3(HALF - 0.12, 1.3, -1.25), Color(1, 0.75, 0.1), "Ride elevator", ride, 0.0, 2.0)
	_floor_label = B.label(cab, "SURFACE", Vector3(HALF - 0.13, 1.58, -1.25), 32, Color(1, 0.5, 0.2), false)
	_floor_label.rotation.y = -PI / 2
	_floor_label.pixel_size = 0.002
	# Sliding cage doors.
	for s in [-1, 1]:
		var door := A.box(cab, Vector3(DW / 2, DH, 0.04), Vector3(s * DW / 4, DH / 2, -HALF + 0.09), "grate", g, true, 0.6)
		A.box(door, Vector3(DW / 2, 0.08, 0.06), Vector3(0, DH / 2 - 0.05, 0), "rust", Color.WHITE, false, 1.0)
		A.box(door, Vector3(0.06, DH, 0.06), Vector3(-s * DW / 4, 0, 0), "rust", Color.WHITE, false, 1.0)
		_cab_doors.append(door)


func _landing(top: bool) -> void:
	var y := 0.0 if top else bottom
	for s in [-1, 1]:
		A.box(self, Vector3(0.25, DH + 0.3, 0.25), Vector3(s * (DW / 2 + 0.12), y + (DH + 0.3) / 2, -SHAFT - 0.2), "hazard", Color.WHITE, false, 0.6)
	A.box(self, Vector3(DW + 0.5, 0.45, 0.3), Vector3(0, y + DH + 0.2, -SHAFT - 0.2), "metal", Color(0.45, 0.42, 0.4), false)
	var lift_sign := B.label(self, "LIFT", Vector3(0, y + DH + 0.2, -SHAFT - 0.37), 64, Color(1, 0.75, 0.3), false)
	lift_sign.rotation.y = PI
	A.box(self, Vector3(0.25, 0.4, 0.08), Vector3(DW / 2 + 0.6, y + 1.3, -SHAFT - 0.2), "metal", Color(0.3, 0.3, 0.3), false)
	B.interactable(self, Vector3(0.12, 0.12, 0.06), Vector3(DW / 2 + 0.6, y + 1.35, -SHAFT - 0.26), Color(1, 0.4, 0.1),
		"Call elevator", call_to.bind(top), 0.0, 2.0)
	# Solid sliding shaft doors (they keep you out of an empty shaft).
	var pair := []
	for s in [-1, 1]:
		var door := A.box(self, Vector3(DW / 2, DH, 0.05), Vector3(s * DW / 4, y + DH / 2, -SHAFT + 0.18), "riveted", Color(0.75, 0.7, 0.62), true, 1.0)
		A.box(door, Vector3(0.3, 0.4, 0.06), Vector3(-s * 0.2, 0.5, 0), "metal", Color(0.05, 0.05, 0.05), false)
		A.box(door, Vector3(DW / 2, 0.1, 0.07), Vector3(0, -DH / 2 + 0.3, 0), "hazard", Color.WHITE, false, 0.5)
		pair.append(door)
	_landing_doors[top] = pair


# --- behaviour ------------------------------------------------------------------------

func call_to(top: bool) -> void:
	if moving:
		return
	if at_top == top:
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
	_floor_label.text = "GOING DOWN" if at_top else "GOING UP"
	_motor.play()
	_music.play()


func _physics_process(delta: float) -> void:
	if not _travel:
		return
	_t = minf(1.0, _t + delta / RIDE_SECS)
	var y := lerpf(_from, _to, smoothstep(0.0, 1.0, _t))
	var dy := y - cab.position.y
	cab.position.y = y
	for s in _sheaves:
		s.rotation.z += dy / SHEAVE_R
	_update_cable()
	for r in _riders:
		if is_instance_valid(r):
			r.global_position.y += dy
			if r.has_method("shake"):
				r.shake(0.004)
	if _t >= 1.0:
		_arrive()


func _update_cable() -> void:
	var top_y := SHEAVE_Y - SHEAVE_R * 0.2
	var low := cab.position.y + 3.12
	_cable.scale.y = maxf(0.01, top_y - low)
	_cable.position = Vector3(-SHEAVE_R + 0.05, (top_y + low) / 2.0, 0)


func _arrive() -> void:
	_travel = false
	_motor.stop()
	_music.stop()
	at_top = not at_top
	_floor_label.text = "SURFACE" if at_top else "SITE B-1"
	Sfx.play(self, "ding", cab.global_position + Vector3(0, 2.5, 0))
	for c in _cargo:
		if is_instance_valid(c):
			c.reparent(level)
			c.freeze = false
	_cargo.clear()
	_riders.clear()
	await _set_doors(true)
	moving = false


## Slides the cab doors and the doors of the landing the cab is at.
func _set_doors(open: bool) -> void:
	if _doors_open == open:
		return
	_doors_open = open
	if cab.is_inside_tree():
		Sfx.play(self, "door", cab.global_position + Vector3(0, 1.5, -HALF), -2.0, 1.6)
	var tw := create_tween().set_parallel()
	var doors: Array = _cab_doors + _landing_doors[at_top]
	for i in doors.size():
		var s := -1.0 if i % 2 == 0 else 1.0
		tw.tween_property(doors[i], "position:x", s * (DW * 0.73 if open else DW / 4), 1.1).set_trans(Tween.TRANS_SINE)
	await tw.finished
