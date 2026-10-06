# Screenshots of the scanner pulse and a steam line going off, frame by frame. Needs a window.
# Run: godot --path . -s tests/fx_shots.gd -- <out_dir>
extends SceneTree

var main
var out := "user://shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func secs(t: float) -> void:
	await main.get_tree().create_timer(t).timeout


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/fx_%s.png" % [out, name])
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
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	var p = main.player
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = "FACTORY"
	stop.rooms = 20
	stop.weather = "CLEAR"
	p.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	Engine.remove_meta("fast_test")
	p.hp = 1e9
	p.slots[0] = {"id": "FLASHLIGHT", "charge": 99999.0}
	p.sel = 0
	p.light_on = true
	p.equip = {"id": "SCANNER", "charge": -1.0}
	var lvl = main.level
	var fac = lvl.facility
	var hz = lvl.hazards
	hz.events.clear()
	for n in lvl.get_children():
		if n.get_script() and n.get_script().resource_path.get_file() in ["pulsator.gd", "roomba.gd", "snatcher.gd", "bear_trap.gd"]:
			n.queue_free()
	# Flood water spilling out through a doorway, seen from the dry side.
	var fc: Vector2i = hz.flooded.keys()[0] if not hz.flooded.is_empty() else Vector2i.ZERO
	if hz.flooded.is_empty():
		for c in fac.layout.cells:
			if not fac.kinds[c] in ["start", "pit", "vault", "atrium", "tunnel"] and fac.layout.links[c].any(func(n): return fac.kinds[n] != "pit"):
				fc = c
				break
		hz._flood(fc)
	var dry: Vector2i = Vector2i.ZERO
	for n in fac.layout.links[fc]:
		if not hz.flooded.has(n) and fac.kinds[n] != "pit":
			dry = n
	var door: Vector3 = fac.to_global(Vector3((fc.x + dry.x) * 6.0, 0, (fc.y + dry.y) * 6.0))
	var into: Vector3 = fac.to_global(Vector3(dry.x * 12.0, 0, dry.y * 12.0)) - door
	look(door + into.normalized() * 4.5 + Vector3(0.6, 0.05, 0.4), door + Vector3(0, 0.2, 0) - into.normalized() * 2.0)
	await secs(0.5)
	await shot("flood_door")
	# A tunnel seen end to end: the grate walkway has to hold up at range.
	for c in fac.layout.cells:
		if fac.kinds[c] == "tunnel":
			var n: Vector2i = fac.layout.links[c][0]
			var ax := Vector3(n.x - c.x, 0, n.y - c.y)
			var tc: Vector3 = fac.to_global(Vector3(c.x * 12.0, 0.05, c.y * 12.0))
			look(tc - ax * 5.5, tc + ax * 12.0 + Vector3(0, 0.3, 0))
			await secs(0.3)
			await shot("tunnel_grate")
			break
	# Scanner: from the middle of a room with some scrap around.
	var room := Vector2i.ZERO
	for c in fac.layout.cells:
		if not fac.kinds[c] in ["start", "pit", "tunnel", "vault"] and not hz.flooded.has(c) and not hz.gassed.has(c):
			room = c
			break
	var rc: Vector3 = fac.to_global(Vector3(room.x * 12.0, 0.05, room.y * 12.0))
	var rng := RandomNumberGenerator.new()
	for i in 6:
		main.spawn_item(Data_scrap(rng), rc + Vector3(rng.randf_range(-4, 4), 0.6, rng.randf_range(-4, -1.5)))
	await secs(1.0)
	look(rc + Vector3(0, 0, 3.5), rc + Vector3(0, 0.4, -3))
	await frames(5)
	p._scan_cd = 0.0
	p._scan()
	await secs(0.25)
	await shot("scan_1_wave")
	await secs(0.35)
	await shot("scan_2_wave")
	await secs(0.8)
	await shot("scan_3_lit")
	look(rc + Vector3(0, 0, 3.5), rc + Vector3(-6, 1.0, 3.5))   # turn to the wall: finds show through it
	await secs(0.3)
	await shot("scan_4_xray")
	# Steam: side-on view of the jet, through its cycle.
	if hz.steams.is_empty():
		var rooms: Array = fac.layout.cells.filter(func(c): return fac.kinds[c] == "tunnel")
		if rooms.is_empty():
			rooms = fac.layout.cells.filter(func(c): return not fac.kinds[c] in ["start", "pit", "vault", "atrium"] and c != room)
		if fac.kinds[rooms[0]] == "tunnel":
			hz._steam_tunnel(rooms[0])
		else:
			hz._steam_room(rooms[0])
	var st: Dictionary = hz.steams[0]
	var side: Vector3 = st.dir.cross(Vector3.UP).normalized()
	var eye: Vector3 = st.at + st.dir * 2.6 + side * 1.6 - Vector3(0, 1.35, 0)
	look(eye, st.at + st.dir * 1.0 - Vector3(0, 0.1, 0))
	p.light_on = true
	st.state = 0
	st.idle = 1.0
	st.t = 0.2
	await secs(0.6)
	await shot("steam_1_warning")
	look(eye, st.at + st.dir * 0.2 + Vector3(0, 0.2, 0))   # close on the gauge
	await secs(0.15)
	await shot("steam_2_gauge")
	look(eye, st.at + st.dir * 1.6 - Vector3(0, 0.1, 0))
	await secs(0.65)
	await shot("steam_3_burst")
	await secs(0.8)
	await shot("steam_4_full")
	await secs(1.2)
	await shot("steam_5_sputter")
	await secs(0.9)
	await shot("steam_6_mist")
	# Standing in it: the visor fogs.
	p.global_position = st.at + st.dir * 1.5 - Vector3(0, 1.35, 0)
	p.rotation.y = atan2(st.dir.x, st.dir.z)
	st.state = 1
	st.t = 0.0
	await secs(0.8)
	await shot("steam_7_visor")
	quit()


func Data_scrap(rng: RandomNumberGenerator) -> String:
	return load("res://src/data.gd").random_scrap(rng)
