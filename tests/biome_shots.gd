# A station in one of the surface biomes, from the ground and the air: rolling in, the platform,
# out behind the station toward the lift, the way there, close up among what grows or stands
# there, and the line running out of the valley. Needs a window.
# and the station's landmark, outside and in.
# Run: tests/run.sh 500 --path . -s tests/biome_shots.gd -- <out_dir> FOREST|SWAMP|CITY|DESERT|ARCTIC [CHAPEL|LOOKOUT|FARM|FUEL] [hour]
extends SceneTree

var out := ""
var main


func _initialize() -> void:
	_run()


func shot(name: String, cam: Camera3D, pos: Vector3, at: Vector3) -> void:
	var lv: Node3D = main.level
	cam.global_position = lv.to_global(pos)
	cam.look_at(lv.to_global(at))
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("saved ", name)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://biome"
	var bio: String = args[1] if args.size() > 1 else "FOREST"
	if args.size() > 2 and args[2] != "-":
		Engine.set_meta("force_landmark", args[2])
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	main.hud.visible = false
	main.player.frozen = true
	main.term.run("LEAVE_CHECKPOINT")
	var d: Dictionary = main.route[0][0]
	d.biome = bio
	d.weather = "CLEAR"
	Engine.set_meta("fast_test", true)
	main.term.run("ROUTE_TO " + d.letter)
	while main.busy:
		await process_frame
	Engine.remove_meta("fast_test")
	main.hours = float(args[3]) if args.size() > 3 else 10.0
	main.player.global_position = Vector3(0, 60, -90)   # (out of every shot, above ground)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 64
	cam.far = 3000.0
	for i in 30:
		await process_frame
	var lv = main.level
	var sx: float = lv._station_x
	var e: Vector3 = lv.elevator_pos
	var mid: Vector3 = Vector3(sx, 0, 20.5).lerp(e, 0.5)
	var gy := func(p: Vector3) -> Vector3: return Vector3(p.x, lv.ground_y(p.x, p.z), p.z)
	await shot("01_rolling_in", cam, Vector3(-60, 3.2, -3.5), Vector3(0, 2.5, 4))
	await shot("02_platform", cam, Vector3(19, 2.7, 3.2), Vector3(-10, 2.0, 5))
	await shot("03_behind_station", cam, Vector3(sx + 2, 2.2, 22.5), mid + Vector3(0, 1.5, 0))
	await shot("04_the_way", cam, gy.call(mid) + Vector3(-3, 1.8, -4), e + Vector3(0, 3, 0))
	await shot("05_lift_back", cam, e + Vector3(4, 2.0, 6), Vector3(sx, 3.0, 18))
	await shot("06_wide_left", cam, Vector3(-40, 2.2, 30), Vector3(-70, 2.0, 60))
	await shot("07_wide_right", cam, Vector3(40, 2.2, 30), Vector3(70, 2.0, 60))
	await shot("08_aerial", cam, Vector3(-30, 30, -36), Vector3(0, 0, 25))
	await shot("09_aerial_back", cam, e + Vector3(30, 26, 30), Vector3(sx, 0, 14))
	await shot("10_line_out", cam, Vector3(80, 3.0, -2.5), Vector3(200, 4.0, -10))
	if lv.landmark != "":
		var lp: Vector3 = lv._landmark_at
		var rot: float = lv._landmark_rot
		var f := func(v: Vector3) -> Vector3: return lp + v.rotated(Vector3.UP, rot)   # (the landmark's own frame: front at -z)
		await shot("11_landmark", cam, f.call(Vector3(-7, 2.4, -12)), f.call(Vector3(0, 3.0, 0)))
		await shot("12_landmark_side", cam, f.call(Vector3(16, 4.0, 6)), f.call(Vector3(0, 2.5, 2)))
		await shot("13_landmark_air", cam, f.call(Vector3(-18, 20, -22)), f.call(Vector3(0, 0, 3)))
		match lv.landmark:
			"CHAPEL":
				await shot("14_inside", cam, f.call(Vector3(0.5, 1.7, -6.0)), f.call(Vector3(0, 1.2, 6)))
				await shot("15_graveyard", cam, f.call(Vector3(-5.5, 1.8, 9.0)), f.call(Vector3(3, 0.6, 15)))
			"LOOKOUT":
				await shot("14_inside", cam, f.call(Vector3(-1.8, 14.3, -1.8)), f.call(Vector3(1.5, 13.3, 1.5)))
				await shot("15_stairs", cam, f.call(Vector3(-1.5, 2.0, 1.5)), f.call(Vector3(1.5, 5.0, -1.5)))
				await shot("16_view", cam, f.call(Vector3(0, 14.4, -3.4)), f.call(Vector3(0, 8.0, -40)))
			"FARM":
				await shot("14_inside", cam, f.call(Vector3(0.5, 1.7, -5.5)), f.call(Vector3(0, 1.0, 4)))
			"FUEL":
				await shot("14_inside", cam, f.call(Vector3(2.5, 1.7, 3.4)), f.call(Vector3(-2.5, 1.0, 5.5)))
	quit()
