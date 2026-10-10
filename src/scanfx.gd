# Scanner pulse. A soft blue wave rolls out from where you stood across every surface in reach
# (a depth pass on the camera: a bright front, a fading grid behind it), and whatever it reaches
# lights up through walls for a few seconds: scrap in blue with its name and worth, entities in red,
# points of interest (main breaker, airdrops) in amber.
extends Node3D

const Data = preload("res://src/data.gd")
const Sfx = preload("res://src/sfx.gd")

const SPEED := 13.0   # metres per second
const HOLD := 5.5     # seconds a find stays lit
const TINT := {"scrap": Color(0.35, 0.75, 1.0), "entity": Color(1.0, 0.28, 0.22), "poi": Color(1.0, 0.72, 0.25)}

var main
var origin := Vector3.ZERO
var radius := 16.0
var hits: Array = []   # {node, d, kind, name, detail, lit, t, meshes, tag, lift}
var _t := 0.0
var _post: MeshInstance3D
var _post_mat: ShaderMaterial
var _layer: CanvasLayer
var _overlay: Control
static var _wave: Shader
static var _glow: Shader
static var _glow_mats := {}
static var _font: SystemFont
static var _ring: ImageTexture


func start(cam: Camera3D, at: Vector3, r: float, list: Array) -> void:
	origin = at
	radius = r
	hits = list
	if _wave == null:
		_wave = Shader.new()
		_wave.code = WAVE
		_glow = Shader.new()
		_glow.code = GLOW
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "monospace"])
		_font.font_weight = 700
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = _wave
	_post_mat.set_shader_parameter("origin", origin)
	_post_mat.set_shader_parameter("max_radius", radius)
	_post_mat.set_shader_parameter("tint", TINT.scrap)
	_post = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	_post.mesh = q
	_post.material_override = _post_mat
	_post.extra_cull_margin = 16384.0
	_post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cam.add_child(_post)
	_post.position = Vector3(0, 0, -0.3)
	# The rings and names are drawn flat, over everything (the HUD, the night-vision goggles):
	# they're the scanner's readout on your visor, not things in the world.
	_layer = CanvasLayer.new()
	_layer.layer = 3
	add_child(_layer)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)


func _process(delta: float) -> void:
	_t += delta
	var r := _t * SPEED
	if is_instance_valid(_post):
		_post_mat.set_shader_parameter("radius", r)
		_post_mat.set_shader_parameter("fade", clampf(1.0 - (r - radius) / 5.0, 0.0, 1.0))
	var blips := 0
	for h in hits:
		if not is_instance_valid(h.node):
			for k in ["tag", "ring"]:
				if h.get(k) != null and is_instance_valid(h[k]):
					h[k].queue_free()
			continue
		if not h.lit:
			if r < h.d:
				continue
			_light(h, blips < 10)
			blips += 1
		h.t += delta
		var g: float = (0.75 + 1.4 * exp(-h.t * 5.0)) * clampf(HOLD - h.t, 0.0, 1.0)   # pop, settle, fade
		for mi in h.meshes:
			if is_instance_valid(mi):
				mi.set_instance_shader_parameter("glow", g)
		var ring: Sprite3D = h.ring
		ring.global_position = h.node.global_position + Vector3(0, h.lift * 0.35, 0)
		ring.scale = Vector3.ONE * (1.0 + 2.5 * exp(-h.t * 12.0) + 0.06 * sin(h.t * 7.0)) * (1.6 if h.kind != "scrap" else 1.0)
		ring.modulate.a = clampf(HOLD - h.t, 0.0, 1.0) * minf(1.0, h.t * 8.0)
		var tag: Label3D = h.tag
		tag.global_position = ring.global_position
		tag.scale = Vector3.ONE * (1.0 + 0.35 * exp(-h.t * 8.0)) * minf(1.0, h.t * 6.0 + 0.2)
		tag.modulate.a = clampf(HOLD - h.t, 0.0, 1.0)
		tag.outline_modulate.a = tag.modulate.a * 0.85
	if _overlay:
		_overlay.queue_redraw()
	if _t > radius / SPEED + HOLD + 0.5:
		_finish()


func _light(h: Dictionary, blip: bool) -> void:
	h.lit = true
	var mat: ShaderMaterial = _glow_mats.get(h.kind)
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = _glow
		mat.set_shader_parameter("tint", TINT[h.kind])
		_glow_mats[h.kind] = mat
	for mi: MeshInstance3D in h.node.find_children("*", "MeshInstance3D", true, false):
		if mi.material_overlay == null and mi.visible:
			mi.material_overlay = mat
			h.meshes.append(mi)
	var ring := Sprite3D.new()   # lock-on ring: snaps in from wide, then breathes
	ring.texture = _ring_tex()
	ring.pixel_size = 0.0009
	ring.fixed_size = true
	ring.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ring.no_depth_test = true
	ring.shaded = false
	ring.render_priority = 9
	ring.modulate = TINT[h.kind]
	ring.visible = false   # (drawn on the overlay)
	add_child(ring)
	h.ring = ring
	var tag := Label3D.new()
	tag.text = "%s\n%s" % [h.name, h.detail]
	tag.font = _font
	tag.font_size = 34
	tag.line_spacing = -4
	tag.pixel_size = 0.0006
	tag.visible = false   # (drawn on the overlay)
	h.tag_show = h.get("tag_ok", true)
	tag.offset = Vector2(0, 78 if h.kind == "scrap" else 110)   # above the ring, in screen pixels
	tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	tag.fixed_size = true
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.render_priority = 10
	tag.outline_size = 10
	tag.outline_modulate = Color(0.02, 0.05, 0.1, 0.85)
	tag.modulate = TINT[h.kind].lightened(0.35)
	tag.shaded = false
	add_child(tag)
	h.tag = tag
	if blip:
		var pitch := 0.6 if h.kind == "entity" else (0.85 if h.kind == "poi" else clampf(0.9 + h.get("value", 0) * 0.04, 0.9, 1.5))
		Sfx.play(self, "blip", h.node.global_position, -10.0 if h.kind == "scrap" else -4.0, pitch)


## Each lock-on ring and its name tag, where it is on screen.
func _draw_overlay() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var vh: float = _overlay.size.y
	var k: float = vh / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))   # world size at 1 m -> pixels (as fixed_size draws)
	for h in hits:
		if not h.get("lit", false) or h.get("ring") == null or not is_instance_valid(h.ring):
			continue
		var ring: Sprite3D = h.ring
		if cam.is_position_behind(ring.global_position):
			continue
		var at: Vector2 = cam.unproject_position(ring.global_position)
		var tex := _ring_tex()
		var sz: float = tex.get_width() * ring.pixel_size * k * ring.scale.x
		_overlay.draw_texture_rect(tex, Rect2(at - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, ring.modulate)
		var tag: Label3D = h.tag
		if not h.get("tag_show", true) or tag.modulate.a <= 0.01:
			continue
		var fs := int(tag.font_size * tag.pixel_size * k * tag.scale.x * 1.35)
		var lines: PackedStringArray = tag.text.split("
")
		var y: float = at.y - tag.offset.y * tag.pixel_size * k - (lines.size() - 1) * fs * 1.05
		for line in lines:
			var w: float = _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var p := Vector2(at.x - w * 0.5, y)
			_overlay.draw_string_outline(_font, p, line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, tag.outline_modulate)
			_overlay.draw_string(_font, p, line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tag.modulate)
			y += fs * 1.05


static func _ring_tex() -> ImageTexture:
	if _ring == null:
		var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
		for y in 96:
			for x in 96:
				var a := Vector2(x - 47.5, y - 47.5).angle()
				var r := Vector2(x - 47.5, y - 47.5).length()
				var band := exp(-pow((r - 40.0) / 2.2, 2.0)) + 0.35 * exp(-pow((r - 40.0) / 7.0, 2.0))
				var gaps := 0.15 if fmod(a + TAU, PI / 2.0) < 0.22 else 1.0   # four notches, like a reticle
				img.set_pixel(x, y, Color(1, 1, 1, clampf(band * gaps, 0.0, 1.0)))
		_ring = ImageTexture.create_from_image(img)
	return _ring


func _finish() -> void:
	for h in hits:
		for mi in h.meshes:
			if is_instance_valid(mi) and mi.material_overlay == _glow_mats.get(h.kind):
				mi.material_overlay = null
		for k in ["tag", "ring"]:
			if h.get(k) != null and is_instance_valid(h[k]):
				h[k].queue_free()
	if is_instance_valid(_post):
		_post.queue_free()
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_post):
		_post.queue_free()


const WAVE := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_add, fog_disabled, shadows_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 origin;
uniform float radius = 0.0;
uniform float max_radius = 16.0;
uniform float fade = 1.0;
uniform vec3 tint : source_color;
void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);   // full screen
}
void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec3 col = vec3(0.0);
	if (depth > 0.000001 && depth < 0.999999) {
		vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		v.xyz /= v.w;
		vec3 world = (INV_VIEW_MATRIX * vec4(v.xyz, 1.0)).xyz;
		float d = distance(world, origin);
		float behind = radius - d;                          // > 0 once the wave has passed
		float front = exp(-behind * behind / 0.12);                    // the soft ring itself
		float trail = behind > 0.0 ? exp(-behind / 1.3) : 0.0;          // a faint wake behind it
		vec3 g = abs(fract(world * 1.25) - 0.5);
		float grid = smoothstep(0.465, 0.5, max(max(g.x, g.y), g.z));
		float reach = 1.0 - smoothstep(max_radius * 0.8, max_radius, d);
		col = tint * (front * 0.32 + trail * 0.03 + grid * trail * 0.22) * reach * fade;
	}
	ALBEDO = col;
	ALPHA = 1.0;
}"""

const GLOW := """shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_back, fog_disabled, shadows_disabled;
uniform vec3 tint : source_color;
instance uniform float glow = 0.0;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float lines = 0.8 + 0.2 * sin(FRAGCOORD.y * 0.6 - TIME * 14.0);
	ALBEDO = tint * (rim * 1.8 + 0.42) * glow * lines;
	ALPHA = 1.0;
}"""
