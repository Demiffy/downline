# The train terminal. Commands are registered by main.gd as (name, min_args, usage, Callable).
# TAB completes, UP/DOWN walks history, typos get "Did you mean ...?".
# Full-screen overlay while you use it; the train's monitor mirrors it in the world (screen_text()).
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
var decline := Callable()   # a NO for a question the host asked (net.gd)
var booted := false
var _typed := 0.0
var _screen := ""
var _screen_key := ""
# Right-hand monitor: camera feed or facility map.
var monitor: Control
var feed: TextureRect
var feed_vp: SubViewport
var feed_cam: Camera3D
var feed_label: Label
var feed_stamp: Label
var rec_dot: Control
var map: Control
var map_draw := Callable()
var _cam_target: Node3D
var _cam_yaw := 0.0
var _cam_name := ""
var header: Label
var suggest: RichTextLabel
var quickref: PanelContainer
var quickref_text: RichTextLabel
var _glass: ShaderMaterial
var _power: Tween
var _closing := false
var _glitch := 0.0      # the feed tearing as it switches camera
var status_fn := Callable()   # main sets this: returns "STATION A   08:14   CREDITS 60"
const QUICK := [["HELP", "every command"], ["MAP", "your route"], ["VIEW_STATION", "details of a stop"], ["ROUTE_TO", "travel"],
	["MARKET", "quota + prices"], ["SCAN_TRAIN", "what you've got"], ["SHOP", "buy gear"], ["LIST_CAMS", "security cameras"],
	["OPEN_BULKHEAD", "open a door below"], ["LIST_LOGS", "data disks"], ["LEAVE_CHECKPOINT", "start an assignment"]]


func _ready() -> void:
	layer = 5
	visible = false
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "monospace"])
	var bold := SystemFont.new()
	bold.font_names = font.font_names
	bold.font_weight = 700
	# Amber CRT: dark bezel, rounded glass, scanlines + vignette shader on top.
	var bezel := Control.new()   # the casing: dark painted steel, screws, the Bureau's badge
	add_child(bezel)
	bezel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bezel.draw.connect(func():
		var r := Rect2(Vector2.ZERO, bezel.size)
		bezel.draw_rect(r, Color(0.075, 0.068, 0.06))
		for i in 6:   # brushed bands
			bezel.draw_rect(Rect2(0, r.size.y * i / 6.0, r.size.x, r.size.y / 12.0), Color(1, 1, 1, 0.012))
		for c in [Vector2(14, 14), Vector2(r.size.x - 14, 14), Vector2(14, r.size.y - 14), Vector2(r.size.x - 14, r.size.y - 14)]:
			bezel.draw_circle(c, 6.0, Color(0.2, 0.19, 0.17))
			bezel.draw_line(c - Vector2(4, 1), c + Vector2(4, 1), Color(0.05, 0.05, 0.05), 1.5)
		var badge := Rect2(r.size.x / 2.0 - 70, r.size.y - 25, 140, 18)
		bezel.draw_rect(badge, Color(0.55, 0.45, 0.25))
		bezel.draw_string(bold, badge.position + Vector2(16, 14), "BRM  RAILNET-7", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.12, 0.1, 0.08))
		bezel.draw_circle(Vector2(r.size.x - 60, r.size.y - 16), 4.0, Color(0.3, 1.0, 0.35)))   # the power lamp
	var glass := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.045, 0.02)
	sb.set_corner_radius_all(48)
	sb.border_color = Color(0.02, 0.018, 0.015)
	sb.set_border_width_all(10)
	glass.add_theme_stylebox_override("panel", sb)
	add_child(glass)
	glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 28)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 64)
	# Header: system name left, where/when/balance right, a rule under it.
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := _text(bold, 18, AMBER)
	title.text = "BRM RAILNET OS v1.3"
	head.add_child(title)
	header = _text(font, 18, AMBER.darkened(0.15))
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(header)
	box.add_child(_rule())
	# Body: the log on the left; on the right either the monitor (cams/map) or a quick reference.
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	out = RichTextLabel.new()
	out.bbcode_enabled = true
	out.scroll_following = true
	out.focus_mode = Control.FOCUS_NONE
	out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out.visible_characters = 0
	out.add_theme_font_override("normal_font", font)
	out.add_theme_font_override("bold_font", bold)
	out.add_theme_font_size_override("normal_font_size", 19)
	out.add_theme_font_size_override("bold_font_size", 19)
	out.add_theme_color_override("default_color", AMBER)
	out.add_theme_constant_override("line_separation", 3)
	row.add_child(out)
	_build_monitor(row, font)
	quickref = PanelContainer.new()
	quickref.custom_minimum_size.x = 360
	var qsb := StyleBoxFlat.new()
	qsb.bg_color = Color(0.07, 0.035, 0.015)
	qsb.border_color = AMBER.darkened(0.6)
	qsb.set_border_width_all(2)
	qsb.set_content_margin_all(14)
	quickref.add_theme_stylebox_override("panel", qsb)
	row.add_child(quickref)
	quickref_text = RichTextLabel.new()
	quickref_text.bbcode_enabled = true
	quickref_text.fit_content = true
	quickref_text.focus_mode = Control.FOCUS_NONE
	quickref_text.add_theme_font_override("normal_font", font)
	quickref_text.add_theme_font_override("bold_font", bold)
	quickref_text.add_theme_font_size_override("normal_font_size", 16)
	quickref_text.add_theme_font_size_override("bold_font_size", 16)
	quickref_text.add_theme_color_override("default_color", AMBER.darkened(0.2))
	quickref.add_child(quickref_text)
	box.add_child(_rule())
	# Suggestions for what you're typing (matching commands, or the usage of the one you've typed).
	suggest = RichTextLabel.new()
	suggest.bbcode_enabled = true
	suggest.fit_content = true
	suggest.scroll_active = false
	suggest.focus_mode = Control.FOCUS_NONE
	suggest.custom_minimum_size.y = 24
	suggest.add_theme_font_override("normal_font", font)
	suggest.add_theme_font_size_override("normal_font_size", 16)
	suggest.add_theme_color_override("default_color", AMBER.darkened(0.35))
	box.add_child(suggest)
	# Prompt line.
	var line_panel := PanelContainer.new()
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(0.16, 0.07, 0.02)
	lsb.border_color = AMBER.darkened(0.25)
	lsb.set_border_width_all(2)
	lsb.set_content_margin_all(8)
	lsb.content_margin_left = 14
	line_panel.add_theme_stylebox_override("panel", lsb)
	box.add_child(line_panel)
	var line := HBoxContainer.new()
	line_panel.add_child(line)
	var prompt := _text(bold, 20, AMBER.lightened(0.15))
	prompt.text = "RAILNET> "
	line.add_child(prompt)
	input = LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.placeholder_text = "type a command, e.g. HELP"
	input.caret_blink = true
	input.caret_force_displayed = true
	input.context_menu_enabled = false
	if "keep_editing_on_text_submit" in input:
		input.set("keep_editing_on_text_submit", true)
	input.add_theme_font_override("font", bold)
	input.add_theme_font_size_override("font_size", 20)
	input.add_theme_color_override("font_color", Color(1, 0.86, 0.6))
	input.add_theme_color_override("font_placeholder_color", AMBER.darkened(0.55))
	input.add_theme_color_override("caret_color", Color(1, 0.86, 0.6))
	input.add_theme_constant_override("caret_width", 3)
	var none := StyleBoxEmpty.new()
	input.add_theme_stylebox_override("normal", none)
	input.add_theme_stylebox_override("focus", none)
	line.add_child(input)
	# Key hints.
	var hints := RichTextLabel.new()
	hints.bbcode_enabled = true
	hints.fit_content = true
	hints.scroll_active = false
	hints.focus_mode = Control.FOCUS_NONE
	hints.add_theme_font_override("normal_font", font)
	hints.add_theme_font_size_override("normal_font_size", 15)
	hints.add_theme_color_override("default_color", AMBER.darkened(0.45))
	hints.text = "[ENTER] run    [TAB] complete    [UP/DOWN] history    [PGUP/PGDN] scroll    [ESC] leave terminal"
	box.add_child(hints)
	# The glass over it all: bulged, a fringe of colour, scanlines, the phosphor glowing, a slow
	# roll bar, and the picture opening up when it's switched on (and shrinking away when off).
	var scan := ColorRect.new()
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float open_h = 1.0;
uniform float open_v = 1.0;
uniform float flash = 0.0;
uniform float roll = 0.0;
void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	vec2 uv = SCREEN_UV + c * dot(c, c) * 0.07;
	float ab = 0.0012;
	vec3 col = vec3(textureLod(screen, uv + vec2(ab, 0.0), 0.0).r, textureLod(screen, uv, 0.0).g, textureLod(screen, uv - vec2(ab, 0.0), 0.0).b);
	vec3 glow = textureLod(screen, uv, 3.0).rgb * 0.5 + textureLod(screen, uv, 5.0).rgb * 0.35;
	col += glow * vec3(1.0, 0.7, 0.4) * 0.55;
	col *= 0.86 + 0.14 * sin(FRAGCOORD.y * 2.0);
	col += 0.025 * smoothstep(0.07, 0.0, abs(fract(SCREEN_UV.y - roll) - 0.5));
	col *= smoothstep(0.95, 0.3, length(c * vec2(1.0, 1.25))) * 0.55 + 0.45;
	float m = step(abs(c.x), open_h * 0.5) * step(abs(c.y), max(open_v * 0.5, 0.0015));
	col = mix(vec3(0.0), col + flash * vec3(1.0, 0.9, 0.75), m);
	COLOR = vec4(col, 1.0);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	scan.material = mat
	add_child(scan)
	scan.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glass = mat
	input.text_submitted.connect(_submit)
	input.text_changed.connect(func(_t): _update_suggest())
	input.gui_input.connect(_key)


func _text(font: Font, size: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = AMBER.darkened(0.6)
	r.custom_minimum_size.y = 2
	return r


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
	feed_cam.cull_mask = 0xFFFFF & ~2   # (not the first-person hand)
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
uniform float glitch = 0.0;
float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + time_s) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	float band = step(0.7, fract(sin(floor(UV.y * 24.0) * 91.7 + floor(time_s * 20.0)) * 437.5));
	uv.x += (band * 0.08 + 0.01 * sin(UV.y * 40.0 + time_s * 30.0)) * glitch;
	vec4 c = texture(TEXTURE, uv);
	float g = dot(c.rgb, vec3(0.3, 0.59, 0.11)) * 1.6;
	vec3 tint = vec3(1.0, 0.72, 0.4) * g;
	tint += (rnd(UV * 400.0) - 0.5) * 0.12;
	tint *= 0.85 + 0.15 * sin(UV.y * 900.0);
	tint = mix(tint, vec3(rnd(UV * 300.0)) * 0.6, glitch * 0.5);
	tint *= smoothstep(0.8, 0.35, length(UV - 0.5));
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
	feed_stamp = Label.new()   # the camera's own clock, burnt into the corner
	feed_stamp.add_theme_font_override("font", font)
	feed_stamp.add_theme_font_size_override("font_size", 15)
	feed_stamp.add_theme_color_override("font_color", Color(AMBER, 0.8))
	monitor.add_child(feed_stamp)
	feed_stamp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	feed_stamp.position += Vector2(18, -34)
	rec_dot = Control.new()
	monitor.add_child(rec_dot)
	rec_dot.draw.connect(func():
		if fmod(Time.get_ticks_msec() / 500.0, 2.0) < 1.0:
			rec_dot.draw_circle(Vector2.ZERO, 7.0, Color(1.0, 0.15, 0.1))
			rec_dot.draw_circle(Vector2.ZERO, 12.0, Color(1.0, 0.15, 0.1, 0.25)))


func show_camera(target: Node3D, cam_name: String) -> void:
	_cam_target = target
	_cam_name = cam_name
	_cam_yaw = 0.0
	_glitch = 1.0
	Sfx.play(self, "crackle", null, -18.0, 1.4)
	monitor.visible = true
	quickref.visible = false
	feed.visible = true
	map.visible = false
	feed_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func show_map(draw: Callable, title: String) -> void:
	map_draw = draw
	_cam_target = null
	monitor.visible = true
	quickref.visible = false
	feed.visible = false
	map.visible = true
	rec_dot.visible = false
	feed_stamp.visible = false
	feed_label.text = title
	feed_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func hide_monitor() -> void:
	_cam_target = null
	monitor.visible = false
	quickref.visible = true
	feed_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func add(name: String, min_args: int, usage: String, fn: Callable) -> void:
	commands[name] = {"args": min_args, "usage": usage, "fn": fn}


func open() -> void:
	if _power:
		_power.kill()
	var was := visible and not _closing
	_closing = false
	visible = true
	if not was:   # switched on: a line, then the picture
		Sfx.play(self, "flash_whine", null, -22.0, 1.6)
		_glass.set_shader_parameter("open_h", 0.0)
		_glass.set_shader_parameter("open_v", 0.0)
		_glass.set_shader_parameter("flash", 1.0)
		_power = create_tween()
		_power.tween_method(func(v: float): _glass.set_shader_parameter("open_h", v), 0.0, 1.0, 0.12).set_ease(Tween.EASE_OUT)
		_power.tween_method(func(v: float): _glass.set_shader_parameter("open_v", v), 0.0, 1.0, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_power.tween_method(func(v: float): _glass.set_shader_parameter("flash", v), 1.0, 0.0, 0.3)
	if monitor.visible and feed.visible:
		feed_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_refresh_quickref()
	_update_suggest()
	_focus()
	if not booted:
		booted = true
		say("BRM RAILNET OS v1.3   (c) Bureau of Reclaimed Materials\n----------------------------------------------------------")
		say("Your productivity is appreciated. Your safety is estimated.")
		say("Type HELP for a list of commands.\n")


func _focus() -> void:
	input.grab_focus()
	input.caret_column = input.text.length()
	if input.has_method("edit"):
		input.call("edit")


func _refresh_quickref() -> void:
	var t := "[b]QUICK REFERENCE[/b]\n\n"
	for q in QUICK:
		if commands.has(q[0]):
			t += "[color=#ffd08a]%s[/color]\n  %s\n" % [q[0], q[1]]
	quickref_text.text = t


## Matching commands while typing the first word; the usage line once a command is typed.
func _update_suggest() -> void:
	var parts := input.text.strip_edges(true, false).to_upper().split(" ")
	var word := parts[0] if parts.size() > 0 else ""
	if word == "":
		suggest.text = "commands: HELP  MAP  ROUTE_TO  MARKET  SHOP  LIST_CAMS  ...   (TAB completes)"
		return
	if commands.has(word) and (parts.size() > 1 or input.text.ends_with(" ")):
		suggest.text = "[color=#ffd08a]usage:[/color] " + String(commands[word].usage).replace("[", "[lb]")
		return
	var hits: Array = commands.keys().filter(func(n): return String(n).begins_with(word))
	hits.sort()
	if hits.is_empty():
		var guess := closest(word, commands.keys())
		if guess == "" and word.length() >= 3:   # same first letters is a decent hint too
			var near: Array = commands.keys().filter(func(n): return String(n).begins_with(word.left(3)))
			guess = near[0] if near.size() > 0 else ""
		suggest.text = "[color=#ff6a3a]no such command[/color]" + ("   did you mean [color=#ffd08a]%s[/color]?" % guess if guess != "" else "")
	elif hits.size() == 1 and hits[0] == word:
		suggest.text = "[color=#ffd08a]usage:[/color] " + String(commands[word].usage).replace("[", "[lb]")
	else:
		suggest.text = "  ".join(hits.map(func(h): return "[color=#ffd08a]%s[/color]%s" % [h.left(word.length()), h.substr(word.length())]))


## Plain text of the last `rows` lines (wrapped at `cols`) plus the prompt: for the in-world monitor.
func screen_text(rows := 12, cols := 34) -> String:
	var key := "%d|%s|%d" % [out.visible_characters, input.text, int(Time.get_ticks_msec() / 500) % 2]
	if key == _screen_key:
		return _screen
	_screen_key = key
	var txt := out.get_parsed_text().left(out.visible_characters)
	var lines := PackedStringArray()
	for raw in txt.split("\n"):
		var l: String = raw
		while l.length() > cols:
			lines.append(l.left(cols))
			l = l.substr(cols)
		lines.append(l)
	while lines.size() > 0 and lines[lines.size() - 1].strip_edges() == "":
		lines.remove_at(lines.size() - 1)
	var start := maxi(0, lines.size() - (rows - 1))
	var show := lines.slice(start)
	var cursor := "_" if int(Time.get_ticks_msec() / 500) % 2 == 0 else " "
	show.append(("> " + input.text + cursor).right(cols))
	_screen = "\n".join(show)
	return _screen


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	feed_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	input.release_focus()
	closed.emit()
	# Switched off: the picture squeezed to a line, the line to a dot, gone.
	if _power:
		_power.kill()
	_power = create_tween()
	_power.tween_method(func(v: float): _glass.set_shader_parameter("flash", v), 0.0, 0.6, 0.06)
	_power.tween_method(func(v: float): _glass.set_shader_parameter("open_v", v), 1.0, 0.0, 0.12).set_ease(Tween.EASE_IN)
	_power.tween_method(func(v: float): _glass.set_shader_parameter("open_h", v), 1.0, 0.0, 0.1).set_ease(Tween.EASE_IN)
	_power.tween_callback(func():
		if _closing:
			visible = false
			_closing = false)


func say(text: String) -> void:
	var net = get_tree().root.get_node_or_null("Net")
	if net and net.term_capture(text):
		return   # (output of a crewmate's command: it goes back to them)
	out.append_text(text + "\n")


func error(text: String) -> void:
	say("[color=#ff4a2a]ERROR: %s[/color]" % text)
	Sfx.play(self, "error", null, -8.0)


func clear() -> void:
	out.clear()
	out.visible_characters = 0


func _process(delta: float) -> void:
	if visible:
		if not input.has_focus() and not _closing:
			_focus()
		_glass.set_shader_parameter("roll", fmod(Time.get_ticks_msec() / 1000.0 * 0.11, 1.0))
		if status_fn.is_valid():
			header.text = status_fn.call()
	if monitor.visible:
		if feed.visible:
			if is_instance_valid(_cam_target):
				feed_cam.global_transform = _cam_target.global_transform.rotated_local(Vector3.UP, _cam_yaw)
				feed_label.text = "%s          REC" % _cam_name
				rec_dot.position = Vector2(feed_label.position.x + feed_label.size.x - 66, feed_label.position.y + feed_label.size.y / 2.0)
				rec_dot.visible = true
				feed_stamp.visible = true
				rec_dot.queue_redraw()
				var m = get_parent()
				var h: float = m.hours if m != null and "hours" in m else 0.0
				feed_stamp.text = "BRM SEC  %02d:%02d:%02d" % [int(h) % 24, int(fmod(h, 1.0) * 60.0), int(fmod(h * 3600.0, 60.0))]
				_glitch = move_toward(_glitch, 0.0, delta * 2.5)
				(feed.material as ShaderMaterial).set_shader_parameter("time_s", Time.get_ticks_msec() / 1000.0)
				(feed.material as ShaderMaterial).set_shader_parameter("glitch", _glitch)
			else:
				feed_label.text = "SIGNAL LOST"
				rec_dot.visible = false
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
	say("\n[color=#ffe2b0][b]> %s[/b][/color]" % line.replace("[", "[lb]"))
	run(line)
	_update_suggest()
	_focus.call_deferred()


## The same as run(), for commands run on someone else's behalf (net.gd).
func run_quiet(line: String) -> void:
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
			if decline.is_valid():
				var d := decline
				decline = Callable()
				d.call()
			else:
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
		KEY_PAGEUP, KEY_PAGEDOWN:
			var bar := out.get_v_scroll_bar()
			bar.value += (-1.0 if e.keycode == KEY_PAGEUP else 1.0) * out.size.y * 0.8
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
