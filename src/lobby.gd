# Title screen and crew lobby, in the pause menu's Bureau console style, over the live checkpoint.
#   SOLO SHIFT        play alone (as ever)
#   HOST A CREW       open a port (forward it on your router: UDP, default 24565) and wait for others
#   JOIN A CREW       type the host's address (and port) and connect
# In the lobby everyone sees the crew list; the host starts the shift. People can still join a
# shift that's already under way: they're brought aboard wherever the train is.
extends CanvasLayer

const Settings = preload("res://src/settings.gd")
const Sfx = preload("res://src/sfx.gd")
const Menu = preload("res://src/menu.gd")

const AMBER := Color(1.0, 0.62, 0.22)
const DIM := Color(0.62, 0.55, 0.45)
const INK := Color(0.95, 0.93, 0.88)
const SOOT := Color(0.055, 0.05, 0.045, 0.96)
const RED := Color(1.0, 0.38, 0.28)

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
var _lobby_head: Label
var _hint: Label


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	net = get_tree().root.get_node("Net")
	_m = Menu.new()
	_m.mono.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "monospace"])
	_m.mono.font_weight = 700
	root = Control.new()
	root.theme = _m._theme()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.material = _m._scan_shader()
	root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
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


func _process(_delta: float) -> void:
	if main and main.player:
		main.player.frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if net.started and net.active:
		_close()


func _build() -> void:
	var col := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = SOOT
	sb.border_color = Color(AMBER, 0.55)
	sb.border_width_right = 2
	sb.content_margin_left = 56
	sb.content_margin_right = 44
	sb.content_margin_bottom = 40
	col.add_theme_stylebox_override("panel", sb)
	root.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_right = 600
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
	v.add_child(_m._text("SUBTERRA", 56, INK))
	_m._gap(v, 4)
	v.add_child(_m._text("RAILNET FIELD SERVICE  ·  SHIFT ROSTER", 14, AMBER))
	_m._gap(v, 16)
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
	var solo: Button = _m._action("SOLO SHIFT")
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
	hr.add_child(_m._text("(forward it, UDP)", 13, Color(DIM, 0.8)))
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
	_start_btn = _m._action("START THE SHIFT")
	_start_btn.pressed.connect(_start)
	_lobby_box.add_child(_start_btn)
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
	_hint = _m._text("Voices carry: talk to the crew with your microphone (V for push-to-talk in SETTINGS).\nWalls muffle them. So does distance. Things down there can hear you too.", 13, Color(DIM, 0.85))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 480
	v.add_child(_hint)


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
	else:
		_lobby_head.text = "CREW" if net.active else "CONNECTING..."
		_crew.text = ("\n".join(lines) + "\n\nWaiting for the host to start the shift.") if net.active and not ids.is_empty() else "Reaching %s ..." % _addr_in.text
		_start_btn.visible = false


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


func _start() -> void:
	Sfx.play(main, "horn", null, -6.0)
	net.start()
	_close()


func _on_failed(why: String) -> void:
	_status.text = why
	_show_title()


func _close() -> void:
	if main and main.player:
		main.player.frozen = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()
