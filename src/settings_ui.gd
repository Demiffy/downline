# The settings screen, the same from the pause menu and the title screen: tabs (game, controls,
# video, audio, accessibility), each setting in a row that says what it does at the foot when you
# point at it; changes take at once and are saved on the way out. Controls can be rebound; the
# audio tab picks your devices, shows your mic live against the gate and can set the gate for you.
#   var s := SettingsUI.new(); s.m = <a menu.gd, for its look>; s.main = main; parent.add_child(s)
#   s.open() / s.closed
extends PanelContainer

signal closed

const Settings = preload("res://src/settings.gd")
const Sfx = preload("res://src/sfx.gd")

const AMBER := Color(1.0, 0.62, 0.22)
const DIM := Color(0.62, 0.55, 0.45)
const INK := Color(0.95, 0.93, 0.88)
const GREEN := Color(0.55, 1.0, 0.55)
const TABS := ["GAME", "CONTROLS", "VIDEO", "AUDIO", "ACCESSIBILITY"]

var m          # a menu.gd: its look (labels, rules)
var main
var _pages := {}
var _tab_btns := {}
var _tab := "GAME"
var _keys := {}            # tab -> the settings on it (for RESET TAB)
var _refresh: Array[Callable] = []
var _ticks: Array[Callable] = []
var _desc: Label
var _scroll: ScrollContainer
var _rebinding := ""       # the action waiting for a key
var _rebind_btn: Button
var _cal_t := -1.0         # mic calibration: seconds left, or -1
var _cal_peak := 0.0
var _cal_l: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.055, 0.05, 0.97)
	sb.border_color = Color(AMBER, 0.4)
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 26
	sb.content_margin_bottom = 22
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_child(m._text("SETTINGS", 30, INK))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(m._text("FORM B-7 · EMPLOYEE COMFORT", 12, DIM))
	v.add_child(head)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	v.add_child(tabs)
	v.add_child(m._rule())
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	var pad := MarginContainer.new()   # (clear of the scroll bar)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 26)
	_scroll.add_child(pad)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(pages)
	for t in TABS:
		var b := Button.new()
		b.text = t
		b.toggle_mode = true
		b.theme_type_variation = "TabButton"
		b.pressed.connect(show_tab.bind(t))
		tabs.add_child(b)
		_tab_btns[t] = b
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 10)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pages.add_child(page)
		_pages[t] = page
		_keys[t] = []
	v.add_child(m._rule())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	_desc = m._text("", 13, DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desc.custom_minimum_size.y = 40
	foot.add_child(_desc)
	var reset := Button.new()
	reset.text = "RESET TAB"
	reset.theme_type_variation = "SmallButton"
	reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reset.pressed.connect(_reset_tab)
	_hint(reset, "Put everything on this tab back the way it came.")
	foot.add_child(reset)
	var back := Button.new()
	back.text = "BACK"
	back.theme_type_variation = "SmallButton"
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	foot.add_child(back)
	v.add_child(foot)
	_build_game()
	_build_controls()
	_build_video()
	_build_audio()
	_build_access()
	show_tab("GAME", true)
	visible = false


func open() -> void:
	visible = true
	_rebinding = ""
	for f in _refresh:
		f.call()
	show_tab(_tab, true)
	(func(): _tab_btns[_tab].grab_focus()).call_deferred()


func close() -> void:
	if not visible:
		return
	_stop_rebind()
	_cal_t = -1.0
	Settings.v.mic_test = false
	visible = false
	_meter(false)
	Settings.save()
	Sfx.play(self, "click", null, -8.0, 1.1)
	closed.emit()


func show_tab(t: String, quiet := false) -> void:
	_tab = t
	for k in _pages:
		_pages[k].visible = k == t
		_tab_btns[k].button_pressed = k == t
	_scroll.scroll_vertical = 0
	_desc.text = ""
	_meter(visible and t == "AUDIO")
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f != null and f in _tab_btns.values() and f != _tab_btns[t]:
		_tab_btns[t].grab_focus()   # (the tab you were on would still look picked)
	if not quiet:
		Sfx.play(self, "click", null, -10.0, 1.2)


func _input(e: InputEvent) -> void:
	if not visible:
		return
	if _rebinding != "":   # the next key (or mouse button) is the new one
		if e is InputEventKey and e.pressed and not e.echo:
			get_viewport().set_input_as_handled()
			if e.keycode == KEY_ESCAPE:
				_stop_rebind()
			else:
				_bind(_rebinding, {"k": e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode})
		elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
			get_viewport().set_input_as_handled()
			_bind(_rebinding, {"m": e.button_index})
		return
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func _process(delta: float) -> void:
	if not visible:
		return
	for t in _ticks:
		t.call()
	if _cal_t >= 0.0:
		var vo = _voice()
		if vo != null:
			_cal_peak = maxf(_cal_peak, vo.raw_level)
		_cal_t -= delta
		_cal_l.text = "STAY QUIET... %d" % ceili(maxf(_cal_t, 0.0))
		if _cal_t < 0.0:
			Settings.v.voice_gate = clampf(_cal_peak * 1.7 + 0.0015, 0.002, 0.06)
			_cal_l.text = "GATE SET"
			for f in _refresh:
				f.call()
			Sfx.play(self, "click", null, -6.0, 1.3)


# --- the tabs ------------------------------------------------------------------------------------

func _build_game() -> void:
	var p: VBoxContainer = _pages.GAME
	_section(p, "VIEW")
	_slider(p, "FIELD OF VIEW", "fov", 60.0, 110.0, 1.0, func(x): return "%d°" % x,
		"How wide you see. Wider shows more round you; narrower looks closer.")
	_toggle(p, "CROSSHAIR", "crosshair", "The small ring in the middle of the visor.")
	_slider(p, "HUD OPACITY", "hud_opacity", 0.15, 1.0, 0.05, _pct,
		"How strongly the visor's readouts show: clock, compass, health, slots, messages.")
	_toggle(p, "FPS COUNTER", "show_fps", "Frames per second in the corner.")
	_section(p, "STARTUP")
	_toggle(p, "SHORT INTRO", "skip_intro", "Always play the quick version of the terminal boot when the game starts.")


func _build_controls() -> void:
	var p: VBoxContainer = _pages.CONTROLS
	_section(p, "MOUSE")
	_slider(p, "SENSITIVITY", "sens", 0.2, 3.0, 0.05, func(x): return "%.2fx" % x, "How far the view turns for a move of the mouse.")
	_toggle(p, "INVERT LOOK", "invert_y", "Mouse forward looks down.")
	_section(p, "MOVEMENT")
	_toggle(p, "TOGGLE CROUCH", "crouch_toggle", "Press crouch once to stay down, again to stand. Off: hold it.")
	_toggle(p, "TOGGLE SPRINT", "sprint_toggle", "Press sprint once to run until you stop or run out of breath. Off: hold it.")
	_section(p, "KEYS")
	for b in Settings.BINDABLE:
		_bind_row(p, b[0], b[1])
	_keys.CONTROLS.append("binds")


func _build_video() -> void:
	var p: VBoxContainer = _pages.VIDEO
	_section(p, "DISPLAY")
	_choice(p, "WINDOW", "window_mode", Settings.WINDOW_MODES,
		"FULLSCREEN fills the screen and alt-tabs quickly. EXCLUSIVE can be a little faster but flickers on alt-tab. F11 switches.")
	_toggle(p, "VSYNC", "vsync", "Waits for the screen's refresh: no tearing, a touch more input delay.")
	_choice(p, "FRAME CAP", "fps_cap", Settings.FPS_CAPS.map(func(f): return "NONE" if f == 0 else str(f)),
		"The most frames a second it will draw. A cap keeps a fast card cooler and quieter.")
	_slider(p, "BRIGHTNESS", "brightness", 0.5, 1.8, 0.05, _pct,
		"Raise it until you can just make things out in the dark of a facility; the dark is meant to be dark.")
	_section(p, "QUALITY")
	_choice(p, "PRESET", "quality", Settings.QUALITY,
		"Sets everything below at once. Change any of them and it becomes CUSTOM.", func():
			if int(Settings.v.quality) < Settings.PRESETS.size():
				Settings.use_preset(int(Settings.v.quality))
			else:
				Settings.v.quality = 0
				Settings.use_preset(0)
			_refresh_all())
	var custom := func(): Settings.match_preset(); _refresh_all()
	_slider(p, "RENDER SCALE", "render_scale", 0.5, 1.0, 0.05, _pct,
		"Draws the world at this share of the window and scales it up (FSR). The biggest gain on a slow card.", custom)
	_choice(p, "SHADOWS", "shadows", Settings.SHADOWS, "Shadow sharpness and how soft their edges are.", custom)
	_toggle(p, "AMBIENT OCCLUSION", "ssao", "Darkens corners and creases where light can't reach.", custom)
	_toggle(p, "BOUNCED LIGHT", "gi", "Light spreads as it really does: off the walls and floors, round corners and through doorways, and stays out of rooms walled off from it. Costs a millisecond or two a frame: on in ULTRA.", custom)
	_toggle(p, "GLOW", "glow", "Lights and fire bloom softly.", custom)
	_choice(p, "FOG DETAIL", "fog", ["LOW", "MEDIUM", "HIGH"], "How finely the fog and the light through it are worked out.", custom)
	_choice(p, "ANTI-ALIASING", "aa", Settings.AA,
		"Smooths jagged edges. FXAA is cheap and a bit soft; TAA is smoothest in motion; MSAA is sharp and costly.", custom)


func _build_audio() -> void:
	var p: VBoxContainer = _pages.AUDIO
	_section(p, "VOLUME")
	_slider(p, "MASTER", "vol_master", 0.0, 1.0, 0.01, _pct, "Everything.")
	_slider(p, "EFFECTS", "vol_world", 0.0, 1.0, 0.01, _pct, "The world: steps, machines, creatures, the train.")
	_slider(p, "AMBIENCE", "vol_ambience", 0.0, 1.0, 0.01, _pct, "Wind, rooms humming, the facility settling.")
	_slider(p, "VOICES", "voice_vol", 0.0, 1.5, 0.01, _pct, "Your crew's voices.")
	_section(p, "DEVICES")
	_device(p, "OUTPUT", "out_device", AudioServer.get_output_device_list, "Where the sound comes out. DEFAULT follows Windows.")
	_device(p, "MICROPHONE", "in_device", AudioServer.get_input_device_list, "Which microphone the crew hears. DEFAULT follows Windows.")
	_section(p, "VOICE")
	_toggle(p, "MICROPHONE ON", "mic_on", "Off: nobody hears you (you still hear them).")
	_choice(p, "MODE", "voice_mode", ["OPEN MIC", "PUSH TO TALK"],
		"OPEN MIC sends whenever you're louder than the gate. PUSH TO TALK only while you hold %s." % Settings.key_name("push_to_talk"))
	_slider(p, "MIC LEVEL", "mic_gain", 0.2, 3.0, 0.05, func(x): return "%.1fx" % x, "Turn your microphone up or down before anything else.")
	_slider(p, "OPEN MIC GATE", "voice_gate", 0.001, 0.06, 0.001, func(x): return "%d" % roundi(x * 1000),
		"How loud you must be to be sent: the amber mark on the meter. Too high cuts your words; too low sends your room.")
	_mic_meter(p)
	var h := _row(p, "SET THE GATE", "Stay quiet for three seconds: it listens to your room and puts the gate just above it.")
	var cal := Button.new()
	cal.text = "LISTEN"
	cal.theme_type_variation = "SmallButton"
	cal.custom_minimum_size.x = 130
	h.add_child(cal)
	_cal_l = m._text("", 14, AMBER)
	h.add_child(_cal_l)
	cal.pressed.connect(func():
		_cal_t = 3.0
		_cal_peak = 0.0
		Sfx.play(self, "click", null, -8.0))
	_hook(cal, h)
	_toggle(p, "HEAR MYSELF", "mic_test", "Plays your voice back as the crew gets it (wear headphones).")


func _build_access() -> void:
	var p: VBoxContainer = _pages.ACCESSIBILITY
	_section(p, "MOTION")
	_toggle(p, "HEAD BOB", "head_bob", "The view rocks with your stride.")
	_slider(p, "CAMERA SHAKE", "shake", 0.0, 1.0, 0.05, _pct, "Blasts, falls, heavy machinery. 0% keeps the view still.")
	_section(p, "LIGHT")
	_slider(p, "FLASHES", "flash", 0.0, 1.0, 0.05, _pct, "How bright explosions flash and how red the visor goes when you're hurt.")


# --- rows ----------------------------------------------------------------------------------------

func _section(page: VBoxContainer, title: String) -> void:
	if page.get_child_count() > 0:
		m._gap(page, 8)
	var l: Label = m._text(title, 13, AMBER)
	page.add_child(l)


func _row(page: VBoxContainer, label: String, desc: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.custom_minimum_size.y = 34
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	var l: Label = m._text(label, 16, INK)
	l.custom_minimum_size.x = 250
	h.add_child(l)
	page.add_child(h)
	h.mouse_entered.connect(func(): _desc.text = desc)
	h.set_meta("desc", desc)
	return h


## Pointing at the control (or tabbing to it) tells you about it too.
func _hook(c: Control, row: Control) -> void:
	var d: String = row.get_meta("desc", "")
	c.mouse_entered.connect(func(): _desc.text = d)
	c.focus_entered.connect(func(): _desc.text = d; _scroll.ensure_control_visible(row))


func _hint(c: Control, d: String) -> void:
	c.mouse_entered.connect(func(): _desc.text = d)
	c.focus_entered.connect(func(): _desc.text = d)


func _slider(page: VBoxContainer, label: String, key: String, lo: float, hi: float, step: float, fmt: Callable, desc: String, after := Callable()) -> void:
	_own(page, key)
	var h := _row(page, label, desc)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var val: Label = m._text("", 16, AMBER)
	val.custom_minimum_size.x = 76
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	s.value_changed.connect(func(x):
		Settings.v[key] = x
		val.text = fmt.call(x)
		if after.is_valid():
			after.call()
		Settings.apply(main))
	_hook(s, h)
	_refresh.append(func():
		s.set_value_no_signal(float(Settings.v[key]))
		val.text = fmt.call(float(Settings.v[key])))


func _toggle(page: VBoxContainer, label: String, key: String, desc: String, after := Callable()) -> void:
	_own(page, key)
	var h := _row(page, label, desc)
	var b := Button.new()
	b.theme_type_variation = "SmallButton"
	b.custom_minimum_size.x = 130
	h.add_child(b)
	var show := func():
		b.text = "ON" if Settings.v[key] else "OFF"
		b.add_theme_color_override("font_color", AMBER if Settings.v[key] else DIM)
	b.pressed.connect(func():
		Settings.v[key] = not Settings.v[key]
		show.call()
		if after.is_valid():
			after.call()
		Settings.apply(main)
		Sfx.play(self, "click", null, -8.0))
	_hook(b, h)
	_refresh.append(show)


## One of a few: arrows either side step through them (and clicking the name goes on to the next).
func _choice(page: VBoxContainer, label: String, key: String, names: Array, desc: String, after := Callable()) -> void:
	_own(page, key)
	var h := _row(page, label, desc)
	var prev := Button.new()
	prev.text = "◂"
	prev.theme_type_variation = "SmallButton"
	h.add_child(prev)
	var b := Button.new()
	b.theme_type_variation = "SmallButton"
	b.custom_minimum_size.x = 230
	h.add_child(b)
	var next := Button.new()
	next.text = "▸"
	next.theme_type_variation = "SmallButton"
	h.add_child(next)
	var show := func(): b.text = str(names[clampi(int(Settings.v[key]), 0, names.size() - 1)])
	var step := func(d: int):
		Settings.v[key] = posmod(int(Settings.v[key]) + d, names.size())
		if after.is_valid():
			after.call()
		show.call()
		Settings.apply(main)
		Sfx.play(self, "click", null, -8.0)
	prev.pressed.connect(step.bind(-1))
	b.pressed.connect(step.bind(1))
	next.pressed.connect(step.bind(1))
	for c in [prev, b, next]:
		_hook(c, h)
	_refresh.append(show)


## An audio device by name, from the list there is now (unplugged ones fall back to DEFAULT).
func _device(page: VBoxContainer, label: String, key: String, list: Callable, desc: String) -> void:
	_own(page, key)
	var h := _row(page, label, desc)
	var o := OptionButton.new()
	o.theme_type_variation = "SmallButton"
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.clip_text = true
	h.add_child(o)
	var fill := func():
		o.clear()
		var names: PackedStringArray = list.call()
		var at := 0
		for i in names.size():
			o.add_item(names[i].to_upper().left(48))
			o.set_item_metadata(i, names[i])
			if names[i] == Settings.v[key]:
				at = i
		o.select(at)
	o.item_selected.connect(func(i: int):
		Settings.v[key] = o.get_item_metadata(i)
		Settings.apply(main)
		if key == "in_device":
			var vo = _voice()
			if vo != null and vo.has_method("_restart_mic"):
				vo._restart_mic()
		Sfx.play(self, "click", null, -8.0))
	o.pressed.connect(fill)   # (plugged in since: listed when you open it)
	_hook(o, h)
	_refresh.append(fill)


## Your microphone, live: the raw level against the open-mic gate (the amber mark).
func _mic_meter(page: VBoxContainer) -> void:
	var h := _row(page, "MIC INPUT", "Talk: the bar goes green when you're loud enough to be sent. The amber mark is the gate.")
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 16)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	var to_x := func(rms: float) -> float: return clampf(sqrt(rms / 0.08), 0.0, 1.0) * bar.size.x   # (a square-root scale: quiet levels get room)
	var peak := [0.0]
	bar.draw.connect(func():
		var vo = _voice()
		var raw: float = vo.raw_level if vo != null else 0.0
		var on: bool = raw >= float(Settings.v.voice_gate) and bool(Settings.v.mic_on)
		peak[0] = maxf(raw, peak[0] - 0.0015)
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color(INK, 0.07))
		bar.draw_rect(Rect2(Vector2.ZERO, Vector2(to_x.call(raw), bar.size.y)), Color(GREEN, 0.85) if on else Color(INK, 0.45))
		bar.draw_rect(Rect2(Vector2(to_x.call(peak[0]) - 1.0, 0), Vector2(2, bar.size.y)), Color(INK, 0.6))
		var gx: float = to_x.call(float(Settings.v.voice_gate))
		bar.draw_rect(Rect2(Vector2(gx - 1.5, -4), Vector2(3, bar.size.y + 8)), AMBER)
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color(INK, 0.3), false, 1.0))
	var val: Label = m._text("", 15, AMBER)
	val.custom_minimum_size.x = 76
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	_ticks.append(func():
		if bar.is_visible_in_tree():
			var vo = _voice()
			if vo == null:
				val.text = "NO MIC"
			else:
				val.text = "SENDING" if vo.raw_level >= float(Settings.v.voice_gate) and bool(Settings.v.mic_on) else "--"
			bar.queue_redraw())


func _bind_row(page: VBoxContainer, action: String, label: String) -> void:
	var h := _row(page, label, "Click, then press the key (or a mouse button) you want. Esc leaves it as it was.")
	var b := Button.new()
	b.theme_type_variation = "SmallButton"
	b.custom_minimum_size.x = 200
	h.add_child(b)
	var show := func():
		b.text = Settings.key_name(action)
		var custom: bool = Settings.v.binds.has(action)
		b.add_theme_color_override("font_color", AMBER if custom else INK)
	b.pressed.connect(func():
		_stop_rebind()
		_rebinding = action
		_rebind_btn = b
		b.text = "PRESS A KEY..."
		Sfx.play(self, "click", null, -8.0))
	_hook(b, h)
	_refresh.append(show)


func _bind(action: String, ev: Dictionary) -> void:
	# Already on another action: they swap.
	var old := _encode(Settings.bind_event(action))
	for b in Settings.BINDABLE:
		if b[0] != action and _encode(Settings.bind_event(b[0])) == ev:
			Settings.v.binds[b[0]] = old
	Settings.v.binds[action] = ev
	for b in Settings.BINDABLE:   # (back to the default: not custom any more)
		if Settings.v.binds.has(b[0]) and _encode(Settings.bind_event(b[0])) == {"k": b[2]}:
			Settings.v.binds.erase(b[0])
	Settings.apply_binds()
	_stop_rebind()
	_refresh_all()
	Sfx.play(self, "click", null, -6.0, 1.2)


static func _encode(e: InputEvent) -> Dictionary:
	if e is InputEventMouseButton:
		return {"m": e.button_index}
	return {"k": (e as InputEventKey).physical_keycode}


func _stop_rebind() -> void:
	_rebinding = ""
	_rebind_btn = null
	_refresh_all()


# --- the rest ------------------------------------------------------------------------------------

## Which tab a setting is on (for RESET TAB): the page it's built on.
func _own(page: VBoxContainer, key: String) -> void:
	for t in _pages:
		if _pages[t] == page:
			_keys[t].append(key)


func _reset_tab() -> void:
	for k in _keys[_tab]:
		Settings.v[k] = Settings.DEFAULTS[k].duplicate() if Settings.DEFAULTS[k] is Dictionary else Settings.DEFAULTS[k]
	if _tab == "CONTROLS":
		Settings.apply_binds()
	Settings.apply(main)
	_refresh_all()
	Sfx.play(self, "click", null, -6.0)


func _refresh_all() -> void:
	for f in _refresh:
		f.call()


func _meter(on: bool) -> void:
	var vo = _voice()
	if vo != null:
		vo.meter = on


func _voice():
	var n = get_tree().root.get_node_or_null("Net") if is_inside_tree() else null
	return n.voice if n != null else null


static func _pct(x: float) -> String:
	return "%d%%" % roundi(x * 100)
