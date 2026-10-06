# Pause menu (Esc) and settings, styled as a Bureau field console: hazard stripe, stencil-ish mono type,
# amber on soot. Pauses the whole tree; this layer keeps running. Settings apply live, save on close.
extends CanvasLayer

const Settings = preload("res://src/settings.gd")
const Sfx = preload("res://src/sfx.gd")

const AMBER := Color(1.0, 0.62, 0.22)
const DIM := Color(0.62, 0.55, 0.45)
const INK := Color(0.95, 0.93, 0.88)
const SOOT := Color(0.055, 0.05, 0.045, 0.96)
const TIPS := [
	"Crouch near anything that listens. Footsteps carry further than you think.",
	"A gas mask in your pack keeps the air in gassed rooms breathable.",
	"Live cables arc through flood water. Cut the power, or keep your feet dry.",
	"When the lights die, the breaker panel is somewhere on site. Find it.",
	"Steam lines hiss before they burst. Time it, or crouch under the jet.",
	"Tremors shake things loose. Some of what falls is worth picking up.",
	"A red flare on the surface means the Bureau dropped something. Others will hear it too.",
	"Heavy scrap needs both hands. Plan the route before you lift it.",
	"The train leaves at midnight. The train has never once been late.",
]

var main
var root: Control
var left: VBoxContainer
var settings_panel: PanelContainer
var status_l: Label
var tip_l: Label
var _pages := {}       # tab name -> VBoxContainer
var _tab_btns := {}
var _confirm := ""     # which button is waiting for a second press
var _buttons := {}
var _prev_mouse := Input.MOUSE_MODE_CAPTURED
var mono := SystemFont.new()


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	mono.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "monospace"])
	mono.font_weight = 700
	root = Control.new()
	root.theme = _theme()
	root.visible = false
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()   # the game behind, darkened and scanlined
	shade.material = _scan_shader()
	root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_left()
	_build_settings()


# --- open / close ---------------------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE):
		return
	get_viewport().set_input_as_handled()
	if not root.visible:
		open()
	elif settings_panel.visible:
		_show_settings(false)
	else:
		close()


func open() -> void:
	if root.visible:
		return
	_prev_mouse = Input.mouse_mode
	get_tree().paused = true
	root.visible = true
	_show_settings(false)
	_confirm = ""
	_relabel()
	tip_l.text = "FIELD NOTE\n" + TIPS[randi() % TIPS.size()]
	status_l.text = _status()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_buttons.resume.grab_focus.call_deferred()
	Sfx.play(self, "click", null, -8.0, 0.8)


func close() -> void:
	if not root.visible:
		return
	root.visible = false
	Settings.save()
	get_tree().paused = false
	Input.mouse_mode = _prev_mouse
	Sfx.play(self, "click", null, -8.0, 1.1)


func is_open() -> bool:
	return root.visible


func _status() -> String:
	if main == null:
		return ""
	var where: String = "CHECKPOINT" if main.at_checkpoint else "STATION %s  ·  %s" % [main.stop.get("letter", "?"), main.stop.get("theme", "")]
	var t := "--:--" if main.at_checkpoint else "%02d:%02d" % [int(main.hours) % 24, int(fmod(main.hours, 1.0) * 60.0)]
	return "ASSIGNMENT %d   ·   %s\nSHIFT CLOCK %s   ·   CREDITS %d   ·   VITALS %d%%" % [main.assignment, where, t, main.credits, roundi(main.player.hp)]


# --- left column: header, status, actions, tip ------------------------------------------------

func _build_left() -> void:
	var col := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = SOOT
	sb.border_color = Color(AMBER, 0.55)
	sb.border_width_right = 2
	sb.content_margin_left = 56
	sb.content_margin_right = 44
	sb.content_margin_top = 0
	sb.content_margin_bottom = 40
	col.add_theme_stylebox_override("panel", sb)
	root.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_right = 520
	left = VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	col.add_child(left)
	var stripe := Control.new()   # hazard stripe across the top
	stripe.custom_minimum_size = Vector2(0, 18)
	stripe.draw.connect(func(): _hazard(stripe))
	left.add_child(stripe)
	_gap(left, 54)
	left.add_child(_text("BUREAU OF RECLAIMED MATERIALS", 14, DIM))
	_gap(left, 6)
	left.add_child(_text("SHIFT PAUSED", 46, INK))
	_gap(left, 14)
	left.add_child(_rule())
	_gap(left, 12)
	status_l = _text("", 15, AMBER)
	left.add_child(status_l)
	_gap(left, 12)
	left.add_child(_rule())
	_gap(left, 40)
	for b in [["resume", "RESUME SHIFT"], ["settings", "SETTINGS"], ["restart", "RESTART RUN"], ["quit", "QUIT TO DESKTOP"]]:
		var btn := _action(b[1])
		btn.pressed.connect(_on_action.bind(b[0]))
		_buttons[b[0]] = btn
		left.add_child(btn)
		_gap(left, 6)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(fill)
	tip_l = _text("", 14, DIM)
	tip_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_l.custom_minimum_size.x = 400
	left.add_child(tip_l)
	_gap(left, 18)
	left.add_child(_text("ESC  resume      ↑↓  select      ENTER  confirm", 12, Color(DIM, 0.7)))


func _on_action(what: String) -> void:
	Sfx.play(self, "click", null, -6.0)
	match what:
		"resume":
			close()
		"settings":
			_show_settings(not settings_panel.visible)
		"restart", "quit":
			if _confirm != what:   # dangerous ones take a second press
				_confirm = what
				_relabel()
				return
			Settings.save()
			get_tree().paused = false
			if what == "quit":
				get_tree().quit()
			else:
				get_tree().reload_current_scene()


func _relabel() -> void:
	_buttons.restart.text = "  CONFIRM: LOSE THIS RUN?" if _confirm == "restart" else "  RESTART RUN"
	_buttons.quit.text = "  CONFIRM: QUIT GAME?" if _confirm == "quit" else "  QUIT TO DESKTOP"
	for k in ["restart", "quit"]:
		for c in ["font_color", "font_hover_color", "font_focus_color"]:
			if _confirm == k:
				_buttons[k].add_theme_color_override(c, Color(1, 0.35, 0.25))
			else:
				_buttons[k].remove_theme_color_override(c)


# --- settings ---------------------------------------------------------------------------------

func _build_settings() -> void:
	settings_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.065, 0.06, 0.97)
	sb.border_color = Color(AMBER, 0.4)
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.set_content_margin_all(34)
	settings_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(settings_panel)
	settings_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	settings_panel.offset_left = 580
	settings_panel.offset_right = 1220
	settings_panel.offset_top = -300
	settings_panel.offset_bottom = 300
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	settings_panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(_text("SETTINGS", 30, INK))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(_text("FORM B-7 · EMPLOYEE COMFORT", 12, DIM))
	v.add_child(head)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	v.add_child(tabs)
	v.add_child(_rule())
	_gap(v, 6)
	for t in ["CONTROLS", "VIDEO", "AUDIO"]:
		var b := Button.new()
		b.text = t
		b.toggle_mode = true
		b.theme_type_variation = "TabButton"
		b.pressed.connect(_tab.bind(t))
		tabs.add_child(b)
		_tab_btns[t] = b
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 14)
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(page)
		_pages[t] = page
	var c: VBoxContainer = _pages.CONTROLS
	_slider(c, "MOUSE SENSITIVITY", "sens", 0.2, 3.0, 0.05, func(x): return "%.2fx" % x)
	_toggle(c, "INVERT LOOK", "invert_y")
	_toggle(c, "HEAD BOB", "head_bob")
	c.add_child(_text("\nW A S D move   SHIFT sprint   CTRL crouch   SPACE jump\nE use / hold to pry   Q drop   C drop equipment   F scan\n1-6 / wheel slots   CLICK use item   ESC this menu\nFULLSCREEN  F11 · ALT+ENTER · CMD+CTRL+F (Mac)", 13, DIM))
	var vid: VBoxContainer = _pages.VIDEO
	_toggle(vid, "FULLSCREEN", "fullscreen")
	_toggle(vid, "VSYNC", "vsync")
	_slider(vid, "FIELD OF VIEW", "fov", 60.0, 110.0, 1.0, func(x): return "%d°" % x)
	_slider(vid, "BRIGHTNESS", "brightness", 0.5, 1.8, 0.05, func(x): return "%d%%" % roundi(x * 100))
	_cycle(vid, "QUALITY", "quality", ["LOW", "MEDIUM", "HIGH"])
	vid.add_child(_text("LOW renders at 67% and drops ambient occlusion and glow.\nMEDIUM renders at 85% without ambient occlusion.", 13, DIM))
	var aud: VBoxContainer = _pages.AUDIO
	var pct := func(x): return "%d%%" % roundi(x * 100)
	_slider(aud, "MASTER", "vol_master", 0.0, 1.0, 0.01, pct)
	_slider(aud, "EFFECTS", "vol_world", 0.0, 1.0, 0.01, pct)
	_slider(aud, "AMBIENCE", "vol_ambience", 0.0, 1.0, 0.01, pct)
	var foot := HBoxContainer.new()
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp2)
	var reset := Button.new()
	reset.text = "RESTORE DEFAULTS"
	reset.theme_type_variation = "SmallButton"
	reset.pressed.connect(func():
		Settings.v = Settings.DEFAULTS.duplicate()
		Settings.apply(main)
		_rebuild_values()
		Sfx.play(self, "click", null, -6.0))
	foot.add_child(reset)
	var back := Button.new()
	back.text = "BACK"
	back.theme_type_variation = "SmallButton"
	back.pressed.connect(_show_settings.bind(false))
	foot.add_child(back)
	v.add_child(foot)
	_tab("CONTROLS")
	settings_panel.visible = false


func _show_settings(on: bool) -> void:
	settings_panel.visible = on
	if on:
		_rebuild_values()
		_tab_btns.CONTROLS.grab_focus.call_deferred()
	else:
		Settings.save()
		if root.visible:
			_buttons.settings.grab_focus.call_deferred()


func _tab(t: String) -> void:
	for k in _pages:
		_pages[k].visible = k == t
		_tab_btns[k].button_pressed = k == t
	Sfx.play(self, "click", null, -10.0, 1.2)


var _refresh: Array[Callable] = []

func _rebuild_values() -> void:
	for f in _refresh:
		f.call()


func _row(page: VBoxContainer, label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := _text(label, 16, INK)
	l.custom_minimum_size.x = 230
	h.add_child(l)
	page.add_child(h)
	return h


func _slider(page: VBoxContainer, label: String, key: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	var h := _row(page, label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var val := _text("", 16, AMBER)
	val.custom_minimum_size.x = 70
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	s.value_changed.connect(func(x):
		Settings.v[key] = x
		val.text = fmt.call(x)
		Settings.apply(main))
	_refresh.append(func():
		s.set_value_no_signal(float(Settings.v[key]))
		val.text = fmt.call(float(Settings.v[key])))


func _toggle(page: VBoxContainer, label: String, key: String) -> void:
	var h := _row(page, label)
	var b := Button.new()
	b.theme_type_variation = "SmallButton"
	b.custom_minimum_size.x = 120
	h.add_child(b)
	var show := func(): b.text = "[ ON  ]" if Settings.v[key] else "[ OFF ]"
	b.pressed.connect(func():
		Settings.v[key] = not Settings.v[key]
		show.call()
		Settings.apply(main)
		Sfx.play(self, "click", null, -8.0))
	_refresh.append(show)


func _cycle(page: VBoxContainer, label: String, key: String, names: Array) -> void:
	var h := _row(page, label)
	var b := Button.new()
	b.theme_type_variation = "SmallButton"
	b.custom_minimum_size.x = 160
	h.add_child(b)
	var show := func(): b.text = "◂ %s ▸" % names[int(Settings.v[key])]
	b.pressed.connect(func():
		Settings.v[key] = (int(Settings.v[key]) + 1) % names.size()
		show.call()
		Settings.apply(main)
		Sfx.play(self, "click", null, -8.0))
	_refresh.append(show)


# --- look ------------------------------------------------------------------------------------

func _text(s: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_override("font", mono)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l


func _gap(box: BoxContainer, h: float) -> void:
	var g := Control.new()
	g.custom_minimum_size.y = h
	box.add_child(g)


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(AMBER, 0.35)
	r.custom_minimum_size.y = 1
	return r


func _action(s: String) -> Button:
	var b := Button.new()
	b.text = "  " + s
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(400, 52)
	b.mouse_entered.connect(func(): b.grab_focus())
	b.focus_entered.connect(func(): Sfx.play(self, "key", null, -12.0))
	return b


func _hazard(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	c.draw_rect(Rect2(-56, 0, w + 100, h), Color(0.08, 0.07, 0.05))   # bleed over the panel margins
	var x := -56.0 - h
	while x < w + 44.0:
		c.draw_colored_polygon(PackedVector2Array([Vector2(x, h), Vector2(x + h, 0), Vector2(x + h * 1.8, 0), Vector2(x + h * 0.8, h)]), Color(0.92, 0.66, 0.12, 0.85))
		x += h * 2.0
	c.draw_rect(Rect2(-56, h - 2, w + 100, 2), Color(0, 0, 0, 0.5))


func _scan_shader() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec3 c = textureLod(screen, SCREEN_UV, 1.5).rgb;
	float g = dot(c, vec3(0.3, 0.55, 0.15));
	c = mix(vec3(g) * vec3(1.0, 0.85, 0.7), c, 0.25) * 0.45;   // desaturated, sepia, dark
	c *= 0.9 + 0.1 * sin(FRAGCOORD.y * 2.2);                   // scanlines
	float v = distance(SCREEN_UV, vec2(0.5));
	c *= 1.0 - v * 0.9;
	COLOR = vec4(c, 1.0);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _flat(bg: Color, border: Color, left := 0, all := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(all)
	if left > 0:
		s.border_width_left = left
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _theme() -> Theme:
	var t := Theme.new()
	t.default_font = mono
	t.default_font_size = 16
	var flat := _flat
	# Big actions: bare text; hover/focus gets an amber bar and a warm wash.
	t.set_stylebox("normal", "Button", flat.call(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	t.set_stylebox("hover", "Button", flat.call(Color(AMBER, 0.1), AMBER, 5))
	t.set_stylebox("focus", "Button", flat.call(Color(AMBER, 0.1), AMBER, 5))
	t.set_stylebox("pressed", "Button", flat.call(Color(AMBER, 0.22), AMBER, 5))
	t.set_font_size("font_size", "Button", 24)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", AMBER)
	t.set_color("font_focus_color", "Button", AMBER)
	t.set_color("font_pressed_color", "Button", AMBER)
	t.set_color("font_hover_pressed_color", "Button", AMBER)
	# Small boxed buttons (toggles, back, defaults).
	t.set_type_variation("SmallButton", "Button")
	t.set_stylebox("normal", "SmallButton", flat.call(Color(1, 1, 1, 0.04), Color(AMBER, 0.35), 0, 1))
	t.set_stylebox("hover", "SmallButton", flat.call(Color(AMBER, 0.14), AMBER, 0, 1))
	t.set_stylebox("focus", "SmallButton", flat.call(Color(AMBER, 0.14), AMBER, 0, 1))
	t.set_stylebox("pressed", "SmallButton", flat.call(Color(AMBER, 0.25), AMBER, 0, 1))
	t.set_font_size("font_size", "SmallButton", 15)
	# Tabs: underlined when selected.
	t.set_type_variation("TabButton", "Button")
	var tab_on := flat.call(Color(AMBER, 0.12), AMBER) as StyleBoxFlat
	tab_on.border_width_bottom = 3
	t.set_stylebox("normal", "TabButton", flat.call(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	t.set_stylebox("hover", "TabButton", flat.call(Color(AMBER, 0.08), Color(0, 0, 0, 0)))
	t.set_stylebox("focus", "TabButton", flat.call(Color(AMBER, 0.08), Color(AMBER, 0.6), 0, 1))
	t.set_stylebox("pressed", "TabButton", tab_on)
	t.set_stylebox("hover_pressed", "TabButton", tab_on)
	t.set_font_size("font_size", "TabButton", 16)
	t.set_color("font_color", "TabButton", DIM)
	t.set_color("font_pressed_color", "TabButton", AMBER)
	# Sliders: thin track, amber fill, a chunky lever grabber.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.12)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(AMBER, 0.85)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var img := Image.create(12, 24, false, Image.FORMAT_RGBA8)
	img.fill(INK)
	img.fill_rect(Rect2i(0, 0, 12, 2), AMBER)
	img.fill_rect(Rect2i(0, 22, 12, 2), AMBER)
	var grab := ImageTexture.create_from_image(img)
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", grab)
	return t
