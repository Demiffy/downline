# Marks left where a hit lands on the world: a shotgun pellet's hole (a dark pit with a ring of
# chipped paint and a few hairline cracks out from it), a crowbar's or axe's gouge (a raw scrape
# along the swing); a puff of grit off concrete and a few sparks off metal as it happens. Pooled
# decals on whatever the hit was in (the stop or the train), the oldest reused; they fade after a
# few minutes. net.gd passes them to the crew (marks).
extends RefCounted

const POOL := 160
const LIFE := 240.0

static var _pool: Array = []
static var _next := 0
static var _tex := {}


## A mark of `kind` ("pellet" or "gouge") at `pos` on a surface facing `normal`, in `parent`;
## `along` the swing's direction for a gouge.
static func hit(parent: Node3D, pos: Vector3, normal: Vector3, kind: String, along := Vector3.ZERO) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var d: Decal
	_pool = _pool.filter(func(e): return is_instance_valid(e))
	if _pool.size() < POOL:
		d = Decal.new()
		d.cull_mask = 1 | (1 << 6)   # (the world and the train: main.TRAIN_BIT)
		d.normal_fade = 0.3
		_pool.append(d)
	else:
		_next = (_next + 1) % _pool.size()
		d = _pool[_next]
	if d.get_parent() != parent:
		if d.get_parent() != null:
			d.get_parent().remove_child(d)
		parent.add_child(d)
	d.texture_albedo = _texture(kind)
	var big := 0.09 if kind == "pellet" else 0.32
	d.size = Vector3(big, 0.12, big if kind == "pellet" else 0.1)
	# The decal projects down its own -y: point that into the surface.
	var y := normal.normalized()
	var x := (along - y * along.dot(y)).normalized() if along.length() > 0.01 else y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	x = x.rotated(y, randf_range(-0.2, 0.2)) if kind == "gouge" else x.rotated(y, randf() * TAU)
	d.global_transform = Transform3D(Basis(x, y, x.cross(y)).orthonormalized(), pos + normal * 0.03)
	d.modulate = Color(1, 1, 1, 1)
	var tw := d.create_tween()
	tw.tween_interval(LIFE * 0.8)
	tw.tween_property(d, "modulate:a", 0.0, LIFE * 0.2)
	_puff(parent, pos, normal)


## Grit off the surface: a little burst of dust and chips (and sparks, a few, either way: it's a fight).
static func _puff(parent: Node3D, pos: Vector3, normal: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 10
	p.lifetime = 0.6
	p.direction = normal
	p.spread = 35.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.025)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.5))
	g.set_color(1, Color(0.35, 0.33, 0.3, 0.0))
	p.color_ramp = g
	parent.add_child(p)
	p.global_position = pos + normal * 0.02
	p.emitting = true
	p.finished.connect(p.queue_free)


static func _texture(kind: String) -> ImageTexture:
	if _tex.has(kind):
		return _tex[kind]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var c := Color(0, 0, 0, 0)
			if kind == "pellet":
				var r := Vector2(u, v).length()
				if r < 0.36:   # the pit
					c = Color(0.05, 0.045, 0.04, 1.0)
				elif r < 0.55:   # chipped paint round it, ragged
					var rag := 0.45 + 0.1 * sin(atan2(v, u) * 7.0 + 1.3)
					if r < rag:
						c = Color(0.26, 0.24, 0.22, 0.8)
			else:   # a gouge: a long raw scrape, deepest in the middle, frayed edges
				var w := 0.34 * (1.0 - u * u) + 0.05 * sin(u * 23.0)
				if absf(v) < w:
					var core := 1.0 - absf(v) / maxf(w, 0.001)
					c = Color(0.4, 0.38, 0.35, 0.75).lerp(Color(0.04, 0.035, 0.03, 1.0), smoothstep(0.2, 0.7, core))
			img.set_pixel(x, y, c)
	if kind == "pellet":   # hairline cracks out from the pit
		for k in 5:
			var a := rng.randf() * TAU
			var len := rng.randf_range(0.5, 0.95)
			for s in 40:
				var t := s / 40.0 * len
				var px := int((0.5 + cos(a) * t * 0.5) * n)
				var py := int((0.5 + sin(a) * t * 0.5) * n)
				if px >= 0 and py >= 0 and px < n and py < n:
					img.set_pixel(px, py, Color(0.1, 0.09, 0.08, 0.8 * (1.0 - t)))
				a += rng.randf_range(-0.08, 0.08)
	img.generate_mipmaps()
	_tex[kind] = ImageTexture.create_from_image(img)
	return _tex[kind]
