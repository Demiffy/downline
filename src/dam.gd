# The dam: a landmark stop (Data.LANDMARK_STOPS). The valley behind the station is dammed: a concrete
# arch 44 m high from ridge to ridge, the reservoir behind it up to the crest, a gated spillway roaring
# down its face into a stilling basin, and at its foot the powerhouse (the penstocks coming down into
# it), the transformer yard and the pylons carrying the lines away over the ridge. A steel stair tower
# climbs the face to the crest road, its parapets, lamps and a hut with a safe in it. The lift goes down
# beside the powerhouse into its galleries (the DAM facility: dam_halls.gd).
# level.gd builds it in place of the usual landmark and keeps everything random off it (keep_out);
# line.gd raises the ridges round the reservoir (ridge()).
extends RefCounted

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const P = preload("res://src/props.gd")
const Sfx = preload("res://src/sfx.gd")
const Merge = preload("res://src/merge.gd")
const Landmarks = preload("res://src/landmarks.gd")

const CREST := 44.0        # the crest road above the valley floor
const R := 400.0           # the arch's radius (its centre downstream, toward the station)
const MID_Z := 96.0        # the upstream face, in the middle
const SPAN := 142.0        # how far out the abutments go (buried in the ridges)
const TOP_T := 7.0         # thick at the crest
const BASE_T := 20.0       # ...and at the foot
const FOOT := -6.0         # (the foundations, below the valley floor)
const SPILL := Vector2(24.0, 52.0)   # the spillway's bays (x)
const SPILL_DROP := 8.0    # its ogee crest, under the road bridge
const WATER := CREST - 2.5 # the reservoir
const LIFT := Vector3(-6.0, 0.0, 44.0)
const HOUSE := Rect2(-74.0, 48.0, 44.0, 16.0)   # the powerhouse (x, z, w, d)
const YARD := Rect2(-27.0, 49.0, 14.0, 13.0)    # the transformer yard
const BASIN := Rect2(18.0, 46.0, 40.0, 30.0)    # the stilling basin (its far wall under the face)
const STAIR := Vector3(-88.0, 0.0, 58.0)        # the stair tower's foot
const DARK := Color(0.3, 0.29, 0.27)
const CONC := Color(0.86, 0.85, 0.8)
const STEEL := Color(0.36, 0.4, 0.38)
const OXIDE := Color(0.55, 0.22, 0.14)   # the gates' red lead
const LAMP := Color(1.0, 0.76, 0.46)

static var _flow: ShaderMaterial
static var _churn: ShaderMaterial
static var _foam: ShaderMaterial
static var _lake: StandardMaterial3D
static var _pane: StandardMaterial3D


# --- the shape ------------------------------------------------------------------------------------

## The upstream face along the arch (z at x).
static func up_z(x: float) -> float:
	return MID_Z - R + sqrt(R * R - x * x)


## Downstream, along the ground, at x (toward the arch's centre).
static func out_n(x: float) -> Vector3:
	var d := (Vector2(0.0, MID_Z - R) - Vector2(x, up_z(x))).normalized()
	return Vector3(d.x, 0.0, d.y)


static func thick(y: float) -> float:
	return lerpf(BASE_T, TOP_T, y / CREST)


## A point on the downstream face (the batter leans it back as it rises).
static func face(x: float, y: float) -> Vector3:
	return Vector3(x, y, up_z(x)) + out_n(x) * thick(y)


static func toe_z(x: float) -> float:
	return face(x, 0.0).z


## The ridges either side of the reservoir and closing it off far behind (line.gd adds this to its
## ground; dx from the station, z as the stop has it).
static func ridge(dx: float, z: float) -> float:
	var ax := absf(dx)
	var sides := 74.0 * smoothstep(98.0, 152.0, ax) * smoothstep(28.0, 82.0, z) * (1.0 - smoothstep(320.0, 470.0, ax))
	var head := 58.0 * smoothstep(420.0, 560.0, z) * (1.0 - smoothstep(320.0, 470.0, ax))
	return maxf(sides, head)


## Nothing random goes here: the dam and the works at its foot.
static func keep_out(p: Vector3, r := 0.0) -> bool:
	if p.z > toe_z(clampf(p.x, -SPAN, SPAN)) - 7.0 - r:
		return true
	for rect: Rect2 in [HOUSE.grow(7.0 + r), YARD.grow(5.0 + r), BASIN.grow(6.0 + r), Rect2(STAIR.x - 6.0, STAIR.z - 6.0, 12.0, 12.0).grow(r)]:
		if rect.has_point(Vector2(p.x, p.z)):
			return true
	return Vector2(p.x - LIFT.x, p.z - LIFT.z).length() < 9.0 + r


## Ground kept level for the works: [centre, radius] (level._flat).
static func flats() -> Array:
	return [[HOUSE.get_center(), 28.0], [YARD.get_center(), 10.0], [BASIN.get_center(), 24.0], [Vector2(STAIR.x, STAIR.z), 8.0],
		[Vector2(STAIR.x + 14.0, STAIR.z - 6.0), 9.0]]


## The basin's pit (level.ground_y): below the floor inside, the floor's own level outside.
static func basin_floor(x: float, z: float) -> float:
	var r := BASIN.grow(-0.5)
	return -3.9 if r.has_point(Vector2(x, z)) else INF


# --- building it ----------------------------------------------------------------------------------

## Everything. Returns the loot spots (level coordinates).
static func build(lv: Node3D, rng: RandomNumberGenerator, name: String) -> Array:
	var spots: Array = []
	_body(lv)
	_crest(lv, rng)
	_face_dressing(lv, rng)
	_spillway(lv, rng)
	_basin(lv, rng)
	_intakes(lv, rng)
	_reservoir(lv)
	spots.append_array(_powerhouse(lv, rng, name))
	spots.append_array(_yard(lv, rng))
	spots.append_array(_stairs(lv, rng))
	spots.append_array(_crest_hut(lv, rng))
	_abutments(lv, rng)
	_pylons(lv, rng)
	_floodlights(lv)
	return spots


## A frame on the face at (x, y): +z out of it, +y up it (tilted with the batter) unless `level`.
static func _on_face(lv: Node3D, x: float, y: float, level := false) -> Node3D:
	var n := out_n(x)
	var r := Node3D.new()
	lv.add_child(r)
	r.position = face(x, y)
	r.rotation = Vector3(0.0 if level else -atan2(BASE_T - TOP_T, CREST), atan2(n.x, n.z), 0.0)
	return r


## A frame on the crest at x: +z downstream, +x along the arch, y at the road.
static func _on_crest(lv: Node3D, x: float, depth := 0.5) -> Node3D:
	var n := out_n(x)
	var r := Node3D.new()
	lv.add_child(r)
	r.position = Vector3(x, CREST, up_z(x)) + n * (TOP_T * depth)
	r.rotation.y = atan2(n.x, n.z)
	return r


## The mass of the dam: the downstream face battered back, the crest, the upstream face, from ridge to
## ridge; the spillway's span cut down to its ogee crest under the road. One mesh (and its collision).
static func _body(lv: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for span in [[-SPAN, SPILL.x, CREST], [SPILL.x, SPILL.y, CREST - SPILL_DROP], [SPILL.y, SPAN, CREST]]:
		var x0: float = span[0]
		var x1: float = span[1]
		var top: float = span[2]
		var n := maxi(2, int((x1 - x0) / 5.0))
		var prev := {}
		for i in n + 1:
			var x := lerpf(x0, x1, float(i) / n)
			var nn := out_n(x)
			var u := Vector3(x, 0.0, up_z(x))
			var cut := {"u0": u + Vector3(0, FOOT, 0), "u1": u + Vector3(0, top, 0),
				"d0": face(x, FOOT), "d1": Vector3(x, top, up_z(x)) + nn * thick(top)}
			if not prev.is_empty():
				_quad(st, prev.d0, cut.d0, cut.d1, prev.d1, nn)                 # downstream face
				_quad(st, prev.d1, cut.d1, cut.u1, prev.u1, Vector3.UP)         # the top
				_quad(st, prev.u1, cut.u1, cut.u0, prev.u0, -nn)                # upstream face
			if i == 0 or i == n:   # the end of a span: closed off (the spillway's cheeks)
				var side := Vector3(-1, 0, 0) if i == 0 else Vector3(1, 0, 0)
				_quad(st, cut.u0, cut.u1, cut.d1, cut.d0, side)
			prev = cut
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m: StandardMaterial3D = A.mat("formwork", CONC, 6.0).duplicate()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.uv1_world_triplanar = true
	mi.material_override = m
	Merge.live(mi)
	lv.add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	lv.add_child(body)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3) -> void:
	var n := (b - a).cross(d - a).normalized()
	if n.dot(want) < 0.0:
		n = -n
	for v in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.add_vertex(v)


## The crest road: asphalt between parapets with copings, kerbs, lamp standards, joints across it; the
## road bridge over the spillway on its piers.
static func _crest(lv: Node3D, rng: RandomNumberGenerator) -> void:
	var step := 6.0
	var x := -SPAN + 6.0
	var k := 0
	while x < SPAN - 6.0:
		var x1 := minf(x + step, SPAN - 6.0)
		var mid := (x + x1) / 2.0
		var r := _on_crest(lv, mid)
		var ln := x1 - x + 0.08
		var spill := mid > SPILL.x - 0.5 and mid < SPILL.y + 0.5
		if not spill:
			A.box(r, Vector3(ln, 0.1, TOP_T - 1.0), Vector3(0, 0.05, 0), "asphalt", Color(0.85, 0.85, 0.85), false, 3.0)
			A.box(r, Vector3(0.1, 0.11, TOP_T - 1.0), Vector3(-ln / 2.0, 0.055, 0), "concrete", DARK, false)   # a joint across
		for s: float in [-1.0, 1.0]:   # the parapets, a coping on each
			if s > 0.0 and absf(mid - STAIR.x) < 3.2:
				for e: float in [-1.0, 1.0]:   # (a gap where the stair tower's catwalk comes in, a post each side)
					A.box(r, Vector3(0.36, 1.25, 0.5), Vector3(e * 1.0, 0.62, TOP_T / 2.0 - 0.22), "concrete", CONC.darkened(0.08), true)
				A.box(r, Vector3(2.0 - 0.3, 0.12, 0.36), Vector3(0, 0.06, TOP_T / 2.0 - 0.22), "concrete", CONC, false)
				continue
			var z := s * (TOP_T / 2.0 - 0.22)
			A.box(r, Vector3(ln, 1.05, 0.36), Vector3(0, 0.52, z), "formwork", CONC.darkened(0.04), true, 3.0)
			A.box(r, Vector3(ln, 0.09, 0.48), Vector3(0, 1.09, z), "concrete", Color(0.8, 0.79, 0.75), false, 2.0)
			A.box(r, Vector3(ln, 0.18, 0.25), Vector3(0, 0.09, z - s * 0.3), "concrete", Color(0.7, 0.69, 0.66), false, 2.0)   # the kerb
		if k % 4 == 1 and not spill and absf(mid) < 96.0:   # lamp standards on the downstream side
			A.lamp_post(r, Vector3(0, 0.0, TOP_T / 2.0 - 0.75), LAMP).visible = absf(mid) < 70.0   # (the far ones dark)
		x = x1
		k += 1
	# The road bridge across the spillway: its deck on the piers, parapets of railing.
	for bay in 4:
		var bx := SPILL.x + 3.5 + bay * 7.0
		var r := _on_crest(lv, bx)
		A.box(r, Vector3(7.06, 1.0, TOP_T - 0.4), Vector3(0, -0.5, 0), "concrete", CONC.darkened(0.06), true, 2.0)
		A.box(r, Vector3(7.06, 0.1, TOP_T - 1.0), Vector3(0, 0.05, 0), "asphalt", Color(0.85, 0.85, 0.85), false, 3.0)
		for s: float in [-1.0, 1.0]:
			var z := s * (TOP_T / 2.0 - 0.25)
			for p in 4:
				A.box(r, Vector3(0.1, 1.1, 0.1), Vector3(-3.0 + p * 2.0, 0.55, z), "metal", STEEL, false)
			A.box(r, Vector3(7.06, 0.08, 0.08), Vector3(0, 1.05, z), "metal", STEEL, false)
			A.box(r, Vector3(7.06, 0.06, 0.06), Vector3(0, 0.6, z), "metal", STEEL, false)
			B.invisible_wall(r, Vector3(7.06, 1.4, 0.2), Vector3(0, 0.7, z))
	# The ends: the road runs into rock; nobody walks out onto the ridges.
	for s: float in [-1.0, 1.0]:
		var ex := s * 96.0
		var r := _on_crest(lv, ex)
		B.invisible_wall(r, Vector3(0.6, 6.0, TOP_T + 2.0), Vector3(0, 3.0, 0))
		A.box(r, Vector3(0.3, 1.2, TOP_T - 1.2), Vector3(s * 0.3, 0.6, 0), "metal", Color(0.72, 0.62, 0.2), false)   # a barrier, striped
		for b in 4:
			A.box(r, Vector3(0.32, 0.24, 0.8), Vector3(s * 0.3, 0.75, -2.4 + b * 1.6), "metal", Color(0.12, 0.12, 0.12), false)


## The downstream face: a joint between every block, inspection galleries with their doors and
## balconies, drain outlets and the streaks under them, a name in big letters.
static func _face_dressing(lv: Node3D, rng: RandomNumberGenerator) -> void:
	var x := -SPAN + 15.0
	while x < SPAN:   # contraction joints, every 15 m
		if x < SPILL.x - 1.0 or x > SPILL.y + 1.0:
			var r := _on_face(lv, x, 0.0)
			var ln := Vector2(BASE_T - TOP_T, CREST).length()
			A.box(r, Vector3(0.14, ln, 0.04), Vector3(0, ln / 2.0, 0.02), "concrete", DARK, false, 2.0)
		x += 15.0
	for g in [[-62.0, 15.0], [-20.0, 29.0], [86.0, 21.0], [-104.0, 31.0]]:   # gallery doors, a balcony each
		var r := _on_face(lv, g[0], g[1], true)
		A.box(r, Vector3(1.4, 2.4, 0.5), Vector3(0, 1.2, -0.05), "concrete", CONC.darkened(0.15), false)
		A.box(r, Vector3(1.0, 2.1, 0.08), Vector3(0, 1.05, 0.22), "riveted", Color(0.3, 0.36, 0.34), false, 0.6)
		A.box(r, Vector3(3.0, 0.2, 1.4), Vector3(0, -0.1, 0.85), "concrete", CONC.darkened(0.08), false)
		for s: float in [-1.0, 1.0]:
			A.seg(r, Vector3(s * 1.45, -0.1, 0.3), Vector3(s * 1.45, -1.1, 0.05), 0.06, 0.06, "metal", STEEL)   # the brackets
		for p in [Vector3(-1.45, 0, 1.5), Vector3(1.45, 0, 1.5), Vector3(-1.45, 0, 0.3), Vector3(1.45, 0, 0.3)]:
			A.box(r, Vector3(0.06, 1.0, 0.06), p + Vector3(0, 0.5, 0), "metal", STEEL, false)
		A.box(r, Vector3(2.96, 0.05, 0.05), Vector3(0, 1.0, 1.5), "metal", STEEL, false)
		for s: float in [-1.0, 1.0]:
			A.box(r, Vector3(0.05, 0.05, 1.2), Vector3(s * 1.45, 1.0, 0.9), "metal", STEEL, false)
		A.glow(r, Vector3(0.24, 0.12, 0.08), Vector3(0, 2.55, 0.25), LAMP, 2.0)
	for i in 34:   # streaks of water and lime down the face from the crest drains
		var sx := rng.randf_range(-SPAN + 8.0, SPAN - 8.0)
		if sx > SPILL.x - 3.0 and sx < SPILL.y + 3.0:
			continue
		var ln := rng.randf_range(4.0, 26.0)
		var r := _on_face(lv, sx, CREST - 0.6)
		var c := DARK.lerp(Color(0.42, 0.36, 0.3), rng.randf()) if rng.randf() < 0.7 else Color(0.85, 0.84, 0.78)
		A.box(r, Vector3(rng.randf_range(0.2, 0.9), ln, 0.03), Vector3(0, -ln / 2.0, 0.02), "concrete", c, false, 2.0)
		A.cyl(r, 0.12, 0.6, Vector3(0, -0.1, 0.3), "metal", STEEL.darkened(0.2), false, "z")   # the drain's spout
	var name_at := _on_face(lv, -58.0, CREST - 7.5)
	B.label(name_at, "B.R.M. HYDRO", Vector3(0, 0, 0.05), 900, Color(0.92, 0.9, 0.84), "stencil", 0.006)
	var year := _on_face(lv, 76.0, CREST - 7.5)
	B.label(year, "1938", Vector3(0, 0, 0.05), 700, Color(0.92, 0.9, 0.84), "stencil", 0.006)


## The spillway: piers carrying the road over four radial gates (red lead, cracked open), the water
## coming out under them over the ogee, down the chute between its training walls in a white sheet.
static func _spillway(lv: Node3D, rng: RandomNumberGenerator) -> void:
	var low := CREST - SPILL_DROP
	for p in 5:   # the piers: rounded noses into the reservoir, the hoist deck on their tops
		var px := SPILL.x + p * 7.0
		var r := _on_crest(lv, px, 0.0)
		var h := SPILL_DROP + 6.0
		A.box(r, Vector3(1.6, h, TOP_T + 3.0), Vector3(0, h / 2.0 - SPILL_DROP, TOP_T / 2.0 - 1.5), "formwork", CONC, true, 3.0)
		A.cyl(r, 0.8, h, Vector3(0, h / 2.0 - SPILL_DROP, -3.0), "formwork", CONC, true)
		for s: float in [-1.0, 1.0]:   # the gates' trunnion pins in the pier sides
			A.cyl(r, 0.35, 0.3, Vector3(s * 0.9, -2.5, TOP_T - 1.2), "metal", STEEL.darkened(0.2), false, "x")
	var deck := _on_crest(lv, (SPILL.x + SPILL.y) / 2.0, 0.0)   # the hoist deck: four winch houses in a row
	A.box(deck, Vector3(SPILL.y - SPILL.x + 2.0, 0.6, 4.0), Vector3(0, 6.3, 0.2), "concrete", CONC.darkened(0.05), false, 2.0)
	for g in 4:
		var gx := -10.5 + g * 7.0
		A.box(deck, Vector3(3.6, 2.4, 3.0), Vector3(gx, 7.8, 0.2), "corrugated", Color(0.55, 0.6, 0.55), false, 1.5)
		A.box(deck, Vector3(3.9, 0.15, 3.3), Vector3(gx, 9.05, 0.2), "metal", STEEL.darkened(0.1), false)
		A.box(deck, Vector3(0.9, 0.7, 0.05), Vector3(gx + 0.8, 8.1, 1.73), "metal", Color(0.12, 0.13, 0.12), false)   # a window
		for s: float in [-1.0, 1.0]:   # hoist chains down to the gate
			A.seg(deck, Vector3(gx + s * 1.2, 6.0, 1.6), Vector3(gx + s * 1.2, -1.5, 2.8), 0.05, 0.05, "metal", Color(0.25, 0.25, 0.24))
	for g in 4:   # the gates: curved skins facing the water, arms back to the trunnions; each up a metre
		var gx := SPILL.x + 3.5 + g * 7.0
		var r := _on_crest(lv, gx, 0.0)
		var lift := 1.0 + rng.randf_range(-0.2, 0.3)
		var y0 := low - CREST + lift   # its bottom edge, a metre or so off the ogee
		for k in 6:   # the skin, in strakes, curving back toward the top
			var y := y0 + 0.45 + k * 0.92
			var z := 2.2 + pow(k * 0.92, 2.0) * 0.035
			A.box(r, Vector3(5.9, 0.95, 0.12), Vector3(0, y, z), "riveted", OXIDE, false, 0.8, Vector3(-0.08 * k, 0, 0))
		A.box(r, Vector3(5.9, 0.16, 0.3), Vector3(0, y0 + 0.08, 2.25), "metal", OXIDE.darkened(0.35), false)   # the bottom seal
		for s: float in [-1.0, 1.0]:   # the arms back to the trunnion pins in the piers
			A.seg(r, Vector3(s * 2.6, -2.5, TOP_T - 1.2), Vector3(s * 2.6, y0 + 0.9, 2.4), 0.13, 0.13, "riveted", OXIDE.darkened(0.2))
			A.seg(r, Vector3(s * 2.6, -2.5, TOP_T - 1.2), Vector3(s * 2.6, y0 + 4.9, 2.9), 0.13, 0.13, "riveted", OXIDE.darkened(0.2))
	# The chute: training walls down both sides, the sheet of water between them.
	var top := low - 0.2
	var len := Vector2(thick(FOOT) - thick(top), top - FOOT).length()
	for wx: float in [SPILL.x - 0.4, SPILL.y + 0.4]:
		var r := _on_face(lv, wx, FOOT)
		A.box(r, Vector3(0.8, len + 2.0, 1.8), Vector3(0, len / 2.0 + 1.0, 0.9), "formwork", CONC, true, 3.0)
	_spill_water(lv, low, rng)


## The water through the spillway, as one sheet: drawn down off the reservoir toward the gates, out
## under their lips, curling over the ogee, down the chute (faster, rougher, whiter as it falls) and
## round the bucket at the foot out onto the basin. UV in metres (u across, v along it); UV2.x how
## far down the face it is (0 at the crest, 1 at the foot; below 0 still the reservoir), UV2.y the
## plunge (white through).
static func _spill_water(lv: Node3D, low: float, rng: RandomNumberGenerator) -> void:
	if _flow == null:
		_flow = _water_mat(FLOW)
		_churn = _water_mat(CHURN)
		_foam = _water_mat(FOAM)
	var cols := 40
	var paths: Array = []
	for i in cols + 1:
		var x := lerpf(SPILL.x + 0.02, SPILL.y - 0.02, float(i) / cols)
		paths.append(_spill_path(x, low))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: int = paths[0].size()
	var vlen := []   # arc length down each column
	for path in paths:
		var acc := [0.0]
		for r in range(1, rows):
			acc.append(acc[r - 1] + (path[r][0] as Vector3).distance_to(path[r - 1][0]))
		vlen.append(acc)
	for i in cols:
		for r in rows - 1:
			var quad := [[i, r], [i + 1, r], [i + 1, r + 1], [i, r + 1]]
			var a: Vector3 = paths[i][r][0]
			var b: Vector3 = paths[i + 1][r][0]
			var d: Vector3 = paths[i][r + 1][0]
			var nrm := (b - a).cross(d - a).normalized()
			if nrm.y < 0.0 and nrm.dot(out_n(a.x)) < 0.0:
				nrm = -nrm
			for t in [0, 1, 2, 0, 2, 3]:
				var c: Array = quad[t]
				var row: Array = paths[c[0]][c[1]]
				var pos: Vector3 = row[0]
				st.set_uv(Vector2(pos.x, vlen[c[0]][c[1]]))
				st.set_uv2(Vector2(row[1], row[2]))
				st.set_normal(nrm)
				st.add_vertex(pos)
	var sheet := MeshInstance3D.new()
	sheet.mesh = st.commit()
	sheet.material_override = _flow
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Merge.live(sheet)
	lv.add_child(sheet)
	var top := AudioStreamPlayer3D.new()   # the roar at the gates too, thinner
	top.stream = Sfx.stream("waterfall")
	top.bus = "World"
	top.unit_size = 14.0
	top.max_distance = 120.0
	top.volume_db = -4.0
	top.pitch_scale = 1.35
	top.autoplay = true
	lv.add_child(top)
	top.position = Vector3((SPILL.x + SPILL.y) / 2.0, low, up_z((SPILL.x + SPILL.y) / 2.0)) + out_n((SPILL.x + SPILL.y) / 2.0) * 6.0


## One column of the sheet: [position, down-the-face 0..1, plunge 0..1] from the reservoir to the basin.
static func _spill_path(x: float, low: float) -> Array:
	var n := out_n(x)
	var u := Vector3(x, 0.0, up_z(x))
	var rows := []
	rows.append([u - n * 10.0 + Vector3(0, WATER - 0.03, 0), -0.5, 0.0])   # still the reservoir (under its surface)
	rows.append([u - n * 4.0 + Vector3(0, WATER - 0.2, 0), -0.4, 0.0])
	rows.append([u - n * 1.0 + Vector3(0, WATER - 0.9, 0), -0.3, 0.0])     # drawn down toward the gates
	rows.append([u + n * 0.9 + Vector3(0, WATER - 2.3, 0), -0.2, 0.0])
	rows.append([u + n * 2.4 + Vector3(0, low + 1.05, 0), -0.08, 0.0])     # out under the gate's lip
	rows.append([u + n * 4.6 + Vector3(0, low + 0.7, 0), 0.0, 0.0])        # over the ogee
	rows.append([u + n * (thick(low) - 0.6) + Vector3(0, low + 0.35, 0), 0.03, 0.0])
	rows.append([u + n * (thick(low) + 0.35) + Vector3(0, low - 0.35, 0), 0.06, 0.0])   # curling onto the face
	for k in 10:
		var y := lerpf(low - 1.6, 1.1, float(k) / 9.0)
		var down := 1.0 - y / low
		rows.append([face(x, y) + n * (0.3 + 0.55 * down), 0.08 + 0.92 * down, 0.0])   # (thicker and rougher lower down)
	rows.append([face(x, 0.0) + n * 1.2 + Vector3(0, -0.05, 0), 1.0, 0.45])   # round the bucket at the foot
	rows.append([face(x, 0.0) + n * 2.8 + Vector3(0, -0.45, 0), 1.0, 1.0])
	rows.append([face(x, 0.0) + n * 5.0 + Vector3(0, -0.66, 0), 1.0, 0.8])
	rows.append([face(x, 0.0) + n * 7.5 + Vector3(0, -0.69, 0), 1.0, 0.4])    # and out onto the basin
	return rows


## The stilling basin at the foot of the chute: concrete walls, the water boiling white where the
## sheet comes down and settling toward the far end, spray hanging over it all, the roar.
static func _basin(lv: Node3D, rng: RandomNumberGenerator) -> void:
	var b := BASIN
	var top := 0.9
	var wall_kind := "formwork"
	for s in [[Vector3(b.position.x - 0.5, 0, b.get_center().y), Vector3(1.0, 0, b.size.y + 1.0)], [Vector3(b.end.x + 0.5, 0, b.get_center().y), Vector3(1.0, 0, b.size.y + 1.0)],
			[Vector3(b.get_center().x, 0, b.position.y - 0.5), Vector3(b.size.x + 2.0, 0, 1.0)]]:
		var at: Vector3 = s[0]
		var sz: Vector3 = s[1]
		A.box(lv, Vector3(sz.x, top + 4.2, sz.z), at + Vector3(0, (top - 4.2) / 2.0 + 0.0, 0), wall_kind, CONC, true, 3.0)
		A.box(lv, Vector3(sz.x + 0.1, 0.12, sz.z + 0.1), at + Vector3(0, top + 0.06, 0), "concrete", Color(0.78, 0.77, 0.73), false)
	A.box(lv, Vector3(b.size.x, 0.4, b.size.y), Vector3(b.get_center().x, -3.4, b.get_center().y), "concrete", DARK, false, 3.0)
	for k in 6:   # the baffle blocks on its floor, breaking the water up
		A.box(lv, Vector3(2.0, 1.6, 2.0), Vector3(b.position.x + 5.0 + k * 6.0, -2.4, b.end.y - 12.0), "formwork", CONC.darkened(0.2), false, 2.0)
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = b.size
	pm.subdivide_width = 48
	pm.subdivide_depth = 36
	water.mesh = pm
	water.material_override = _churn
	_churn.set_shader_parameter("size", b.size)
	_churn.set_shader_parameter("drain", Vector2((b.end.x - 6.0 - b.position.x) / b.size.x, 3.0))
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Merge.live(water)
	lv.add_child(water)
	water.position = Vector3(b.get_center().x, -0.7, b.get_center().y)
	# The roller where the sheet lands: a long churning hump of white across the foot of the chute.
	var mid := (SPILL.x + SPILL.y) / 2.0
	var roll := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = SPILL.y - SPILL.x - 0.6
	cm.radial_segments = 20
	cm.rings = 24
	roll.mesh = cm
	roll.material_override = _foam
	roll.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Merge.live(roll)
	lv.add_child(roll)
	roll.position = face(mid, 0.0) + out_n(mid) * 3.6 + Vector3(0, -0.85, 0)
	roll.rotation = Vector3(0, atan2(out_n(mid).x, out_n(mid).z), PI / 2.0)
	roll.scale = Vector3(0.7, 1.0, 2.4)   # (low, and stretched out along the flow)
	# Spray thrown up off it, and droplets falling back.
	var drops := CPUParticles3D.new()
	drops.amount = 220
	drops.lifetime = 1.6
	drops.preprocess = 2.0
	drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drops.emission_box_extents = Vector3((SPILL.y - SPILL.x) * 0.48, 0.3, 1.2)
	drops.direction = out_n(mid) + Vector3(0, 1.6, 0)
	drops.spread = 32.0
	drops.initial_velocity_min = 3.5
	drops.initial_velocity_max = 8.0
	drops.gravity = Vector3(0, -9.8, 0)
	drops.scale_amount_min = 0.1
	drops.scale_amount_max = 0.32
	var dr := Gradient.new()
	dr.set_color(0, Color(0.95, 0.97, 0.96, 0.55))
	dr.set_color(dr.get_point_count() - 1, Color(0.95, 0.97, 0.96, 0.0))
	drops.color_ramp = dr
	drops.mesh = _puff()
	lv.add_child(drops)
	drops.position = face(mid, 0.0) + out_n(mid) * 2.6 + Vector3(0, -0.2, 0)
	drops.emitting = true
	# The culvert it drains through: an arch in the near wall, a grille across it.
	var cx := b.end.x - 6.0
	A.box(lv, Vector3(4.6, 3.0, 0.3), Vector3(cx, -0.5, b.position.y - 1.05), "concrete", Color(0.08, 0.08, 0.08), false)
	A.box(lv, Vector3(4.4, 2.6, 0.12), Vector3(cx, -0.6, b.position.y - 1.1), "grate", Color(0.4, 0.4, 0.38), false, 0.5)
	# Railings all round (solid: nobody goes in), signs on them.
	var rail := func(a: Vector3, c: Vector3) -> void:
		var d := c - a
		var n := int(d.length() / 2.5)
		for i in n + 1:
			A.box(lv, Vector3(0.07, 1.1, 0.07), a + d * (float(i) / n) + Vector3(0, top + 0.55, 0), "metal", Color(0.75, 0.62, 0.18), false)
		for y: float in [0.55, 1.08]:
			A.box(lv, Vector3(absf(d.x) + 0.07, 0.06, absf(d.z) + 0.07), (a + c) / 2.0 + Vector3(0, top + y, 0), "metal", Color(0.75, 0.62, 0.18), false)
		B.invisible_wall(lv, Vector3(absf(d.x) + 0.1, 2.4, absf(d.z) + 0.1), (a + c) / 2.0 + Vector3(0, top + 1.2, 0))
	rail.call(Vector3(b.position.x - 0.5, 0, b.position.y - 0.5), Vector3(b.end.x + 0.5, 0, b.position.y - 0.5))
	rail.call(Vector3(b.position.x - 0.5, 0, b.position.y - 0.5), Vector3(b.position.x - 0.5, 0, b.end.y))
	rail.call(Vector3(b.end.x + 0.5, 0, b.position.y - 0.5), Vector3(b.end.x + 0.5, 0, b.end.y))
	for sx: float in [b.position.x + 8.0, b.end.x - 14.0]:
		var sign := A.root(lv, Vector3(sx, top + 0.85, b.position.y - 0.62), PI)
		A.box(sign, Vector3(1.8, 0.7, 0.04), Vector3.ZERO, "enamel", Color(0.92, 0.9, 0.84), false, 0.6)
		A.box(sign, Vector3(1.8, 0.18, 0.045), Vector3(0, 0.26, 0), "enamel", Color(0.7, 0.12, 0.1), false, 0.6)
		B.label(sign, "DANGER", Vector3(0, 0.26, 0.03), 40, Color(0.95, 0.92, 0.85), "stencil", 0.0045)
		B.label(sign, "SPILLWAY - KEEP OUT", Vector3(0, -0.06, 0.03), 34, Color(0.15, 0.13, 0.12), "stencil", 0.0042)
	# Mist: big slow clouds rolling up off the plunge and drifting out over the basin, catching the light.
	for k in 2:
		var mist := CPUParticles3D.new()
		mist.amount = 30
		mist.lifetime = 7.0
		mist.preprocess = 7.0
		mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		mist.emission_box_extents = Vector3((SPILL.y - SPILL.x) * 0.5, 0.6, 2.0)
		mist.direction = out_n(mid) + Vector3(0, 0.9 - k * 0.4, 0)
		mist.spread = 25.0
		mist.initial_velocity_min = 1.2
		mist.initial_velocity_max = 3.2
		mist.gravity = Vector3(0, 0.12, 0)
		mist.damping_min = 0.25
		mist.damping_max = 0.45
		mist.scale_amount_min = 4.0 + k * 3.0
		mist.scale_amount_max = 8.0 + k * 5.0
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.92, 0.94, 0.94, 0.0))
		ramp.add_point(0.15, Color(0.92, 0.94, 0.94, 0.32 - k * 0.12))
		ramp.set_color(ramp.get_point_count() - 1, Color(0.92, 0.94, 0.94, 0.0))
		mist.color_ramp = ramp
		mist.mesh = _puff()
		lv.add_child(mist)
		mist.position = face(mid, 0.0) + out_n(mid) * (2.0 + k * 4.0) + Vector3(0, 0.6 + k * 1.5, 0)
		mist.emitting = true
	# The drain: the water slides over a lip into the culvert under the near wall.
	var cxx := b.end.x - 6.0
	var drain := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lip := [[b.position.y + 1.6, -0.7, 0.0], [b.position.y + 0.2, -0.78, 0.2], [b.position.y - 0.6, -1.4, 0.6], [b.position.y - 1.2, -2.2, 1.0]]
	for k in lip.size() - 1:
		for t in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
			var row: Array = lip[k + t[1]]
			var x: float = cxx + (t[0] - 0.5) * 4.2
			st.set_uv(Vector2(x, float(k + t[1]) * 0.9))
			st.set_uv2(Vector2(row[2], 0.0))
			st.set_normal(Vector3(0, 1, 0.3).normalized())
			st.add_vertex(Vector3(x, row[1], row[0]))
	drain.mesh = st.commit()
	drain.material_override = _flow
	Merge.live(drain)
	lv.add_child(drain)
	var mists: Array = []
	for m in lv.get_children():
		if m is CPUParticles3D:
			mists.append(m)
	lv.set_meta("dam_mist", mists)   # (site_clock.gd opens it right out at 18:00)
	var roar := AudioStreamPlayer3D.new()
	roar.stream = Sfx.stream("waterfall")
	roar.bus = "World"
	roar.unit_size = 34.0
	roar.max_distance = 260.0
	roar.volume_db = 2.0
	roar.autoplay = true
	lv.add_child(roar)
	roar.position = Vector3(b.get_center().x, 2.0, b.end.y - 2.0)
	lv.set_meta("dam_roar", roar)


## A soft round puff (spray, mist): a radial gradient on a quad that always faces you.
static func _puff() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var g := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	g.gradient = gr
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(0.5, 0.0)
	m.albedo_texture = g
	q.material = m
	return q


## The intake towers out in the reservoir: round concrete shafts with a gatehouse on top, a steel
## truss bridge to each from the crest. (They feed the penstocks.)
static func _intakes(lv: Node3D, rng: RandomNumberGenerator) -> void:
	for tx: float in [-70.0, -42.0]:
		var c := Vector3(tx, 0, up_z(tx) + 19.0)
		A.cyl(lv, 4.2, CREST + 10.0 - FOOT, c + Vector3(0, (CREST + 10.0 + FOOT) / 2.0, 0), "formwork", CONC, true)
		for y: float in [CREST - 6.0, CREST + 2.0]:
			A.cyl(lv, 4.4, 0.4, c + Vector3(0, y, 0), "concrete", CONC.darkened(0.06), false)
		var top := c + Vector3(0, CREST + 10.0, 0)
		var house := A.root(lv, top, atan2(out_n(tx).x, out_n(tx).z))
		A.box(house, Vector3(7.0, 4.2, 7.0), Vector3(0, 2.1, 0), "brick", Color(0.78, 0.6, 0.5), true, 2.0)
		for s: float in [-1.0, 1.0]:
			for w: float in [-1.6, 1.6]:
				A.box(house, Vector3(1.0, 1.8, 0.06), Vector3(w, 2.3, s * 3.53), "metal", Color(0.1, 0.11, 0.11), false)
				A.box(house, Vector3(1.2, 0.12, 0.2), Vector3(w, 1.35, s * 3.6), "concrete", Color(0.8, 0.78, 0.74), false)
		A.box(house, Vector3(7.8, 0.3, 7.8), Vector3(0, 4.35, 0), "concrete", CONC.darkened(0.1), false)
		A.prism(house, Vector3(7.6, 2.0, 7.6), Vector3(0, 5.5, 0), "corrugated", Color(0.45, 0.5, 0.48), Vector3.ZERO, 1.5)
		A.cyl(house, 0.06, 4.0, Vector3(2.8, 8.0, 2.8), "metal", STEEL)   # a mast
		# The bridge back to the crest, on its trusses.
		var a := Vector3(tx, CREST, up_z(tx))
		var d := Vector3(top.x, CREST, top.z - 4.2)
		var mid := (a + d) / 2.0
		var br := A.root(lv, mid, atan2(d.x - a.x, d.z - a.z))
		var ln := a.distance_to(d)
		A.box(br, Vector3(1.8, 0.15, ln), Vector3(0, 0.0, 0), "grate", Color(0.45, 0.45, 0.42), false, 0.5)
		for s: float in [-1.0, 1.0]:
			A.box(br, Vector3(0.12, 0.5, ln), Vector3(s * 0.95, -0.35, 0), "metal", STEEL, false)
			A.box(br, Vector3(0.06, 0.06, ln), Vector3(s * 0.95, 1.05, 0), "metal", STEEL, false)
			var n := int(ln / 1.6)
			for i in n + 1:
				var z := -ln / 2.0 + ln * float(i) / n
				A.box(br, Vector3(0.05, 1.05, 0.05), Vector3(s * 0.95, 0.52, z), "metal", STEEL, false)
				if i < n:
					A.seg(br, Vector3(s * 0.95, -0.6, z), Vector3(s * 0.95, -0.1, z + ln / n), 0.03, 0.03, "metal", STEEL)
		for s: float in [-0.3, 0.3]:   # a ladder up the tower to the gatehouse
			A.box(lv, Vector3(0.05, 10.0, 0.05), d + Vector3(s, 5.0, -0.15), "metal", STEEL, false)
		for k in 25:
			A.box(lv, Vector3(0.6, 0.04, 0.04), d + Vector3(0, 0.3 + k * 0.4, -0.15), "metal", STEEL, false)


## The reservoir: still dark water from the upstream face away up the valley between the ridges.
static func _reservoir(lv: Node3D) -> void:
	if _lake == null:
		_lake = StandardMaterial3D.new()
		_lake.albedo_color = Color(0.1, 0.14, 0.15)
		_lake.roughness = 0.04
		_lake.metallic_specular = 1.0
		_lake.metallic = 0.15
		var nt := NoiseTexture2D.new()
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 4.0
		var fn := FastNoiseLite.new()
		fn.frequency = 0.02
		nt.noise = fn
		_lake.normal_enabled = true
		_lake.normal_texture = nt
		_lake.normal_scale = 0.35
		_lake.uv1_triplanar = true
		_lake.uv1_world_triplanar = true
		_lake.uv1_scale = Vector3.ONE * 0.04
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 40
	var far := 760.0
	for i in n:
		var xa := lerpf(-260.0, 260.0, float(i) / n)
		var xb := lerpf(-260.0, 260.0, float(i + 1) / n)
		var za := up_z(clampf(xa, -SPAN, SPAN)) - 0.3
		var zb := up_z(clampf(xb, -SPAN, SPAN)) - 0.3
		for v in [Vector3(xa, WATER, za), Vector3(xb, WATER, zb), Vector3(xb, WATER, far), Vector3(xa, WATER, za), Vector3(xb, WATER, far), Vector3(xa, WATER, far)]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _lake
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Merge.live(mi)
	lv.add_child(mi)


## The powerhouse at the dam's foot: brick on a concrete plinth, tall windows between pilasters, a
## cornice with the name on it, a roof monitor; the penstocks coming down the face into its back; a
## roller door at the yard end. (Shut: its halls are down the lift.)
static func _powerhouse(lv: Node3D, rng: RandomNumberGenerator, name: String) -> Array:
	var h := HOUSE
	var hgt := 16.0
	var brick := Color(0.74, 0.52, 0.42)
	var stone := Color(0.84, 0.8, 0.72)
	var x0 := h.position.x
	var x1 := h.end.x
	var z0 := h.position.y
	var z1 := h.end.y
	var cx := h.get_center().x
	A.box(lv, Vector3(h.size.x + 1.2, 1.4, h.size.y + 1.2), Vector3(cx, 0.3, h.get_center().y), "concrete", CONC.darkened(0.08), true, 2.0)   # the plinth
	if _pane == null:
		_pane = StandardMaterial3D.new()
		_pane.albedo_color = Color(0.07, 0.09, 0.09)
		_pane.metallic = 0.6
		_pane.roughness = 0.12
	var bays := 6
	var bw := h.size.x / bays
	var win := []
	for k in bays:
		win.append([x0 + bw * (k + 0.5), 3.0, 3.2, 12.4])
	A.wall(lv, x0, x1, z0, hgt, 0.6, win, "brick", brick, true, 1.0, true, 1.6)   # the front, facing the station
	A.wall(lv, x0, x1, z1, hgt, 0.6, [], "brick", brick, true, 1.0, true, 1.6)
	A.wall(lv, z0, z1, x0, hgt, 0.6, [[h.get_center().y, 3.0, 4.0, 12.0]], "brick", brick, false, 1.0, true, 1.6)
	A.wall(lv, z0, z1, x1, hgt, 0.6, [[h.get_center().y, 6.0, 0.0, 7.0]], "brick", brick, false, 1.0, true, 1.6)
	for k in bays:   # each window: stone sill and head, a steel grid of panes (some out), pilasters between
		var wx: float = win[k][0]
		A.box(lv, Vector3(3.6, 0.3, 0.9), Vector3(wx, 4.1, z0 - 0.15), "concrete", stone, false)
		A.box(lv, Vector3(3.8, 0.7, 0.8), Vector3(wx, 13.75, z0 - 0.1), "concrete", stone, false)
		A.box(lv, Vector3(1.0, 0.7, 0.85), Vector3(wx, 13.85, z0 - 0.12), "concrete", stone.lightened(0.05), false)   # the keystone
		for c in 4:
			for rr in 7:
				var pane := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.7, 1.15, 0.03)
				pane.mesh = bm
				pane.material_override = _pane
				lv.add_child(pane)
				pane.position = Vector3(wx - 1.2 + c * 0.8, 4.85 + rr * 1.27, z0 + 0.05)
				pane.visible = rng.randf() > 0.12
		for c in 5:
			A.box(lv, Vector3(0.07, 9.2, 0.08), Vector3(wx - 1.6 + c * 0.8, 8.8, z0 + 0.02), "metal", STEEL.darkened(0.3), false)
		for rr in 8:
			A.box(lv, Vector3(3.2, 0.07, 0.08), Vector3(wx, 4.25 + rr * 1.27, z0 + 0.02), "metal", STEEL.darkened(0.3), false)
		if k > 0:
			A.box(lv, Vector3(1.1, hgt, 0.5), Vector3(x0 + bw * k, hgt / 2.0 + 1.0, z0 - 0.4), "brick", brick.darkened(0.05), true, 1.6)
	for c: float in [x0, x1]:
		A.box(lv, Vector3(1.6, hgt, 1.6), Vector3(c, hgt / 2.0 + 1.0, z0), "brick", brick.darkened(0.08), true, 1.6)
		A.box(lv, Vector3(1.6, hgt, 1.6), Vector3(c, hgt / 2.0 + 1.0, z1), "brick", brick.darkened(0.08), true, 1.6)
	# The cornice and its frieze with the name; a parapet; the flat roof and its monitor.
	A.box(lv, Vector3(h.size.x + 2.0, 1.6, 0.9), Vector3(cx, hgt + 0.6, z0 - 0.2), "concrete", stone, false, 2.0)
	A.box(lv, Vector3(h.size.x + 2.4, 0.35, 1.3), Vector3(cx, hgt + 1.55, z0 - 0.3), "concrete", stone.darkened(0.08), false, 2.0)
	B.label(lv, "%s  POWER STATION" % name, Vector3(cx, hgt + 0.6, z0 - 0.67), 120, Color(0.22, 0.2, 0.18), "plate", 0.012).rotation.y = PI
	A.box(lv, Vector3(h.size.x, 0.4, h.size.y), Vector3(cx, hgt + 1.0, h.get_center().y), "concrete", CONC.darkened(0.2), true, 3.0)
	A.box(lv, Vector3(h.size.x - 10.0, 2.6, 5.0), Vector3(cx, hgt + 2.5, h.get_center().y + 1.0), "corrugated", Color(0.5, 0.55, 0.52), false, 1.5)
	for k in 9:   # the monitor's louvres
		A.box(lv, Vector3(3.0, 1.4, 0.06), Vector3(x0 + 7.5 + k * 4.4, hgt + 2.6, h.get_center().y - 1.55), "metal", Color(0.2, 0.22, 0.2), false)
	A.box(lv, Vector3(h.size.x - 9.0, 0.3, 5.8), Vector3(cx, hgt + 3.9, h.get_center().y + 1.0), "metal", STEEL.darkened(0.2), false)
	for s: float in [x0 + 3.0, x1 - 3.0]:   # downpipes and their heads
		A.cyl(lv, 0.14, hgt + 1.0, Vector3(s, (hgt + 1.0) / 2.0, z0 - 0.45), "metal", Color(0.3, 0.32, 0.3))
		A.box(lv, Vector3(0.6, 0.5, 0.4), Vector3(s, hgt + 0.9, z0 - 0.5), "metal", Color(0.3, 0.32, 0.3), false)
	# The roller door at the yard end and a personnel door beside it, a canopy over that; lamps.
	A.box(lv, Vector3(0.2, 7.0, 6.0), Vector3(x1 + 0.2, 4.5, h.get_center().y), "corrugated", Color(0.5, 0.55, 0.52), false, 1.0)
	A.box(lv, Vector3(0.5, 0.8, 6.6), Vector3(x1 + 0.4, 8.4, h.get_center().y), "metal", STEEL.darkened(0.2), false)
	for k in 6:
		A.box(lv, Vector3(0.24, 0.05, 6.0), Vector3(x1 + 0.32, 1.6 + k * 1.1, h.get_center().y), "metal", Color(0.38, 0.42, 0.4), false)
	A.wall_lamp(lv, Vector3(x1 + 0.4, 9.3, h.get_center().y - 4.0), Vector3(1, 0, 0), LAMP, 1.2, false)
	var plate := A.root(lv, Vector3(cx, 3.2, z0 - 0.35), PI)
	A.box(plate, Vector3(4.8, 1.0, 0.06), Vector3.ZERO, "brass", Color(0.8, 0.64, 0.36), false, 0.5)
	B.label(plate, "BUREAU OF RECLAIMED MATERIALS", Vector3(0, 0.18, 0.04), 30, Color(0.25, 0.18, 0.1), "plate", 0.004)
	B.label(plate, "HYDRO-ELECTRIC DIVISION", Vector3(0, -0.2, 0.04), 26, Color(0.25, 0.18, 0.1), "plate", 0.004)
	# The penstocks: three steel pipes out of the face, down into the back wall, banded and on saddles.
	for k in 3:
		var px := x0 + 12.0 + k * 14.0
		var a := face(px, 17.0) + out_n(px) * 0.2
		var b := Vector3(px, 11.0, z1 + 0.6)
		var dir := (b - a).normalized()
		A.seg(lv, a - dir * 1.0, b + dir * 0.6, 1.25, 1.25, "riveted", Color(0.4, 0.46, 0.42))
		var n := int(a.distance_to(b) / 2.2)
		for i in n + 1:
			var ring := A.ring(lv, 1.42, 1.27, a.lerp(b, float(i) / n), "metal", Color(0.3, 0.34, 0.32))
			ring.basis = Basis(Quaternion(Vector3.UP, dir))
		A.box(lv, Vector3(3.6, 3.2, 2.4), b + Vector3(0, 0.0, 0.4), "formwork", CONC, true, 3.0)   # the anchor block at the wall
		var sad := a.lerp(b, 0.5)
		A.box(lv, Vector3(3.0, sad.y - 1.2, 1.4), Vector3(sad.x, (sad.y - 1.2) / 2.0, sad.z), "formwork", CONC.darkened(0.05), true, 3.0)   # a saddle pier
	return [Vector3(x1 + 3.0, 0.4, h.get_center().y + 4.5), Vector3(x0 + 4.0, 0.4, z0 - 3.0)]


## The transformer yard: three big transformers (radiators, a conservator, bushings), a steel gantry
## with insulator strings the lines leave from, gravel, a fence round it, a hazard sign.
static func _yard(lv: Node3D, rng: RandomNumberGenerator) -> Array:
	var y := YARD
	A.box(lv, Vector3(y.size.x, 0.12, y.size.y), Vector3(y.get_center().x, 0.04, y.get_center().y), "gravel", Color(0.8, 0.78, 0.75), false, 1.5)
	for k in 3:
		var t := Vector3(y.position.x + 2.6 + k * 4.5, 0.1, y.get_center().y + 1.5)
		A.box(lv, Vector3(3.0, 0.4, 3.6), t + Vector3(0, 0.2, 0), "concrete", CONC.darkened(0.1), true)
		A.box(lv, Vector3(2.2, 2.8, 2.6), t + Vector3(0, 1.8, 0), "enamel", Color(0.46, 0.52, 0.48), true, 0.8)
		for s: float in [-1.0, 1.0]:   # radiator banks
			for f in 6:
				A.box(lv, Vector3(0.06, 2.2, 0.9), t + Vector3(s * 1.25, 1.7, -1.0 + f * 0.4), "metal", Color(0.4, 0.46, 0.42), false, 0.5)
		A.cyl(lv, 0.42, 1.8, t + Vector3(0, 3.65, 0.9), "enamel", Color(0.46, 0.52, 0.48), false, "x")   # the conservator
		for i in 3:   # high-voltage bushings, ribbed
			var bp := t + Vector3(-0.7 + i * 0.7, 3.2, -0.6)
			A.cyl(lv, 0.1, 1.4, bp + Vector3(0, 0.7, 0), "cream", Color(0.62, 0.42, 0.3))
			for j in 5:
				A.cyl(lv, 0.2, 0.05, bp + Vector3(0, 0.25 + j * 0.24, 0), "cream", Color(0.62, 0.42, 0.3))
			A.seg(lv, bp + Vector3(0, 1.4, 0), Vector3(bp.x, 9.0, y.position.y + 1.0), 0.02, 0.02, "copper", Color(0.6, 0.45, 0.3))
	for s: float in [y.position.x + 0.8, y.end.x - 0.8]:   # the gantry
		for z: float in [y.position.y + 0.6, y.position.y + 2.2]:
			A.box(lv, Vector3(0.3, 10.0, 0.3), Vector3(s, 5.0, z), "metal", STEEL, false)
		for k in 4:
			A.seg(lv, Vector3(s, k * 2.4, y.position.y + 0.6), Vector3(s, (k + 1) * 2.4, y.position.y + 2.2), 0.04, 0.04, "metal", STEEL)
	A.box(lv, Vector3(y.size.x, 0.6, 2.0), Vector3(y.get_center().x, 9.8, y.position.y + 1.4), "metal", STEEL, false)
	for i in 3:
		var ip := Vector3(y.position.x + 3.0 + i * 4.0, 9.5, y.position.y + 1.0)
		for j in 6:
			A.cyl(lv, 0.16, 0.06, ip - Vector3(0, j * 0.16, 0), "cream", Color(0.5, 0.6, 0.62))
	P.fence(lv, Vector3(y.position.x - 0.5, 0, y.end.y + 0.5), Vector3(y.end.x + 0.5, 0, y.end.y + 0.5), rng)
	P.fence(lv, Vector3(y.position.x - 0.5, 0, y.position.y - 0.5), Vector3(y.end.x - 4.0, 0, y.position.y - 0.5), rng)
	P.fence(lv, Vector3(y.position.x - 0.5, 0, y.position.y - 0.5), Vector3(y.position.x - 0.5, 0, y.end.y + 0.5), rng)
	P.fence(lv, Vector3(y.end.x + 0.5, 0, y.position.y - 0.5), Vector3(y.end.x + 0.5, 0, y.end.y + 0.5), rng)
	var sign := A.root(lv, Vector3(y.position.x + 3.0, 1.6, y.position.y - 0.62), PI)
	A.box(sign, Vector3(0.9, 0.6, 0.03), Vector3.ZERO, "enamel", Color(0.95, 0.85, 0.2), false, 0.5)
	B.label(sign, "DANGER", Vector3(0, 0.12, 0.02), 34, Color(0.1, 0.08, 0.06), "stencil", 0.0042)
	B.label(sign, "11 000 VOLTS", Vector3(0, -0.12, 0.02), 30, Color(0.1, 0.08, 0.06), "stencil", 0.004)
	return [Vector3(y.get_center().x + 2.0, 0.3, y.position.y + 3.0)]


## The stair tower up the face: a braced steel frame, switchback flights with landings (walkable),
## a catwalk across to the crest at the top. A sign at its foot.
static func _stairs(lv: Node3D, rng: RandomNumberGenerator) -> Array:
	var f := STAIR
	var w := 6.4   # along x (flights of 4.2 m for 2.75 m: about 33 degrees, walkable)
	var d := 3.4   # along z
	var rise := 2.75
	var flights := int(ceilf((CREST + 0.2) / rise))
	if flights % 2 == 0:
		flights += 1   # (the last flight up the front: the deck and the catwalk go across the back)
	var top := flights * rise
	var col := Color(0.62, 0.52, 0.2)   # safety yellow, gone ochre
	for c in [Vector2(-w / 2.0, -d / 2.0), Vector2(w / 2.0, -d / 2.0), Vector2(-w / 2.0, d / 2.0), Vector2(w / 2.0, d / 2.0)]:
		A.box(lv, Vector3(0.22, top + 1.4, 0.22), f + Vector3(c.x, (top + 1.4) / 2.0, c.y), "metal", col, false)
	for k in flights + 1:
		var y := k * rise
		for s: float in [-1.0, 1.0]:
			A.box(lv, Vector3(w, 0.14, 0.14), f + Vector3(0, y, s * d / 2.0), "metal", col, false)
			A.box(lv, Vector3(0.14, 0.14, d), f + Vector3(s * w / 2.0, y, 0), "metal", col, false)
		if k < flights:
			for s: float in [-1.0, 1.0]:
				A.seg(lv, f + Vector3(-w / 2.0, y, s * d / 2.0), f + Vector3(w / 2.0, y + rise, s * d / 2.0), 0.05, 0.05, "metal", col)
	for k in flights:   # the flights: up along x one way, back the other, a landing at each end
		var y := k * rise
		var dirn := 1.0 if k % 2 == 0 else -1.0
		var z := -0.75 if k % 2 == 0 else 0.75
		var run := w - 2.2
		var a := f + Vector3(-dirn * run / 2.0, y, z)
		var b := f + Vector3(dirn * run / 2.0, y + rise, z)
		var mid := (a + b) / 2.0
		var slope := atan2(rise, run)
		var fl := A.box(lv, Vector3(Vector2(run, rise).length(), 0.12, 1.4), mid, "grate", Color(0.5, 0.5, 0.46), true, 0.4)
		fl.rotation.z = slope * dirn
		for s: float in [-1.0, 1.0]:   # the stringers
			A.seg(lv, a + Vector3(0, 0.05, s * 0.72), b + Vector3(0, 0.05, s * 0.72), 0.06, 0.06, "metal", col)
		var oz := signf(z) * 0.72   # the handrail, on the outside
		A.seg(lv, a + Vector3(0, 1.0, oz), b + Vector3(0, 1.0, oz), 0.035, 0.035, "metal", col)
		for e: float in [-1.0, 1.0]:   # landings
			A.box(lv, Vector3(1.1, 0.12, d - 0.2), f + Vector3(e * (w / 2.0 - 0.55), y + (rise if e == dirn else 0.0), 0), "grate", Color(0.5, 0.5, 0.46), true, 0.4)
	A.box(lv, Vector3(w - 2.2, 0.12, d / 2.0 - 0.05), f + Vector3(0, top, d / 4.0 + 0.02), "grate", Color(0.5, 0.5, 0.46), true, 0.4)   # the top deck, across the back
	for e: float in [-1.0, 1.0]:   # (the cage's rails keep you on it)
		B.invisible_wall(lv, Vector3(0.1, top + 2.0, d), f + Vector3(e * (w / 2.0 + 0.1), (top + 2.0) / 2.0, 0))
	B.invisible_wall(lv, Vector3(w, top + 2.0, 0.1), f + Vector3(0, (top + 2.0) / 2.0, -d / 2.0 - 0.1))
	B.invisible_wall(lv, Vector3(w, top - 1.0, 0.1), f + Vector3(0, (top - 1.0) / 2.0, d / 2.0 + 0.1))
	# The catwalk across to the crest.
	var start := f + Vector3(0, top, d / 2.0)
	var crest_z := up_z(f.x) + out_n(f.x).z * (TOP_T - 0.4)
	var end := Vector3(f.x, CREST, crest_z)
	var ln := end.z - start.z
	var cw := A.root(lv, (start + end) / 2.0, 0.0)
	var cw_slope := atan2(end.y - start.y, ln)
	A.box(cw, Vector3(1.4, 0.12, Vector2(ln, end.y - start.y).length() + 0.2), Vector3.ZERO, "grate", Color(0.5, 0.5, 0.46), true, 0.4).rotation.x = -cw_slope
	for s: float in [-1.0, 1.0]:
		A.box(cw, Vector3(0.06, 0.06, ln), Vector3(s * 0.7, 1.05, 0), "metal", col, false)
		A.box(cw, Vector3(0.18, 0.4, ln), Vector3(s * 0.7, -0.3, 0), "metal", col, false)
		B.invisible_wall(cw, Vector3(0.1, 1.6, ln), Vector3(s * 0.75, 0.8, 0))
		for i in int(ln / 1.5) + 1:
			A.box(cw, Vector3(0.05, 1.05, 0.05), Vector3(s * 0.7, 0.52, -ln / 2.0 + i * 1.5), "metal", col, false)
	var sign := A.root(lv, f + Vector3(w / 2.0 + 0.9, 1.5, -d / 2.0 - 0.3), PI)
	A.box(sign, Vector3(1.6, 0.55, 0.04), Vector3.ZERO, "enamel", Color(0.92, 0.9, 0.84), false, 0.6)
	B.label(sign, "CREST ACCESS", Vector3(0, 0.1, 0.03), 36, Color(0.15, 0.13, 0.12), "stencil", 0.0042)
	B.label(sign, "AUTHORISED STAFF", Vector3(0, -0.13, 0.03), 28, Color(0.7, 0.12, 0.1), "stencil", 0.004)
	return [f + Vector3(1.4, top + 0.2, 0), f + Vector3(-1.4, rise * 8.0 + 0.2, 0)]


## A hut on the crest by the stairs: the dam keeper's office, its door open; a desk, a log, the
## safe. A long climb for it.
static func _crest_hut(lv: Node3D, rng: RandomNumberGenerator) -> Array:
	var x := STAIR.x + 9.0
	var r := _on_crest(lv, x)
	var w := 5.0
	var d := 3.6
	var h := 2.8
	A.wall(r, -w / 2.0, w / 2.0, -d / 2.0, h, 0.2, [[1.0, 1.4, 0.9, 2.0]], "siding", Color(0.82, 0.84, 0.78), true, 0.1, true, 1.2)
	A.wall(r, -w / 2.0, w / 2.0, d / 2.0, h, 0.2, [[-1.0, 1.0, 0.0, 2.1]], "siding", Color(0.82, 0.84, 0.78), true, 0.1, true, 1.2)
	A.wall(r, -d / 2.0, d / 2.0, -w / 2.0, h, 0.2, [], "siding", Color(0.82, 0.84, 0.78), false, 0.1, true, 1.2)
	A.wall(r, -d / 2.0, d / 2.0, w / 2.0, h, 0.2, [[0.0, 1.2, 1.0, 2.0]], "siding", Color(0.82, 0.84, 0.78), false, 0.1, true, 1.2)
	A.box(r, Vector3(w + 0.6, 0.15, d + 0.6), Vector3(0, h + 0.15, 0), "corrugated", Color(0.45, 0.5, 0.48), false, 1.5, Vector3(0.08, 0, 0))
	A.box(r, Vector3(w, 0.06, d), Vector3(0, 0.12, 0), "wood", Color(0.6, 0.5, 0.4), false)
	A.box(r, Vector3(1.6, 0.06, 0.7), Vector3(-1.2, 0.86, -1.2), "wood", Color(0.5, 0.36, 0.24), false)   # the desk
	for s: float in [-1.0, 1.0]:
		A.box(r, Vector3(0.06, 0.74, 0.6), Vector3(-1.2 + s * 0.74, 0.47, -1.2), "wood", Color(0.45, 0.32, 0.22), false)
	A.box(r, Vector3(0.36, 0.05, 0.26), Vector3(-1.4, 0.9, -1.2), "paper", Color(0.85, 0.8, 0.65), false)   # the log
	A.cyl(r, 0.1, 0.18, Vector3(-0.7, 0.98, -1.15), "metal", Color(0.2, 0.2, 0.2))   # a telephone
	A.wall_lamp(r, Vector3(1.0, 2.5, d / 2.0 + 0.15), Vector3(0, 0, 1), LAMP, 0.8, false)
	Landmarks.safe(lv, r, Vector3(1.6, 0.12, -1.2), PI, true)
	return [lv.to_local(r.to_global(Vector3(0.2, 0.4, 0.2)))]


## Rock where the dam meets the ridges: strata stacked against each end.
static func _abutments(lv: Node3D, rng: RandomNumberGenerator) -> void:
	var CP = load("res://src/checkpoint.gd")
	var Data = load("res://src/data.gd")
	var tint: Color = Data.biome(lv.biome).rock_tint
	for s: float in [-1.0, 1.0]:
		for k in 4:
			var x := s * (100.0 + k * 9.0)
			var foot := Vector3(x, -2.0, toe_z(x) - 6.0 + k * 3.0)
			CP._crag(lv, foot, 22.0, 16.0, CREST + 8.0 - k * 4.0, rng.randf() * TAU, rng, tint)


## Pylons carrying the lines from the yard away over the western ridge: lattice towers, crossarms,
## insulator strings, the wires sagging between.
static func _pylons(lv: Node3D, rng: RandomNumberGenerator) -> void:
	var pts := [Vector3(-36.0, 0.0, 36.0), Vector3(-84.0, 0.0, 28.0), Vector3(-142.0, 0.0, 44.0), Vector3(-204.0, 0.0, 70.0)]
	var tops := []
	for p: Vector3 in pts:
		var gy := ridge(p.x, p.z) if absf(p.x) > 100.0 else 0.0
		var base := Vector3(p.x, gy - (6.0 if absf(p.x) > 100.0 else 0.0), p.z)
		tops.append(_pylon(lv, base, gy + 26.0 - base.y, atan2(pts[0].x - pts[-1].x, pts[0].z - pts[-1].z)))
	var start := Vector3(YARD.get_center().x, 9.6, YARD.position.y + 1.0)
	var arms: Array = [[start + Vector3(-4, 0, 0), start, start + Vector3(4, 0, 0)]]
	arms.append_array(tops)
	for i in arms.size() - 1:
		for w in 3:
			_wire(lv, arms[i][w], arms[i + 1][w], 0.035)


## One lattice tower `h` high: four legs tapering in, braced; two crossarms; returns its three
## insulator ends (where the wires hang from).
static func _pylon(lv: Node3D, base: Vector3, h: float, yaw: float) -> Array:
	var r := A.root(lv, base, yaw)
	var col := Color(0.52, 0.54, 0.52)
	var w0 := 3.4
	var w1 := 0.8
	var panels := 7
	var corner := func(y: float, sx: float, sz: float) -> Vector3:
		var w := lerpf(w0, w1, clampf(y / (h - 4.0), 0.0, 1.0))
		return Vector3(sx * w, y, sz * w)
	for sx: float in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			A.seg(r, corner.call(0.0, sx, sz), corner.call(h - 4.0, sx, sz), 0.1, 0.07, "metal", col)
			A.seg(r, corner.call(h - 4.0, sx, sz), Vector3(sx * 0.4, h, sz * 0.4), 0.07, 0.05, "metal", col)
	for k in panels:
		var ya := (h - 4.0) * k / panels
		var yb := (h - 4.0) * (k + 1) / panels
		for face_ in [[Vector2(-1, -1), Vector2(1, -1)], [Vector2(1, -1), Vector2(1, 1)], [Vector2(1, 1), Vector2(-1, 1)], [Vector2(-1, 1), Vector2(-1, -1)]]:
			var p: Vector2 = face_[0]
			var q: Vector2 = face_[1]
			A.seg(r, corner.call(yb, p.x, p.y), corner.call(yb, q.x, q.y), 0.04, 0.04, "metal", col)
			A.seg(r, corner.call(ya, p.x, p.y), corner.call(yb, q.x, q.y), 0.03, 0.03, "metal", col)
			A.seg(r, corner.call(ya, q.x, q.y), corner.call(yb, p.x, p.y), 0.03, 0.03, "metal", col)
	var ends := []
	for arm in [[h - 7.0, 5.5], [h - 3.0, 4.0]]:
		var y: float = arm[0]
		var ln: float = arm[1]
		A.seg(r, Vector3(-ln, y, 0), Vector3(ln, y, 0), 0.08, 0.08, "metal", col)
		for s: float in [-1.0, 1.0]:
			A.seg(r, Vector3(s * ln, y, 0), corner.call(y - 2.0, s, 0.0), 0.04, 0.04, "metal", col)
	for e in [Vector3(-5.2, h - 7.0, 0), Vector3(0.0, h - 3.0, 0), Vector3(5.2, h - 7.0, 0)]:   # insulator strings
		for j in 6:
			A.cyl(r, 0.14, 0.05, e - Vector3(0, 0.2 + j * 0.16, 0), "cream", Color(0.45, 0.55, 0.58))
		ends.append(lv.to_local(r.to_global(e - Vector3(0, 1.2, 0))))
	A.box(r, Vector3(0.5, 0.4, 0.04), Vector3(0, 3.0, -w0 * 0.86), "enamel", Color(0.92, 0.9, 0.84), false, 0.5)   # the danger plate
	return ends


## A wire hanging between two points, sagging.
static func _wire(lv: Node3D, a: Vector3, b: Vector3, r: float) -> void:
	var n := 10
	var sag := a.distance_to(b) * 0.04
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		A.seg(lv, prev, p, r, r, "metal", Color(0.2, 0.2, 0.2))
		prev = p


## Sodium floodlights on the crest, down the face: it stands lit after dark.
static func _floodlights(lv: Node3D) -> void:
	for x: float in [-80.0, -30.0, 70.0, 104.0]:
		var r := _on_crest(lv, x, 1.0)
		A.box(r, Vector3(0.5, 0.35, 0.4), Vector3(0, 1.4, 0.15), "metal", Color(0.3, 0.32, 0.3), false)
		A.glow(r, Vector3(0.4, 0.25, 0.05), Vector3(0, 1.4, 0.36), LAMP, 4.0)
		var l := SpotLight3D.new()
		l.light_color = LAMP
		l.light_energy = 5.0
		l.spot_range = 70.0
		l.spot_angle = 38.0
		l.distance_fade_enabled = true
		l.distance_fade_begin = 220.0
		l.distance_fade_length = 40.0
		r.add_child(l)
		l.position = Vector3(0, 1.4, 0.5)
		l.rotation.x = -1.15
		l.rotation.y = PI


# --- water ----------------------------------------------------------------------------------------

## The sheet down the chute: white water streaming down, more air in it toward the bottom; pixel
## steps like the textures. UV in metres (u across, v down), UV2.x how far down (0..1).
const FLOW := """shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;
uniform vec3 deep : source_color = vec3(0.09, 0.17, 0.16);
uniform vec3 glass : source_color = vec3(0.42, 0.56, 0.52);
uniform vec3 foam : source_color = vec3(0.94, 0.96, 0.95);
varying float air;
varying float plunge;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
float fbm(vec2 p) { return n(p) * 0.5 + n(p * 2.1) * 0.3 + n(p * 4.3) * 0.2; }
void vertex() {
	air = clamp(UV2.x, 0.0, 1.0);
	plunge = UV2.y;
	float w = sin(UV.x * 1.7 + TIME * 6.0 - UV.y * 0.9) * 0.5 + sin(UV.x * 3.3 - TIME * 4.4 + UV.y * 1.9) * 0.5;
	float lump = n(vec2(UV.x * 0.9, UV.y * 0.6 - TIME * 3.0)) - 0.5;
	VERTEX += NORMAL * (w * (0.02 + air * 0.12) + lump * (air * 0.3 + plunge * 0.9));
}
void fragment() {
	vec2 uv = floor(UV * vec2(10.0, 6.0)) / vec2(10.0, 6.0);
	float t = TIME;
	float sp = 1.0 + air * 2.6;   // faster as it falls
	// every layer drawn out down the flow: ropes and streaks, never spots
	float rope = n(vec2(uv.x * 1.2, uv.y * 0.04 - t * 0.45 * sp)) * 0.55 + n(vec2(uv.x * 2.8, uv.y * 0.07 - t * 0.8 * sp)) * 0.3 + n(vec2(uv.x * 6.5, uv.y * 0.12 - t * 1.4 * sp)) * 0.15;
	float body = n(vec2(uv.x * 3.4, uv.y * 0.1 - t * 1.6 * sp)) * 0.6 + n(vec2(uv.x * 8.0, uv.y * 0.2 - t * 2.6 * sp)) * 0.4;
	float a = rope * 0.65 + body * 0.35;
	float white = smoothstep(0.6 - air * 0.75, 0.7 - air * 0.6, a);        // glassy ropes over the crest, white through lower down
	white = clamp(max(white, plunge * (0.8 + 0.2 * body)), 0.0, 1.0);
	float shade = 0.78 + 0.22 * smoothstep(0.3, 0.7, rope * 0.7 + body * 0.3);   // (the white itself streaked)
	vec3 water = mix(deep, glass, clamp(air * 4.0 + 0.2, 0.0, 1.0));
	float glint = smoothstep(0.7, 0.9, body) * (1.0 - air) * 0.25;           // light on the smooth water over the crest
	ALBEDO = mix(water, foam * shade, white) + glint;
	ROUGHNESS = mix(0.04, 0.45, white);
	SPECULAR = 0.7;
	EMISSION = foam * white * 0.08;
	ALPHA = mix(0.88, 0.98, white);
}
"""

## The basin: boiling white where the sheet lands, the foam carried off it toward the near wall and
## breaking into lace over green water, foam against the side walls, a swirl over the drain; ripples
## catching the light. UV across the plane (0..1), v = 1 at the face's end.
const CHURN := """shader_type spatial;
render_mode blend_mix, depth_draw_opaque, specular_schlick_ggx;
uniform vec3 deep : source_color = vec3(0.1, 0.18, 0.16);
uniform vec3 foam : source_color = vec3(0.93, 0.95, 0.94);
uniform vec2 size = vec2(40.0, 30.0);
uniform vec2 drain = vec2(0.85, 3.0);
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
vec2 flow(vec2 m, float t) { return vec2(sin(m.y * 0.25 + t * 0.3) * 0.8, t * 1.5); }   // carried off the plunge toward the near wall
void vertex() {
	float boil = smoothstep(0.5, 1.0, UV.y);
	vec2 m = UV * size;
	float chop = n(m * 0.6 + flow(m, TIME) * 1.2) - 0.5;
	VERTEX.y += (sin(VERTEX.x * 1.1 + TIME * 3.6) * 0.5 + sin(VERTEX.z * 1.6 - TIME * 3.1) * 0.5) * 0.08 * (0.3 + boil) + chop * (0.06 + boil * 0.5);
}
void fragment() {
	vec2 m = floor(UV * size * 8.0) / 8.0;   // metres, in eighth-metre steps
	float t = TIME;
	float boil = smoothstep(0.45, 1.0, UV.y);
	boil *= boil;
	vec2 f = flow(m, t);
	vec2 s = m * vec2(1.0, 0.45);   // (foam drawn out along the current)
	float a = n(s * 0.35 + f * 0.6) * 0.6 + n(s * 0.9 + f) * 0.4;
	float lace = smoothstep(0.58, 0.61, a) * (1.0 - smoothstep(0.65, 0.69, a));   // lines of foam
	float raft = smoothstep(0.42, 0.66, n(s * 0.11 + f * 0.25));   // ...only in the rafts of it drifting off, clear water between
	lace *= mix(raft, 1.0, boil);
	float edge = 1.0 - smoothstep(0.0, 0.07, min(UV.x, 1.0 - UV.x));
	vec2 dc = vec2((UV.x - drain.x) * size.x, UV.y * size.y);
	float swirl = (1.0 - smoothstep(0.0, drain.y, length(dc))) * smoothstep(0.4, 0.7, n(vec2(atan(dc.y, dc.x) * 3.0 + t * 2.0, length(dc) * 2.0 - t * 3.0)));
	float churned = smoothstep(0.35, 0.6, n(s * 1.4 + f * 1.5));   // the boil breaking up as it spreads
	float white = clamp(boil * mix(0.4, 1.2, churned) + lace * mix(0.6, 1.0, boil) + edge * lace * 0.5 + swirl, 0.0, 1.0);
	float e = 0.15;
	vec2 q = UV * size * 2.6 + f * 2.0;   // (fine ripples from smooth coordinates: stepped, they lit up as a checkerboard)
	float h0 = n(q) + n(q * 2.3 + 7.0) * 0.5;
	float hx = n(q + vec2(e, 0.0)) + n((q + vec2(e, 0.0)) * 2.3 + 7.0) * 0.5;
	float hy = n(q + vec2(0.0, e)) + n((q + vec2(0.0, e)) * 2.3 + 7.0) * 0.5;
	NORMAL_MAP = normalize(vec3((h0 - hx) * 0.7, (h0 - hy) * 0.7, 1.0)) * 0.5 + 0.5;
	ALBEDO = mix(deep, foam, white);
	ROUGHNESS = mix(0.22, 0.6, white);
	SPECULAR = 0.4;
	EMISSION = foam * white * 0.05;
}
"""

## The roller at the foot of the chute: white foam heaving and tumbling over itself, grey in its hollows.
const FOAM := """shader_type spatial;
render_mode blend_mix, depth_draw_opaque, specular_schlick_ggx;
uniform vec3 foam : source_color = vec3(0.94, 0.96, 0.95);
uniform vec3 hollow : source_color = vec3(0.55, 0.66, 0.66);
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void vertex() {
	float b = n(VERTEX.xz * 1.6 + vec2(TIME * 1.7, -TIME * 2.3)) * 0.6 + n(VERTEX.xy * 3.1 - TIME * 2.9) * 0.4;
	VERTEX += NORMAL * (b - 0.45) * 0.55;
}
void fragment() {
	vec2 p = floor(UV * vec2(120.0, 30.0)) / vec2(120.0, 30.0);
	float a = n(p * vec2(55.0, 11.0) + vec2(0.0, -TIME * 3.4)) * 0.6 + n(p * vec2(140.0, 26.0) - vec2(TIME * 1.1, TIME * 5.0)) * 0.4;
	ALBEDO = mix(hollow, foam, smoothstep(0.28, 0.55, a));
	ROUGHNESS = 0.55;
	EMISSION = foam * 0.07;
}
"""


static func _water_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m
