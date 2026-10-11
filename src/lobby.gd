# Title screen and crew lobby, in the pause menu's Bureau console style, over slow cinematic shots of
# the checkpoint (title_cam.gd); starting the shift flies the camera into your eyes.
#   SOLO SHIFT        play alone (as ever)
#   HOST A CREW       open a port (forward it on your router: UDP, default 24565) and wait for others
#   JOIN A CREW       type the host's address (and port) and connect
# In the lobby everyone sees the crew list; the host starts the shift. People can still join a
# shift that's already under way: they're brought aboard wherever the train is.
extends CanvasLayer

const Settings = preload("res://src/settings.gd")
const Sfx = preload("res://src/sfx.gd")
const Menu = preload("res://src/menu.gd")
const Save = preload("res://src/save.gd")
const Version = preload("res://src/version.gd")
const TitleCam = preload("res://src/title_cam.gd")
const Intro = preload("res://src/intro.gd")
const SettingsUI = preload("res://src/settings_ui.gd")   # (for its logo: the launcher's copy, which is fine)

const AMBER := Color(1.0, 0.62, 0.22)
const DIM := Color(0.62, 0.55, 0.45)
const INK := Color(0.95, 0.93, 0.88)
const SOOT := Color(0.055, 0.05, 0.045, 0.96)
const RED := Color(1.0, 0.38, 0.28)
const LOGO_H := 46.0

var main
var net
var root: Control
var _m          # a menu.gd, unparented, for its look (theme, labels, stripes)
var _title_box: VBoxContainer
var _lobby_box: VBoxContainer
var _name_in: LineEdit
var _addr_in: LineEdit
var _port_in: LineEdit
var _status: Label
var _crew: Label
var _start_btn: Button
var _cont_btn: Button       # (title) carry on with the saved run, alone
var _cont_l: Label
var _cont_host: Button      # (lobby) the host carries on with the saved run, with the crew
var _saved := {}
var _lobby_head: Label
var _cam: Camera3D
var _col: Control          # the menu column
var _back: Control         # the wash, vignette, bars and caption behind it
var _bars: Array = []      # letterbox
var _caption: Label
var _logo: Control
var _logo_t := 0.0
var _closing := false
var _settings   # settings_ui.gd
var _look       # crew_look.gd


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	net = main.net if main else load("res://src/net.gd").get_or_make(get_tree())   # /root/Net is added deferred, so it may not be in the tree yet
	_m = Menu.new()
	_m.mono.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "monospace"])
	_m.mono.font_weight = 700
	root = Control.new()
	root.theme = _m._theme()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop()
	_build()
	_settings = SettingsUI.new()   # (over the shots, beside the menu)
	_settings.m = _m
	_settings.main = main
	root.add_child(_settings)
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings.offset_left = 640
	_settings.offset_right = -48
	_settings.offset_top = 80
	_settings.offset_bottom = -80
	_look = load("res://src/crew_look.gd").new()
	_look.m = _m
	_look.main = main
	root.add_child(_look)
	_look.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_look.offset_left = 640
	_look.offset_right = -48
	_look.offset_top = 80
	_look.offset_bottom = -80
	_enter()
	net.roster_changed.connect(_refresh)
	net.joined.connect(_refresh)
	net.failed.connect(_on_failed)
	if Settings.v.player_name == "":
		Settings.v.player_name = "EMPLOYEE %d" % (randi() % 900 + 100)
	_name_in.text = Settings.v.player_name
	_addr_in.text = Settings.v.last_ip
	_port_in.text = str(Settings.v.last_port)
	_show_title()


func _exit_tree() -> void:
	if _m:
		_m.free()


func _process(delta: float) -> void:
	if main and main.player:
		main.player.frozen = true
	if _closing:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_logo_t += delta
	_logo.queue_redraw()
	if net.started and net.active:
		_close()


func _build() -> void:
	var col := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT   # (the backdrop's wash is its ground)
	sb.content_margin_left = 56
	sb.content_margin_right = 44
	sb.content_margin_bottom = 76   # (clear of the letterbox)
	col.add_theme_stylebox_override("panel", sb)
	root.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_right = 600
	_col = col
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	col.add_child(v)
	var stripe := Control.new()
	stripe.custom_minimum_size = Vector2(0, 18)
	stripe.draw.connect(func(): _m._hazard(stripe))
	v.add_child(stripe)
	_m._gap(v, 50)
	v.add_child(_m._text("BUREAU OF RECLAIMED MATERIALS", 14, DIM))
	_m._gap(v, 6)
	_m._gap(v, 10)
	_logo = Control.new()   # the intro's DOWNLINE, drawn in again by its line
	_logo.custom_minimum_size = Vector2(Intro.logo_geom(LOGO_H).width, LOGO_H * 1.55)
	_logo.draw.connect(_draw_logo)
	v.add_child(_logo)
	_m._gap(v, 8)
	v.add_child(_m._text("RAILNET FIELD SERVICE  ·  SHIFT ROSTER", 14, AMBER))
	_m._gap(v, 4)
	v.add_child(_m._text("BUILD %s  ·  %s" % [Version.BUILD, OS.get_name().to_upper()], 11, DIM))
	_m._gap(v, 12)
	v.add_child(_m._rule())
	_m._gap(v, 22)
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 14)
	var nl: Label = _m._text("NAME ON THE ROSTER", 15, DIM)
	nl.custom_minimum_size.x = 210
	nr.add_child(nl)
	_name_in = _field("EMPLOYEE", 16)
	nr.add_child(_name_in)
	v.add_child(nr)
	_m._gap(v, 18)
	# Title: the three ways in.
	_title_box = VBoxContainer.new()
	_title_box.add_theme_constant_override("separation", 6)
	v.add_child(_title_box)
	_saved = Save.peek(main.save_path) if main != null else {}
	_cont_btn = _m._action("CONTINUE RUN")
	_cont_btn.pressed.connect(_continue)
	_title_box.add_child(_cont_btn)
	_cont_l = _m._text("", 13, AMBER)
	_title_box.add_child(_cont_l)
	_cont_btn.visible = not _saved.is_empty()
	_cont_l.visible = _cont_btn.visible
	if not _saved.is_empty():
		_cont_l.text = "     ASSIGNMENT %d  ·  %s  ·  %02d:%02d  ·  %d CR%s" % [_saved.assignment, _saved.where, int(_saved.hours) % 24, int(fmod(_saved.hours, 1.0) * 60.0), _saved.credits,
			("\n     crew: " + ", ".join(_saved.crew)) if not _saved.crew.is_empty() else ""]
		_m._gap(_title_box, 8)
	var solo: Button = _m._action("NEW SOLO SHIFT" if not _saved.is_empty() else "SOLO SHIFT")
	solo.pressed.connect(_solo)
	_title_box.add_child(solo)
	var host: Button = _m._action("HOST A CREW")
	host.pressed.connect(_host)
	_title_box.add_child(host)
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 14)
	var pl: Label = _m._text("     PORT", 14, DIM)
	pl.custom_minimum_size.x = 120
	hr.add_child(pl)
	_port_in = _field("24565", 6)
	_port_in.custom_minimum_size.x = 120
	hr.add_child(_port_in)
	_title_box.add_child(hr)
	_m._gap(_title_box, 10)
	var join: Button = _m._action("JOIN A CREW")
	join.pressed.connect(_join)
	_title_box.add_child(join)
	var jr := HBoxContainer.new()
	jr.add_theme_constant_override("separation", 14)
	var al: Label = _m._text("     ADDRESS", 14, DIM)
	al.custom_minimum_size.x = 120
	jr.add_child(al)
	_addr_in = _field("host address  (ip or ip:port)", 64)
	_addr_in.text_submitted.connect(func(_t): _join())
	jr.add_child(_addr_in)
	_title_box.add_child(jr)
	_m._gap(_title_box, 10)
	var looks: Button = _m._action("CREW LOOK")
	looks.pressed.connect(_toggle_look)
	_title_box.add_child(looks)
	var sets: Button = _m._action("SETTINGS")
	sets.pressed.connect(func():
		_look.close()
		if _settings.visible:
			_settings.close()
		else:
			_settings.open())
	_title_box.add_child(sets)
	var quit: Button = _m._action("QUIT TO DESKTOP")
	quit.pressed.connect(func(): get_tree().quit())
	_title_box.add_child(quit)
	# Lobby: the crew, and the host's START.
	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 8)
	v.add_child(_lobby_box)
	_lobby_head = _m._text("CREW", 30, INK)
	_lobby_box.add_child(_lobby_head)
	_crew = _m._text("", 18, AMBER)
	_lobby_box.add_child(_crew)
	_m._gap(_lobby_box, 14)
	_cont_host = _m._action("CONTINUE THE SAVED RUN")
	_cont_host.pressed.connect(_start.bind(true))
	_lobby_box.add_child(_cont_host)
	_start_btn = _m._action("START A NEW SHIFT" if not _saved.is_empty() else "START THE SHIFT")
	_start_btn.pressed.connect(_start)
	_lobby_box.add_child(_start_btn)
	var looks2: Button = _m._action("CREW LOOK")
	looks2.pressed.connect(_toggle_look)
	_lobby_box.add_child(looks2)
	var back: Button = _m._action("LEAVE")
	back.pressed.connect(func():
		net.leave()
		_show_title())
	_lobby_box.add_child(back)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	_status = _m._text("", 15, RED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 480
	v.add_child(_status)
	_m._gap(v, 12)


func _field(placeholder: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_override("font", _m.mono)
	e.add_theme_font_size_override("font_size", 18)
	e.add_theme_color_override("font_color", INK)
	e.add_theme_color_override("caret_color", AMBER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.border_color = Color(AMBER, 0.45)
	sb.set_border_width_all(1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	e.add_theme_stylebox_override("normal", sb)
	var sf := sb.duplicate()
	sf.border_color = AMBER
	e.add_theme_stylebox_override("focus", sf)
	return e


func _save_fields() -> void:
	Settings.v.player_name = _name_in.text.strip_edges()
	Settings.v.last_ip = _addr_in.text.strip_edges()
	Settings.v.last_port = int(_port_in.text) if _port_in.text.is_valid_int() else 24565
	Settings.save()


func _show_title() -> void:
	_title_box.visible = true
	_lobby_box.visible = false
	_name_in.editable = true


func _show_lobby() -> void:
	_title_box.visible = false
	_lobby_box.visible = true
	_name_in.editable = false
	_refresh()


func _refresh() -> void:
	if not _lobby_box.visible:
		return
	var lines := PackedStringArray()
	var ids: Array = net.roster.keys()
	ids.sort()
	for id in ids:
		lines.append("%s  %s%s" % ["▸" if id == net.me() else " ", net.roster[id].name, "   (HOST)" if id == 1 else ""])
	if net.is_host:
		_lobby_head.text = "CREW  ·  %d / %d" % [ids.size(), net.MAX_PLAYERS]
		_crew.text = "\n".join(lines) + "\n\nOthers join with your address and port %s.\nForward UDP %s on your router to play over the internet." % [_port_in.text, _port_in.text]
		_start_btn.visible = true
		_cont_host.visible = not _saved.is_empty()
	else:
		_lobby_head.text = "CREW" if net.active else "CONNECTING..."
		_crew.text = ("\n".join(lines) + "\n\nWaiting for the host to start the shift.") if net.active and not ids.is_empty() else "Reaching %s ..." % _addr_in.text
		_start_btn.visible = false
		_cont_host.visible = false


func _continue() -> void:
	_save_fields()
	Sfx.play(main, "click", null, -6.0)
	net.leave()
	if not main.continue_run():
		_status.text = "That save couldn't be read."
		return
	_close()


func _solo() -> void:
	_save_fields()
	Sfx.play(main, "click", null, -6.0)
	net.leave()
	_close()


func _host() -> void:
	_save_fields()
	var port := int(_port_in.text) if _port_in.text.is_valid_int() else 24565
	var err: String = net.host(port, _name_in.text)
	if err != "":
		_status.text = err
		return
	_status.text = ""
	_show_lobby()


func _join() -> void:
	_save_fields()
	var addr := _addr_in.text.strip_edges()
	var port := int(_port_in.text) if _port_in.text.is_valid_int() else 24565
	if ":" in addr and addr.count(":") == 1:   # ip:port
		port = int(addr.get_slice(":", 1))
		addr = addr.get_slice(":", 0)
	if addr == "":
		_status.text = "Type the host's address first."
		return
	var err: String = net.join(addr, port, _name_in.text)
	if err != "":
		_status.text = err
		return
	_status.text = ""
	_show_lobby()


func _start(carry_on := false) -> void:
	Sfx.play(main, "horn", null, -16.0)
	if carry_on and not main.continue_run():
		_status.text = "That save couldn't be read."
		return
	net.start()
	_close()


func _on_failed(why: String) -> void:
	_status.text = why
	_show_title()


## Off the screen: the menu slides away, the bars open, and the camera flies into your eyes.
func _close() -> void:
	if _closing:
		return
	_closing = true
	if _settings.visible:
		_settings.close()
	_look.close()
	_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in _col.find_children("*", "Control", true, false):
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE   # (nothing more to click on the way out)
	var tw := create_tween().set_parallel().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_col, "position:x", -140.0, 0.45)
	tw.tween_property(_col, "modulate:a", 0.0, 0.4)
	tw.tween_property(_back, "modulate:a", 0.0, 0.9)
	if _cam and main and main.player:
		_cam.fly_to(main.player.cam, 1.3)
		await _cam.arrived
	else:
		await tw.finished
	if main:
		if main.player:
			main.player.frozen = false
			main.player.cam.current = true
			main.player.dress()   # (with the name you're on the roster as)
		main.hud.visible = true
	if _cam:
		_cam.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()


## Behind the menu: the camera, a dark wash rising from the left for the menu to sit on, a
## vignette, letterbox bars, and a caption naming the shot.
func _backdrop() -> void:
	if main:
		main.hud.visible = false
		_cam = TitleCam.new()
		_cam.origin = main.train.global_transform
		_cam.ears = main.player.cam.global_transform if main.player else _cam.origin
		# The world's sounds come up gently rather than all at once with the menu (no pop).
		for name in ["World", "Ambience"]:
			var bus := AudioServer.get_bus_index(name)
			if bus >= 0:
				var to := AudioServer.get_bus_volume_db(bus)
				AudioServer.set_bus_volume_db(bus, -60.0)
				create_tween().tween_method(func(db: float): AudioServer.set_bus_volume_db(bus, db), -60.0, to, 1.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		_cam.shot_changed.connect(_on_shot)
		main.add_child(_cam)
	_back = Control.new()
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_back)
	_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var wash := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.42, 0.75, 1.0])
	g.colors = PackedColorArray([Color(SOOT, 0.93), Color(SOOT, 0.82), Color(SOOT, 0.25), Color(SOOT, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	wash.texture = gt
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.add_child(wash)
	wash.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	wash.offset_right = 1000
	var vig := ColorRect.new()
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment() {\n\tfloat v = smoothstep(0.45, 1.0, distance(UV, vec2(0.6, 0.5)) * 1.3);\n\tCOLOR = vec4(0.03, 0.025, 0.02, v * 0.7);\n}"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	vig.material = mat
	_back.add_child(vig)
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0.02, 0.018, 0.015)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_back.add_child(bar)
		bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.offset_top = 0.0
		bar.offset_bottom = 0.0
		_bars.append(bar)
	_caption = _m._text("", 13, Color(INK, 0.8))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_back.add_child(_caption)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_caption.offset_left = -900
	_caption.offset_right = -48
	_caption.offset_top = -100
	_caption.offset_bottom = -72
	_caption.modulate.a = 0.0


## Coming on: the bars close in, the menu slides in, its lines one after another.
func _enter() -> void:
	var tw := create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_bars[0], "offset_bottom", 52.0, 1.4)
	tw.tween_property(_bars[1], "offset_top", -52.0, 1.4)
	_col.position.x = -60.0
	_col.modulate.a = 0.0
	tw.tween_property(_col, "position:x", 0.0, 0.9).set_delay(0.2)
	tw.tween_property(_col, "modulate:a", 1.0, 0.7).set_delay(0.2)
	var i := 0
	for c in _col.get_child(0).get_children():
		if c is Control and c.visible:
			c.modulate.a = 0.0
			tw.tween_property(c, "modulate:a", 1.0, 0.5).set_delay(0.3 + 0.04 * i)
			i += 1


func _toggle_look() -> void:
	if _look.visible:
		_look.close()
	else:
		_settings.close()
		_look.open()


func _on_shot(caption: String) -> void:
	var tw := create_tween()
	tw.tween_property(_caption, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		var clock := ""
		if main:
			clock = "     %02d:%02d" % [int(main.hours) % 24, int(fmod(main.hours, 1.0) * 60.0)]
		_caption.text = caption + clock)
	tw.tween_interval(0.4)
	tw.tween_property(_caption, "modulate:a", 1.0, 1.0)


func _draw_logo() -> void:
	var t := _logo_t - 0.45   # (once the menu's in)
	var run := clampf(t / 0.9, 0.0, 1.0)
	var split := clampf((t - 0.9) / 0.35, 0.0, 1.0)
	Intro.draw_logo(_logo, Vector2(0, 0), LOGO_H, 1.0 - pow(1.0 - run, 2.4), 1.0 - pow(1.0 - split, 3.0),
		exp(-(t - 0.9) * 4.0) if t > 0.9 else 0.0, 70.0, 0.0)
