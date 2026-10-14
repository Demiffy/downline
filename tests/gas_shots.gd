# A gas room, photographed: from inside (torch on), from across the room, at the burst line, from the
# next room in through the doorway, and with the room's own lamps only. Needs a window.
# Run: tests/run.sh 300 --path . -s tests/gas_shots.gd -- <out_dir> [THEME]
extends SceneTree

var main
var out := "user://shots"
var theme := "FACTORY"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		theme = args[1]
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func secs(t: float) -> void:
	await main.get_tree().create_timer(t).timeout


func shot(name: String) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, theme.to_lower(), name])
	print("saved ", name)


func look(pos: Vector3, at: Vector3) -> void:
	var p = main.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	var d := at - (pos + Vector3(0, 1.6, 0))
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _run() -> void:
	Engine.set_meta("fast_test", true)
	Engine.set_meta("test_seed", 11)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	var p = main.player
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = theme
	stop.rooms = 20
	stop.weather = "CLEAR"
	p.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	Engine.remove_meta("fast_test")
	p.hp = 1e9
	p.slots[0] = {"id": "FLASHLIGHT", "charge": 99999.0}
	p.slots[1] = {"id": "GAS_MASK", "charge": -1.0}
	p.sel = 0
	p.light_on = true
	main.hud.visible = false
	var lvl = main.level
	var fac = lvl.facility
	var hz = lvl.hazards
	hz.events.clear()
	for n in lvl.get_children():
		if n.is_in_group("monsters") or (n.get_script() and n.get_script().resource_path.get_file() in ["snatcher.gd", "bear_trap.gd", "gloe.gd"]):
			n.queue_free()
	if hz.gassed.is_empty():
		var rooms: Array = fac.layout.cells.filter(func(c): return not fac.kinds[c] in ["start", "pit", "vault", "atrium", "tunnel", "stairwell"] and not fac.group_of.has(c) and not hz.flooded.has(c))
		hz._gas(rooms.pop_back())
	var gc: Vector2i = hz.gassed.keys()[0]
	var go: Vector3 = fac.to_global(Vector3(gc.x * 12.0, 0, gc.y * 12.0))
	look(go + Vector3(-4.5, 0.05, -0.5), go + Vector3(2, 1, 0))
	await secs(2.0)
	await shot("gas")
	look(go + Vector3(4.5, 0.05, 4.5), go + Vector3(-2, 0.6, -2))
	await secs(0.5)
	await shot("gas_across")
	var src: Array = fac.find_children("*", "OmniLight3D", true, false).filter(func(l): return is_equal_approx(l.omni_range, 4.5) and l.light_color.g > 0.8 and l.light_color.b < 0.5)
	if not src.is_empty():   # the pool's glow, under the burst line
		var at: Vector3 = src[0].global_position
		var away := ((go - at) * Vector3(1, 0, 1)).normalized()
		look(at + away * 3.2 + Vector3(0, -0.35, 0), at + Vector3(0, 0.5, 0))
		await secs(0.5)
		await shot("gas_source")
	p.light_on = false
	look(go + Vector3(4.5, 0.05, 4.5), go + Vector3(-2, 0.6, -2))
	await secs(0.5)
	await shot("gas_dark")
	p.light_on = true
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:   # from the next room, looking in at the doorway
		if fac.layout.links[gc].has(gc + d) and not fac.kinds.get(gc + d, "") in ["pit", "stairwell", "atrium"]:
			var dv := Vector3(d.x, 0, d.y)
			look(go + dv * 9.0 + Vector3(0, 0.05, 0), go + dv * 4.0 + Vector3(0, 0.6, 0))
			await secs(0.5)
			await shot("gas_doorway")
			break
	quit(0)
