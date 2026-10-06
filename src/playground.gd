# Monster playground: the real game, dropped straight into a facility with debug tools.
#   godot --path . -- playground [FACTORY|LAB|FLESH|BACKROOMS]
# TAB opens the spawn panel (click a monster to drop it where you're looking). Hotkeys below.
extends CanvasLayer

const Data = preload("res://src/data.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")

const SPAWNS := [
	["Roomba", "res://src/roomba.gd"], ["Pulsator", "res://src/pulsator.gd"], ["Statue", "res://src/statue.gd"],
	["Marionette", "res://src/marionette.gd"], ["Mimic", "res://src/mimic.gd"], ["Warden", "res://src/warden.gd"],
	["Scrapper", "res://src/scrapper.gd"], ["Gloe", "res://src/gloe.gd"], ["Bear trap", "res://src/bear_trap.gd"],
	["Snatcher (ceiling)", "res://src/snatcher.gd"], ["Leviathan (surface)", "res://src/leviathan.gd"],
]
const ENUMS := ["IDLE", "RUMBLE", "WARN", "ERUPT", "PATROL", "HUNT", "SEARCH", "HIDE", "BITE", "FLEE"]
const KEYS := """[TAB] panel: spawns + every tool as a button (no F-keys needed on a Mac)      [F1] god mode %s      [F2] freeze monsters %s      [F3] state labels %s
[F4] clear monsters      [F5] day / night      [F6] slow motion %s      [F7] noclip fly %s
[F8 / N] make a noise at the crosshair      [F9] surface / facility      [F10] new facility (%s)      [G] spawn scrap"""

var main
var theme := "FACTORY"
var god := true
var frozen := false
var labels := true
var slow := false
var fly := false
var panel: PanelContainer
var help: Label
var _tags := {}   # monster -> Label3D
var _ready_done := false


func _ready() -> void:
	layer = 4
	var args := OS.get_cmdline_user_args()
	for a in args:
		if String(a).to_upper() in ["FACTORY", "LAB", "FLESH", "BACKROOMS"]:
			theme = String(a).to_upper()
	help = Label.new()
	help.add_theme_font_size_override("font_size", 15)
	help.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	help.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	help.add_theme_constant_override("shadow_offset_x", 2)
	help.add_theme_constant_override("shadow_offset_y", 2)
	add_child(help)
	help.position = Vector2(40, 210)
	_build_panel()
	_go_below(true)


# --- setup -----------------------------------------------------------------------------------

func _go_below(first: bool) -> void:
	Engine.set_meta("fast_test", true)   # quick travel animations
	if first:
		for i in 20:
			await get_tree().process_frame
		main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0] if first else main.stop
	stop.theme = theme
	stop.rooms = 18
	stop.weather = "CLEAR"
	if first:
		main.player.global_position = Vector3(0, 1.3, 0)
		main.term.run("ROUTE_TO " + stop.letter)
	else:
		main.level.queue_free()
		main.level = null
		await get_tree().process_frame
		main._load_level(stop)
	while main.busy:
		await get_tree().process_frame
	Engine.remove_meta("fast_test")
	_clear()
	var p = main.player
	if not p.slots.any(func(it): return it != null and it.id == "FLASHLIGHT"):
		p.slots[0] = {"id": "FLASHLIGHT", "charge": 99999.0}
		p.sel = 0
	_drop_into_facility()
	main.hud.msg("PLAYGROUND: %s facility. TAB to spawn monsters." % theme)
	_ready_done = true


func _drop_into_facility() -> void:
	var el = main.level.elevator
	if el.at_top:
		el.cab.position.y = el.bottom
		el.at_top = false
		el._set_doors(true)
	main.player.global_position = el.cab.global_position + Vector3(0, 0.3, -4.0)
	main.player.velocity = Vector3.ZERO


func _build_panel() -> void:
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.06, 0.92)
	sb.border_color = Color(0.4, 1.0, 0.6)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	panel.visible = false
	add_child(panel)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -40
	panel.offset_left = -40   # zero width; grows left to fit its buttons
	panel.offset_top = 130
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	panel.add_child(cols)
	var box := VBoxContainer.new()
	cols.add_child(box)
	var title := Label.new()
	title.text = "SPAWN AT CROSSHAIR"
	title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	box.add_child(title)
	for s in SPAWNS:
		var b := Button.new()
		b.text = s[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_spawn.bind(s[1]))
		box.add_child(b)
	box = VBoxContainer.new()   # second column: tools + rebuilds
	cols.add_child(box)
	var tools := Label.new()
	tools.text = "TOOLS"
	tools.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	box.add_child(tools)
	# Every hotkey as a button too (Mac F-keys need Fn, and F11 is taken by macOS).
	for t in [["God mode", KEY_F1], ["Freeze monsters", KEY_F2], ["State labels", KEY_F3], ["Clear monsters", KEY_F4],
			["Day / night", KEY_F5], ["Slow motion", KEY_F6], ["Noclip fly", KEY_F7], ["Surface / facility", KEY_F9], ["Spawn scrap", KEY_G]]:
		var b := Button.new()
		b.text = t[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_hotkey.bind(t[1]))
		box.add_child(b)
	var events := Label.new()
	events.text = "EVENTS"
	events.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	box.add_child(events)
	for t in [["Power failure", func(): main.level.hazards.power_fail()], ["Reset breaker", func(): main.level.hazards.restore()],
			["Tremor", func(): main.level.hazards.tremor()], ["Airdrop (surface)", func(): main.level.hazards.airdrop()],
			["Go to breaker", func(): _go_to(main.level.hazards.breaker)]]:
		var b := Button.new()
		b.text = t[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(t[1])
		box.add_child(b)
	for t in ["FACTORY", "LAB", "FLESH", "BACKROOMS"]:
		var b := Button.new()
		b.text = "Rebuild as " + t
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): theme = t; _ready_done = false; _go_below(false))
		box.add_child(b)


# --- tools -----------------------------------------------------------------------------------

func _go_to(n: Node3D) -> void:
	if n == null:
		return
	main.player.global_position = n.global_position + n.global_transform.basis.z * -1.6 + Vector3(0, 0.3, 0)
	main.player.velocity = Vector3.ZERO

## Where the crosshair lands (up to 25 m), pulled back off walls a little.
func _aim() -> Vector3:
	var cam: Camera3D = main.player.cam
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * 25.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [main.player.get_rid()]
	var hit: Dictionary = main.player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return to
	return hit.position + hit.normal * 0.6


func _floor_below(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.5, 0), p - Vector3(0, 30, 0), 1)
	var hit: Dictionary = main.player.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else p


func _spawn(path: String) -> void:
	var lvl = main.level
	if lvl == null:
		return
	var at := _floor_below(_aim())
	if at.distance_to(main.player.global_position) < 2.5 and not path.ends_with("gloe.gd"):
		main.hud.msg("Too close: aim further away to spawn.")
		Sfx.play(main, "error", null, -8.0)
		return
	var m = load(path).new()
	m.main = main
	if "level" in m:
		m.level = lvl
	lvl.add_child(m)
	match path.get_file():
		"snatcher.gd":
			var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.5, 0), at + Vector3(0, 10, 0), 1)
			var hit: Dictionary = main.player.get_world_3d().direct_space_state.intersect_ray(q)
			m.global_position = hit.position if not hit.is_empty() else at + Vector3(0, 4, 0)
		"bear_trap.gd":
			m.global_position = at
		"gloe.gd":
			m.global_position = at + Vector3(0, 1.5, 0)
		"leviathan.gd":
			m.global_position = Vector3.ZERO
			m.state = m.RUMBLE
			m._t = 0.0
			main.hud.msg("Leviathan is listening. Make a noise on the surface (F8) - it only hunts topside.")
		_:
			m.global_position = at + Vector3(0, 0.05, 0)
	Sfx.play(main, "beep", null, -8.0)


func _clear() -> void:
	if main.level == null:
		return
	for n in main.level.get_children():
		var sc: Script = n.get_script()
		if sc and (n.is_in_group("monsters") or sc.resource_path.get_file() in ["bear_trap.gd", "snatcher.gd", "gloe.gd", "leviathan.gd"]):
			n.queue_free()
	_tags.clear()


func _noise_at_crosshair() -> void:
	var at := _aim()
	main.noise(at, 12.0)
	Sfx.play(main, "clank", at, 4.0)
	var ring := MeshInstance3D.new()   # show how far it carried
	var tm := TorusMesh.new()
	tm.inner_radius = 11.8
	tm.outer_radius = 12.0
	ring.mesh = tm
	ring.material_override = B.mat(Color(0.4, 1, 0.6), 3.0)
	main.add_child(ring)
	ring.global_position = _floor_below(at) + Vector3(0, 0.1, 0)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * 0.05, 0.0)
	tw.tween_property(ring, "scale", Vector3.ONE, 0.5)
	tw.tween_callback(ring.queue_free)


func _input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo) or main.term.visible:
		return
	if _hotkey(e.keycode):
		get_viewport().set_input_as_handled()


## Runs a tool. Returns false if the key isn't one of ours.
func _hotkey(key: int) -> bool:
	match key:
		KEY_TAB:
			panel.visible = not panel.visible
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if panel.visible else Input.MOUSE_MODE_CAPTURED
			main.player.frozen = panel.visible
		KEY_F1: god = not god
		KEY_F2:
			frozen = not frozen
			for m in _monsters():
				m.process_mode = Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT
		KEY_F3: labels = not labels
		KEY_F4: _clear()
		KEY_F5: main.hours = 22.0 if main.hours < 20.0 else 9.0
		KEY_F6:
			slow = not slow
			Engine.time_scale = 0.3 if slow else 1.0
		KEY_F7:
			fly = not fly
			main.player.collision_mask = 0 if fly else 1
		KEY_F8, KEY_N: _noise_at_crosshair()
		KEY_F9:
			if main.player.global_position.y < -20.0:
				main.player.global_position = main.level.elevator_pos + Vector3(0, 0.5, -6.0)
			else:
				_drop_into_facility()
		KEY_F10:
			theme = ["FACTORY", "LAB", "FLESH", "BACKROOMS"][(["FACTORY", "LAB", "FLESH", "BACKROOMS"].find(theme) + 1) % 4]
			_ready_done = false
			_go_below(false)
		KEY_G:
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			main.spawn_item(Data.random_scrap(rng), _aim() + Vector3(0, 0.5, 0))
		_:
			return false
	return true


func _monsters() -> Array:
	if main.level == null:
		return []
	return main.level.get_children().filter(func(n): return n.get_script() != null and (n.is_in_group("monsters") or String(n.get_script().resource_path.get_file()) in ["bear_trap.gd", "snatcher.gd", "gloe.gd", "leviathan.gd"]))


func _process(delta: float) -> void:
	if main == null:
		return
	var p = main.player
	if god:
		p.hp = maxf(p.hp, 100.0)
		p.stamina = p.max_stamina
		p.trapped = null
	if fly and not p.frozen:   # noclip: fly where you look
		var dir := Vector3.ZERO
		var basis: Basis = p.cam.global_transform.basis
		if Input.is_action_pressed("move_forward"): dir -= basis.z
		if Input.is_action_pressed("move_back"): dir += basis.z
		if Input.is_action_pressed("move_left"): dir -= basis.x
		if Input.is_action_pressed("move_right"): dir += basis.x
		if Input.is_action_pressed("jump"): dir += Vector3.UP
		if Input.is_action_pressed("crouch"): dir -= Vector3.UP
		p.velocity = dir.normalized() * (14.0 if Input.is_action_pressed("sprint") else 6.0)
	help.text = KEYS % ["ON" if god else "off", "ON" if frozen else "off", "ON" if labels else "off", "ON" if slow else "off", "ON" if fly else "off", theme] \
		+ "\nmonsters: %d      time %02d:%02d" % [_monsters().size(), int(main.hours) % 24, int(fmod(main.hours, 1.0) * 60)]
	_update_tags()


## A floating readout over every monster: what it is, what it's doing, how far away.
func _update_tags() -> void:
	for m in _tags.keys():
		if not is_instance_valid(m):
			_tags.erase(m)
	for m in _monsters():
		if not _tags.has(m):
			var l := Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.fixed_size = true
			l.pixel_size = 0.0009
			l.font_size = 22
			l.modulate = Color(0.6, 1, 0.7)
			l.outline_size = 6
			m.add_child(l)
			l.position.y = 2.6
			_tags[m] = l
		var tag: Label3D = _tags[m]
		tag.visible = labels
		if labels:
			tag.text = "%s  %.0fm\n%s" % [m.get_script().resource_path.get_file().get_basename().to_upper(), m.global_position.distance_to(main.player.global_position), _state_of(m)]


func _state_of(m: Node) -> String:
	var bits := PackedStringArray()
	if "state" in m:
		var names: Dictionary = m.get_script().get_script_constant_map()
		var s = m.state
		var label := str(s)
		for k in names:
			if k in ENUMS and names[k] == s:
				label = k
		bits.append(label)
	for k in ["awake", "standing", "chasing"]:
		if k in m and m.get(k):
			bits.append(k.to_upper())
	if "armed" in m and m.armed >= 0.0:
		bits.append("ARMED %.1f" % m.armed)
	if "fuse" in m and m.fuse > 0.0:
		bits.append("fuse %.1f" % m.fuse)
	if "fleeing" in m and m.fleeing > 0.0:
		bits.append("fleeing")
	if "friend" in m and m.friend != null:
		bits.append("following you")
	if "cooldown" in m and m.cooldown > 0.0:
		bits.append("cooldown %.0f" % m.cooldown)
	return "  ".join(bits) if not bits.is_empty() else "idle"
