# A station from every side: rolling in, along the platform, under the canopy, the booking office
# outside and in (hall, ticket office, waiting room), the steps and forecourt behind, the signal box,
# the water crane, from the air. Needs a window.
# Run: godot --path . -s tests/station_shots.gd -- <out_dir> [DESERT|ARCTIC] [hour]
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


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://station"
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	main.hud.visible = false
	main.player.frozen = true
	main.term.run("LEAVE_CHECKPOINT")
	var d: Dictionary = main.route[0][0]
	d.biome = args[1] if args.size() > 1 else "DESERT"
	d.weather = "CLEAR"
	Engine.set_meta("fast_test", true)
	main.term.run("ROUTE_TO " + d.letter)
	while main.busy:
		await process_frame
	Engine.remove_meta("fast_test")
	main.hours = float(args[2]) if args.size() > 2 else 9.5
	main.player.global_position = Vector3(0, 60, -90)   # (out of every shot, above ground)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 64
	cam.far = 3000.0
	for i in 30:
		await process_frame
	var sx: float = main.level._station_x
	var S = load("res://src/station.gd")
	var z1: float = S.Z1
	var b: float = z1 + S.DEEP / 2.0   # the building's middle (z)
	await shot("01_rolling_in", cam, Vector3(-60, 3.2, -3.5), Vector3(0, 2.5, 4))
	await shot("02_platform_west", cam, Vector3(-27, 2.7, 3.4), Vector3(10, 2.3, 4.5))
	await shot("03_platform_east", cam, Vector3(19, 2.7, 3.2), Vector3(-10, 2.0, 5))
	await shot("04_from_track", cam, Vector3(sx - 2, 2.0, -4), Vector3(sx, 3.0, 8))
	await shot("05_canopy_up", cam, Vector3(sx + 6, 2.4, 3.6), Vector3(sx + 2, 4.6, 4.6))
	await shot("06_front", cam, Vector3(sx + 3, 2.6, 2.6), Vector3(sx, 3.2, z1))
	await shot("07_hall", cam, Vector3(sx + 0.4, 2.65, z1 + 0.7), Vector3(sx - 0.5, 2.2, z1 + 6.5))
	await shot("08_hall_back", cam, Vector3(sx, 2.65, z1 + 7.0), Vector3(sx - 2.0, 2.0, z1 + 1.5))
	await shot("09_office", cam, Vector3(sx - 3.6, 2.6, b + 3.0), Vector3(sx - 7.5, 1.6, b - 2.0))
	await shot("10_waiting", cam, Vector3(sx + 3.6, 2.6, b - 3.0), Vector3(sx + 8.0, 1.5, b + 2.0))
	await shot("11_back", cam, Vector3(sx + 7, 2.2, z1 + 16), Vector3(sx, 2.5, z1 + 6))
	await shot("12_forecourt", cam, Vector3(sx - 4, 1.8, z1 + 7.5), Vector3(sx + 6, 1.0, z1 + 18))
	await shot("13_signal_box", cam, Vector3(S.X0 - 4, 2.6, -2.0), Vector3(S.X0 - 12, 3.4, 7.6))
	await shot("14_water_crane", cam, Vector3(S.X1 + 1, 2.6, 2.5), Vector3(S.X1 + 6, 2.8, -3.1))
	await shot("15_aerial", cam, Vector3(-30, 26, -34), Vector3(0, 0, 8))
	await shot("16_aerial_back", cam, Vector3(sx + 24, 22, 44), Vector3(sx, 0, 6))
	quit()
