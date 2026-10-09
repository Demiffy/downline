# Monster playground: the real game, dropped straight into a facility with debug tools.
#   godot --path . -- playground [FACTORY|LAB|FLESH|BACKROOMS]
# (F8 makes a noise; N stays night vision.)
# TAB opens the tool panel (CREATURES / ITEMS / PLAYER / WORLD): click a creature or an item to
# drop it where you're looking. A slim status strip shows what's switched on; H hides it.
# Styled like the pause menu (menu.gd's theme): amber on soot.
extends CanvasLayer

const Data = preload("res://src/data.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")

const SPAWNS := [
	["Roomba", "res://src/roomba.gd"], ["Pulsator", "res://src/pulsator.gd"], ["Statue", "res://src/statue.gd"],
	["Marionette", "res://src/marionette.gd"], ["Mimic", "res://src/mimic.gd"], ["Warden", "res://src/warden.gd"],
	["Scrapper", "res://src/scrapper.gd"], ["Gloe", "res://src/gloe.gd"], ["Bear trap", "res://src/bear_trap.gd"],
	["Snatcher", "res://src/snatcher.gd"], ["Leviathan", "res://src/leviathan.gd"],
	["Observer", "res://src/observer.gd"], ["Wraith", "res://src/wraith.gd"],
	["Siren", "res://src/siren.gd"], ["Husk", "res://src/husk.gd"],
]
const NOTES := {   # a line under the creature grid for the ones that need explaining
	"siren.gd": "Siren: steals voices from voice chat. Alone, it fakes a sound instead.",
	"leviathan.gd": "Leviathan: surface only. Make a noise topside (F8).",
	"snatcher.gd": "Snatcher: goes on the ceiling above the crosshair.",
}
const ENUMS := ["IDLE", "RUMBLE", "WARN", "ERUPT", "PATROL", "HUNT", "SEARCH", "HIDE", "BITE", "FLEE", "LURK", "FOLLOW", "CHARGE",
	"DRIFT", "STALK", "BURN", "GONE", "LUNGE", "WANDER", "APPROACH", "STARE", "ATTACK"]
const THEMES := ["FACTORY", "LAB", "FLESH", "BACKROOMS"]
const AMBER := Color(1.0, 0.62, 0.22)
const DIM := Color(0.62, 0.55, 0.45)
const INK := Color(0.95, 0.93, 0.88)
const GREEN := Color(0.45, 1.0, 0.55)
const SOOT := Color(0.055, 0.05, 0.045, 0.99)

var main
var theme := "FACTORY"
var god := true
var frozen := false
var labels := true
var slow := false
var fly := false
var bright := false
var paths = null   # pathdebug.gd while the path gizmos are on
var panel: PanelContainer
var strip: PanelContainer
var status: RichTextLabel
var help: RichTextLabel     # (kept for tests: the status text)
var _pages := {}
var _tab_btns := {}
var _toggles := {}          # name -> Button (toggle_mode), kept in step with the state
var _note: Label
var _tags := {}   # monster -> Label3D
var _ready_done := false
var _station := {}          # the stop we built (to come back to from the checkpoint)


func _ready() -> void:
	layer = 4
	for a in OS.get_cmdline_user_args():
		if String(a).to_upper() in THEMES:
			theme = String(a).to_upper()
	_build_strip()
	_build_panel()
	_go_below(true)


# --- setup -----------------------------------------------------------------------------------

func _go_below(first: bool) -> void:
	Engine.set_meta("fast_test", true)   # quick travel animations
	if first:
		for i in 20:
			await get_tree().process_frame
		main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0] if first else (_station if not _station.is_empty() else main.stop)
	stop.theme = theme
	stop.rooms = 18
	stop.weather = "CLEAR"
	_station = stop
	if first:
		main.player.global_position = Vector3(0, 1.3, 0)
		main.term.run("ROUTE_TO " + stop.letter)
	else:
		_rebuild(stop)
	while main.busy:
		await get_tree().process_frame
	Engine.remove_meta("fast_test")
	_clear()
	var p = main.player
	if not p.slots.any(func(it): return it != null and it.id == "FLASHLIGHT"):
		p.slots[0] = {"id": "FLASHLIGHT", "charge": 99999.0}
		p.sel = 0
	_drop_into_facility()
	main.hud.msg("PLAYGROUND: %s facility. TAB for the tools, H hides the strip." % theme)
	_ready_done = true


func _rebuild(stop: Dictionary) -> void:
	if main.level != null:
		main.level.queue_free()
		main.level = null
	main._load_level(stop)


func _drop_into_facility() -> void:
	var el = main.level.elevator
	if el == null:
		return
	if el.at_top:
		el.cab.position.y = el.bottom
		el.at_top = false
		el._set_doors(true)
	main.player.global_position = el.cab.global_position + Vector3(0, 0.3, -4.0)
	main.player.velocity = Vector3.ZERO


## The checkpoint, to try the shredder: some scrap in the hopper and you at the lever.
func _go_checkpoint() -> void:
	_clear()
	_rebuild(main.CHECKPOINT_STOP)
	await get_tree().process_frame
	var lvl = main.level
	for id in ["ENGINE_BLOCK", "TYPEWRITER", "COPPER_PIPE", "WRENCH", "TOY_TRUCK"]:
		if Data.ITEMS.has(id):
			main.spawn_item(id, lvl.to_global(Vector3(randf_range(-0.7, 0.7), 1.8, randf_range(12.5, 13.5))), -1.0, lvl)
	main.player.global_position = lvl.to_global(Vector3(3.5, 0.3, 9.6))
	main.player.rotation.y = PI   # (facing the lever and the hopper)
	main.player.velocity = Vector3.ZERO
	main.hud.msg("CHECKPOINT: scrap's in the hopper. Throw the MAIN DRIVE lever (E).")


# --- the status strip --------------------------------------------------------------------------

func _build_strip() -> void:
	strip = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(SOOT, 0.82)
	sb.border_color = Color(AMBER, 0.6)
	sb.border_width_left = 3
	sb.content_margin_left = 12
	sb.content_margin_right = 14
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	strip.add_theme_stylebox_override("panel", sb)
	add_child(strip)
	strip.position = Vector2(40, 262)
	status = RichTextLabel.new()
	status.bbcode_enabled = true
	status.fit_content = true
	status.scroll_active = false
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.custom_minimum_size = Vector2(560, 0)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Menlo", "DejaVu Sans Mono", "monospace"])
	status.add_theme_font_override("normal_font", mono)
	status.add_theme_font_size_override("normal_font_size", 13)
	status.add_theme_color_override("default_color", DIM)
	strip.add_child(status)
	help = status


func _chip(name: String, key: String, on: bool) -> String:
	return "[color=#%s]%s %s[/color][color=#6b6050] %s[/color]" % [(GREEN if on else Color(DIM, 0.75)).to_html(false), "●" if on else "○", name, key]


func _refresh_strip() -> void:
	var where := "CHECKPOINT" if main.at_checkpoint else "%s  ·  %s" % [theme, "SURFACE" if main.player.global_position.y > -20.0 else "FACILITY"]
	var t := "[color=#%s]PLAYGROUND[/color]  ·  %s  ·  creatures %d  ·  %02d:%02d      [color=#%s]TAB[/color] tools   [color=#%s]H[/color] hide\n" % [
		AMBER.to_html(false), where, _monsters().size(), int(main.hours) % 24, int(fmod(main.hours, 1.0) * 60.0), AMBER.to_html(false), AMBER.to_html(false)]
	t += "   ".join([_chip("GOD", "F1", god), _chip("FREEZE", "F2", frozen), _chip("LABELS", "F3", labels), _chip("SLOW", "F6", slow),
		_chip("NOCLIP", "F7", fly), _chip("BRIGHT", "B", bright), _chip("PATHS", "P", paths != null)])
	status.text = t


# --- the panel ---------------------------------------------------------------------------------

func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.theme = main.menu._theme()
	var sb := StyleBoxFlat.new()
	sb.bg_color = SOOT
	sb.border_color = Color(AMBER, 0.55)
	sb.border_width_left = 2
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 0
	sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	panel.visible = false
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -470
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var stripe := Control.new()   # hazard stripe across the top
	stripe.custom_minimum_size = Vector2(0, 12)
	stripe.draw.connect(func():
		var w := stripe.size.x + 44.0
		for i in int(w / 22.0) + 2:
			var x := -22.0 + i * 22.0
			stripe.draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + 11, 0), Vector2(x + 23, 12), Vector2(x + 12, 12)]), Color(0.85, 0.6, 0.12)))
	v.add_child(stripe)
	var head := HBoxContainer.new()
	head.add_child(main.menu._text("PLAYGROUND", 26, INK))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(main.menu._text("DEBUG · TAB to close", 12, DIM))
	v.add_child(head)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	v.add_child(tabs)
	v.add_child(main.menu._rule())
	for t in ["CREATURES", "ITEMS", "PLAYER", "WORLD"]:
		var b := Button.new()
		b.text = t
		b.toggle_mode = true
		b.theme_type_variation = "TabButton"
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_tab.bind(t))
		tabs.add_child(b)
		_tab_btns[t] = b
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		v.add_child(scroll)
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 6)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(page)
		_pages[t] = scroll
	_creatures_page(_pages.CREATURES.get_child(0))
	_items_page(_pages.ITEMS.get_child(0))
	_player_page(_pages.PLAYER.get_child(0))
	_world_page(_pages.WORLD.get_child(0))
	_tab("CREATURES")


func _tab(t: String) -> void:
	for k in _pages:
		_pages[k].visible = k == t
		_tab_btns[k].button_pressed = k == t


func _section(page: Control, title: String) -> GridContainer:
	var l: Label = main.menu._text(title, 13, AMBER)
	page.add_child(l)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	page.add_child(g)
	return g


func _button(grid: GridContainer, text: String, act: Callable, toggle := "") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "SmallButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(205, 34)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.pressed.connect(act)
	if toggle != "":
		b.toggle_mode = true
		_toggles[toggle] = b
	grid.add_child(b)
	return b


func _creatures_page(page: VBoxContainer) -> void:
	var g := _section(page, "SPAWN AT THE CROSSHAIR")
	for s in SPAWNS:
		var b := _button(g, s[0], _spawn.bind(s[1]))
		if NOTES.has(String(s[1]).get_file()):
			b.mouse_entered.connect(func(): _note.text = NOTES[String(s[1]).get_file()])
	_note = main.menu._text("", 12, DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_note)
	g = _section(page, "THE DEAD")
	_button(g, "Rising body (3 s)", _body_that_rises)
	_button(g, "Body (stays down)", func(): _spawn_item("REMAINS"))
	g = _section(page, "ALL OF THEM")
	_button(g, "Freeze  [F2]", _hotkey.bind(KEY_F2), "frozen")
	_button(g, "State labels  [F3]", _hotkey.bind(KEY_F3), "labels")
	_button(g, "Clear all  [F4]", _hotkey.bind(KEY_F4))
	_button(g, "Noise  [F8]", _hotkey.bind(KEY_F8))


func _items_page(page: VBoxContainer) -> void:
	var g := _section(page, "GEAR")
	for id in Data.ITEMS:
		var k := Data.kind(id)
		if k in ["scrap", "photo", "remains"]:
			continue
		_button(g, Data.ITEMS[id].name, _spawn_item.bind(id))
	g = _section(page, "SCRAP")
	_button(g, "Random scrap  [G]", _hotkey.bind(KEY_G))
	_button(g, "Something valuable", func():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_spawn_item(Data.valuable_scrap(rng, false)))
	_button(g, "Something heavy", func():
		var heavy := Data.ITEMS.keys().filter(func(i): return Data.is_heavy(i))
		_spawn_item(heavy[randi() % heavy.size()]))
	_button(g, "A photograph", func(): _spawn_item("PHOTO"))


func _player_page(page: VBoxContainer) -> void:
	var g := _section(page, "YOU")
	_button(g, "God mode  [F1]", _hotkey.bind(KEY_F1), "god")
	_button(g, "Noclip fly  [F7]", _hotkey.bind(KEY_F7), "fly")
	_button(g, "Heal to full", func():
		main.player.hp = 100.0
		main.player.since_hurt = 99.0)
	_button(g, "Take 25 (cracks)", func():
		if god:
			god = false
			main.hud.msg("God mode off (it would heal you straight back, cracks and all).")
		main.player.hurt(25.0, "The playground."))
	_button(g, "Recharge everything", func(): main.player.recharge())
	_button(g, "+500 credits", func(): main.credits += 500)
	_button(g, "Headlamp + NV", func():
		for u in ["HEADLAMP", "NIGHT_VISION", "BATTERY_PACK"]:
			main.upgrades[u] = true
		main.hud.msg("Headlamp [T] and night vision [N] installed."))
	_button(g, "Back to the lift", func(): _drop_into_facility())


func _world_page(page: VBoxContainer) -> void:
	var g := _section(page, "VIEW")
	_button(g, "Fullbright  [B]", _hotkey.bind(KEY_B), "bright")
	_button(g, "Path gizmos  [P]", _hotkey.bind(KEY_P), "paths")
	_button(g, "Slow motion  [F6]", _hotkey.bind(KEY_F6), "slow")
	_button(g, "Day / night  [F5]", _hotkey.bind(KEY_F5))
	g = _section(page, "GO")
	_button(g, "Up / down  [F9]", _hotkey.bind(KEY_F9))
	_button(g, "To the breaker", func():
		if main.level and main.level.hazards:
			_go_to(main.level.hazards.breaker))
	_button(g, "Checkpoint (shredder)", _go_checkpoint)
	_button(g, "Back to the station", func():
		_ready_done = false
		_go_below(false))
	g = _section(page, "EVENTS")
	for ev in [["Power failure", "power_fail"], ["Reset breaker", "restore"], ["Tremor", "tremor"], ["Airdrop (surface)", "airdrop"]]:
		_button(g, ev[0], func():
			if _hazards():
				main.level.hazards.call(ev[1]))
	g = _section(page, "REBUILD THE SITE  [F10 cycles]")
	for t in THEMES:
		_button(g, t, func():
			theme = t
			_ready_done = false
			_go_below(false))


func _hazards() -> bool:
	return main.level != null and main.level.get("hazards") != null


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
			main.hud.msg("Leviathan is listening. Make a noise on the surface (F8): it only hunts topside.")
		_:
			m.global_position = at + Vector3(0, 0.05, 0)
	Sfx.play(main, "beep", null, -8.0)


func _spawn_item(id: String) -> void:
	if not Data.ITEMS.has(id):
		return
	var p = main.spawn_item(id, _aim() + Vector3(0, 0.4, 0), -1.0, main.level)
	if p != null and id == "PHOTO":
		p.add_to_group("photos")
	Sfx.play(main, "beep", null, -8.0)


## A body at the crosshair that gets up as a husk a few seconds later (instead of 90).
func _body_that_rises() -> void:
	var lvl = main.level
	if lvl == null or lvl.facility == null:
		main.hud.msg("Bodies only get up down in a facility.")
		return
	var r = main.spawn_item("REMAINS", _aim() + Vector3(0, 0.4, 0), -1.0, lvl)
	if r == null:
		return
	r.set_meta("born", Time.get_ticks_msec() / 1000.0 - lvl.POSSESS_AFTER * Data.pace() + 3.0)
	main.hud.msg("A body. Give it a few seconds.")


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
	ring.material_override = B.mat(AMBER, 3.0)
	main.add_child(ring)
	ring.global_position = _floor_below(at) + Vector3(0, 0.1, 0)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * 0.05, 0.0)
	tw.tween_property(ring, "scale", Vector3.ONE, 0.5)
	tw.tween_callback(ring.queue_free)


func _input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo) or main.term.visible or main.menu.is_open():
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
			Sfx.play(main, "click", null, -8.0, 0.9 if panel.visible else 1.1)
		KEY_H: strip.visible = not strip.visible
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
			main.player.collision_mask = 0 if fly else 1 | 16
		KEY_F8: _noise_at_crosshair()
		KEY_B:   # fullbright: every surface at its own colour, no lights, shadows or fog
			bright = not bright
			get_viewport().debug_draw = Viewport.DEBUG_DRAW_UNSHADED if bright else Viewport.DEBUG_DRAW_DISABLED
		KEY_P:   # path gizmos: routes, waypoints, targets, the room graph, shut bulkheads, stuck spots
			if paths == null:
				paths = load("res://src/pathdebug.gd").new()
				paths.main = main
				main.add_child(paths)
			else:
				paths.queue_free()
				paths = null
			NavigationServer3D.set_debug_enabled(paths != null)   # the baked navigation mesh too
		KEY_F9:
			if main.level == null or main.level.get("elevator") == null:
				return true
			if main.player.global_position.y < -20.0:
				main.player.global_position = main.level.elevator_pos + Vector3(0, 0.5, -6.0)
			else:
				_drop_into_facility()
		KEY_F10:
			theme = THEMES[(THEMES.find(theme) + 1) % THEMES.size()]
			_ready_done = false
			_go_below(false)
		KEY_G:
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			_spawn_item(Data.random_scrap(rng))
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
	var state := {"god": god, "frozen": frozen, "labels": labels, "slow": slow, "fly": fly, "bright": bright, "paths": paths != null}
	for k in _toggles:
		_toggles[k].set_pressed_no_signal(state[k])
	_refresh_strip()
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
			l.modulate = AMBER
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
