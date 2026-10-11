# Procedural art kit: pixel-grime textures (generated at startup, no image files) and prop builders.
# Look target: low-res point-filtered textures, warm rust palette, lots of clutter.
extends RefCounted

const B = preload("res://src/build.gd")
const PX := 64

static var _tex := {}
static var snow_cover := false   # set while an arctic surface is being built: roofs and caps get snow
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
	_tex[kind].set_meta("kind", kind)
	return _tex[kind]


static func _rand(kind: String, x: int, y: int) -> float:
	return float(posmod((x * 73856093) ^ (y * 19349663) ^ kind.hash(), 1009)) / 1009.0


static func _px(kind: String, x: int, y: int, v: float) -> Color:
	var r := _rand(kind, x, y)
	var c := Color.MAGENTA
	match kind:
		"panelling":   # varnished tongue-and-groove boards, vertical, with the grooves between
			c = Color(0.2, 0.12, 0.07).lerp(Color(0.38, 0.24, 0.13), v * 0.6 + r * 0.15 + 0.25 * sin(y * 0.6 + x * 0.05))
			if x % 8 == 0: c = c.darkened(0.55)
			elif x % 8 == 1: c = c.lightened(0.12)
			if v < 0.25: c = c.darkened(0.2)
		"enamel":   # painted steel, satin, tint picks the colour: faint brush marks, chips showing primer
			c = Color(0.82, 0.82, 0.8).lerp(Color(0.9, 0.9, 0.88), v * 0.5 + r * 0.1)
			if y % 32 == 0: c = c.darkened(0.25)   # panel seams
			if y % 32 == 2 and x % 8 == 4: c = c.darkened(0.4)   # rivets
		"linoleum":   # worn checker tiles
			var chk := (x / 16 + y / 16) % 2 == 0
			c = (Color(0.56, 0.53, 0.48) if chk else Color(0.3, 0.29, 0.27)).lerp(Color(0.42, 0.39, 0.35), v * 0.3)
			if x % 16 == 0 or y % 16 == 0: c = c.darkened(0.2)
			if r < 0.03: c = c.lightened(0.1)
		"runner":   # ribbed rubber floor mat
			c = Color(0.1, 0.1, 0.1).lerp(Color(0.18, 0.17, 0.16), v * 0.6)
			if y % 4 < 2: c = c.lightened(0.07)
		"headliner":   # ceiling panels: cream perforated board in a frame
			c = Color(0.85, 0.82, 0.74).lerp(Color(0.72, 0.68, 0.6), v * 0.5)
			if x % 4 == 2 and y % 4 == 2: c = c.darkened(0.3)
			if x % 32 == 0 or y % 32 == 0: c = Color(0.4, 0.35, 0.28)
			if v < 0.2: c = c.darkened(0.12)
		"asphalt":
			c = Color(0.13, 0.13, 0.13).lerp(Color(0.26, 0.25, 0.24), v * 0.7 + r * 0.3)
			if r < 0.04: c = c.lightened(0.2)
			if absf(v - 0.5) < 0.01: c = c.darkened(0.4)   # cracks
		"gravel":
			c = Color(0.3, 0.28, 0.25).lerp(Color(0.55, 0.52, 0.47), r)
			if v < 0.3: c = c.darkened(0.3)
		"mesa":   # banded desert rock: layered strata
			var band := sin(y * 0.35 + v * 3.0)
			c = Color(0.46, 0.33, 0.25).lerp(Color(0.68, 0.55, 0.43), 0.5 + 0.5 * band)
			if r < 0.05: c = c.darkened(0.3)
			if absf(band) < 0.05: c = c.darkened(0.35)
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
		"siding":   # painted clapboard, the paint flaking off grey boards (tint picks the paint colour)
			var board := y / 8
			var lip := y % 8
			c = Color(0.86, 0.84, 0.8).darkened(0.08 + (float(lip) / 8.0) * 0.12)
			if v > 0.6 + _rand(kind, board, 3) * 0.2:   # bare weathered wood where the paint has gone
				c = Color(0.5, 0.47, 0.43).lerp(Color(0.38, 0.35, 0.32), r)
			if lip == 7: c = c.darkened(0.45)   # shadow under each board's lap
			if r < 0.03: c = c.darkened(0.25)
		"brick":
			var row := y / 6
			var bx := (x + (8 if row % 2 == 1 else 0)) % 16
			c = Color(0.48, 0.2, 0.13).lerp(Color(0.6, 0.3, 0.18), _rand(kind, (x + (8 if row % 2 == 1 else 0)) / 16, row) * 0.7 + v * 0.3)
			if y % 6 == 5 or bx == 15: c = Color(0.55, 0.52, 0.47).darkened(v * 0.3)   # mortar
			elif r < 0.05: c = c.darkened(0.3)
		"shingle":   # asphalt roof shingles, staggered tabs, some missing
			var srow := y / 6
			var tab := (x + (5 if srow % 2 == 1 else 0)) / 10
			c = Color(0.2, 0.19, 0.18).lerp(Color(0.34, 0.31, 0.28), _rand(kind, tab, srow) * 0.6 + v * 0.4)
			if y % 6 == 5 or (x + (5 if srow % 2 == 1 else 0)) % 10 == 9: c = c.darkened(0.5)
			if _rand(kind, tab, srow + 50) < 0.06: c = Color(0.35, 0.25, 0.16).lerp(Color(0.25, 0.17, 0.1), r)   # missing: bare deck
		"stone":   # cold grey granite with lichen-dark flecks (arctic rock)
			c = Color(0.36, 0.38, 0.42).lerp(Color(0.6, 0.62, 0.66), v)
			if absf(v - 0.5) < 0.02: c = c.darkened(0.45)
			if r < 0.05: c = c.darkened(0.3)
			elif r > 0.97: c = c.lightened(0.2)
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
		"riveted":
			c = Color(0.3, 0.29, 0.28).lerp(Color(0.48, 0.46, 0.44), v)
			if x % 32 == 0 or y % 32 == 0: c = c.darkened(0.45)
			elif (x % 32 == 3 or x % 32 == 29) and y % 8 == 4: c = c.lightened(0.35)
			elif (y % 32 == 3 or y % 32 == 29) and x % 8 == 4: c = c.lightened(0.35)
			if v > 0.7: c = c.lerp(Color(0.45, 0.2, 0.08), (v - 0.7) * 2.5)
		"ceiling_tile":
			if x % 32 == 0 or y % 32 == 0: c = Color(0.35, 0.33, 0.3)
			else: c = Color(0.8, 0.76, 0.66).darkened(r * 0.12 + maxf(0.0, 0.35 - v) * 0.6)
		"grille":
			c = Color(0.1, 0.1, 0.1) if y % 4 < 2 else Color(0.42, 0.42, 0.4).lerp(Color(0.45, 0.22, 0.1), maxf(0.0, v - 0.6) * 2.0)
		"paper":
			c = Color(0.88, 0.85, 0.76).darkened(r * 0.1)
			if y % 6 == 3 and x > 6 and x < 58 and r > 0.3: c = Color(0.35, 0.35, 0.4)
		"plow":
			c = Color(0.85, 0.5, 0.15).lerp(Color(0.95, 0.65, 0.25), r * 0.3 + v * 0.4)
			if v < 0.3: c = Color(0.15, 0.08, 0.04).lerp(c, v * 3.0)
			if r < 0.05: c = c.darkened(0.6)
		"leaf":
			c = Color(0.08, 0.2, 0.06).lerp(Color(0.25, 0.42, 0.12), v * 0.6 + r * 0.4)
		"fabric":   # worn orange work suit: twill weave, seams, grime
			c = Color(0.55, 0.24, 0.07).lerp(Color(0.74, 0.36, 0.11), v * 0.7 + r * 0.3)
			if posmod(x + y, 3) == 0: c = c.darkened(0.08)
			if x % 32 == 0: c = c.darkened(0.4)
			if v < 0.32: c = c.lerp(Color(0.2, 0.14, 0.1), (0.32 - v) * 2.0)
		"fabric_tint":   # the same suit cloth undyed (tint it: crew looks)
			c = Color(0.6, 0.6, 0.59).lerp(Color(0.86, 0.86, 0.84), v * 0.7 + r * 0.3)
			if posmod(x + y, 3) == 0: c = c.darkened(0.08)
			if x % 32 == 0: c = c.darkened(0.4)
			if v < 0.32: c = c.lerp(Color(0.25, 0.22, 0.2), (0.32 - v) * 2.0)
		"leather":  # work glove: dark, scuffed, creased
			c = Color(0.16, 0.12, 0.09).lerp(Color(0.3, 0.23, 0.16), v * 0.8 + r * 0.2)
			if absf(v - 0.5) < 0.015: c = c.darkened(0.35)
		"plastic":  # scuffed moulded plastic (tint it)
			c = Color(0.72, 0.72, 0.7).lerp(Color(0.95, 0.95, 0.93), v * 0.6 + r * 0.15)
			if r < 0.01: c = c.darkened(0.2)
			if v < 0.25: c = c.darkened(0.06)
		"rubber":
			c = Color(0.07, 0.07, 0.075).lerp(Color(0.16, 0.16, 0.16), v * 0.8 + r * 0.2)
			if r < 0.04: c = c.lightened(0.12)
		"copper":   # tarnished copper with verdigris
			c = Color(0.42, 0.18, 0.07).lerp(Color(0.86, 0.5, 0.24), v * 0.7 + r * 0.3)
			if v > 0.7: c = c.lerp(Color(0.3, 0.55, 0.45), (v - 0.7) * 2.5)
		"brass":
			c = Color(0.42, 0.32, 0.1).lerp(Color(0.86, 0.7, 0.34), v * 0.7 + r * 0.3)
			if v < 0.28: c = c.darkened(0.3)
		"canvas":   # neutral woven cloth (tint it)
			c = Color(0.62, 0.6, 0.55).lerp(Color(0.8, 0.78, 0.72), v * 0.6 + r * 0.25)
			if posmod(x + y, 3) == 0: c = c.darkened(0.08)
			if v < 0.22: c = c.darkened(0.12)
		"pcb":
			c = Color(0.06, 0.28, 0.12).lerp(Color(0.1, 0.38, 0.16), v)
			if (y % 8 == 3 and x % 16 > 3) or (x % 12 == 5 and y % 16 > 6): c = Color(0.75, 0.55, 0.25)
		"keys":     # rows of keycaps
			c = Color(0.06, 0.06, 0.06) if x % 8 == 0 or y % 8 == 0 else Color(0.82, 0.8, 0.72).darkened(v * 0.25)
		"cardboard":   # kraft board: muted, faint corrugation, a little shelf grime
			c = Color(0.5, 0.42, 0.32).lerp(Color(0.6, 0.51, 0.39), v * 0.5 + r * 0.2)
			if y % 4 == 0: c = c.darkened(0.04)
			if v < 0.2: c = c.darkened(0.08)
		"maroon":   # old railway maroon, sun-faded, with some rust bloom
			c = Color(0.34, 0.09, 0.07).lerp(Color(0.47, 0.15, 0.11), v * 0.75 + r * 0.15)
			if v > 0.8: c = c.lerp(Color(0.42, 0.24, 0.12), (v - 0.8) * 3.0)
			if r < 0.025: c = c.darkened(0.25)
		"loco":     # faded safety-orange diesel livery, rust streaks
			c = Color(0.74, 0.43, 0.13).lerp(Color(0.88, 0.58, 0.2), v * 0.7 + r * 0.15)
			if v > 0.76: c = c.lerp(Color(0.38, 0.18, 0.08), (v - 0.76) * 2.6)
			if posmod(x, 11) == 4 and v > 0.55: c = c.darkened(0.18)
		"knurl":    # diamond-knurled grip
			c = Color(0.18, 0.18, 0.18) if (posmod(x + y, 4) < 2) != (posmod(x - y, 4) < 2) else Color(0.42, 0.42, 0.4)
		_:
			c = Color(0.5, 0.5, 0.5).lerp(Color(0.6, 0.6, 0.6), v)
	return c


## kind = texture; tile = metres per texture repeat. Tint multiplies the texture.
static func mat(kind: String, tint := Color.WHITE, tile := 2.0, emit := 0.0) -> StandardMaterial3D:
	# Snap tints so near-identical colours share a material (and merge into one draw in merge.gd).
	tint = Color(snappedf(tint.r, 0.08), snappedf(tint.g, 0.08), snappedf(tint.b, 0.08), tint.a)
	tile = snappedf(tile, 0.25) if tile > 0.3 else tile
	var k := "%s|%s|%s|%s" % [kind, tint.to_html(), tile, emit]
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture(kind)
	m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC   # no shimmer on stripes at grazing angles
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / tile
	m.roughness = 0.92
	if kind in ["metal", "rust", "grate", "corrugated", "copper", "brass"]:
		m.metallic = 0.35
		m.roughness = 0.65
	if kind == "grate":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # mipmaps blur the holes away and the grate vanishes at range
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = tint
		m.emission_energy_multiplier = emit
	elif _layer_kinds.size() < ARRAY_MAX or _layers.has(kind):
		# merge.gd draws every tint and tiling of every texture in one surface per chunk: the
		# texture as a layer of one array, its tiling and the tint carried by the vertices.
		m.set_meta("arr", Vector3(layer_of(kind), 1.0 / tile, 1.0 if kind == "grate" else 0.0))
		m.set_meta("vc_tint", tint)
	_mats[k] = m
	return m


# --- one material for everything merged -------------------------------------------------------------
# Every texture kind is a layer of one Texture2DArray; a shader does what mat()'s StandardMaterial3D
# does (triplanar, nearest filtering, the tint, roughness and metalness by kind) with the layer and
# the tiling read from UV2 and the tint from the vertex colour. So a merged chunk is one draw (two
# with see-through grating), whatever it's made of.
const ARRAY_MAX := 128
const METAL_KINDS := ["metal", "rust", "grate", "corrugated", "copper", "brass"]
static var _layers := {}
static var _layer_kinds: Array[String] = []
static var _arr_mats := {}
static var _arr_built := -1


static func layer_of(kind: String) -> int:
	if not _layers.has(kind):
		texture(kind)
		_layers[kind] = _layer_kinds.size()
		_layer_kinds.append(kind)
	return _layers[kind]


## The material merged surfaces draw with (scissor: grating, cut out and two-sided). Rebuilt when a
## texture has been added since; surfaces made earlier keep the one they got (it has their layers).
static func array_material(scissor: bool) -> ShaderMaterial:
	if _arr_built != _layer_kinds.size():
		_build_array()
	return _arr_mats[scissor]


static func _build_array() -> void:
	var imgs: Array[Image] = []
	var metal := PackedFloat32Array()
	var rough := PackedFloat32Array()
	metal.resize(ARRAY_MAX)
	rough.resize(ARRAY_MAX)
	for i in _layer_kinds.size():
		var kind: String = _layer_kinds[i]
		imgs.append(texture(kind).get_image())
		metal[i] = 0.35 if kind in METAL_KINDS else 0.0
		rough[i] = 0.65 if kind in METAL_KINDS else 0.92
	var arr := Texture2DArray.new()
	arr.create_from_images(imgs)
	for scissor in [false, true]:
		var key := "array_shader_%s" % scissor
		if not _mats.has(key):
			var sh := Shader.new()
			sh.code = ARRAY_SHADER.replace("CULL", "cull_disabled" if scissor else "cull_back").replace("//CUT", "" if scissor else "//")
			_mats[key] = sh
		var m := ShaderMaterial.new()
		m.shader = _mats[key]
		m.set_shader_parameter("tex", arr)
		m.set_shader_parameter("metal", metal)
		m.set_shader_parameter("rough", rough)
		_arr_mats[scissor] = m
	_arr_built = _layer_kinds.size()


const ARRAY_SHADER := """shader_type spatial;
render_mode blend_mix, depth_draw_opaque, CULL, diffuse_burley, specular_schlick_ggx;
uniform sampler2DArray tex : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform float metal[128];
uniform float rough[128];
varying vec3 tpos;
varying vec3 tw;
varying flat float layer;
void vertex() {
	layer = UV2.x;
	tw = abs(NORMAL);
	tw /= dot(tw, vec3(1.0));
	tpos = VERTEX * UV2.y * vec3(1.0, -1.0, 1.0);
	COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
}
void fragment() {
	vec4 s = texture(tex, vec3(tpos.xy, layer)) * tw.z + texture(tex, vec3(tpos.xz, layer)) * tw.y + texture(tex, vec3(tpos.zy * vec2(-1.0, 1.0), layer)) * tw.x;
	ALBEDO = s.rgb * COLOR.rgb;
	int i = int(layer + 0.5);
	METALLIC = metal[i];
	ROUGHNESS = rough[i];
	//CUT ALPHA = s.a;
	//CUT ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""


static func glass() -> StandardMaterial3D:
	if not _mats.has("glass"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.55, 0.6, 0.55, 0.22)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.1
		m.metallic = 0.3
		_mats["glass"] = m
	return _mats["glass"]


## Window glass that gets wet: when it rains (the "rain_amount" global, weather.gd) beads sit on it
## and drops run down, gathering others as they go. The train's windows.
static func rain_glass() -> ShaderMaterial:
	if not _mats.has("rain_glass"):
		if not Engine.has_meta("rain_amount"):   # (the global, made once; asking the server for its list is editor-only)
			RenderingServer.global_shader_parameter_add("rain_amount", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
			Engine.set_meta("rain_amount", true)
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
global uniform float rain_amount;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = vec2(wpos.x + wpos.z, wpos.y) * 26.0;
	float wet = 0.0;
	// Beads: one in some cells, a little off centre.
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float r = hash(cell);
	vec2 off = vec2(hash(cell + 1.3), hash(cell + 4.1)) - 0.5;
	float rad = 0.07 + 0.14 * hash(cell + 9.4);
	float bd = length(f - off * 0.6);
	float bead = step(0.74, r) * smoothstep(rad, rad * 0.6, bd);
	wet += bead * (0.35 + 0.65 * smoothstep(rad * 0.5, rad * 0.9, bd));   // (a bright rim, clearer in the middle)
	// Runs: in some columns a drop slides down, leaving a trail.
	float col = floor(p.x * 0.5);
	float hc = hash(vec2(col, 7.0));
	if (hc > 0.6) {
		float y = fract(p.y * 0.05 + TIME * (0.12 + hc * 0.25) + hc * 9.0);
		float x = fract(p.x * 0.5) - 0.5 + sin(p.y * 0.7 + hc * 20.0) * 0.08;
		float head = smoothstep(0.09, 0.02, length(vec2(x * 1.2, (y - 0.08) * 3.0)));
		float trail = smoothstep(0.05, 0.0, abs(x)) * smoothstep(0.08, 0.5, y) * 0.35;
		wet += head + trail;
	}
	wet = clamp(wet, 0.0, 1.0) * rain_amount;
	ALBEDO = mix(vec3(0.55, 0.6, 0.55), vec3(0.75, 0.8, 0.85), wet);
	ALPHA = 0.22 + wet * 0.3;
	ROUGHNESS = mix(0.1, 0.02, wet);
	METALLIC = 0.3;
	SPECULAR = 0.5 + wet * 0.5;
}"""
		var m := ShaderMaterial.new()
		m.shader = sh
		_mats["rain_glass"] = m
	return _mats["rain_glass"]


## A puddle: a decal that makes whatever floor it lies on dark, wet and mirror-smooth inside a ragged
## edge (so your flashlight and the lamps glint off it). Fits uneven ground: it's projected down.
static func puddle(parent: Node, pos: Vector3, size: float, turn: float) -> Decal:
	if not _mats.has("puddle"):
		var n := FastNoiseLite.new()
		n.frequency = 0.012
		n.fractal_octaves = 4
		var albedo := Image.create(256, 256, false, Image.FORMAT_RGBA8)
		var orm := Image.create(256, 256, false, Image.FORMAT_RGB8)
		for y in 256:
			for x in 256:
				var r := Vector2(x - 127.5, y - 127.5).length() / 128.0
				var m := clampf((n.get_noise_2d(x, y) * 0.9 + 0.75 - r) * 6.0, 0.0, 1.0)
				albedo.set_pixel(x, y, Color(0.09, 0.09, 0.1, m * 0.8))
				orm.set_pixel(x, y, Color(1.0, 0.04, 0.0))
		albedo.generate_mipmaps()
		orm.generate_mipmaps()
		_mats["puddle"] = [ImageTexture.create_from_image(albedo), ImageTexture.create_from_image(orm)]
	var d := Decal.new()
	d.texture_albedo = _mats["puddle"][0]
	d.texture_orm = _mats["puddle"][1]
	d.size = Vector3(size, 0.6, size * randf_range(0.6, 1.0))
	d.cull_mask = 1   # (the floor, not people's boots)
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	parent.add_child(d)
	d.global_position = pos
	d.rotation.y = turn
	return d


## A ring spreading on water (a drop landing, a foot wading, rain on a puddle): dark and glossy, so
## it only shows where light catches it. Frees itself.
static func ripple(parent: Node, pos: Vector3, size := 0.8, life := 1.1) -> void:
	if not _mats.has("ripple"):
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
instance uniform float age = 0.0;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float ring = smoothstep(0.1, 0.0, abs(r - age)) * (1.0 - age);
	float inner = smoothstep(0.08, 0.0, abs(r - age * 0.6)) * (1.0 - age) * 0.5;
	ALBEDO = vec3(0.03);
	ROUGHNESS = 0.02;
	SPECULAR = 1.0;
	NORMAL = normalize(NORMAL + vec3(UV.x - 0.5, 0.0, UV.y - 0.5) * (ring + inner) * 1.2);
	ALPHA = (ring + inner) * 0.45;
}"""
		var m := ShaderMaterial.new()
		m.shader = sh
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		q.orientation = PlaneMesh.FACE_Y
		_mats["ripple"] = [m, q]
	var mi := MeshInstance3D.new()
	mi.mesh = _mats["ripple"][1]
	mi.material_override = _mats["ripple"][0]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.012, 0)
	mi.scale = Vector3.ONE * size
	var tw := mi.create_tween()
	tw.tween_method(func(k: float): mi.set_instance_shader_parameter("age", k), 0.0, 1.0, life)
	tw.tween_callback(mi.queue_free)


## A flat panel (centred on the parent's origin, facing ±z) with a rectangular hole cut through it,
## built from four boxes, for doors you can actually see through.
static func panel_with_hole(parent: Node, size: Vector3, hole_c: Vector2, hole: Vector2, kind: String, tint: Color, tile := 1.0) -> void:
	var x0 := -size.x / 2.0
	var x1 := size.x / 2.0
	var y0 := -size.y / 2.0
	var y1 := size.y / 2.0
	var hx0 := hole_c.x - hole.x / 2.0
	var hx1 := hole_c.x + hole.x / 2.0
	var hy0 := hole_c.y - hole.y / 2.0
	var hy1 := hole_c.y + hole.y / 2.0
	for r in [[x0, x1, y0, hy0], [x0, x1, hy1, y1], [x0, hx0, hy0, hy1], [hx1, x1, hy0, hy1]]:
		if r[1] - r[0] > 0.001 and r[3] - r[2] > 0.001:
			box(parent, Vector3(r[1] - r[0], r[3] - r[2], size.z), Vector3((r[0] + r[1]) / 2.0, (r[2] + r[3]) / 2.0, 0), kind, tint, false, tile)


## A thin frame round a window opening, on both faces of a panel `thick` deep.
static func window_frame(parent: Node, c: Vector2, size: Vector2, thick: float, tint: Color) -> void:
	var t := 0.025
	for z in [-1.0, 1.0]:
		var zz: float = z * (thick / 2.0 + 0.004)
		box(parent, Vector3(size.x + 2 * t, t, 0.008), Vector3(c.x, c.y + size.y / 2.0 + t / 2.0, zz), "metal", tint, false)
		box(parent, Vector3(size.x + 2 * t, t, 0.008), Vector3(c.x, c.y - size.y / 2.0 - t / 2.0, zz), "metal", tint, false)
		box(parent, Vector3(t, size.y, 0.008), Vector3(c.x - size.x / 2.0 - t / 2.0, c.y, zz), "metal", tint, false)
		box(parent, Vector3(t, size.y, 0.008), Vector3(c.x + size.x / 2.0 + t / 2.0, c.y, zz), "metal", tint, false)


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


## Triangular prism: the triangle (base size.x, height size.y, apex in the middle) in the XY plane,
## extruded size.z along Z. For gable ends.
static func prism(parent: Node, size: Vector3, pos: Vector3, kind: String, tint := Color.WHITE, rot := Vector3.ZERO, tile := 2.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = mat(kind, tint, tile)
	parent.add_child(mi)
	mi.position = pos
	mi.rotation = rot
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


## Tapered cylinder from a (radius r0) to b (radius r1). Visual only.
static func seg(parent: Node, a: Vector3, b: Vector3, r0: float, r1: float, kind: String, tint := Color.WHITE, tile := 0.5) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.height = a.distance_to(b)
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat(kind, tint, tile)
	parent.add_child(mi)
	mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, (b - a).normalized())), (a + b) / 2.0)
	return mi


## Torus lying flat around y (rot stands it up). Visual only.
static func ring(parent: Node, outer: float, inner: float, pos: Vector3, kind: String, tint := Color.WHITE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.outer_radius = outer
	tm.inner_radius = inner
	tm.rings = 20
	tm.ring_segments = 6
	mi.mesh = tm
	mi.material_override = mat(kind, tint, 0.5)
	parent.add_child(mi)
	mi.position = pos
	mi.rotation = rot
	return mi


## A StaticBody (or plain node) placed and turned, with one box collider sitting on the floor.
static func root(parent: Node, pos: Vector3, rot_y: float, solid_size := Vector3.ZERO) -> Node3D:
	var r: Node3D = StaticBody3D.new() if solid_size != Vector3.ZERO else Node3D.new()
	parent.add_child(r)
	r.position = pos
	r.rotation.y = rot_y
	if solid_size != Vector3.ZERO:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = solid_size
		cs.shape = sh
		cs.position.y = solid_size.y / 2
		r.add_child(cs)
	return r


# --- animation helpers -------------------------------------------------------------

static func spin(node: Node3D, axis: String, secs: float) -> void:
	node.set_meta("live", true)
	var tw := node.create_tween().set_loops()
	tw.tween_property(node, "rotation:" + axis, TAU * signf(secs), absf(secs)).as_relative()


static func sway(node: Node3D, amount: float, secs: float) -> void:
	node.set_meta("live", true)
	var tw := node.create_tween().set_loops()
	tw.tween_property(node, "rotation:z", amount, secs).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "rotation:z", -amount, secs).set_trans(Tween.TRANS_SINE)


static func bob(node: Node3D, amount: float, secs: float) -> void:
	node.set_meta("live", true)
	var tw := node.create_tween().set_loops()
	tw.tween_property(node, "position:y", amount, secs).as_relative().set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "position:y", -amount, secs).as_relative().set_trans(Tween.TRANS_SINE)


# --- props ---------------------------------------------------------------------------

static func barrel(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var tints := [Color(0.45, 0.55, 0.7), Color(0.75, 0.35, 0.25), Color(0.5, 0.6, 0.35), Color(0.8, 0.7, 0.4), Color(0.35, 0.35, 0.38)]
	var t: Color = tints[rng.randi() % tints.size()]
	var r := Node3D.new()
	parent.add_child(r)
	r.position = pos
	r.rotation.y = rng.randf() * TAU
	cyl(r, 0.31, 0.88, Vector3(0, 0.44, 0), "rust", t, true)
	for y in [0.3, 0.6]:   # rolling hoops
		ring(r, 0.325, 0.3, Vector3(0, y, 0), "rust", t.darkened(0.15))
	for y in [0.015, 0.875]:   # rims
		ring(r, 0.315, 0.29, Vector3(0, y, 0), "metal", Color(0.55, 0.55, 0.55))
	cyl(r, 0.295, 0.01, Vector3(0, 0.888, 0), "rust", t.darkened(0.3))   # lid, clear of the body's top face
	for b in [Vector2(0.17, 0.05), Vector2(-0.15, -0.08)]:   # bungs
		cyl(r, 0.035 if b.x > 0 else 0.022, 0.018, Vector3(b.x, 0.899, b.y), "metal", Color(0.45, 0.45, 0.45))
	if rng.randf() < 0.45:
		cyl(r, 0.312, 0.16, Vector3(0, 0.45, 0), "hazard" if rng.randf() < 0.5 else "paper", Color.WHITE, false, "y")
	if rng.randf() < 0.3:   # spill down the side
		box(r, Vector3(0.06, rng.randf_range(0.15, 0.5), 0.01), Vector3(0, 0.7, 0.312), "dirt", Color(0.2, 0.15, 0.1), false, 0.3)


static func crate(parent: Node, pos: Vector3, s: float, rng: RandomNumberGenerator, solid := true) -> void:
	var r := root(parent, pos, rng.randf_range(-0.25, 0.25), Vector3(s, s, s) if solid else Vector3.ZERO)
	var tint := Color.WHITE.darkened(rng.randf() * 0.3)
	box(r, Vector3(s * 0.96, s * 0.96, s * 0.96), Vector3(0, s / 2, 0), "wood", tint, false, 1.0)
	var e := s * 0.08
	var frame := tint.darkened(0.25)
	for a in [-1, 1]:
		for b in [-1, 1]:
			box(r, Vector3(e, s, e), Vector3(a * (s - e) / 2, s / 2, b * (s - e) / 2), "wood", frame, false, 1.0)
			box(r, Vector3(s, e, e), Vector3(0, s / 2 + a * (s - e) / 2, b * (s - e) / 2), "wood", frame, false, 1.0)
			box(r, Vector3(e, e, s), Vector3(a * (s - e) / 2, s / 2 + b * (s - e) / 2, 0), "wood", frame, false, 1.0)
	for f in [-1, 1]:   # diagonal braces on two faces
		var d := box(r, Vector3(e * 0.9, s * 1.25, e * 0.5), Vector3(0, s / 2, f * (s / 2 + e * 0.1)), "wood", frame, false, 1.0)
		d.rotation.z = PI / 4 * f
	if rng.randf() < 0.35:
		var words := ["FRAGILE", "THIS SIDE UP", "B.R.M.", "PARTS", "DO NOT STACK"]
		var paint := B.label(r, words[rng.randi() % words.size()], Vector3(0, s * 0.62, s / 2 + e * 0.6), 40, Color(0.12, 0.1, 0.08), "stencil", s * 0.004)
		paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func pallet(parent: Node, pos: Vector3) -> void:
	for i in 5:
		box(parent, Vector3(1.2, 0.03, 0.16), pos + Vector3(0, 0.13, -0.5 + i * 0.25), "wood", Color.WHITE, false, 1.0)
	for i in 3:
		box(parent, Vector3(1.2, 0.1, 0.1), pos + Vector3(0, 0.06, -0.45 + i * 0.45), "wood", Color(0.7, 0.7, 0.7), false, 1.0)


## Metal rack with junk on it: boxes, binders, paint tins, jars. One collision box for the unit.
static func shelf_unit(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator, w := 2.0, h := 2.2, d := 0.5) -> void:
	var r := root(parent, pos, rot_y, Vector3(w, h, d))
	r.collision_layer = 16   # solid to bodies, but you (and anything else) can see through the shelving
	var steel := Color(0.55, 0.6, 0.62) if rng.randf() < 0.5 else Color(0.7, 0.55, 0.3)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var x: float = sx * (w / 2 - 0.03)
			var z: float = sz * (d / 2 - 0.03)
			box(r, Vector3(0.05, h, 0.012), Vector3(x, h / 2, z - sz * 0.02), "metal", steel, false, 0.5)   # angle iron
			box(r, Vector3(0.012, h, 0.05), Vector3(x - sx * 0.02, h / 2, z), "metal", steel, false, 0.5)
			box(r, Vector3(0.08, 0.01, 0.08), Vector3(x, 0.005, z), "metal", steel.darkened(0.3), false)
	var levels := 4
	for i in levels:
		var y := 0.15 + i * (h - 0.25) / (levels - 1)
		box(r, Vector3(w, 0.025, d), Vector3(0, y, 0), "metal", steel.lightened(0.15), false, 0.8)
		box(r, Vector3(w, 0.05, 0.015), Vector3(0, y + 0.012, -d / 2), "metal", steel, false, 0.5)   # front lip
		if i == levels - 1:
			break
		var top := (h - 0.25) / (levels - 1) - 0.06
		var x := -w / 2 + 0.1
		while x < w / 2 - 0.15:
			var roll := rng.randf()
			if roll < 0.35:   # cardboard box, flaps taped
				var s := Vector3(rng.randf_range(0.22, 0.45), rng.randf_range(0.16, minf(0.38, top)), rng.randf_range(0.22, d - 0.06))
				if x + s.x > w / 2 - 0.05:
					break
				var bx := box(r, s, Vector3(x + s.x / 2, y + 0.013 + s.y / 2, 0), "cardboard", Color.WHITE.darkened(rng.randf() * 0.25), false, 0.6, Vector3(0, rng.randf_range(-0.12, 0.12), 0))
				box(bx, Vector3(s.x * 1.01, 0.004, 0.05), Vector3(0, s.y / 2, 0), "plastic", Color(0.75, 0.65, 0.45), false, 0.3)
				x += s.x + 0.04
			elif roll < 0.55:   # row of binders, one leaning
				var n := rng.randi_range(3, 7)
				var col: Color = [Color(0.2, 0.24, 0.36), Color(0.38, 0.14, 0.12), Color(0.2, 0.3, 0.22), Color(0.22, 0.22, 0.22), Color(0.55, 0.45, 0.22)][rng.randi() % 5]
				for k in n:
					var bn := box(r, Vector3(0.05, 0.3, 0.26), Vector3(x + 0.03 + k * 0.055, y + 0.165, -d / 2 + 0.16), "plastic", col.darkened(rng.randf() * 0.2), false, 0.3)
					box(bn, Vector3(0.058, 0.07, 0.05), Vector3(0, 0.06, -0.113), "paper", Color(0.9, 0.88, 0.8), false, 0.3)
					if k == n - 1 and rng.randf() < 0.6:
						bn.rotation.z = -0.35
						bn.position.x += 0.06
				x += n * 0.055 + 0.12
			elif roll < 0.72:   # paint tins
				for k in rng.randi_range(1, 3):
					var c: Color = [Color(0.75, 0.68, 0.5), Color(0.42, 0.5, 0.58), Color(0.55, 0.3, 0.22), Color(0.4, 0.45, 0.32)][rng.randi() % 4]
					cyl(r, 0.08, 0.17, Vector3(x + 0.09, y + 0.1, -0.05 + k * 0.0), "metal", Color(0.7, 0.7, 0.7))
					cyl(r, 0.081, 0.1, Vector3(x + 0.09, y + 0.09, -0.05), "paper", c)
					ring(r, 0.08, 0.072, Vector3(x + 0.09, y + 0.185, -0.05), "metal", Color(0.6, 0.6, 0.6))
					x += 0.19
			elif roll < 0.85:   # jars of something
				for k in rng.randi_range(2, 4):
					var c: Color = [Color(0.6, 0.48, 0.25), Color(0.4, 0.45, 0.32), Color(0.45, 0.22, 0.16), Color(0.75, 0.73, 0.64)][rng.randi() % 4]
					cyl(r, 0.04, 0.09, Vector3(x + 0.05, y + 0.06, 0.05), "cream", c)
					var jar = cyl(r, 0.045, 0.14, Vector3(x + 0.05, y + 0.083, 0.05), "metal")
					jar.material_override = glass()
					cyl(r, 0.047, 0.025, Vector3(x + 0.05, y + 0.165, 0.05), "metal", Color(0.75, 0.7, 0.4))
					x += 0.11
			else:
				x += 0.2


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
	var bulb := sphere(parent, 0.09, pos + normal * 0.1, "cream", c, 4.0)
	for i in 3:
		var bar := Vector3(0.02, 0.2, 0.02)
		var off := normal * 0.16 + (Vector3(0, 0, (i - 1) * 0.08) if absf(normal.x) > 0.5 else Vector3((i - 1) * 0.08, 0, 0))
		box(parent, bar, pos + off, "metal", Color(0.4, 0.4, 0.4), false)
	return bind_glow(B.omni(parent, pos + normal * 0.4, c, energy, 9.0, shadow), [bulb])


## Ties the glowing part of a fitting to its light, so when the light flickers or dies the bulb does too.
static func bind_glow(l: Light3D, meshes: Array) -> Light3D:
	for m in meshes:
		m.set_meta("live", true)   # kept out of the merge: it changes
	l.set_meta("glow", meshes)
	return l


## Lamp hanging from the ceiling on a cord; it sways.
## Industrial pendant: ceiling canopy, cable, enamelled cone shade with a pale reflector inside,
## a pear bulb just showing under the rim and a wire guard around it. Sways a little.
static func hanging_lamp(parent: Node, ceiling: Vector3, c: Color, drop := 1.0, energy := 1.4, shadow := true) -> OmniLight3D:
	var pivot := Node3D.new()
	parent.add_child(pivot)
	pivot.position = ceiling
	cyl(parent, 0.07, 0.04, ceiling + Vector3(0, -0.02, 0), "metal", Color(0.3, 0.3, 0.3), false)   # canopy (doesn't sway)
	box(pivot, Vector3(0.012, drop, 0.012), Vector3(0, -drop / 2, 0), "rubber", Color(0.08, 0.08, 0.08), false)
	var y := -drop
	cyl(pivot, 0.035, 0.08, Vector3(0, y - 0.03, 0), "metal", Color(0.25, 0.25, 0.25), false)   # lamp holder
	var enamel := Color(0.22, 0.32, 0.26)
	cyl(pivot, 0.3, 0.2, Vector3(0, y - 0.16, 0), "paint", enamel, false, "y", 0.06)              # shade, outside
	var refl := cyl(pivot, 0.285, 0.185, Vector3(0, y - 0.17, 0), "cream", c.lerp(Color.WHITE, 0.6), false, "y", 0.05)   # reflector, lit
	refl.material_override = mat("cream", c.lerp(Color.WHITE, 0.6), 1.0, 0.7)
	ring(pivot, 0.305, 0.285, Vector3(0, y - 0.26, 0), "metal", enamel.darkened(0.4))             # rolled rim
	var bulb := sphere(pivot, 0.06, Vector3(0, y - 0.25, 0), "cream", c.lerp(Color.WHITE, 0.4), 6.0, 1.35)    # pear bulb
	for k in 4:   # wire guard
		var a := TAU * k / 4.0
		seg(pivot, Vector3(cos(a) * 0.29, y - 0.26, sin(a) * 0.29), Vector3(cos(a) * 0.09, y - 0.36, sin(a) * 0.09), 0.006, 0.006, "metal", Color(0.2, 0.2, 0.2))
	ring(pivot, 0.1, 0.09, Vector3(0, y - 0.36, 0), "metal", Color(0.2, 0.2, 0.2))
	var l := B.omni(pivot, Vector3(0, y - 0.32, 0), c, energy, 10.0, shadow)
	sway(pivot, 0.05, 1.8 + randf())
	return bind_glow(l, [bulb, refl])


static func fluorescent(parent: Node, pos: Vector3, c: Color, energy := 1.0) -> OmniLight3D:
	box(parent, Vector3(1.3, 0.06, 0.25), pos, "metal", Color(0.6, 0.6, 0.6), false)
	var tube := glow(parent, Vector3(1.2, 0.03, 0.15), pos + Vector3(0, -0.04, 0), c, 3.0)
	return bind_glow(B.omni(parent, pos + Vector3(0, -0.3, 0), c, energy, 10.0, false), [tube])


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
	B.fade(s)
	root.add_child(s)
	s.position = Vector3(0, 2.05, -0.15)
	s.rotation.x = -0.3


## Vines hanging from the ceiling: wavy segmented stems with leaves, some ending in a curl.
static func vines(parent: Node, pos: Vector3, length: float, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(3, 7):
		var l := rng.randf_range(0.6, length)
		var p := pos + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
		var n := int(l / 0.25)
		var phase := rng.randf() * TAU
		var leaf := Color(0.75, 0.9, 0.6).darkened(rng.randf() * 0.3)
		for j in n:
			var q := p + Vector3(sin(phase + j * 0.7) * 0.08, -0.25, cos(phase + j * 0.5) * 0.08)
			seg(parent, p, q, 0.022 - j * 0.0012, 0.02 - j * 0.0012, "leaf", Color(0.6, 0.65, 0.45))
			if rng.randf() < 0.6:
				var lf := box(parent, Vector3(0.12, 0.012, 0.07), q + Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05)), "leaf", leaf, false, 0.3,
					Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU, rng.randf_range(0.2, 0.7)))
				lf.scale = Vector3.ONE * rng.randf_range(0.7, 1.3)
			p = q


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
	var r := root(parent, pos, rot_y, Vector3(1.6, 0.8, 0.8))
	var body := Color(0.55, 0.58, 0.52) if rng.randf() < 0.6 else Color(0.62, 0.55, 0.45)
	box(r, Vector3(1.6, 0.035, 0.8), Vector3(0, 0.77, 0), "wood", Color(0.85, 0.78, 0.65), false, 1.0)   # laminate top
	box(r, Vector3(1.62, 0.025, 0.82), Vector3(0, 0.745, 0), "metal", body.darkened(0.3), false)
	box(r, Vector3(0.45, 0.72, 0.74), Vector3(-0.56, 0.37, 0), "metal", body, false, 0.8)            # drawer pedestal
	for i in 3:
		var y := 0.6 - i * 0.22
		box(r, Vector3(0.41, 0.19, 0.015), Vector3(-0.56, y, -0.375), "metal", body.lightened(0.08), false, 0.5)
		seg(r, Vector3(-0.63, y + 0.05, -0.39), Vector3(-0.49, y + 0.05, -0.39), 0.008, 0.008, "metal", Color(0.75, 0.75, 0.72))
		box(r, Vector3(0.06, 0.025, 0.004), Vector3(-0.56, y - 0.02, -0.384), "paper", Color(0.9, 0.88, 0.8), false, 0.2)
	box(r, Vector3(0.04, 0.72, 0.74), Vector3(0.76, 0.37, 0), "metal", body, false, 0.8)
	box(r, Vector3(1.1, 0.4, 0.02), Vector3(0.18, 0.5, 0.36), "metal", body.darkened(0.1), false, 0.8)    # modesty panel
	if rng.randf() < 0.7:
		crt(r, Vector3(rng.randf_range(-0.15, 0.25), 0.79, 0.12), rng.randf() < 0.4)
	else:   # desk lamp
		var lx := rng.randf_range(0.3, 0.6)
		cyl(r, 0.08, 0.02, Vector3(lx, 0.8, 0.2), "metal", Color(0.2, 0.3, 0.25))
		seg(r, Vector3(lx, 0.8, 0.2), Vector3(lx + 0.05, 1.1, 0.15), 0.01, 0.01, "metal", Color(0.2, 0.3, 0.25))
		seg(r, Vector3(lx + 0.05, 1.1, 0.15), Vector3(lx - 0.1, 1.15, -0.02), 0.01, 0.01, "metal", Color(0.2, 0.3, 0.25))
		cyl(r, 0.09, 0.12, Vector3(lx - 0.12, 1.08, -0.04), "metal", Color(0.2, 0.3, 0.25), false, "y", 0.04)
	box(r, Vector3(0.45, 0.025, 0.16), Vector3(0.05, 0.8, -0.25), "keys", Color.WHITE, false, 0.45)
	box(r, Vector3(0.46, 0.015, 0.17), Vector3(0.05, 0.793, -0.25), "plastic", Color(0.85, 0.82, 0.72), false, 0.3)
	box(r, Vector3(0.06, 0.03, 0.1), Vector3(0.38, 0.8, -0.25), "plastic", Color(0.85, 0.82, 0.72), false, 0.3)
	if rng.randf() < 0.6:   # mug
		var mx := rng.randf_range(-0.7, -0.4)
		cyl(r, 0.04, 0.1, Vector3(mx, 0.84, -0.15), "plastic", Color.from_hsv(rng.randf(), 0.3, 0.9))
		ring(r, 0.025, 0.016, Vector3(mx + 0.045, 0.84, -0.15), "plastic", Color(0.9, 0.9, 0.9), Vector3(PI / 2, 0, 0))
	for i in rng.randi_range(0, 4):
		box(r, Vector3(0.21, 0.004, 0.29), Vector3(rng.randf_range(-0.7, 0.7), 0.79 + i * 0.005, rng.randf_range(-0.3, 0.3)), "paper", Color.WHITE.darkened(rng.randf() * 0.25), false, 0.3, Vector3(0, rng.randf() * TAU, 0))


## Cream retro CRT with a keyboard-less front: bezel, curved-looking screen, vents, power LED. Returns the screen.
static func crt(parent: Node, pos: Vector3, on := false, screen_color := Color(1.0, 0.6, 0.2)) -> Node3D:
	var cr := Color(0.8, 0.78, 0.71)   # aged beige plastic
	var dk := cr.darkened(0.12)
	# Front bezel: a frame round the glass, thicker below for the controls, chamfered at the edge.
	box(parent, Vector3(0.5, 0.035, 0.07), pos + Vector3(0, 0.425, -0.205), "plastic", cr, false, 0.4)
	box(parent, Vector3(0.5, 0.075, 0.07), pos + Vector3(0, 0.07, -0.205), "plastic", cr, false, 0.4)
	for sx in [-1, 1]:
		box(parent, Vector3(0.05, 0.32, 0.07), pos + Vector3(sx * 0.225, 0.25, -0.205), "plastic", cr, false, 0.4)
	for sx in [-1, 1]:   # the glass sits back in a dark inner bevel
		box(parent, Vector3(0.014, 0.31, 0.03), pos + Vector3(sx * 0.198, 0.25, -0.225), "plastic", Color(0.18, 0.18, 0.17), false, 0.3)
	for sy in [-1, 1]:
		box(parent, Vector3(0.41, 0.014, 0.03), pos + Vector3(0, 0.25 + sy * 0.153, -0.225), "plastic", Color(0.18, 0.18, 0.17), false, 0.3)
	# The tube's housing, tapering back.
	box(parent, Vector3(0.48, 0.4, 0.14), pos + Vector3(0, 0.25, -0.1), "plastic", dk, false, 0.4)
	box(parent, Vector3(0.4, 0.33, 0.14), pos + Vector3(0, 0.24, 0.04), "plastic", dk.darkened(0.04), false, 0.4)
	box(parent, Vector3(0.28, 0.24, 0.12), pos + Vector3(0, 0.22, 0.17), "plastic", dk.darkened(0.08), false, 0.4)
	for i in 6:   # vents on top
		box(parent, Vector3(0.3, 0.004, 0.012), pos + Vector3(0, 0.452, -0.12 + i * 0.022), "plastic", Color(0.15, 0.15, 0.14), false, 0.2)
	var screen := glow(parent, Vector3(0.38, 0.29, 0.02), pos + Vector3(0, 0.25, -0.24), screen_color if on else Color(0.05, 0.06, 0.05), 1.5 if on else 0.2)
	# Controls on the chin: brightness and contrast knobs, the power button and its lamp, a badge.
	for k in 2:
		cyl(parent, 0.011, 0.012, pos + Vector3(0.1 + k * 0.035, 0.065, -0.243), "plastic", Color(0.22, 0.22, 0.21), false, "z")
	box(parent, Vector3(0.03, 0.018, 0.01), pos + Vector3(0.19, 0.065, -0.243), "plastic", Color(0.3, 0.3, 0.28), false, 0.2)
	sphere(parent, 0.006, pos + Vector3(0.19, 0.083, -0.241), "cream", Color(0.3, 1, 0.3) if on else Color(0.2, 0.2, 0.2), 4.0 if on else 0.0)
	box(parent, Vector3(0.07, 0.016, 0.003), pos + Vector3(-0.15, 0.065, -0.242), "metal", Color(0.7, 0.7, 0.68), false, 0.2)
	# On a tilt-and-swivel foot.
	box(parent, Vector3(0.14, 0.04, 0.12), pos + Vector3(0, 0.03, -0.03), "plastic", dk, false, 0.3)
	box(parent, Vector3(0.3, 0.018, 0.24), pos + Vector3(0, 0.009, -0.03), "plastic", dk.darkened(0.05), false, 0.3)
	return screen


static func locker(parent: Node, pos: Vector3, rot_y: float, tint := Color(0.5, 0.56, 0.6)) -> void:
	var r := root(parent, pos, rot_y, Vector3(0.6, 1.9, 0.5))
	box(r, Vector3(0.6, 1.85, 0.02), Vector3(0, 0.975, 0.24), "enamel", tint, false, 1.0)
	for s in [-1, 1]:
		box(r, Vector3(0.02, 1.85, 0.5), Vector3(s * 0.29, 0.975, 0), "enamel", tint, false, 1.0)
	box(r, Vector3(0.6, 0.02, 0.5), Vector3(0, 1.89, 0), "enamel", tint.darkened(0.1), false, 1.0)
	box(r, Vector3(0.6, 0.06, 0.5), Vector3(0, 0.03, 0), "enamel", tint.darkened(0.4), false, 1.0)
	box(r, Vector3(0.56, 1.8, 0.46), Vector3(0, 0.96, 0.0), "metal", Color(0.12, 0.12, 0.12), false, 1.0)   # dark inside
	box(r, Vector3(0.56, 0.02, 0.44), Vector3(0, 1.55, 0.0), "enamel", tint.darkened(0.2), false, 1.0)       # hat shelf
	var door := Node3D.new()   # hinged on the left; some hang open
	r.add_child(door)
	door.position = Vector3(-0.28, 0, -0.25)
	if randf() < 0.25:
		door.rotation.y = randf_range(0.6, 1.6)
		box(r, Vector3(0.3, 0.7, 0.1), Vector3(0.0, 1.1, 0.05), "canvas", [Color(0.3, 0.32, 0.4), Color(0.4, 0.3, 0.25), Color(0.32, 0.36, 0.3)][randi() % 3], false, 0.5)   # jacket on a hook
	box(door, Vector3(0.56, 1.8, 0.02), Vector3(0.28, 0.96, 0), "enamel", tint.lightened(0.05), false, 1.0)
	for i in 5:
		for y0 in [1.6, 0.3]:
			box(door, Vector3(0.3, 0.012, 0.012), Vector3(0.28, y0 + i * 0.04, -0.012), "metal", Color(0.08, 0.08, 0.08), false, 0.2)
	box(door, Vector3(0.025, 0.14, 0.03), Vector3(0.5, 1.0, -0.02), "metal", Color(0.75, 0.75, 0.72), false, 0.2)
	box(door, Vector3(0.08, 0.04, 0.004), Vector3(0.28, 1.35, -0.012), "brass", Color.WHITE, false, 0.2)


static func blob(parent: Node, pos: Vector3, radius: float, rng: RandomNumberGenerator) -> void:
	var b := sphere(parent, radius, pos, "flesh", Color(1, 0.85, 0.85), 0.15, rng.randf_range(0.5, 1.0))
	b.rotation.y = rng.randf() * TAU
	b.set_meta("live", true)
	var tw := b.create_tween().set_loops()
	tw.tween_property(b, "scale", Vector3.ONE * 1.06, rng.randf_range(0.8, 1.6)).set_trans(Tween.TRANS_SINE)
	tw.tween_property(b, "scale", Vector3.ONE, rng.randf_range(0.8, 1.6)).set_trans(Tween.TRANS_SINE)


## Railing from a to b (horizontal). Top rail is solid so you can't walk off.
const BARRIER := 16   # collision layer for walk-blockers you can see and hear through (railing panels)


static func railing(parent: Node, a: Vector3, b: Vector3, h := 1.0, kind := "rust", solid := false) -> void:
	var d := b - a
	var n := maxi(1, int(d.length() / 1.4))
	for i in n + 1:
		box(parent, Vector3(0.05, h, 0.05), a + d * (float(i) / n) + Vector3(0, h / 2, 0), kind, Color.WHITE, false, 1.0)
	var along_x := absf(d.x) > absf(d.z)
	for y in [h, h * 0.5]:
		var size := Vector3(d.length(), 0.05, 0.05) if along_x else Vector3(0.05, 0.05, d.length())
		box(parent, size, (a + b) / 2.0 + Vector3(0, y, 0), kind, Color.WHITE, false, 1.0)
	if solid:   # one invisible panel, floor to rail: nothing walks under or through it (and the navmesh sees it).
		var body := StaticBody3D.new()   # On its own layer (BARRIER): it stops bodies, not sight or sound.
		body.collision_layer = BARRIER
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(d.length(), h, 0.12) if along_x else Vector3(0.12, h, d.length())
		cs.shape = sh
		body.add_child(cs)
		parent.add_child(body)
		body.position = (a + b) / 2.0 + Vector3(0, h / 2.0, 0)


## Snow on top of something: a soft, slightly lumpy white layer.
static func snow_cap(parent: Node, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> Node3D:
	return box(parent, size, pos, "snow", Color(1.0, 1.0, 1.0), false, 1.5, rot)


## Spruce: a straight trunk and stacked, drooping tiers of needles, each loaded with snow. Some lean,
## some are dead and bare, a few are snapped off.
static func pine(parent: Node, pos: Vector3, rng: RandomNumberGenerator, snowy := true) -> void:
	var h := rng.randf_range(6.0, 11.0)
	var r := Node3D.new()
	parent.add_child(r)
	r.position = pos
	r.rotation = Vector3(rng.randf_range(-0.04, 0.04), rng.randf() * TAU, rng.randf_range(-0.04, 0.04))
	var bark := Color(0.38, 0.3, 0.25)
	var roll := rng.randf()
	if roll < 0.12:   # snapped: a jagged stump and the top lying beside it
		var sh := rng.randf_range(1.5, 3.0)
		cyl(r, 0.28, sh, Vector3(0, sh / 2.0, 0), "wood", bark, true, "y", 0.2)
		var fallen := cyl(r, 0.2, h * 0.6, Vector3(h * 0.3, 0.25, 0.4), "wood", bark, false, "x", 0.05)
		fallen.rotation.y = rng.randf_range(-0.4, 0.4)
		if snowy:
			snow_cap(r, Vector3(h * 0.55, 0.08, 0.3), Vector3(h * 0.3, 0.47, 0.4), Vector3(0, fallen.rotation.y, 0))
		return
	cyl(r, 0.24, h, Vector3(0, h / 2.0, 0), "wood", bark, true, "y", 0.08)
	if roll < 0.25:   # dead: bare, short broken branches
		for i in rng.randi_range(6, 12):
			var l := rng.randf_range(0.5, 1.6)
			var br := cyl(r, 0.05, l, Vector3.ZERO, "wood", bark, false, "y", 0.02)
			br.rotation = Vector3(0, rng.randf() * TAU, rng.randf_range(1.2, 1.7))
			br.position = Vector3(0, rng.randf_range(h * 0.3, h * 0.95), 0) + br.basis.y * (l / 2.0)
		return
	var needles := Color(0.16, 0.26, 0.18).darkened(rng.randf() * 0.2)
	var tiers := rng.randi_range(5, 7)
	for t in tiers:
		var f := float(t) / tiers
		var rad := lerpf(2.2, 0.5, f) * rng.randf_range(0.9, 1.1)
		var y := lerpf(h * 0.22, h * 0.86, f)
		var th := lerpf(2.0, 1.2, f)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = rad
		cm.top_radius = 0.05
		cm.height = th
		cm.radial_segments = 8
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = mat("leaf", needles, 1.0)
		r.add_child(mi)
		mi.position = Vector3(0, y + th / 2.0, 0)
		if snowy:   # snow lying on the upper side of each tier
			var sm := MeshInstance3D.new()
			var sc := CylinderMesh.new()
			sc.bottom_radius = rad * 0.82
			sc.top_radius = 0.04
			sc.height = th * 0.62
			sc.radial_segments = 8
			sc.rings = 1
			sm.mesh = sc
			sm.material_override = mat("snow", Color.WHITE, 1.0)
			r.add_child(sm)
			sm.position = Vector3(0, y + th * 0.42 + th * 0.31, 0)
			sm.rotation.y = 0.4
	cyl(r, 0.04, 1.0, Vector3(0, h * 0.86 + 1.4, 0), "wood", bark, false, "y", 0.01)


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
	cyl(parent, 0.13, 7.0, pos + Vector3(0, 3.5, 0), "wood", Color(0.6, 0.55, 0.5), true, "y", 0.1)
	for y in [6.5, 5.9]:
		box(parent, Vector3(0.1, 0.1, 1.6 if y > 6 else 1.1), pos + Vector3(0, y, 0), "wood", Color(0.55, 0.5, 0.45), false, 1.0)
		for z in ([-0.7, -0.35, 0.35, 0.7] if y > 6 else [-0.45, 0.45]):
			cyl(parent, 0.035, 0.12, pos + Vector3(0, y + 0.1, z), "cream", Color(0.45, 0.6, 0.55))
	seg(parent, pos + Vector3(0, 6.45, -0.6), pos + Vector3(0, 5.95, -0.08), 0.02, 0.02, "metal", Color(0.4, 0.4, 0.4))
	cyl(parent, 0.18, 0.5, pos + Vector3(0.22, 5.2, 0), "metal", Color(0.5, 0.52, 0.5))   # transformer can


static func lamp_post(parent: Node, pos: Vector3, c: Color) -> OmniLight3D:
	cyl(parent, 0.22, 0.25, pos + Vector3(0, 0.12, 0), "concrete", Color(0.7, 0.68, 0.65), true)
	cyl(parent, 0.08, 3.6, pos + Vector3(0, 1.9, 0), "metal", Color(0.3, 0.32, 0.3), true, "y", 0.05)
	seg(parent, pos + Vector3(0, 3.6, 0), pos + Vector3(0.25, 3.78, 0), 0.04, 0.035, "metal", Color(0.3, 0.32, 0.3))
	seg(parent, pos + Vector3(0.25, 3.78, 0), pos + Vector3(0.6, 3.72, 0), 0.035, 0.03, "metal", Color(0.3, 0.32, 0.3))
	box(parent, Vector3(0.5, 0.1, 0.24), pos + Vector3(0.75, 3.68, 0), "metal", Color(0.35, 0.37, 0.35), false, 0.5)
	glow(parent, Vector3(0.4, 0.02, 0.18), pos + Vector3(0.77, 3.62, 0), c, 5.0)
	box(parent, Vector3(0.2, 0.3, 0.12), pos + Vector3(0, 1.0, -0.1), "metal", Color(0.4, 0.42, 0.4), false, 0.5)   # access box
	return B.omni(parent, pos + Vector3(0.75, 3.35, 0), c, 1.6, 12.0, false)


## Two-storey wooden building, hollow with a door, a porch and a balcony. Faces -z.
## Returns a point inside (for loot).
static func wood_house(parent: Node, pos: Vector3, rot_y: float, rng: RandomNumberGenerator, back_door := false) -> Vector3:
	var root := Node3D.new()
	parent.add_child(root)
	root.position = pos
	root.rotation.y = rot_y
	var w := rng.randf_range(7.0, 10.0)
	var d := rng.randf_range(6.0, 8.0)
	# Which kind of house: weathered planks, painted clapboard, a brick block with a flat roof, or a
	# tin shack with a lean-to roof. One or two storeys.
	var style: String = ["wood", "siding", "siding", "brick", "shack"][rng.randi() % 5]
	var storeys := 1 if style == "shack" or rng.randf() < 0.4 else 2
	var h := 3.2 * storeys
	var kind: String = {"wood": "wood", "siding": "siding", "brick": "brick", "shack": "corrugated"}[style]
	var paints := [Color(0.62, 0.72, 0.78), Color(0.8, 0.55, 0.48), Color(0.7, 0.76, 0.6), Color(0.92, 0.86, 0.7), Color(0.85, 0.85, 0.82), Color(0.6, 0.62, 0.7)]
	var tint: Color = paints[rng.randi() % paints.size()] if style == "siding" else (Color(0.8, 0.62, 0.5) if style == "shack" else Color.WHITE.darkened(rng.randf() * 0.25))
	var trim := Color(0.85, 0.82, 0.75).darkened(rng.randf() * 0.3)
	if style == "brick":
		trim = Color(0.75, 0.72, 0.66)
	var door := [[0.0, 1.4, 0.0, 2.3]]
	var win1 := [[-w / 3, 1.0, 1.0, 2.2], [w / 3, 1.0, 1.0, 2.2]]
	var win2 := [[-w / 3, 1.0, 4.0, 5.2], [0.0, 1.0, 4.0, 5.2], [w / 3, 1.0, 4.0, 5.2]] if storeys == 2 else []
	wall(root, -w / 2, w / 2, -d / 2, h, 0.15, door + win1 + win2, kind, tint, true, 0.0, true, 1.5)
	wall(root, -w / 2, w / 2, d / 2, h, 0.15, (door if back_door else []) + win1 + win2, kind, tint, true, 0.0, true, 1.5)
	var side_wins := [[0.0, 1.0, 1.0, 2.2]] + ([[0.0, 1.0, 4.0, 5.2]] if storeys == 2 else [])
	wall(root, -d / 2, d / 2, -w / 2, h, 0.15, side_wins, kind, tint, false, 0.0, true, 1.5)
	wall(root, -d / 2, d / 2, w / 2, h, 0.15, [[0.0, 1.0, 1.0, 2.2]], kind, tint, false, 0.0, true, 1.5)
	box(root, Vector3(w + 0.1, 0.25, d + 0.1), Vector3(0, -0.1, 0), "concrete", Color(0.6, 0.57, 0.52), false, 1.0)   # footing
	if storeys == 2:
		box(root, Vector3(w, 0.15, d), Vector3(0, 3.1, 0), "wood", Color.WHITE.darkened(0.2), false, 1.5)
		box(root, Vector3(w + 0.04, 0.12, d + 0.04), Vector3(0, 3.2, 0), "wood", trim, false, 1.0)   # band between the storeys
	box(root, Vector3(w - 0.3, 0.06, d - 0.3), Vector3(0, 0.03, 0), "wood", Color(0.6, 0.5, 0.42), false, 1.0)   # floorboards
	box(root, Vector3(w - 0.3, 0.1, d - 0.3), Vector3(0, h + 0.05, 0), "wood", Color.WHITE.darkened(0.4), true, 1.5)   # ceiling
	for cx in [-w / 2, w / 2]:   # corner boards
		for cz in [-d / 2, d / 2]:
			box(root, Vector3(0.2, h, 0.2), Vector3(cx, h / 2, cz), "wood", trim, false, 1.0)
	var chim_x := w / 2 - 1.0
	var ridge := h
	match style:
		"brick":   # flat roof behind a parapet, a coping along the top
			box(root, Vector3(w + 0.2, 0.2, d + 0.2), Vector3(0, h + 0.1, 0), "concrete", Color(0.35, 0.33, 0.3), true, 2.0)
			for e in [[Vector3(w + 0.3, 0.6, 0.18), Vector3(0, h + 0.4, d / 2 + 0.06)], [Vector3(w + 0.3, 0.6, 0.18), Vector3(0, h + 0.4, -d / 2 - 0.06)],
					[Vector3(0.18, 0.6, d + 0.3), Vector3(w / 2 + 0.06, h + 0.4, 0)], [Vector3(0.18, 0.6, d + 0.3), Vector3(-w / 2 - 0.06, h + 0.4, 0)]]:
				box(root, e[0], e[1], "brick", Color.WHITE, false, 1.5)
				box(root, e[0] * Vector3(1, 0, 1) + Vector3(0.06 if e[0].x < 1 else 0.0, 0.08, 0.06 if e[0].z < 1 else 0.0), e[1] + Vector3(0, 0.34, 0), "concrete", Color(0.7, 0.68, 0.62), false, 1.0)
			if snow_cover:
				snow_cap(root, Vector3(w - 0.1, 0.25, d - 0.1), Vector3(0, h + 0.32, 0))
			ridge = h + 0.7
		"shack":   # lean-to: one sheet of tin falling to the back
			var fall := 0.6
			var span := d + 0.9
			var sheet := box(root, Vector3(w + 0.6, 0.06, span / cos(atan2(fall, span))), Vector3(0, h + fall / 2.0 + 0.03, 0), "corrugated", Color(0.75, 0.6, 0.5), false, 1.0)
			sheet.rotation.x = -atan2(fall, span)
			if snow_cover:
				snow_cap(root, Vector3(w + 0.4, 0.14, span / cos(atan2(fall, span)) - 0.3), Vector3(0, h + fall / 2.0 + 0.13, 0), Vector3(-atan2(fall, span), 0, 0))
			for side in [-1.0, 1.0]:   # triangles closing the ends under the slope
				prism(root, Vector3(d, fall, 0.14), Vector3(side * w / 2, h + fall / 2.0, 0), kind, tint, Vector3(0, PI / 2, 0), 1.5).mesh.left_to_right = 0.0
			ridge = h + fall
		_:   # gable roof, shingles or tin, with closed gable ends and a ridge cap
			var a := 0.55
			var hd := d / 2.0 + 0.45
			var rkind := "shingle" if rng.randf() < 0.6 else "corrugated"
			var rtint := Color.WHITE if rkind == "shingle" else Color(0.82, 0.72, 0.62)
			for side in [-1.0, 1.0]:
				var zc: float = side * hd / 2.0
				var slab := box(root, Vector3(w + 0.7, 0.1, hd / cos(a)), Vector3(0, h + (d / 2.0 - absf(zc)) * tan(a) + 0.05 / cos(a), zc), rkind, rtint, false, 1.5)
				slab.rotation.x = side * a   # the ridge side up
				if snow_cover:   # snow on each slope, a little short of the eaves
					var n := Vector3(0, cos(a), side * sin(a))   # slope normal (out of the roof)
					snow_cap(root, Vector3(w + 0.5, 0.16, hd / cos(a) - 0.35), slab.position + n * 0.12 + Vector3(0, 0, -side * 0.12), Vector3(side * a, 0, 0))
				var fascia := box(root, Vector3(w + 0.7, 0.18, 0.05), Vector3(0, h - 0.45 * tan(a) - 0.04, side * (hd - 0.02)), "wood", trim, false, 1.0)
				fascia.rotation.x = side * a
				prism(root, Vector3(d, d / 2.0 * tan(a), 0.15), Vector3(side * w / 2.0, h + d / 4.0 * tan(a), 0), kind, tint, Vector3(0, PI / 2, 0), 1.5)
			box(root, Vector3(w + 0.75, 0.12, 0.3), Vector3(0, h + d / 2.0 * tan(a) + 0.08, 0), "metal", Color(0.4, 0.38, 0.36), false, 1.0)   # ridge cap
			ridge = h + d / 2.0 * tan(a)
	box(root, Vector3(0.7, ridge - h + 1.0, 0.7), Vector3(chim_x, (h + ridge + 1.0) / 2.0, d * 0.15), "brick", Color.WHITE, false, 1.0)   # chimney
	box(root, Vector3(0.82, 0.12, 0.82), Vector3(chim_x, ridge + 1.06, d * 0.15), "concrete", Color(0.5, 0.45, 0.4), false, 1.0)
	# Window frames: glass, a broken shard, or boarded up.
	for side in [-1, 1]:
		for wd in (win1 + win2):
			var x: float = wd[0]
			var y0: float = wd[2]
			var y1: float = wd[3]
			var z: float = side * (d / 2 + 0.09)
			var c := Vector3(x, (y0 + y1) / 2, z)
			for e in [[Vector3(1.12, 0.08, 0.06), Vector3(0, (y1 - y0) / 2 + 0.04, 0)], [Vector3(1.12, 0.1, 0.12), Vector3(0, -(y1 - y0) / 2 - 0.05, 0)],
					[Vector3(0.08, y1 - y0, 0.06), Vector3(-0.54, 0, 0)], [Vector3(0.08, y1 - y0, 0.06), Vector3(0.54, 0, 0)]]:
				box(root, e[0], c + e[1], "wood", trim, false, 0.5)
			var roll := rng.randf()
			if roll < 0.3:
				var g = box(root, Vector3(1.0, y1 - y0, 0.01), c, "metal", Color.WHITE, false)
				g.material_override = glass()
				box(root, Vector3(0.04, y1 - y0, 0.03), c, "wood", trim, false, 0.3)
			elif roll < 0.6:
				var g = box(root, Vector3(0.5, 0.45, 0.01), c + Vector3(rng.randf_range(-0.25, 0.25), -0.35, 0), "metal", Color.WHITE, false, 2.0, Vector3(0, 0, rng.randf_range(-0.4, 0.4)))
				g.material_override = glass()
			elif roll < 0.85:
				for k in rng.randi_range(2, 3):
					box(root, Vector3(1.2, 0.18, 0.04), c + Vector3(0, -0.4 + k * 0.4, side * 0.04), "wood", Color(0.7, 0.62, 0.5).darkened(rng.randf() * 0.3), false, 0.8, Vector3(0, 0, rng.randf_range(-0.25, 0.25)))
	# Door frame and a door hanging open.
	for e in [[Vector3(1.6, 0.12, 0.2), Vector3(0, 2.36, 0)], [Vector3(0.1, 2.3, 0.2), Vector3(-0.75, 1.15, 0)], [Vector3(0.1, 2.3, 0.2), Vector3(0.75, 1.15, 0)]]:
		box(root, e[0], Vector3(0, 0, -d / 2) + e[1], "wood", trim, false, 0.5)
	var hinge := Node3D.new()
	root.add_child(hinge)
	hinge.position = Vector3(-0.68, 0, -d / 2 + 0.05)
	hinge.rotation.y = rng.randf_range(1.0, 1.9)
	box(hinge, Vector3(1.3, 2.2, 0.06), Vector3(0.65, 1.12, 0), "wood", tint.darkened(0.15), false, 1.0)
	sphere(hinge, 0.04, Vector3(1.15, 1.05, -0.05), "brass")
	# Porch roof + posts, balcony above it, steps up.
	var porch_h := 3.1 if storeys == 2 else 2.65
	box(root, Vector3(w, 0.15, 2.0), Vector3(0, porch_h, -d / 2 - 1.0), "wood", Color(0.7, 0.62, 0.52), false, 1.5)
	box(root, Vector3(w, 0.12, 2.0), Vector3(0, 0.06, -d / 2 - 1.0), "wood", Color(0.65, 0.55, 0.45), false, 1.0)
	box(root, Vector3(1.8, 0.08, 0.4), Vector3(0, 0.04, -d / 2 - 2.2), "wood", Color(0.6, 0.5, 0.4), false, 1.0)
	for x in [-w / 2 + 0.2, 0.0, w / 2 - 0.2]:
		if x != 0.0:
			box(root, Vector3(0.15, porch_h, 0.15), Vector3(x, porch_h / 2.0, -d / 2 - 1.9), "wood", trim, true, 1.5)
	if storeys == 2:
		railing(root, Vector3(-w / 2, 3.15, -d / 2 - 1.95), Vector3(w / 2, 3.15, -d / 2 - 1.95), 1.0, "wood")
	for i in 2:
		box(root, Vector3(0.9, 1.0, 0.05), Vector3(-w / 3 + i * w * 0.66, 1.6, -d / 2 - 0.08), "board", Color(0.3, 0.3, 0.3), false)
	# Inside: a table and chairs, a bed, a cupboard, junk on the floor.
	var tx := rng.randf_range(-w / 4, w / 4)
	box(root, Vector3(1.4, 0.06, 0.8), Vector3(tx, 0.76, 0.6), "wood", Color(0.6, 0.45, 0.32), false, 0.8)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			box(root, Vector3(0.06, 0.73, 0.06), Vector3(tx + sx * 0.62, 0.37, 0.6 + sz * 0.33), "wood", Color(0.5, 0.38, 0.28), false, 0.5)
		var ch := box(root, Vector3(0.42, 0.05, 0.42), Vector3(tx + sx * 0.95, 0.45, 0.6), "wood", Color(0.55, 0.42, 0.3), false, 0.5)
		if rng.randf() < 0.4:
			ch.rotation = Vector3(PI / 2, 0, 0.3)
			ch.position.y = 0.21
		else:
			box(root, Vector3(0.05, 0.45, 0.42), Vector3(tx + sx * 1.15, 0.7, 0.6), "wood", Color(0.55, 0.42, 0.3), false, 0.5)
	var bx := -w / 2 + 1.2
	box(root, Vector3(1.1, 0.35, 2.0), Vector3(bx, 0.25, d / 2 - 1.2), "wood", Color(0.5, 0.38, 0.28), false, 0.8)
	box(root, Vector3(1.0, 0.18, 1.9), Vector3(bx, 0.5, d / 2 - 1.2), "canvas", Color(0.7, 0.68, 0.6), false, 0.5)
	box(root, Vector3(1.1, 0.9, 0.08), Vector3(bx, 0.6, d / 2 - 0.2), "wood", Color(0.5, 0.38, 0.28), false, 0.8)
	box(root, Vector3(1.0, 1.9, 0.5), Vector3(w / 2 - 0.5, 0.95, d / 2 - 1.5), "wood", Color(0.55, 0.4, 0.3), false, 0.8, Vector3(0, PI / 2, 0))
	for k in rng.randi_range(4, 9):
		var s := rng.randf_range(0.08, 0.3)
		box(root, Vector3(s, 0.01 + s * 0.2, s * 1.4), Vector3(rng.randf_range(-w / 2 + 0.5, w / 2 - 0.5), 0.07, rng.randf_range(-d / 2 + 0.5, d / 2 - 0.5)),
			["paper", "wood", "canvas", "cardboard"][rng.randi() % 4], Color.WHITE.darkened(rng.randf() * 0.3), false, 0.3, Vector3(0, rng.randf() * TAU, 0))
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
