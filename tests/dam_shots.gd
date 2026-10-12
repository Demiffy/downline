# The dam landmark stop from all round: the station with the dam behind it, the powerhouse and its
# yard, the spillway and basin, the stair tower, the crest road, the reservoir and intake towers, the
# air; then underground, the turbine hall and the control room. Needs a window.
# Run: tests/run.sh 400 --path . -s tests/dam_shots.gd -- <dir> [DESERT|ARCTIC|FOREST] [hour] [view ...]
extends SceneTree

var out := ""
var main
var only: Array = []


func _initialize() -> void:
	_run()


func shot(name: String, cam: Camera3D, pos: Vector3, at: Vector3) -> void:
	if not only.is_empty() and not name in only:
		return
	var lv: Node3D = main.level
	cam.global_position = lv.to_global(pos)
	cam.look_at(lv.to_global(at))
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://dam"
	only = args.slice(3) if args.size() > 3 else []
	DirAccess.make_dir_recursive_absolute(out)
	Engine.set_meta("force_dam", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	main.hud.visible = false
	main.player.frozen = true
	main.term.run("LEAVE_CHECKPOINT")
	var d: Dictionary = main.route[0][0]
	if args.size() > 1:
		d.biome = args[1]
	d.weather = "CLEAR"
	print("STOP ", d)
	Engine.set_meta("fast_test", true)
	main.term.run("ROUTE_TO " + d.letter)
	while main.busy:
		await process_frame
	Engine.remove_meta("fast_test")
	main.hours = float(args[2]) if args.size() > 2 else 10.0
	main.player.global_position = Vector3(0, 300, -300)   # (out of every shot)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 64
	cam.far = 3000.0
	for i in 120:   # (the sky and fog settle on the new hour)
		main.hours = float(args[2]) if args.size() > 2 else 10.0
		await process_frame
	var Dam = load("res://src/dam.gd")
	var lv = main.level
	var sx: float = lv._station_x
	await shot("01_from_platform", cam, Vector3(sx - 14, 2.8, 4.0), Vector3(-10, 22, 80))
	await shot("02_station_and_dam", cam, Vector3(sx + 40, 6.0, -26.0), Vector3(-10, 18, 70))
	await shot("03_powerhouse", cam, Vector3(-40, 2.0, 30.0), Vector3(-60, 10, 60))
	await shot("04_yard_and_lift", cam, Vector3(-2, 2.0, 30.0), Vector3(-22, 6, 58))
	await shot("05_spillway", cam, Vector3(30, 3.0, 34.0), Vector3(38, 26, 80))
	await shot("06_basin", cam, Vector3(52, 3.2, 42.0), Vector3(36, -1, 64))
	await shot("07_stair_tower", cam, Vector3(-66, 2.5, 36.0), Vector3(-88, 20, 60))
	var ce: Vector3 = Dam.face(-40.0, Dam.CREST) + Dam.out_n(-40.0) * -3.5
	await shot("08_crest_road", cam, ce + Vector3(0, 1.7, 0), ce + Vector3(60, 1.0, -6))
	await shot("09_reservoir", cam, ce + Vector3(0, 1.8, 0), ce + Vector3(-10, -2.0, 60))
	await shot("10_down_the_face", cam, Dam.face(10.0, Dam.CREST) + Vector3(0, 2.0, -1.0), Vector3(20, 0, 40))
	await shot("11_aerial", cam, Vector3(-120, 90, -60), Vector3(-10, 10, 70))
	await shot("12_aerial_spill", cam, Vector3(90, 70, 0), Vector3(30, 20, 70))
	# Underground: the turbine hall and the control room (the player down there too, so it's lit as below).
	var fac = lv.facility
	main.player.global_position = fac.global_position + Vector3(0, -30, 0)
	for g in fac.groups:
		if g.kind in ["turbine_hall", "control_room"]:
			var H = load("res://src/halls.gd")
			var f: Dictionary = H.frame(g)
			var c: Vector3 = fac.to_global(H.at(f, 0, 0, 1.7))
			var name := "13_" + String(g.kind)
			var lvc: Vector3 = lv.to_local(c)
			var back: Vector3 = lv.to_local(fac.to_global(H.at(f, -10.0 if f.shape != "L" else -4.5, -4.0 if f.shape == "2x2" else 0.0, 2.6)))
			await shot(name, cam, back, lvc + Vector3(0, -1.2, 0))
			await shot(name + "_b", cam, lv.to_local(fac.to_global(H.at(f, 4.0, 4.5, 2.4))), lvc + Vector3(0, -1.0, 0))
			if g.kind == "control_room" and fac.has_meta("mimic"):   # the board itself, from behind the desks
				var mb: Array = fac.get_meta("mimic")
				var bp: Vector3 = lv.to_local(fac.to_global(mb[0]))
				var bn: Vector3 = mb[1]
				await shot(name + "_board", cam, bp + bn * 7.5 + Vector3(0, 1.9, 0), bp + Vector3(0, 1.5, 0))
	print("jackpot ", fac.jackpot, " groups ", fac.groups.map(func(g): return g.kind))
	quit()
