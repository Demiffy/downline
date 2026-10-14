# The game's own lettering, drawn in code: one chamfered, industrial skeleton (the DOWNLINE logo's
# family: square corners cut at 45 degrees, no circles), stroked at a weight per style into a
# coverage mask that paint.gd ages. No font files, and the same letters on every machine.
#
# A glyph is a list of strokes, each a polyline "x,y x,y ..." in cap units: x from 0, y 0 at the top
# of the capitals, 1 on the baseline, 0.38 the top of the lowercase, down to 1.3 for descenders.
# Styles (STYLE): "stencil" bold and condensed with bridges cut through bowls and crossbars, "plate"
# even weight with slab serifs on the stems, "type" thin and monospaced, a little uneven, "chalk"
# wobbly and slanted.
extends RefCounted

const G := {
	"A": ["0,1 0,0.25 0.15,0 0.45,0 0.6,0.25 0.6,1", "0,0.56 0.6,0.56"],
	"B": ["0,1 0,0 0.44,0 0.58,0.13 0.58,0.36 0.46,0.48 0,0.48", "0.46,0.48 0.6,0.6 0.6,0.86 0.46,1 0,1"],
	"C": ["0.6,0.16 0.44,0 0.16,0 0,0.16 0,0.84 0.16,1 0.44,1 0.6,0.84"],
	"D": ["0,1 0,0 0.4,0 0.6,0.2 0.6,0.8 0.4,1 0,1"],
	"E": ["0.58,0 0,0 0,1 0.58,1", "0,0.5 0.44,0.5"],
	"F": ["0.58,0 0,0 0,1", "0,0.5 0.44,0.5"],
	"G": ["0.6,0.16 0.44,0 0.16,0 0,0.16 0,0.84 0.16,1 0.44,1 0.6,0.84 0.6,0.56 0.32,0.56"],
	"H": ["0,0 0,1", "0.6,0 0.6,1", "0,0.5 0.6,0.5"],
	"I": ["0,0 0,1"],
	"J": ["0.48,0 0.48,0.84 0.32,1 0.14,1 0,0.86 0,0.72"],
	"K": ["0,0 0,1", "0.58,0 0,0.62", "0.2,0.43 0.6,1"],
	"L": ["0,0 0,1 0.54,1"],
	"M": ["0,1 0,0 0.36,0.56 0.72,0 0.72,1"],
	"N": ["0,1 0,0 0.6,1 0.6,0"],
	"O": ["0.16,0 0.44,0 0.6,0.16 0.6,0.84 0.44,1 0.16,1 0,0.84 0,0.16 0.16,0"],
	"P": ["0,1 0,0 0.44,0 0.6,0.16 0.6,0.4 0.44,0.56 0,0.56"],
	"Q": ["0.16,0 0.44,0 0.6,0.16 0.6,0.84 0.44,1 0.16,1 0,0.84 0,0.16 0.16,0", "0.36,0.76 0.62,1.06"],
	"R": ["0,1 0,0 0.44,0 0.6,0.16 0.6,0.4 0.44,0.56 0,0.56", "0.3,0.56 0.6,1"],
	"S": ["0.6,0.16 0.44,0 0.16,0 0,0.16 0,0.34 0.14,0.47 0.46,0.53 0.6,0.66 0.6,0.84 0.44,1 0.16,1 0,0.84"],
	"T": ["0,0 0.6,0", "0.3,0 0.3,1"],
	"U": ["0,0 0,0.84 0.16,1 0.44,1 0.6,0.84 0.6,0"],
	"V": ["0,0 0.3,1 0.6,0"],
	"W": ["0,0 0.18,1 0.38,0.36 0.58,1 0.76,0"],
	"X": ["0,0 0.6,1", "0.6,0 0,1"],
	"Y": ["0,0 0.3,0.5 0.6,0", "0.3,0.5 0.3,1"],
	"Z": ["0,0 0.6,0 0,1 0.6,1"],
	"0": ["0.14,0 0.41,0 0.55,0.14 0.55,0.86 0.41,1 0.14,1 0,0.86 0,0.14 0.14,0"],
	"1": ["0.06,0.2 0.28,0 0.28,1"],
	"2": ["0,0.16 0.14,0 0.41,0 0.55,0.14 0.55,0.38 0,1 0.55,1"],
	"3": ["0,0.12 0.12,0 0.43,0 0.55,0.12 0.55,0.36 0.43,0.48 0.18,0.48", "0.43,0.48 0.55,0.6 0.55,0.88 0.43,1 0.12,1 0,0.88"],
	"4": ["0.42,1 0.42,0 0,0.68 0.58,0.68"],
	"5": ["0.55,0 0,0 0,0.46 0.41,0.46 0.55,0.6 0.55,0.86 0.41,1 0.12,1 0,0.88"],
	"6": ["0.52,0.06 0.44,0 0.14,0 0,0.14 0,0.86 0.14,1 0.41,1 0.55,0.86 0.55,0.62 0.41,0.48 0,0.48"],
	"7": ["0,0 0.55,0 0.18,1"],
	"8": ["0.14,0.48 0.02,0.36 0.02,0.12 0.14,0 0.41,0 0.53,0.12 0.53,0.36 0.41,0.48 0.14,0.48 0,0.6 0,0.88 0.12,1 0.43,1 0.55,0.88 0.55,0.6 0.41,0.48"],
	"9": ["0.03,0.94 0.11,1 0.41,1 0.55,0.86 0.55,0.14 0.41,0 0.14,0 0,0.14 0,0.38 0.14,0.52 0.55,0.52"],
	"a": ["0.04,0.44 0.12,0.38 0.38,0.38 0.48,0.48 0.48,1", "0.48,0.66 0.12,0.66 0,0.76 0,0.9 0.1,1 0.36,1 0.48,0.9"],
	"b": ["0,0 0,1", "0,0.5 0.12,0.38 0.38,0.38 0.5,0.5 0.5,0.88 0.38,1 0.12,1 0,0.88"],
	"c": ["0.48,0.48 0.38,0.38 0.12,0.38 0,0.5 0,0.88 0.12,1 0.38,1 0.48,0.9"],
	"d": ["0.5,0 0.5,1", "0.5,0.5 0.38,0.38 0.12,0.38 0,0.5 0,0.88 0.12,1 0.38,1 0.5,0.88"],
	"e": ["0,0.68 0.5,0.68 0.5,0.5 0.38,0.38 0.12,0.38 0,0.5 0,0.88 0.12,1 0.42,1 0.5,0.92"],
	"f": ["0.38,0.03 0.3,0 0.2,0 0.1,0.1 0.1,1", "0,0.4 0.34,0.4"],
	"g": ["0.5,0.38 0.5,1.18 0.38,1.3 0.08,1.3", "0.5,0.5 0.38,0.38 0.12,0.38 0,0.5 0,0.84 0.12,0.96 0.38,0.96 0.5,0.84"],
	"h": ["0,0 0,1", "0,0.5 0.12,0.38 0.38,0.38 0.5,0.5 0.5,1"],
	"i": ["0,0.38 0,1", "0,0.12 0,0.18"],
	"j": ["0.22,0.38 0.22,1.18 0.1,1.3 0,1.28", "0.22,0.12 0.22,0.18"],
	"k": ["0,0 0,1", "0.46,0.38 0,0.72", "0.16,0.6 0.48,1"],
	"l": ["0,0 0,0.9 0.08,1"],
	"m": ["0,1 0,0.38", "0,0.48 0.1,0.38 0.24,0.38 0.33,0.48 0.33,1", "0.33,0.48 0.43,0.38 0.57,0.38 0.66,0.48 0.66,1"],
	"n": ["0,1 0,0.38", "0,0.5 0.12,0.38 0.38,0.38 0.5,0.5 0.5,1"],
	"o": ["0.12,0.38 0.38,0.38 0.5,0.5 0.5,0.88 0.38,1 0.12,1 0,0.88 0,0.5 0.12,0.38"],
	"p": ["0,0.38 0,1.3", "0,0.5 0.12,0.38 0.38,0.38 0.5,0.5 0.5,0.88 0.38,1 0.12,1 0,0.88"],
	"q": ["0.5,0.38 0.5,1.3", "0.5,0.5 0.38,0.38 0.12,0.38 0,0.5 0,0.88 0.12,1 0.38,1 0.5,0.88"],
	"r": ["0,0.38 0,1", "0,0.52 0.14,0.38 0.38,0.38"],
	"s": ["0.46,0.46 0.36,0.38 0.12,0.38 0.02,0.46 0.02,0.6 0.12,0.67 0.38,0.71 0.48,0.78 0.48,0.92 0.38,1 0.12,1 0,0.92"],
	"t": ["0.1,0.1 0.1,0.9 0.2,1 0.32,1", "0,0.4 0.3,0.4"],
	"u": ["0,0.38 0,0.88 0.12,1 0.38,1 0.5,0.88", "0.5,0.38 0.5,1"],
	"v": ["0,0.38 0.24,1 0.48,0.38"],
	"w": ["0,0.38 0.15,1 0.32,0.58 0.49,1 0.64,0.38"],
	"x": ["0,0.38 0.46,1", "0.46,0.38 0,1"],
	"y": ["0,0.38 0.24,0.98", "0.48,0.38 0.16,1.3"],
	"z": ["0,0.38 0.46,0.38 0,1 0.46,1"],
	".": ["0,0.96 0,1"],
	",": ["0.06,0.93 0.06,1 0,1.12"],
	":": ["0,0.36 0,0.4", "0,0.96 0,1"],
	";": ["0.06,0.36 0.06,0.4", "0.06,0.93 0.06,1 0,1.12"],
	"!": ["0,0 0,0.7", "0,0.96 0,1"],
	"?": ["0,0.16 0.14,0 0.38,0 0.5,0.12 0.5,0.32 0.24,0.5 0.24,0.7", "0.24,0.96 0.24,1"],
	"'": ["0,0 0,0.24"],
	"\"": ["0,0 0,0.24", "0.16,0 0.16,0.24"],
	"-": ["0,0.56 0.32,0.56"],
	"+": ["0,0.56 0.4,0.56", "0.2,0.36 0.2,0.76"],
	"=": ["0,0.44 0.4,0.44", "0,0.66 0.4,0.66"],
	"/": ["0,1 0.4,0"],
	"\\": ["0,0 0.4,1"],
	"(": ["0.2,0 0.04,0.2 0.04,0.8 0.2,1"],
	")": ["0,0 0.16,0.2 0.16,0.8 0,1"],
	"[": ["0.18,0 0,0 0,1 0.18,1"],
	"]": ["0,0 0.18,0 0.18,1 0,1"],
	"<": ["0.36,0.3 0,0.56 0.36,0.82"],
	">": ["0,0.3 0.36,0.56 0,0.82"],
	"*": ["0.2,0.06 0.2,0.46", "0.02,0.16 0.38,0.36", "0.38,0.16 0.02,0.36"],
	"#": ["0.16,0.1 0.12,0.9", "0.4,0.1 0.36,0.9", "0,0.36 0.52,0.36", "0,0.64 0.52,0.64"],
	"%": ["0,1 0.55,0", "0,0 0.16,0 0.16,0.22 0,0.22 0,0", "0.39,0.78 0.55,0.78 0.55,1 0.39,1 0.39,0.78"],
	"&": ["0.6,1 0.12,0.5 0.12,0.12 0.24,0 0.38,0 0.48,0.12 0.48,0.3 0,0.62 0,0.88 0.12,1 0.36,1 0.6,0.68"],
	"_": ["0,1.1 0.5,1.1"],
	"·": ["0,0.54 0,0.58"],
	"°": ["0,0.08 0.08,0 0.18,0 0.26,0.08 0.26,0.18 0.18,0.26 0.08,0.26 0,0.18 0,0.08"],
	"▲": ["0,0.94 0.27,0.42 0.54,0.94 0,0.94", "0.13,0.84 0.41,0.84", "0.27,0.6 0.27,0.84", "0.2,0.72 0.34,0.72"],
	"▼": ["0,0.42 0.27,0.94 0.54,0.42 0,0.42", "0.13,0.52 0.41,0.52", "0.27,0.52 0.27,0.76", "0.2,0.64 0.34,0.64"],
}
## Where a stencil bridges a glyph's closed counters (glyph units across): just past the stem, or
## through the middle of a round one. Others go whole.
const BRIDGE := {"D": 0.25, "P": 0.25, "O": 0.3, "Q": 0.3, "0": 0.275, "8": 0.275}
const SPACE := 0.36   # a word space, cap units
const GAP := 0.2      # between letters

## Per style: stroke weight (cap units), how condensed, monospaced cell, slab serifs, stencil bridges,
## wobble (chalk), slant, uneven baseline and ink (type).
const STYLE := {
	"stencil": {"weight": 0.23, "squeeze": 0.84, "mono": 0.0, "serifs": false, "bridges": true, "wobble": 0.0, "slant": 0.0, "jitter": 0.0},
	"plate": {"weight": 0.16, "squeeze": 0.92, "mono": 0.0, "serifs": true, "bridges": false, "wobble": 0.0, "slant": 0.0, "jitter": 0.0},
	"type": {"weight": 0.1, "squeeze": 1.0, "mono": 0.62, "serifs": true, "bridges": false, "wobble": 0.004, "slant": 0.0, "jitter": 0.025},
	"mono": {"weight": 0.14, "squeeze": 1.0, "mono": 0.66, "serifs": false, "bridges": false, "wobble": 0.0, "slant": 0.0, "jitter": 0.0},
	"chalk": {"weight": 0.11, "squeeze": 0.95, "mono": 0.0, "serifs": false, "bridges": false, "wobble": 0.035, "slant": 0.12, "jitter": 0.03},
}

static var _parsed := {}


## A glyph's strokes as PackedVector2Arrays (a character we have no glyph for draws as nothing).
static func strokes(ch: String) -> Array:
	if _parsed.has(ch):
		return _parsed[ch]
	var out: Array = []
	for s: String in G.get(ch, []):
		var pts := PackedVector2Array()
		for p in s.split(" ", false):
			pts.append(Vector2(float(p.get_slice(",", 0)), float(p.get_slice(",", 1))))
		out.append(pts)
	_parsed[ch] = out
	return out


static func _width(ch: String) -> float:
	var w := 0.0
	for pts: PackedVector2Array in strokes(ch):
		for p in pts:
			w = maxf(w, p.x)
	return w


## How wide a line is, in cap units, in `style`.
static func line_width(line: String, style: String) -> float:
	var st: Dictionary = STYLE[style]
	var w := 0.0
	for ch in line:
		w += _advance(ch, st)
	return maxf(w - GAP * st.squeeze, 0.0)


## Pen travel past a glyph: its width, the stroke's own weight, and the gap.
static func _advance(ch: String, st: Dictionary) -> float:
	if st.mono > 0.0:
		return st.mono
	if ch == " ":
		return SPACE * st.squeeze + st.weight
	return (_width(ch) + GAP) * st.squeeze + st.weight


## Strokes `line` into `mask` (w wide, row-major coverage 0..1): the capitals' top at `top`, cap height
## `cap` px, starting at x `left`. `rng` makes a style's wobble and unevenness (the same every time
## for the same seed).
static func draw_line(mask: PackedFloat32Array, w: int, h: int, line: String, style: String, left: float, top: float, cap: float, rng: RandomNumberGenerator) -> void:
	var st: Dictionary = STYLE[style]
	var half: float = st.weight * cap * 0.5
	var pen := left + half
	for ch in line:
		var adv: float = _advance(ch, st) * cap
		if ch == " ":
			pen += adv
			continue
		var gw := _width(ch)
		var sx: float = st.squeeze
		var ox := 0.0
		if st.mono > 0.0:   # (centred in its cell; a wide one squeezed into it)
			sx = minf(1.0, (st.mono - GAP * 0.6) / maxf(gw, 0.01))
			ox = (st.mono - GAP * 0.6 - gw * sx) * 0.5
		var dy: float = rng.randf_range(-1.0, 1.0) * st.jitter
		var ink: float = 1.0 - rng.randf() * (0.3 if st.jitter > 0.0 else 0.0)
		var at := func(p: Vector2) -> Vector2:
			var q := Vector2(ox + p.x * sx, p.y + dy)
			if st.wobble > 0.0:
				q += Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * st.wobble
			q.x += (1.0 - q.y) * st.slant
			return Vector2(pen + q.x * cap, top + q.y * cap)
		var cut := -1.0   # a stencil's bridge: where the bowls and crossbars break
		if st.bridges and BRIDGE.has(ch):
			cut = pen + (ox + float(BRIDGE[ch]) * sx) * cap
		for pts: PackedVector2Array in strokes(ch):
			var prev: Vector2 = at.call(pts[0])
			if pts.size() == 1:
				_seg(mask, w, h, prev, prev, half, ink, cut, half * 0.6)
			for i in range(1, pts.size()):
				var cur: Vector2 = at.call(pts[i])
				_seg(mask, w, h, prev, cur, half, ink, cut, half * 0.6)
				prev = cur
			if st.serifs and ch != ch.to_lower() or (st.serifs and ch.is_valid_int()):   # slab serifs where an upright stem meets the cap line or the baseline
				for k in [0, pts.size() - 1]:
					var n := 1 if k == 0 else pts.size() - 2
					var d := pts[k] - pts[n]
					if pts.size() > 1 and absf(d.y) > absf(d.x) * 2.5 and (pts[k].y < 0.02 or pts[k].y > 0.98):
						var e: Vector2 = at.call(pts[k])
						_seg(mask, w, h, e - Vector2(cap * 0.12, 0), e + Vector2(cap * 0.12, 0), half * 0.85, ink, -1.0, 0.0)
		pen += adv


## One stroke: a capsule half `r` wide from a to b, anti-aliased. Upright-ish strokes keep their whole
## length; flat ones lose a gap `gap` wide round x = `cut` (the stencil's bridge).
static func _seg(mask: PackedFloat32Array, w: int, h: int, a: Vector2, b: Vector2, r: float, ink: float, cut: float, gap: float) -> void:
	var x0 := maxi(0, int(minf(a.x, b.x) - r - 1.0))
	var x1 := mini(w - 1, int(maxf(a.x, b.x) + r + 1.0))
	var y0 := maxi(0, int(minf(a.y, b.y) - r - 1.0))
	var y1 := mini(h - 1, int(maxf(a.y, b.y) + r + 1.0))
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.0001)
	var flat := cut >= 0.0 and absf(ab.x) > absf(ab.y) * 0.8
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if flat and absf(x + 0.5 - cut) < gap:
				continue
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			var cov := clampf(r + 0.5 - d, 0.0, 1.0) * ink
			if cov > 0.0:
				var i := y * w + x
				mask[i] = maxf(mask[i], cov)



static var _fonts := {}

## The lettering as a Godot font, for text that changes or glows (Label3D: screens, readouts, the shop's
## sign, name tags): each glyph stroked once into an atlas at `px` (cap height about 0.72 of it), white
## on clear, tinted by the label. "mono" is the screens' (monospaced, even). Scales to any font_size.
static func font(style := "mono", px := 32) -> FontFile:
	var key := "%s|%d" % [style, px]
	if _fonts.has(key):
		return _fonts[key]
	var st: Dictionary = STYLE[style]
	var cap := px * 0.72
	var margin := int(ceil(cap * 0.14)) + 2   # (room either side for serifs and the stroke's width)
	var cell := Vector2i(int(ceil((1.0 + st.weight) * cap)) + margin * 2, int(px * 1.5))
	var chars: Array = [" "] + G.keys()
	var cols := 16
	var rows := int(ceil(chars.size() / float(cols)))
	var w := cols * cell.x
	var h := rows * cell.y
	var mask := PackedFloat32Array()
	mask.resize(w * h)
	var rng := RandomNumberGenerator.new()
	rng.seed = key.hash()
	var f := FontFile.new()
	f.fixed_size = px
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	var sz := Vector2i(px, 0)
	var top := px * 0.28   # (the capitals' top, below the line's top: room for accents' worth of air)
	for i in chars.size():
		var ch: String = chars[i]
		var ox := (i % cols) * cell.x + margin
		var oy := (i / cols) * cell.y
		if ch != " ":
			draw_line(mask, w, h, ch, style, ox, oy + top, cap, rng)
		var gi := ch.unicode_at(0)
		var adv := _advance(ch, st) * cap
		f.set_glyph_advance(0, px, gi, Vector2(adv, 0))
		f.set_glyph_offset(0, sz, gi, Vector2(-margin, -px * 1.05))
		f.set_glyph_size(0, sz, gi, Vector2(cell))
		f.set_glyph_uv_rect(0, sz, gi, Rect2((i % cols) * cell.x, oy, cell.x, cell.y))
		f.set_glyph_texture_idx(0, sz, gi, 0)
	var img := Image.create(w, h, false, Image.FORMAT_LA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color(1, 1, 1, mask[y * w + x]))
	f.set_texture_image(0, sz, 0, img)
	f.set_cache_ascent(0, px, px * 1.05)
	f.set_cache_descent(0, px, px * 0.4)
	_fonts[key] = f
	return f
