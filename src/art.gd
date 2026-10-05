# Procedural art kit: pixel-grime textures (generated at startup, no image files) and prop builders.
# Look target: low-res point-filtered textures, warm rust palette, lots of clutter.
extends RefCounted

const B = preload("res://src/build.gd")
const PX := 64

static var _tex := {}
static var _mats := {}


# --- textures -------------------------------------------------------------------

static func texture(kind: String) -> ImageTexture:
	if _tex.has(kind):
		return _tex[kind]
	var noise := FastNoiseLite.new()
	noise.seed = kind.hash()
	noise.frequency = 0.05
	noise.fractal_octaves = 4
	var n := noise.get_seamless_image(PX, PX)
	var img := Image.create(PX, PX, false, Image.FORMAT_RGBA8)
	for y in PX:
		for x in PX:
			img.set_pixel(x, y, _px(kind, x, y, n.get_pixel(x, y).r))
	img.generate_mipmaps()
	_tex[kind] = ImageTexture.create_from_image(img)
	return _tex[kind]


static func _rand(kind: String, x: int, y: int) -> float:
	return float(posmod((x * 73856093) ^ (y * 19349663) ^ kind.hash(), 1009)) / 1009.0


static func _px(kind: String, x: int, y: int, v: float) -> Color:
	var r := _rand(kind, x, y)
	var c := Color.MAGENTA
	match kind:
		"concrete":
			c = Color(0.27, 0.26, 0.24).lerp(Color(0.48, 0.46, 0.42), v)
			if r < 0.06: c = c.darkened(0.3)
		"dirt":
			c = Color(0.14, 0.1, 0.07).lerp(Color(0.33, 0.25, 0.16), v)
			if r < 0.05: c = c.lightened(0.15)
		"rock":
			c = Color(0.3, 0.24, 0.19).lerp(Color(0.52, 0.42, 0.33), v)
			if absf(v - 0.5) < 0.02: c = c.darkened(0.5)
		"rust":
			c = Color(0.18, 0.08, 0.04).lerp(Color(0.6, 0.3, 0.12), v)
			if r < 0.07: c = c.darkened(0.35)
		"metal":
			c = Color(0.24, 0.25, 0.26).lerp(Color(0.46, 0.47, 0.48), r * 0.3 + v * 0.7)
			if v > 0.68: c = c.lerp(Color(0.5, 0.24, 0.1), (v - 0.68) / 0.32)
		"paint":
			c = Color(0.34, 0.1, 0.07).lerp(Color(0.46, 0.15, 0.1), r * 0.4 + v * 0.6)
			if v > 0.72: c = Color(0.35, 0.18, 0.09).lerp(Color(0.2, 0.1, 0.05), r)
			if v < 0.22: c = c.darkened(0.35)
		"red_wall":
			c = Color(0.19, 0.07, 0.05).lerp(Color(0.34, 0.12, 0.08), v)
			if r < 0.08: c = c.darkened(0.3)
			elif r > 0.96: c = c.lightened(0.15)
		"wood":
			var plank := y / 8
			var pr := _rand(kind, plank, 7)
			c = Color(0.28, 0.17, 0.09).lerp(Color(0.5, 0.33, 0.18), pr)
			c = c.darkened((v - 0.5) * 0.4)
			if y % 8 == 0: c = c.darkened(0.55)
			if r > 0.996: c = Color(0.1, 0.1, 0.1)
		"sand":
			c = Color(0.6, 0.42, 0.27).lerp(Color(0.76, 0.58, 0.4), v * 0.8 + r * 0.2)
		"snow":
			c = Color(0.78, 0.82, 0.88).lerp(Color(0.95, 0.96, 0.98), v * 0.8 + r * 0.2)
		"tiles":
			if x % 16 == 0 or y % 16 == 0:
				c = Color(0.32, 0.32, 0.3)
			else:
				c = Color(0.78, 0.8, 0.79).lerp(Color(0.55, 0.57, 0.55), v * 0.7 + r * 0.15)
		"wallpaper":
			c = Color(0.76, 0.68, 0.4) if (x / 4) % 2 == 0 else Color(0.7, 0.62, 0.36)
			if v < 0.3: c = c.lerp(Color(0.45, 0.38, 0.2), (0.3 - v) * 2.0)
		"carpet":
			c = Color(0.44, 0.39, 0.24).lerp(Color(0.56, 0.5, 0.32), r).darkened(maxf(0.0, 0.4 - v))
		"flesh":
			c = Color(0.32, 0.05, 0.06).lerp(Color(0.68, 0.24, 0.26), v)
			if absf(v - 0.5) < 0.025: c = Color(0.2, 0.03, 0.12)
		"grate":
			if posmod(x + y, 8) == 0 or posmod(x - y, 8) == 0:
				c = Color(0.35, 0.33, 0.3).lerp(Color(0.5, 0.25, 0.1), v)
			else:
				c = Color(0, 0, 0, 0)
		"corrugated":
			var s := sin(x * TAU / 8.0) * 0.5 + 0.5
			c = Color(0.3, 0.3, 0.3).lerp(Color(0.5, 0.5, 0.48), s)
			if v > 0.62: c = c.lerp(Color(0.48, 0.22, 0.09), (v - 0.62) * 2.0)
		"cream":
			c = Color(0.82, 0.75, 0.58).lerp(Color(0.66, 0.58, 0.43), v * 0.6)
			if r < 0.04: c = c.darkened(0.35)
		"hazard":
			c = Color(0.85, 0.65, 0.1) if posmod(x + y, 16) < 8 else Color(0.08, 0.08, 0.08)
			if v > 0.7: c = c.lerp(Color(0.3, 0.2, 0.1), 0.6)
		"board":
			c = Color(0.08, 0.15, 0.1).lerp(Color(0.14, 0.22, 0.15), v)
		"leaf":
			c = Color(0.08, 0.2, 0.06).lerp(Color(0.25, 0.42, 0.12), v * 0.6 + r * 0.4)
		_:
			c = Color(0.5, 0.5, 0.5).lerp(Color(0.6, 0.6, 0.6), v)
	return c


## kind = texture; tile = metres per texture repeat. Tint multiplies the texture.
static func mat(kind: String, tint := Color.WHITE, tile := 2.0, emit := 0.0) -> StandardMaterial3D:
	var k := "%s|%s|%s|%s" % [kind, tint.to_html(), tile, emit]
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture(kind)
	m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / tile
	m.roughness = 0.92
	if kind in ["metal", "rust", "grate", "corrugated"]:
		m.metallic = 0.35
		m.roughness = 0.65
	if kind == "grate":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = tint
		m.emission_energy_multiplier = emit
	_mats[k] = m
	return m


static func glass() -> StandardMaterial3D:
	if not _mats.has("glass"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.55, 0.6, 0.55, 0.22)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.1
		m.metallic = 0.3
		_mats["glass"] = m
	return _mats["glass"]


# --- primitives --------------------------------------------------------------------

static func box(parent: Node, size: Vector3, pos: Vector3, kind: String, tint := Color.WHITE, solid := true, tile := 2.0, rot := Vector3.ZERO) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat(kind, tint, tile)
	var node: Node3D = mi
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		body.add_child(mi)
		node = body
	parent.add_child(node)
	node.position = pos
	node.rotation = rot
	return node


## Cylinder; axis "y" (upright), "x" or "z" (lying down).
static func cyl(parent: Node, radius: float, height: float, pos: Vector3, kind: String, tint := Color.WHITE, solid := false, axis := "y", top := -1.0) -> Node3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius if top < 0.0 else top
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 14
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat(kind, tint, 1.0)
	var node: Node3D = mi
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = height
		cs.shape = sh
		body.add_child(cs)
		body.add_child(mi)
		node = body
	parent.add_child(node)
	node.position = pos
	if axis == "x":
		node.rotation.z = PI / 2
	elif axis == "z":
		node.rotation.x = PI / 2
	return node


static func sphere(parent: Node, radius: float, pos: Vector3, kind: String, tint := Color.WHITE, emit := 0.0, squash := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0 * squash
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = mat(kind, tint, 1.0, emit)
	parent.add_child(mi)
	mi.position = pos
	return mi


static func glow(parent: Node, size: Vector3, pos: Vector3, c: Color, energy := 3.0) -> Node3D:
	return B.box(parent, size, pos, c, false, energy)


## A wall with rectangular holes (doors/windows). along_x: wall runs along x at fixed z = c.
## holes: [[center_along, width, y_bottom, y_top], ...] relative to y0.
static func wall(parent: Node, a0: float, a1: float, c: float, h: float, thick: float, holes: Array, kind: String,
		tint := Color.WHITE, along_x := true, y0 := 0.0, solid := true, tile := 2.0) -> void:
	var cuts := [a0, a1]
	for o in holes:
		cuts.append(o[0] - o[1] / 2.0)
		cuts.append(o[0] + o[1] / 2.0)
	cuts.sort()
	for i in cuts.size() - 1:
		var a: float = maxf(cuts[i], a0)
		var b: float = minf(cuts[i + 1], a1)
		if b - a < 0.005:
			continue
		var mid := (a + b) / 2.0
		var spans := [[0.0, h]]
		for o in holes:
			if mid > o[0] - o[1] / 2.0 and mid < o[0] + o[1] / 2.0:
				var next := []
				for s in spans:
					if o[2] > s[0]: next.append([s[0], minf(s[1], o[2])])
					if o[3] < s[1]: next.append([maxf(s[0], o[3]), s[1]])
				spans = next
		for s in spans:
			var sh: float = s[1] - s[0]
			if sh < 0.005:
				continue
			var size := Vector3(b - a, sh, thick) if along_x else Vector3(thick, sh, b - a)
			var pos := Vector3(mid, y0 + (s[0] + s[1]) / 2.0, c) if along_x else Vector3(c, y0 + (s[0] + s[1]) / 2.0, mid)
			box(parent, size, pos, kind, tint, solid, tile)


# --- animation helpers -------------------------------------------------------------

static func spin(node: Node3D, axis: String, secs: float) -> void:
	var tw := node.create_tween().set_loops()
	tw.tween_property(node, "rotation:" + axis, TAU * signf(secs), absf(secs)).as_relative()


static func sway(node: Node3D, amount: float, secs: float) -> void:
	var tw := node.create_tween().set_loops()
	tw.tween_property(node, "rotation:z", amount, secs).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "rotation:z", -amount, secs).set_trans(Tween.TRANS_SINE)


static func bob(node: Node3D, amount: float, secs: float) -> void:
	var tw := node.create_tween().set_loops()
	tw.tween_property(node, "position:y", amount, secs).as_relative().set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "position:y", -amount, secs).as_relative().set_trans(Tween.TRANS_SINE)


# --- props ---------------------------------------------------------------------------

static func barrel(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var tints := [Color(0.45, 0.55, 0.7), Color(0.75, 0.35, 0.25), Color(0.5, 0.6, 0.35), Color(0.8, 0.7, 0.4), Color.WHITE]
	var t: Color = tints[rng.randi() % tints.size()]
	cyl(parent, 0.33, 0.9, pos + Vector3(0, 0.45, 0), "rust", t, true)
	for y in [0.18, 0.72]:
		cyl(parent, 0.345, 0.04, pos + Vector3(0, y, 0), "metal", Color(0.6, 0.6, 0.6))


static func crate(parent: Node, pos: Vector3, s: float, rng: RandomNumberGenerator, solid := true) -> void:
	var tint := Color.WHITE.darkened(rng.randf() * 0.35)
	box(parent, Vector3(s, s, s), pos + Vector3(0, s / 2, 0), "wood", tint, solid, 1.0, Vector3(0, rng.randf_range(-0.25, 0.25), 0))


static func pallet(parent: Node, pos: Vector3) -> void:
	for i in 5:
		box(parent, Vector3(1.2, 0.03, 0.16), pos + Vector3(0, 0.13, -0.5 + i * 0.25), "wood", Color.WHITE, false, 1.0)
	for i in 3:
		box(parent, Vector3(1.2, 0.1, 0.1), pos + Vector3(0, 0.06, -0.45 + i * 0.45), "wood", Color(0.7, 0.7, 0.7), false, 1.0)


## Metal rack with junk on it. One collision box for the whole unit.
static func shelf_unit(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator, w := 2.0, h := 2.2, d := 0.5) -> void:
	var root := StaticBody3D.new()
	parent.add_child(root)
	root.position = pos
	root.rotation.y = rot_y
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(w, h, d)
	cs.shape = sh
	cs.position.y = h / 2
	root.add_child(cs)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			box(root, Vector3(0.05, h, 0.05), Vector3(sx * (w / 2 - 0.03), h / 2, sz * (d / 2 - 0.03)), "metal", Color.WHITE, false)
	var levels := 4
	for i in levels:
		var y := 0.15 + i * (h - 0.25) / (levels - 1)
		box(root, Vector3(w, 0.04, d), Vector3(0, y, 0), "metal", Color(0.8, 0.8, 0.8), false)
		var x := -w / 2 + 0.15
		while x < w / 2 - 0.2 and i < levels - 1:
			if rng.randf() < 0.6:
				var s := Vector3(rng.randf_range(0.15, 0.4), rng.randf_range(0.12, 0.35), rng.randf_range(0.15, d - 0.05))
				var kinds := ["cream", "wood", "metal", "rust"]
				box(root, s, Vector3(x + s.x / 2, y + 0.02 + s.y / 2, 0), kinds[rng.randi() % kinds.size()], Color.WHITE.darkened(rng.randf() * 0.4), false, 0.5)
				x += s.x + 0.05
			else:
				x += 0.25


## Horizontal or vertical pipe between two axis-aligned points, with flanges.
static func pipe(parent: Node, a: Vector3, b: Vector3, radius := 0.08, kind := "metal", tint := Color.WHITE) -> void:
	var d := b - a
	var axis := "x" if absf(d.x) > 0.01 else ("z" if absf(d.z) > 0.01 else "y")
	var length := d.length()
	cyl(parent, radius, length, (a + b) / 2.0, kind, tint, false, axis)
	var steps := int(length / 2.5)
	for i in range(1, steps + 1):
		cyl(parent, radius * 1.4, 0.06, a + d * (float(i) / (steps + 1)), "rust", tint, false, axis)


## Caged bulkhead lamp on a wall. normal = direction the lamp faces.
static func wall_lamp(parent: Node, pos: Vector3, normal: Vector3, c: Color, energy := 1.2, shadow := false) -> OmniLight3D:
	var flat := Vector3(0.22, 0.22, 0.04) if absf(normal.z) > 0.5 else Vector3(0.04, 0.22, 0.22)
	box(parent, flat, pos, "metal", Color(0.5, 0.5, 0.5), false)
	sphere(parent, 0.09, pos + normal * 0.1, "cream", c, 4.0)
	for i in 3:
		var bar := Vector3(0.02, 0.2, 0.02)
		var off := normal * 0.16 + (Vector3(0, 0, (i - 1) * 0.08) if absf(normal.x) > 0.5 else Vector3((i - 1) * 0.08, 0, 0))
		box(parent, bar, pos + off, "metal", Color(0.4, 0.4, 0.4), false)
	return B.omni(parent, pos + normal * 0.4, c, energy, 9.0, shadow)


## Lamp hanging from the ceiling on a cord; it sways.
static func hanging_lamp(parent: Node, ceiling: Vector3, c: Color, drop := 1.0, energy := 1.4, shadow := true) -> OmniLight3D:
	var pivot := Node3D.new()
	parent.add_child(pivot)
	pivot.position = ceiling
	box(pivot, Vector3(0.02, drop, 0.02), Vector3(0, -drop / 2, 0), "metal", Color(0.1, 0.1, 0.1), false)
	var shade := cyl(pivot, 0.32, 0.22, Vector3(0, -drop - 0.05, 0), "metal", Color(0.35, 0.4, 0.35), false, "y", 0.06)
	shade.scale = Vector3.ONE
	sphere(pivot, 0.08, Vector3(0, -drop - 0.15, 0), "cream", c, 5.0)
	var l := B.omni(pivot, Vector3(0, -drop - 0.3, 0), c, energy, 10.0, shadow)
	sway(pivot, 0.06, 1.8 + randf())
	return l


static func fluorescent(parent: Node, pos: Vector3, c: Color, energy := 1.0) -> OmniLight3D:
	box(parent, Vector3(1.3, 0.06, 0.25), pos, "metal", Color(0.6, 0.6, 0.6), false)
	glow(parent, Vector3(1.2, 0.03, 0.15), pos + Vector3(0, -0.04, 0), c, 3.0)
	return B.omni(parent, pos + Vector3(0, -0.3, 0), c, energy, 10.0, false)


## Work light on a tripod, like the ones crews leave around.
static func tripod_light(parent: Node, pos: Vector3, rot_y: float, c: Color) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.position = pos
	root.rotation.y = rot_y
	for i in 3:
		var leg := box(root, Vector3(0.03, 1.3, 0.03), Vector3(0, 0.6, 0).rotated(Vector3.UP, TAU * i / 3.0) + Vector3(0.25, 0, 0).rotated(Vector3.UP, TAU * i / 3.0), "metal", Color(0.3, 0.3, 0.3), false)
		leg.rotation = Vector3(0.0, TAU * i / 3.0, 0.25)
	box(root, Vector3(0.04, 0.9, 0.04), Vector3(0, 1.6, 0), "metal", Color(0.3, 0.3, 0.3), false)
	box(root, Vector3(0.6, 0.12, 0.1), Vector3(0, 2.05, 0), "metal", Color(0.25, 0.25, 0.25), false)
	for i in 3:
		glow(root, Vector3(0.12, 0.08, 0.04), Vector3(-0.2 + i * 0.2, 2.05, -0.06), c, 6.0)
	var s := SpotLight3D.new()
	s.light_color = c
	s.light_energy = 3.0
	s.spot_range = 14.0
	s.spot_angle = 50.0
	s.shadow_enabled = true
	root.add_child(s)
	s.position = Vector3(0, 2.05, -0.15)
	s.rotation.x = -0.3


static func vines(parent: Node, pos: Vector3, length: float, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(3, 7):
		var l := rng.randf_range(0.4, length)
		var p := pos + Vector3(rng.randf_range(-0.6, 0.6), -l / 2, rng.randf_range(-0.6, 0.6))
		box(parent, Vector3(0.05, l, 0.05), p, "leaf", Color.WHITE, false, 0.5)
		for j in int(l / 0.35):
			box(parent, Vector3(0.18, 0.02, 0.1), p + Vector3(0, -l / 2 + j * 0.35, 0), "leaf", Color.WHITE, false, 0.5, Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU, 0))


static func fern(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(5, 9):
		var a := TAU * i / 7.0 + rng.randf() * 0.5
		var leaf := box(parent, Vector3(0.12, 0.02, 0.7), pos + Vector3(0, 0.15, 0) + Vector3(0, 0, 0.3).rotated(Vector3.UP, a), "leaf", Color.WHITE, false, 0.5)
		leaf.rotation = Vector3(-0.5, a, 0)


static func rubble(parent: Node, pos: Vector3, rng: RandomNumberGenerator, kind := "concrete") -> void:
	for i in rng.randi_range(3, 7):
		var s := rng.randf_range(0.1, 0.45)
		box(parent, Vector3(s, s * 0.6, s), pos + Vector3(rng.randf_range(-0.7, 0.7), s * 0.25, rng.randf_range(-0.7, 0.7)), kind, Color.WHITE, false, 1.0,
			Vector3(rng.randf(), rng.randf() * TAU, rng.randf()))


static func desk(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
	var root := StaticBody3D.new()
	parent.add_child(root)
	root.position = pos
	root.rotation.y = rot_y
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.6, 0.8, 0.8)
	cs.shape = sh
	cs.position.y = 0.4
	root.add_child(cs)
	box(root, Vector3(1.6, 0.06, 0.8), Vector3(0, 0.77, 0), "metal", Color(0.7, 0.7, 0.65), false)
	for sx in [-1, 1]:
		box(root, Vector3(0.05, 0.75, 0.75), Vector3(sx * 0.75, 0.37, 0), "metal", Color(0.6, 0.6, 0.55), false)
	if rng.randf() < 0.7:
		crt(root, Vector3(rng.randf_range(-0.3, 0.3), 0.8, 0.05), rng.randf() < 0.4)
	for i in rng.randi_range(0, 3):
		box(root, Vector3(0.21, 0.01, 0.29), Vector3(rng.randf_range(-0.7, 0.7), 0.805, rng.randf_range(-0.3, 0.3)), "cream", Color.WHITE, false, 0.5, Vector3(0, rng.randf() * TAU, 0))


## Cream retro CRT. Returns the screen node.
static func crt(parent: Node, pos: Vector3, on := false, screen_color := Color(1.0, 0.6, 0.2)) -> Node3D:
	box(parent, Vector3(0.55, 0.45, 0.5), pos + Vector3(0, 0.225, 0), "cream", Color.WHITE, false, 0.5)
	box(parent, Vector3(0.35, 0.3, 0.2), pos + Vector3(0, 0.22, 0.32), "cream", Color(0.85, 0.85, 0.85), false, 0.5)
	var screen := glow(parent, Vector3(0.42, 0.32, 0.02), pos + Vector3(0, 0.25, -0.255), screen_color if on else Color(0.05, 0.06, 0.05), 1.5 if on else 0.2)
	box(parent, Vector3(0.5, 0.04, 0.18), pos + Vector3(0, 0.02, -0.4), "cream", Color(0.9, 0.9, 0.9), false, 0.5)
	return screen


static func locker(parent: Node, pos: Vector3, rot_y: float, tint := Color(0.55, 0.62, 0.55)) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.position = pos
	root.rotation.y = rot_y
	box(root, Vector3(0.6, 1.9, 0.5), Vector3(0, 0.95, 0), "metal", tint)
	for i in 3:
		box(root, Vector3(0.3, 0.02, 0.01), Vector3(0, 1.6 - i * 0.05, -0.255), "metal", Color(0.1, 0.1, 0.1), false)
	box(root, Vector3(0.02, 1.85, 0.01), Vector3(0, 0.95, -0.255), "metal", Color(0.15, 0.15, 0.15), false)


static func blob(parent: Node, pos: Vector3, radius: float, rng: RandomNumberGenerator) -> void:
	var b := sphere(parent, radius, pos, "flesh", Color(1, 0.85, 0.85), 0.15, rng.randf_range(0.5, 1.0))
	b.rotation.y = rng.randf() * TAU
	var tw := b.create_tween().set_loops()
	tw.tween_property(b, "scale", Vector3.ONE * 1.06, rng.randf_range(0.8, 1.6)).set_trans(Tween.TRANS_SINE)
	tw.tween_property(b, "scale", Vector3.ONE, rng.randf_range(0.8, 1.6)).set_trans(Tween.TRANS_SINE)


## Railing from a to b (horizontal). Top rail is solid so you can't walk off.
static func railing(parent: Node, a: Vector3, b: Vector3, h := 1.0, kind := "rust", solid := false) -> void:
	var d := b - a
	var n := maxi(1, int(d.length() / 1.4))
	for i in n + 1:
		box(parent, Vector3(0.05, h, 0.05), a + d * (float(i) / n) + Vector3(0, h / 2, 0), kind, Color.WHITE, false, 1.0)
	var along_x := absf(d.x) > absf(d.z)
	for y in [h, h * 0.5]:
		var size := Vector3(d.length(), 0.05, 0.05) if along_x else Vector3(0.05, 0.05, d.length())
		box(parent, size, (a + b) / 2.0 + Vector3(0, y, 0), kind, Color.WHITE, solid and y == h, 1.0)


static func dead_tree(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(4.0, 7.0)
	cyl(parent, 0.3, h, pos + Vector3(0, h / 2, 0), "wood", Color(0.45, 0.4, 0.38), true, "y", 0.12)
	for i in rng.randi_range(3, 6):
		var l := rng.randf_range(1.0, 2.5)
		var y := rng.randf_range(h * 0.45, h * 0.95)
		var a := rng.randf() * TAU
		var br := cyl(parent, 0.08, l, Vector3.ZERO, "wood", Color(0.45, 0.4, 0.38), false, "y", 0.03)
		br.rotation = Vector3(0, a, rng.randf_range(0.6, 1.1))
		br.position = pos + Vector3(0, y, 0) + br.basis.y * (l / 2)


static func telephone_pole(parent: Node, pos: Vector3) -> void:
	cyl(parent, 0.12, 7.0, pos + Vector3(0, 3.5, 0), "wood", Color(0.6, 0.55, 0.5), true)
	box(parent, Vector3(0.1, 0.1, 1.6), pos + Vector3(0, 6.5, 0), "wood", Color(0.6, 0.55, 0.5), false, 1.0)


static func lamp_post(parent: Node, pos: Vector3, c: Color) -> OmniLight3D:
	cyl(parent, 0.06, 3.6, pos + Vector3(0, 1.8, 0), "metal", Color(0.3, 0.3, 0.3), true)
	box(parent, Vector3(0.5, 0.06, 0.06), pos + Vector3(0.22, 3.55, 0), "metal", Color(0.3, 0.3, 0.3), false)
	sphere(parent, 0.12, pos + Vector3(0.45, 3.45, 0), "cream", c, 5.0)
	return B.omni(parent, pos + Vector3(0.45, 3.2, 0), c, 1.6, 12.0, false)


## Two-storey wooden building, hollow with a door, a porch and a balcony. Faces -z.
## Returns a point inside (for loot).
static func wood_house(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> Vector3:
	var root := Node3D.new()
	parent.add_child(root)
	root.position = pos
	root.rotation.y = rot_y
	var w := rng.randf_range(7.0, 10.0)
	var d := rng.randf_range(6.0, 8.0)
	var tint := Color.WHITE.darkened(rng.randf() * 0.3)
	var door := [[0.0, 1.4, 0.0, 2.3]]
	var win1 := [[-w / 3, 1.0, 1.0, 2.2], [w / 3, 1.0, 1.0, 2.2]]
	var win2 := [[-w / 3, 1.0, 4.0, 5.2], [0.0, 1.0, 4.0, 5.2], [w / 3, 1.0, 4.0, 5.2]]
	wall(root, -w / 2, w / 2, -d / 2, 6.4, 0.15, door + win1 + win2, "wood", tint, true, 0.0, true, 1.5)
	wall(root, -w / 2, w / 2, d / 2, 6.4, 0.15, win1 + win2, "wood", tint, true, 0.0, true, 1.5)
	wall(root, -d / 2, d / 2, -w / 2, 6.4, 0.15, [[0.0, 1.0, 1.0, 2.2], [0.0, 1.0, 4.0, 5.2]], "wood", tint, false, 0.0, true, 1.5)
	wall(root, -d / 2, d / 2, w / 2, 6.4, 0.15, [[0.0, 1.0, 1.0, 2.2]], "wood", tint, false, 0.0, true, 1.5)
	box(root, Vector3(w, 0.15, d), Vector3(0, 3.1, 0), "wood", tint.darkened(0.2), false, 1.5)
	var roof := box(root, Vector3(w + 0.8, 0.2, d * 0.6), Vector3(0, 6.9, -d * 0.24), "corrugated", Color(0.8, 0.75, 0.7), false, 1.5)
	roof.rotation.x = 0.35
	var roof2 := box(root, Vector3(w + 0.8, 0.2, d * 0.6), Vector3(0, 6.9, d * 0.24), "corrugated", Color(0.8, 0.75, 0.7), false, 1.5)
	roof2.rotation.x = -0.35
	box(root, Vector3(w - 0.3, 0.1, d - 0.3), Vector3(0, 6.45, 0), "wood", tint.darkened(0.4), true, 1.5)
	# Porch roof + posts, balcony above it.
	box(root, Vector3(w, 0.15, 2.0), Vector3(0, 3.1, -d / 2 - 1.0), "wood", tint.darkened(0.15), false, 1.5)
	for x in [-w / 2 + 0.2, 0.0, w / 2 - 0.2]:
		if x != 0.0:
			box(root, Vector3(0.15, 3.1, 0.15), Vector3(x, 1.55, -d / 2 - 1.9), "wood", tint, true, 1.5)
	railing(root, Vector3(-w / 2, 3.15, -d / 2 - 1.95), Vector3(w / 2, 3.15, -d / 2 - 1.95), 1.0, "wood")
	for i in 2:
		box(root, Vector3(0.9, 1.0, 0.05), Vector3(-w / 3 + i * w * 0.66, 1.6, -d / 2 - 0.08), "board", Color(0.3, 0.3, 0.3), false)
	return root.to_global(Vector3(rng.randf_range(-w / 3, w / 3), 0.6, rng.randf_range(-d / 4, d / 4)))


## Small cheery shop robot.
static func robot(parent: Node, pos: Vector3, rot_y: float) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.position = pos
	root.rotation.y = rot_y
	cyl(root, 0.35, 1.0, Vector3(0, 0.5, 0), "metal", Color(0.8, 0.7, 0.45), true)
	var head := Node3D.new()
	root.add_child(head)
	head.position.y = 1.25
	box(head, Vector3(0.6, 0.4, 0.45), Vector3.ZERO, "cream", Color.WHITE, false, 0.5)
	for x in [-0.13, 0.13]:
		glow(head, Vector3(0.1, 0.08, 0.02), Vector3(x, 0.03, -0.23), Color(0.3, 1, 0.6), 5.0)
	box(head, Vector3(0.02, 0.3, 0.02), Vector3(0, 0.35, 0), "metal", Color(0.4, 0.4, 0.4), false)
	sphere(head, 0.05, Vector3(0, 0.52, 0), "cream", Color(1, 0.3, 0.2), 4.0)
	bob(head, 0.04, 0.9)
	var tw := head.create_tween().set_loops()
	tw.tween_property(head, "rotation:y", 0.4, 2.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(head, "rotation:y", -0.4, 2.0).set_trans(Tween.TRANS_SINE)
