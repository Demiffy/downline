# Old, weathered text for the world: glyphs are blitted from a system font into an image, then
# aged: stencil bridges cut through the letters, paint chipped off, faded and grimy, drips run down.
# The result goes on a lit, one-sided quad, so it reads like paint on the surface behind it.
# Styles: "stencil" (spray-painted codes and labels), "plate" (old slab-serif signage),
# "type" (typewritten paper), "chalk" (chalkboard). Fonts are the OS's own, so no files ship.
extends RefCounted

const STYLES := {
	"stencil": {"fonts": ["DIN Condensed", "Impact", "Arial Narrow", "DejaVu Sans Condensed"], "weight": 700,
		"chips": 0.74, "speckle": 0.01, "drips": true, "bridges": true, "fade": 0.25},
	"plate": {"fonts": ["Rockwell", "Copperplate", "Georgia", "DejaVu Serif"], "weight": 700,
		"chips": 0.72, "speckle": 0.02, "drips": false, "bridges": false, "fade": 0.3},
	"type": {"fonts": ["American Typewriter", "Courier New", "Courier", "DejaVu Sans Mono"], "weight": 400,
		"chips": 0.8, "speckle": 0.06, "drips": false, "bridges": false, "fade": 0.35},
	"chalk": {"fonts": ["Chalkduster", "Chalkboard", "Comic Sans MS", "DejaVu Sans"], "weight": 400,
		"chips": 0.75, "speckle": 0.3, "drips": false, "bridges": false, "fade": 0.15},
}

static var _fonts := {}
static var _noise: Image
static var _cache := {}


static func _font(style: String) -> Font:
	if not _fonts.has(style):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(STYLES[style].fonts)
		f.font_weight = STYLES[style].weight
		_fonts[style] = f
	return _fonts[style]


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
	var font := _font(style)
	var ts := TextServerManager.get_primary_interface()
	var rids := font.get_rids()
	var lines := text.split("\n")
	var line_h := int(font.get_height(size))
	var pad := int(size * 0.3)
	var w := 8
	for l in lines:
		w = maxi(w, int(font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x))
	var img := Image.create(w + pad * 2, line_h * lines.size() + pad * 2, false, Image.FORMAT_RGBA8)
	var mask := PackedFloat32Array()
	mask.resize(img.get_width() * img.get_height())
	var iw := img.get_width()
	var ih := img.get_height()
	var sz := Vector2i(size, 0)
	var atlases := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = key.hash()
	if not rids.is_empty():
		var rid: RID = rids[0]
		var asc := ts.font_get_ascent(rid, size)
		for li in lines.size():
			var line: String = lines[li]
			var lw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var pen := Vector2(pad + (w - lw) / 2.0, pad + asc + li * line_h)
			for ch in line:
				var g := ts.font_get_glyph_index(rid, size, ch.unicode_at(0), 0)
				ts.font_render_glyph(rid, sz, g)
				var ti := ts.font_get_glyph_texture_idx(rid, sz, g)
				if ti >= 0:
					if not atlases.has(ti):
						atlases[ti] = ts.font_get_texture_image(rid, sz, ti)
					var atlas: Image = atlases[ti]
					var uv := ts.font_get_glyph_uv_rect(rid, sz, g)
					var o := pen + ts.font_get_glyph_offset(rid, sz, g)
					var gw := int(uv.size.x)
					# Stencil bridge: a thin vertical cut through the middle of wide letters.
					var cut := -1
					if st.bridges and gw > size * 0.32 and not (ch in "IJ1l|!.:,-"):
						cut = int(gw * rng.randf_range(0.45, 0.55))
					for y in int(uv.size.y):
						for x in gw:
							if cut >= 0 and absi(x - cut) <= maxi(1, size / 28):
								continue
							var dx := int(o.x) + x
							var dy := int(o.y) + y
							if dx < 0 or dy < 0 or dx >= iw or dy >= ih:
								continue
							var a := atlas.get_pixel(int(uv.position.x) + x, int(uv.position.y) + y).a
							mask[dy * iw + dx] = maxf(mask[dy * iw + dx], a)
				pen.x += ts.font_get_glyph_advance(rid, size, g).x
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
			var n := _grime(x * 30 / size + ox, y * 30 / size + oy)   # flakes ~ a third of a letter
			if n > chips or rng.randf() < st.speckle:
				continue
			var col := c.lerp(Color(0.55, 0.52, 0.47), clampf((n - 0.35) * 1.6, 0.0, 1.0) * st.fade)
			col = col.darkened(rng.randf() * 0.12)
			col.a = a
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## A painted quad centred on `pos`, facing +z. `height` is the line height in metres.
static func quad(parent: Node, text: String, pos: Vector3, height: float, c := Color.WHITE, style := "stencil") -> MeshInstance3D:
	var size := 48
	var tex := texture(text, style, c, size)
	var lh := _font(style).get_height(size)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(tex.get_width(), tex.get_height()) * height / lh
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.roughness = 0.95
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = pos
	return mi
