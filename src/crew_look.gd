# The crew editor (title screen): you, in the suit you'll wear, turning slowly under a work lamp
# (drag to turn yourself; WHOLE, HELMET and BACK frame you), and the choices beside it in two
# columns, every one of suit.gd's LOOK: suit, helmet, marking, visor, pack, gloves, boots, tape,
# helmet style, chest kit, wear. Saved with the settings, sent to the crew (net.send_look), worn by
# your body and your sleeves.
#   var c := CrewLook.new(); c.m = <a menu.gd, for its look>; c.main = main; parent.add_child(c); c.open()
extends PanelContainer

signal closed

const Settings = preload("res://src/settings.gd")
const Suit = preload("res://src/suit.gd")
const Sfx = preload("res://src/sfx.gd")

const AMBER := Color(1.0, 0.62, 0.22)
const DIM := Color(0.62, 0.55, 0.45)
const INK := Color(0.95, 0.93, 0.88)

var m
var main
var _vp: SubViewport
var _fig: Node3D
var _turn := PI + 0.4
var _spin := 0.35
var _drag := false
var _refresh: Array[Callable] = []
var _cam: Camera3D
var _frame := 0   # 0 whole, 1 helmet, 2 back
const LABELS := {"suit": "SUIT", "helmet": "HELMET", "mark": "MARKING", "visor": "VISOR", "pack": "ON YOUR BACK", "gloves": "GLOVES",
	"boots": "BOOTS", "trim": "REFLECTIVE TAPE", "style": "HELMET STYLE", "chest": "ON YOUR CHEST", "wear": "WEAR"}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.055, 0.05, 0.97)
	sb.border_color = Color(AMBER, 0.4)
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.set_content_margin_all(28)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_child(m._text("CREW LOOK", 30, INK))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(m._text("FORM 9-C · ISSUE OF CLOTHING", 12, DIM))
	v.add_child(head)
	v.add_child(m._rule())
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 26)
	v.add_child(row)
	# You, on a turntable.
	var box := SubViewportContainer.new()
	box.stretch = true
	box.custom_minimum_size = Vector2(250, 0)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.gui_input.connect(_drag_input)
	row.add_child(box)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_4X
	box.add_child(_vp)
	_stage()
	# The choices.
	var c := VBoxContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_theme_constant_override("separation", 18)
	row.add_child(c)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	c.add_child(grid)
	var lists := Suit.lists()
	for slot in Suit.LOOK:
		var opts: Array = lists[slot]
		_choice(grid, LABELS[slot], "look_" + slot, opts.map(func(e): return e if e is String else e[0]))
	var views := HBoxContainer.new()   # where the camera looks
	views.add_theme_constant_override("separation", 8)
	views.add_child(m._text("VIEW", 13, AMBER))
	for k in 3:
		var vb := Button.new()
		vb.text = ["WHOLE", "HELMET", "BACK"][k]
		vb.theme_type_variation = "SmallButton"
		vb.pressed.connect(func():
			_frame = k
			_turn = 0.0 if k == 2 else PI + 0.4 * float(k == 0)   # (it faces -z, the camera's at +z: PI shows its front)
			_spin = 0.0 if k > 0 else 0.35
			_aim())
		views.add_child(vb)
	c.add_child(views)
	var note: Label = m._text("Your name goes on your chest and on your pack.\nDrag the figure to turn it.", 13, DIM)
	c.add_child(note)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.add_child(fill)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	var rnd := Button.new()
	rnd.text = "SURPRISE ME"
	rnd.theme_type_variation = "SmallButton"
	rnd.pressed.connect(func():
		var ls := Suit.lists()
		for slot in Suit.LOOK:
			Settings.v["look_" + slot] = randi() % (ls[slot] as Array).size()
		_changed())
	foot.add_child(rnd)
	var issue := Button.new()
	issue.text = "BUREAU ISSUE"
	issue.theme_type_variation = "SmallButton"
	issue.pressed.connect(func():
		for slot in Suit.LOOK:
			Settings.v["look_" + slot] = 0
		_changed())
	foot.add_child(issue)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp2)
	var done := Button.new()
	done.text = "DONE"
	done.theme_type_variation = "SmallButton"
	done.pressed.connect(close)
	foot.add_child(done)
	c.add_child(foot)
	visible = false


func open() -> void:
	visible = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_dress()
	for f in _refresh:
		f.call()


func close() -> void:
	if not visible:
		return
	visible = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	Settings.save()
	Sfx.play(self, "click", null, -8.0, 1.1)
	closed.emit()


func _input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func _process(delta: float) -> void:
	if not visible or _fig == null:
		return
	if not _drag:
		_turn += _spin * delta
	_fig.rotation.y = _turn


func _drag_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
	elif e is InputEventMouseMotion and _drag:
		_turn += e.relative.x * 0.012


## A dark booth: a work lamp from above, a warm rim behind, a disc of floor.
func _stage() -> void:
	var w := Node3D.new()
	_vp.add_child(w)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.04, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.55, 0.5)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var key := SpotLight3D.new()
	key.light_color = Color(1.0, 0.88, 0.7)
	key.light_energy = 6.0
	key.spot_range = 8.0
	key.spot_angle = 32.0
	key.shadow_enabled = true
	w.add_child(key)
	key.position = Vector3(0.8, 3.6, 1.6)
	key.look_at_from_position(key.position, Vector3(0, 0.9, 0))
	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.55, 0.2)
	rim.light_energy = 2.0
	rim.omni_range = 4.0
	w.add_child(rim)
	rim.position = Vector3(-1.0, 1.8, -1.4)
	var floor := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.8
	cm.bottom_radius = 0.85
	cm.height = 0.06
	floor.mesh = cm
	floor.material_override = load("res://src/art.gd").mat("grate", Color(0.55, 0.52, 0.48))
	w.add_child(floor)
	floor.position.y = -0.03
	_fig = Node3D.new()
	w.add_child(_fig)
	Suit.standing(_fig)
	_cam = Camera3D.new()
	_cam.fov = 32.0
	w.add_child(_cam)
	_cam.current = true
	_aim()


## The camera on the whole figure, its helmet, or its back (the figure turns its back to it).
func _aim() -> void:
	if _cam == null:
		return
	var at: Vector3 = [Vector3(0, 0.95, 0), Vector3(0, 1.68, 0), Vector3(0, 1.25, 0)][_frame]
	var from: Vector3 = [Vector3(0, 1.15, 4.2), Vector3(0, 1.75, 1.35), Vector3(0, 1.4, 2.3)][_frame]
	_cam.transform = Transform3D(Basis.IDENTITY, from).looking_at(at)


func _dress() -> void:
	var net = get_tree().root.get_node_or_null("Net")
	var who: String = net.my_name if net != null and net.active else String(Settings.v.player_name)
	if who == "":
		who = "EMPLOYEE"
	Suit.apply_look(_fig, Settings.look(), who)


func _changed() -> void:
	_dress()
	for f in _refresh:
		f.call()
	Settings.save()
	var net = get_tree().root.get_node_or_null("Net")
	if net != null:
		net.send_look()
	if main and main.player:
		main.player.dress()
	Sfx.play(self, "rustle", null, -10.0, randf_range(0.9, 1.15))


func _choice(page: Container, label: String, key: String, names: Array) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # (the two columns share the width)
	col.add_theme_constant_override("separation", 6)
	page.add_child(col)
	col.add_child(m._text(label, 13, AMBER))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	col.add_child(h)
	var prev := Button.new()
	prev.text = "◂"
	prev.theme_type_variation = "SmallButton"
	h.add_child(prev)
	var b := Button.new()
	b.theme_type_variation = "SmallButton"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true   # (a long name is cut, not pushing the panel wider)
	b.custom_minimum_size.x = 80
	b.add_theme_font_size_override("font_size", 13)
	h.add_child(b)
	var next := Button.new()
	next.text = "▸"
	next.theme_type_variation = "SmallButton"
	h.add_child(next)
	var swatch := ColorRect.new()   # (the colour itself)
	swatch.custom_minimum_size = Vector2(22, 22)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(swatch)
	var show := func():
		var i := clampi(int(Settings.v.get(key, 0)), 0, names.size() - 1)
		b.text = str(names[i])
		b.tooltip_text = "%s   %d of %d" % [names[i], i + 1, names.size()]
		swatch.visible = true
		var leather := Color(0.4, 0.27, 0.18)
		match key:
			"look_suit": swatch.color = Color(0.74, 0.36, 0.11) if i == 0 else Suit.SUITS[i][1] * Color(0.85, 0.85, 0.85)
			"look_helmet": swatch.color = Suit.HELMETS[i][1]
			"look_visor": swatch.color = (Suit.VISORS[i][1] as Color).lightened(0.15)
			"look_gloves": swatch.color = leather * (Suit.GLOVES[i][2] as Color) if Suit.GLOVES[i][1] == "leather" else Suit.GLOVES[i][2]
			"look_boots": swatch.color = leather * (Suit.BOOTS[i][2] as Color) if Suit.BOOTS[i][1] == "leather" else (Suit.BOOTS[i][2] as Color) * (0.25 if Suit.BOOTS[i][1] == "rubber" else 1.0)
			"look_trim": swatch.color = Suit.TRIMS[i][1] if i < Suit.TRIMS.size() - 1 else Color(0, 0, 0, 0)
			_: swatch.visible = false
	var step := func(d: int):
		Settings.v[key] = posmod(int(Settings.v.get(key, 0)) + d, names.size())
		_changed()
	prev.pressed.connect(step.bind(-1))
	b.pressed.connect(step.bind(1))
	next.pressed.connect(step.bind(1))
	_refresh.append(show)
