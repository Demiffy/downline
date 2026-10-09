# Cracked visor glass, drawn once per size and kept: impact points with cracks running out from
# them (wandering, forking), a tight spider-web of rings round each impact and a few chips of glass.
# Tiers add impacts: 1 a single strike low on one side, 2 another across the top, 3 the visor nearly
# gone. Used full-screen by the HUD (your own visor) and on the suit's visor (everyone else's view).
extends RefCounted

const IMPACTS := [[Vector2(0.18, 0.74), 1.0], [Vector2(0.8, 0.22), 0.9], [Vector2(0.62, 0.82), 0.8], [Vector2(0.32, 0.3), 0.85], [Vector2(0.9, 0.62), 0.6]]
const PER_TIER := [0, 1, 2, 5]   # impacts shown at each tier

static var _cache := {}


## The crack texture for `tier` (1..3) at `size` px square: white lines with a dark edge, on clear.
static func texture(tier: int, size := 512) -> ImageTexture:
	tier = clampi(tier, 1, 3)
	var key := "%d|%d" % [tier, size]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	for k in PER_TIER[tier]:
		rng.seed = 9100 + k * 37   # (the same strike in the same place at every tier)
		var at: Vector2 = IMPACTS[k][0] * size
		var power: float = IMPACTS[k][1]
		for r in 3:   # the web round the impact
			var rad := (6.0 + r * 9.0) * power * size / 512.0
			var a0 := rng.randf() * TAU
			var steps := 7 + r * 3
			for s in steps:
				if rng.randf() < 0.75:
					var a := a0 + TAU * s / steps
					var b := a + TAU / steps * rng.randf_range(0.7, 1.1)
					_line(img, at + Vector2(cos(a), sin(a)) * rad, at + Vector2(cos(b), sin(b)) * rad * rng.randf_range(0.9, 1.15), 0.7)
		for c in rng.randi_range(6, 9):   # the cracks running out from it
			_crack(img, rng, at, rng.randf() * TAU, power * size * rng.randf_range(0.18, 0.42), 2)
		for c in 5:   # chipped flecks right at the impact
			var p := at + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 5.0 * power
			_dot(img, p, 0.9)
	img.generate_mipmaps()
	_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


## One crack: a wandering line `length` long from `from`, forking now and then (`forks` deep).
static func _crack(img: Image, rng: RandomNumberGenerator, from: Vector2, ang: float, length: float, forks: int) -> void:
	var p := from
	var left := length
	var seg := maxf(4.0, length / 9.0)
	while left > 0.0:
		ang += rng.randf_range(-0.35, 0.35)
		var q := p + Vector2(cos(ang), sin(ang)) * minf(seg, left)
		_line(img, p, q, clampf(left / length + 0.3, 0.35, 1.0))
		if forks > 0 and rng.randf() < 0.22:
			_crack(img, rng, q, ang + rng.randf_range(0.5, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0), left * rng.randf_range(0.3, 0.6), forks - 1)
		p = q
		left -= seg


## A line of crack: bright core over a dark edge (so it reads on light and dark alike).
static func _line(img: Image, a: Vector2, b: Vector2, strength: float) -> void:
	var n := int(maxf(a.distance_to(b), 1.0))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		_px(img, p + Vector2(1, 1), Color(0.0, 0.0, 0.0, 0.55 * strength))
		_px(img, p, Color(0.92, 0.95, 1.0, 0.9 * strength))
		if strength > 0.6:   # the main cracks, near the strike, are wider
			_px(img, p + Vector2(1, 0), Color(0.92, 0.95, 1.0, 0.75 * strength))
			_px(img, p + Vector2(2, 1), Color(0.0, 0.0, 0.0, 0.4 * strength))


static func _dot(img: Image, p: Vector2, strength: float) -> void:
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			_px(img, p + Vector2(dx, dy), Color(0.95, 0.97, 1.0, 0.7 * strength))


static func _px(img: Image, p: Vector2, c: Color) -> void:
	var x := int(p.x)
	var y := int(p.y)
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var old := img.get_pixel(x, y)
	if c.a > old.a or c.r > old.r:   # (bright over dark: the core wins where they cross)
		img.set_pixel(x, y, c if c.r > 0.5 or old.a < 0.05 else old)
