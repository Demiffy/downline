# Grass you walk through: clumps of real blades (tapered, curved, dark at the root and paler at
# the tip), planted by the thousand as one instanced mesh a field, so they cost next to nothing.
# One shader for all of it: the blades sway in the wind (slow gusts rolling over the field, a
# flutter on top, harder in a storm) and lean away from anyone walking through, pressed down
# under their feet, springing back once they've passed (the crew and the creatures: `_pushers`).
#   grass  the forest's meadow grass, knee-high, green going to straw here and there
#   sedge  the swamp's: taller, darker, fewer blades a clump
#   dry    the desert's: stiff spiky tufts of bleached grass, splayed out low
#   frost  the arctic's: thin dead stalks, straw and grey, poking up through the snow
#   weeds  the dead town's: broad-bladed weeds, dark green, in patches off the streets
# level.gd and line.gd call plant(); the field node keeps the shared shader fed each frame.
extends MultiMeshInstance3D

const MAX_PUSH := 8
const SHADER := """shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
uniform vec4 pushers[8];
uniform int n_push = 0;
uniform vec3 wind = vec3(1.0, 0.3, 0.3);   // xz: the way it blows; z: how hard (0..1)
varying vec3 tint;

void vertex() {
	float h = UV.y;   // 0 at the root, 1 at the tip
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float s = wind.z;
	float gust = sin(TIME * 0.6 + root.x * 0.045 + root.z * 0.035) * 0.5 + 0.5;   // gusts rolling over
	float flutter = sin(TIME * (2.2 + s * 3.0) + root.x * 0.9 + root.z * 0.7 + VERTEX.x * 4.0);
	vec2 dir = normalize(wind.xy + vec2(0.0001));
	float bend = (s * (0.2 + 0.8 * gust) + flutter * (0.05 + 0.12 * s)) * h * h;
	vec3 off = vec3(dir.x, 0.0, dir.y) * bend * 0.5;
	off.y -= bend * bend * 0.25;
	for (int i = 0; i < n_push; i++) {   // whoever's walking through
		vec4 p = pushers[i];
		vec2 d = world.xz - p.xz;
		float dist = length(d);
		if (dist < p.w && abs(world.y - p.y) < 1.6) {
			float k = 1.0 - dist / p.w;
			k = k * k * (3.0 - 2.0 * k);
			off.xz += normalize(d + vec2(0.0001)) * k * 0.6 * h;
			off.y -= k * 0.45 * h * h;
		}
	}
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
	tint = COLOR.rgb;
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.9;
	BACKLIGHT = tint * 0.4;   // (the sun through the blades)
}
"""

static var _mat: ShaderMaterial
static var _meshes := {}
static var _frame := -1


const TILE := 8.0         # a field is cut into tiles this size...
const NEAR := 35.0        # ...each drawn in full this close to the camera...
const FAR := 75.0         # ...and a sixth of it out to here (past that the ground's own texture does)


## Grass all over a stretch of ground given as its own height grid (the mesh's: xs along, zs across,
## hs[i][j], two triangles a cell split corner to corner like line.gd's and level.gd's), so every clump
## stands on the ground as drawn. `per_m2` clumps a square metre, thinner between the drifts; `cell_ok`
## (x, z of a cell's middle) and `spot_ok` (each clump) keep it off what isn't ground. `dx` shifts x
## into the parent's space. Returns the spots, for plant().
static func carpet(xs: Array, zs: Array, hs: Array, dx: float, per_m2: float, cell_ok: Callable, spot_ok: Callable, rng: RandomNumberGenerator, seed: int) -> Array:
	var out: Array = []
	for i in xs.size() - 1:
		var x0: float = xs[i]
		var x1: float = xs[i + 1]
		for j in zs.size() - 1:
			var z0: float = zs[j]
			var z1: float = zs[j + 1]
			if not cell_ok.call((x0 + x1) / 2.0, (z0 + z1) / 2.0):
				continue
			var ha: float = hs[i][j]
			var hb: float = hs[i + 1][j]
			var hc: float = hs[i + 1][j + 1]
			var hd: float = hs[i][j + 1]
			var want := (x1 - x0) * (z1 - z0) * per_m2 * (1.0 if lush(Vector3((x0 + x1) / 2.0, 0, (z0 + z1) / 2.0), seed, 0.6) else 0.6)
			var n := int(want) + (1 if rng.randf() < fmod(want, 1.0) else 0)
			for k in n:
				var u := rng.randf()
				var v := rng.randf()
				var x := lerpf(x0, x1, u)
				var z := lerpf(z0, z1, v)
				if not spot_ok.call(x, z):
					continue
				var h := (ha + (hb - ha) * u + (hc - hb) * v) if u >= v else (ha + (hd - ha) * v + (hc - hd) * u)
				out.append(Vector3(x + dx, h - 0.03, z))
	return out


## A field of `kind` at `spots` (Vector3s under `parent`, on the ground), turned and sized at random.
static func plant(parent: Node3D, kind: String, spots: Array, rng: RandomNumberGenerator, pause := Callable()) -> void:
	var tiles := {}
	for p: Vector3 in spots:
		var k := Vector2i(floori(p.x / TILE), floori(p.z / TILE))
		if not tiles.has(k):
			tiles[k] = []
		tiles[k].append(p)
	for k in tiles:
		var pts: Array = tiles[k]
		var buf := PackedFloat32Array()   # (12 floats of transform and 4 of colour a clump, straight to the GPU)
		buf.resize(pts.size() * 16)
		var far := PackedFloat32Array()
		var nf := 0
		for i in pts.size():
			var sc := rng.randf_range(0.75, 1.25)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.75, 1.3), sc))
			var p: Vector3 = pts[i]
			var dry := rng.randf()   # most green, some going to straw
			var c := Color.WHITE.lerp(Color(1.3, 1.12, 0.72), dry * dry * dry * 0.8).darkened(rng.randf() * 0.2)
			var o := i * 16
			buf[o] = b.x.x; buf[o + 1] = b.y.x; buf[o + 2] = b.z.x; buf[o + 3] = p.x
			buf[o + 4] = b.x.y; buf[o + 5] = b.y.y; buf[o + 6] = b.z.y; buf[o + 7] = p.y
			buf[o + 8] = b.x.z; buf[o + 9] = b.y.z; buf[o + 10] = b.z.z; buf[o + 11] = p.z
			buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = 1.0
			if i % 6 == 0:
				far.append_array(buf.slice(o, o + 16))
				nf += 1
		if not is_instance_valid(parent):
			return
		_tile(parent, kind, buf, pts.size(), 0.0, NEAR)
		_tile(parent, kind, far, nf, NEAR, FAR)
		if pause.is_valid():   # (a tile at a time, while the train's moving)
			await pause.call()


static func _tile(parent: Node3D, kind: String, buf: PackedFloat32Array, n: int, from: float, to: float) -> void:
	if n == 0:
		return
	var f := new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _mesh(kind)
	mm.instance_count = n
	mm.buffer = buf
	f.multimesh = mm
	f.material_override = _material()
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.visibility_range_begin = from
	f.visibility_range_end = to
	f.set_meta("live", true)   # (merge.gd leaves it alone)
	parent.add_child(f)


## Where grass grows best: in drifts and patches, thinner between them.
static func lush(p: Vector3, seed: int, amount := 0.5) -> bool:
	var n := sin(p.x * 0.11 + seed) * sin(p.z * 0.093 - seed * 0.7) + 0.5 * sin(p.x * 0.31 + p.z * 0.27 + seed * 1.3)
	return n + amount * 2.0 - 1.0 > 0.0


static func _material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
	return _mat


## A clump: a tuft of blades from one root, each a tapered strip in two bends.
static func _mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var r := RandomNumberGenerator.new()
	r.seed = hash(kind)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# [blades, root colour, tip colour, spread, lean, height, width]
	var spec: Array = {
		"grass": [6, Color(0.08, 0.13, 0.05), Color(0.36, 0.44, 0.18), 0.16, [0.08, 0.3], [0.15, 0.35], [0.022, 0.034]],
		"sedge": [7, Color(0.1, 0.12, 0.06), Color(0.25, 0.29, 0.13), 0.14, [0.08, 0.3], [0.5, 0.95], [0.02, 0.03]],
		"dry": [11, Color(0.42, 0.32, 0.2), Color(0.86, 0.76, 0.52), 0.06, [0.25, 0.6], [0.14, 0.32], [0.008, 0.013]],
		"frost": [6, Color(0.28, 0.24, 0.18), Color(0.6, 0.53, 0.38), 0.05, [0.04, 0.16], [0.18, 0.42], [0.008, 0.013]],
		"weeds": [6, Color(0.08, 0.12, 0.05), Color(0.3, 0.36, 0.14), 0.08, [0.2, 0.45], [0.1, 0.26], [0.03, 0.05]],
	}[kind]
	var blades: int = spec[0]
	var root_c: Color = spec[1]
	var tip_c: Color = spec[2]
	for b in blades:
		var a := r.randf() * TAU
		var spread := r.randf_range(0.0, spec[3])
		var base := Vector3(cos(a) * spread, 0, sin(a) * spread)
		var lean := Vector3(cos(a), 0, sin(a)) * r.randf_range(spec[4][0], spec[4][1])
		var h := r.randf_range(spec[5][0], spec[5][1])
		var w := r.randf_range(spec[6][0], spec[6][1])
		var side := Vector3(-sin(a + 1.2), 0, cos(a + 1.2))   # (the blade's face, turned off its lean)
		var pts := []
		for k in 3:
			var t := k / 2.0
			pts.append([base + lean * t * t * h + Vector3(0, t * h, 0), w * (1.0 - t * 0.85), t])
		for k in 2:
			var p0: Vector3 = pts[k][0]
			var p1: Vector3 = pts[k + 1][0]
			var w0: float = pts[k][1]
			var w1: float = pts[k + 1][1]
			var t0: float = pts[k][2]
			var t1: float = pts[k + 1][2]
			var q := [p0 - side * w0, p0 + side * w0, p1 + side * w1, p1 - side * w1]
			var tt := [t0, t0, t1, t1]
			var n := side.cross(p1 - p0).normalized()
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for i in tri:
					st.set_normal(n)
					st.set_color(root_c.lerp(tip_c, tt[i]))
					st.set_uv(Vector2(0, tt[i]))
					st.add_vertex(q[i])
	_meshes[kind] = st.commit()
	return _meshes[kind]


func _process(_delta: float) -> void:
	if _frame == Engine.get_process_frames():   # (the first field each frame feeds the shader for all)
		return
	_frame = Engine.get_process_frames()
	_pushers()


## Who's pushing through the grass: the nearest of the crew and the creatures to the camera.
func _pushers() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var near: Array = []
	for n in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("monsters"):
		if n is Node3D and n.is_inside_tree():
			var d: float = (n as Node3D).global_position.distance_to(cam.global_position)
			if d < 60.0:
				near.append([d, n])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var arr := PackedVector4Array()
	for e in near.slice(0, MAX_PUSH):
		var p: Vector3 = e[1].global_position
		arr.append(Vector4(p.x, p.y, p.z, 1.3 if e[1].is_in_group("monsters") else 0.75))
	while arr.size() < MAX_PUSH:
		arr.append(Vector4(0, -9999, 0, 0.0))
	_mat.set_shader_parameter("pushers", arr)
	_mat.set_shader_parameter("n_push", mini(near.size(), MAX_PUSH))
	var main = get_tree().root.get_node_or_null("Main")
	var w: String = main.weather_now() if main != null and main.has_method("weather_now") else ""
	var s := 0.9 if w in ["STORM", "SANDSTORM", "BLIZZARD"] else (0.55 if w in ["RAIN", "ACID_RAIN"] else 0.28)
	_mat.set_shader_parameter("wind", Vector3(0.8, 0.6, s))
