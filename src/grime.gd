# Age on the facility's walls: rust streaks bleeding down from high up (a bolt, a seam, a pipe
# bracket long gone), water stains spreading from the ceiling with a darker tide mark round them, and
# paint peeling off in patches lower down, the grey render showing through. Decals, a few per wall,
# from each room's own dice (not the site's: the rest of the layout stays as it was); never over a
# doorway or a vent. facility.gd calls dress() once every wall is known.
extends RefCounted

const Baked = preload("res://src/baked.gd")

const KINDS := ["rust", "stain", "peel"]
const VARIANTS := 3
static var _tex := {}


static func dress(fac: Node3D, cell_walls: Dictionary, kinds: Dictionary, h: float, cell: float) -> void:
	for c: Vector2i in cell_walls:
		if kinds.get(c, "") == "tunnel":
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([c, "grime"])
		for w: Array in cell_walls[c]:
			if w[4]:   # (open to the same big room: no wall there)
				continue
			for k in rng.randi_range(1, 3):
				var kind: String = KINDS[rng.randi() % KINDS.size()]
				var off := rng.randf_range(-cell / 2.0 + 0.8, cell / 2.0 - 0.8)
				if w[3] and absf(off) < 1.9:   # (keep clear of the doorway or vent in the middle)
					continue
				var size: Vector2   # across, down
				var top: float
				match kind:
					"rust":
						size = Vector2(rng.randf_range(0.35, 0.8), rng.randf_range(1.4, 3.0))
						top = h - rng.randf_range(0.2, 1.2)
					"stain":
						size = Vector2(rng.randf_range(1.0, 2.6), rng.randf_range(0.9, 2.0))
						top = h + 0.1
					_:
						size = Vector2(rng.randf_range(0.6, 1.5), rng.randf_range(0.5, 1.2))
						top = rng.randf_range(0.9, 2.4) + size.y
				_decal(fac, w, off, top, size, kind, rng.randi() % VARIANTS)


static func _decal(fac: Node3D, w: Array, off: float, top: float, size: Vector2, kind: String, variant: int) -> void:
	var n: Vector3 = w[2]
	var along := Vector3(1, 0, 0) if w[1] else Vector3(0, 0, 1)
	var d := Decal.new()
	d.texture_albedo = texture(kind, variant)
	d.size = Vector3(size.x, 1.2, size.y)
	d.normal_fade = 0.6   # (the wall, not the floor or ceiling its box reaches into)
	d.cull_mask = 1
	d.distance_fade_enabled = true
	d.distance_fade_begin = 28.0
	d.distance_fade_length = 6.0
	d.albedo_mix = 0.9 if kind == "peel" else 0.75
	d.set_meta("grime", kind)
	fac.add_child(d)
	# The decal projects down its own -y: into the wall. Its z runs down the wall (the texture's v).
	d.transform = Transform3D(Basis(along, n, along.cross(n)), w[0] + along * off + n * 0.1 + Vector3(0, top - size.y / 2.0, 0))
	if d.transform.basis.z.y > 0.0:   # (keep the texture's top at the top whichever way the wall faces)
		d.transform.basis = Basis(-along, n, -along.cross(n))


## The textures: drawn once each, `variant` changes the dice.
static func texture(kind: String, variant: int) -> ImageTexture:
	var key := "%s%d" % [kind, variant]
	if _tex.has(key):
		return _tex[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var wpx := 96
	var hpx := 256 if kind == "rust" else 128
	var img := Baked.image("grime_" + key, func() -> Image:   # (drawn once, kept as a file)
		var drawn := Image.create(wpx, hpx, false, Image.FORMAT_RGBA8)
		match kind:
			"rust": _rust(drawn, rng)
			"stain": _stain(drawn, rng)
			_: _peel(drawn, rng)
		return drawn)
	img.generate_mipmaps()
	_tex[key] = ImageTexture.create_from_image(img)
	return _tex[key]


static func _noise(x: float, y: float, s: int) -> float:   # value noise, 0..1
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - ix
	var fy := y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _h(ix, iy, s)
	var b := _h(ix + 1, iy, s)
	var c := _h(ix, iy + 1, s)
	var e := _h(ix + 1, iy + 1, s)
	return lerpf(lerpf(a, b, fx), lerpf(c, e, fx), fy)


static func _h(x: int, y: int, s: int) -> float:
	return float(hash(Vector3i(x, y, s)) % 10007) / 10007.0


## Rust bleeding down: a dark source near the top, streaks of different widths running down from it,
## thinning and fading as they go, the colour going from deep brown to orange.
static func _rust(img: Image, rng: RandomNumberGenerator) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var s := rng.randi()
	var streaks := []
	for k in rng.randi_range(6, 12):
		streaks.append([rng.randf_range(0.2, 0.8) * w, rng.randf_range(2.5, 10.0), rng.randf_range(0.3, 1.0)])   # x, width px, length 0..1
	for y in h:
		var v := float(y) / h
		for x in w:
			var a := 0.0
			var wash := 0.0
			for st in streaks:
				if v > st[2]:
					continue
				var wob: float = st[0] + (_noise(v * 6.0, 0.0, s + int(st[0])) - 0.5) * 7.0
				var width: float = st[1] * (1.0 - v / st[2] * 0.6)
				var fade := pow(1.0 - v / st[2], 0.6)
				var dx := absf(x - wob)
				a = maxf(a, (1.0 - smoothstep(width * 0.35, width, dx)) * fade)
				wash = maxf(wash, (1.0 - smoothstep(width, width * 3.5, dx)) * fade * 0.3)   # the faint orange wash round each run
			var src := (1.0 - smoothstep(0.0, 0.14, v)) * (1.0 - smoothstep(w * 0.15, w * 0.4, absf(x - w * 0.5)))   # the source: a blot at the top
			a = maxf(maxf(a, wash), src) * lerpf(0.6, 1.0, _noise(x * 0.3, y * 0.08, s))
			var col := Color(0.4, 0.15, 0.05).lerp(Color(0.8, 0.4, 0.12), smoothstep(0.05, 0.7, v))
			img.set_pixel(x, y, Color(col, clampf(a, 0.0, 1.0) * 0.95))


## Water stain: a pale, blotchy bloom of the salts the water left, hanging from the top edge and
## ragged at its foot (it shows on a dark wall as on a light one), a little darker toward its edge.
## (No hard tide lines: drawn dark they read as cracks or shadow stripes.)
static func _stain(img: Image, rng: RandomNumberGenerator) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var s := rng.randi()
	for y in h:
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var v := (y + 0.5) / h
			var reach := 0.7 + (_noise(u * 2.2 + 7.0, 0.5, s) - 0.5) * 0.9 + (_noise(u * 9.0, 1.5, s + 2) - 0.5) * 0.25   # how far down it got here
			var side := 1.0 - smoothstep(0.55, 1.0, absf(u) + (_noise(v * 3.0, 4.0, s + 4) - 0.5) * 0.3)
			var f := v / maxf(reach, 0.15)   # 0 at the top, 1 at its foot here
			var body := (1.0 - smoothstep(0.75, 1.0, f)) * side
			var blotch := 0.45 + 0.55 * _noise(x * 0.09, y * 0.09, s + 1)
			var rim := smoothstep(0.6, 0.95, f) * body   # a little darker where it dried back
			var a := body * 0.45 * blotch
			var col := Color(0.66, 0.62, 0.52).lerp(Color(0.42, 0.36, 0.26), rim)
			img.set_pixel(x, y, Color(col, clampf(a, 0.0, 1.0)))


## Peeling paint: a ragged patch where the paint's gone, the pale grey render under it, a thin dark
## line of shadow under the lifted edge and a lighter lip of curled paint along it.
static func _peel(img: Image, rng: RandomNumberGenerator) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var s := rng.randi()
	for y in h:
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var v := (y + 0.5) / h * 2.0 - 1.0
			var n := _noise(x * 0.09, y * 0.09, s) * 0.65 + _noise(x * 0.3, y * 0.3, s + 3) * 0.35
			var r := sqrt(u * u + v * v) + (n - 0.5) * 0.7
			var c := Color(0, 0, 0, 0)
			if r < 0.62:   # bare render
				c = Color(0.44, 0.42, 0.39, 0.9).lerp(Color(0.33, 0.31, 0.29, 0.9), _noise(x * 0.4, y * 0.4, s + 5))
			elif r < 0.68:   # the curled lip, catching light
				c = Color(0.62, 0.6, 0.55, 0.8)
			elif r < 0.76:   # its shadow on the paint
				c = Color(0.05, 0.04, 0.03, 0.45 * (1.0 - (r - 0.68) / 0.08))
			img.set_pixel(x, y, c)
