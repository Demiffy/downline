# Old, weathered text for the world: the game's own lettering (glyphs.gd) stroked into an image, then
# aged: paint chipped off, faded and grimy, drips run down. The result goes on a lit, one-sided quad,
# so it reads like paint on the surface behind it. Styles: "stencil" (spray-painted codes and labels),
# "plate" (old slab-serif signage), "type" (typewritten paper), "chalk" (chalkboard).
extends RefCounted

const Glyphs = preload("res://src/glyphs.gd")
const STYLES := {
	"stencil": {"chips": 0.74, "speckle": 0.01, "drips": true, "fade": 0.25},
	"plate": {"chips": 0.72, "speckle": 0.02, "drips": false, "fade": 0.3},
	"type": {"chips": 0.8, "speckle": 0.06, "drips": false, "fade": 0.35},
	"chalk": {"chips": 0.75, "speckle": 0.3, "drips": false, "fade": 0.15},
}
const CAP := 0.72    # the capitals' height, of `size`...
const LINE := 1.25   # ...and a line's, of `size` (so `size` works much as a font's pixel size did)

static var _noise: Image
static var _cache := {}


static func _grime(x: int, y: int) -> float:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.06
		n.fractal_octaves = 3
		_noise = n.get_seamless_image(256, 256)
	return _noise.get_pixel(posmod(x, 256), posmod(y, 256)).r


## Weathered paint texture for `text`. Same inputs give the same (cached) texture.
static func texture(text: String, style: String, c: Color, size := 48) -> ImageTexture:
	var key := "%s|%s|%s|%d" % [text, style, c.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var st: Dictionary = STYLES[style]
	var lines := text.split("\n")
	var cap := size * CAP
	var line_h := int(size * LINE)
	var pad := int(size * 0.3)
	var w := 8
	for l in lines:
		w = maxi(w, int(ceil(Glyphs.line_width(l, style) * cap)))
	var img := Image.create(w + pad * 2, line_h * lines.size() + pad * 2, false, Image.FORMAT_RGBA8)
	var mask := PackedFloat32Array()
	mask.resize(img.get_width() * img.get_height())
	var iw := img.get_width()
	var ih := img.get_height()
	var rng := RandomNumberGenerator.new()
	rng.seed = key.hash()
	for li in lines.size():
		var lw := Glyphs.line_width(lines[li], style) * cap
		Glyphs.draw_line(mask, iw, ih, lines[li], style, pad + (w - lw) / 2.0, pad + li * line_h + size * 0.1, cap, rng)
	# Drips: paint runs down from the bottom edge of strokes.
	if st.drips:
		for k in int(w / float(size) * 1.5):
			var x := rng.randi_range(pad, iw - pad - 1)
			var y := ih - 1
			while y > 0 and mask[y * iw + x] < 0.5:
				y -= 1
			if y <= 0:
				continue
			var run := rng.randi_range(size / 8, size / 3)
			for d in run:
				if y + d >= ih:
					break
				var a := 1.0 - float(d) / run
				for xx in [x, x + 1]:
					if xx < iw:
						mask[(y + d) * iw + xx] = maxf(mask[(y + d) * iw + xx], a)
	# Age it: chips, speckle holes, fading and grime.
	var ox := rng.randi_range(0, 255)
	var oy := rng.randi_range(0, 255)
	var chips: float = st.chips
	for y in ih:
		for x in iw:
			var a := mask[y * iw + x]
			if a <= 0.0:
				continue
			var n := _grime(x * 90 / size + ox, y * 90 / size + oy)   # flakes ~ a tenth of a letter: worn, never a letter gone
			if n > chips or rng.randf() < st.speckle:
				continue
			var col := c.lerp(Color(0.55, 0.52, 0.47), clampf((n - 0.35) * 1.6, 0.0, 1.0) * st.fade)
			col = col.darkened(rng.randf() * 0.12)
			col.a = a
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(mips(img))
	_cache[key] = tex
	return tex


## A painted quad centred on `pos`, facing +z. `height` is the line height in metres. `fit`: the most
## room the lettering may take (width, height in metres; 0 for no limit): bigger, it's scaled down to
## fit, so it never runs off the plate or wall it's painted on.
static func quad(parent: Node, text: String, pos: Vector3, height: float, c := Color.WHITE, style := "stencil", fit := Vector2.ZERO) -> MeshInstance3D:
	var size := 48
	var tex := texture(text, style, c, size)
	var lh := size * LINE
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	var m := height / lh   # metres a pixel
	var pad := int(size * 0.3)
	var lettered := Vector2(tex.get_width() - pad * 2, tex.get_height() - pad * 2) * m
	if fit.x > 0.0 and lettered.x > fit.x:
		m *= fit.x / lettered.x
		lettered = Vector2(tex.get_width() - pad * 2, tex.get_height() - pad * 2) * m
	if fit.y > 0.0 and lettered.y > fit.y:
		m *= fit.y / lettered.y
	q.size = Vector2(tex.get_width(), tex.get_height()) * m
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.45
	mat.roughness = 0.95
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = pos
	mi.set_meta("paint", text)
	if Engine.has_meta("sign_survey"):   # (tests/sign_survey.gd: where each one comes from)
		mi.set_meta("src", where_from())
	return mi


## The first caller outside the lettering code: "file.gd:line" (debug builds only).
static func where_from() -> String:
	for f in get_stack():
		var file := String(f.source).get_file()
		if not file in ["paint.gd", "build.gd", "glyphs.gd"]:
			return "%s:%d" % [file, f.line]
	return "?"


## A mip chain that keeps thin strokes: each smaller level's alpha is scaled up just enough to keep as
## many pixels over the cutout (0.45) as the full size has. Averaged as usual, a diagonal thins below
## it a few metres off and whole letters went (a K, an A).
static func mips(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var cut := 115   # (0.45 of 255)
	var want := _over(data, cut, 1.0) / float(w * h)
	var cur := img
	while cur.get_width() > 1 or cur.get_height() > 1:
		var nxt := cur.duplicate() as Image
		nxt.resize(maxi(1, cur.get_width() / 2), maxi(1, cur.get_height() / 2), Image.INTERPOLATE_BILINEAR)
		var d := nxt.get_data()
		var n := nxt.get_width() * nxt.get_height()
		var hist := PackedInt32Array()
		hist.resize(256)
		for i in range(3, d.size(), 4):
			hist[d[i]] += 1
		var k := 1.0
		while k < 4.0 and _over_hist(hist, cut, k) < want * n:
			k += 0.1
		if k > 1.0:
			for i in range(3, d.size(), 4):
				d[i] = mini(255, int(d[i] * k))
		data.append_array(d)
		cur = Image.create_from_data(nxt.get_width(), nxt.get_height(), false, Image.FORMAT_RGBA8, d)
	return Image.create_from_data(w, h, true, Image.FORMAT_RGBA8, data)


static func _over(data: PackedByteArray, cut: int, k: float) -> int:
	var n := 0
	for i in range(3, data.size(), 4):
		if data[i] * k > cut:
			n += 1
	return n


static func _over_hist(hist: PackedInt32Array, cut: int, k: float) -> int:
	var n := 0
	for a in range(1, 256):
		if a * k > cut:
			n += hist[a]
	return n
