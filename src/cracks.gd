# Cracked visor glass, drawn once per tier and kept. Each impact: a spider web of rings round the
# point, a tight star of short cracks, long cracks running out (wandering, forking, thinning), chips
# of glass, and the glass round it frosted with fine fractures. Tiers add impacts: 1 a single strike
# low on one side, 2 another across the top, 3 the visor nearly gone.
# The texture: R the cracks (anti-aliased, wider near the strike), G the frosting. Used by the HUD on
# your own visor (overlay(): a screen shader that bends the light at the crack edges, blurs and
# whitens the frosted glass, fringes colour at the cracks) and on the suit's visor (visor_material()).
extends RefCounted

const IMPACTS := [[Vector2(0.2, 0.66), 1.0], [Vector2(0.79, 0.3), 0.9], [Vector2(0.6, 0.72), 0.8], [Vector2(0.33, 0.33), 0.85], [Vector2(0.9, 0.6), 0.6]]
const PER_TIER := [0, 1, 2, 5]   # impacts shown at each tier
const SIZE := 1024

static var _cache := {}
static var _images := {}
static var _lock := Mutex.new()


## The crack texture for `tier` (1..3). (`size` is ignored: one size serves both uses.)
static func texture(tier: int, _size := SIZE) -> ImageTexture:
	tier = clampi(tier, 1, 3)
	if not _cache.has(tier):
		_cache[tier] = ImageTexture.create_from_image(image(tier))
	return _cache[tier]


## Draw every tier ahead, on a worker thread (each takes a moment; a hit shouldn't hitch).
static func warm() -> void:
	WorkerThreadPool.add_task(func():
		for t in [1, 2, 3]:
			image(t))


static func image(tier: int) -> Image:
	_lock.lock()
	if not _images.has(tier):
		_images[tier] = _draw(tier)
	var img: Image = _images[tier]
	_lock.unlock()
	return img


static func _draw(tier: int) -> Image:
	var n := SIZE
	var core := PackedFloat32Array()
	core.resize(n * n)
	var rng := RandomNumberGenerator.new()
	var shown: int = PER_TIER[tier]
	for k in shown:
		rng.seed = 9100 + k * 37   # (the same strike in the same place at every tier)
		var at: Vector2 = IMPACTS[k][0] * n
		var power: float = IMPACTS[k][1]
		var sc := power * n / 1024.0
		for r in 4:   # the web: rings round the impact (straight pieces between the radial cracks)
			var rad := (12.0 + r * r * 9.0 + r * 10.0) * sc
			var a0 := rng.randf() * TAU
			var steps := 7 + r * 2
			for s in steps:
				if rng.randf() < 0.88 - r * 0.15:
					var a := a0 + TAU * s / steps
					var b := a + TAU / steps * rng.randf_range(0.75, 1.05)
					var pa := at + Vector2(cos(a), sin(a)) * rad * rng.randf_range(0.92, 1.08)
					var pb := at + Vector2(cos(b), sin(b)) * rad * rng.randf_range(0.92, 1.08)
					_seg(core, n, pa, pb, 0.75 - r * 0.1, 0.8 - r * 0.15)
		for c in rng.randi_range(8, 11):   # the star: short cracks right round the strike
			var a := rng.randf() * TAU
			_seg(core, n, at, at + Vector2(cos(a), sin(a)) * rng.randf_range(10.0, 22.0) * sc, 1.1, 1.0)
		var spokes := rng.randi_range(6, 8)
		for c in spokes:   # the long cracks running out, spread evenly round it
			var a := TAU * (c + rng.randf_range(-0.3, 0.3)) / spokes
			_crack(core, n, rng, at, a, power * n * rng.randf_range(0.18, 0.42), 2, 1.15 * sqrt(power))
		for c in 9:   # chips knocked out at the strike
			var p := at + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 7.0 * sc
			_seg(core, n, p, p + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2)), 1.6, 1.0)
	# The frosting: crushed glass round each strike, fading out and broken up, drawn small and scaled up.
	var lo := 128
	var frost := Image.create(lo, lo, false, Image.FORMAT_RF)
	for y in lo:
		for x in lo:
			var p := Vector2(x + 0.5, y + 0.5) / lo
			var v := 0.0
			for k in shown:
				var d: float = p.distance_to(IMPACTS[k][0]) / (0.06 * IMPACTS[k][1])
				var grain := 0.65 + 0.35 * sin(x * 2.3 + y * 1.7 + k) * sin(x * 0.9 - y * 2.9)
				v = maxf(v, exp(-d * d) * grain)
			frost.set_pixel(x, y, Color(v, 0, 0))
	frost.resize(n, n, Image.INTERPOLATE_CUBIC)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var fd := frost.get_data().to_float32_array()
	var out := PackedByteArray()
	out.resize(n * n * 4)
	for i in n * n:
		out[i * 4] = int(clampf(core[i], 0.0, 1.0) * 255.0)
		out[i * 4 + 1] = int(clampf(fd[i], 0.0, 1.0) * 255.0)
		out[i * 4 + 2] = 0
		out[i * 4 + 3] = 255
	img.set_data(n, n, false, Image.FORMAT_RGBA8, out)
	img.generate_mipmaps()
	return img


## One crack: a wandering line `length` long from `from`, forking now and then (`forks` deep),
## `w` wide at the start thinning to a hairline.
static func _crack(core: PackedFloat32Array, n: int, rng: RandomNumberGenerator, from: Vector2, ang: float, length: float, forks: int, w: float) -> void:
	var p := from
	var left := length
	var seg := maxf(8.0, length / 7.0)
	while left > 0.0:
		ang += rng.randf_range(-0.1, 0.1)   # (glass breaks nearly straight, kinking a little)
		var q := p + Vector2(cos(ang), sin(ang)) * minf(seg, left)
		var t := left / length
		_seg(core, n, p, q, lerpf(0.45, w, t), clampf(t + 0.3, 0.35, 1.0))
		if forks > 0 and rng.randf() < 0.1:
			_crack(core, n, rng, q, ang + rng.randf_range(0.35, 0.8) * (1.0 if rng.randf() < 0.5 else -1.0), left * rng.randf_range(0.25, 0.5), forks - 1, lerpf(0.5, w, t) * 0.8)
		p = q
		left -= seg


## A line segment into the crack mask, anti-aliased: `w` its half width in pixels, `s` its strength.
static func _seg(core: PackedFloat32Array, n: int, a: Vector2, b: Vector2, w: float, s: float) -> void:
	var r := int(ceil(w + 1.0))
	var x0 := maxi(int(minf(a.x, b.x)) - r, 0)
	var x1 := mini(int(maxf(a.x, b.x)) + r, n - 1)
	var y0 := maxi(int(minf(a.y, b.y)) - r, 0)
	var y1 := mini(int(maxf(a.y, b.y)) + r, n - 1)
	var ab := b - a
	var l2 := maxf(ab.length_squared(), 0.0001)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			var v := clampf(w + 0.5 - d, 0.0, 1.0) * s
			var i := y * n + x
			if v > core[i]:
				core[i] = v


const OVERLAY := """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D cracks : filter_linear_mipmap;
uniform float aspect = 1.7778;
uniform float amount = 1.0;   // fades it in

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 tuv = vec2(uv.x, (uv.y - 0.5) / aspect + 0.5);   // (square cracks across the width: never stretched)
	vec4 c = texture(cracks, tuv);
	float e = 3.0 / 1024.0;   // light bends where the glass is broken: the slope of the blurred cracks
	float l = textureLod(cracks, tuv - vec2(e, 0.0), 2.5).r;
	float r = textureLod(cracks, tuv + vec2(e, 0.0), 2.5).r;
	float d = textureLod(cracks, tuv - vec2(0.0, e), 2.5).r;
	float u = textureLod(cracks, tuv + vec2(0.0, e), 2.5).r;
	vec2 off = vec2(r - l, u - d) * 0.02 * amount;
	off += (c.g * vec2(0.006, -0.004)) * amount;   // the frosted glass sits askew
	vec3 col = vec3(texture(screen_tex, uv + off * 1.35).r, texture(screen_tex, uv + off).g, texture(screen_tex, uv + off * 0.65).b);
	vec3 blur = textureLod(screen_tex, uv + off, 3.0).rgb;
	col = mix(col, blur * 1.1 + vec3(0.05, 0.055, 0.06), clamp(c.g * 0.85, 0.0, 0.8) * amount);   // frost
	float halo = textureLod(cracks, tuv, 1.5).r;
	col *= 1.0 - halo * 0.35 * amount;   // the dark edge either side of a crack
	// A crack is mostly clear glass: it catches the light only here and there along it (and more
	// where the scene behind is bright), glinting as you turn your head.
	float glint = 0.5 + 0.5 * sin(tuv.x * 61.0 + tuv.y * 37.0 + sin(tuv.y * 23.0 - tuv.x * 11.0) * 3.0);
	glint = 0.25 + 0.75 * pow(glint, 3.0);
	float lum = dot(col, vec3(0.3, 0.55, 0.15));
	float shine = clamp(c.r * glint * (0.55 + lum * 0.8), 0.0, 1.0);
	col = mix(col, vec3(0.88, 0.93, 1.0), shine * 0.8 * amount);
	COLOR = vec4(col, 1.0);
}
"""

const VISOR := """shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
uniform sampler2D cracks : filter_linear_mipmap;
uniform vec2 centre = vec2(0.0, 0.168);
uniform float scale = 3.0;
varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 uv = vec2(0.5 + lp.x * scale, 0.5 - (lp.y - centre.y) * scale);
	vec4 c = texture(cracks, uv);
	float frost = clamp(c.g * 0.6, 0.0, 0.55);
	float glint = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(uv.x * 61.0 + uv.y * 37.0), 2.0);
	ALBEDO = mix(vec3(0.75, 0.78, 0.82), vec3(0.95, 0.97, 1.0), c.r);
	ALPHA = clamp(max(c.r * 0.8 * glint, frost), 0.0, 1.0);
	ROUGHNESS = mix(0.15, 0.6, frost);
	METALLIC = 0.2;
	EMISSION = vec3(0.45, 0.5, 0.55) * c.r * 0.6;   // (the light catches the broken edges)
}
"""

static var _visor_shader: Shader
static var _overlay_shader: Shader


## The suit visor's crack layer for `tier`.
static func visor_material(tier: int) -> ShaderMaterial:
	if _visor_shader == null:
		_visor_shader = Shader.new()
		_visor_shader.code = VISOR
	var m := ShaderMaterial.new()
	m.shader = _visor_shader
	m.set_shader_parameter("cracks", texture(tier))
	return m


## The full-screen overlay for your own visor (a ColorRect over the view, under the readouts).
static func overlay() -> ColorRect:
	if _overlay_shader == null:
		_overlay_shader = Shader.new()
		_overlay_shader.code = OVERLAY
	var r := ColorRect.new()
	var m := ShaderMaterial.new()
	m.shader = _overlay_shader
	r.material = m
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
