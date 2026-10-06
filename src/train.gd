# The train: a rusty road-switcher diesel + walkable crew car + flatcar (+ optional storage car).
# Floor is at y = 1.0 so station platforms line up with the doors; the platform side is +z.
# `speed` (m/s) drives wheels and exhaust. Static parts are merged into a few meshes (merge.gd).
extends Node3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")
const Merge = preload("res://src/merge.gd")

const F := 1.0  # floor height
const INSIDE := AABB(Vector3(-8.1, 0.6, -2.0), Vector3(16.2, 3.2, 4.0))
const STORAGE := AABB(Vector3(-20.5, 0.6, -2.0), Vector3(12.4, 3.2, 4.0))
const CAR_LEN := 12.4
const WALL_H := 2.7

const CREAM := Color(0.86, 0.8, 0.66)
const FRAME := Color(0.2, 0.19, 0.18)
const RAIL := Color(0.9, 0.72, 0.2)          # safety-yellow handrails

var speed := 0.0
var clock_label: Label3D
var market_label: Label3D
var headlight: SpotLight3D
var _wheels: Array = []   # [pivot, radius]
var _rods: Array = []     # [rod, center_x, side]
var _angle := 0.0
var _steam: GPUParticles3D
var _steam_mat: ParticleProcessMaterial
var _chug: AudioStreamPlayer3D
var has_storage := false
var _rear_lock: Node3D
var _flat: Node3D


func contains(pos: Vector3) -> bool:
	var l := to_local(pos)
	return INSIDE.has_point(l) or (has_storage and STORAGE.has_point(l))


## x of the very back of the train (where the delivery handcar parks).
func rear_x() -> float:
	return -15.6 - (CAR_LEN if has_storage else 0.0)


func build(open_terminal: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_car()
	_interior(open_terminal, rng)
	_locomotive()
	_flatcar(rng)
	_chug = AudioStreamPlayer3D.new()
	_chug.stream = Sfx.stream("chug")
	_chug.unit_size = 10.0
	add_child(_chug)
	_chug.position = Vector3(11, 2, 0)
	Merge.live(_rear_lock)   # removed when the storage car is bought
	Merge.live(_flat)        # slides back when the storage car is bought
	Merge.bake(self, 8.0)
	Merge.bake(_flat, 8.0)


func _process(delta: float) -> void:
	_angle -= speed * delta
	for w in _wheels:
		w[0].rotation.z = _angle / w[1]
	_steam.amount_ratio = clampf(0.25 + absf(speed) / 6.0, 0.0, 1.0)
	_steam_mat.gravity = Vector3(-speed * 2.0, 1.5, 0)
	if absf(speed) > 0.3:
		if not _chug.playing:
			_chug.play()
		_chug.pitch_scale = clampf(0.4 + absf(speed) / 12.0, 0.4, 2.5)
		_chug.volume_db = -6.0
	elif _chug.playing:
		_chug.stop()


# --- running gear (shared) -------------------------------------------------------

## Wheel on a live pivot (it spins): tyre, flange, dished centre, spokes so the motion reads.
func _wheel(pos: Vector3, radius: float, parent: Node = null) -> Node3D:
	var pivot := Node3D.new()
	(parent if parent else self).add_child(pivot)
	pivot.position = pos
	Merge.live(pivot)
	var s := signf(pos.z) if pos.z != 0.0 else 1.0
	A.cyl(pivot, radius, 0.1, Vector3.ZERO, "metal", Color(0.42, 0.4, 0.38), false, "z")
	A.cyl(pivot, radius + 0.035, 0.025, Vector3(0, 0, -s * 0.05), "metal", Color(0.3, 0.29, 0.28), false, "z")   # flange, rail side
	A.cyl(pivot, radius * 0.82, 0.12, Vector3.ZERO, "rust", Color(0.75, 0.7, 0.68), false, "z")
	A.cyl(pivot, radius * 0.22, 0.2, Vector3.ZERO, "metal", Color(0.3, 0.3, 0.3), false, "z")
	for a in [0.0, PI / 3, 2 * PI / 3]:
		var spoke := A.box(pivot, Vector3(radius * 1.6, 0.07, 0.13), Vector3.ZERO, "rust", Color(0.65, 0.6, 0.58), false, 1.0)
		spoke.rotation.z = a
	A.box(pivot, Vector3(radius * 0.5, radius * 0.25, 0.14), Vector3(radius * 0.45, 0, 0), "metal", Color(0.3, 0.3, 0.3), false)   # counterweight
	_wheels.append([pivot, radius])
	return pivot


## A truck/bogie: cast side frames with spring nests, axle boxes, brake shoes, a bolster,
## `axles` axles `spacing` apart, wheels on the rails (z = +-0.78). Optional traction motors.
func _bogie(parent: Node, x: float, axles: int, spacing: float, radius := 0.45, motors := false) -> void:
	var half := (axles - 1) * spacing / 2.0
	var y := radius
	for s in [-1, 1]:
		var z: float = s * 1.0
		A.box(parent, Vector3(half * 2 + 0.9, 0.18, 0.12), Vector3(x, y + 0.08, z), "metal", FRAME, false, 0.6)
		A.box(parent, Vector3(half * 2 + 0.5, 0.1, 0.12), Vector3(x, y - 0.12, z), "metal", FRAME, false, 0.6)
		for k in axles:
			var ax := x - half + k * spacing
			A.box(parent, Vector3(0.3, 0.34, 0.2), Vector3(ax, y, z), "metal", Color(0.28, 0.27, 0.26), false, 0.4)
			A.cyl(parent, 0.07, 0.05, Vector3(ax, y, z + s * 0.11), "metal", Color(0.5, 0.48, 0.45), false, "z")
			for b in [-1, 1]:   # brake shoes
				if (k == 0 and b < 0) or (k == axles - 1 and b > 0) or axles == 2:
					A.box(parent, Vector3(0.08, 0.3, 0.12), Vector3(ax + b * (radius + 0.06), y, s * 0.78), "metal", Color(0.25, 0.25, 0.25), false)
		for k in axles - 1:   # spring nests between axles
			var mx := x - half + (k + 0.5) * spacing
			for dz in [-0.08, 0.08]:
				A.cyl(parent, 0.06, 0.24, Vector3(mx + dz, y + 0.05, z), "metal", Color(0.55, 0.52, 0.48))
			for r in 4:
				A.ring(parent, 0.075, 0.055, Vector3(mx, y - 0.04 + r * 0.06, z), "metal", Color(0.6, 0.58, 0.55))
	A.box(parent, Vector3(0.45, 0.28, 2.0), Vector3(x, y + 0.12, 0), "metal", FRAME, false, 0.6)   # bolster
	for k in axles:
		var ax := x - half + k * spacing
		A.cyl(parent, 0.08, 1.7, Vector3(ax, y, 0), "metal", Color(0.3, 0.3, 0.3), false, "z")   # axle
		if motors:
			A.cyl(parent, 0.28, 0.9, Vector3(ax + 0.25, y + 0.02, 0), "metal", Color(0.22, 0.24, 0.26), false, "z")
		for s in [-1, 1]:
			_wheel(Vector3(ax, y, s * 0.78), radius, parent)


## Knuckle coupler pointing along `dir` (+1 / -1 in x), with an air hose and cut lever.
func _coupler(parent: Node, x: float, dir: float) -> void:
	A.box(parent, Vector3(0.5, 0.2, 0.25), Vector3(x, 0.75, 0), "metal", FRAME, false)
	A.box(parent, Vector3(0.22, 0.32, 0.32), Vector3(x + dir * 0.3, 0.75, 0), "metal", Color(0.3, 0.29, 0.28), false)
	A.box(parent, Vector3(0.12, 0.3, 0.12), Vector3(x + dir * 0.42, 0.75, 0.1), "metal", Color(0.3, 0.29, 0.28), false)
	A.seg(parent, Vector3(x, 0.62, 0.35), Vector3(x + dir * 0.35, 0.4, 0.3), 0.035, 0.035, "rubber")
	A.cyl(parent, 0.05, 0.12, Vector3(x + dir * 0.38, 0.38, 0.3), "brass", Color.WHITE, false, "x")
	A.seg(parent, Vector3(x, 0.95, -0.3), Vector3(x, 0.95, -1.2), 0.015, 0.015, "metal", Color(0.5, 0.5, 0.5))


## Hanging boarding steps with side plates.
func _steps(parent: Node, x: float, z: float, w := 0.6) -> void:
	var s := signf(z)
	for i in 2:
		A.box(parent, Vector3(w, 0.04, 0.28), Vector3(x, 0.62 - i * 0.3, z), "grate", Color.WHITE, false, 0.3)
	for e in [-1, 1]:
		A.box(parent, Vector3(0.04, 0.55, 0.3), Vector3(x + e * w / 2, 0.55, z), "metal", FRAME, false)
	A.box(parent, Vector3(w, 0.03, 0.03), Vector3(x, 0.32, z + s * 0.14), "metal", RAIL, false)


## Left-to-right spans of x0..x1 minus the given [centre, width] holes.
func _spans(x0: float, x1: float, holes: Array) -> Array:
	var cuts := [[x0, x0]]
	var hs := holes.duplicate()
	hs.sort_custom(func(a, b): return a[0] < b[0])
	for h in hs:
		cuts.append([h[0] - h[1] / 2.0, h[0] + h[1] / 2.0])
	cuts.append([x1, x1])
	var out := []
	for i in cuts.size() - 1:
		if cuts[i + 1][0] - cuts[i][1] > 0.05:
			out.append([cuts[i][1], cuts[i + 1][0]])
	return out


# --- passenger-style car body (crew car + storage car share this) -------------------

## Everything on the outside of a car shell between x0 and x1: ribs, belt rail, letterboard,
## window frames, side sill, door tracks with the door leaves slid open, roof, underframe.
func _car_dress(parent: Node, x0: float, x1: float, doors: Array, windows: Array, back_windows: Array, title: String, number: String, slide: Array, kind := "maroon", tint := Color.WHITE) -> void:
	var xc := (x0 + x1) / 2.0
	var len := x1 - x0
	for s in [-1, 1]:
		var z: float = s * 2.23
		var holes: Array = (doors + windows) if s > 0 else back_windows
		var door_spans: Array = doors if s > 0 else []
		var leaves: Array = slide if s > 0 else []
		# Ribs, skipping holes and parked door leaves.
		var blocked := holes + leaves.map(func(l): return [l, 1.6])
		var x := x0 + 0.5
		while x < x1 - 0.3:
			var clear := true
			for h in blocked:
				if absf(x - h[0]) < h[1] / 2.0 + 0.1:
					clear = false
			if clear:
				A.box(parent, Vector3(0.07, WALL_H - 0.1, 0.04), Vector3(x, F + WALL_H / 2.0, z), kind, tint.darkened(0.2), false, 1.0)
			x += 0.95
		# Belt rail and window-sill band (broken by doors), letterboard above everything.
		for sp in _spans(x0, x1, door_spans):
			var w: float = sp[1] - sp[0]
			var c: float = (sp[0] + sp[1]) / 2.0
			A.box(parent, Vector3(w, 0.08, 0.05), Vector3(c, F + 0.92, z + s * 0.01), "metal", FRAME, false, 1.0)
		A.box(parent, Vector3(len - 0.1, 0.32, 0.03), Vector3(xc, F + 2.5, z + s * 0.01), "cream", CREAM, false, 2.0)
		A.box(parent, Vector3(len, 0.05, 0.06), Vector3(xc, F + 2.34, z + s * 0.02), "metal", FRAME, false, 1.0)
		var t := B.label(parent, title, Vector3(xc, F + 2.5, z + s * 0.035), 46, Color(0.32, 0.12, 0.08), "plate", 0.0055)
		t.rotation.y = 0.0 if s > 0 else PI
		var n := B.label(parent, number, Vector3(x1 - 1.2 if s > 0 else x0 + 1.2, F + 0.62, z + s * 0.02), 60, CREAM, "stencil", 0.006)
		n.rotation.y = 0.0 if s > 0 else PI
		# Window frames.
		for h in holes:
			if h[2] <= 0.0:
				continue
			var wx: float = h[0]
			var ww: float = h[1]
			var y0: float = F + h[2]
			var y1: float = F + h[3]
			A.box(parent, Vector3(ww + 0.16, 0.08, 0.1), Vector3(wx, y0 - 0.02, z + s * 0.03), "metal", FRAME, false)
			A.box(parent, Vector3(ww + 0.12, 0.06, 0.06), Vector3(wx, y1 + 0.03, z + s * 0.02), "metal", FRAME, false)
			for e in [-1, 1]:
				A.box(parent, Vector3(0.06, y1 - y0, 0.06), Vector3(wx + e * (ww / 2 + 0.03), (y0 + y1) / 2, z + s * 0.02), "metal", FRAME, false)
			A.box(parent, Vector3(0.03, y1 - y0, 0.04), Vector3(wx, (y0 + y1) / 2, z + s * 0.0), "metal", FRAME, false)   # mullion
		# Side sill (skirt) under the floor line.
		A.box(parent, Vector3(len, 0.32, 0.06), Vector3(xc, F - 0.18, s * 2.18), "metal", FRAME, false, 1.0)
		for k in int(len / 1.2):
			A.box(parent, Vector3(0.04, 0.3, 0.07), Vector3(x0 + 0.6 + k * 1.2, F - 0.18, s * 2.19), "metal", Color(0.3, 0.29, 0.28), false)
	# Door track over each platform door, the leaf slid open beside it, a step below.
	for k in doors.size():
		var d: Array = doors[k]
		A.box(parent, Vector3(3.4, 0.08, 0.1), Vector3(d[0] + (slide[k] - d[0]) / 2.0, F + 2.32, 2.3), "metal", FRAME, false)
		var leaf := Vector3(slide[k], F + 1.15, 2.3)
		A.box(parent, Vector3(1.5, 2.28, 0.05), leaf, kind, tint.darkened(0.08), false, 1.0)
		A.box(parent, Vector3(0.6, 0.7, 0.01), leaf + Vector3(0, 0.45, 0.03), "metal", Color(0.06, 0.06, 0.07), false)
		var g = A.box(parent, Vector3(0.56, 0.66, 0.01), leaf + Vector3(0, 0.45, 0.04), "metal", Color.WHITE, false)
		g.material_override = A.glass()
		A.box(parent, Vector3(1.5, 0.3, 0.06), leaf + Vector3(0, -0.95, 0.01), "metal", FRAME, false)
		for r in 2:
			A.box(parent, Vector3(0.1, 0.06, 0.06), leaf + Vector3(-0.6 + r * 1.2, 1.12, 0.0), "metal", Color(0.4, 0.4, 0.4), false)   # rollers
		_steps(parent, d[0], 2.38, 1.3)
	_roof(parent, x0, x1)
	# Underframe between the trucks: truss rods, air reservoirs, battery box, brake cylinder.
	for s in [-1, 1]:
		var z: float = s * 1.25
		A.seg(parent, Vector3(x0 + 2.4, 0.6, z), Vector3(xc - 1.4, 0.18, z), 0.025, 0.025, "metal", FRAME)
		A.seg(parent, Vector3(xc - 1.4, 0.18, z), Vector3(xc + 1.4, 0.18, z), 0.025, 0.025, "metal", FRAME)
		A.seg(parent, Vector3(xc + 1.4, 0.18, z), Vector3(x1 - 2.4, 0.6, z), 0.025, 0.025, "metal", FRAME)
		for qx in [xc - 1.4, xc + 1.4]:
			A.box(parent, Vector3(0.1, 0.36, 0.1), Vector3(qx, 0.36, z), "metal", FRAME, false)
	A.cyl(parent, 0.2, 1.6, Vector3(xc - 0.6, 0.38, 0.6), "metal", Color(0.35, 0.36, 0.38), false, "x")
	A.cyl(parent, 0.16, 1.2, Vector3(xc + 1.0, 0.4, -0.7), "metal", Color(0.35, 0.36, 0.38), false, "x")
	A.box(parent, Vector3(1.0, 0.4, 0.7), Vector3(xc + 0.6, 0.35, 0.75), "metal", Color(0.22, 0.24, 0.22), false, 0.6)
	A.box(parent, Vector3(0.8, 0.06, 0.5), Vector3(xc + 0.6, 0.57, 0.75), "metal", Color(0.3, 0.3, 0.3), false)
	A.cyl(parent, 0.15, 0.45, Vector3(xc - 2.0, 0.42, -0.4), "metal", FRAME, false, "x")
	A.seg(parent, Vector3(x0 + 1.0, 0.55, -0.9), Vector3(x1 - 1.0, 0.55, -0.9), 0.02, 0.02, "metal", Color(0.4, 0.4, 0.4))   # train line
	# Ends: corner posts, end ladder, marker lamps, coupler.
	for e in [[x0, -1.0], [x1, 1.0]]:
		var ex: float = e[0]
		var dir: float = e[1]
		for s in [-1, 1]:
			A.box(parent, Vector3(0.12, WALL_H + 0.1, 0.12), Vector3(ex, F + WALL_H / 2.0, s * 2.18), "metal", FRAME, false, 0.6)
		_coupler(parent, ex + dir * 0.2, dir)


## Clerestory-less barrel roof: eight curved strips, gutters, a plank running board, vents.
func _roof(parent: Node, x0: float, x1: float) -> void:
	var xc := (x0 + x1) / 2.0
	var len := x1 - x0 + 0.3
	var rise := 0.5
	var half := 2.3
	for i in 8:
		var a0 := PI * i / 8.0
		var a1 := PI * (i + 1) / 8.0
		var p0 := Vector2(cos(a0) * half, F + WALL_H + sin(a0) * rise)
		var p1 := Vector2(cos(a1) * half, F + WALL_H + sin(a1) * rise)
		var d := p1 - p0
		var strip := A.box(parent, Vector3(len, 0.06, d.length() + 0.02), Vector3(xc, (p0.y + p1.y) / 2.0, (p0.x + p1.x) / 2.0), "maroon", Color(0.55, 0.48, 0.46), false, 2.0)
		strip.rotation.x = atan2(-d.y, d.x)
	for s in [-1, 1]:
		A.box(parent, Vector3(len, 0.06, 0.08), Vector3(xc, F + WALL_H + 0.02, s * 2.32), "metal", FRAME, false)   # gutter
	for k in int(len / 1.9):   # seam straps over the curve
		var sx := x0 + 0.8 + k * 1.9
		for i in 8:
			var a0 := PI * i / 8.0
			var a1 := PI * (i + 1) / 8.0
			var p0 := Vector2(cos(a0) * half, F + WALL_H + sin(a0) * rise + 0.035)
			var p1 := Vector2(cos(a1) * half, F + WALL_H + sin(a1) * rise + 0.035)
			var d := p1 - p0
			var st := A.box(parent, Vector3(0.06, 0.03, d.length() + 0.02), Vector3(sx, (p0.y + p1.y) / 2.0, (p0.x + p1.x) / 2.0), "metal", Color(0.35, 0.33, 0.32), false)
			st.rotation.x = atan2(-d.y, d.x)
	A.box(parent, Vector3(len - 0.6, 0.04, 0.5), Vector3(xc, F + WALL_H + rise + 0.05, 0), "wood", Color(0.6, 0.55, 0.5), false, 0.6)   # running board
	for vx in [x0 + 2.5, xc, x1 - 2.5]:
		A.cyl(parent, 0.17, 0.7, Vector3(vx, F + WALL_H + rise + 0.18, 0.7), "metal", Color(0.5, 0.5, 0.5), false, "x")   # torpedo vent
		A.box(parent, Vector3(0.6, 0.08, 0.22), Vector3(vx, F + WALL_H + rise + 0.04, 0.7), "metal", FRAME, false)
	A.cyl(parent, 0.09, 0.4, Vector3(x1 - 1.0, F + WALL_H + rise + 0.2, -0.6), "rust", Color.WHITE)   # stove pipe
	A.cyl(parent, 0.14, 0.05, Vector3(x1 - 1.0, F + WALL_H + rise + 0.42, -0.6), "rust", Color.WHITE)


# --- crew car -------------------------------------------------------------------

func _car() -> void:
	var door_holes := [[-4.5, 1.5, 0.0, 2.3], [2.6, 1.5, 0.0, 2.3]]
	var side_windows := [[-6.6, 1.0, 1.0, 2.0], [-1.2, 1.0, 1.0, 2.0], [5.0, 1.1, 1.0, 2.0], [7.2, 0.9, 1.0, 2.0]]
	var back_windows := [[4.0, 1.1, 1.0, 2.0], [6.6, 1.0, 1.0, 2.0], [-6.0, 1.0, 1.0, 2.0]]
	# Exterior paint skin + interior red skin.
	A.wall(self, -8.2, 8.2, 2.18, WALL_H, 0.08, door_holes + side_windows, "maroon", Color.WHITE, true, F)
	A.wall(self, -8.2, 8.2, 2.06, WALL_H, 0.08, door_holes + side_windows, "red_wall", Color.WHITE, true, F, false, 1.0)
	A.wall(self, -8.2, 8.2, -2.18, WALL_H, 0.08, back_windows, "maroon", Color.WHITE, true, F)
	A.wall(self, -8.2, 8.2, -2.06, WALL_H, 0.08, back_windows, "red_wall", Color.WHITE, true, F, false, 1.0)
	A.wall(self, -2.2, 2.2, 8.2, WALL_H, 0.15, [[0.0, 1.6, 1.0, 2.0]], "maroon", Color.WHITE, false, F)
	A.wall(self, -2.2, 2.2, -8.2, WALL_H, 0.15, [[0.0, 1.2, 0.0, 2.3]], "maroon", Color.WHITE, false, F)
	_rear_lock = A.box(self, Vector3(0.1, 2.3, 1.2), Vector3(-8.15, F + 1.15, 0), "riveted", Color(0.6, 0.55, 0.5), true, 1.0)
	var lock_sign := B.label(_rear_lock, "STORAGE CAR\nNOT INSTALLED", Vector3(0.07, 0.3, 0), 28, Color(0.95, 0.8, 0.35), "stencil", 0.003)
	lock_sign.rotation.y = PI / 2
	# Wood wainscot inside.
	A.wall(self, -8.1, 8.1, 2.0, 0.9, 0.03, door_holes, "wood", Color.WHITE, true, F, false, 1.0)
	A.wall(self, -8.1, 8.1, -2.0, 0.9, 0.03, [], "wood", Color.WHITE, true, F, false, 1.0)
	for w in side_windows + door_holes:
		if w[2] > 0.0:
			_glass(Vector3(w[0], F + (w[2] + w[3]) / 2.0, 2.12), Vector3(w[1], w[3] - w[2], 0.02))
	for w in back_windows:
		_glass(Vector3(w[0], F + (w[2] + w[3]) / 2.0, -2.12), Vector3(w[1], w[3] - w[2], 0.02))
	# Floor, chassis, ceiling ribs.
	A.box(self, Vector3(16.4, 0.12, 4.2), Vector3(0, F - 0.06, 0), "wood", Color(0.85, 0.8, 0.75), true, 1.5)
	A.box(self, Vector3(16.8, 0.35, 3.4), Vector3(0, 0.7, 0), "rust", Color(0.6, 0.6, 0.6), true)
	A.box(self, Vector3(16.4, 0.08, 4.4), Vector3(0, F + WALL_H + 0.04, 0), "metal", Color(0.5, 0.45, 0.42), true)
	for i in 9:
		A.box(self, Vector3(0.1, 0.12, 4.1), Vector3(-8.0 + i * 2.0, F + WALL_H - 0.06, 0), "rust", Color.WHITE, false, 1.0)
	# Door frames + grab irons.
	for d in door_holes:
		for s in [-1, 1]:
			A.box(self, Vector3(0.08, 2.4, 0.06), Vector3(d[0] + s * 0.8, F + 1.2, 2.25), "metal", FRAME, false)
			A.cyl(self, 0.025, 1.2, Vector3(d[0] + s * 0.95, F + 1.0, 2.36), "metal", RAIL)
	_car_dress(self, -8.2, 8.2, door_holes, side_windows, back_windows, "BUREAU OF RECLAIMED MATERIALS", "BRM 207", [-2.95, 1.0])
	# End details: gangway diaphragm at the back, a ladder and red markers.
	for dz in [-0.75, 0.75]:
		A.box(self, Vector3(0.3, 2.4, 0.1), Vector3(-8.4, F + 1.2, dz), "rubber", Color.WHITE, false, 0.5)
	A.box(self, Vector3(0.3, 0.1, 1.6), Vector3(-8.4, F + 2.4, 0), "rubber", Color.WHITE, false, 0.5)
	for s in [-1, 1]:
		var lamp := Vector3(-8.32, F + 2.3, s * 1.9)
		A.box(self, Vector3(0.12, 0.2, 0.16), lamp, "metal", FRAME, false)
		A.glow(self, Vector3(0.02, 0.12, 0.1), lamp + Vector3(-0.07, 0, 0), Color(1, 0.12, 0.08), 3.0)
	for k in 8:
		A.box(self, Vector3(0.04, 0.04, 0.45), Vector3(-8.33, 0.55 + k * 0.35, -1.55), "metal", RAIL, false)
	for dz in [-1.33, -1.77]:
		A.box(self, Vector3(0.04, 3.0, 0.04), Vector3(-8.33, 1.7, dz), "metal", RAIL, false)
	_bogie(self, -4.9, 2, 1.3)
	_bogie(self, 4.9, 2, 1.3)


func _glass(pos: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = A.glass()
	add_child(mi)
	mi.position = pos


# --- interior -------------------------------------------------------------------------

func _interior(open_terminal: Callable, rng: RandomNumberGenerator) -> void:
	# Terminal desk against the back wall, front section.
	var desk := StaticBody3D.new()
	add_child(desk)
	desk.position = Vector3(6.5, F, -1.55)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.2, 0.8, 0.85)
	cs.shape = sh
	cs.position.y = 0.4
	desk.add_child(cs)
	A.box(desk, Vector3(2.2, 0.07, 0.85), Vector3(0, 0.78, 0), "wood", Color.WHITE, false, 1.0)
	for sx in [-1, 1]:
		A.box(desk, Vector3(0.06, 0.75, 0.8), Vector3(sx * 1.05, 0.37, 0), "wood", Color(0.7, 0.7, 0.7), false, 1.0)
	var mon := Node3D.new()
	desk.add_child(mon)
	mon.position = Vector3(-0.35, 0.81, -0.05)
	mon.rotation.y = PI
	A.crt(mon, Vector3.ZERO, true)
	B.interactable(self, Vector3(0.44, 0.33, 0.03), Vector3(6.15, F + 1.06, -1.33), Color(0, 0, 0, 0), "Use terminal", open_terminal)
	var mon2 := Node3D.new()
	desk.add_child(mon2)
	mon2.position = Vector3(0.6, 0.81, -0.05)
	mon2.rotation.y = PI
	A.crt(mon2, Vector3.ZERO, true, Color(0.25, 0.12, 0.04))
	market_label = Label3D.new()
	market_label.font_size = 32
	market_label.pixel_size = 0.0011
	market_label.modulate = Color(1, 0.65, 0.25)
	market_label.outline_size = 0
	add_child(market_label)
	market_label.position = Vector3(7.1, F + 1.06, -1.32)
	# Clock, chalkboard, charger, control panel, horn lever.
	A.box(self, Vector3(1.1, 0.32, 0.05), Vector3(6.5, F + 2.05, -1.99), "metal", Color(0.15, 0.15, 0.15), false)
	clock_label = Label3D.new()
	clock_label.font_size = 64
	clock_label.pixel_size = 0.004
	clock_label.modulate = Color(1, 0.5, 0.15)
	clock_label.outline_size = 0
	add_child(clock_label)
	clock_label.position = Vector3(6.5, F + 2.05, -1.96)
	A.box(self, Vector3(1.9, 1.15, 0.05), Vector3(3.6, F + 1.6, -1.99), "wood", Color.WHITE, false, 1.0)
	A.box(self, Vector3(1.75, 1.0, 0.02), Vector3(3.6, F + 1.6, -1.96), "board", Color.WHITE, false)
	var chalk := B.label(self, "BUREAU OF RECLAIMED MATERIALS\n\n- store scrap in the cargo end\n- train leaves at 24:00 sharp\n- do NOT look at the mannequins\n\nquota is quota.", Vector3(3.6, F + 1.6, -1.94), 40, Color(0.9, 0.92, 0.85), "chalk", 0.0022)
	A.box(self, Vector3(0.6, 0.35, 0.22), Vector3(2.0, F + 1.3, -1.9), "metal", Color(0.4, 0.42, 0.4), false)
	for i in 4:
		A.glow(self, Vector3(0.08, 0.05, 0.02), Vector3(1.8 + i * 0.13, F + 1.38, -1.78), Color(0.2, 1, 0.3), 3.0)
	var panel := A.box(self, Vector3(0.35, 1.0, 1.7), Vector3(7.95, F + 1.2, 0.6), "metal", Color(0.45, 0.48, 0.45))
	for i in 3:
		A.cyl(panel, 0.11, 0.03, Vector3(-0.19, 0.25, -0.5 + i * 0.4), "cream", Color(0.9, 0.9, 0.85), false, "x")
	B.interactable(self, Vector3(0.08, 0.5, 0.08), Vector3(7.7, F + 1.05, 1.2), Color(0.8, 0.1, 0.1), "Pull horn",
		func(): Sfx.play(self, "horn", Vector3(12, 4, 0), 0.0), 0.0, 0.3)
	A.cyl(self, 0.22, 0.6, Vector3(6.2, F + 0.3, -0.4), "metal", Color(0.4, 0.3, 0.25), true)
	A.locker(self, Vector3(7.65, F, -0.6), PI / 2)
	# Lighting: caged ceiling lamps, one hanging lamp in the cargo end.
	for x in [-5.0, 0.5, 5.5]:
		A.sphere(self, 0.12, Vector3(x, F + 2.55, 0), "cream", Color(1, 0.8, 0.5), 5.0)
		for a in 4:
			var bar := A.box(self, Vector3(0.02, 0.25, 0.02), Vector3(x, F + 2.55, 0) + Vector3(0.14, 0, 0).rotated(Vector3.UP, a * PI / 2), "metal", Color(0.3, 0.3, 0.3), false)
			bar.rotation.y = a * PI / 2
		B.omni(self, Vector3(x, F + 2.2, 0), Color(1, 0.75, 0.5), 1.0, 7.5)
	A.hanging_lamp(self, Vector3(-2.8, F + 2.65, 0.5), Color(1, 0.75, 0.45), 0.6, 0.9, false)
	# Cargo end: shelving, crates, barrel, bench.
	for x in [-6.6, -4.2, -1.8]:
		A.shelf_unit(self, Vector3(x, F, -1.72), 0.0, rng, 2.25, 2.2, 0.5)
	var scrap_sign := B.label(self, "STORE SCRAP HERE", Vector3(-4.2, F + 2.45, -1.97), 40, Color(0.95, 0.9, 0.75), "stencil", 0.004)
	A.crate(self, Vector3(-7.5, F, 1.5), 0.75, rng)
	A.crate(self, Vector3(-7.45, F + 0.75, 1.5), 0.5, rng, false)
	A.barrel(self, Vector3(-7.5, F, 0.55), rng)
	A.box(self, Vector3(1.8, 0.45, 0.45), Vector3(-0.8, F + 0.225, 1.72), "wood", Color.WHITE, true, 1.0)


# --- locomotive -----------------------------------------------------------------------------
# Road-switcher layout: long hood behind the cab (radiators + fans at the back end, exhaust stack,
# dynamic-brake blister), the cab, a short nose with headlights, walkways with yellow handrails
# all round, three-axle trucks with traction motors, a fuel tank slung between them, a V plow.

func _locomotive() -> void:
	var body := Color(0.82, 0.52, 0.18)   # for trim tints
	var maroon := Color(0.55, 0.42, 0.4)
	var x0 := 8.35
	var x1 := 17.25
	var xc := (x0 + x1) / 2.0
	# Frame, deck plate, sill with hazard edge.
	A.box(self, Vector3(x1 - x0, 0.35, 3.0), Vector3(xc, 0.75, 0), "metal", FRAME, true, 1.0)
	A.box(self, Vector3(x1 - x0, 0.08, 3.1), Vector3(xc, F - 0.04, 0), "riveted", Color(0.45, 0.43, 0.4), true, 1.0)
	for s in [-1, 1]:
		A.box(self, Vector3(x1 - x0, 0.3, 0.06), Vector3(xc, 0.82, s * 1.55), "maroon", Color.WHITE, false, 1.5)
		A.box(self, Vector3(x1 - x0, 0.08, 0.065), Vector3(xc, 0.62, s * 1.56), "hazard", Color.WHITE, false, 0.5)
		var num := B.label(self, "B.R.M.", Vector3(11.0, 0.84, s * 1.59), 60, CREAM, "stencil", 0.006)
		num.rotation.y = 0.0 if s > 0 else PI
	A.box(self, Vector3(0.3, 0.12, 2.4), Vector3(8.2, F - 0.06, 0), "riveted", Color(0.4, 0.4, 0.4), false)   # bridge plate to the car
	# --- long hood ---
	var h0 := 8.75
	var h1 := 13.55
	var hc := (h0 + h1) / 2.0
	var hl := h1 - h0
	A.box(self, Vector3(hl, 2.05, 1.9), Vector3(hc, F + 1.03, 0), "loco", Color.WHITE, true, 2.0)
	A.box(self, Vector3(hl, 0.22, 1.5), Vector3(hc, F + 2.17, 0), "loco", Color.WHITE, false, 2.0)
	for s in [-1, 1]:
		A.cyl(self, 0.22, hl, Vector3(hc, F + 2.05, s * 0.73), "loco", Color.WHITE, false, "x")
		var z: float = s * 0.955
		# Access doors: panel seams, louvres, latches.
		for k in 5:
			var dx := h0 + 0.5 + k * 0.95
			A.box(self, Vector3(0.03, 1.75, 0.02), Vector3(dx, F + 1.0, z), "metal", FRAME, false)
			if k < 4:
				A.box(self, Vector3(0.08, 0.05, 0.04), Vector3(dx + 0.85, F + 1.25, z + s * 0.01), "metal", Color(0.75, 0.75, 0.72), false)
				A.box(self, Vector3(0.06, 0.04, 0.03), Vector3(dx + 0.12, F + 1.65, z), "metal", FRAME, false)
				A.box(self, Vector3(0.06, 0.04, 0.03), Vector3(dx + 0.12, F + 0.35, z), "metal", FRAME, false)
		A.box(self, Vector3(hl, 0.03, 0.02), Vector3(hc, F + 1.9, z), "metal", FRAME, false)
		# Radiator intakes at the back end, air filter louvres up front.
		A.box(self, Vector3(1.6, 1.15, 0.03), Vector3(h0 + 0.95, F + 1.25, z + s * 0.005), "grille", Color.WHITE, false, 0.3)
		A.box(self, Vector3(1.7, 1.25, 0.02), Vector3(h0 + 0.95, F + 1.25, z), "metal", FRAME, false)
		for k in 6:
			A.box(self, Vector3(0.7, 0.04, 0.05), Vector3(h1 - 0.7, F + 0.6 + k * 0.15, z + s * 0.02), "metal", body.darkened(0.3), false, 0.3, Vector3(0.5 * s, 0, 0))
		var tag := B.label(self, "BRM 07", Vector3(hc + 0.4, F + 1.45, z + s * 0.02), 90, Color(0.3, 0.08, 0.06), "stencil", 0.007)
		tag.rotation.y = 0.0 if s > 0 else PI
		var warn := B.label(self, "DANGER  600V", Vector3(h0 + 2.6, F + 0.35, z + s * 0.02), 30, Color(0.1, 0.08, 0.06), "stencil", 0.005)
		warn.rotation.y = 0.0 if s > 0 else PI
	# Roof: two big radiator fans in a grille deck, the exhaust stack, the dynamic brake blister.
	A.box(self, Vector3(2.0, 0.12, 1.55), Vector3(h0 + 1.05, F + 2.33, 0), "metal", body.darkened(0.2), false)
	for fx in [h0 + 0.55, h0 + 1.55]:
		A.cyl(self, 0.44, 0.06, Vector3(fx, F + 2.41, 0), "grille", Color.WHITE)
		A.ring(self, 0.46, 0.4, Vector3(fx, F + 2.42, 0), "metal", FRAME)
		var fan := Node3D.new()
		add_child(fan)
		fan.position = Vector3(fx, F + 2.37, 0)
		for k in 4:
			A.box(fan, Vector3(0.8, 0.02, 0.13), Vector3.ZERO, "metal", Color(0.25, 0.25, 0.25), false, 0.3, Vector3(0.25, k * PI / 4, 0))
		A.spin(fan, "y", 0.6 + fx * 0.01)
	A.box(self, Vector3(1.5, 0.35, 1.3), Vector3(h0 + 3.1, F + 2.42, 0), "loco", Color.WHITE.darkened(0.08), false, 1.5)
	for s in [-1, 1]:
		A.box(self, Vector3(1.2, 0.22, 0.02), Vector3(h0 + 3.1, F + 2.42, s * 0.66), "grille", Color.WHITE, false, 0.2)
	A.box(self, Vector3(0.6, 0.12, 0.4), Vector3(11.6, F + 2.33, 0), "metal", FRAME, false)
	A.cyl(self, 0.16, 0.5, Vector3(11.6, F + 2.6, 0), "rust", Color(0.55, 0.5, 0.48))   # exhaust stack
	A.cyl(self, 0.19, 0.06, Vector3(11.6, F + 2.86, 0), "rust", Color(0.35, 0.3, 0.28))
	A.cyl(self, 0.09, 0.2, Vector3(12.9, F + 2.37, 0.35), "metal", Color(0.6, 0.6, 0.6))   # sand filler
	A.sphere(self, 0.13, Vector3(12.9, F + 2.35, -0.4), "brass", Color.WHITE, 0.0, 0.8)   # bell
	for lx in [h0 + 0.2, h1 - 0.2]:
		A.ring(self, 0.06, 0.035, Vector3(lx, F + 2.32, 0), "metal", FRAME, Vector3(PI / 2, 0, 0))   # lift rings
	# --- cab ---
	var c0 := 13.6
	var c1 := 15.95
	var ccx := (c0 + c1) / 2.0
	var ch := 2.75
	A.box(self, Vector3(c1 - c0, ch, 2.7), Vector3(ccx, F + ch / 2, 0), "loco", Color.WHITE, true, 2.0)
	A.box(self, Vector3(c1 - c0, 0.3, 2.7), Vector3(ccx, F + 0.15, 0), "maroon", Color.WHITE, false, 1.5)
	var roof := A.box(self, Vector3(c1 - c0 + 0.3, 0.12, 2.95), Vector3(ccx, F + ch + 0.06, 0), "maroon", Color.WHITE, false, 1.5)
	for s in [-1, 1]:
		A.cyl(self, 0.08, c1 - c0 + 0.3, Vector3(ccx, F + ch + 0.02, s * 1.42), "maroon", Color.WHITE, false, "x")
		var z: float = s * 1.355
		# Two side windows (one slid half open), framed, with an armrest and grab irons.
		for k in 2:
			var wx := c0 + 0.6 + k * 1.05
			A.box(self, Vector3(0.82, 0.72, 0.02), Vector3(wx, F + 2.0, z + s * 0.005), "metal", Color(0.06, 0.07, 0.08), false)
			var g = A.box(self, Vector3(0.78, 0.68, 0.01), Vector3(wx + (0.2 if k == 1 else 0.0), F + 2.0, z + s * 0.02), "metal", Color.WHITE, false)
			g.material_override = A.glass()
			for e in [-1, 1]:
				A.box(self, Vector3(0.05, 0.8, 0.05), Vector3(wx + e * 0.43, F + 2.0, z + s * 0.02), "metal", FRAME, false)
			A.box(self, Vector3(0.9, 0.05, 0.06), Vector3(wx, F + 1.6, z + s * 0.03), "metal", FRAME, false)
			A.box(self, Vector3(0.9, 0.05, 0.06), Vector3(wx, F + 2.4, z + s * 0.03), "metal", FRAME, false)
		A.box(self, Vector3(0.8, 0.07, 0.12), Vector3(c0 + 0.6, F + 1.62, z + s * 0.07), "metal", FRAME, false)   # armrest
		for gx in [c0 + 0.08, c1 - 0.08]:
			A.seg(self, Vector3(gx, F + 0.4, z + s * 0.06), Vector3(gx, F + 1.9, z + s * 0.06), 0.022, 0.022, "metal", RAIL)
		A.box(self, Vector3(0.5, 0.3, 0.02), Vector3(c0 + 1.15, F + 1.05, z + s * 0.005), "metal", FRAME, false)
		var cab_num := B.label(self, "07", Vector3(c0 + 1.15, F + 1.05, z + s * 0.02), 80, Color(0.3, 0.08, 0.06), "stencil", 0.0045)
		cab_num.rotation.y = 0.0 if s > 0 else PI
		A.box(self, Vector3(0.12, 0.2, 0.15), Vector3(c1 + 0.05, F + ch - 0.25, s * 1.2), "metal", FRAME, false)   # class lights
		A.glow(self, Vector3(0.02, 0.1, 0.1), Vector3(c1 + 0.12, F + ch - 0.25, s * 1.2), Color(0.95, 0.95, 0.85), 2.0)
	# Front and rear windows, sun visors, wipers, number board.
	for e in [[c1, 1.0], [c0, -1.0]]:
		var ex: float = e[0] + e[1] * 0.005
		for wz in [-0.62, 0.62]:
			A.box(self, Vector3(0.02, 0.7, 0.95), Vector3(ex, F + 2.05, wz), "metal", Color(0.06, 0.07, 0.08), false)
			var g = A.box(self, Vector3(0.01, 0.66, 0.9), Vector3(ex + e[1] * 0.01, F + 2.05, wz), "metal", Color.WHITE, false)
			g.material_override = A.glass()
			A.box(self, Vector3(0.05, 0.78, 1.03), Vector3(ex + e[1] * 0.015, F + 2.05, wz), "metal", FRAME, false).scale = Vector3(1, 1, 1)
			if e[1] > 0.0:
				A.box(self, Vector3(0.3, 0.03, 0.9), Vector3(ex + 0.15, F + 2.45, wz), "metal", FRAME, false, 1.0, Vector3(0, 0, -0.2))
				A.seg(self, Vector3(ex + 0.03, F + 1.72, wz), Vector3(ex + 0.03, F + 2.25, wz + 0.3), 0.012, 0.012, "metal", Color(0.1, 0.1, 0.1))
	A.box(self, Vector3(0.05, 0.22, 0.7), Vector3(c1 + 0.03, F + ch - 0.2, 0), "metal", Color(0.05, 0.05, 0.05), false)
	A.glow(self, Vector3(0.02, 0.18, 0.66), Vector3(c1 + 0.06, F + ch - 0.2, 0), Color(0.95, 0.9, 0.75), 1.2)
	var nb := B.display(self, "07", Vector3(c1 + 0.075, F + ch - 0.2, 0), 64, Color(0.1, 0.08, 0.06))
	nb.rotation.y = PI / 2
	nb.pixel_size = 0.0028
	# Roof gear: three-chime horn, antenna, amber beacon.
	for k in 3:
		A.seg(self, Vector3(ccx - 0.2 + k * 0.18, F + ch + 0.12, -0.6), Vector3(ccx - 0.2 + k * 0.18 + (0.25 if k == 1 else -0.25), F + ch + 0.22, -0.6), 0.03, 0.09, "metal", Color(0.65, 0.65, 0.62))
	A.seg(self, Vector3(ccx + 0.4, F + ch + 0.12, 0.5), Vector3(ccx + 0.4, F + ch + 0.9, 0.5), 0.012, 0.006, "metal", Color(0.3, 0.3, 0.3))
	var beacon := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.1
	bm.height = 0.2
	bm.is_hemisphere = true
	beacon.mesh = bm
	add_child(beacon)
	beacon.position = Vector3(ccx - 0.4, F + ch + 0.12, 0.3)
	Merge.live(beacon)
	var tw := beacon.create_tween().set_loops()
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1, 0.6, 0.1)
	bmat.emission_enabled = true
	bmat.emission = Color(1, 0.55, 0.1)
	beacon.material_override = bmat
	tw.tween_property(bmat, "emission_energy_multiplier", 5.0, 0.5)
	tw.tween_property(bmat, "emission_energy_multiplier", 0.2, 0.5)
	# --- short nose with twin headlights ---
	var n0 := c1
	var n1 := 16.85
	A.box(self, Vector3(n1 - n0, 1.3, 1.7), Vector3((n0 + n1) / 2, F + 0.65, 0), "loco", Color.WHITE, true, 2.0)
	var nose_top := A.box(self, Vector3(n1 - n0 + 0.05, 0.08, 1.7), Vector3((n0 + n1) / 2 + 0.03, F + 1.36, 0), "loco", Color.WHITE.darkened(0.1), false, 2.0)
	nose_top.rotation.z = -0.12
	for s in [-1, 1]:
		A.box(self, Vector3(n1 - n0, 1.3, 0.02), Vector3((n0 + n1) / 2, F + 0.65, s * 0.86), "metal", FRAME, false).scale = Vector3(1, 1, 1)
	A.box(self, Vector3(0.05, 1.0, 0.6), Vector3(n1 + 0.02, F + 0.6, 0), "metal", body.darkened(0.15), false)   # nose door
	A.box(self, Vector3(0.06, 0.06, 0.15), Vector3(n1 + 0.05, F + 0.6, 0.2), "metal", Color(0.75, 0.75, 0.72), false)
	for hz in [-0.55, 0.55]:
		A.cyl(self, 0.15, 0.12, Vector3(n1 + 0.04, F + 1.05, hz), "metal", FRAME, false, "x")
		A.glow(self, Vector3(0.03, 0.2, 0.2), Vector3(n1 + 0.1, F + 1.05, hz), Color(1, 0.88, 0.6), 6.0)
		A.box(self, Vector3(0.15, 0.04, 0.32), Vector3(n1 + 0.1, F + 1.2, hz), "metal", FRAME, false)
	headlight = SpotLight3D.new()
	headlight.light_color = Color(1, 0.85, 0.6)
	headlight.light_energy = 5.0
	headlight.spot_range = 60.0
	headlight.spot_angle = 18.0
	headlight.light_volumetric_fog_energy = 2.0
	add_child(headlight)
	headlight.position = Vector3(n1 + 0.2, F + 1.05, 0)
	headlight.rotation = Vector3(-0.05, -PI / 2, 0)
	# --- walkway handrails (yellow), end railings, steps at every corner ---
	for s in [-1, 1]:
		var z: float = s * 1.45
		var posts := [8.55, 9.7, 10.85, 12.0, 13.15, 14.0, 15.95, 16.9, 17.15]
		for px in posts:
			if px > c0 and px < c1:
				continue
			A.seg(self, Vector3(px, F, z), Vector3(px, F + 1.0, z), 0.022, 0.022, "metal", RAIL)
		for seg in [[8.55, 13.6], [15.95, 17.15]]:
			for y in [1.0, 0.55]:
				A.seg(self, Vector3(seg[0], F + y, z), Vector3(seg[1], F + y, z), 0.02, 0.02, "metal", RAIL)
		A.box(self, Vector3(0.3, 0.02, 0.06), Vector3(13.4, F + 0.02, z), "hazard", Color.WHITE, false)
		_steps(self, 8.7, s * 1.62, 0.6)
		_steps(self, 16.95, s * 1.62, 0.6)
		A.seg(self, Vector3(8.4, F, s * 1.45), Vector3(8.4, F + 1.0, s * 1.45), 0.02, 0.02, "metal", RAIL)
	for y in [1.0, 0.55]:   # front rail across the pilot
		A.seg(self, Vector3(17.15, F + y, -1.45), Vector3(17.15, F + y, 1.45), 0.02, 0.02, "metal", RAIL)
	# --- pilot, plow, ditch lights, coupler ---
	A.box(self, Vector3(0.25, 0.55, 3.0), Vector3(x1 + 0.02, 0.72, 0), "hazard", Color.WHITE, true, 0.8)
	for s in [-1, 1]:
		var blade := A.box(self, Vector3(1.6, 0.6, 0.08), Vector3(x1 + 0.38, 0.38, s * 0.72), "plow", Color(0.9, 0.85, 0.8), false, 1.0)
		blade.rotation.y = s * 0.45
		for k in 3:   # ribs behind the blade
			var rib := A.box(self, Vector3(0.05, 0.55, 0.25), Vector3(x1 + 0.12 + k * 0.22, 0.38, s * (1.25 - k * 0.42)), "metal", FRAME, false)
			rib.rotation.y = s * 0.45
		var lip := A.box(self, Vector3(1.6, 0.06, 0.12), Vector3(x1 + 0.4, 0.1, s * 0.75), "metal", Color(0.3, 0.3, 0.3), false)
		lip.rotation.y = s * 0.45
		A.box(self, Vector3(0.14, 0.14, 0.14), Vector3(x1 + 0.12, F + 0.35, s * 1.2), "metal", FRAME, false)
		A.glow(self, Vector3(0.02, 0.1, 0.1), Vector3(x1 + 0.2, F + 0.35, s * 1.2), Color(1, 0.9, 0.65), 4.0)
	_coupler(self, x1 + 0.1, 1.0)
	_coupler(self, x0 - 0.05, -1.0)
	# --- fuel tank, air reservoirs, trucks ---
	A.box(self, Vector3(3.0, 0.5, 2.1), Vector3(12.55, 0.4, 0), "metal", Color(0.28, 0.28, 0.3), false, 1.0)
	for s in [-1, 1]:
		A.cyl(self, 0.28, 3.0, Vector3(12.55, 0.32, s * 0.78), "metal", Color(0.28, 0.28, 0.3), false, "x")
		A.cyl(self, 0.16, 2.6, Vector3(12.55, 0.45, s * 1.3), "metal", Color(0.4, 0.4, 0.42), false, "x")
	A.cyl(self, 0.1, 0.05, Vector3(12.0, 0.45, 1.06), "paper", Color(0.9, 0.9, 0.85), false, "z")
	A.ring(self, 0.11, 0.09, Vector3(12.0, 0.45, 1.08), "metal", Color(0.6, 0.6, 0.6), Vector3(PI / 2, 0, 0))
	A.cyl(self, 0.08, 0.12, Vector3(13.2, 0.62, 1.1), "metal", Color(0.75, 0.15, 0.1), false, "z")
	var fuel := B.label(self, "FUEL", Vector3(12.6, 0.4, 1.06), 40, CREAM, "stencil", 0.005)
	_bogie(self, 9.75, 3, 1.05, 0.45, true)
	_bogie(self, 15.6, 3, 1.05, 0.45, true)
	# Exhaust.
	_steam = GPUParticles3D.new()
	_steam.amount = 90
	_steam.lifetime = 3.5
	_steam.local_coords = false
	_steam.visibility_aabb = AABB(Vector3(-40, -5, -10), Vector3(60, 25, 20))
	_steam_mat = ParticleProcessMaterial.new()
	_steam_mat.direction = Vector3(0, 1, 0)
	_steam_mat.spread = 12.0
	_steam_mat.initial_velocity_min = 2.0
	_steam_mat.initial_velocity_max = 3.5
	_steam_mat.scale_min = 0.6
	_steam_mat.scale_max = 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 2.5))
	var gt := CurveTexture.new()
	gt.curve = grow
	_steam_mat.scale_curve = gt
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.5))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	_steam_mat.color_ramp = ft
	_steam.process_material = _steam_mat
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	var sm := StandardMaterial3D.new()
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(0.3, 0.28, 0.27)
	quad.material = sm
	_steam.draw_pass_1 = quad
	add_child(_steam)
	_steam.position = Vector3(11.6, F + 2.9, 0)


# --- flatcar -------------------------------------------------------------------------------

func _flatcar(rng: RandomNumberGenerator) -> void:
	_flat = Node3D.new()
	add_child(_flat)
	var x0 := -15.5
	var x1 := -8.7
	var xc := (x0 + x1) / 2.0
	var len := x1 - x0
	# Plank deck on a fishbelly frame, stake pockets along the sides.
	for k in 14:
		A.box(_flat, Vector3(len, 0.08, 0.19), Vector3(xc, 1.01, -1.3 + k * 0.2), "wood", Color.WHITE.darkened(rng.randf() * 0.25), k == 0, 1.0)
	A.box(_flat, Vector3(len, 0.08, 2.8), Vector3(xc, 0.97, 0), "wood", Color(0.5, 0.45, 0.4), true, 1.5)
	A.box(_flat, Vector3(len + 0.2, 0.3, 2.3), Vector3(xc, 0.75, 0), "metal", FRAME, false, 1.0)
	for s in [-1, 1]:
		A.box(_flat, Vector3(len, 0.22, 0.1), Vector3(xc, 0.86, s * 1.42), "rust", Color(0.75, 0.7, 0.68), false, 1.0)
		A.box(_flat, Vector3(3.0, 0.3, 0.1), Vector3(xc, 0.6, s * 1.35), "rust", Color(0.7, 0.65, 0.62), false, 1.0)
		for e in [-1, 1]:
			var taper := A.box(_flat, Vector3(1.1, 0.12, 0.1), Vector3(xc + e * 2.0, 0.66, s * 1.35), "rust", Color(0.7, 0.65, 0.62), false, 1.0)
			taper.rotation.z = e * 0.28
		for k in 6:
			var px := x0 + 0.5 + k * (len - 1.0) / 5.0
			A.box(_flat, Vector3(0.12, 0.18, 0.1), Vector3(px, 0.85, s * 1.5), "metal", FRAME, false)
			if k % 2 == 0 and not (s < 0 and k == 0):
				A.box(_flat, Vector3(0.09, 1.1, 0.09), Vector3(px, 1.4, s * 1.48), "wood", Color(0.6, 0.5, 0.42), false, 0.5)
		var tag := B.label(_flat, "BRM 4413", Vector3(xc + 2.2, 0.86, s * 1.48), 40, CREAM, "stencil", 0.006)
		tag.rotation.y = 0.0 if s > 0 else PI
	# Load: crates under ratchet straps, barrels, and a big tarp-covered lump roped down.
	A.crate(_flat, Vector3(-9.8, 1.05, 0.65), 1.0, rng)
	A.crate(_flat, Vector3(-10.9, 1.05, 0.55), 0.8, rng)
	A.crate(_flat, Vector3(-10.0, 2.05, 0.6), 0.6, rng, false)
	for sx in [-9.8, -10.9]:
		A.box(_flat, Vector3(0.06, 0.02, 2.6), Vector3(sx, 2.07 if sx > -10.0 else 1.87, 0), "canvas", Color(0.85, 0.65, 0.15), false, 0.3)
		for s in [-1, 1]:
			A.box(_flat, Vector3(0.06, 1.0, 0.02), Vector3(sx, 1.55, s * 1.3), "canvas", Color(0.85, 0.65, 0.15), false, 0.3)
	A.barrel(_flat, Vector3(-9.9, 1.05, -0.8), rng)
	A.barrel(_flat, Vector3(-10.6, 1.05, -0.9), rng)
	var tarp := A.sphere(_flat, 1.0, Vector3(-13.2, 1.2, 0), "canvas", Color(0.45, 0.5, 0.38), 0.0, 1.0)
	tarp.scale = Vector3(1.8, 0.85, 1.25)
	A.box(_flat, Vector3(3.4, 0.3, 2.5), Vector3(-13.2, 1.18, 0), "canvas", Color(0.42, 0.47, 0.36), false, 0.6)
	for rx in [-14.4, -13.6, -12.8, -12.0]:   # ropes over the tarp, following its curve
		var prev := Vector3(rx, 1.06, 1.32)
		for k in range(1, 9):
			var a := PI * k / 8.0
			var pt := Vector3(rx, 1.2 + sin(a) * 0.88, cos(a) * 1.3)
			A.seg(_flat, prev, pt, 0.018, 0.018, "canvas", Color(0.75, 0.68, 0.5))
			prev = pt
	A.box(_flat, Vector3(3.4, 1.4, 2.4), Vector3(-13.2, 1.7, 0), "canvas", Color.WHITE, true).visible = false   # its collision
	# Brake wheel on a staff at the back end, end sills, couplers, trucks.
	A.seg(_flat, Vector3(x0 + 0.2, 0.9, 1.0), Vector3(x0 + 0.2, 1.9, 1.0), 0.03, 0.03, "metal", FRAME)
	A.ring(_flat, 0.25, 0.22, Vector3(x0 + 0.24, 1.95, 1.0), "metal", Color(0.4, 0.4, 0.4), Vector3(0, 0, PI / 2))
	for k in 3:
		A.box(_flat, Vector3(0.03, 0.46, 0.03), Vector3(x0 + 0.24, 1.95, 1.0), "metal", Color(0.4, 0.4, 0.4), false, 1.0, Vector3(k * PI / 3, 0, 0))
	for e in [x0, x1]:
		A.box(_flat, Vector3(0.15, 0.35, 2.8), Vector3(e, 0.82, 0), "metal", FRAME, false)
		A.box(_flat, Vector3(0.16, 0.08, 2.8), Vector3(e, 0.62, 0), "hazard", Color.WHITE, false, 0.5)
	_coupler(_flat, x0 - 0.1, -1.0)
	_coupler(_flat, x1 + 0.05, 1.0)
	_bogie(_flat, -10.0, 2, 1.3)
	_bogie(_flat, -14.2, 2, 1.3)


# --- upgrades / deliveries -----------------------------------------------------------

## STORAGE_CAR upgrade: a second walk-in car behind the crew car; the flatcar moves back.
func add_storage_car() -> void:
	if has_storage:
		return
	has_storage = true
	_rear_lock.queue_free()
	_flat.position.x -= CAR_LEN
	var x0 := -8.3 - CAR_LEN
	var x1 := -8.3
	var xc := (x0 + x1) / 2.0
	var root := Node3D.new()
	add_child(root)
	var paint := Color(0.78, 0.6, 0.48)
	var door := [[xc + 2.0, 1.5, 0.0, 2.3]]
	var wins := [[xc - 3.5, 1.0, 1.0, 2.0], [xc + 4.5, 1.0, 1.0, 2.0]]
	A.wall(root, x0, x1, 2.18, WALL_H, 0.08, door + wins, "corrugated", paint, true, F, true, 1.2)
	A.wall(root, x0, x1, 2.06, WALL_H, 0.08, door + wins, "red_wall", Color.WHITE, true, F, false, 1.0)
	A.wall(root, x0, x1, -2.18, WALL_H, 0.08, [], "corrugated", paint, true, F, true, 1.2)
	A.wall(root, x0, x1, -2.06, WALL_H, 0.08, [], "red_wall", Color.WHITE, true, F, false, 1.0)
	A.wall(root, -2.2, 2.2, x0, WALL_H, 0.15, [], "corrugated", paint, false, F, true, 1.2)
	A.wall(root, -2.2, 2.2, x1 + 0.05, WALL_H, 0.15, [[0.0, 1.2, 0.0, 2.3]], "corrugated", paint, false, F, true, 1.2)
	for w in wins:
		_glass_at(root, Vector3(w[0], F + 1.5, 2.12), Vector3(w[1], 1.0, 0.02))
	A.box(root, Vector3(CAR_LEN, 0.12, 4.2), Vector3(xc, F - 0.06, 0), "wood", Color(0.85, 0.8, 0.75), true, 1.5)
	A.box(root, Vector3(CAR_LEN + 0.4, 0.35, 3.4), Vector3(xc, 0.7, 0), "rust", Color(0.6, 0.6, 0.6), true)
	A.box(root, Vector3(CAR_LEN, 0.08, 4.4), Vector3(xc, F + 2.74, 0), "metal", Color(0.5, 0.45, 0.42), true)
	for i in 6:
		A.box(root, Vector3(0.1, 0.12, 4.1), Vector3(x0 + 0.5 + i * 2.2, F + WALL_H - 0.06, 0), "rust", Color.WHITE, false, 1.0)
	_car_dress(root, x0, x1, door, wins, [], "RECLAIMED MATERIALS  -  STORAGE", "BRM 311", [xc + 0.4], "corrugated", paint)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# Inside: racks along the back wall, tie-down rails, a cargo net, pallets, work lamps.
	for i in 4:
		A.shelf_unit(root, Vector3(x0 + 1.6 + i * 2.6, F, -1.72), 0.0, rng, 2.4, 2.3, 0.5)
	for y in [F + 0.4, F + 1.4]:
		A.box(root, Vector3(CAR_LEN - 0.6, 0.06, 0.04), Vector3(xc, y, 2.0), "metal", Color(0.55, 0.55, 0.52), false)
	for k in 5:
		A.ring(root, 0.05, 0.03, Vector3(x0 + 1.0 + k * 2.6, F + 0.4, 1.97), "metal", Color(0.6, 0.6, 0.6), Vector3(PI / 2, 0, 0))
	for k in 6:   # cargo net across the end
		A.box(root, Vector3(0.02, 2.0, 0.02), Vector3(x0 + 0.35, F + 1.1, -1.5 + k * 0.6), "canvas", Color(0.7, 0.6, 0.35), false, 0.2)
		A.box(root, Vector3(0.02, 0.02, 3.2), Vector3(x0 + 0.35, F + 0.2 + k * 0.38, 0), "canvas", Color(0.7, 0.6, 0.35), false, 0.2)
	A.pallet(root, Vector3(xc - 1.5, F, 0.9))
	A.pallet(root, Vector3(xc + 4.0, F, 0.9))
	var cargo_sign := B.label(root, "CARGO", Vector3(xc, F + 2.45, -1.97), 48, Color(0.95, 0.9, 0.75), "stencil", 0.005)
	for x in [xc - 3.0, xc + 3.0]:
		A.sphere(root, 0.12, Vector3(x, F + 2.55, 0), "cream", Color(1, 0.8, 0.5), 5.0)
		B.omni(root, Vector3(x, F + 2.2, 0), Color(1, 0.75, 0.5), 1.0, 7.5)
	for d in door:
		for sgn in [-1, 1]:
			A.box(root, Vector3(0.08, 2.4, 0.06), Vector3(d[0] + sgn * 0.8, F + 1.2, 2.25), "metal", FRAME, false)
			A.cyl(root, 0.025, 1.2, Vector3(d[0] + sgn * 0.95, F + 1.0, 2.36), "metal", RAIL)
	_bogie(root, x0 + 2.4, 2, 1.3)
	_bogie(root, x1 - 2.4, 2, 1.3)
	Merge.bake(root, 8.0)


func _glass_at(parent: Node, pos: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = A.glass()
	parent.add_child(mi)
	mi.position = pos


## The little rail handcar that brings shop orders. Returns it; caller animates position.x.
func make_handcar() -> Node3D:
	var car := Node3D.new()
	add_child(car)
	A.box(car, Vector3(2.4, 0.15, 1.9), Vector3(0, 0.75, 0), "wood", Color.WHITE, true, 1.0)
	A.box(car, Vector3(2.2, 0.25, 1.4), Vector3(0, 0.55, 0), "rust", Color(0.5, 0.5, 0.5), false)
	for x in [-0.8, 0.8]:
		for z in [-0.78, 0.78]:
			_wheel(Vector3(x, 0.35, z), 0.33, car)
	A.box(car, Vector3(0.12, 1.1, 0.12), Vector3(0, 1.35, 0), "metal", Color(0.4, 0.4, 0.4), false)
	var lever := Node3D.new()
	car.add_child(lever)
	lever.position = Vector3(0, 1.9, 0)
	A.box(lever, Vector3(1.8, 0.08, 0.08), Vector3.ZERO, "rust", Color.WHITE, false, 1.0)
	for x in [-0.9, 0.9]:
		A.box(lever, Vector3(0.08, 0.08, 0.8), Vector3(x, 0, 0), "metal", Color(0.6, 0.6, 0.6), false)
	var tw := lever.create_tween().set_loops()
	tw.tween_property(lever, "rotation:z", 0.35, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(lever, "rotation:z", -0.35, 0.5).set_trans(Tween.TRANS_SINE)
	for sgn in [-1, 1]:
		A.railing(car, Vector3(-1.2, 0.82, sgn * 0.95), Vector3(1.2, 0.82, sgn * 0.95), 0.5, "rust")
	A.sphere(car, 0.08, Vector3(1.1, 1.5, 0.8), "cream", Color(1, 0.75, 0.4), 5.0)
	B.omni(car, Vector3(1.1, 1.5, 0.8), Color(1, 0.75, 0.4), 0.8, 5.0)
	return car
