# The facility's new pieces, close up: the records room's keypad door and the chalked code, the
# twin-key blast door and its two levers, a fire shutter rolled up and then down in a lockdown
# with its beacons turning, a burst main. One facility build, the camera straight to each.
# Run: tests/run.sh 500 --path . --resolution 1280x720 -s tests/puzzle_shots.gd -- <out_dir> [THEME]
extends SceneTree

var main
var out := "user://puzzles"
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


## Stand in front of a doorway (center, along_x) on the side away from `away_cell`, looking at it.
func face_door(fac, door: Node3D, away: Vector3, dist := 3.2) -> void:
	var c: Vector3 = door.global_position
	c.y = fac.global_position.y
	var n := (c - away)
	n.y = 0.0
	n = n.normalized()
	if absf(n.x) > absf(n.z):
		n = Vector3(signf(n.x), 0, 0)
	else:
		n = Vector3(0, 0, signf(n.z))
	look(c + n * dist + Vector3(0.6, 0.05, 0.6) * Vector3(absf(n.z), 0, absf(n.x)), c + Vector3(0, 1.4, 0))


func _run() -> void:
	Engine.set_meta("fast_test", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	for n in main.get_children():
		if n.has_method("_show_title"):
			n.queue_free()
	var p = main.player
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = theme
	stop.rooms = 24
	stop.weather = "CLEAR"
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
	lvl.director.mood = "RELAX"
	lvl.director._t = 1e9
	for n in lvl.get_children():
		if n.is_in_group("monsters"):
			n.queue_free()
	await frames(5)
	var cellpos := func(c: Vector2i) -> Vector3: return fac.to_global(Vector3(c.x * 12.0, 0, c.y * 12.0))
	if fac.secure_code != "":
		face_door(fac, fac.doors[fac.secure_code], cellpos.call(fac.secure_cell))
		await shot("01_secure_door")
		if fac.clue_at != Vector3.INF:
			var to_wall: Vector3 = fac.clue_at
			var room: Vector3 = cellpos.call(fac.cell_at(fac.clue_at))
			var back := (room - Vector3(to_wall.x, room.y, to_wall.z)).normalized()
			look(Vector3(to_wall.x, room.y + 0.05, to_wall.z) + back * 2.8, to_wall)
			await shot("02_chalked_code")
		main.term.run("OPEN_BULKHEAD " + fac.secure_code)
		await create_timer(1.5).timeout
		face_door(fac, fac.doors[fac.secure_code], cellpos.call(fac.secure_cell), 2.2)
		await shot("03_secure_open")
	if fac.twin_code != "":
		face_door(fac, fac.doors[fac.twin_code], cellpos.call(fac.twin_cell), 4.0)
		await shot("04_twin_door")
		for i in fac.twin_levers.size():
			var lv: Node3D = fac.twin_levers[i]
			var out_n: Vector3 = lv.global_basis.z
			look(lv.global_position + out_n * 1.6 + Vector3(0, -1.3, 0) + lv.global_basis.x * 0.5, lv.global_position)
			await shot("05_lever_%d" % i)
	var site = lvl.site
	if not site.shutters.is_empty():
		var sh: Node3D = fac.doors[site.shutters[0]]
		var e: Array = fac.layout.doors[site.shutters[0]]
		face_door(fac, sh, cellpos.call(e[0]), 4.0)
		await shot("06_shutter_open")
		site._say(["lockdown", true])
		await create_timer(1.8).timeout
		await shot("07_shutter_lockdown")
		site._say(["lockdown", false])
	var c = site._burst_room()
	if c != null:
		site._say(["burst", c])
		var o: Vector3 = cellpos.call(c)
		await create_timer(10.0).timeout
		look(o + Vector3(-4.0, 0.05, -4.0), o + Vector3(2.0, 1.4, 2.0))
		await shot("08_burst_main")
	quit()
