# Pause menu (Esc) and settings, styled as a Bureau field console: hazard stripe, stencil-ish mono type,
# amber on soot. Pauses the whole tree; this layer keeps running. Settings apply live, save on close.
extends CanvasLayer

const Settings = preload("res://src/settings.gd")
const SettingsUI = preload("res://src/settings_ui.gd")
const Save = preload("res://src/save.gd")
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
var settings_panel   # settings_ui.gd
var album: Control         # the run's photographs, to the right of the buttons
var _album_grid: GridContainer
var _album_head: Label
var _album_n := -1
var _zoom: Control         # one photo, held up close
var status_l: Label
var tip_l: Label
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
	_build_album()
	_build_settings()


# --- open / close ---------------------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE):
		return
	get_viewport().set_input_as_handled()
	if not root.visible:
		open()
	elif _zoom.visible:
		_zoom.visible = false
	elif settings_panel.visible:
		_show_settings(false)
	else:
		close()


func _net():
	return get_tree().root.get_node_or_null("Net")


## With a crew the world doesn't stop for one person.
func _solo() -> bool:
	var n = _net()
	return n == null or not n.active


func open() -> void:
	if root.visible:
		return
	_prev_mouse = Input.mouse_mode
	get_tree().paused = _solo()
	if main and main.player:
		main.player.frozen = true
	root.visible = true
	_show_settings(false)
	_confirm = ""
	_relabel()
	tip_l.text = "FIELD NOTE\n" + TIPS[randi() % TIPS.size()]
	_fill_album()
	_zoom.visible = false
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
	if main and main.player and not (main.term.visible and not main.term._closing):
		main.player.frozen = false
	Input.mouse_mode = _prev_mouse
	Sfx.play(self, "click", null, -8.0, 1.1)


func is_open() -> bool:
	return root.visible


func _status() -> String:
	if main == null:
		return ""
	var where: String = "CHECKPOINT" if main.at_checkpoint else "STATION %s  ·  %s" % [main.stop.get("letter", "?"), main.stop.get("theme", "")]
	var crew := ""
	if not _solo():
		crew = "\nCREW: " + ", ".join(_net().roster.values().map(func(r): return r.name))
	return "ASSIGNMENT %d   ·   %s\nCREDITS %d   ·   VITALS %d%%%s" % [main.assignment, where, main.credits, roundi(main.player.hp), crew]


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
	for b in [["resume", "RESUME SHIFT"], ["settings", "SETTINGS"], ["title", "SAVE & EXIT TO TITLE"], ["restart", "RESTART RUN"], ["leave", "LEAVE CREW"], ["quit", "QUIT TO DESKTOP"]]:
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


func _on_action(what: String) -> void:
	Sfx.play(self, "click", null, -6.0)
	match what:
		"resume":
			close()
		"settings":
			_show_settings(not settings_panel.visible)
		"title":
			var ok: bool = main != null and main.autosave()
			Settings.save()
			get_tree().paused = false
			if not ok and main != null and main.autosaves:
				main.hud.alert("Saved on arrival (the train was moving).")
			if not _solo():
				_net().leave()
			get_tree().reload_current_scene()
		"restart", "quit", "leave":
			if what == "restart" and not _solo() and not _net().is_host:
				return   # (the host restarts for everyone)
			if _confirm != what:   # dangerous ones take a second press
				_confirm = what
				_relabel()
				return
			Settings.save()
			get_tree().paused = false
			if what == "quit":
				if main != null:
					main.autosave()   # (the run's kept: CONTINUE on the title screen)
				get_tree().quit()
			elif what == "leave":
				_net().leave()
				get_tree().reload_current_scene()
			else:
				if main != null and main.autosaves:
					Save.delete(main.save_path)
				if not _solo():
					_net().event("restart")
				get_tree().reload_current_scene()


func _relabel() -> void:
	_buttons.restart.text = "  CONFIRM: LOSE THIS RUN?" if _confirm == "restart" else "  RESTART RUN"
	_buttons.quit.text = "  CONFIRM: QUIT GAME?" if _confirm == "quit" else "  QUIT TO DESKTOP"
	_buttons.leave.text = "  CONFIRM: LEAVE THE CREW?" if _confirm == "leave" else "  LEAVE CREW"
	_buttons.leave.visible = not _solo()
	_buttons.restart.visible = _solo() or _net().is_host
	_buttons.title.visible = _solo() or _net().is_host
	_buttons.title.text = "  SAVE & EXIT TO TITLE" if _solo() else "  SAVE & END THE SHIFT   (everyone)"
	if _confirm != "quit":
		_buttons.quit.text = "  SAVE & QUIT TO DESKTOP" if _solo() or _net().is_host else "  QUIT TO DESKTOP"
	_buttons.resume.text = "  RESUME SHIFT" if _solo() else "  BACK TO WORK   (the shift goes on)"
	for k in ["restart", "quit", "leave"]:
		for c in ["font_color", "font_hover_color", "font_focus_color"]:
			if _confirm == k:
				_buttons[k].add_theme_color_override(c, Color(1, 0.35, 0.25))
			else:
				_buttons[k].remove_theme_color_override(c)


# --- the run's photographs ----------------------------------------------------------------------

## Every photograph the observer took this run, as prints on a board. Click one to hold it up.
func _build_album() -> void:
	album = Control.new()
	root.add_child(album)
	album.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	album.offset_left = 580
	album.offset_right = -48
	album.offset_top = 72
	album.offset_bottom = -48
	album.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	album.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_album_head = _text("PHOTOGRAPHS  ·  THIS RUN", 22, INK)
	v.add_child(_album_head)
	v.add_child(_text("Taken by the observer. Pick them up down there, pin them up aboard.", 13, DIM))
	v.add_child(_rule())
	_gap(v, 10)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_album_grid = GridContainer.new()
	_album_grid.columns = 4
	_album_grid.add_theme_constant_override("h_separation", 26)
	_album_grid.add_theme_constant_override("v_separation", 30)
	scroll.add_child(_album_grid)
	# The print held up close.
	_zoom = Control.new()
	_zoom.visible = false
	root.add_child(_zoom)
	_zoom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	_zoom.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_zoom.visible = false)


func _fill_album() -> void:
	var photos: Array = main.photo_log if main != null else []
	var cols := clampi(int((get_viewport().get_visible_rect().size.x - 640.0) / 236.0), 2, 6)
	_album_grid.columns = cols
	if photos.size() == _album_n:
		return
	_album_n = photos.size()
	for c in _album_grid.get_children():
		c.queue_free()
	_album_head.text = "PHOTOGRAPHS  ·  THIS RUN  ·  %d" % photos.size()
	if photos.is_empty():
		_album_grid.add_child(_text("None yet. Something down there carries a camera.", 15, Color(DIM, 0.8)))
		return
	for i in photos.size():
		_album_grid.add_child(_print(photos[i], 210.0, i, true))


## A glossy print: white border, the picture, the stamp along the bottom, a little crooked.
func _print(e: Dictionary, w: float, i: int, clickable: bool) -> Control:
	var h := w * 1.08
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(w, h)
	var card := Control.new()
	holder.add_child(card)
	card.size = Vector2(w, h)
	card.pivot_offset = card.size / 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = i * 7919 + 17
	card.rotation = deg_to_rad(rng.randf_range(-4.0, 4.0)) if clickable else 0.0
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.5)
	shadow.position = Vector2(5, 7)
	shadow.size = card.size
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(shadow)
	var paper := ColorRect.new()
	paper.color = Color(0.93, 0.92, 0.87)
	paper.size = card.size
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(paper)
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.position = Vector2(w * 0.05, w * 0.05)
	pic.size = Vector2(w * 0.9, w * 0.78)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(pic)
	if e.has("tex"):
		pic.texture = e.tex
	else:   # nothing came out: a dark, blank print
		var blank := ColorRect.new()
		blank.color = Color(0.12, 0.11, 0.1)
		blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.add_child(blank)
		blank.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stamp := _text(e.get("stamp", ""), int(w * 0.062), Color(0.2, 0.22, 0.45))
	stamp.position = Vector2(w * 0.06, w * 0.86)
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(stamp)
	if clickable:
		var hit := Button.new()   # (the whole print is a button: hover lifts it, click holds it up)
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.size = card.size
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.add_child(hit)
		hit.mouse_entered.connect(func(): create_tween().tween_property(card, "scale", Vector2.ONE * 1.06, 0.12))
		hit.mouse_exited.connect(func(): create_tween().tween_property(card, "scale", Vector2.ONE, 0.12))
		hit.pressed.connect(func(): _hold_up(e, i))
	return holder


func _hold_up(e: Dictionary, i: int) -> void:
	for c in _zoom.get_children():
		if c is not ColorRect:
			c.queue_free()
	var vs := get_viewport().get_visible_rect().size
	var w := minf(vs.x * 0.5, (vs.y - 120.0) / 1.08)
	var p := _print(e, w, i, false)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom.add_child(p)
	p.position = (vs - Vector2(w, w * 1.08)) / 2.0
	var hint := _text("click or ESC to put it back", 13, DIM)
	_zoom.add_child(hint)
	hint.position = Vector2(vs.x / 2.0 - 120.0, vs.y - 44.0)
	_zoom.visible = true
	Sfx.play(self, "rustle", null, -8.0, 1.3)


# --- settings ---------------------------------------------------------------------------------

func _build_settings() -> void:
	settings_panel = SettingsUI.new()
	settings_panel.m = self
	settings_panel.main = main
	root.add_child(settings_panel)
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.offset_left = 580
	settings_panel.offset_right = -48
	settings_panel.offset_top = 70
	settings_panel.offset_bottom = -70
	settings_panel.closed.connect(func():
		album.visible = true
		if root.visible:
			_buttons.settings.grab_focus.call_deferred())


func _show_settings(on: bool) -> void:
	album.visible = not on
	if on:
		settings_panel.open()
	else:
		settings_panel.close()


func _tab(t: String) -> void:
	settings_panel.show_tab(t)


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
