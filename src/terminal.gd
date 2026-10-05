# The train terminal. Commands are registered by main.gd as (name, min_args, usage, Callable).
# TAB completes, UP/DOWN walks history, typos get "Did you mean ...?".
# ponytail: full-screen overlay instead of an in-world screen; move to a SubViewport on the monitor later.
extends CanvasLayer

const Sfx = preload("res://src/sfx.gd")

signal closed

const AMBER := Color(1.0, 0.62, 0.22)

var out: RichTextLabel
var input: LineEdit
var commands := {}       # NAME -> {"args": int, "usage": String, "fn": Callable}
var history: Array[String] = []
var hist_i := 0
var confirm := Callable()  # pending YES/NO action
var booted := false
var _typed := 0.0
# Right-hand monitor: camera feed or facility map.
var monitor: Control
var feed: TextureRect
var feed_vp: SubViewport
var feed_cam: Camera3D
var feed_label: Label
var map: Control
var map_draw := Callable()
var _cam_target: Node3D
var _cam_yaw := 0.0
var _cam_name := ""


func _ready() -> void:
	layer = 5
	visible = false
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "monospace"])
	# Amber CRT: dark bezel, rounded glass, scanlines + vignette shader on top.
	var bezel := ColorRect.new()
	bezel.color = Color(0.05, 0.03, 0.02, 0.97)
	add_child(bezel)
	bezel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var glass := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.06, 0.02)
	sb.set_corner_radius_all(48)
	sb.border_color = Color(0.3, 0.2, 0.12)
	sb.set_border_width_all(6)
	glass.add_theme_stylebox_override("panel", sb)
	add_child(glass)
	glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 28)
	var box := VBoxContainer.new()
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 70)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	out = RichTextLabel.new()
	out.bbcode_enabled = true
	out.scroll_following = true
	out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out.visible_characters = 0
	out.add_theme_font_override("normal_font", font)
	out.add_theme_font_size_override("normal_font_size", 18)
	out.add_theme_color_override("default_color", AMBER)
	row.add_child(out)
	_build_monitor(row, font)
	input = LineEdit.new()
	input.placeholder_text = "type a command   (TAB completes, UP/DOWN history, ESC leaves)"
	input.add_theme_font_override("font", font)
	input.add_theme_font_size_override("font_size", 18)
	input.add_theme_color_override("font_color", AMBER.lightened(0.2))
	input.add_theme_color_override("caret_color", AMBER)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.1, 0.05, 0.02)
	flat.border_color = AMBER.darkened(0.5)
	flat.border_width_top = 2
	input.add_theme_stylebox_override("normal", flat)
	input.add_theme_stylebox_override("focus", flat)
	box.add_child(input)
	var scan := ColorRect.new()
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment() {
	float lines = 0.5 + 0.5 * sin(SCREEN_UV.y * 1400.0);
	vec2 d = UV - vec2(0.5);
	float vig = smoothstep(0.35, 0.75, length(d * vec2(1.0, 1.3)));
	COLOR = vec4(0.0, 0.0, 0.0, lines * 0.16 + vig * 0.55);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	scan.material = mat
	add_child(scan)
	scan.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	input.text_submitted.connect(_submit)
	input.gui_input.connect(_key)


func _build_monitor(row: HBoxContainer, font: Font) -> void:
	monitor = Control.new()
	monitor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	monitor.size_flags_stretch_ratio = 0.9
	monitor.visible = false
	monitor.clip_contents = true
	row.add_child(monitor)
	var frame := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.02, 0.01)
	sb.border_color = AMBER.darkened(0.3)
	sb.set_border_width_all(3)
	frame.add_theme_stylebox_override("panel", sb)
	monitor.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	feed_vp = SubViewport.new()
	feed_vp.size = Vector2i(800, 560)
	feed_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(feed_vp)
	feed_cam = Camera3D.new()
	feed_cam.fov = 75.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.55, 0.5)
	env.ambient_light_energy = 0.15
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	feed_cam.environment = env
	feed_vp.add_child(feed_cam)
	feed = TextureRect.new()
	feed.texture = feed_vp.get_texture()
	feed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	feed.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float time_s = 0.0;
float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + time_s) * 43758.5453); }
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.3, 0.59, 0.11)) * 1.6;
	vec3 tint = vec3(1.0, 0.72, 0.4) * g;
	tint += (rnd(UV * 400.0) - 0.5) * 0.12;
	tint *= 0.85 + 0.15 * sin(UV.y * 900.0);
	COLOR = vec4(tint, 1.0);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	feed.material = mat
	monitor.add_child(feed)
	feed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	map = Control.new()
	monitor.add_child(map)
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	map.draw.connect(func(): if map_draw.is_valid(): map_draw.call(map))
	feed_label = Label.new()
	feed_label.add_theme_font_override("font", font)
	feed_label.add_theme_font_size_override("font_size", 20)
	feed_label.add_theme_color_override("font_color", AMBER)
	monitor.add_child(feed_label)
	feed_label.position = Vector2(18, 12)


func show_camera(target: Node3D, cam_name: String) -> void:
	_cam_target = target
	_cam_name = cam_name
	_cam_yaw = 0.0
	monitor.visible = true
	feed.visible = true
	map.visible = false
	feed_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func show_map(draw: Callable, title: String) -> void:
	map_draw = draw
	_cam_target = null
	monitor.visible = true
	feed.visible = false
	map.visible = true
	feed_label.text = title
	feed_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func hide_monitor() -> void:
	_cam_target = null
	monitor.visible = false
	feed_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func add(name: String, min_args: int, usage: String, fn: Callable) -> void:
	commands[name] = {"args": min_args, "usage": usage, "fn": fn}


func open() -> void:
	visible = true
	if monitor.visible and feed.visible:
		feed_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	input.grab_focus()
	if not booted:
		booted = true
		say("BRM RAILNET OS v1.3   (c) Bureau of Reclaimed Materials\n----------------------------------------------------------")
		say("Your productivity is appreciated. Your safety is estimated.")
		say("Type HELP for a list of commands.\n")


func close() -> void:
	if not visible:
		return
	visible = false
	feed_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	input.release_focus()
	closed.emit()


func say(text: String) -> void:
	out.append_text(text + "\n")


func error(text: String) -> void:
	say("[color=#ff4a2a]ERROR: %s[/color]" % text)
	Sfx.play(self, "error", null, -8.0)


func clear() -> void:
	out.clear()
	out.visible_characters = 0


func _process(delta: float) -> void:
	if monitor.visible:
		if feed.visible:
			if is_instance_valid(_cam_target):
				feed_cam.global_transform = _cam_target.global_transform.rotated_local(Vector3.UP, _cam_yaw)
				feed_label.text = "%s     %s REC" % [_cam_name, "o" if fmod(Time.get_ticks_msec() / 500.0, 2.0) < 1.0 else " "]
				(feed.material as ShaderMaterial).set_shader_parameter("time_s", Time.get_ticks_msec() / 1000.0)
			else:
				feed_label.text = "SIGNAL LOST"
		else:
			map.queue_redraw()
	var total := out.get_total_character_count()
	if out.visible_characters < total:
		_typed += delta * 900.0
		var n := int(_typed)
		_typed -= n
		out.visible_characters = mini(out.visible_characters + n, total)
		if n > 0 and randf() < 0.25:
			Sfx.play(self, "key", null, -20.0)


func _submit(line: String) -> void:
	input.clear()
	if line.strip_edges() == "":
		return
	history.append(line)
	hist_i = history.size()
	say("\\\\RAILNET\\\\> " + line.replace("[", "[lb]"))
	run(line)


func run(line: String) -> void:
	var a := parse(line)
	if a.is_empty():
		return
	if confirm.is_valid():
		var c := confirm
		confirm = Callable()
		if a[0] in ["YES", "Y"]:
			c.call()
			return
		if a[0] in ["NO", "N"]:
			say("Cancelled.")
			return
	var cmd = commands.get(a[0])
	if cmd == null:
		var guess := closest(a[0], commands.keys())
		error("Command not recognized. " + ("Did you mean %s?" % guess if guess != "" else "Type HELP for a list of commands."))
		return
	if a.size() - 1 < cmd.args:
		error("Incorrect use of parameters. Usage: " + cmd.usage)
		return
	cmd.fn.call(a.slice(1))


func _key(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_TAB:
			var parts := input.text.split(" ")
			if parts.size() == 1:
				var done := complete(parts[0].to_upper(), commands.keys())
				input.text = done + (" " if commands.has(done) else "")
				input.caret_column = input.text.length()
			input.accept_event()
		KEY_UP:
			hist_i = maxi(0, hist_i - 1)
			if hist_i < history.size():
				input.text = history[hist_i]
				input.caret_column = input.text.length()
			input.accept_event()
		KEY_DOWN:
			hist_i = mini(history.size(), hist_i + 1)
			input.text = history[hist_i] if hist_i < history.size() else ""
			input.caret_column = input.text.length()
			input.accept_event()
		KEY_LEFT, KEY_RIGHT:
			if monitor.visible and feed.visible and input.text == "":
				_cam_yaw = clampf(_cam_yaw + (0.12 if e.keycode == KEY_LEFT else -0.12), -1.2, 1.2)
				input.accept_event()
		KEY_ESCAPE:
			close()
			input.accept_event()


static func parse(line: String) -> PackedStringArray:
	return line.strip_edges().to_upper().split(" ", false)


## Longest common prefix of every name starting with `word` (unchanged if none match).
static func complete(word: String, names: Array) -> String:
	var hits := names.filter(func(n): return String(n).begins_with(word))
	if hits.is_empty():
		return word
	var p: String = hits[0]
	for h in hits:
		while not String(h).begins_with(p):
			p = p.left(-1)
	return p


static func closest(word: String, names: Array) -> String:
	var best := ""
	var score := 0.45
	for n in names:
		var s := word.similarity(n)
		if s > score:
			score = s
			best = n
	return best
