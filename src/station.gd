# A station on the line (level.gd builds one at every stop but the checkpoint): an old country
# station the Bureau still stops at.
#
#   the platform:  a brick face to the track under a stone coping with its white edge and the yellow
#                  line, worn asphalt on top, ramps down at both ends; long enough for the storage car
#   the canopy:    cast-iron columns with brackets, a lattice beam, a tin roof falling back to the
#                  building (sheets missing, rust), a timber valance of pointed boards along its edge;
#                  lamps, hanging name boards and a double-faced clock under it
#   the building:  a brick booking office on the platform's back edge, its floor at platform level:
#                  the booking hall walked straight through (platform door to forecourt door), the
#                  ticket office behind its window to one side, the waiting room to the other
#   round it:      benches, a luggage trolley, fire buckets, the timetable, name boards at both ends,
#                  steps down at the back to a forecourt (where the way to the lift starts), a signal
#                  box past the platform's west end, a water crane at the other
#
# The track runs along x; the platform is on +z (z 2.35..6.5, its top level with the train's floor,
# y = 1.0); the building stands behind it, centred on `sx`.
extends RefCounted

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const P = preload("res://src/props.gd")

const TOP := 1.0           # the platform's top (the train's floor)
const Z0 := 2.35           # its edge to the track
const Z1 := 6.5            # its back edge (the building's front wall)
const X0 := -30.0          # its ends: room for the storage car at the back of the train
const X1 := 21.0
const HW := 9.0            # the building: half its width...
const DEEP := 8.0          # ...its depth back from the platform...
const WALL := 3.7          # ...and its walls' height over the floor
const BRICK := Color(0.66, 0.56, 0.52)   # (the texture is red already: this weathers it)
const STONE := Color(0.8, 0.77, 0.7)
const IRON := Color(0.2, 0.24, 0.22)        # the canopy's paint: railway green gone almost black
const CREAM := Color(0.86, 0.8, 0.64)
const TRIM := Color(0.42, 0.5, 0.4)         # doors and window frames, faded green


## Builds it all into `lv`; returns a spot inside the building for loot.
static func build(lv: Node3D, letter: String, sx: float, rng: RandomNumberGenerator, arctic: bool, mark := Callable()) -> Vector3:
	var title := "STATION %s" % letter
	_platform(lv, sx, rng, arctic)
	_canopy(lv, sx, title, rng, arctic)
	if mark.is_valid():   # (a stop built on the way: a piece a frame)
		await mark.call("station building")
	var inside := _building(lv, sx, title, rng, arctic)
	if mark.is_valid():
		await mark.call("station furniture")
	_furniture(lv, sx, title, rng)
	_forecourt(lv, sx, rng)
	_signal_box(lv, letter, rng, arctic)
	_water_crane(lv, Vector3(X1 + 6.0, 0, -3.1))
	return inside


# --- the platform -----------------------------------------------------------------------------------

static func _platform(lv: Node3D, sx: float, rng: RandomNumberGenerator, arctic: bool) -> void:
	var ln := X1 - X0
	var xc := (X0 + X1) / 2.0
	var zc := (Z0 + Z1) / 2.0
	# The body (solid), faced in brick toward the track and at the back, a stone coping on the edge.
	A.box(lv, Vector3(ln, TOP - 0.06, Z1 - Z0 - 0.3), Vector3(xc, (TOP - 0.06) / 2.0, zc + 0.15), "concrete", Color(0.5, 0.48, 0.45), true, 3.0)
	A.box(lv, Vector3(ln, TOP - 0.1, 0.16), Vector3(xc, (TOP - 0.1) / 2.0, Z0 + 0.2), "brick", BRICK, false, 0.8)
	A.box(lv, Vector3(ln, TOP - 0.06, 0.16), Vector3(xc, (TOP - 0.06) / 2.0, Z1 - 0.08), "brick", BRICK.darkened(0.08), false, 0.8)
	var x := X0 + 2.0
	while x < X1 - 1.0:   # pilasters along the face, a recess of soot between each pair
		A.box(lv, Vector3(0.45, TOP - 0.1, 0.06), Vector3(x, (TOP - 0.1) / 2.0, Z0 + 0.1), "brick", BRICK.darkened(0.12), false, 0.8)
		x += 4.0
	A.box(lv, Vector3(ln + 0.1, 0.12, 0.6), Vector3(xc, TOP - 0.06, Z0 + 0.25), "concrete", STONE, true, 1.0)   # coping, proud of the face
	A.box(lv, Vector3(ln + 0.1, 0.012, 0.1), Vector3(xc, TOP + 0.006, Z0 + 0.06), "cream", Color(0.92, 0.9, 0.84), false, 0.5)   # white edge
	A.box(lv, Vector3(ln, 0.012, 0.09), Vector3(xc, TOP + 0.006, Z0 + 0.82), "cream", Color(0.88, 0.7, 0.18), false, 0.5)   # yellow line
	A.box(lv, Vector3(ln, 0.06, Z1 - Z0 - 0.55), Vector3(xc, TOP - 0.03, (Z0 + 0.55 + Z1) / 2.0), "asphalt", Color(0.8, 0.78, 0.76), false, 3.0)   # the surface
	for k in 14:   # patches and cracks in the asphalt
		var px := rng.randf_range(X0 + 2.0, X1 - 2.0)
		var pz := rng.randf_range(Z0 + 1.2, Z1 - 0.5)
		if rng.randf() < 0.5:
			A.box(lv, Vector3(rng.randf_range(0.6, 2.2), 0.008, rng.randf_range(0.4, 1.2)), Vector3(px, TOP + 0.004, pz), "asphalt", Color(0.55, 0.53, 0.52), false, 2.0, Vector3(0, rng.randf_range(-0.3, 0.3), 0))
		else:
			A.box(lv, Vector3(rng.randf_range(0.8, 2.5), 0.006, 0.03), Vector3(px, TOP + 0.003, pz), "rubber", Color(0.1, 0.1, 0.1), false, 1.0, Vector3(0, rng.randf_range(-0.8, 0.8), 0))
	# Ramps down at the ends, with a rail down their outer side.
	for s in [-1.0, 1.0]:
		var edge: float = X1 if s > 0.0 else X0
		var run := 4.6
		var ang := atan2(TOP, run)
		var ramp := A.box(lv, Vector3(sqrt(run * run + TOP * TOP), 0.2, Z1 - Z0 - 0.3), Vector3(edge + s * run / 2.0, TOP / 2.0 - 0.08, zc + 0.15), "concrete", Color(0.68, 0.65, 0.6), true, 2.0)
		ramp.rotation.z = -s * ang
		A.box(lv, Vector3(0.3, TOP, Z1 - Z0), Vector3(edge, TOP / 2.0 - 0.02, zc), "brick", BRICK.darkened(0.1), false, 0.8)   # the end wall under the coping
		P.railing_slope(lv, Vector3(edge, TOP, Z1 - 0.15), Vector3(s, 0, 0), TOP, run)
		A.lamp_post(lv, Vector3(edge - s * 1.2, TOP, Z1 - 0.5), Color(1.0, 0.78, 0.5)).light_energy = 1.2
	# A low fence along the back edge either side of the building.
	for seg in [[X0 + 0.5, sx - HW - 0.3], [sx + HW + 0.3, X1 - 0.5]]:
		if seg[1] - seg[0] > 1.0:
			_picket(lv, Vector3(seg[0], TOP, Z1 - 0.12), Vector3(seg[1], TOP, Z1 - 0.12), rng)
	if arctic:   # snow blown up against the back of it, and lying at the ends where nobody walks
		for k in 6:
			var px := rng.randf_range(X0 + 1.0, X1 - 1.0)
			if absf(px - sx) < HW + 1.0:
				continue
			var d := A.sphere(lv, 0.5, Vector3(px, TOP + 0.02, Z1 - 0.5), "snow", Color.WHITE, 0.0, 0.25)
			d.scale = Vector3(rng.randf_range(2.0, 4.0), 1.0, rng.randf_range(0.8, 1.4))


## A picket fence: posts, two rails, pointed palings, some missing, a few leaning.
static func _picket(lv: Node3D, a: Vector3, b: Vector3, rng: RandomNumberGenerator) -> void:
	var c := Color(0.75, 0.72, 0.64)
	var d := b - a
	var ln := d.length()
	var mid := (a + b) / 2.0
	for y in [0.35, 0.85]:
		A.box(lv, Vector3(ln, 0.07, 0.04), mid + Vector3(0, y, 0.03), "wood", c.darkened(0.15), false, 1.0)
	var x := 0.0
	while x < ln:
		var p := a + d.normalized() * x
		if fmod(x, 2.4) < 0.17:
			A.box(lv, Vector3(0.1, 1.15, 0.1), p + Vector3(0, 0.575, 0), "wood", c.darkened(0.2), false, 0.6)
		elif rng.randf() > 0.12:
			var lean := rng.randf_range(-0.12, 0.12) if rng.randf() < 0.15 else 0.0
			A.box(lv, Vector3(0.08, 1.0, 0.025), p + Vector3(0, 0.5, 0.06), "wood", c.darkened(rng.randf() * 0.2), false, 0.6, Vector3(0, 0, lean))
		x += 0.17


# --- the canopy -------------------------------------------------------------------------------------

## Over the middle of the platform, from the building's front to just short of the edge.
static func _canopy(lv: Node3D, sx: float, title: String, rng: RandomNumberGenerator, arctic: bool) -> void:
	var c0 := -16.0
	var c1 := 16.0
	var zf := Z0 + 0.35     # the front edge (the valance hangs here)
	var zb := Z1             # the back, against the building / a beam
	var col_z := Z1 - 0.7
	var yb := 4.35           # the roof at the back...
	var yf := 4.7            # ...rising to the front
	# Columns: a base, a fluted shaft, a capital, and a bracket each side curving out under the beam.
	var cols: Array[float] = []
	var x := c0 + 1.0
	while x <= c1 - 0.9:
		if absf(x - sx) > 1.5:   # (clear of the booking hall's door)
			cols.append(x)
		x += 5.0
	for cx in cols:
		A.box(lv, Vector3(0.38, 0.3, 0.38), Vector3(cx, TOP + 0.15, col_z), "metal", IRON, true, 0.5)
		A.cyl(lv, 0.1, yb - TOP - 0.4, Vector3(cx, (TOP + 0.3 + yb - 0.1) / 2.0, col_z), "metal", IRON, true)
		for k in 6:   # flutes
			var a := TAU * k / 6.0
			A.box(lv, Vector3(0.03, yb - TOP - 0.6, 0.03), Vector3(cx + cos(a) * 0.1, (TOP + yb) / 2.0, col_z + sin(a) * 0.1), "metal", IRON.darkened(0.2), false, 0.3)
		A.box(lv, Vector3(0.32, 0.16, 0.32), Vector3(cx, yb - 0.12, col_z), "metal", IRON, false, 0.5)
		# The brackets: toward the track and back, a curl at the root.
		A.seg(lv, Vector3(cx, yb - 1.0, col_z), Vector3(cx, yb + 0.05, col_z - 1.6), 0.035, 0.035, "metal", IRON)
		A.seg(lv, Vector3(cx, yb - 0.6, col_z), Vector3(cx, yb + 0.05, col_z + 0.6), 0.03, 0.03, "metal", IRON)
		A.ring(lv, 0.22, 0.17, Vector3(cx, yb - 0.45, col_z - 0.4), "metal", IRON, Vector3(0, PI / 2.0, PI / 2.0))
		if rng.randf() < 0.5:   # the timetable, a notice or the station's name on a column
			A.box(lv, Vector3(0.02, 0.5, 0.38), Vector3(cx - 0.11, TOP + 1.6, col_z), "paper", Color(0.85, 0.82, 0.7), false, 0.5)
	# The beam the columns carry: a lattice girder along the platform, and the rafters across.
	for y in [yb - 0.05, yb - 0.45]:
		A.box(lv, Vector3(c1 - c0, 0.08, 0.16), Vector3((c0 + c1) / 2.0, y, col_z), "metal", IRON, false, 0.5)
	x = c0 + 0.25
	while x < c1:
		var lat := A.box(lv, Vector3(0.04, 0.55, 0.04), Vector3(x + 0.2, yb - 0.25, col_z), "metal", IRON, false, 0.3)
		lat.rotation.z = 0.7 if int((x - c0) / 0.5) % 2 == 0 else -0.7
		x += 0.5
	var pitch := atan2(yf - yb, zb - zf)
	var span := (zb - zf) / cos(pitch)
	x = c0
	while x < c1 + 0.01:   # rafters every 2.5 m
		var r := A.box(lv, Vector3(0.08, 0.16, span), Vector3(x, (yf + yb) / 2.0 - 0.12, (zf + zb) / 2.0), "metal", IRON, false, 0.5)
		r.rotation.x = pitch
		x += 2.5
	# The roof: corrugated sheets, a few gone (the sky through the gap), some rusted through.
	x = c0
	var w := 1.0
	while x < c1 - 0.01:
		var roll := rng.randf()
		if roll > 0.06:
			var tint := Color(0.7, 0.68, 0.64) if roll > 0.3 else Color(0.62, 0.42, 0.3)
			var sheet := A.box(lv, Vector3(w + 0.06, 0.04, span + 0.3), Vector3(x + w / 2.0, (yf + yb) / 2.0 + 0.0, (zf + zb) / 2.0 - 0.1), "corrugated", tint, false, 1.0)
			sheet.rotation.x = pitch
			if arctic:
				A.snow_cap(lv, Vector3(w, 0.14, span), sheet.position + Vector3(0, 0.1, 0), Vector3(pitch, 0, 0))
		x += w
	# The gutter at the back, downpipes down the columns at the ends.
	A.box(lv, Vector3(c1 - c0 + 0.2, 0.14, 0.16), Vector3((c0 + c1) / 2.0, yb - 0.05, zb - 0.05), "metal", IRON.darkened(0.2), false, 0.5)
	for cx in [cols[0], cols[-1]]:
		A.cyl(lv, 0.05, yb - TOP, Vector3(cx + 0.18, (TOP + yb) / 2.0, col_z + 0.18), "metal", IRON.darkened(0.25), false)
	# The valance: a fringe of boards with pointed ends along the front edge, painted cream once.
	var front := A.box(lv, Vector3(c1 - c0 + 0.1, 0.12, 0.06), Vector3((c0 + c1) / 2.0, yf + 0.05, zf - 0.1), "wood", CREAM.darkened(0.2), false, 0.8)
	front.rotation.x = 0.0
	x = c0
	while x < c1:
		if rng.randf() > 0.04:   # (one gone here and there)
			var cr := CREAM.darkened(rng.randf() * 0.25)
			A.box(lv, Vector3(0.15, 0.48, 0.025), Vector3(x + 0.085, yf - 0.24, zf - 0.13), "wood", cr, false, 0.5)
			A.prism(lv, Vector3(0.15, 0.13, 0.025), Vector3(x + 0.085, yf - 0.545, zf - 0.13), "wood", cr, Vector3(0, 0, PI), 0.5)
		x += 0.17
	# Lamps under it, and the station's name hanging across it at each end (seen down the platform).
	for lx in [c0 + 4.5, (c0 + c1) / 2.0 + (2.5 if absf((c0 + c1) / 2.0 - sx) < 2.0 else 0.0), c1 - 4.5]:
		A.hanging_lamp(lv, Vector3(lx, yb + 0.1, Z0 + 2.2), Color(1.0, 0.8, 0.55), 0.55, 1.3, false)
	var under := yb + (yf - yb) * (zb - (Z0 + 1.9)) / (zb - zf)   # (the roof's height over the hangers)
	for hx in [c0 + 1.2, c1 - 1.2]:
		_hung_board(lv, Vector3(hx, under - 0.02, Z0 + 1.9), title)
	_hung_clock(lv, Vector3(sx + 3.5 if absf(sx + 3.5) < 13.0 else sx - 3.5, under - 0.02, Z0 + 1.9))


## A name board hanging from the canopy on two rods, across the platform: readable both ways.
static func _hung_board(lv: Node3D, at: Vector3, title: String) -> void:
	for dz in [-0.6, 0.6]:
		A.box(lv, Vector3(0.025, 0.85, 0.025), at + Vector3(0, -0.42, dz), "metal", IRON, false, 0.3)
	A.box(lv, Vector3(0.06, 0.5, 1.7), at + Vector3(0, -1.1, 0), "enamel", Color(0.16, 0.24, 0.34), false, 0.5)
	A.box(lv, Vector3(0.05, 0.56, 1.76), at + Vector3(0, -1.1, 0), "metal", Color(0.85, 0.83, 0.76), false, 0.5)
	for s in [-1.0, 1.0]:
		var t := B.label(lv, title, at + Vector3(s * 0.035, -1.1, 0), 34, Color(0.94, 0.92, 0.86), "plate", 0.0075)
		t.rotation.y = s * PI / 2.0


## The platform clock: a drum with a face each way, black hands, hung from the canopy on a bracket.
static func _hung_clock(lv: Node3D, at: Vector3) -> void:
	A.box(lv, Vector3(0.05, 0.45, 0.05), at + Vector3(0, -0.22, 0), "metal", IRON, false, 0.3)
	var drum := A.cyl(lv, 0.32, 0.22, at + Vector3(0, -0.7, 0), "metal", IRON, false, "x")
	drum.rotation = Vector3(0, 0, PI / 2.0)
	for s in [-1.0, 1.0]:
		var face := A.cyl(lv, 0.27, 0.01, at + Vector3(s * 0.115, -0.7, 0), "cream", Color(0.92, 0.9, 0.82), false, "x")
		face.rotation = Vector3(0, 0, PI / 2.0)
		for k in 12:   # hour marks
			var a := TAU * k / 12.0
			A.box(lv, Vector3(0.005, 0.045 if k % 3 == 0 else 0.025, 0.012), at + Vector3(s * 0.122, -0.7 + cos(a) * 0.22, sin(a) * 0.22), "rubber", Color(0.08, 0.08, 0.08), false, 0.2, Vector3(a, 0, 0))
		A.box(lv, Vector3(0.006, 0.17, 0.018), at + Vector3(s * 0.125, -0.7 + 0.07, 0.03), "rubber", Color(0.06, 0.06, 0.06), false, 0.2, Vector3(-0.4, 0, 0))   # (stopped, long ago)
		A.box(lv, Vector3(0.006, 0.12, 0.02), at + Vector3(s * 0.125, -0.7 - 0.03, -0.05), "rubber", Color(0.06, 0.06, 0.06), false, 0.2, Vector3(-2.2, 0, 0))


# --- the building -----------------------------------------------------------------------------------

## Brick, stone quoins, sills and lintels, a slate roof with two chimneys; the booking hall straight
## through the middle, the ticket office to the west behind its window, the waiting room to the east.
static func _building(lv: Node3D, sx: float, title: String, rng: RandomNumberGenerator, arctic: bool) -> Vector3:
	var r := Node3D.new()
	lv.add_child(r)
	r.position = Vector3(sx, 0, Z1 + DEEP / 2.0)
	var hd := DEEP / 2.0
	var top := TOP + WALL
	# The plinth up to the platform's level, the floor on it.
	A.box(r, Vector3(HW * 2.0 + 0.3, TOP, DEEP + 0.15), Vector3(0, TOP / 2.0, 0.075), "brick", BRICK.darkened(0.15), true, 0.8)   # (front flush with the platform's back)
	A.box(r, Vector3(HW * 2.0 + 0.4, 0.12, DEEP + 0.25), Vector3(0, 0.2, 0.12), "concrete", STONE.darkened(0.2), false, 1.0)   # (the damp course, proud)
	for room in [[-HW + 0.15, -3.0, "wood"], [-3.0, 3.0, "tiles"], [3.0, HW - 0.15, "wood"]]:
		var w: float = room[1] - room[0]
		A.box(r, Vector3(w, 0.04, DEEP - 0.3), Vector3((room[0] + room[1]) / 2.0, TOP + 0.02, 0), room[2], Color(0.72, 0.66, 0.58) if room[2] == "tiles" else Color(0.62, 0.52, 0.42), false, 1.0 if room[2] == "tiles" else 1.5)
	# The walls, with their doors and windows: [centre, width, bottom, top] over the floor.
	var door := [0.0, 1.7, 0.0, 2.55]
	var wins := [[-6.0, 1.3, 0.85, 2.6], [6.0, 1.3, 0.85, 2.6]]
	var front_wins := wins + [[-3.9, 0.9, 1.0, 2.2]]   # (the office's small window by the hall door)
	A.wall(r, -HW, HW, -hd + 0.15, WALL, 0.3, [door] + front_wins, "brick", BRICK, true, TOP, true, 0.8)
	A.wall(r, -HW, HW, hd - 0.15, WALL, 0.3, [door] + wins, "brick", BRICK, true, TOP, true, 0.8)
	for s in [-1.0, 1.0]:
		A.wall(r, -hd + 0.3, hd - 0.3, s * (HW - 0.15), WALL, 0.3, [[0.0, 1.3, 0.85, 2.6]], "brick", BRICK, false, TOP, true, 0.8)
	# Inside: the hall's partitions (a door into each side room; the ticket window on the office side).
	var into := [1.8, 1.0, 0.0, 2.2]
	A.wall(r, -hd + 0.3, hd - 0.3, -3.0, WALL, 0.12, [into, [-1.5, 1.1, 0.95, 1.9]], "concrete", Color(0.7, 0.68, 0.62), false, TOP, true, 1.5)
	A.wall(r, -hd + 0.3, hd - 0.3, 3.0, WALL, 0.12, [into], "concrete", Color(0.7, 0.68, 0.62), false, TOP, true, 1.5)
	# Inside, every room lined: glazed tiles to the waist in the hall, boards in the side rooms,
	# distemper above gone grey and stained (a skin a centimetre inside the brick and partitions).
	var rooms := [[-HW + 0.3, -3.07, "panelling", Color(0.62, 0.5, 0.38)], [-2.93, 2.93, "tiles", Color(0.5, 0.62, 0.52)], [3.07, HW - 0.3, "panelling", Color(0.62, 0.5, 0.38)]]
	for rm in rooms:
		var x0: float = rm[0]
		var x1: float = rm[1]
		for s in [-1.0, 1.0]:   # front and back
			var holes := ([door] + (front_wins if s < 0.0 else wins)).filter(func(o): return o[0] + o[1] / 2.0 > x0 and o[0] - o[1] / 2.0 < x1)
			_lining(r, x0, x1, s * (hd - 0.31), true, holes, rm[2], rm[3])
		for e in [[x0, 1.0], [x1, -1.0]]:   # the two end walls of the room, its inside faces
			var ex: float = e[0] + e[1] * 0.01
			var holes := []
			if absf(e[0]) > HW - 1.0:
				holes = [[0.0, 1.3, 0.85, 2.6]]
			else:
				holes = [into] + ([[-1.5, 1.1, 0.95, 1.9]] if e[0] < 0.0 else [])
			_lining(r, -hd + 0.31, hd - 0.31, ex, false, holes, rm[2], rm[3])
	A.box(r, Vector3(HW * 2.0 - 0.6, 0.1, DEEP - 0.6), Vector3(0, top - 0.05, 0), "ceiling_tile", Color(0.8, 0.78, 0.72), false, 1.0)   # ceilings
	# Stone at the corners (quoins, long and short in turn), round the openings, a band at the eaves.
	for cx in [-HW, HW]:
		for cz in [-hd, hd]:
			var y := TOP
			var k := 0
			while y < top - 0.1:
				var lg := k % 2 == 0
				var sxz := Vector3(0.55 if lg else 0.32, 0.3, 0.32 if lg else 0.55)
				A.box(r, sxz, Vector3(signf(cx) * (HW + 0.025 - sxz.x / 2.0), y + 0.15, signf(cz) * (hd + 0.025 - sxz.z / 2.0)), "concrete", STONE, false, 1.0)
				y += 0.32
				k += 1
	A.box(r, Vector3(HW * 2.0 + 0.36, 0.22, DEEP + 0.36), Vector3(0, top - 0.11, 0), "concrete", STONE.darkened(0.08), false, 1.0)   # eaves band
	for s in [-1.0, 1.0]:
		var z: float = s * (hd + 0.03)
		for o in [door] + (front_wins if s < 0.0 else wins):
			_opening(r, Vector3(o[0], TOP + o[2], z), o[1], o[3] - o[2], s, o == door, rng)
	for s in [-1.0, 1.0]:
		_opening_side(r, Vector3(s * (HW + 0.03), TOP + 0.85, 0.0), 1.3, 1.75, s, rng)
	# The ticket window: a brass grille in it, a counter ledge either side, a sign over it.
	for k in 7:
		A.cyl(r, 0.012, 0.95, Vector3(-3.0, TOP + 1.42, -1.5 - 0.45 + k * 0.15), "brass", Color.WHITE)
	A.box(r, Vector3(0.6, 0.05, 1.3), Vector3(-3.0, TOP + 0.93, -1.5), "wood", Color(0.5, 0.36, 0.25), true, 0.6)
	A.box(r, Vector3(0.04, 0.22, 0.9), Vector3(-2.9, TOP + 2.1, -1.5), "enamel", Color(0.16, 0.24, 0.34), false, 0.5)
	B.label(r, "TICKETS", Vector3(-2.88, TOP + 2.1, -1.5), 30, Color(0.92, 0.9, 0.84), "plate", 0.005).rotation.y = PI / 2.0
	# The roof: slates on a gable roof along the building, gable ends in brick with a stone coping,
	# two chimneys with pots, a ridge of clay.
	var pitch := 0.62
	var run := hd + 0.55
	var rise := run * tan(pitch)
	for s in [-1.0, 1.0]:
		var slope := A.box(r, Vector3(HW * 2.0 + 0.8, 0.12, run / cos(pitch)), Vector3(0, top + rise / 2.0 - 0.02, s * run / 2.0), "shingle", Color(0.55, 0.58, 0.64), false, 1.0)
		slope.rotation.x = s * pitch
		if arctic:
			var n := Vector3(0, cos(pitch), s * sin(pitch))
			A.snow_cap(r, Vector3(HW * 2.0 + 0.6, 0.18, run / cos(pitch) - 0.4), slope.position + n * 0.14 + Vector3(0, 0, -s * 0.1), Vector3(s * pitch, 0, 0))
		var fascia := A.box(r, Vector3(HW * 2.0 + 0.8, 0.22, 0.05), Vector3(0, top - 0.04, s * (run - 0.02)), "wood", TRIM.darkened(0.3), false, 0.8)
		fascia.rotation.x = s * pitch
		A.box(r, Vector3(HW * 2.0 + 0.8, 0.1, 0.14), Vector3(0, top - 0.2, s * (run + 0.03)), "metal", Color(0.3, 0.3, 0.3), false, 0.5)   # gutter
	A.box(r, Vector3(HW * 2.0 + 0.85, 0.16, 0.26), Vector3(0, top + rise + 0.04, 0), "brick", Color(0.6, 0.35, 0.28), false, 0.6)   # ridge tiles
	for s in [-1.0, 1.0]:
		A.prism(r, Vector3(DEEP + 0.3, rise, 0.3), Vector3(s * (HW - 0.15), top + rise / 2.0, 0), "brick", BRICK, Vector3(0, PI / 2.0, 0), 1.5)
		for side in [-1.0, 1.0]:   # stone coping up the gable's edges
			var cp := A.box(r, Vector3(0.42, 0.14, run / cos(pitch) + 0.1), Vector3(s * (HW - 0.12), top + rise / 2.0 + 0.1, side * run / 2.0), "concrete", STONE, false, 1.0)
			cp.rotation.x = side * pitch
		A.cyl(r, 0.25, 0.08, Vector3(s * (HW - 0.12), top + 1.0, 0), "concrete", STONE, false, "x")   # a round vent in the gable
		var cx: float = s * (HW - 2.2)
		A.box(r, Vector3(0.7, rise + 1.3, 0.9), Vector3(cx, top + (rise + 1.3) / 2.0 + 0.2, 0.4), "brick", BRICK.darkened(0.1), false, 1.0)
		A.box(r, Vector3(0.82, 0.12, 1.02), Vector3(cx, top + rise + 1.56, 0.4), "concrete", STONE.darkened(0.2), false, 1.0)
		for pz in [0.2, 0.6]:
			A.cyl(r, 0.1, 0.35, Vector3(cx, top + rise + 1.78, pz), "brick", Color(0.65, 0.38, 0.28), false, "y", 0.08)
	# Over the platform door: the station's name, and BOOKING OFFICE over the hall's back door.
	A.box(r, Vector3(1.3, 0.3, 0.03), Vector3(1.75, TOP + 2.1, -hd - 0.02), "enamel", Color(0.16, 0.24, 0.34), false, 0.5)   # beside the platform door
	B.label(r, "BOOKING HALL", Vector3(1.75, TOP + 2.1, -hd - 0.04), 20, Color(0.94, 0.92, 0.86), "plate", 0.0065).rotation.y = PI
	A.box(r, Vector3(2.6, 0.32, 0.04), Vector3(0, TOP + 2.95, hd + 0.04), "enamel", Color(0.16, 0.24, 0.34), false, 0.5)
	B.label(r, "BOOKING OFFICE", Vector3(0, TOP + 2.95, hd + 0.065), 24, Color(0.94, 0.92, 0.86), "plate", 0.0075)
	for s in [-1.0, 1.0]:   # WAITING ROOM and PARCELS over the side doors, inside
		B.label(r, "WAITING ROOM" if s > 0.0 else "PARCELS  OFFICE", Vector3(s * 2.92, TOP + 2.45, 1.8), 18, Color(0.18, 0.16, 0.14), "plate", 0.0075).rotation.y = -s * PI / 2.0
	# Posters on the platform front, a downpipe at each end.
	for px in [-7.8, 4.2, 7.8]:
		if absf(px) > 1.2:
			var tint := [Color(0.8, 0.4, 0.3), Color(0.35, 0.5, 0.65), Color(0.85, 0.75, 0.4), Color(0.8, 0.78, 0.7)][rng.randi() % 4] as Color
			A.box(r, Vector3(0.9, 1.2, 0.02), Vector3(px, TOP + 1.5, -hd - 0.02), "paper", tint, false, 0.6, Vector3(0, 0, rng.randf_range(-0.03, 0.03)))
			if rng.randf() < 0.5:   # a corner come away
				A.box(r, Vector3(0.3, 0.3, 0.02), Vector3(px + 0.3, TOP + 2.0, -hd - 0.05), "paper", tint.darkened(0.2), false, 0.4, Vector3(0.5, 0, 0.6))
	for s in [-1.0, 1.0]:
		for zz in [-1.0, 1.0]:
			A.cyl(r, 0.055, top - 0.3, Vector3(s * (HW - 0.4), (top - 0.3) / 2.0 + 0.1, zz * (hd + 0.12)), "metal", Color(0.28, 0.28, 0.28), false)
	# Lights: one in the hall, one in each side room (one of them out).
	A.hanging_lamp(r, Vector3(0, top - 0.1, 0.4), Color(1.0, 0.8, 0.55), 0.6, 1.2, false)
	A.hanging_lamp(r, Vector3(-6.0, top - 0.1, 0.0), Color(1.0, 0.82, 0.6), 0.5, 0.9, false)
	_interior(r, rng)
	_back_steps(r, rng)
	return r.to_global(Vector3(rng.randf_range(-7.0, 7.0), TOP + 0.4, rng.randf_range(-2.5, 2.5)))


## A room's lining on one wall: `dado` to the waist, stained distemper above. `c` is the wall's
## inside face (offset a centimetre into the room by the caller); holes as A.wall's.
static func _lining(r: Node3D, a0: float, a1: float, c: float, along_x: bool, holes: Array, dado: String, tint: Color) -> void:
	var waist := 1.15
	var up := []
	for o in holes:
		up.append([o[0], o[1], o[2] - waist, o[3] - waist])
	A.wall(r, a0, a1, c, waist, 0.02, holes, dado, tint, along_x, TOP, false, 0.6)
	A.wall(r, a0, a1, c, WALL - waist - 0.02, 0.02, up, "concrete", Color(0.84, 0.8, 0.7), along_x, TOP + waist, false, 2.0)
	var cuts := []   # a dado rail along the top, broken at every door and window it'd cross
	for o in holes:
		if o[2] < waist and o[3] > waist:
			cuts.append([o[0] - o[1] / 2.0, o[0] + o[1] / 2.0])
	cuts.sort_custom(func(p, q): return p[0] < q[0])
	var from := a0
	for piece in cuts + [[a1, a1]]:
		var to: float = minf(piece[0], a1)
		if to - from > 0.05:
			var mid := (from + to) / 2.0
			var rail := Vector3(to - from, 0.06, 0.04) if along_x else Vector3(0.04, 0.06, to - from)
			A.box(r, rail, Vector3(mid, TOP + waist, c) if along_x else Vector3(c, TOP + waist, mid), "wood", Color(0.4, 0.3, 0.22), false, 0.5)
		from = maxf(from, piece[1])


## A door or window in the front or back wall: a stone sill and lintel, a frame, and what's left of it.
static func _opening(r: Node3D, at: Vector3, w: float, h: float, s: float, is_door: bool, rng: RandomNumberGenerator) -> void:
	A.box(r, Vector3(w + 0.5, 0.22, 0.4), at + Vector3(0, h + 0.11, 0), "concrete", STONE, false, 1.0)   # lintel
	A.box(r, Vector3(0.12, 0.2, 0.36), at + Vector3(0, h + 0.13, s * 0.02), "concrete", STONE.darkened(0.15), false, 1.0)   # keystone
	for side in [-1.0, 1.0]:
		A.box(r, Vector3(0.08, h, 0.12), at + Vector3(side * (w / 2.0 - 0.04), h / 2.0, -s * 0.12), "wood", TRIM, false, 0.5)
	A.box(r, Vector3(w, 0.08, 0.12), at + Vector3(0, h - 0.04, -s * 0.12), "wood", TRIM, false, 0.5)
	if is_door:
		# Double doors with glass in the top half: one standing open, one shut (both on the inside).
		var hinge := Node3D.new()
		r.add_child(hinge)
		hinge.position = at + Vector3(-w / 2.0 + 0.04, 0, -s * 0.2)
		hinge.rotation.y = s * rng.randf_range(1.2, 1.6)
		_door_leaf(hinge, Vector3(w / 4.0, 0, 0), w / 2.0 - 0.04, h - 0.1, rng)
		var other := Node3D.new()   # (both stand open: the way through stays clear)
		r.add_child(other)
		other.position = at + Vector3(w / 2.0 - 0.04, 0, -s * 0.2)
		other.rotation.y = -s * rng.randf_range(1.3, 1.7)
		_door_leaf(other, Vector3(-w / 4.0, 0, 0), w / 2.0 - 0.04, h - 0.1, rng)
		A.box(r, Vector3(w + 0.1, 0.06, 0.5), at + Vector3(0, 0.02, s * 0.05), "concrete", STONE.darkened(0.1), false, 1.0)   # step stone
		return
	A.box(r, Vector3(w + 0.3, 0.1, 0.36), at + Vector3(0, -0.05, s * 0.05), "concrete", STONE, false, 1.0)   # sill
	_sash(r, at + Vector3(0, h / 2.0, -s * 0.13), w - 0.16, h - 0.08, false, rng)


static func _opening_side(r: Node3D, at: Vector3, w: float, h: float, s: float, rng: RandomNumberGenerator) -> void:
	A.box(r, Vector3(0.4, 0.22, w + 0.5), at + Vector3(0, h + 0.11, 0), "concrete", STONE, false, 1.0)
	A.box(r, Vector3(0.36, 0.1, w + 0.3), at + Vector3(s * 0.05, -0.05, 0), "concrete", STONE, false, 1.0)
	var n := Node3D.new()
	r.add_child(n)
	n.position = at + Vector3(-s * 0.13, h / 2.0, 0)
	n.rotation.y = PI / 2.0
	_sash(n, Vector3.ZERO, w - 0.16, h - 0.08, false, rng)


## A sash window: frame, glazing bars, glass (some broken out), or boards nailed over it.
static func _sash(r: Node3D, c: Vector3, w: float, h: float, _x: bool, rng: RandomNumberGenerator) -> void:
	for side in [-1.0, 1.0]:
		A.box(r, Vector3(0.07, h, 0.08), c + Vector3(side * w / 2.0, 0, 0), "wood", TRIM, false, 0.4)
		A.box(r, Vector3(w, 0.07, 0.08), c + Vector3(0, side * h / 2.0, 0), "wood", TRIM, false, 0.4)
	A.box(r, Vector3(w, 0.06, 0.1), c, "wood", TRIM, false, 0.4)   # meeting rail
	A.box(r, Vector3(0.035, h, 0.05), c, "wood", TRIM, false, 0.3)
	var roll := rng.randf()
	if roll < 0.2:   # boarded up
		for k in 3:
			A.box(r, Vector3(w + 0.2, 0.2, 0.04), c + Vector3(0, -h / 3.0 + k * h / 3.0, -0.07), "wood", Color(0.62, 0.55, 0.45).darkened(rng.randf() * 0.3), false, 0.8, Vector3(0, 0, rng.randf_range(-0.2, 0.2)))
		return
	for side in [-1.0, 1.0]:
		for half in [-1.0, 1.0]:
			if rng.randf() < (0.3 if roll < 0.6 else 0.05):
				continue   # a pane gone
			var g := A.box(r, Vector3(w / 2.0 - 0.06, h / 2.0 - 0.07, 0.01), c + Vector3(side * w / 4.0, half * h / 4.0, 0.01), "metal", Color.WHITE, false)
			g.material_override = A.glass()


static func _door_leaf(parent: Node3D, at: Vector3, w: float, h: float, rng: RandomNumberGenerator) -> void:
	A.box(parent, Vector3(w, h * 0.55, 0.05), at + Vector3(0, h * 0.275, 0), "wood", TRIM.darkened(0.1), false, 0.6)
	for side in [-1.0, 1.0]:
		A.box(parent, Vector3(0.08, h * 0.45, 0.06), at + Vector3(side * (w / 2.0 - 0.04), h * 0.775, 0), "wood", TRIM.darkened(0.1), false, 0.6)
	A.box(parent, Vector3(w, 0.08, 0.06), at + Vector3(0, h - 0.04, 0), "wood", TRIM.darkened(0.1), false, 0.6)
	if rng.randf() < 0.6:
		var g := A.box(parent, Vector3(w - 0.16, h * 0.4, 0.01), at + Vector3(0, h * 0.77, 0), "metal", Color.WHITE, false)
		g.material_override = A.glass()
	A.sphere(parent, 0.035, at + Vector3(w / 2.0 - 0.12, h * 0.5, -0.05), "brass")


## Furnishing, laid out round the ways through: the hall walked straight across from the platform door
## to the back door, and a clear patch inside every door (nothing stands in a doorway or in front of a
## window above its sill). In the building's space: x along (office -x, hall, waiting room +x), z from
## the platform (-) to the forecourt (+); the walls' inside faces at z ±3.69 and x ±8.69, the
## partitions' at ±2.94 (hall side) and ±3.06; their doors at z 1.3..2.3, the ticket window at
## z -2.05..-0.95 in the office's.
##   hall:    benches on the bare walls, the queue rail at the ticket window, the B.R.M. medallion in
##            the floor, a map of the line, the notice board, the departures board, the weighing
##            machine, a clock over the platform door, TO TRAINS hung from the ceiling, WAY OUT
##   office:  the clerk's counter under the ticket window with its stool, the ticket case, the desk
##            under the front window, parcels on the bench under the end window, the platform scale
##            and its weights, a sack truck, shelves of ledgers, the safe, a coat and cap on a hook
##   waiting: a chimney breast with the fire still glowing in the grate, a mirror and a clock on the
##            mantel, an armchair drawn up to it on a rug, benches, a table laid for tea, a coat
##            stand, a dead palm, pictures on the walls
static func _interior(r: Node3D, rng: RandomNumberGenerator) -> void:
	var f := TOP + 0.04
	var hd := DEEP / 2.0
	var top := TOP + WALL
	var wood := Color(0.5, 0.36, 0.25)
	# --- the booking hall ---
	_bench(r, Vector3(2.64, f, -1.6), _yaw(Vector3.LEFT), rng)   # on the waiting room's partition
	_bench(r, Vector3(-1.95, f, hd - 0.61), _yaw(Vector3.FORWARD), rng)   # either side of the back door
	_bench(r, Vector3(1.95, f, hd - 0.61), _yaw(Vector3.FORWARD), rng)
	A.box(r, Vector3(1.6, 1.0, 0.04), Vector3(1.95, f + 1.6, hd - 0.33), "board", Color(0.3, 0.32, 0.28), false, 0.6)   # departures, over that bench
	B.label(r, "DEPARTURES\n\n06.10  CHECKPOINT\n07.42  EAST\n--.--  WITHDRAWN\n--.--  WITHDRAWN", Vector3(1.95, f + 1.6, hd - 0.355), 16, Color(0.9, 0.88, 0.8), "chalk", 0.006).rotation.y = PI
	for k in 2:   # the queue rail at the ticket window: brass posts, a sagging rope
		A.cyl(r, 0.035, 0.95, Vector3(-2.15, f + 0.475, -2.55 + k * 2.1), "brass", Color.WHITE)
		A.cyl(r, 0.11, 0.04, Vector3(-2.15, f + 0.02, -2.55 + k * 2.1), "brass", Color.WHITE)
	A.seg(r, Vector3(-2.15, f + 0.9, -2.55), Vector3(-2.15, f + 0.72, -1.5), 0.018, 0.018, "canvas", Color(0.55, 0.12, 0.1))
	A.seg(r, Vector3(-2.15, f + 0.72, -1.5), Vector3(-2.15, f + 0.9, -0.45), 0.018, 0.018, "canvas", Color(0.55, 0.12, 0.1))
	A.cyl(r, 1.05, 0.012, Vector3(0, f + 0.006, 0.2), "tiles", Color(0.28, 0.34, 0.3), false)   # the medallion set in the floor
	A.cyl(r, 0.85, 0.014, Vector3(0, f + 0.008, 0.2), "tiles", Color(0.82, 0.76, 0.6), false)
	A.ring(r, 0.62, 0.58, Vector3(0, f + 0.0, 0.2), "tiles", Color(0.3, 0.36, 0.32))
	var emblem := B.label(r, "B.R.M.", Vector3(0, f + 0.017, 0.2), 40, Color(0.2, 0.26, 0.22), "plate", 0.008)
	emblem.rotation.x = -PI / 2.0
	_line_map(r, Vector3(2.92, f + 1.85, -1.6), -1.0)   # over the bench
	var nb := Node3D.new()   # the notice board, between the ticket window and the office door
	r.add_child(nb)
	nb.position = Vector3(-2.92, f + 1.55, 0.2)
	nb.rotation.y = PI / 2.0
	A.box(nb, Vector3(1.1, 0.85, 0.04), Vector3.ZERO, "wood", wood.darkened(0.2), false, 0.5)
	A.box(nb, Vector3(1.0, 0.75, 0.01), Vector3(0, 0, 0.025), "cardboard", Color(0.72, 0.6, 0.45), false, 0.4)
	for k in 5:
		A.box(nb, Vector3(rng.randf_range(0.2, 0.32), rng.randf_range(0.22, 0.32), 0.004), Vector3(-0.32 + k * 0.16, rng.randf_range(-0.18, 0.18), 0.033), "paper", Color(0.92, 0.9, 0.82).darkened(rng.randf() * 0.25), false, 0.3, Vector3(0, 0, rng.randf_range(-0.12, 0.12)))
	B.label(nb, "BUREAU NOTICES", Vector3(0, 0.33, 0.04), 14, Color(0.15, 0.13, 0.1), "stencil", 0.005)
	var clock := A.cyl(r, 0.25, 0.06, Vector3(0, f + 3.05, -hd + 0.36), "cream", Color(0.92, 0.9, 0.82), false, "z")   # over the platform door
	clock.rotation = Vector3(PI / 2.0, 0, 0)
	A.ring(r, 0.27, 0.24, Vector3(0, f + 3.05, -hd + 0.38), "brass", Color.WHITE, Vector3(PI / 2.0, 0, 0))
	A.box(r, Vector3(0.015, 0.17, 0.01), Vector3(0.03, f + 3.12, -hd + 0.4), "rubber", Color(0.06, 0.06, 0.06), false, 0.2, Vector3(0, 0, -0.5))
	A.box(r, Vector3(0.018, 0.12, 0.01), Vector3(-0.04, f + 3.02, -hd + 0.4), "rubber", Color(0.06, 0.06, 0.06), false, 0.2, Vector3(0, 0, 2.1))
	var hang := Node3D.new()   # TO TRAINS, hung from the ceiling just inside the platform door
	r.add_child(hang)
	hang.position = Vector3(0, f + 2.65, -2.4)
	for s in [-0.5, 0.5]:
		A.cyl(hang, 0.008, top - f - 2.65, Vector3(s, (top - f - 2.65) / 2.0, 0), "metal", Color(0.3, 0.3, 0.3))
	A.box(hang, Vector3(1.3, 0.28, 0.04), Vector3.ZERO, "enamel", Color(0.16, 0.24, 0.34), false, 0.5)
	for side in [-1.0, 1.0]:
		var tt := B.label(hang, "TO TRAINS", Vector3(0, 0, side * 0.025), 22, Color(0.94, 0.92, 0.86), "plate", 0.0065)
		tt.rotation.y = 0.0 if side > 0.0 else PI
	A.box(r, Vector3(1.1, 0.24, 0.03), Vector3(0, f + 2.72, hd - 0.33), "enamel", Color(0.16, 0.24, 0.34), false, 0.5)   # WAY OUT over the back door
	B.label(r, "WAY OUT", Vector3(0, f + 2.72, hd - 0.35), 22, Color(0.94, 0.92, 0.86), "plate", 0.0065).rotation.y = PI
	A.box(r, Vector3(0.5, 0.65, 0.4), Vector3(-2.55, f + 0.33, -hd + 0.6), "metal", Color(0.3, 0.28, 0.25), false, 0.5)   # a weighing machine
	A.cyl(r, 0.16, 0.03, Vector3(-2.55, f + 0.68, -hd + 0.6), "cream", Color(0.85, 0.82, 0.7), false)
	A.box(r, Vector3(0.75, 1.0, 0.02), Vector3(1.9, f + 1.55, -hd + 0.33), "paper", Color(0.35, 0.5, 0.65), false, 0.6, Vector3(0, 0, 0.02))   # a holiday poster, faded
	B.label(r, "SEE THE\nCOAST", Vector3(1.9, f + 1.75, -hd + 0.345), 26, Color(0.95, 0.9, 0.75), "stencil", 0.006)
	P.litter(r, Vector3(0, f, 0.5), 2.2, rng, 6)
	# --- the ticket office (-x) ---
	A.box(r, Vector3(0.6, 0.93, 1.7), Vector3(-3.36, f + 0.465, -1.5), "wood", wood.darkened(0.15), true, 0.6)   # the clerk's counter under the window
	A.box(r, Vector3(0.7, 0.05, 1.8), Vector3(-3.4, f + 0.955, -1.5), "wood", wood, false, 0.6)
	for k in 2:
		A.box(r, Vector3(0.02, 0.18, 0.7), Vector3(-3.67, f + 0.6, -1.9 + k * 0.8), "wood", wood.lightened(0.08), false, 0.4)   # drawer fronts
	A.box(r, Vector3(0.18, 0.12, 0.25), Vector3(-3.45, f + 1.04, -1.0), "brass", Color.WHITE, false, 0.3)   # the ticket dater
	A.box(r, Vector3(0.22, 0.004, 0.3), Vector3(-3.5, f + 0.983, -1.9), "paper", Color(0.9, 0.86, 0.74), false, 0.3, Vector3(0, 0.3, 0))
	_stool(r, Vector3(-4.05, f, -1.45))
	_ticket_case(r, Vector3(-4.85, f + 1.65, -hd + 0.44), rng)   # on the front wall between its windows
	A.desk(r, Vector3(-6.0, f, -hd + 0.75), _yaw(Vector3.BACK), rng)   # under the front window
	P.chair(r, Vector3(-6.2, f, -2.2), 0.15)
	A.box(r, Vector3(0.3, 0.12, 0.22), Vector3(-5.5, f + 0.87, -3.0), "wood", Color(0.35, 0.25, 0.18), false, 0.3)   # telegraph sounder
	A.cyl(r, 0.07, 0.22, Vector3(-6.6, f + 0.92, -3.05), "metal", Color(0.3, 0.32, 0.28))   # a hand lamp
	A.sphere(r, 0.06, Vector3(-6.6, f + 1.0, -3.05), "cream", Color(1, 0.8, 0.5), 0.6)
	A.box(r, Vector3(0.55, 0.06, 2.6), Vector3(-8.4, f + 0.72, 0.0), "wood", wood, true, 0.6)   # the parcels bench under the end window
	for zz in [-1.15, 1.15]:
		A.box(r, Vector3(0.5, 0.7, 0.06), Vector3(-8.4, f + 0.35, zz), "wood", wood.darkened(0.2), false, 0.5)
	for k in rng.randi_range(5, 8):   # parcels, brown paper and string (low under the sill)
		var sz := Vector3(rng.randf_range(0.2, 0.4), rng.randf_range(0.06, 0.12) if absf(-1.0 + k * 0.32) < 0.7 else rng.randf_range(0.12, 0.3), rng.randf_range(0.2, 0.35))
		var pz := -1.1 + k * 0.32
		var pc := A.box(r, sz, Vector3(-8.4 + rng.randf_range(-0.08, 0.08), f + 0.75 + sz.y / 2.0, pz), "cardboard", Color(0.72, 0.58, 0.4), false, 0.4, Vector3(0, rng.randf_range(-0.3, 0.3), 0))
		A.box(pc, Vector3(sz.x + 0.004, sz.y + 0.004, 0.012), Vector3.ZERO, "canvas", Color(0.85, 0.8, 0.65), false, 0.2)   # string
		A.box(pc, Vector3(0.1, 0.002, 0.07), Vector3(0.0, sz.y / 2.0 + 0.002, 0.06), "paper", Color(0.95, 0.92, 0.85), false, 0.2)   # label
	_scale(r, Vector3(-7.5, f, 2.3))   # the platform scale and its weights
	_sack_truck(r, Vector3(-7.25, f, hd - 0.45))
	A.shelf_unit(r, Vector3(-4.5, f, hd - 0.56), _yaw(Vector3.FORWARD), rng, 1.6, 2.2, 0.45)   # ledgers, by the back wall
	A.box(r, Vector3(0.75, 0.9, 0.7), Vector3(-8.25, f + 0.45, hd - 0.75), "metal", Color(0.22, 0.24, 0.22), true, 0.5)   # the safe, in the corner
	A.cyl(r, 0.1, 0.04, Vector3(-7.85, f + 0.55, hd - 0.75), "brass", Color.WHITE, false, "x")
	P.filing_cabinet(r, Vector3(-8.3, f, -hd + 0.55), _yaw(Vector3.RIGHT))
	_coat_hook(r, Vector3(-3.08, f + 1.75, 0.2), -1.0, rng)   # on the partition, between the window and the door
	A.box(r, Vector3(0.02, 0.5, 0.36), Vector3(-8.67, f + 1.65, -2.4), "paper", Color(0.92, 0.9, 0.84), false, 0.3)   # a calendar, years out of date
	A.box(r, Vector3(0.025, 0.1, 0.36), Vector3(-8.665, f + 1.85, -2.4), "paper", Color(0.75, 0.2, 0.15), false, 0.3)
	for k in rng.randi_range(3, 5):
		P.papers(r, Vector3(rng.randf_range(-7.6, -4.6), f, rng.randf_range(-1.8, 1.6)), rng)
	# --- the waiting room (+x) ---
	_fireplace(r, Vector3(7.65, f, hd), rng)   # a chimney breast on the back wall, clear of the window
	A.box(r, Vector3(2.4, 0.012, 1.7), Vector3(6.8, f + 0.006, 1.5), "canvas", Color(0.45, 0.14, 0.12), false, 0.5)   # the rug
	A.box(r, Vector3(2.2, 0.013, 1.5), Vector3(6.8, f + 0.007, 1.5), "canvas", Color(0.55, 0.38, 0.22), false, 0.5)
	_armchair(r, Vector3(6.85, f, 1.65), _yaw(Vector3(0.35, 0, 1.0).normalized()), rng)
	_bench(r, Vector3(4.3, f, -hd + 0.61), _yaw(Vector3.BACK), rng)   # under the front windows' sills, either side
	_bench(r, Vector3(7.6, f, -hd + 0.61), _yaw(Vector3.BACK), rng)
	P.table(r, Vector3(6.0, f, -1.0), 0.15, 1.1, 0.7)   # laid for tea that never came
	for k in 2:
		P.chair(r, Vector3(6.0 + (k * 2 - 1) * 0.35, f, -1.65 if k == 0 else -0.35), PI * (1 - k) + 0.2)   # (facing the table)
	A.box(r, Vector3(0.42, 0.004, 0.3), Vector3(5.75, f + 0.8, -1.0), "paper", Color(0.88, 0.86, 0.8), false, 0.3, Vector3(0, 0.4, 0))   # a newspaper
	for k in 2:
		A.cyl(r, 0.04, 0.07, Vector3(6.2 + k * 0.2, f + 0.83, -0.9 - k * 0.1), "cream", Color(0.9, 0.88, 0.82))
	A.cyl(r, 0.07, 0.14, Vector3(6.35, f + 0.87, -1.2), "enamel", Color(0.3, 0.42, 0.55), false, "y", 0.05)   # the pot
	_coat_stand(r, Vector3(3.55, f, hd - 0.45), rng)
	_palm(r, Vector3(8.25, f, -1.7), rng)
	for pic in [[Vector3(3.08, f + 1.75, -1.5), 1.0], [Vector3(8.67, f + 1.75, 2.3), -1.0]]:
		_picture(r, pic[0], pic[1], rng)
	A.hanging_lamp(r, Vector3(5.6, top - 0.1, 0.0), Color(1.0, 0.8, 0.55), 0.6, 0.6, false)


## A rotation that turns a piece's front (its local -z) to face `n`.
static func _yaw(n: Vector3) -> float:
	return atan2(-n.x, -n.z)


## A map of the line on a board: the track drawn across it, the stations as dots, THE LINE over it.
## `s`: which way the wall faces (-1: -x).
static func _line_map(r: Node3D, at: Vector3, s: float) -> void:
	var m := Node3D.new()
	r.add_child(m)
	m.position = at
	m.rotation.y = s * PI / 2.0
	A.box(m, Vector3(1.5, 0.9, 0.04), Vector3.ZERO, "wood", Color(0.35, 0.25, 0.18), false, 0.5)
	A.box(m, Vector3(1.4, 0.8, 0.01), Vector3(0, 0, 0.025), "paper", Color(0.88, 0.84, 0.72), false, 0.5)
	var pts := [Vector2(-0.6, -0.15), Vector2(-0.3, 0.05), Vector2(-0.05, -0.05), Vector2(0.2, 0.12), Vector2(0.45, 0.0), Vector2(0.62, 0.18)]
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		A.seg(m, Vector3(a.x, a.y - 0.08, 0.034), Vector3(b.x, b.y - 0.08, 0.034), 0.012, 0.012, "enamel", Color(0.6, 0.15, 0.12))
	for p: Vector2 in pts:
		A.cyl(m, 0.03, 0.008, Vector3(p.x, p.y - 0.08, 0.036), "enamel", Color(0.12, 0.12, 0.12), false, "z")
	B.label(m, "THE LINE", Vector3(0, 0.3, 0.034), 20, Color(0.2, 0.17, 0.14), "stencil", 0.006)


## The case of ticket stock on the clerk's side: a glass-fronted cabinet of pigeonholes, a stack of
## card tickets in each (a colour a destination), some empty.
static func _ticket_case(r: Node3D, at: Vector3, rng: RandomNumberGenerator) -> void:
	A.box(r, Vector3(0.95, 1.2, 0.26), at, "wood", Color(0.42, 0.3, 0.2), false, 0.6)
	var cols := [Color(0.85, 0.82, 0.6), Color(0.55, 0.7, 0.55), Color(0.85, 0.55, 0.45), Color(0.55, 0.65, 0.8), Color(0.9, 0.85, 0.8)]
	for row in 7:
		for col in 6:
			var c := at + Vector3(-0.38 + col * 0.152, -0.48 + row * 0.16, 0.12)
			A.box(r, Vector3(0.13, 0.13, 0.02), c, "wood", Color(0.18, 0.12, 0.08), false, 0.3)   # the hole
			if rng.randf() < 0.75:
				A.box(r, Vector3(0.05, 0.09, 0.03), c + Vector3(0, -0.015, 0.012), "paper", cols[(row + col * 3) % cols.size()], false, 0.2)
	B.label(r, "TICKETS", at + Vector3(0, 0.68, 0.135), 16, Color(0.9, 0.86, 0.74), "plate", 0.005)


static func _stool(r: Node3D, at: Vector3) -> void:
	A.cyl(r, 0.19, 0.05, at + Vector3(0, 0.72, 0), "wood", Color(0.45, 0.32, 0.22))
	for k in 3:
		var a := TAU * k / 3.0
		A.seg(r, at + Vector3(cos(a) * 0.14, 0.7, sin(a) * 0.14), at + Vector3(cos(a) * 0.22, 0.0, sin(a) * 0.22), 0.02, 0.02, "wood", Color(0.4, 0.28, 0.2))


## A platform scale: an iron platform, a column, the beam with its sliding poise, weights stacked by it.
static func _scale(r: Node3D, at: Vector3) -> void:
	A.box(r, Vector3(0.6, 0.12, 0.5), at + Vector3(0, 0.06, 0), "metal", IRON, true, 0.5)
	A.box(r, Vector3(0.5, 0.02, 0.4), at + Vector3(0, 0.13, 0), "metal", Color(0.4, 0.4, 0.38), false, 0.4)
	A.cyl(r, 0.035, 1.0, at + Vector3(0, 0.62, 0.22), "metal", IRON)
	A.box(r, Vector3(0.55, 0.04, 0.03), at + Vector3(0.1, 1.12, 0.22), "brass", Color.WHITE, false, 0.3)
	A.box(r, Vector3(0.05, 0.07, 0.05), at + Vector3(0.22, 1.12, 0.22), "metal", IRON, false, 0.3)
	for k in 3:
		A.cyl(r, 0.07 - k * 0.012, 0.05, at + Vector3(-0.42, 0.025 + k * 0.05, 0.05), "metal", Color(0.25, 0.25, 0.25))


## A sack truck stood against the wall: two iron wheels, the nose plate, two handles.
static func _sack_truck(r: Node3D, at: Vector3) -> void:
	var t := Node3D.new()
	r.add_child(t)
	t.position = at
	t.rotation.x = -0.18
	for s in [-1.0, 1.0]:
		A.seg(t, Vector3(s * 0.2, 0.15, 0), Vector3(s * 0.17, 1.25, 0.05), 0.02, 0.02, "metal", IRON)
		A.cyl(t, 0.14, 0.05, Vector3(s * 0.26, 0.14, -0.06), "metal", Color(0.2, 0.2, 0.2), false, "x")
	for k in 3:
		A.box(t, Vector3(0.4, 0.025, 0.025), Vector3(0, 0.45 + k * 0.3, 0.02), "metal", IRON, false, 0.3)
	A.box(t, Vector3(0.42, 0.02, 0.22), Vector3(0, 0.03, -0.12), "metal", IRON, false, 0.3)


## A row of hooks on the wall with a long coat and a cap hung on it. `s`: which way the wall faces.
static func _coat_hook(r: Node3D, at: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	A.box(r, Vector3(0.03, 0.08, 0.7), at, "wood", Color(0.4, 0.28, 0.2), false, 0.4)
	for k in 3:
		A.box(r, Vector3(0.08, 0.02, 0.02), at + Vector3(s * 0.05, 0.0, -0.25 + k * 0.25), "brass", Color.WHITE, false, 0.2)
	var coat := A.box(r, Vector3(0.12, 1.05, 0.42), at + Vector3(s * 0.1, -0.55, -0.25), "canvas", Color(0.25, 0.27, 0.3).darkened(rng.randf() * 0.3), false, 0.4)
	coat.rotation.x = 0.04
	A.cyl(r, 0.11, 0.08, at + Vector3(s * 0.09, 0.02, 0.25), "canvas", Color(0.15, 0.17, 0.22))   # the cap
	A.box(r, Vector3(0.1, 0.012, 0.16), at + Vector3(s * 0.16, -0.03, 0.25), "leather", Color(0.1, 0.1, 0.1), false, 0.2)


## The waiting room's fire: a brick chimney breast to the ceiling, the opening with an iron grate and
## the embers still glowing in it, a stone hearth, the mantel (a clock, candlesticks), a mirror over it.
static func _fireplace(r: Node3D, back: Vector3, rng: RandomNumberGenerator) -> void:
	var z := back.z - 0.31   # the wall's inside face
	var h := WALL - 0.12
	A.box(r, Vector3(1.7, h, 0.5), Vector3(back.x, back.y + h / 2.0, z - 0.25), "brick", BRICK.darkened(0.15), true, 1.0)
	A.box(r, Vector3(0.85, 0.75, 0.04), Vector3(back.x, back.y + 0.4, z - 0.51), "rubber", Color(0.03, 0.03, 0.03), false, 0.5)   # the opening
	for k in 5:   # the grate
		A.box(r, Vector3(0.6, 0.02, 0.02), Vector3(back.x, back.y + 0.12 + k * 0.05, z - 0.56), "metal", IRON, false, 0.3)
	A.glow(r, Vector3(0.5, 0.06, 0.12), Vector3(back.x, back.y + 0.13, z - 0.55), Color(1.0, 0.35, 0.08), 2.5)   # embers
	var ember := OmniLight3D.new()
	ember.light_color = Color(1.0, 0.45, 0.15)
	ember.light_energy = 0.7
	ember.omni_range = 4.5
	r.add_child(ember)
	ember.position = Vector3(back.x, back.y + 0.35, z - 0.9)
	A.box(r, Vector3(1.9, 0.05, 0.65), Vector3(back.x, back.y + 0.025, z - 0.8), "concrete", STONE.darkened(0.1), false, 1.0)   # hearth
	A.box(r, Vector3(1.95, 0.08, 0.32), Vector3(back.x, back.y + 1.25, z - 0.62), "concrete", STONE, false, 1.0)   # mantel
	A.box(r, Vector3(0.28, 0.32, 0.14), Vector3(back.x, back.y + 1.45, z - 0.6), "wood", Color(0.3, 0.2, 0.14), false, 0.3)   # the clock
	A.cyl(r, 0.1, 0.01, Vector3(back.x, back.y + 1.48, z - 0.675), "cream", Color(0.9, 0.86, 0.75), false, "z")
	for s in [-1.0, 1.0]:
		A.cyl(r, 0.03, 0.22, Vector3(back.x + s * 0.65, back.y + 1.4, z - 0.6), "brass", Color.WHITE)
		A.cyl(r, 0.015, 0.08, Vector3(back.x + s * 0.65, back.y + 1.55, z - 0.6), "cream", Color(0.9, 0.88, 0.8))
	A.box(r, Vector3(0.9, 0.7, 0.04), Vector3(back.x, back.y + 2.05, z - 0.52), "wood", Color(0.5, 0.38, 0.18), false, 0.4)   # the mirror
	var g := A.box(r, Vector3(0.78, 0.58, 0.01), Vector3(back.x, back.y + 2.05, z - 0.545), "metal", Color(0.55, 0.58, 0.6), false, 0.5)
	(g as MeshInstance3D).material_override = A.glass()
	if rng.randf() < 0.5:   # cracked
		A.box(r, Vector3(0.5, 0.008, 0.005), Vector3(back.x + 0.1, back.y + 2.1, z - 0.552), "cream", Color(0.85, 0.85, 0.85), false, 0.2, Vector3(0, 0, 0.6))


## An armchair: a deep leather seat, rolled arms, a high back, short legs.
static func _armchair(r: Node3D, at: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var n := Node3D.new()
	r.add_child(n)
	n.position = at
	n.rotation.y = yaw
	var hide := Color(0.4, 0.22, 0.14).darkened(rng.randf() * 0.25)
	A.box(n, Vector3(0.75, 0.22, 0.7), Vector3(0, 0.3, 0), "leather", hide, false, 0.4)   # seat
	A.box(n, Vector3(0.65, 0.1, 0.6), Vector3(0, 0.45, -0.02), "leather", hide.lightened(0.08), false, 0.4)   # cushion
	A.box(n, Vector3(0.8, 0.75, 0.18), Vector3(0, 0.62, 0.3), "leather", hide, false, 0.4)   # back
	for s in [-1.0, 1.0]:
		A.box(n, Vector3(0.14, 0.32, 0.68), Vector3(s * 0.38, 0.5, 0.0), "leather", hide.darkened(0.05), false, 0.4)
		A.cyl(n, 0.08, 0.68, Vector3(s * 0.38, 0.66, 0.0), "leather", hide, false, "z")   # the roll
		for zz in [-0.28, 0.28]:
			A.cyl(n, 0.03, 0.18, Vector3(s * 0.3, 0.09, zz), "wood", Color(0.25, 0.16, 0.1))
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.8, 0.6, 0.75)
	cs.shape = sh
	b.add_child(cs)
	n.add_child(b)
	b.position = Vector3(0, 0.3, 0)


static func _coat_stand(r: Node3D, at: Vector3, rng: RandomNumberGenerator) -> void:
	A.cyl(r, 0.03, 1.8, at + Vector3(0, 0.9, 0), "wood", Color(0.35, 0.24, 0.16))
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		A.seg(r, at + Vector3(0, 0.2, 0), at + Vector3(cos(a) * 0.28, 0.0, sin(a) * 0.28), 0.02, 0.02, "wood", Color(0.35, 0.24, 0.16))
		A.seg(r, at + Vector3(0, 1.7, 0), at + Vector3(cos(a) * 0.14, 1.78, sin(a) * 0.14), 0.012, 0.012, "brass", Color.WHITE)
	if rng.randf() < 0.7:   # an umbrella left on it
		A.seg(r, at + Vector3(0.12, 1.72, 0), at + Vector3(0.2, 0.9, 0.05), 0.04, 0.012, "canvas", Color(0.08, 0.08, 0.1))


## A palm in a pot, long dead: a brass-banded tub, dry fronds drooping.
static func _palm(r: Node3D, at: Vector3, rng: RandomNumberGenerator) -> void:
	A.cyl(r, 0.24, 0.45, at + Vector3(0, 0.225, 0), "wood", Color(0.4, 0.28, 0.18), false, "y", 0.28)
	A.cyl(r, 0.27, 0.04, at + Vector3(0, 0.38, 0), "brass", Color.WHITE)
	A.cyl(r, 0.04, 0.6, at + Vector3(0, 0.75, 0), "bark", Color(0.45, 0.38, 0.28))
	for k in 7:
		var a := TAU * k / 7.0 + rng.randf() * 0.4
		var tip := at + Vector3(cos(a) * rng.randf_range(0.5, 0.75), rng.randf_range(0.55, 0.9), sin(a) * rng.randf_range(0.5, 0.75))
		A.seg(r, at + Vector3(0, 1.05, 0), tip, 0.035, 0.008, "canvas", Color(0.55, 0.48, 0.3).darkened(rng.randf() * 0.25))


## A framed picture on a wall facing `s` (+1: +x): a gilt frame, a dark landscape, hanging a little askew.
static func _picture(r: Node3D, at: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var p := Node3D.new()
	r.add_child(p)
	p.position = at
	p.rotation = Vector3(0, s * PI / 2.0, rng.randf_range(-0.05, 0.05))
	A.box(p, Vector3(0.7, 0.5, 0.04), Vector3.ZERO, "brass", Color(0.7, 0.55, 0.3), false, 0.3)
	A.box(p, Vector3(0.6, 0.4, 0.01), Vector3(0, 0, 0.022), "canvas", Color(0.35, 0.45, 0.5), false, 0.4)   # sky
	A.box(p, Vector3(0.6, 0.18, 0.012), Vector3(0, -0.11, 0.024), "canvas", Color(0.3, 0.36, 0.22), false, 0.4)   # hills
	A.box(p, Vector3(0.12, 0.09, 0.013), Vector3(0.12, -0.04, 0.026), "canvas", Color(0.6, 0.3, 0.2), false, 0.3)   # a house


static func _bench(r: Node3D, at: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var n := Node3D.new()
	r.add_child(n)
	n.position = at
	n.rotation.y = yaw
	var wood := Color(0.55, 0.42, 0.3).darkened(rng.randf() * 0.2)
	for s in [-1.0, 1.0]:   # cast ends
		A.box(n, Vector3(0.06, 0.45, 0.45), Vector3(s * 0.85, 0.22, 0.0), "metal", IRON, false, 0.4)
		A.box(n, Vector3(0.06, 0.5, 0.08), Vector3(s * 0.85, 0.7, 0.22), "metal", IRON, false, 0.4)
	for k in 4:   # seat slats
		A.box(n, Vector3(1.85, 0.04, 0.09), Vector3(0, 0.46, -0.16 + k * 0.11), "wood", wood, false, 0.6)
	for k in 3:   # back slats
		A.box(n, Vector3(1.85, 0.09, 0.03), Vector3(0, 0.62 + k * 0.13, 0.24), "wood", wood, false, 0.6)
	var body := StaticBody3D.new()   # (you can stand on it; things can't fall through it)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.85, 0.5, 0.5)
	cs.shape = sh
	body.add_child(cs)
	n.add_child(body)
	body.position = Vector3(0, 0.25, 0)


## Steps from the hall's back door down to the forecourt, with cheek walls and an iron rail.
static func _back_steps(r: Node3D, _rng: RandomNumberGenerator) -> void:
	var hd := DEEP / 2.0
	var steps := 4
	var depth := 0.42
	for k in steps:
		var y := TOP - (k + 1) * TOP / steps
		A.box(r, Vector3(2.4, TOP / steps, depth + 0.02), Vector3(0, y + TOP / steps / 2.0, hd + 0.15 + depth * (k + 0.5)), "concrete", STONE.darkened(0.05 * k), true, 1.0)
		if y > 0.01:
			A.box(r, Vector3(2.4, y, depth), Vector3(0, y / 2.0, hd + 0.15 + depth * (k + 0.5)), "concrete", STONE.darkened(0.2), false, 1.0)
	for s in [-1.0, 1.0]:
		A.box(r, Vector3(0.3, TOP, depth * steps), Vector3(s * 1.35, TOP / 2.0, hd + 0.15 + depth * steps / 2.0), "brick", BRICK.darkened(0.1), true, 1.0)
		P.railing_slope(r, Vector3(s * 1.35, TOP + 0.05, hd + 0.15), Vector3(0, 0, 1), TOP, depth * steps)
	# A little roof over the back door on two brackets.
	var hood := A.box(r, Vector3(2.6, 0.08, 1.1), Vector3(0, TOP + 2.95, hd + 0.55), "corrugated", Color(0.62, 0.45, 0.35), false, 1.0)
	hood.rotation.x = -0.2
	for s in [-1.0, 1.0]:
		A.seg(r, Vector3(s * 1.1, TOP + 2.4, hd + 0.02), Vector3(s * 1.1, TOP + 2.95, hd + 0.95), 0.03, 0.03, "metal", IRON)


# --- on the platform ---------------------------------------------------------------------------------

static func _furniture(lv: Node3D, sx: float, title: String, rng: RandomNumberGenerator) -> void:
	# Benches facing the track, against the building.
	for bx in [-13.0, -8.5, 9.5, 13.5]:
		if absf(bx - sx) > HW + 1.0:
			_bench(lv, Vector3(bx, TOP, Z1 - 0.65), _yaw(Vector3.FORWARD), rng)   # (backs to the building)
	# Name boards at both ends, on two posts, facing the track: what you read rolling in.
	for nx in [X0 + 4.0, X1 - 4.0]:
		for dx in [-1.55, 1.55]:
			A.box(lv, Vector3(0.12, 2.1, 0.12), Vector3(nx + dx, TOP + 1.05, Z1 - 0.6), "metal", IRON, false, 0.5)
		A.box(lv, Vector3(3.6, 0.8, 0.06), Vector3(nx, TOP + 1.85, Z1 - 0.62), "enamel", Color(0.16, 0.24, 0.34), false, 0.5)
		A.box(lv, Vector3(3.7, 0.9, 0.05), Vector3(nx, TOP + 1.85, Z1 - 0.59), "metal", Color(0.85, 0.83, 0.76), false, 0.5)
		B.label(lv, title, Vector3(nx, TOP + 1.85, Z1 - 0.655), 54, Color(0.94, 0.92, 0.86), "plate", 0.0085).rotation.y = PI
	# A luggage trolley: iron-shod wheels, a slatted bed, a handle bar; a few cases on it.
	var t := Node3D.new()
	lv.add_child(t)
	t.position = Vector3(-21.5, TOP, Z1 - 1.6)
	t.rotation.y = rng.randf_range(-0.3, 0.3)
	for k in 6:
		A.box(t, Vector3(2.2, 0.04, 0.16), Vector3(0, 0.5, -0.45 + k * 0.18), "wood", Color(0.5, 0.4, 0.3), false, 0.6)
	for s in [-1.0, 1.0]:
		A.box(t, Vector3(2.3, 0.08, 0.06), Vector3(0, 0.44, s * 0.48), "metal", IRON, false, 0.4)
		for wx in [-0.8, 0.8]:
			A.cyl(t, 0.22, 0.06, Vector3(wx, 0.22, s * 0.5), "metal", Color(0.2, 0.2, 0.2), false, "z")
	A.seg(t, Vector3(1.1, 0.5, -0.45), Vector3(1.6, 1.2, 0.0), 0.025, 0.025, "metal", IRON)
	A.seg(t, Vector3(1.1, 0.5, 0.45), Vector3(1.6, 1.2, 0.0), 0.025, 0.025, "metal", IRON)
	A.box(t, Vector3(0.7, 0.4, 0.45), Vector3(-0.4, 0.73, 0.1), "leather", Color(0.45, 0.3, 0.2), false, 0.4)
	A.box(t, Vector3(0.55, 0.3, 0.35), Vector3(0.3, 0.68, -0.15), "canvas", Color(0.5, 0.48, 0.4), false, 0.4)
	A.crate(t, Vector3(-0.2, 0.52, -0.3), 0.5, rng, false)
	# Fire buckets on a red rack, sand in them; a bin; milk churns waiting for a train that won't come.
	var fr := Vector3(-17.5, TOP, Z1 - 0.3)
	A.box(lv, Vector3(1.2, 0.7, 0.08), fr + Vector3(0, 1.3, 0), "enamel", Color(0.7, 0.15, 0.1), false, 0.5)
	B.label(lv, "FIRE", fr + Vector3(0, 1.45, -0.045), 26, Color(0.95, 0.92, 0.85), "stencil", 0.007).rotation.y = PI
	for k in 3:
		A.cyl(lv, 0.13, 0.28, fr + Vector3(-0.38 + k * 0.38, 1.05, -0.12), "enamel", Color(0.72, 0.16, 0.1), false, "y", 0.11)
	for k in rng.randi_range(2, 4):
		var cz := Vector3(17.5 + k * 0.45, TOP, Z1 - 0.6 - (k % 2) * 0.4)
		A.cyl(lv, 0.2, 0.62, cz + Vector3(0, 0.31, 0), "metal", Color(0.62, 0.62, 0.6), true, "y", 0.16)
		A.cyl(lv, 0.11, 0.12, cz + Vector3(0, 0.68, 0), "metal", Color(0.55, 0.55, 0.53), false)
	A.barrel(lv, Vector3(-19.2, TOP, Z1 - 0.7), rng)
	A.crate(lv, Vector3(19.3, TOP, Z1 - 1.5), 0.8, rng)


# --- behind the station --------------------------------------------------------------------------------

## The forecourt behind the building: packed gravel, a lamp, a bench and a notice board pointing on
## to the lift, an old van that never left, a hand cart.
static func _forecourt(lv: Node3D, sx: float, rng: RandomNumberGenerator) -> void:
	var z0 := Z1 + DEEP + 0.2
	var z1 := z0 + 9.0
	A.box(lv, Vector3(26.0, 0.05, z1 - z0), Vector3(sx, 0.025, (z0 + z1) / 2.0), "gravel", Color(0.72, 0.68, 0.62), true, 2.0)
	for s in [-1.0, 1.0]:   # kerbs along its sides
		A.box(lv, Vector3(0.25, 0.15, z1 - z0), Vector3(sx + s * 13.0, 0.075, (z0 + z1) / 2.0), "concrete", STONE.darkened(0.1), false, 1.0)
	A.lamp_post(lv, Vector3(sx - 4.5, 0, z0 + 2.5), Color(1.0, 0.78, 0.5))
	_bench(lv, Vector3(sx - 7.0, 0.05, z0 + 0.8), PI, rng)
	# The notice board: B.R.M. instructions and an arrow to the lift.
	var nb := Vector3(sx + 5.5, 0, z0 + 2.6)
	for dx in [-0.9, 0.9]:
		A.box(lv, Vector3(0.1, 2.2, 0.1), nb + Vector3(dx, 1.1, 0), "wood", Color(0.5, 0.42, 0.34), false, 0.6)
	A.box(lv, Vector3(2.0, 1.1, 0.06), nb + Vector3(0, 1.6, 0), "board", Color(0.32, 0.36, 0.3), false, 0.6)
	A.box(lv, Vector3(2.2, 0.12, 0.3), nb + Vector3(0, 2.22, 0), "wood", Color(0.45, 0.38, 0.3), false, 0.6)   # its little roof
	for k in 3:
		A.box(lv, Vector3(0.45, 0.6, 0.01), nb + Vector3(-0.6 + k * 0.6, 1.6, -0.035), "paper", Color(0.85, 0.82, 0.72).darkened(rng.randf() * 0.2), false, 0.4, Vector3(0, 0, rng.randf_range(-0.05, 0.05)))
	B.label(lv, "B.R.M.  NOTICES", nb + Vector3(0, 2.02, -0.04), 20, Color(0.9, 0.88, 0.8), "stencil", 0.006).rotation.y = PI
	P.car_wreck(lv, Vector3(sx + 9.0, 0, z0 + 5.5), rng.randf_range(-0.3, 0.3), rng)
	A.crate(lv, Vector3(sx - 10.5, 0, z0 + 1.0), 0.9, rng)
	A.pallet(lv, Vector3(sx - 9.5, 0, z0 + 2.4))


## A signal box past the platform's west end: a brick locking room under a timber cabin glazed all
## round, a stair up its end, the lever frame inside, its name on the front.
static func _signal_box(lv: Node3D, letter: String, rng: RandomNumberGenerator, arctic: bool) -> void:
	var r := Node3D.new()
	lv.add_child(r)
	r.position = Vector3(X0 - 12.0, 0, 7.6)
	var w := 5.0
	var d := 3.4
	var low := 2.6
	var cab := 2.5
	# Locking room: brick, small windows with bars, a door.
	A.wall(r, -w / 2.0, w / 2.0, -d / 2.0 + 0.12, low, 0.24, [[-1.2, 0.6, 1.0, 1.8], [0.0, 0.6, 1.0, 1.8], [1.2, 0.6, 1.0, 1.8]], "brick", BRICK, true, 0.0, true, 0.8)
	A.wall(r, -w / 2.0, w / 2.0, d / 2.0 - 0.12, low, 0.24, [], "brick", BRICK, true, 0.0, true, 0.8)
	A.wall(r, -d / 2.0, d / 2.0, -w / 2.0 + 0.12, low, 0.24, [[0.0, 0.9, 0.0, 2.0]], "brick", BRICK, false, 0.0, true, 0.8)
	A.wall(r, -d / 2.0, d / 2.0, w / 2.0 - 0.12, low, 0.24, [], "brick", BRICK, false, 0.0, true, 0.8)
	for k in 3:
		for b in 4:
			A.cyl(r, 0.012, 0.8, Vector3(-1.2 + k * 1.2 - 0.22 + b * 0.15, 1.4, -d / 2.0 + 0.02), "rust", Color.WHITE)
	A.box(r, Vector3(w + 0.1, 0.16, d + 0.1), Vector3(0, low + 0.08, 0), "wood", Color(0.5, 0.4, 0.3), true, 1.0)   # the floor above
	# Cabin: timber posts and panels below the windows, glass all round above, a hipped tin roof.
	var c := Color(0.72, 0.62, 0.48)
	var y0 := low + 0.16
	for s in [-1.0, 1.0]:
		A.box(r, Vector3(w, 1.0, 0.1), Vector3(0, y0 + 0.5, s * (d / 2.0 - 0.05)), "wood", c, true, 0.8)
	A.box(r, Vector3(0.1, 1.0, d), Vector3(-w / 2.0 + 0.05, y0 + 0.5, 0), "wood", c, true, 0.8)
	A.wall(r, -d / 2.0, d / 2.0, w / 2.0 - 0.05, cab, 0.1, [[0.0, 0.9, 0.0, 2.1]], "wood", c, false, y0, true, 0.8)   # the end with the door
	var leaf := A.box(r, Vector3(0.05, 2.05, 0.85), Vector3(w / 2.0 + 0.35, y0 + 1.03, 0.43 + 0.35), "wood", TRIM, false, 0.6)   # standing open
	leaf.rotation.y = 1.2
	for px in [-w / 2.0, -w / 6.0, w / 6.0, w / 2.0]:
		for pz in [-d / 2.0, d / 2.0]:
			A.box(r, Vector3(0.12, cab, 0.12), Vector3(px, y0 + cab / 2.0, pz), "wood", TRIM.lightened(0.1), false, 0.6)
	for s in [-1.0, 1.0]:
		var g := A.box(r, Vector3(w - 0.1, cab - 1.15, 0.02), Vector3(0, y0 + 1.0 + (cab - 1.15) / 2.0, s * (d / 2.0 - 0.04)), "metal", Color.WHITE, false)
		g.material_override = A.glass()
		if s < 0.0:
			var g2 := A.box(r, Vector3(0.02, cab - 1.15, d - 0.1), Vector3(s * (w / 2.0 - 0.04), y0 + 1.0 + (cab - 1.15) / 2.0, 0), "metal", Color.WHITE, false)
			g2.material_override = A.glass()
		A.box(r, Vector3(w + 0.1, 0.08, 0.14), Vector3(0, y0 + 1.0, s * (d / 2.0)), "wood", TRIM.lightened(0.1), false, 0.6)
		A.box(r, Vector3(w + 0.1, 0.1, 0.14), Vector3(0, y0 + cab, s * (d / 2.0)), "wood", TRIM.lightened(0.1), false, 0.6)
	var ry := y0 + cab + 0.05
	for s in [-1.0, 1.0]:
		var sl := A.box(r, Vector3(w + 0.9, 0.06, d / 2.0 + 0.7), Vector3(0, ry + 0.35, s * (d / 4.0 + 0.2)), "corrugated", Color(0.55, 0.4, 0.32), false, 1.0)
		sl.rotation.x = s * 0.4
		if arctic:
			A.snow_cap(r, Vector3(w + 0.7, 0.14, d / 2.0 + 0.5), sl.position + Vector3(0, 0.1, 0), Vector3(s * 0.4, 0, 0))
	A.box(r, Vector3(0.3, 1.4, 0.3), Vector3(1.6, ry + 0.9, 0.5), "metal", Color(0.2, 0.2, 0.2), false, 0.5)   # stove pipe
	# The lever frame: a row of levers, painted by what they work.
	var cols := [Color(0.75, 0.12, 0.08), Color(0.75, 0.12, 0.08), Color(0.85, 0.7, 0.15), Color(0.12, 0.12, 0.12), Color(0.75, 0.12, 0.08), Color(0.2, 0.3, 0.6), Color(0.85, 0.85, 0.82), Color(0.75, 0.12, 0.08)]
	A.box(r, Vector3(w - 0.8, 0.12, 0.4), Vector3(0, y0 + 0.06, -0.6), "metal", Color(0.25, 0.25, 0.25), false, 0.5)
	for k in cols.size():
		var lv_ := A.box(r, Vector3(0.05, 1.1, 0.06), Vector3(-1.75 + k * 0.5, y0 + 0.6, -0.6), "metal", cols[k], false, 0.3)
		lv_.rotation.z = 0.0
		lv_.rotation.x = 0.3 if rng.randf() < 0.3 else -0.15
	A.box(r, Vector3(w - 0.6, 0.4, 0.06), Vector3(0, y0 + 1.95, d / 2.0 - 0.2), "board", Color(0.2, 0.22, 0.2), false, 0.5)   # the track diagram
	# The stair up its far end and a landing at the door.
	P.stairs(r, Vector3(w / 2.0 + 0.6, y0, 0.0), Vector3(1, 0, 0), y0, 3.4, 1.0)
	A.box(r, Vector3(1.2, 0.08, 1.2), Vector3(w / 2.0 + 0.0, y0 - 0.04, 0.0), "grate", Color.WHITE, true, 0.5)
	# Its name, facing the track.
	A.box(r, Vector3(2.4, 0.4, 0.05), Vector3(0, low - 0.35, -d / 2.0 - 0.03), "enamel", Color(0.16, 0.24, 0.34), false, 0.5)
	B.label(r, "%s  SIGNAL BOX" % letter, Vector3(0, low - 0.35, -d / 2.0 - 0.06), 28, Color(0.94, 0.92, 0.86), "plate", 0.007).rotation.y = PI


## A water crane beside the line: a fluted column on a base, a swinging arm along the track, a
## leather bag hanging off its end, a valve wheel.
static func _water_crane(lv: Node3D, at: Vector3) -> void:
	var c := Color(0.28, 0.3, 0.28)
	A.box(lv, Vector3(0.9, 0.3, 0.9), at + Vector3(0, 0.15, 0), "concrete", Color(0.7, 0.68, 0.64), false, 1.0)
	A.cyl(lv, 0.22, 0.6, at + Vector3(0, 0.6, 0), "metal", c, false)
	A.cyl(lv, 0.14, 3.0, at + Vector3(0, 2.4, 0), "metal", c, true)
	A.cyl(lv, 0.2, 0.25, at + Vector3(0, 3.9, 0), "metal", c, false)
	A.cyl(lv, 0.12, 3.2, at + Vector3(-1.4, 4.1, 0), "metal", c, false, "x")   # the arm
	A.seg(lv, at + Vector3(0, 4.6, 0), at + Vector3(-2.6, 4.2, 0), 0.02, 0.02, "metal", c)   # its stay
	A.seg(lv, at + Vector3(-3.0, 4.0, 0), at + Vector3(-3.05, 2.6, 0.1), 0.11, 0.09, "leather", Color(0.35, 0.24, 0.16))   # the bag
	A.ring(lv, 0.25, 0.2, at + Vector3(0.3, 1.2, 0), "metal", Color(0.6, 0.15, 0.1), Vector3(0, 0, PI / 2.0))   # valve wheel
	A.cyl(lv, 0.05, 0.8, at + Vector3(0, 4.45, 0), "metal", c, false)   # the lamp on top
	A.box(lv, Vector3(0.18, 0.22, 0.18), at + Vector3(0, 4.95, 0), "metal", c, false, 0.3)
