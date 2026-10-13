# The checkpoint as a whole site (level._checkpoint builds its core: platform, reclamation hall,
# shredder, shop, gate). This lays out everything round it: a basin ringed by banded rock ridges,
# the main line coming in and out through tunnel portals, and the Bureau's works filling the
# floor: the head office over a parking lot, a container terminal, the scrap works (crusher,
# conveyor, stacks), the classification yard with its repair shed, a fuel depot. The moving parts
# (people, vehicles, the shunter, cranes, smoke) are yard_life.gd's.
#   x runs along the main line (the train leaves toward +x); +z is the hall side.
extends RefCounted

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const P = preload("res://src/props.gd")
const Merge = preload("res://src/merge.gd")

const X_EDGE := 172.0      # the ridges the line tunnels through
const Z_NORTH := 150.0
const Z_SOUTH := -128.0
const FAR_LINE := -78.0    # the through line at the far side of the yard (yard_life runs trains on it)
const SIDINGS := [-24.0, -30.0, -36.0, -42.0, -48.0, -54.0]
const SHUNT_Z := -24.0     # the siding the shunter works (kept clear of standing wagons between these)
const LADDER_A := Vector2(-106.0, 0.0)   # the yard ladder: off the main line here, ...
const LADDER_B := Vector2(-156.0, -54.0)  # ...across every siding to the last
const SHUNT_X := Vector2(-112.0, -8.0)
const RAIL_TOP := 0.285   # the rail heads of _track's track
const CONV_A := Vector3(86, 0.5, 52)    # the conveyor, foot to head
const CONV_B := Vector3(112, 11.0, 84)
const STACKS := [Vector3(116, 34.5, 96), Vector3(125, 34.5, 96)]
const CC := [Color(0.25, 0.4, 0.55), Color(0.65, 0.25, 0.15), Color(0.3, 0.45, 0.3), Color(0.75, 0.6, 0.2), Color(0.5, 0.5, 0.5), Color(0.2, 0.25, 0.3), Color(0.55, 0.35, 0.2)]


## `mark` (level._slice): awaited between the parts, so the basin can be built over several frames.
static func build(lv: Node3D, rng: RandomNumberGenerator, mark := Callable()) -> void:
	var parts := [_ground.bind(lv), _edges.bind(lv, rng), _main_line.bind(lv), _yard_south.bind(lv, rng), _admin.bind(lv, rng),
		_terminal.bind(lv, rng), _scrapworks.bind(lv, rng), _fuel.bind(lv, rng), _lights.bind(lv)]
	for k in parts.size():
		if mark.is_valid():
			await mark.call("cp %d" % k)
		parts[k].call()


# --- the ground and its edges ---------------------------------------------------------------------

static func _ground(lv: Node3D) -> void:
	A.box(lv, Vector3(560, 1.0, 460), Vector3(0, -0.5, 10), "dirt", Color(0.66, 0.56, 0.46), true, 3.0)   # packed earth, trodden and driven over
	# Pavement, in layers that never share a height (the core's concrete pads, level._checkpoint, are
	# 0.06 on top): the yard's ballast 0.03, the lots 0.05, the roads 0.08 over everything.
	A.box(lv, Vector3(310, 0.03, 66), Vector3(-10, 0.015, -48), "gravel", Color(0.75, 0.72, 0.68), true, 2.0)   # the yard's ballast bed
	A.box(lv, Vector3(99, 0.05, 50), Vector3(0, 0.025, 70), "asphalt", Color.WHITE, true, 4.0)    # admin + parking (butting the lots either side, not over them)
	A.box(lv, Vector3(105, 0.05, 92), Vector3(-102, 0.025, 58), "concrete", Color(0.7, 0.68, 0.64), true, 4.0)   # container terminal
	A.box(lv, Vector3(105, 0.05, 92), Vector3(102, 0.025, 58), "dirt", Color(0.9, 0.85, 0.8), true, 3.0)   # scrap works
	A.box(lv, Vector3(320, 0.05, 9), Vector3(-5, 0.055, 40.5), "asphalt", Color.WHITE, true, 4.0)   # the ring road
	for x in [-52.0, 52.0]:   # the side roads, from the ring road's edge (not over it)
		A.box(lv, Vector3(9, 0.05, 69), Vector3(x, 0.055, 79.5), "asphalt", Color.WHITE, true, 4.0)
	for x in range(-150, 150, 12):   # dashed centre line along the ring road
		if absf(x + 3.0 - 52.0) > 7.0 and absf(x + 3.0 + 52.0) > 7.0:
			A.box(lv, Vector3(5.0, 0.01, 0.18), Vector3(x + 3.0, 0.085, 40.5), "cream", Color(0.95, 0.85, 0.3), false, 1.0)
	for k in 12:   # parking bays
		A.box(lv, Vector3(0.15, 0.01, 5.0), Vector3(-33.0 + k * 3.2, 0.055, 52.5), "cream", Color(0.92, 0.92, 0.88), false, 1.0)


## Banded rock all round: long ridges with mesas and spires in front of them to break the line,
## talus at their feet, and a far skyline of mesas fading in the haze.
static func _edges(lv: Node3D, rng: RandomNumberGenerator) -> void:
	var rock := Color(0.95, 0.9, 0.85)
	# A solid back to each side (so nothing shows through), well behind the faces built in front.
	for s in [-1.0, 1.0]:
		var x: float = s * (X_EDGE + 16.0)
		A.wall(lv, Z_SOUTH - 30.0, Z_NORTH + 30.0, x, 30.0, 24.0, [[0.0, 11.4, 0.0, 11.4], [FAR_LINE, 11.4, 0.0, 11.4]], "mesa", rock.darkened(0.15), false, 0.0, true, 11.0)
		for z in [0.0, FAR_LINE]:
			_portal(lv, Vector3(s * X_EDGE, 0, z), s, rng, rock)
	for side in [[Z_NORTH, 1.0], [Z_SOUTH, -1.0]]:
		A.wall(lv, -X_EDGE - 40.0, X_EDGE + 40.0, side[0] + side[1] * 20.0, 28.0, 24.0, [], "mesa", rock.darkened(0.15), true, 0.0, true, 11.0)
	# The faces: rock in blocks of every size, set at angles, staggered in and out, some leaning,
	# stepped up in ledges; then fallen rock heaped along their feet.
	var runs := [[Vector3(-X_EDGE, 0, Z_NORTH), Vector3(X_EDGE, 0, Z_NORTH), Vector3(0, 0, -1)], [Vector3(-X_EDGE, 0, Z_SOUTH), Vector3(X_EDGE, 0, Z_SOUTH), Vector3(0, 0, 1)],
		[Vector3(-X_EDGE, 0, Z_SOUTH), Vector3(-X_EDGE, 0, Z_NORTH), Vector3(1, 0, 0)], [Vector3(X_EDGE, 0, Z_SOUTH), Vector3(X_EDGE, 0, Z_NORTH), Vector3(-1, 0, 0)]]
	for run in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var inward: Vector3 = run[2]
		var along := (b - a).normalized()
		var t := 0.0
		var total := a.distance_to(b)
		while t < total:
			var w := rng.randf_range(12.0, 26.0)
			var p: Vector3 = a + along * (t + w / 2.0)
			t += w * rng.randf_range(0.55, 0.85)
			if absf(inward.x) > 0.5 and (absf(p.z) < 10.0 + w * 0.62 or absf(p.z - FAR_LINE) < 10.0 + w * 0.62):
				continue   # (clear of the tunnel mouths)
			var h := rng.randf_range(14.0, 34.0)
			var d := rng.randf_range(12.0, 22.0)
			var back := rng.randf_range(-2.0, 7.0)
			_crag(lv, p - inward * (back + d / 2.0 - 4.0), w, d, h, atan2(along.z, along.x), rng, rock.darkened(rng.randf() * 0.18))
			for k in rng.randi_range(1, 2):   # scree at its foot
				var q := p + inward * rng.randf_range(4.0, 9.0) + along * rng.randf_range(-w / 2.0, w / 2.0)
				P.boulder(lv, q, Vector3(rng.randf_range(3, 7), rng.randf_range(1.5, 3.5), rng.randf_range(3, 6)), rng, Color(0.82, 0.72, 0.64), false)
			if rng.randf() < 0.35:
				P.boulder(lv, p + inward * rng.randf_range(6.0, 12.0), Vector3(rng.randf_range(1.5, 4), rng.randf_range(1, 3), rng.randf_range(1.5, 4)), rng, Color(0.85, 0.75, 0.68), true)
	for k in 6:   # spires standing out from the walls
		P.rock_spire(lv, Vector3(rng.randf_range(-140, 140), 0, Z_NORTH - 10.0 if k % 2 == 0 else Z_SOUTH + 10.0), rng, Color(0.85, 0.75, 0.68))
	# The skyline: mesas a long way off in every direction.
	for k in 16:
		var ang := TAU * k / 16.0 + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(320, 420)
		P.mesa(lv, Vector3(cos(ang) * r, 0, sin(ang) * r * 0.85), rng, Color(0.82, 0.72, 0.64))
	# You stay inside.
	for s in [-1.0, 1.0]:
		B.invisible_wall(lv, Vector3(2, 40, 420), Vector3(s * (X_EDGE - 4.0), 20, 10)).add_to_group("across_line")   # (line.gd lets the train through)
	B.invisible_wall(lv, Vector3(420, 40, 2), Vector3(0, 20, Z_NORTH - 6.0))
	B.invisible_wall(lv, Vector3(420, 40, 2), Vector3(0, 20, Z_SOUTH + 6.0))


## One buttress of the cliff, w along the wall and d deep: strata stacked up, each a faceted drum
## stretched along the wall, pulling in and wandering a little, set at its own small angle, so the
## face reads as weathered rock in ledges instead of a box. (No collision: the invisible walls keep you in.)
static func _crag(lv: Node3D, foot: Vector3, w: float, d: float, h: float, yaw: float, rng: RandomNumberGenerator, tint: Color) -> void:
	var tiers := rng.randi_range(2, 4)
	var y := -1.5
	var sx := w * 0.62   # the drum's facets cut its corners in: a little over half the width as radius
	var sz := d * 0.62
	for k in tiers:
		var th := (h + 1.5) / tiers * rng.randf_range(0.75, 1.25)
		var pull := rng.randf_range(0.8, 0.95)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = 1.0
		cm.top_radius = pull
		cm.height = th
		cm.radial_segments = rng.randi_range(6, 9)
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = A.mat("mesa", tint.darkened(0.07 * (k % 2)) if k % 3 != 2 else tint.lerp(Color(0.95, 0.78, 0.62), 0.12), 11.0)
		mi.rotation.y = rng.randf() * TAU   # facets at a random phase before the stretch: edges come forward, not one broad flat face
		var st := Node3D.new()
		lv.add_child(st)
		st.add_child(mi)
		st.position = foot + Vector3(rng.randf_range(-1.0, 1.0), y + th / 2.0, rng.randf_range(-1.0, 1.0))
		st.rotation = Vector3(rng.randf_range(-0.03, 0.03), -yaw + rng.randf_range(-0.3, 0.3), rng.randf_range(-0.03, 0.03))
		st.scale = Vector3(sx, 1.0, sz)
		y += th
		sx *= pull * rng.randf_range(0.85, 1.0)
		sz *= pull * rng.randf_range(0.85, 1.0)


## A tunnel mouth set into the cliff, s = +1 for the east (the bore runs off toward +x). Built in a
## frame whose -x side faces the basin: a concrete headwall (piers, an arched opening ringed by
## voussoirs with a keystone and date stone, impost blocks, pilasters, a string course, a coping, the
## name on a plate), wing walls stepping down either side into fallen rock, a lined bore with ribs
## that darkens into the hill, a lamp; then crags either side and over the top so it sits in rock.
const ARCH_W := 4.5      # half the opening's width = the arch's radius
const SPRING := 5.2      # where the arch springs from the piers
const HEAD_H := 13.0
const HEAD_W := 10.5     # half the headwall's width

## `twin`: the world z side (+1 / -1) another portal stands against: no wing wall or rock there.
static func _portal(lv: Node3D, at: Vector3, s: float, rng: RandomNumberGenerator, rock: Color, plug := true, twin := 0.0) -> void:
	var c := Color(0.66, 0.63, 0.58)
	var r := Node3D.new()
	lv.add_child(r)
	r.position = at
	r.rotation.y = 0.0 if s > 0 else PI
	var thick := 1.6
	# Piers either side of the opening, full height.
	for sz in [-1.0, 1.0]:
		var pw := HEAD_W - ARCH_W
		A.box(r, Vector3(thick, HEAD_H, pw), Vector3(thick / 2.0, HEAD_H / 2.0, sz * (ARCH_W + pw / 2.0)), "concrete", c, true, 2.0)
		A.box(r, Vector3(0.35, HEAD_H, 1.3), Vector3(-0.17, HEAD_H / 2.0, sz * (HEAD_W - 0.9)), "concrete", c.darkened(0.06), false, 2.0)   # pilaster
		A.box(r, Vector3(thick + 0.3, 0.45, 1.2), Vector3(thick / 2.0 - 0.15, SPRING - 0.22, sz * (ARCH_W + 0.6)), "concrete", c.darkened(0.12), false, 1.5)   # impost
		A.box(r, Vector3(0.6, 0.5, 1.4), Vector3(-0.3, 0.25, sz * (ARCH_W + 0.7)), "concrete", c.darkened(0.2), false, 1.5)   # kerb at the foot
	# Over the arch: upright slices, each sitting on the ring's circle at its inner edge (the ring
	# covers what's left between), up to the coping.
	var ring_out := ARCH_W + 1.1
	var n := 18
	for i in n:
		var z0 := -ARCH_W + i * (2.0 * ARCH_W / n)
		var z1 := z0 + 2.0 * ARCH_W / n
		var zin := minf(absf(z0), absf(z1)) if z0 * z1 > 0.0 else 0.0
		var bottom := SPRING + sqrt(maxf(0.0, (ring_out - 0.6) * (ring_out - 0.6) - zin * zin))
		A.box(r, Vector3(thick, HEAD_H - bottom, z1 - z0 + 0.01), Vector3(thick / 2.0, (bottom + HEAD_H) / 2.0, (z0 + z1) / 2.0), "concrete", c, true, 2.0)
	# The voussoirs, standing a little proud, the keystone more so.
	var stones := 15
	for i in stones:
		var a := PI * (i + 0.5) / stones
		var key := i == stones / 2
		var rad := ARCH_W + 0.55
		var st := A.box(r, Vector3(thick + (0.5 if key else 0.24), 1.1 + (0.4 if key else 0.0), 1.24), Vector3(thick / 2.0 - (0.25 if key else 0.12), SPRING + sin(a) * (rad + (0.2 if key else 0.0)), cos(a) * rad), "concrete", c.darkened(0.1 if i % 2 == 0 else 0.16), false, 1.5)
		st.rotation.x = -(a - PI / 2.0)
	B.label(r, "1961", Vector3(-0.51, SPRING + ARCH_W + 0.75, 0), 40, Color(0.3, 0.28, 0.25), "stencil", 0.01).rotation.y = -PI / 2.0
	# String course, coping, the name plate.
	A.box(r, Vector3(0.3, 0.35, HEAD_W * 2.0), Vector3(-0.15, 11.3, 0), "concrete", c.darkened(0.12), false, 1.5)
	A.box(r, Vector3(thick + 0.6, 0.55, HEAD_W * 2.0 + 0.6), Vector3(thick / 2.0 - 0.3, HEAD_H + 0.27, 0), "concrete", c.darkened(0.15), false, 1.5)
	A.box(r, Vector3(0.08, 0.85, 7.0), Vector3(-0.04, 12.3, 0), "metal", Color(0.3, 0.32, 0.3), false, 0.5)
	B.label(r, "BRM  TUNNEL  %s" % ("EAST" if s > 0 else "WEST"), Vector3(-0.085, 12.3, 0), 60, Color(0.85, 0.8, 0.7), "plate", 0.01).rotation.y = -PI / 2.0
	A.wall_lamp(r, Vector3(-0.02, SPRING + 1.2, ARCH_W + 1.6), Vector3(-1, 0, 0), Color(1, 0.85, 0.6), 1.2, false)
	# Wing walls: out from the piers' outer edges toward the basin, flaring, their tops stepping down.
	for sz in [-1.0, 1.0]:
		if twin != 0.0 and sz * (1.0 if s > 0 else -1.0) == twin:
			continue
		var a0 := Vector3(0.3, 0, sz * (HEAD_W - 0.5))
		var a1 := Vector3(-6.5, 0, sz * (HEAD_W + 3.5))
		var steps := 4
		for k in steps:
			var t0 := float(k) / steps
			var t1 := float(k + 1) / steps
			var p0 := a0.lerp(a1, t0)
			var p1 := a0.lerp(a1, t1)
			var h := lerpf(HEAD_H - 1.5, 3.0, t1)
			var mid := (p0 + p1) / 2.0
			var ln := p0.distance_to(p1) + 0.3
			var yaw := atan2(p1.z - p0.z, p1.x - p0.x)
			A.box(r, Vector3(ln, h, 1.0), Vector3(mid.x, h / 2.0, mid.z), "concrete", c, true, 2.0, Vector3(0, -yaw, 0))
			A.box(r, Vector3(ln + 0.1, 0.3, 1.25), Vector3(mid.x, h + 0.15, mid.z), "concrete", c.darkened(0.15), false, 1.5, Vector3(0, -yaw, 0))
		for k in 3:   # rock spilled down behind it
			var q := a0.lerp(a1, 0.35 + k * 0.25) + Vector3(0, 0, sz * 2.2)
			P.boulder(r, q + Vector3(0, 0.8, 0), Vector3(4.0 - k, 3.4 - k * 0.8, 3.0), rng, rock.darkened(0.1), false)
	# The bore: side walls, the vault in blocks along it, ribs every few metres, going dark.
	var deep := 30.0
	for seg in 2:
		var xa := thick if seg == 0 else 9.0
		var xb := 9.0 if seg == 0 else deep
		var tint := c.darkened(0.5 if seg == 0 else 0.82)
		var ln := xb - xa
		for sz in [-1.0, 1.0]:
			A.box(r, Vector3(ln, SPRING, 0.6), Vector3((xa + xb) / 2.0, SPRING / 2.0, sz * (ARCH_W + 0.3)), "concrete", tint, false, 2.0)
		for i in 12:
			var a := PI * (i + 0.5) / 12.0
			var vb := A.box(r, Vector3(ln, 0.6, 1.35), Vector3((xa + xb) / 2.0, SPRING + sin(a) * (ARCH_W + 0.3), cos(a) * (ARCH_W + 0.3)), "concrete", tint, false, 2.0)
			vb.rotation.x = -(a - PI / 2.0)
	var x := thick + 3.0
	while x < deep - 2.0:   # ribs
		var tint := c.darkened(0.6 if x < 9.0 else 0.85)
		for sz in [-1.0, 1.0]:
			A.box(r, Vector3(0.35, SPRING, 0.25), Vector3(x, SPRING / 2.0, sz * (ARCH_W - 0.1)), "concrete", tint, false, 1.0)
		for i in 10:
			var a := PI * (i + 0.5) / 10.0
			var rb := A.box(r, Vector3(0.35, 0.25, 1.45), Vector3(x, SPRING + sin(a) * (ARCH_W - 0.1), cos(a) * (ARCH_W - 0.1)), "concrete", tint, false, 1.0)
			rb.rotation.x = -(a - PI / 2.0)
		x += 4.0
	if plug:   # the dark further in (line.gd hides it when a train runs on through: group "bore_plug")
		var dark := A.box(r, Vector3(0.5, SPRING + ARCH_W + 1.0, ARCH_W * 2.0 + 1.0), Vector3(deep, (SPRING + ARCH_W + 1.0) / 2.0, 0), "rubber", Color(0.02, 0.02, 0.02), false, 1.0)
		dark.add_to_group("bore_plug")
		Merge.live(dark)
	# Rock either side and over the top, set back so the headwall stands proud of it.
	for sz in [-1.0, 1.0]:
		if twin != 0.0 and sz * (1.0 if s > 0 else -1.0) == twin:
			continue
		_crag(r, Vector3(9.0, 0, sz * 17.0), 16.0, 18.0, rng.randf_range(22.0, 30.0), PI / 2.0, rng, rock.darkened(rng.randf() * 0.12))
	_crag(r, Vector3(8.0, HEAD_H - 0.5, 0), 28.0, 12.0, rng.randf_range(10.0, 16.0), PI / 2.0, rng, rock.darkened(rng.randf() * 0.12))


static func _track(lv: Node3D, z: float, x0: float, x1: float) -> void:
	var ln := x1 - x0
	var xc := (x0 + x1) / 2.0
	A.box(lv, Vector3(ln, 0.12, 3.2), Vector3(xc, 0.06, z), "gravel", Color(0.7, 0.66, 0.6), false, 1.5)
	for k in int(ln / 2.2):
		A.box(lv, Vector3(0.26, 0.08, 2.5), Vector3(x0 + 1.1 + k * 2.2, 0.13, z), "wood", Color(0.45, 0.4, 0.35), false, 1.0)
	for dz in [-0.72, 0.72]:
		A.box(lv, Vector3(ln, 0.13, 0.08), Vector3(xc, 0.22, z + dz), "metal", Color(0.62, 0.6, 0.58), false, 1.0)


## The main line out to both tunnels (the core's own rails stop at ±100).
static func _main_line(lv: Node3D) -> void:
	for s in [-1.0, 1.0]:
		_track(lv, 0.0, minf(s * 99.0, s * (X_EDGE + 30.0)), maxf(s * 99.0, s * (X_EDGE + 30.0)))
	_track(lv, FAR_LINE, -X_EDGE - 30.0, X_EDGE + 30.0)
	for x in range(-150, 151, 25):   # catenary-less line poles with their wires
		for z in [5.0, FAR_LINE - 5.0]:
			A.cyl(lv, 0.12, 8.0, Vector3(x, 4.0, z), "wood", Color(0.45, 0.38, 0.3), false)
			A.box(lv, Vector3(0.12, 0.12, 1.6), Vector3(x, 7.6, z), "wood", Color(0.45, 0.38, 0.3), false, 1.0)


# --- the classification yard (south of the main line) -----------------------------------------------

## Where a siding starts: on the ladder, the diagonal that leads off the main line at the yard's west
## throat and crosses each siding in turn.
static func _siding_start(z: float) -> float:
	return LADDER_A.x + (LADDER_B.x - LADDER_A.x) * (z / LADDER_B.y)


static func _yard_south(lv: Node3D, rng: RandomNumberGenerator) -> void:
	for z in SIDINGS:
		_track(lv, z, _siding_start(z), 130.0)
		_buffer(lv, Vector3(130.0, 0, z), -1.0)   # stub ends at the east, against buffer stops
	_track_seg(lv, LADDER_A, LADDER_B)
	_buffer(lv, Vector3(LADDER_B.x, 0, LADDER_B.y), -1.0, atan2(LADDER_B.y - LADDER_A.y, LADDER_B.x - LADDER_A.x))
	# The core's own siding (level._checkpoint) leads off the main line here, and stops at a buffer.
	_track_seg(lv, Vector2(-45.0, -9.0), Vector2(-86.0, -0.4), true)
	_buffer(lv, Vector3(45.0, 0, -9.0), -1.0, 0.0, true)
	# Wagons standing on the sidings, in cuts with gaps between.
	for z in SIDINGS:
		var x: float = _siding_start(z) + 7.0 + rng.randf_range(0, 15)
		while x < 120.0:
			if rng.randf() < 0.22 or (z == SHUNT_Z and x > SHUNT_X.x - 6.0 and x < SHUNT_X.y + 6.0):
				x += rng.randf_range(12, 30) if z != SHUNT_Z else 11.2
				continue
			var kind := rng.randi() % 4
			match kind:
				0: P.boxcar(lv, Vector3(x, RAIL_TOP, z), 0.0, rng)   # (wheels on the rail heads)
				1: _tank_car(lv, Vector3(x, RAIL_TOP, z), rng)
				2: _flatcar(lv, Vector3(x, RAIL_TOP, z), rng)
				3: _hopper(lv, Vector3(x, RAIL_TOP, z), rng)
			x += 11.2
	# The repair shed straddling two sidings: a long steel shed, open at both ends.
	_shed(lv, Vector3(80, 0, -39), 48.0, 22.0, 11.0, "WAGON REPAIR")
	# Signal gantries over both ends of the sidings, the switchman's tower.
	for x in [-122.0, 122.0]:
		_signal_gantry(lv, Vector3(x, 0, -39), 36.0)
	_tower(lv, Vector3(-60.0, 0, -62.0), "YARD CONTROL")
	P.tin_shed(lv, Vector3(30.0, 0.06, -63.0), 0.0, rng)
	P.tin_shed(lv, Vector3(-100.0, 0.06, -63.0), PI, rng)


## A straight run of track at any angle, a to b on the ground (x, z): ballast, sleepers square to it,
## the two rails. `low`: the core's lighter track (rails on sleepers on the pad, no ballast bed).
static func _track_seg(lv: Node3D, a: Vector2, b: Vector2, low := false) -> void:
	var d := b - a
	var ln := d.length()
	var yaw := -atan2(d.y, d.x)
	var r := Node3D.new()
	lv.add_child(r)
	r.position = Vector3((a.x + b.x) / 2.0, 0, (a.y + b.y) / 2.0)
	r.rotation.y = yaw
	if not low:
		A.box(r, Vector3(ln, 0.115, 3.2), Vector3(0, 0.0575, 0), "gravel", Color(0.7, 0.66, 0.6), false, 1.5)
	var sy := 0.06 if low else 0.13
	for k in int(ln / 2.2):
		A.box(r, Vector3(0.26, 0.08, 2.5), Vector3(-ln / 2.0 + 1.1 + k * 2.2, sy, 0), "wood", Color(0.45, 0.4, 0.35), false, 1.0)
	for dz in [-0.72, 0.72]:
		if low:
			A.box(r, Vector3(ln, 0.1, 0.08), Vector3(0, 0.1, dz), "rust", Color.WHITE, false, 1.0)
		else:
			A.box(r, Vector3(ln, 0.13, 0.08), Vector3(0, 0.22, dz), "metal", Color(0.62, 0.6, 0.58), false, 1.0)


## A buffer stop at a track's end: the rails bent up into two raking struts each side, a timber
## buffer beam in red and white across them with two sprung buffers facing the track, and a heap of
## ballast behind. `s` is the way the track runs from it (+1: toward +x along the yaw).
static func _buffer(lv: Node3D, at: Vector3, s: float, yaw := 0.0, low := false) -> void:
	var r := Node3D.new()
	lv.add_child(r)
	r.position = at
	r.rotation.y = -yaw
	var base := 0.15 if low else 0.29
	for dz in [-0.72, 0.72]:
		A.seg(r, Vector3(s * 0.3, base, dz), Vector3(0, base + 0.95, dz), 0.05, 0.05, "rust", Color.WHITE)
		A.seg(r, Vector3(-s * 1.6, base, dz), Vector3(0, base + 0.95, dz), 0.05, 0.05, "rust", Color.WHITE)
		A.seg(r, Vector3(-s * 1.6, base, dz), Vector3(s * 0.3, base, dz), 0.04, 0.04, "rust", Color.WHITE)
		A.cyl(r, 0.18, 0.4, Vector3(s * 0.25, base + 0.85, dz * 1.2), "metal", Color(0.3, 0.3, 0.3), false, "x")   # buffer
		A.cyl(r, 0.24, 0.05, Vector3(s * 0.47, base + 0.85, dz * 1.2), "metal", Color(0.45, 0.45, 0.45), false, "x")
	A.box(r, Vector3(0.35, 0.45, 3.1), Vector3(0, base + 0.85, 0), "wood", Color(0.55, 0.4, 0.3), false, 0.6)
	A.box(r, Vector3(0.02, 0.4, 3.0), Vector3(s * 0.18, base + 0.85, 0), "hazard", Color(1.0, 0.5, 0.45), false, 0.5)
	A.glow(r, Vector3(0.1, 0.2, 0.2), Vector3(s * 0.15, base + 1.25, 0), Color(1.0, 0.15, 0.1), 2.0)   # the stop lamp
	var heap := A.sphere(r, 1.6, Vector3(-s * 1.9, 0.0, 0), "gravel", Color(0.7, 0.66, 0.6), 0.0, 0.45)
	heap.scale = Vector3(1.0, 1.0, 1.25)


static func _bogies(r: Node3D, ln: float) -> void:
	for sx in [-1.0, 1.0]:
		var bx: float = sx * (ln / 2.0 - 1.8)
		A.box(r, Vector3(2.4, 0.5, 1.9), Vector3(bx, 0.55, 0), "metal", Color(0.2, 0.2, 0.2), false, 0.5)
		for wx in [-0.7, 0.7]:
			for wz in [-0.72, 0.72]:
				A.cyl(r, 0.42, 0.12, Vector3(bx + wx, 0.48, wz), "metal", Color(0.25, 0.24, 0.23), false, "z")


static func _tank_car(lv: Node3D, at: Vector3, rng: RandomNumberGenerator) -> void:
	var r := P._root(lv, at, 0.0, Vector3(10.4, 4.2, 3.0))
	var c: Color = [Color(0.18, 0.18, 0.18), Color(0.75, 0.72, 0.65), Color(0.45, 0.2, 0.15)][rng.randi() % 3]
	A.box(r, Vector3(10.2, 0.3, 2.6), Vector3(0, 1.05, 0), "metal", Color(0.2, 0.2, 0.2), false, 0.6)
	A.cyl(r, 1.35, 9.6, Vector3(0, 2.55, 0), "enamel", c, false, "x")
	for sx in [-1.0, 1.0]:
		A.sphere(r, 1.35, Vector3(sx * 4.8, 2.55, 0), "enamel", c).scale = Vector3(0.35, 1, 1)
	A.cyl(r, 0.45, 0.4, Vector3(0, 4.0, 0), "metal", c.darkened(0.2), false)   # the dome
	A.box(r, Vector3(2.0, 0.04, 0.5), Vector3(0, 3.92, 0.6), "grate", Color.WHITE, false, 0.4)
	B.label(r, ["BRM FUEL", "CORROSIVE", "WATER", "OIL"][rng.randi() % 4], Vector3(0, 2.55, 1.37), 40, Color(0.9, 0.88, 0.8) if c.v < 0.5 else Color(0.15, 0.13, 0.11), "stencil", 0.012)
	_bogies(r, 10.2)


static func _flatcar(lv: Node3D, at: Vector3, rng: RandomNumberGenerator) -> void:
	var r := P._root(lv, at, 0.0, Vector3(10.4, 1.4, 3.0))
	A.box(r, Vector3(10.4, 0.35, 2.7), Vector3(0, 1.1, 0), "rust", Color(0.7, 0.65, 0.6), false, 0.8)
	_bogies(r, 10.4)
	if rng.randf() < 0.8:
		P.shipping_container(r, Vector3(0, 1.28, 0), PI / 2.0, CC[rng.randi() % CC.size()], rng, true)


static func _hopper(lv: Node3D, at: Vector3, rng: RandomNumberGenerator) -> void:
	var r := P._root(lv, at, 0.0, Vector3(10.2, 3.8, 3.0))
	var c: Color = [Color(0.45, 0.3, 0.2), Color(0.3, 0.32, 0.3), Color(0.5, 0.45, 0.3)][rng.randi() % 3]
	A.box(r, Vector3(10.0, 2.3, 2.9), Vector3(0, 2.45, 0), "riveted", c, false, 1.2)
	for k in 3:   # the hoppers underneath
		var h := A.prism(r, Vector3(2.6, 0.9, 2.6), Vector3(-3.0 + k * 3.0, 0.9, 0), "riveted", c.darkened(0.15), Vector3(PI, 0, 0), 1.2)
		h.scale = Vector3(1, 1, 1)
	A.box(r, Vector3(9.8, 0.3, 2.7), Vector3(0, 3.6, 0), "rust", Color(0.55, 0.4, 0.3), false, 1.0)   # (a load of ore heaped in it)
	_bogies(r, 10.0)


## A long open-ended steel shed: columns, a pitched roof of corrugated sheet, skylights, its name.
static func _shed(lv: Node3D, at: Vector3, ln: float, wid: float, h: float, title: String) -> void:
	var c := Color(0.72, 0.7, 0.66)
	for sz in [-1.0, 1.0]:
		A.wall(lv, at.x - ln / 2.0, at.x + ln / 2.0, at.z + sz * wid / 2.0, h, 0.3, [], "corrugated", c, true, 0.0, true, 2.0)
		for k in 9:
			var x := at.x - ln / 2.0 + k * ln / 8.0
			A.box(lv, Vector3(0.4, h, 0.4), Vector3(x, h / 2.0, at.z + sz * (wid / 2.0 - 0.4)), "metal", Color(0.4, 0.42, 0.4), false, 0.8)
		var roof := A.box(lv, Vector3(ln + 1.0, 0.25, wid / 2.0 + 1.2), Vector3(at.x, h + 1.6, at.z + sz * wid / 4.0), "corrugated", c.darkened(0.15), true, 2.0)
		roof.rotation.x = sz * 0.28
	for x in [at.x - ln / 4.0, at.x + ln / 4.0]:
		A.glow(lv, Vector3(6.0, 0.05, wid * 0.6), Vector3(x, h - 0.2, at.z), Color(1, 0.88, 0.7), 0.5)
	var sg := B.label(lv, title, Vector3(at.x, h + 0.6, at.z - wid / 2.0 - 0.2), 120, Color(0.9, 0.86, 0.75), "plate", 0.02)
	sg.rotation.y = PI
	for k in 3:   # lamps inside
		B.omni(lv, Vector3(at.x - ln / 3.0 + k * ln / 3.0, h - 1.5, at.z), Color(1, 0.85, 0.65), 2.0, 18.0)


static func _signal_gantry(lv: Node3D, at: Vector3, span: float) -> void:
	var g := Color(0.3, 0.32, 0.3)
	for sz in [-1.0, 1.0]:
		A.box(lv, Vector3(0.6, 9.0, 0.6), Vector3(at.x, 4.5, at.z + sz * span / 2.0), "metal", g, true, 0.8)
	A.box(lv, Vector3(0.8, 0.8, span + 0.6), Vector3(at.x, 9.0, at.z), "metal", g, false, 0.8)
	for z in SIDINGS:   # a signal head over each road
		A.box(lv, Vector3(0.5, 1.4, 0.6), Vector3(at.x, 8.0, z), "enamel", Color(0.1, 0.1, 0.1), false, 0.4)
		var lit := Color(0.2, 1.0, 0.3) if int(absf(z)) % 12 == 0 else Color(1.0, 0.2, 0.15)
		A.glow(lv, Vector3(0.52, 0.22, 0.22), Vector3(at.x, 8.3 if lit.g > 0.5 else 7.8, z), lit, 3.0)


## A control tower: a concrete stalk with a glazed cab on top, lit inside.
static func _tower(lv: Node3D, at: Vector3, title: String) -> void:
	A.box(lv, Vector3(4.0, 12.0, 4.0), at + Vector3(0, 6.0, 0), "concrete", Color(0.7, 0.68, 0.64), true, 2.0)
	A.box(lv, Vector3(7.0, 0.4, 7.0), at + Vector3(0, 12.2, 0), "concrete", Color(0.6, 0.58, 0.55), true, 2.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			A.box(lv, Vector3(0.2, 3.0, 0.2), at + Vector3(sx * 3.3, 13.9, sz * 3.3), "metal", Color(0.3, 0.3, 0.3), false, 0.5)
	A.glow(lv, Vector3(6.4, 2.6, 6.4), at + Vector3(0, 13.8, 0), Color(1.0, 0.85, 0.6), 0.6)   # the lit glazing
	A.box(lv, Vector3(7.4, 0.5, 7.4), at + Vector3(0, 15.6, 0), "metal", Color(0.35, 0.35, 0.33), false, 1.0)
	B.label(lv, title, at + Vector3(0, 10.5, -2.02), 60, Color(0.25, 0.23, 0.2), "stencil", 0.012).rotation.y = PI
	for k in 2:
		A.box(lv, Vector3(1.2, 0.2, 2.5), at + Vector3(2.6, 1.0 + k * 2.4, 0), "grate", Color.WHITE, false, 0.5)


# --- the head office and its lot (north) -----------------------------------------------------------

static func _admin(lv: Node3D, rng: RandomNumberGenerator) -> void:
	_office(lv, Vector3(0, 0, 80), Vector3(44, 12.5, 14), rng)
	_clock_tower(lv, Vector3(26.5, 0, 74.5))
	# The canteen and the bunkhouses.
	_block(lv, Vector3(-36, 0, 86), Vector3(18, 4.5, 10), Color(0.75, 0.68, 0.55), "CANTEEN", rng)
	for k in 3:
		_block(lv, Vector3(40.0, 0, 62 + k * 12.0), Vector3(14, 3.6, 7), Color(0.55, 0.6, 0.55), "BUNKHOUSE %d" % (k + 1), rng)
	# The lot: trucks parked in the bays, a fuel bowser, a flagpole row.
	for k in 12:
		if rng.randf() < 0.65:
			truck(lv, Vector3(-31.4 + k * 3.2, 0.05, 53.5), PI + rng.randf_range(-0.04, 0.04), rng)   # (nose out of its bay)
	for k in 3:
		var fx := -12.0 + k * 12.0
		A.cyl(lv, 0.08, 14.0, Vector3(fx, 7.0, 66.0), "metal", Color(0.8, 0.8, 0.8), false)
		var flag := A.box(lv, Vector3(2.4, 1.4, 0.03), Vector3(fx + 1.2, 13.0, 66.0), "canvas", [Color(0.7, 0.2, 0.12), Color(0.85, 0.65, 0.15), Color(0.2, 0.3, 0.5)][k], false, 0.5)
		flag.set_meta("flag", true)
		flag.set_meta("live", true)
	_mast(lv, Vector3(-46, 0, 76), 46.0)
	P.water_tower(lv, Vector3(40.0, 0.06, 97.5))   # (clear of the side road: its legs stood in the lane)


## A Bureau office block: storeys of windows (some lit), a recessed entrance with steps and a sign,
## parapet, rooftop plant, downpipes.
static func _office(lv: Node3D, at: Vector3, size: Vector3, rng: RandomNumberGenerator) -> void:
	var c := Color(0.78, 0.74, 0.66)
	A.box(lv, size, at + Vector3(0, size.y / 2.0, 0), "concrete", c, true, 3.0)
	A.box(lv, Vector3(size.x + 0.6, 0.6, size.z + 0.6), at + Vector3(0, size.y + 0.3, 0), "concrete", c.darkened(0.12), false, 3.0)
	var floors := int(size.y / 3.8)
	for f in floors:
		var y := 2.2 + f * 3.8
		A.box(lv, Vector3(size.x + 0.12, 0.25, 0.3), at + Vector3(0, y - 1.3, -size.z / 2.0), "concrete", c.darkened(0.2), false, 2.0)   # floor band
		for k in int(size.x / 2.8):
			var x := -size.x / 2.0 + 1.6 + k * 2.8
			if f == 0 and absf(x) < 4.0:
				continue
			for side in [-1.0, 1.0]:
				var lit := rng.randf() < 0.45
				var w := Vector3(1.6, 1.8, 0.08)
				var pos := at + Vector3(x, y, side * (size.z / 2.0 + 0.02))
				if lit:
					A.glow(lv, w, pos, Color(1.0, 0.86, 0.62), 0.9)
				else:
					A.box(lv, w, pos, "metal", Color(0.12, 0.14, 0.16), false, 0.5)
				A.box(lv, Vector3(1.8, 0.12, 0.25), pos + Vector3(0, -0.98, side * 0.08), "concrete", c.darkened(0.1), false, 1.0)   # sill
	# The entrance: a dark recess, glass doors lit from inside, steps, the canopy and the sign.
	var door := at + Vector3(0, 0, -size.z / 2.0)
	A.box(lv, Vector3(6.0, 3.4, 0.2), door + Vector3(0, 1.7, -0.05), "metal", Color(0.15, 0.15, 0.15), false, 1.0)
	A.glow(lv, Vector3(4.0, 2.6, 0.1), door + Vector3(0, 1.4, -0.12), Color(1.0, 0.9, 0.7), 0.7)
	A.box(lv, Vector3(8.0, 0.3, 3.0), door + Vector3(0, 3.6, -1.4), "concrete", c.darkened(0.25), false, 2.0)
	for k in 3:
		A.box(lv, Vector3(9.0, 0.18, 1.0 - k * 0.3), door + Vector3(0, 0.09 + k * 0.18, -0.7 - (2 - k) * 0.3), "concrete", c.darkened(0.15), true, 2.0)
	var sg := B.label(lv, "BUREAU OF RECLAIMED MATERIALS", door + Vector3(0, size.y - 1.0, -0.35), 110, Color(0.9, 0.86, 0.75), "plate", 0.02)
	sg.rotation.y = PI
	var sub := B.label(lv, "DISTRICT OFFICE  -  CHECKPOINT 4", door + Vector3(0, 4.4, -0.32), 50, Color(0.85, 0.8, 0.7), "stencil", 0.012)
	sub.rotation.y = PI
	B.omni(lv, door + Vector3(0, 3.2, -2.0), Color(1, 0.86, 0.65), 1.5, 9.0)
	# Rooftop plant and the pipes down the walls.
	for k in 3:
		A.box(lv, Vector3(3.0, 1.6, 2.4), at + Vector3(-12.0 + k * 12.0, size.y + 0.8, 2.0), "metal", Color(0.55, 0.56, 0.55), false, 1.0)
		A.cyl(lv, 0.6, 0.3, at + Vector3(-12.0 + k * 12.0, size.y + 1.75, 2.0), "metal", Color(0.4, 0.4, 0.4), false)
	for x in [-size.x / 2.0 + 0.3, size.x / 2.0 - 0.3]:
		A.cyl(lv, 0.1, size.y, at + Vector3(x, size.y / 2.0, -size.z / 2.0 - 0.15), "metal", Color(0.45, 0.45, 0.42), false)


static func _clock_tower(lv: Node3D, at: Vector3) -> void:
	A.box(lv, Vector3(5, 22, 5), at + Vector3(0, 11, 0), "brick", Color(0.85, 0.7, 0.62), true, 2.0)
	A.box(lv, Vector3(5.8, 0.6, 5.8), at + Vector3(0, 22.3, 0), "concrete", Color(0.7, 0.66, 0.6), false, 2.0)
	A.prism(lv, Vector3(5.6, 3.5, 5.6), at + Vector3(0, 24.4, 0), "shingle", Color(0.5, 0.4, 0.35))
	var face := at + Vector3(0, 18.5, -2.52)
	A.cyl(lv, 1.7, 0.1, face, "cream", Color(0.95, 0.92, 0.84), false, "z")
	A.ring(lv, 1.8, 1.65, face + Vector3(0, 0, -0.06), "metal", Color(0.2, 0.2, 0.2), Vector3(PI / 2.0, 0, 0))
	for k in 12:
		var a := TAU * k / 12.0
		A.box(lv, Vector3(0.12, 0.35, 0.03), face + Vector3(sin(a) * 1.4, cos(a) * 1.4, -0.07), "metal", Color(0.1, 0.1, 0.1), false, 0.2, Vector3(0, 0, -a))
	var hands := Node3D.new()   # (yard_life turns them to the shift's hour)
	hands.name = "ClockHands"
	hands.set_meta("live", true)
	lv.add_child(hands)
	hands.position = face + Vector3(0, 0, -0.09)
	for k in 2:
		var hand := Node3D.new()
		hand.name = "H%d" % k
		hands.add_child(hand)
		A.box(hand, Vector3(0.12 if k == 0 else 0.08, 0.85 if k == 0 else 1.25, 0.03), Vector3(0, (0.85 if k == 0 else 1.25) * 0.4, -0.01 * k), "metal", Color(0.08, 0.08, 0.08), false, 0.2)


static func _block(lv: Node3D, at: Vector3, size: Vector3, c: Color, title: String, rng: RandomNumberGenerator) -> void:
	A.box(lv, size, at + Vector3(0, size.y / 2.0, 0), "siding", c, true, 2.0)
	var roof := A.box(lv, Vector3(size.x + 0.8, 0.2, size.z + 0.8), at + Vector3(0, size.y + 0.1, 0), "corrugated", Color(0.5, 0.48, 0.45), false, 2.0)
	roof.rotation.z = 0.04
	for k in int(size.x / 3.0):
		var x := -size.x / 2.0 + 1.5 + k * 3.0
		var lit := rng.randf() < 0.5
		var pos := at + Vector3(x, size.y * 0.55, -size.z / 2.0 - 0.02)
		if lit:
			A.glow(lv, Vector3(1.2, 1.0, 0.06), pos, Color(1.0, 0.85, 0.6), 0.8)
		else:
			A.box(lv, Vector3(1.2, 1.0, 0.06), pos, "metal", Color(0.12, 0.13, 0.14), false, 0.5)
	A.box(lv, Vector3(1.2, 2.2, 0.08), at + Vector3(size.x / 2.0 - 2.0, 1.1, -size.z / 2.0 - 0.03), "wood", Color(0.5, 0.4, 0.3), false, 0.6)
	var sg := B.label(lv, title, at + Vector3(0, size.y - 0.6, -size.z / 2.0 - 0.06), 60, Color(0.2, 0.18, 0.15), "stencil", 0.012)
	sg.rotation.y = PI


## A lattice radio mast with its red warning lamps (yard_life blinks the top one).
static func _mast(lv: Node3D, at: Vector3, h: float) -> void:
	var g := Color(0.75, 0.3, 0.2)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			A.seg(lv, at + Vector3(sx * 1.6, 0, sz * 1.6), at + Vector3(sx * 0.3, h, sz * 0.3), 0.08, 0.06, "paint", g)
	for k in int(h / 3.0):
		var y := k * 3.0
		var w := lerpf(1.6, 0.3, y / h)
		for e in 4:
			var a := Vector3(-w, y, -w).rotated(Vector3.UP, e * PI / 2.0)
			var b := Vector3(w, y + 3.0, -w).rotated(Vector3.UP, e * PI / 2.0) * Vector3(lerpf(1.0, 0.9, 0.1), 1, 1)
			A.seg(lv, at + a, at + b, 0.03, 0.03, "paint", g)
	var lamp := A.sphere(lv, 0.35, at + Vector3(0, h + 0.3, 0), "cream", Color(1, 0.15, 0.1), 6.0)
	lamp.name = "MastLamp"
	lamp.set_meta("live", true)
	A.sphere(lv, 0.25, at + Vector3(0, h * 0.5, 0.4), "cream", Color(1, 0.15, 0.1), 4.0)


## A cab-over lorry, nose toward -z: chassis rails, a two-tone cab (framed, raked windscreen, doors
## with windows and handles, a slatted grille, lamps in their housings, bumper, steps, mirrors on
## arms, a sun visor and roof lamps), the exhaust stack and fuel tank behind it, dual rear wheels with
## hubs, mudguards and flaps, and a ribbed box van with rear doors or a staked flatbed. Weathered.
## Parked here; yard_life drives some about.
## parts (a Dictionary, for one that drives: yard_life.gd): each wheel built on its own pivots
## (parts.wheels: [steer, spin, front?]), and the windows left clear to see the driver through.
static func truck(parent: Node, at: Vector3, yaw: float, rng: RandomNumberGenerator, solid := true, parts = null) -> Node3D:
	var r := P._root(parent, at, yaw, Vector3(2.5, 3.4, 7.6) if solid else Vector3.ZERO)
	var cab: Color = [Color(0.85, 0.65, 0.15), Color(0.7, 0.2, 0.12), Color(0.25, 0.35, 0.5), Color(0.82, 0.8, 0.74), Color(0.35, 0.45, 0.32)][rng.randi() % 5]
	var dark := Color(0.13, 0.13, 0.13)
	var steel := Color(0.45, 0.45, 0.43)
	# Chassis.
	for sx in [-0.45, 0.45]:
		A.box(r, Vector3(0.18, 0.3, 7.0), Vector3(sx, 0.85, 0.1), "metal", dark, false, 0.6)
	for z in [-2.9, -1.2, 0.6, 2.2, 3.4]:
		A.box(r, Vector3(0.9, 0.12, 0.14), Vector3(0, 0.85, z), "metal", dark, false, 0.4)
	# Wheels: single at the front, twinned on the two rear axles.
	for w in [[-2.55, false], [1.75, true], [2.95, true]]:
		for sx in [-1.0, 1.0]:
			var host: Node3D = r
			var base := Vector3.ZERO
			if parts != null:   # (on pivots: it steers, if it's at the front, and turns)
				var steer := Node3D.new()
				r.add_child(steer)
				steer.position = Vector3(sx * 1.06, 0.5, w[0])
				steer.set_meta("live", true)
				var spin := Node3D.new()
				steer.add_child(spin)
				host = spin
				base = steer.position
				parts.wheels.append([steer, spin, w[0] < 0.0])
			for t in ([1.06, 0.72] if w[1] else [1.06]):
				var wp := Vector3(sx * t, 0.5, w[0]) - base
				A.cyl(host, 0.5, 0.32, wp, "rubber", Color(0.9, 0.9, 0.9), false, "x")
				if t > 1.0:   # the hub on the outside
					A.cyl(host, 0.3, 0.33, wp, "metal", Color(0.55, 0.52, 0.48), false, "x")
					A.cyl(host, 0.13, 0.36, wp, "metal", Color(0.3, 0.3, 0.3), false, "x")
					for n in 6:
						var na := TAU * n / 6.0
						A.cyl(host, 0.025, 0.37, wp + Vector3(0, sin(na) * 0.2, cos(na) * 0.2), "metal", Color(0.25, 0.25, 0.25), false, "x")
		A.box(r, Vector3(2.0, 0.14, 0.14), Vector3(0, 0.5, w[0]), "metal", dark, false, 0.4)   # axle
	for sx in [-1.0, 1.0]:   # mudguards over the front wheels, over the back ones, flaps behind
		A.box(r, Vector3(0.4, 0.05, 1.0), Vector3(sx * 1.06, 1.08, -2.55), "metal", dark, false, 0.4)
		for e in [-1.0, 1.0]:
			A.box(r, Vector3(0.4, 0.05, 0.4), Vector3(sx * 1.06, 0.95, -2.55 + e * 0.62), "metal", dark, false, 0.4, Vector3(e * 0.7, 0, 0))
		A.box(r, Vector3(0.6, 0.5, 0.03), Vector3(sx * 0.9, 0.55, 3.6), "rubber", Color.WHITE, false, 0.4)
		A.box(r, Vector3(0.6, 0.05, 2.0), Vector3(sx * 0.9, 1.06, 2.35), "metal", dark, false, 0.4)
	# The cab.
	var cz := -2.65   # its middle; the front is at -3.7
	A.box(r, Vector3(2.4, 1.05, 2.1), Vector3(0, 1.45, cz), "enamel", cab, false, 0.8)
	A.box(r, Vector3(2.42, 0.32, 2.12), Vector3(0, 1.08, cz), "rust", cab.darkened(0.35), false, 0.8)   # road grime up the lower panels
	A.box(r, Vector3(2.36, 1.12, 1.95), Vector3(0, 2.53, cz + 0.07), "enamel", cab, false, 0.8)
	A.box(r, Vector3(2.4, 0.12, 2.02), Vector3(0, 3.15, cz + 0.06), "enamel", cab.darkened(0.15), false, 0.8)   # roof
	A.box(r, Vector3(2.0, 0.35, 1.2), Vector3(0, 3.38, cz + 0.3), "enamel", cab.darkened(0.08), false, 0.8)    # roof pod
	for x in [-0.5, 0.0, 0.5]:
		A.glow(r, Vector3(0.14, 0.07, 0.05), Vector3(x, 3.27, cz - 1.02), Color(1.0, 0.6, 0.15), 1.2)   # marker lamps
	var ws := A.box(r, Vector3(2.0, 0.95, 0.02), Vector3(0, 2.55, cz - 0.92), "metal", Color.WHITE, false, 0.5)
	ws.rotation.x = -0.08
	ws.material_override = A.glass()
	if parts == null:
		A.box(r, Vector3(2.0, 0.95, 0.01), Vector3(0, 2.55, cz - 0.88), "fabric", Color(0.12, 0.11, 0.1), false, 0.5).rotation.x = -0.08   # (the dark cab seen through it)
	else:   # a cab you can see into: the dash, the wheel, the seats
		A.box(r, Vector3(2.2, 0.45, 0.4), Vector3(0, 2.15, cz - 0.7), "plastic", Color(0.12, 0.12, 0.12), false, 0.5)
		A.cyl(r, 0.2, 0.03, Vector3(-0.55, 2.45, cz - 0.55), "rubber", Color.WHITE, false, "z").rotation.x = PI / 2.0 - 0.6
		for x in [-0.55, 0.55]:
			A.box(r, Vector3(0.55, 0.12, 0.5), Vector3(x, 1.98, cz + 0.05), "canvas", Color(0.18, 0.18, 0.17), false, 0.4)
			A.box(r, Vector3(0.55, 0.7, 0.12), Vector3(x, 2.35, cz + 0.32), "canvas", Color(0.18, 0.18, 0.17), false, 0.4)
		A.box(r, Vector3(2.3, 1.0, 0.05), Vector3(0, 2.5, cz + 0.85), "enamel", Color(0.2, 0.2, 0.2), false, 0.5)   # the cab's back wall
	for sx in [-1.0, 1.0]:
		A.box(r, Vector3(0.14, 1.05, 0.1), Vector3(sx * 1.1, 2.55, cz - 0.93), "enamel", cab.darkened(0.1), false, 0.5, Vector3(-0.08, 0, 0))   # A-pillars
	A.box(r, Vector3(2.36, 0.1, 0.12), Vector3(0, 3.04, cz - 0.95), "enamel", cab.darkened(0.1), false, 0.5)
	A.box(r, Vector3(2.36, 0.12, 0.12), Vector3(0, 2.04, cz - 0.95), "enamel", cab.darkened(0.1), false, 0.5)
	A.box(r, Vector3(2.3, 0.05, 0.32), Vector3(0, 3.1, cz - 1.12), "metal", dark, false, 0.4, Vector3(0.25, 0, 0))   # sun visor
	for sx in [-0.5, 0.5]:
		A.box(r, Vector3(0.6, 0.025, 0.02), Vector3(sx, 2.12, cz - 0.99), "metal", dark, false, 0.3, Vector3(0, 0, sx * 0.6))   # wipers
	# Doors: a window, seams, a handle, steps up to them.
	for sx in [-1.0, 1.0]:
		var dx: float = sx * 1.205
		var gl := A.box(r, Vector3(0.01, 0.75, 1.0), Vector3(dx, 2.55, cz - 0.15), "metal", Color.WHITE, false, 0.4)
		gl.material_override = A.glass()
		if parts == null:
			A.box(r, Vector3(0.012, 0.74, 0.99), Vector3(sx * 1.192, 2.55, cz - 0.15), "fabric", Color(0.12, 0.11, 0.1), false, 0.4)
		for e in [-1.0, 1.0]:
			A.box(r, Vector3(0.015, 2.1, 0.03), Vector3(dx, 2.0, cz - 0.15 + e * 0.6), "metal", dark, false, 0.3)   # door seams
		A.box(r, Vector3(0.04, 0.05, 0.22), Vector3(sx * 1.22, 1.85, cz + 0.25), "metal", Color(0.7, 0.7, 0.68), false, 0.3)   # handle
		for k in 2:
			A.box(r, Vector3(0.3, 0.04, 0.55), Vector3(sx * 1.05, 0.55 + k * 0.32, cz - 0.15), "grate", Color.WHITE, false, 0.3)
		# Mirrors on their arms.
		A.seg(r, Vector3(sx * 1.2, 2.9, cz - 0.85), Vector3(sx * 1.48, 2.85, cz - 0.95), 0.025, 0.025, "metal", dark)
		A.seg(r, Vector3(sx * 1.2, 2.2, cz - 0.85), Vector3(sx * 1.48, 2.3, cz - 0.95), 0.025, 0.025, "metal", dark)
		A.box(r, Vector3(0.07, 0.6, 0.24), Vector3(sx * 1.5, 2.58, cz - 0.95), "metal", dark, false, 0.3)
	# The face: grille slats in a dark surround, lamps in their housings, indicators, the bumper.
	A.box(r, Vector3(1.6, 0.62, 0.04), Vector3(0, 1.55, cz - 1.06), "metal", Color(0.08, 0.08, 0.08), false, 0.4)
	for k in 5:
		A.box(r, Vector3(1.56, 0.05, 0.06), Vector3(0, 1.32 + k * 0.115, cz - 1.08), "metal", Color(0.55, 0.55, 0.53), false, 0.3)
	for sx in [-1.0, 1.0]:
		A.box(r, Vector3(0.42, 0.3, 0.06), Vector3(sx * 0.98, 1.2, cz - 1.07), "metal", Color(0.1, 0.1, 0.1), false, 0.3)
		A.glow(r, Vector3(0.32, 0.2, 0.04), Vector3(sx * 0.98, 1.2, cz - 1.1), Color(1, 0.95, 0.8), 1.5)
		A.glow(r, Vector3(0.14, 0.12, 0.04), Vector3(sx * 0.98, 1.47, cz - 1.08), Color(1.0, 0.55, 0.1), 0.8)
	A.box(r, Vector3(2.5, 0.34, 0.24), Vector3(0, 0.78, cz - 1.12), "metal", Color(0.3, 0.3, 0.3), false, 0.5)   # bumper
	A.box(r, Vector3(2.0, 0.08, 0.02), Vector3(0, 0.9, cz - 1.25), "hazard", Color.WHITE, false, 0.4)
	# Behind the cab: exhaust stack, air intake, fuel tank, battery box.
	A.cyl(r, 0.08, 2.5, Vector3(0.95, 2.25, cz + 1.15), "metal", Color(0.3, 0.28, 0.26), false)
	A.cyl(r, 0.11, 0.5, Vector3(0.95, 2.5, cz + 1.15), "grate", Color.WHITE, false)   # heat shield
	A.cyl(r, 0.12, 0.06, Vector3(0.95, 3.52, cz + 1.15), "metal", dark, false)
	A.cyl(r, 0.16, 1.4, Vector3(-0.95, 2.4, cz + 1.15), "metal", Color(0.4, 0.4, 0.38), false)
	A.cyl(r, 0.3, 1.2, Vector3(-1.0, 0.85, -0.7), "metal", Color(0.62, 0.62, 0.6), false, "z")
	for z in [-1.1, -0.3]:
		A.box(r, Vector3(0.64, 0.05, 0.06), Vector3(-1.0, 1.16, z), "metal", dark, false, 0.3)
	A.box(r, Vector3(0.5, 0.45, 0.7), Vector3(1.0, 0.85, -0.7), "metal", dark, false, 0.4)
	# The body.
	var bz := 1.25
	if rng.randf() < 0.5:   # box van: ribbed sides, frame, rear doors with lock bars
		var bc: Color = [Color(0.78, 0.76, 0.7), Color(0.4, 0.45, 0.5), Color(0.55, 0.3, 0.2)][rng.randi() % 3]
		A.box(r, Vector3(2.45, 2.5, 4.8), Vector3(0, 2.3, bz), "corrugated", bc, false, 1.0)
		for e in [-1.0, 1.0]:
			A.box(r, Vector3(2.5, 0.1, 0.1), Vector3(0, 3.55, bz + e * 2.42), "metal", steel, false, 0.4)
			A.box(r, Vector3(2.5, 0.12, 0.1), Vector3(0, 1.08, bz + e * 2.42), "metal", steel, false, 0.4)
			for sx in [-1.0, 1.0]:
				A.box(r, Vector3(0.1, 2.5, 0.1), Vector3(sx * 1.24, 2.3, bz + e * 2.42), "metal", steel, false, 0.4)
		for sx in [-1.0, 1.0]:
			for y in [1.08, 3.55]:
				A.box(r, Vector3(0.08, 0.1, 4.8), Vector3(sx * 1.24, y, bz), "metal", steel, false, 0.4)
		var back: float = bz + 2.41
		A.box(r, Vector3(2.4, 2.4, 0.03), Vector3(0, 2.3, back + 0.04), "riveted", bc.darkened(0.1), false, 0.6)
		A.box(r, Vector3(0.03, 2.4, 0.05), Vector3(0, 2.3, back + 0.06), "metal", dark, false, 0.3)
		for x in [-0.8, -0.3, 0.3, 0.8]:   # lock bars and their handles
			A.cyl(r, 0.025, 2.35, Vector3(x, 2.3, back + 0.09), "metal", steel, false)
			A.box(r, Vector3(0.05, 0.3, 0.05), Vector3(x + 0.06, 1.7, back + 0.12), "metal", steel, false, 0.3)
		for sx in [-1.0, 1.0]:
			for y in [1.5, 2.3, 3.1]:
				A.box(r, Vector3(0.18, 0.1, 0.06), Vector3(sx * 1.12, y, back + 0.08), "metal", dark, false, 0.3)   # hinges
	else:   # flatbed: deck, headboard, stake posts, low side boards, a load
		A.box(r, Vector3(2.45, 0.15, 4.8), Vector3(0, 1.1, bz), "wood", Color(0.6, 0.5, 0.4), false, 0.8)
		A.box(r, Vector3(2.45, 1.3, 0.08), Vector3(0, 1.82, bz - 2.36), "grate", Color.WHITE, false, 0.4)
		A.box(r, Vector3(2.5, 0.1, 0.12), Vector3(0, 2.5, bz - 2.36), "metal", steel, false, 0.4)
		for sx in [-1.0, 1.0]:
			A.box(r, Vector3(0.05, 0.3, 4.8), Vector3(sx * 1.2, 1.32, bz), "wood", Color(0.5, 0.42, 0.34), false, 0.8)
			for k in 5:
				A.box(r, Vector3(0.08, 0.7, 0.08), Vector3(sx * 1.25, 1.45, bz - 2.0 + k * 1.0), "metal", steel, false, 0.3)
		for k in rng.randi_range(0, 3):
			P.bale(r, Vector3(-0.55 + (k % 2) * 1.1, 1.18, bz - 1.0 + (k / 2) * 1.4), 0.95, rng)
	# Tail: lamps and the underrun bar.
	A.box(r, Vector3(2.3, 0.12, 0.1), Vector3(0, 0.75, bz + 2.55), "metal", Color(0.3, 0.3, 0.3), false, 0.4)
	for sx in [-1.0, 1.0]:
		A.glow(r, Vector3(0.25, 0.14, 0.04), Vector3(sx * 0.95, 0.95, bz + 2.5), Color(0.9, 0.12, 0.08), 0.8)
	return r


## A diesel engine, nose toward +x, rail heads at y = 0, `ln` long. Road switcher (a long hood, the
## cab, a short nose, a plow) or, with `end_cab`, a yard switcher (the long hood all the way to an end
## cab). Trucks with cast side frames, springs and journal boxes; the frame with its sill stripe and
## fuel tank; the hood's doors, louvres, radiator grilles and roof fans; the cab's framed windows,
## roof, horn and beacon; walkway rails, steps, headlights, number boards, couplers. One mesh when
## merged (yard_life merges what it builds).
static func loco(parent: Node, ln: float, body: Color, number: String, end_cab := false) -> Node3D:
	var r := Node3D.new()
	parent.add_child(r)
	var dark := Color(0.16, 0.16, 0.16)
	var trim := body.darkened(0.35)
	var rail := Color(0.9, 0.75, 0.2)
	var deck := 1.35
	var h0 := -ln / 2.0
	var h1 := ln / 2.0
	# Trucks.
	var axles := 2 if end_cab else 3
	for tx in [h0 + 2.2, h1 - 2.2]:
		var half := (axles - 1) * 1.05 / 2.0
		for s in [-1.0, 1.0]:
			A.box(r, Vector3(half * 2.0 + 1.0, 0.2, 0.14), Vector3(tx, 0.58, s * 0.98), "metal", dark, false, 0.6)
			A.box(r, Vector3(half * 2.0 + 0.6, 0.12, 0.14), Vector3(tx, 0.36, s * 0.98), "metal", dark, false, 0.6)
			for k in axles:
				var ax: float = tx - half + k * 1.05
				A.box(r, Vector3(0.3, 0.36, 0.2), Vector3(ax, 0.46, s * 1.0), "metal", Color(0.26, 0.25, 0.24), false, 0.4)   # journal box
				A.cyl(r, 0.46, 0.12, Vector3(ax, 0.46, s * 0.72), "metal", Color(0.3, 0.29, 0.28), false, "z")   # wheel
				A.cyl(r, 0.2, 0.14, Vector3(ax, 0.46, s * 0.72), "metal", Color(0.4, 0.38, 0.36), false, "z")
			for k in axles - 1:
				A.cyl(r, 0.07, 0.3, Vector3(tx - half + (k + 0.5) * 1.05, 0.5, s * 1.0), "metal", Color(0.55, 0.52, 0.48), false)   # springs
		A.box(r, Vector3(0.5, 0.3, 2.0), Vector3(tx, 0.82, 0), "metal", dark, false, 0.5)   # bolster
	# Frame, sill stripe, deck plate, end sills, fuel tank, air tanks.
	A.box(r, Vector3(ln, 0.42, 2.7), Vector3(0, 1.1, 0), "metal", dark, false, 0.6)
	for s in [-1.0, 1.0]:
		A.box(r, Vector3(ln, 0.3, 0.05), Vector3(0, 1.18, s * 1.47), "enamel", body, false, 0.8)
		A.box(r, Vector3(ln, 0.07, 0.055), Vector3(0, 1.0, s * 1.48), "hazard", Color.WHITE, false, 0.4)
	A.box(r, Vector3(ln + 0.1, 0.06, 3.0), Vector3(0, deck + 0.0, 0), "riveted", Color(0.42, 0.4, 0.38), false, 1.0)
	for e in [-1.0, 1.0]:
		A.box(r, Vector3(0.25, 0.55, 3.0), Vector3(e * (ln / 2.0 + 0.1), 1.08, 0), "enamel", body, false, 0.8)
		A.box(r, Vector3(0.01, 0.4, 2.8), Vector3(e * (ln / 2.0 + 0.23), 1.08, 0), "hazard", Color.WHITE, false, 0.5)   # chevrons
		A.box(r, Vector3(0.5, 0.22, 0.3), Vector3(e * (ln / 2.0 + 0.4), 0.85, 0), "metal", dark, false)   # coupler
		A.box(r, Vector3(0.25, 0.3, 0.32), Vector3(e * (ln / 2.0 + 0.7), 0.85, 0), "metal", Color(0.3, 0.29, 0.28), false)
		for s in [-1.0, 1.0]:   # steps at the corners, a grab iron
			for k in 2:
				A.box(r, Vector3(0.55, 0.04, 0.3), Vector3(e * (ln / 2.0 - 0.45), 0.95 - k * 0.32, s * 1.62), "grate", Color.WHITE, false, 0.3)
			A.box(r, Vector3(0.04, 0.6, 0.32), Vector3(e * (ln / 2.0 - 0.17), 0.85, s * 1.62), "metal", dark, false)
			A.seg(r, Vector3(e * (ln / 2.0 - 0.1), deck, s * 1.45), Vector3(e * (ln / 2.0 - 0.1), deck + 1.0, s * 1.45), 0.022, 0.022, "metal", rail)
		for y in [0.55, 1.0]:   # end rail across
			A.seg(r, Vector3(e * (ln / 2.0 - 0.1), deck + y, -1.45), Vector3(e * (ln / 2.0 - 0.1), deck + y, 1.45), 0.02, 0.02, "metal", rail)
	var tl := ln * 0.3
	A.box(r, Vector3(tl, 0.7, 2.0), Vector3(0, 0.62, 0), "enamel", Color(0.25, 0.25, 0.26), false, 0.8)
	for s in [-1.0, 1.0]:
		A.cyl(r, 0.35, tl, Vector3(0, 0.62, s * 1.0), "enamel", Color(0.25, 0.25, 0.26), false, "x")
		A.cyl(r, 0.16, tl * 0.8, Vector3(0, 0.85, s * 1.32), "metal", Color(0.4, 0.4, 0.42), false, "x")
	# Where the cab goes: at the back end for a yard switcher, a little behind the front otherwise.
	var cw := 2.4
	var c1 := (h0 + 0.15 + cw) if end_cab else (h1 - 1.4)
	var c0 := c1 - cw
	var nose_x := c1   # (road switcher: the short nose from the cab to the front)
	# The long hood.
	var la := (c1 + 0.05) if end_cab else (h0 + 0.5)
	var lb := (h1 - 0.5) if end_cab else (c0 - 0.05)
	var lc := (la + lb) / 2.0
	var ll := lb - la
	var hh := 2.1
	A.box(r, Vector3(ll, hh, 1.9), Vector3(lc, deck + hh / 2.0, 0), "enamel", body, false, 1.0)
	A.box(r, Vector3(ll - 0.04, 0.2, 1.5), Vector3(lc, deck + hh + 0.1, 0), "enamel", body.darkened(0.08), false, 1.0)
	A.box(r, Vector3(ll + 0.02, 0.32, 1.92), Vector3(lc, deck + 0.16, 0), "rust", trim, false, 0.8)   # grime along its foot
	for s in [-1.0, 1.0]:
		var z: float = s * 0.955
		var k := 0
		var dx := la + 0.5
		while dx < lb - 0.4:   # access doors: seams, a handle each, louvres high up
			A.box(r, Vector3(0.03, hh - 0.25, 0.02), Vector3(dx, deck + hh / 2.0, z), "metal", dark, false)
			A.box(r, Vector3(0.06, 0.1, 0.04), Vector3(dx + 0.5, deck + 1.0, z + s * 0.01), "metal", Color(0.7, 0.7, 0.68), false)
			if k % 2 == 0:
				for j in 4:
					A.box(r, Vector3(0.6, 0.04, 0.05), Vector3(dx + 0.48, deck + 1.5 + j * 0.12, z + s * 0.02), "metal", trim, false, 0.3, Vector3(0.5 * s, 0, 0))
			dx += 1.0
			k += 1
		var rx := (lb - 0.95) if end_cab else (la + 0.95)   # radiator grilles at the far end of the hood
		A.box(r, Vector3(1.5, 1.2, 0.03), Vector3(rx, deck + 1.2, z + s * 0.005), "grille", Color.WHITE, false, 0.3)
		A.box(r, Vector3(1.6, 1.3, 0.02), Vector3(rx, deck + 1.2, z), "metal", dark, false)
		var nb := B.label(r, number, Vector3(lc, deck + 0.75, z + s * 0.02), 80, Color(0.92, 0.88, 0.78), "stencil", 0.008)
		nb.rotation.y = 0.0 if s > 0 else PI
		# Walkway handrails along the hood.
		var px := la
		while px <= lb + 0.01:
			A.seg(r, Vector3(px, deck, s * 1.45), Vector3(px, deck + 1.0, s * 1.45), 0.02, 0.02, "metal", rail)
			px += 1.2
		for y in [0.55, 1.0]:
			A.seg(r, Vector3(la, deck + y, s * 1.45), Vector3(lb, deck + y, s * 1.45), 0.02, 0.02, "metal", rail)
	var fx := (lb - 0.95) if end_cab else (la + 0.95)
	for k in 2:   # roof fans over the radiators, the exhaust stack
		var fz := fx + (k - 0.5) * 0.75
		A.cyl(r, 0.34, 0.06, Vector3(fz, deck + hh + 0.22, 0), "grille", Color.WHITE, false)
		A.ring(r, 0.36, 0.3, Vector3(fz, deck + hh + 0.24, 0), "metal", dark)
	var ex := lc + (0.6 if end_cab else -0.4)
	A.box(r, Vector3(0.5, 0.12, 0.4), Vector3(ex, deck + hh + 0.24, 0), "metal", dark, false)
	A.cyl(r, 0.13, 0.55, Vector3(ex, deck + hh + 0.5, 0), "rust", Color(0.55, 0.5, 0.48), false)
	A.cyl(r, 0.16, 0.05, Vector3(ex, deck + hh + 0.78, 0), "rust", Color(0.35, 0.3, 0.28), false)
	A.box(r, Vector3(0.05, 1.2, 0.8), Vector3(lb + (0.02 if end_cab else -0.0), deck + 1.1, 0), "metal", trim, false)   # end door
	# The cab.
	var ch := 2.65
	var ccx := (c0 + c1) / 2.0
	A.box(r, Vector3(cw, ch, 2.75), Vector3(ccx, deck + ch / 2.0, 0), "enamel", body, false, 1.0)
	A.box(r, Vector3(cw + 0.02, 0.32, 2.77), Vector3(ccx, deck + 0.16, 0), "rust", trim, false, 0.8)
	A.box(r, Vector3(cw + 0.35, 0.12, 3.0), Vector3(ccx, deck + ch + 0.06, 0), "enamel", trim, false, 0.8)   # roof
	for s in [-1.0, 1.0]:
		A.cyl(r, 0.07, cw + 0.35, Vector3(ccx, deck + ch + 0.02, s * 1.47), "enamel", trim, false, "x")   # drip rail
		var z: float = s * 1.385
		for k in 2:   # side windows, framed
			var wx := c0 + 0.55 + k * 1.15
			A.box(r, Vector3(0.85, 0.72, 0.02), Vector3(wx, deck + 1.95, z), "metal", Color(0.05, 0.06, 0.07), false)
			var g = A.box(r, Vector3(0.8, 0.68, 0.01), Vector3(wx, deck + 1.95, z + s * 0.015), "metal", Color.WHITE, false)
			g.material_override = A.glass()
			for y in [-0.38, 0.38]:
				A.box(r, Vector3(0.92, 0.05, 0.05), Vector3(wx, deck + 1.95 + y, z + s * 0.02), "metal", dark, false)
			for e in [-0.44, 0.44]:
				A.box(r, Vector3(0.05, 0.8, 0.05), Vector3(wx + e, deck + 1.95, z + s * 0.02), "metal", dark, false)
		A.seg(r, Vector3(c0 + 0.08, deck + 0.4, z + s * 0.06), Vector3(c0 + 0.08, deck + 1.9, z + s * 0.06), 0.022, 0.022, "metal", rail)   # grab irons
		A.seg(r, Vector3(c1 - 0.08, deck + 0.4, z + s * 0.06), Vector3(c1 - 0.08, deck + 1.9, z + s * 0.06), 0.022, 0.022, "metal", rail)
	for e in [[c1, 1.0], [c0, -1.0]]:   # front and back windows, the number board over them
		var wx: float = e[0] + e[1] * 0.006
		for wz in [-0.62, 0.62]:
			A.box(r, Vector3(0.02, 0.72, 0.95), Vector3(wx, deck + 2.0, wz), "metal", Color(0.05, 0.06, 0.07), false)
			var g = A.box(r, Vector3(0.01, 0.68, 0.9), Vector3(wx + e[1] * 0.012, deck + 2.0, wz), "metal", Color.WHITE, false)
			g.material_override = A.glass()
			A.box(r, Vector3(0.04, 0.05, 1.0), Vector3(wx + e[1] * 0.02, deck + 2.38, wz), "metal", dark, false)
			A.box(r, Vector3(0.04, 0.05, 1.0), Vector3(wx + e[1] * 0.02, deck + 1.62, wz), "metal", dark, false)
		A.box(r, Vector3(0.05, 0.2, 0.7), Vector3(e[0] + e[1] * 0.025, deck + ch - 0.18, 0), "metal", Color(0.06, 0.06, 0.06), false)
		A.glow(r, Vector3(0.02, 0.16, 0.66), Vector3(e[0] + e[1] * 0.05, deck + ch - 0.18, 0), Color(0.95, 0.9, 0.75), 1.0)
		var num := B.label(r, number, Vector3(e[0] + e[1] * 0.065, deck + ch - 0.18, 0), 50, Color(0.1, 0.08, 0.06), "stencil", 0.004)
		num.rotation.y = PI / 2.0 * e[1]
	for k in 3:   # the horn, a beacon, an aerial
		A.seg(r, Vector3(ccx - 0.25 + k * 0.2, deck + ch + 0.12, -0.6), Vector3(ccx - 0.25 + k * 0.2 + (0.22 if k == 1 else -0.22), deck + ch + 0.22, -0.6), 0.03, 0.08, "metal", Color(0.65, 0.65, 0.62))
	A.cyl(r, 0.1, 0.16, Vector3(ccx + 0.4, deck + ch + 0.2, 0.4), "cream", Color(1, 0.55, 0.1), false).material_override = A.mat("cream", Color(1, 0.55, 0.1), 1.0, 2.0)
	A.seg(r, Vector3(ccx - 0.5, deck + ch + 0.12, 0.6), Vector3(ccx - 0.5, deck + ch + 0.9, 0.6), 0.012, 0.006, "metal", Color(0.3, 0.3, 0.3))
	# The short nose (road switcher), sloped on top, with its own door.
	if not end_cab:
		var n1 := h1 - 0.5
		var nl := n1 - nose_x
		A.box(r, Vector3(nl, 1.3, 1.7), Vector3(nose_x + nl / 2.0, deck + 0.65, 0), "enamel", body, false, 1.0)
		A.box(r, Vector3(nl + 0.04, 0.08, 1.7), Vector3(nose_x + nl / 2.0 + 0.02, deck + 1.33, 0), "enamel", trim, false, 1.0, Vector3(0, 0, -0.12))
		A.box(r, Vector3(0.04, 1.0, 0.6), Vector3(n1 + 0.02, deck + 0.6, 0), "metal", trim, false)
		for s in [-1.0, 1.0]:
			A.seg(r, Vector3(nose_x, deck + 1.0, s * 1.45), Vector3(n1 + 0.4, deck + 1.0, s * 1.45), 0.02, 0.02, "metal", rail)
			A.seg(r, Vector3(nose_x, deck + 0.55, s * 1.45), Vector3(n1 + 0.4, deck + 0.55, s * 1.45), 0.02, 0.02, "metal", rail)
		# The plow under the front.
		var tip := Vector3(h1 + 0.95, 0.32, 0)
		for s in [-1.0, 1.0]:
			var wing := Vector3(h1 + 0.25, 0.32, s * 1.4)
			var run := wing - tip
			var blade := A.box(r, Vector3(run.length(), 0.45, 0.06), (tip + wing) / 2.0, "plow", Color(0.92, 0.85, 0.78), false, 1.0)
			blade.rotation = Vector3(0, atan2(-run.z, run.x), 0)
	# Headlights at both ends (the front burning, the back dim); ditch lights at the front corners.
	var lamps := []
	if end_cab:
		lamps = [[lb + 0.03, deck + hh - 0.3, 1.0], [c0 - 0.03, deck + ch - 0.6, -1.0]]
	else:
		lamps = [[h1 - 0.46, deck + 1.05, 1.0], [la - 0.03, deck + hh - 0.3, -1.0]]
	for lm in lamps:
		var e: float = lm[2]
		for hz in [-0.3, 0.3]:
			A.cyl(r, 0.14, 0.1, Vector3(lm[0], lm[1], hz), "metal", dark, false, "x")
			A.glow(r, Vector3(0.03, 0.18, 0.18), Vector3(lm[0] + e * 0.06, lm[1], hz), Color(1, 0.9, 0.65), 4.0 if e > 0 else 0.6)
	for s in [-1.0, 1.0]:
		A.cyl(r, 0.1, 0.16, Vector3(h1 + 0.32, deck + 0.25, s * 1.2), "metal", dark, false, "x")
		A.glow(r, Vector3(0.02, 0.15, 0.15), Vector3(h1 + 0.41, deck + 0.25, s * 1.2), Color(1, 0.92, 0.7), 3.0)
	return r


# --- the container terminal (west) ----------------------------------------------------------------

static func _terminal(lv: Node3D, rng: RandomNumberGenerator) -> void:
	# Blocks of stacks with lanes between, highest in the middle.
	for bx in 4:
		for bz in 3:
			var x0 := -142.0 + bx * 22.0
			var z0 := 22.0 + bz * 28.0
			for i in 6:
				for j in 2:
					var h := rng.randi_range(1, 4)
					if rng.randf() < 0.12:
						continue
					for k in h:
						P.shipping_container(lv, Vector3(x0 + i * 2.6, 0.06 + k * 2.62, z0 + j * 6.4), rng.randf_range(-0.02, 0.02), CC[rng.randi() % CC.size()], rng)
	# The big gantry crane straddling the stacks (yard_life runs its trolley).
	var gx := -102.0
	var g := Color(0.85, 0.6, 0.12)
	for sz in [-1.0, 1.0]:
		var z: Variant = 58.0 + sz * 42.0
		A.box(lv, Vector3(110.0, 0.2, 0.4), Vector3(gx, 0.1, z), "metal", Color(0.4, 0.4, 0.4), false, 1.0)   # its rails
		for e in [-1.0, 1.0]:   # an end stop at each end of them
			A.box(lv, Vector3(0.6, 0.7, 1.0), Vector3(gx + e * 55.3, 0.35, z), "concrete", Color(0.7, 0.68, 0.64), false, 1.0)
			A.box(lv, Vector3(0.12, 0.5, 0.9), Vector3(gx + e * 54.95, 0.45, z), "hazard", Color.WHITE, false, 0.4)
	var crane := Node3D.new()
	crane.name = "TerminalCrane"
	crane.set_meta("live", true)
	lv.add_child(crane)
	crane.position = Vector3(gx, 0, 58.0)
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			A.box(crane, Vector3(0.9, 18.0, 0.9), Vector3(sx * 4.5, 9.0, sz * 42.0), "enamel", g, false, 0.8)
		A.box(crane, Vector3(11.0, 1.2, 1.4), Vector3(0, 0.9, sz * 42.0), "enamel", g.darkened(0.3), false, 0.8)
	for sx in [-1.0, 1.0]:
		A.box(crane, Vector3(1.2, 2.0, 86.0), Vector3(sx * 4.5, 18.6, 0), "enamel", g, false, 1.0)
	var trolley := Node3D.new()
	trolley.name = "Trolley"
	crane.add_child(trolley)
	A.box(trolley, Vector3(10.0, 1.8, 4.0), Vector3(0, 17.8, 0), "enamel", g.darkened(0.15), false, 0.8)
	A.box(trolley, Vector3(2.6, 2.4, 2.4), Vector3(0, 15.6, -1.0), "metal", Color(0.3, 0.3, 0.3), false, 0.5)   # the cab
	A.glow(trolley, Vector3(2.4, 1.0, 0.05), Vector3(0, 15.9, -2.22), Color(1, 0.85, 0.6), 0.6)
	var spreader := Node3D.new()
	spreader.name = "Spreader"
	trolley.add_child(spreader)
	spreader.position.y = 12.0
	A.box(spreader, Vector3(2.6, 0.5, 6.2), Vector3.ZERO, "enamel", g, false, 0.5)
	for sx in [-1.0, 1.0]:
		A.seg(spreader, Vector3(sx * 0.8, 0.25, 0), Vector3(sx * 0.8, 5.0, 0), 0.03, 0.03, "metal", Color(0.2, 0.2, 0.2))


# --- the scrap works (east) -------------------------------------------------------------------------

static func _scrapworks(lv: Node3D, rng: RandomNumberGenerator) -> void:
	for p in [[Vector3(89, 0, 57), 3.6], [Vector3(118, 0, 62), 3.2], [Vector3(92, 0, 88), 3.0], [Vector3(143, 0, 54), 2.2]]:   # (clear of the roads and the rounds)
		P.scrap_heap(lv, p[0], rng, p[1])
	# The crusher hall, its stacks, the conveyor running up into it from the biggest heap.
	var ch := Vector3(122, 0, 90)
	A.box(lv, Vector3(26, 16, 18), ch + Vector3(0, 8, 0), "corrugated", Color(0.6, 0.55, 0.5), true, 2.0)
	A.box(lv, Vector3(27, 0.5, 19), ch + Vector3(0, 16.2, 0), "rust", Color(0.7, 0.6, 0.55), false, 2.0)
	var nm := B.label(lv, "CRUSHER  No. 2", ch + Vector3(0, 13.0, -9.06), 120, Color(0.9, 0.86, 0.75), "plate", 0.02)
	nm.rotation.y = PI
	for k in 2:
		var sx := ch + Vector3(-6.0 + k * 9.0, 0, 6.0)
		A.cyl(lv, 1.4, 34.0, sx + Vector3(0, 17.0, 0), "brick", Color(0.65, 0.45, 0.38), true)
		A.cyl(lv, 1.6, 1.0, sx + Vector3(0, 33.8, 0), "metal", Color(0.25, 0.22, 0.2), false)
		for b in 3:
			A.cyl(lv, 1.5, 0.4, sx + Vector3(0, 30.0 - b * 2.0, 0), "paint", Color(0.85, 0.85, 0.82) if b % 2 == 0 else Color(0.8, 0.2, 0.15), false)
	var a := CONV_A
	var b := CONV_B
	var belt := Node3D.new()
	belt.name = "Conveyor"
	lv.add_child(belt)
	var d := b - a
	belt.position = (a + b) / 2.0
	belt.look_at_from_position(belt.position, b, Vector3.UP)
	A.box(belt, Vector3(1.6, 0.25, d.length()), Vector3.ZERO, "runner", Color.WHITE, false, 1.0)
	for sx in [-1.0, 1.0]:
		A.box(belt, Vector3(0.12, 0.6, d.length()), Vector3(sx * 0.86, 0.2, 0), "enamel", Color(0.85, 0.6, 0.12), false, 1.0)
	belt.set_meta("from", a)
	belt.set_meta("to", b)
	for k in 6:   # legs under it
		var p := a.lerp(b, (k + 0.5) / 6.0)
		A.box(lv, Vector3(0.4, p.y, 0.4), Vector3(p.x, p.y / 2.0, p.z), "metal", Color(0.4, 0.4, 0.38), false, 0.8)
	# Bales stacked in rows, a weighbridge, a magnet crane on a tower.
	for row in 3:
		for k in 8:
			for lvl in rng.randi_range(1, 3):
				P.bale(lv, Vector3(60.0 + k * 1.3, 0.06 + lvl * 0.95 - 0.95, 70.0 + row * 2.6), 1.15, rng)
	A.box(lv, Vector3(4.0, 0.3, 14.0), Vector3(66, 0.15, 28), "riveted", Color(0.6, 0.58, 0.55), true, 1.0)
	_block(lv, Vector3(74, 0, 24), Vector3(7, 3.2, 4), Color(0.75, 0.7, 0.5), "WEIGHBRIDGE", rng)
	P.gantry_crane(lv, Vector3(104, 0.06, 64), 0.2, 22.0, 12.0)


# --- fuel and power --------------------------------------------------------------------------------

static func _fuel(lv: Node3D, rng: RandomNumberGenerator) -> void:
	for k in 4:
		var p := Vector3(120.0 + (k % 2) * 14.0, 0.06, 12.0 + (k / 2) * 0.0 + (k % 2) * 0.0)
		p.x = 108.0 + k * 13.0
		var tank := A.cyl(lv, 5.0, 9.0, p + Vector3(0, 4.5, 0), "enamel", Color(0.62, 0.6, 0.52), true)
		(tank.get_child(1) as MeshInstance3D).material_override = A.mat("enamel", Color(0.62, 0.6, 0.52), 3.0)   # (sun-faded paint, not a clean white drum)
		A.cyl(lv, 5.04, 1.1, p + Vector3(0, 0.55, 0), "rust", Color(0.85, 0.75, 0.7), false)   # the bottom course rusting through
		A.cyl(lv, 5.04, 0.12, p + Vector3(0, 3.0, 0), "metal", Color(0.45, 0.45, 0.42), false)   # weld seams
		A.cyl(lv, 5.04, 0.12, p + Vector3(0, 6.0, 0), "metal", Color(0.45, 0.45, 0.42), false)
		A.cyl(lv, 5.15, 0.35, p + Vector3(0, 9.15, 0), "metal", Color(0.5, 0.5, 0.48), false)   # roof rim
		A.cyl(lv, 5.0, 0.8, p + Vector3(0, 9.6, 0), "enamel", Color(0.55, 0.53, 0.46), false, "y", 0.6)   # coned roof
		# The stencil on a flat plate bolted against the side (painted straight on, it'd float off the curve).
		A.box(lv, Vector3(4.2, 1.3, 0.08), p + Vector3(0, 5.0, -5.04), "enamel", Color(0.82, 0.8, 0.72), false, 1.0)
		B.label(lv, "BRM DIESEL %d" % (k + 1), p + Vector3(0, 5.0, -5.09), 60, Color(0.15, 0.13, 0.11), "stencil", 0.012).rotation.y = PI
		for dz in [-0.3, 0.3]:   # the ladder up the east side, and a rail round the roof
			A.cyl(lv, 0.035, 9.6, p + Vector3(5.2, 4.8, dz), "metal", Color(0.6, 0.6, 0.58), false)
		for r in 24:
			A.cyl(lv, 0.025, 0.6, p + Vector3(5.2, 0.4 + r * 0.38, 0), "metal", Color(0.6, 0.6, 0.58), false, "z")
		for a in 10:
			var ang := TAU * a / 10.0
			A.cyl(lv, 0.03, 1.0, p + Vector3(cos(ang) * 4.6, 9.75, sin(ang) * 4.6), "metal", Color(0.75, 0.6, 0.2), false)   # (feet on the cone)
		A.ring(lv, 4.64, 4.56, p + Vector3(0, 10.2, 0), "metal", Color(0.75, 0.6, 0.2))
	_fuel_line(lv)
	# A transformer yard behind a fence on the west side.
	for k in 3:
		var t := Vector3(-128.0 + k * 9.0, 0.06, 9.0)
		A.box(lv, Vector3(3.5, 3.0, 2.5), t + Vector3(0, 1.5, 0), "enamel", Color(0.5, 0.55, 0.5), true, 0.8)
		for f in 5:
			A.box(lv, Vector3(0.08, 2.6, 2.6), t + Vector3(-1.4 + f * 0.7, 1.5, 0), "metal", Color(0.4, 0.42, 0.4), false, 0.5)
		for i in 3:
			A.cyl(lv, 0.15, 1.2, t + Vector3(-0.9 + i * 0.9, 3.6, 0), "cream", Color(0.75, 0.55, 0.35), false)
	P.fence(lv, Vector3(-134, 0, 4.5), Vector3(-104, 0, 4.5), rng)


## The fuel line: a header on concrete saddles along the tank row, a branch with a gate valve off
## each tank, down into a valve pit at the east end, and at the west end up through the pump house to
## the filler crane by the main line (its arm swung clear of the track, the hose hanging).
static func _fuel_line(lv: Node3D) -> void:
	var c := Color(0.75, 0.6, 0.2)
	var y := 0.8
	var z := 6.2
	var x0 := 96.0
	var x1 := 152.0
	A.pipe(lv, Vector3(x0, y, z), Vector3(x1, y, z), 0.2, "metal", c)
	var x := x0 + 3.0
	while x < x1:   # saddles, each with a strap over the pipe
		A.box(lv, Vector3(0.5, y - 0.2, 0.7), Vector3(x, (y - 0.2) / 2.0, z), "concrete", Color(0.7, 0.68, 0.64), false, 1.0)
		A.box(lv, Vector3(0.12, 0.05, 0.5), Vector3(x, y + 0.22, z), "metal", Color(0.3, 0.3, 0.3), false, 0.3)
		for e in [-1.0, 1.0]:
			A.box(lv, Vector3(0.12, 0.25, 0.04), Vector3(x, y + 0.1, z + e * 0.23), "metal", Color(0.3, 0.3, 0.3), false, 0.3)
		x += 5.5
	for k in 4:   # a branch off each tank, its gate valve on a stem with the hand wheel
		var tx := 108.0 + k * 13.0
		A.pipe(lv, Vector3(tx, y, z), Vector3(tx, y, 7.4), 0.14, "metal", c)
		A.sphere(lv, 0.24, Vector3(tx, y, z), "metal", c)
		A.cyl(lv, 0.2, 0.3, Vector3(tx, y, 6.75), "metal", Color(0.3, 0.3, 0.3), false, "z")   # valve body
		A.cyl(lv, 0.03, 0.45, Vector3(tx, y + 0.35, 6.75), "metal", Color(0.4, 0.4, 0.4), false)
		A.ring(lv, 0.2, 0.17, Vector3(tx, y + 0.58, 6.75), "paint", Color(0.75, 0.15, 0.1))
		A.cyl(lv, 0.32, 0.06, Vector3(tx, y, 7.1), "metal", c.darkened(0.2), false, "z")   # flange at the tank
	# East end: an elbow down into a valve pit with a chequer-plate lid.
	A.sphere(lv, 0.22, Vector3(x1, y, z), "metal", c)
	A.cyl(lv, 0.2, y, Vector3(x1, y / 2.0, z), "metal", c, false)
	A.box(lv, Vector3(1.6, 0.3, 1.6), Vector3(x1, 0.15, z), "concrete", Color(0.65, 0.63, 0.6), true, 1.0)
	A.box(lv, Vector3(1.2, 0.02, 1.2), Vector3(x1 + 0.1, 0.31, z + 0.1), "riveted", Color(0.5, 0.5, 0.48), false, 0.5)
	# West end: up into the pump house.
	A.sphere(lv, 0.22, Vector3(x0, y, z), "metal", c)
	A.box(lv, Vector3(3.0, 2.6, 2.6), Vector3(x0 - 1.4, 1.3, z + 1.2), "corrugated", Color(0.6, 0.62, 0.58), true, 1.0)
	A.box(lv, Vector3(3.3, 0.12, 2.9), Vector3(x0 - 1.4, 2.66, z + 1.2), "metal", Color(0.4, 0.4, 0.38), false, 0.6)
	A.box(lv, Vector3(0.9, 1.9, 0.05), Vector3(x0 - 1.6, 0.95, z - 0.11), "metal", Color(0.35, 0.37, 0.35), false, 0.5)   # its door
	B.label(lv, "PUMP 1", Vector3(x0 - 1.4, 2.2, z - 0.115), 50, Color(0.9, 0.86, 0.75), "stencil", 0.01).rotation.y = PI
	A.cyl(lv, 0.08, 1.2, Vector3(x0 - 0.4, 3.2, z + 1.8), "metal", Color(0.3, 0.3, 0.3), false)   # vent
	# The filler crane: a standpipe from the pump house, its arm swung clear of the line, the hose.
	var sp := Vector3(x0 - 3.4, 0, 4.4)
	A.pipe(lv, Vector3(x0 - 2.9, y, z), Vector3(sp.x, y, z), 0.14, "metal", c)   # (out of the pump house's side)
	A.sphere(lv, 0.17, Vector3(sp.x, y, z), "metal", c)
	A.pipe(lv, Vector3(sp.x, y, z), Vector3(sp.x, y, sp.z), 0.14, "metal", c)
	A.sphere(lv, 0.17, Vector3(sp.x, y, sp.z), "metal", c)
	A.box(lv, Vector3(0.8, 0.3, 0.8), Vector3(sp.x, 0.15, sp.z), "concrete", Color(0.7, 0.68, 0.64), true, 1.0)
	A.cyl(lv, 0.16, 5.8, Vector3(sp.x, 3.1, sp.z), "metal", c, true)
	A.cyl(lv, 0.24, 0.3, Vector3(sp.x, 6.0, sp.z), "metal", Color(0.3, 0.3, 0.3), false)   # the swivel
	var tip := Vector3(sp.x - 3.2, 6.0, 3.0)
	A.seg(lv, Vector3(sp.x, 6.0, sp.z), tip, 0.12, 0.12, "metal", c)
	A.seg(lv, Vector3(sp.x, 4.6, sp.z), Vector3(sp.x - 1.6, 5.95, 3.7), 0.05, 0.05, "metal", Color(0.3, 0.3, 0.3))   # its brace
	A.sphere(lv, 0.14, tip, "metal", c)
	A.seg(lv, tip, tip + Vector3(0.1, -1.6, 0.05), 0.07, 0.07, "rubber", Color.WHITE)
	A.seg(lv, tip + Vector3(0.1, -1.6, 0.05), tip + Vector3(0.45, -2.3, 0.3), 0.07, 0.07, "rubber", Color.WHITE)
	A.cyl(lv, 0.09, 0.4, tip + Vector3(0.5, -2.5, 0.33), "metal", Color(0.55, 0.55, 0.5), false)   # the nozzle
	A.seg(lv, Vector3(sp.x, 0.3, sp.z), tip + Vector3(0.5, -2.7, 0.33), 0.012, 0.012, "metal", Color(0.3, 0.3, 0.3))   # its tether


# --- light -----------------------------------------------------------------------------------------

static func _lights(lv: Node3D) -> void:
	for p in [[Vector3(-70, 0.06, 30), PI * 0.8], [Vector3(-130, 0.06, 95), PI * 0.2], [Vector3(70, 0.06, 30), -PI * 0.8], [Vector3(140, 0.06, 95), -PI * 0.2],
			[Vector3(-110, 0.06, -60), PI * 0.75], [Vector3(10, 0.06, -60), PI], [Vector3(110, 0.06, -60), -PI * 0.75]]:
		var before := lv.get_child_count()
		P.floodlight_tower(lv, p[0], p[1], 16.0, true)
		for i in range(before, lv.get_child_count()):   # (no shadows from these: each one would draw the whole site again)
			for l: SpotLight3D in lv.get_child(i).find_children("*", "SpotLight3D", true, false):
				l.shadow_enabled = false
	for x in range(-140, 141, 20):   # street lamps along the ring road
		var at := Vector3(x, 0, 45.5)
		A.cyl(lv, 0.1, 7.0, at + Vector3(0, 3.5, 0), "metal", Color(0.35, 0.36, 0.35), false)
		A.box(lv, Vector3(0.2, 0.15, 1.4), at + Vector3(0, 7.0, -0.7), "metal", Color(0.35, 0.36, 0.35), false, 0.4)
		A.glow(lv, Vector3(0.4, 0.08, 0.6), at + Vector3(0, 6.9, -1.2), Color(1, 0.85, 0.6), 2.0)
