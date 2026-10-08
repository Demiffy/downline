# Mine-shaft elevator: steel headframe tower with turning sheave wheels and a cable, a shaft down to
# the facility, sliding doors on both landings and on the cab, call buttons, and a ride that carries
# players + loot. Placed by level.gd; local y=0 is ground level.
extends Node3D

const A = preload("res://src/art.gd")
const Data = preload("res://src/data.gd")
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
var _bodies: Array = []   # ragdolls lying in the cab: their parts are held still and carried along
var _motor: AudioStreamPlayer3D
var _music: AudioStreamPlayer3D
var _sheaves: Array[Node3D] = []
var _cable: Node3D
var _floor_label: Label3D
var _arrows := {}   # true (top) / false (bottom) -> [up lamp, down lamp]


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
	if level_ref.facility:
		_clad(level_ref.facility.theme, facility_h)
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
		A.box(self, Vector3(0.05, top, 2 * SHAFT), Vector3(s * SHAFT, top / 2, 0), "grate", Color.WHITE, true, 1.8)
	A.box(self, Vector3(2 * SHAFT, top, 0.05), Vector3(0, top / 2, SHAFT), "grate", Color.WHITE, true, 1.8)
	A.wall(self, -SHAFT, SHAFT, -SHAFT, top, 0.05, [[0.0, DW, 0.0, DH]], "grate", Color.WHITE, true, 0.0, true, 1.8)
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
		_bulkhead_lamp(self, Vector3(0, y, SHAFT - 0.15), Vector3(0, 0, -1), Color(1, 0.7, 0.4))
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
	var base := 4.8               # leg feet
	var tip := SHAFT + 0.15       # leg tops meet the inner tower here
	var h := SHEAVE_Y - 1.8       # head frame / deck height
	# Inner tower: columns rising from the lift cage to the head, tied every 3 m.
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			A.box(self, Vector3(0.25, h, 0.25), Vector3(sx * SHAFT, h / 2, sz * SHAFT), "rust", Color.WHITE, true, 1.0)
	var y := 9.0
	while y < h - 0.5:
		for s in [-1, 1]:
			_beam(Vector3(-SHAFT, y, s * SHAFT), Vector3(SHAFT, y, s * SHAFT), 0.16)
			_beam(Vector3(s * SHAFT, y, -SHAFT), Vector3(s * SHAFT, y, SHAFT), 0.16)
		y += 3.0
	for s in [-1, 1]:
		_beam(Vector3(-SHAFT, 6.0, s * SHAFT), Vector3(SHAFT, h, s * SHAFT), 0.1)
		_beam(Vector3(s * SHAFT, 6.0, -SHAFT), Vector3(s * SHAFT, h, SHAFT), 0.1)
	# Four raking legs from concrete footings up to the head frame corners.
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_beam(Vector3(sx * base, 0.6, sz * base), Vector3(sx * tip, h, sz * tip), 0.45, true)
			A.box(self, Vector3(1.2, 0.6, 1.2), Vector3(sx * base, 0.3, sz * base), "concrete", Color(0.8, 0.75, 0.7), true)
	# Leg cross-ties, each tying back into the inner tower.
	for frac in [0.3, 0.6]:
		var w: float = lerpf(base, tip, frac)
		var fy: float = 0.6 + (h - 0.6) * frac
		for s in [-1, 1]:
			_beam(Vector3(-w, fy, s * w), Vector3(w, fy, s * w), 0.22)
			_beam(Vector3(s * w, fy, -w), Vector3(s * w, fy, w), 0.22)
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				_beam(Vector3(sx * w, fy, sz * w), Vector3(sx * SHAFT, fy, sz * SHAFT), 0.12)
	# Back stays leaning toward the winch house.
	for sz in [-1, 1]:
		_beam(Vector3(tip, h, sz * tip), Vector3(7.2, 0.6, sz * 2.6), 0.32, true)
		A.box(self, Vector3(1.0, 0.6, 1.0), Vector3(7.2, 0.3, sz * 2.6), "concrete", Color(0.8, 0.75, 0.7), true)
	# Head frame: a square of heavy beams where everything meets, and a plated deck on top.
	for s in [-1, 1]:
		A.box(self, Vector3(2 * tip + 0.5, 0.5, 0.5), Vector3(0, h - 0.25, s * tip), "rust", Color.WHITE, true, 1.0)
		A.box(self, Vector3(0.5, 0.5, 2 * tip + 0.5), Vector3(s * tip, h - 0.25, 0), "rust", Color.WHITE, true, 1.0)
	var d := tip + 0.3
	var hole := 0.35   # the cable drops through here
	for s in [-1, 1]:
		A.box(self, Vector3(2 * d, 0.12, d - hole), Vector3(0, h + 0.06, s * (hole + (d - hole) / 2)), "riveted", Color(0.75, 0.65, 0.6), true, 1.0)
		A.box(self, Vector3(d - hole, 0.12, 2 * hole), Vector3(s * (hole + (d - hole) / 2), h + 0.06, 0), "riveted", Color(0.75, 0.65, 0.6), true, 1.0)
	for s in [-1, 1]:
		A.railing(self, Vector3(-d, h + 0.12, s * d), Vector3(d, h + 0.12, s * d), 1.0, "rust")
		A.railing(self, Vector3(s * d, h + 0.12, -d), Vector3(s * d, h + 0.12, d), 1.0, "rust")
	# Sheave wheel on two bearing stands; its left edge sits over the shaft centre.
	var wheel_x := SHEAVE_R
	for z in [-0.42, 0.42]:
		for k in [-1, 1]:
			var leg := A.box(self, Vector3(0.18, 2.0, 0.22), Vector3(wheel_x + k * 0.45, h + 0.95, z), "rust", Color(0.85, 0.85, 0.85), false, 1.0)
			leg.rotation.z = -k * 0.25
		A.box(self, Vector3(0.5, 0.35, 0.3), Vector3(wheel_x, SHEAVE_Y, z), "metal", Color(0.4, 0.4, 0.4), false)
	A.cyl(self, 0.09, 1.1, Vector3(wheel_x, SHEAVE_Y, 0), "metal", Color(0.75, 0.75, 0.7), false, "z")
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.position = Vector3(wheel_x, SHEAVE_Y, 0)
	A.cyl(pivot, SHEAVE_R, 0.22, Vector3.ZERO, "rust", Color.WHITE, false, "z")
	A.cyl(pivot, SHEAVE_R * 0.82, 0.24, Vector3.ZERO, "metal", Color(0.18, 0.17, 0.16), false, "z")
	A.cyl(pivot, SHEAVE_R * 0.22, 0.3, Vector3.ZERO, "rust", Color(0.8, 0.8, 0.8), false, "z")
	for k in 6:
		var spoke := A.box(pivot, Vector3(SHEAVE_R * 1.7, 0.1, 0.12), Vector3.ZERO, "rust", Color(0.9, 0.9, 0.9), false, 1.0)
		spoke.rotation.z = k * PI / 6
	_sheaves.append(pivot)
	var lamp_post := A.box(self, Vector3(0.12, 1.0, 0.12), Vector3(-d + 0.2, h + 0.6, -d + 0.2), "metal", Color(0.4, 0.4, 0.4), false)
	A.glow(lamp_post, Vector3(0.22, 0.22, 0.22), Vector3(0, 0.6, 0), Color(1, 0.15, 0.1), 6.0)
	# Main cable (resized as the cab moves) and the haul cable to the winch drum.
	_cable = B.box(self, Vector3(0.05, 1.0, 0.05), Vector3.ZERO, Color(0.12, 0.11, 0.1), false)
	var wx := 10.5
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
	_beam(Vector3(wx - 2.1, 2.1, 0), Vector3(wheel_x + SHEAVE_R * 0.75, SHEAVE_Y + SHEAVE_R * 0.66, 0), 0.05)


func _cab() -> void:
	var g := Color(0.85, 0.8, 0.75)
	A.box(cab, Vector3(3.6, 0.1, 3.6), Vector3(0, 0.01, 0), "grate", g, true, 1.2)
	A.box(cab, Vector3(3.5, 0.03, 3.5), Vector3(0, -0.06, 0), "metal", Color(0.3, 0.3, 0.3), false)
	A.box(cab, Vector3(0.05, 3.0, 3.6), Vector3(-HALF + 0.03, 1.5, 0), "grate", g, true, 1.2)
	A.box(cab, Vector3(0.05, 3.0, 3.6), Vector3(HALF - 0.03, 1.5, 0), "grate", g, true, 1.2)
	A.box(cab, Vector3(3.6, 3.0, 0.05), Vector3(0, 1.5, HALF - 0.03), "grate", g, true, 1.2)
	A.wall(cab, -HALF, HALF, -HALF + 0.03, 3.0, 0.05, [[0.0, DW, 0.0, DH]], "grate", g, true, 0.0, true, 1.2)
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
	_bulkhead_lamp(cab, Vector3(0, 3.0, 0), Vector3.DOWN, Color(1, 0.82, 0.58))
	B.omni(cab, Vector3(0, 2.6, 0), Color(1, 0.8, 0.55), 1.0, 5.0)
	_car_panel()
	# Sliding cage doors.
	for s in [-1, 1]:
		var door := A.box(cab, Vector3(DW / 2, DH, 0.04), Vector3(s * DW / 4, DH / 2, -HALF + 0.09), "grate", g, true, 1.2)
		A.box(door, Vector3(DW / 2, 0.08, 0.06), Vector3(0, DH / 2 - 0.05, 0), "rust", Color.WHITE, false, 1.0)
		A.box(door, Vector3(0.06, DH, 0.06), Vector3(-s * DW / 4, 0, 0), "rust", Color.WHITE, false, 1.0)
		_cab_doors.append(door)


func _landing(top: bool) -> void:
	var y := 0.0 if top else bottom
	var face := -SHAFT - 0.15   # outer face of the shaft wall the doors are in
	var steel := Color(0.36, 0.38, 0.4)
	# Portal frame round the opening: jambs and a deep head, standing proud of the wall.
	for s in [-1, 1]:
		A.box(self, Vector3(0.22, DH + 0.22, 0.12), Vector3(s * (DW / 2 + 0.105), y + (DH + 0.22) / 2, face - 0.06), "metal", steel, false, 0.8)
		A.box(self, Vector3(0.05, DH, 0.02), Vector3(s * (DW / 2 + 0.03), y + DH / 2, face - 0.13), "hazard", Color.WHITE, false, 0.4)   # edge stripe
	A.box(self, Vector3(DW + 0.66, 0.5, 0.14), Vector3(0, y + DH + 0.25, face - 0.07), "metal", steel, false, 0.8)
	A.box(self, Vector3(DW + 0.4, 0.02, 0.6), Vector3(0, y + 0.01, face - 0.3), "riveted", Color(0.55, 0.55, 0.52), false, 0.6)   # threshold plate
	# Enamel sign on the head: LIFT, and which level this is.
	A.box(self, Vector3(1.0, 0.32, 0.02), Vector3(-0.35, y + DH + 0.25, face - 0.15), "cream", Color(0.9, 0.82, 0.5), false, 0.5)
	var word := B.label(self, "LIFT", Vector3(-0.35, y + DH + 0.27, face - 0.161), 40, Color(0.1, 0.09, 0.08), "plate", 0.0055)
	word.rotation.y = PI
	var lvl := B.label(self, "SURFACE" if top else "LEVEL B-1", Vector3(-0.35, y + DH + 0.12, face - 0.161), 20, Color(0.15, 0.13, 0.1), "plate", 0.0055)
	lvl.rotation.y = PI
	# Floor indicator: a little housing with up / down lamps (lit while the car is coming or going).
	A.box(self, Vector3(0.42, 0.2, 0.06), Vector3(0.55, y + DH + 0.27, face - 0.17), "metal", Color(0.12, 0.12, 0.12), false)
	var lamps := []
	for k in 2:
		var lamp := A.box(self, Vector3(0.1, 0.1, 0.01), Vector3(0.45 + k * 0.2, y + DH + 0.27, face - 0.205), "metal", Color.WHITE, false)
		lamp.rotation.z = PI / 4
		lamp.material_override = A.mat("cream", Color(0.25, 0.15, 0.08), 1.0, 0.2)
		lamps.append(lamp)
	_arrows[top] = lamps
	# Call panel: brushed plate, mushroom button, CALL stencil.
	var px := DW / 2 + 0.55
	A.box(self, Vector3(0.18, 0.3, 0.03), Vector3(px, y + 1.3, face - 0.015), "metal", Color(0.62, 0.62, 0.6), false, 0.3)
	A.cyl(self, 0.045, 0.03, Vector3(px, y + 1.33, face - 0.045), "metal", Color(0.3, 0.3, 0.3), false, "z")
	A.cyl(self, 0.035, 0.025, Vector3(px, y + 1.33, face - 0.07), "cream", Color(1, 0.55, 0.15), false, "z").material_override = A.mat("cream", Color(1, 0.55, 0.15), 1.0, 2.5)
	var call := B.label(self, "CALL", Vector3(px, y + 1.22, face - 0.032), 14, Color(0.12, 0.12, 0.12), "stencil", 0.005)
	call.rotation.y = PI
	B.interactable(self, Vector3(0.18, 0.3, 0.1), Vector3(px, y + 1.3, face - 0.06), Color(0, 0, 0, 0), "Call elevator", call_to.bind(top), 0.0, 0.0)
	# Sliding shaft doors: ribbed steel leaves with a slot of wired glass and a chevron kick plate.
	var pair := []
	for s in [-1, 1]:
		var door := A.box(self, Vector3(DW / 2, DH, 0.05), Vector3(s * DW / 4, y + DH / 2, -SHAFT + 0.18), "metal", Color(0.5, 0.48, 0.44), true, 1.0)
		var wc := Vector2(-s * 0.18, 0.45)
		var ws := Vector2(0.12, 0.5)
		door.get_child(1).visible = false   # (the collision stays whole; the look gets a real slot)
		A.panel_with_hole(door, Vector3(DW / 2, DH, 0.05), wc, ws, "metal", Color(0.5, 0.48, 0.44), 1.0)
		for k in 5:
			var ry := -DH / 2 + 0.55 + k * 0.42
			if absf(ry - wc.y) < ws.y / 2.0 + 0.05:
				continue   # not across the window
			A.box(door, Vector3(DW / 2 - 0.08, 0.04, 0.012), Vector3(0, ry, -0.031), "metal", Color(0.4, 0.38, 0.35), false)
		var win := A.box(door, Vector3(ws.x, ws.y, 0.008), Vector3(wc.x, wc.y, 0), "metal", Color.WHITE, false)
		win.material_override = A.glass()
		A.window_frame(door, wc, ws, 0.05, Color(0.1, 0.1, 0.1))
		A.box(door, Vector3(DW / 2 - 0.02, 0.28, 0.01), Vector3(0, -DH / 2 + 0.16, -0.03), "hazard", Color.WHITE, false, 0.5)
		pair.append(door)
	_landing_doors[top] = pair


## The facility's own wall finish over the bottom of the shaft, so the lift looks built into the room.
func _clad(theme: Dictionary, facility_h: float) -> void:
	var y0 := bottom
	var band := 1.1
	var t := SHAFT + 0.165   # just outside the concrete
	for s in [-1, 1]:
		A.box(self, Vector3(0.02, band, 2 * t), Vector3(s * t, y0 + band / 2, 0), theme.band_kind, theme.band, false, 1.5)
		A.box(self, Vector3(0.02, facility_h - band, 2 * t), Vector3(s * t, y0 + band + (facility_h - band) / 2, 0), theme.wall_kind, theme.wall, false, 2.0)
	A.box(self, Vector3(2 * t, band, 0.02), Vector3(0, y0 + band / 2, t), theme.band_kind, theme.band, false, 1.5)
	A.box(self, Vector3(2 * t, facility_h - band, 0.02), Vector3(0, y0 + band + (facility_h - band) / 2, t), theme.wall_kind, theme.wall, false, 2.0)
	A.wall(self, -t, t, -t, band, 0.02, [[0.0, DW + 0.44, 0.0, band + 1.0]], theme.band_kind, theme.band, true, y0, false, 1.5)
	A.wall(self, -t, t, -t, facility_h - band, 0.02, [[0.0, DW + 0.44, -10.0, DH + 0.5 - band]], theme.wall_kind, theme.wall, true, y0 + band, false, 2.0)


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
		if n.has_meta("net_puppet"):
			continue   # (the host's item: it goes where the host says)
		if inside(n.global_position):
			if n is RigidBody3D:
				n.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				n.freeze = true
				n.reparent(cab)
				_cargo.append(n)
			else:
				_riders.append(n)
	_bodies.clear()
	for r in get_tree().get_nodes_in_group("pickups"):
		if "parts" in r and not r.puppet and not r.parts.is_empty() and inside(r.global_position):
			for b in r.parts.values():
				b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				b.freeze = true
			_bodies.append(r)
	_from = cab.position.y
	_to = bottom if at_top else 0.0
	_t = 0.0
	_travel = true
	_floor_label.text = ("▼ DOWN" if at_top else "▲ UP") if level.powered() else "EMRG PWR"
	_motor.pitch_scale = 1.0 if level.powered() else 0.6
	_motor.play()
	_light_arrows(not at_top)
	Sfx.play(self, "clunk", cab.global_position + Vector3(0, 3, 0), -2.0)
	_music.play()


func _physics_process(delta: float) -> void:
	if not _travel:
		return
	var crawl := 1.0 if level.powered() else 3.0   # emergency power: a third of the speed
	_t = minf(1.0, _t + delta / (RIDE_SECS * maxf(Data.pace(), 0.3) * crawl))   # riders need small steps
	var y := lerpf(_from, _to, smoothstep(0.0, 1.0, _t))
	var dy := y - cab.position.y
	cab.position.y = y
	for s in _sheaves:
		s.rotation.z += dy / SHEAVE_R
	_update_cable()
	for r in _riders:
		if is_instance_valid(r):
			r.global_position.y += dy
	for r in _bodies:
		if is_instance_valid(r):
			for b in r.parts.values():
				b.global_position.y += dy
			if r.has_method("shake"):
				r.shake(0.004)
	if _t >= 1.0:
		_arrive()


func _update_cable() -> void:
	var top_y := SHEAVE_Y
	var low := cab.position.y + 3.12
	_cable.scale.y = maxf(0.01, top_y - low)
	_cable.position = Vector3(0, (top_y + low) / 2.0, 0)


func _arrive() -> void:
	_travel = false
	Sfx.play(self, "clunk", cab.global_position + Vector3(0, 0.5, 0), 0.0, 0.85)
	_motor.stop()
	_music.stop()
	_light_arrows(null)
	at_top = not at_top
	_floor_label.text = "SURFACE" if at_top else "SITE B-1"
	Sfx.play(self, "ding", cab.global_position + Vector3(0, 2.5, 0))
	for c in _cargo:
		if is_instance_valid(c):
			c.reparent(level)
			c.freeze = false
	_cargo.clear()
	for r in _bodies:
		if is_instance_valid(r):
			for b in r.parts.values():
				b.freeze = false
	_bodies.clear()
	_riders.clear()
	await _set_doors(true)
	moving = false


## Up / down lamps on both landings: lit while the car moves (going_up null = all off).
func _light_arrows(going_up) -> void:
	for top in _arrows:
		for k in 2:
			var on: bool = going_up != null and (k == 0) == going_up
			_arrows[top][k].material_override = A.mat("cream", Color(1, 0.6, 0.2) if on else Color(0.25, 0.15, 0.08), 1.0, 3.0 if on else 0.2)


## Site power went out or came back: the readout says so.
func power_changed(on: bool) -> void:
	if not moving:
		_floor_label.text = ("SURFACE" if at_top else "SITE B-1") if on else "EMRG PWR"


## Car operating panel on the cab's side wall (faces -x): a brushed plate with a recessed amber
## readout, two lit push buttons, an emergency stop, a key switch and the maker's plate.
func _car_panel() -> void:
	var px := HALF - 0.06
	var pz := -1.2
	A.box(cab, Vector3(0.03, 0.85, 0.42), Vector3(px, 1.35, pz), "metal", Color(0.62, 0.62, 0.6), false, 0.3)   # brushed plate
	for e in [[0.4, 0.2], [-0.4, 0.2], [0.4, -0.2], [-0.4, -0.2]]:
		A.sphere(cab, 0.012, Vector3(px - 0.018, 1.35 + e[0], pz + e[1]), "metal", Color(0.4, 0.4, 0.4))   # screws
	# Readout: a dark recessed window with amber monospaced text and a faint glow.
	A.box(cab, Vector3(0.02, 0.15, 0.34), Vector3(px - 0.02, 1.64, pz), "metal", Color(0.08, 0.08, 0.08), false)
	A.box(cab, Vector3(0.006, 0.11, 0.3), Vector3(px - 0.031, 1.64, pz), "metal", Color(0.05, 0.03, 0.02), false).material_override = A.mat("cream", Color(0.12, 0.05, 0.02), 1.0, 0.4)
	_floor_label = Label3D.new()
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "monospace"])
	mono.font_weight = 700
	_floor_label.font = mono
	_floor_label.font_size = 40
	_floor_label.pixel_size = 0.0011
	_floor_label.modulate = Color(1, 0.6, 0.18)
	_floor_label.outline_size = 0
	_floor_label.shaded = false
	_floor_label.double_sided = false
	_floor_label.text = "SURFACE"
	cab.add_child(_floor_label)
	_floor_label.position = Vector3(px - 0.036, 1.64, pz)
	_floor_label.rotation.y = -PI / 2
	# Two buttons with arrows and their legends, an emergency stop below.
	for k in 2:
		var by := 1.45 - k * 0.16
		A.cyl(cab, 0.045, 0.02, Vector3(px - 0.02, by, pz - 0.07), "metal", Color(0.3, 0.3, 0.3), false, "x")
		A.cyl(cab, 0.035, 0.025, Vector3(px - 0.03, by, pz - 0.07), "cream", Color(1, 0.75, 0.3), false, "x").material_override = A.mat("cream", Color(1, 0.72, 0.3), 1.0, 1.5)
		var arrow := B.label(cab, "▲" if k == 0 else "▼", Vector3(px - 0.044, by, pz - 0.07), 30, Color(0.25, 0.12, 0.04), "stencil", 0.0018)
		arrow.rotation.y = -PI / 2
		var legend := B.label(cab, "SURFACE" if k == 0 else "SITE B-1", Vector3(px - 0.018, by, pz + 0.08), 22, Color(0.12, 0.12, 0.12), "stencil", 0.0028)
		legend.rotation.y = -PI / 2
	A.cyl(cab, 0.05, 0.025, Vector3(px - 0.02, 1.08, pz), "hazard", Color.WHITE, false, "x")   # e-stop collar
	A.cyl(cab, 0.04, 0.05, Vector3(px - 0.045, 1.08, pz), "plastic", Color(0.8, 0.08, 0.05), false, "x", 0.032)
	A.cyl(cab, 0.022, 0.02, Vector3(px - 0.02, 1.18, pz + 0.13), "brass", Color.WHITE, false, "x")   # key switch
	A.box(cab, Vector3(0.005, 0.008, 0.026), Vector3(px - 0.031, 1.18, pz + 0.13), "metal", Color(0.1, 0.1, 0.1), false)
	var maker := B.label(cab, "B.R.M.  LIFT 2\nMAX 1000 KG", Vector3(px - 0.018, 0.98, pz + 0.05), 18, Color(0.15, 0.15, 0.15), "plate", 0.0028)
	maker.rotation.y = -PI / 2
	B.interactable(cab, Vector3(0.08, 0.36, 0.2), Vector3(px - 0.05, 1.37, pz - 0.07), Color(0, 0, 0, 0), "Ride elevator", ride, 0.0, 0.0)


## Caged bulkhead fitting: cast base, frosted glass dome, wire guard. normal points out of the mount.
func _bulkhead_lamp(parent: Node3D, at: Vector3, normal: Vector3, c: Color) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.position = at
	root.basis = Basis(Quaternion(Vector3.UP, normal))   # local +y = out of the wall / down from the ceiling
	A.cyl(root, 0.11, 0.05, Vector3(0, 0.025, 0), "metal", Color(0.3, 0.32, 0.3), false)
	var dome := A.sphere(root, 0.08, Vector3(0, 0.06, 0), "cream", c.lerp(Color.WHITE, 0.5), 3.5, 0.9)
	dome.set_meta("live", true)
	for k in 3:   # guard hoops
		var hoop := A.ring(root, 0.095, 0.085, Vector3(0, 0.07, 0), "metal", Color(0.2, 0.2, 0.2), Vector3(0, k * PI / 3, PI / 2))
	A.ring(root, 0.105, 0.095, Vector3(0, 0.05, 0), "metal", Color(0.2, 0.2, 0.2))


## Slides the cab doors and the doors of the landing the cab is at.
func _set_doors(open: bool) -> void:
	# Where every door should be: the cab and the landing it's at open or shut as asked, the other
	# landing always shut. Checked per door, so the state can't get out of step with the car.
	var want := {}
	for d in _cab_doors + _landing_doors[at_top]:
		want[d] = open
	for d in _landing_doors[not at_top]:
		want[d] = false
	var tw := create_tween().set_parallel()
	var moved := false
	for doors in [_cab_doors, _landing_doors[true], _landing_doors[false]]:
		for i in doors.size():
			var s := -1.0 if i % 2 == 0 else 1.0
			var x: float = s * (DW * 0.73 if want[doors[i]] else DW / 4)
			if absf(doors[i].position.x - x) > 0.01:
				moved = true
				tw.tween_property(doors[i], "position:x", x, 1.1 * Data.pace()).set_trans(Tween.TRANS_SINE)
	_doors_open = open
	if not moved:
		tw.kill()
		return
	if cab.is_inside_tree():
		Sfx.play(self, "slide", cab.global_position + Vector3(0, 1.5, -HALF), -4.0, randf_range(0.95, 1.1))
	if tw.is_running():   # a long frame can finish it before we get here
		await tw.finished
