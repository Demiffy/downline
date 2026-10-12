# The README's pictures that need the game running, all from one facility build: the terminal at
# the checkpoint, a room underground by flashlight, the same in a power failure, a flood with a
# live cable, a warden and a siren met in a room. The camera goes straight to each; one frame each.
# Run: tests/run.sh 400 --path . --resolution 1280x720 -s tests/readme_shots.gd -- <out_dir>
extends SceneTree

var main
var out := "user://readme"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
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
	for n in main.get_children():
		if n.has_method("_show_title"):
			n.queue_free()
	var p = main.player
	# The terminal: an assignment issued, the route, a station looked at.
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = "FACTORY"
	stop.rooms = 18
	stop.weather = "CLEAR"
	main.open_terminal()
	main.term.run("MAP")
	main.term.run("VIEW_STATION " + stop.letter)
	await frames(20)
	await shot("terminal")
	main.term.close()
	await frames(5)
	p.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	Engine.remove_meta("fast_test")
	main.hud.visible = false
	p.hp = 1e9
	p.slots[0] = {"id": "FLASHLIGHT", "charge": 99999.0}
	p.sel = 0
	p.light_on = true
	var lvl = main.level
	var fac = lvl.facility
	var hz = lvl.hazards
	hz.events.clear()
	for n in lvl.get_children():   # (nothing wandering into the pictures)
		if n.is_in_group("monsters") or (n.get_script() and n.get_script().resource_path.get_file() in ["snatcher.gd", "bear_trap.gd", "gloe.gd"]):
			n.queue_free()
	await frames(5)
	# A room by flashlight: the biggest machine room, from a corner across it.
	var rooms: Array = fac.layout.cells.filter(func(c): return fac.kinds[c] in ["machine", "storage", "break", "office"] and not hz.flooded.has(c) and not hz.gassed.has(c))
	rooms.sort_custom(func(a, b): return ["machine", "storage", "office", "break"].find(fac.kinds[a]) < ["machine", "storage", "office", "break"].find(fac.kinds[b]))
	var c: Vector2i = rooms[0]
	var o: Vector3 = fac.to_global(Vector3(c.x * 12.0, 0, c.y * 12.0))
	look(o + Vector3(-4.6, 0.05, -4.6), o + Vector3(2, 0.9, 2))
	await frames(10)
	await shot("facility")
	# The same room with the power gone: emergency red, the beacons turning.
	hz.power_fail()
	await create_timer(2.5).timeout
	look(o + Vector3(4.6, 0.05, -4.6), o + Vector3(-2, 1.0, 2))
	await shot("power_failure")
	hz.restore()
	await frames(10)
	# A flood with a live cable arcing through it.
	if hz.flooded.is_empty():
		hz._flood(rooms[rooms.size() - 1])
	if hz.cables.is_empty():
		var fcell: Vector2i = hz.flooded.keys()[0]
		hz._cable(fcell, Vector3(fcell.x * 12.0, 0, fcell.y * 12.0))
	var cb: Dictionary = hz.cables[0]
	var cc: Vector3 = fac.to_global(Vector3(cb.cell.x * 12.0, 0, cb.cell.y * 12.0))
	look(cc + Vector3(-signf(cb.at.x - cc.x) * 1.5, 0.05, -signf(cb.at.z - cc.z) * 1.5), cb.at + Vector3(0, 0.6, 0))
	cb.state = 1
	cb.t = 0.6
	await create_timer(0.65).timeout
	await shot("hazard")
	# Creatures, each met in a room, held still in the flashlight.
	for kind in ["warden", "siren", "observer"]:
		var rc: Vector2i = rooms[mini(1 + ["warden", "siren", "observer"].find(kind), rooms.size() - 1)]
		var ro: Vector3 = fac.to_global(Vector3(rc.x * 12.0, 0, rc.y * 12.0))
		var script: Script = load("res://src/%s.gd" % kind)
		var m = lvl._spawn(script, ro + Vector3(1.5, 0.1, 1.5), false)
		await frames(20)
		if is_instance_valid(m):
			m.process_mode = Node.PROCESS_MODE_DISABLED
			m.global_position = ro + Vector3(1.5, 0.1, 1.5)
			m.look_at(ro + Vector3(-3.5, m.global_position.y - ro.y, -3.5), Vector3.UP)
		look(ro + Vector3(-3.0, 0.05, -3.0), ro + Vector3(1.5, 1.3, 1.5))
		await frames(6)
		await shot("creature_" + kind)
		if is_instance_valid(m):
			m.queue_free()
	quit()
