# A trip between stops, photographed on the way: pulling out, the open line, into the tunnel, inside,
# out into the morning, the approach (signals, boards, a freight in the loop), drawing up at the
# platform. Needs a window; real time (about a minute a trip).
# Run: godot --path . -s tests/journey_shots.gd -- <out_dir> [DESERT|ARCTIC] [DESERT|ARCTIC] [hour]
#   (the two biomes: the first station's and the second's; hour: when the second trip leaves)
extends SceneTree

var out := ""
var main


func _initialize() -> void:
	_run()


func shot(name: String, cam: Camera3D, pos: Vector3, at: Vector3) -> void:
	var gy: float = main.line.height(main.line.s + pos.x, pos.z) if not main.line._in_footprint(main.line.s + pos.x, pos.z) else 0.0
	cam.global_position = main.train.to_global(Vector3(pos.x, maxf(pos.y, gy + 2.5), pos.z))
	cam.look_at(main.train.to_global(at))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name, "  s=%.0f v=%.1f dark=%.2f" % [main.line.s, main.line.v, main.line.dark])


## Wait until the line has come `x` metres (or the trip's over).
func until(x: float) -> void:
	while main.line.riding and main.line.s < x:
		await process_frame


func trip(tag: String, dest: Dictionary, cam: Camera3D) -> void:
	main.term.run("ROUTE_TO " + dest.letter)
	while not main.line.riding:
		await process_frame
	var l = main.line
	var t: Dictionary = l._segs.filter(func(g): return g.kind == "tunnel" and g.b > 0.0)[0]
	var arr: float = l._arr_x
	await until(4.0)
	await shot(tag + "_01_pull_out", cam, Vector3(-30, 6, 16), Vector3(4, 1.5, 0))
	await until(150.0)
	await shot(tag + "_02_side", cam, Vector3(2, 3.2, 26), Vector3(4, 1.5, 0))
	await shot(tag + "_03_window", cam, Vector3(-2, 2.3, -1.4), Vector3(-2, 2.0, -8))
	if t.entry:
		await until(t.a - 170.0)
		await shot(tag + "_04_cab_ahead", cam, Vector3(18.0, 2.4, 0.0), Vector3(60, 2.5, 0))
		await until(t.a - 40.0)
		await shot(tag + "_05_portal", cam, Vector3(-30, 8, 13), Vector3(70, 6, 0))
	await until(t.a + 40.0)
	await shot(tag + "_06_tunnel_cab", cam, Vector3(18.0, 2.4, 0.0), Vector3(60, 2.5, 0))
	await shot(tag + "_07_tunnel_flat", cam, Vector3(-13, 2.4, 1.0), Vector3(-40, 2.5, 0))
	await until(t.b - 60.0)
	await shot(tag + "_08_tunnel_late", cam, Vector3(18.0, 2.4, 0.0), Vector3(60, 2.5, 0))
	await until(t.b + 30.0)
	await shot(tag + "_09_out", cam, Vector3(18.0, 2.4, 0.0), Vector3(60, 2.5, 0))
	await shot(tag + "_10_out_back", cam, Vector3(-14, 4, 6), Vector3(-80, 8, 0))
	if not main.at_checkpoint:
		await until(t.b + 90.0)
		await shot(tag + "_11_approach", cam, Vector3(-20, 8, 22), Vector3(30, 2, 0))
		await until(arr - 260.0)
		await shot(tag + "_12_cab_station", cam, Vector3(18.0, 2.4, 0.0), Vector3(80, 2.0, 0))
		await until(arr - 90.0)
		await shot(tag + "_13_running_in", cam, Vector3(30, 4, 9), Vector3(-5, 2, 0))
	else:
		await until(arr - 120.0)
		await shot(tag + "_13_basin", cam, Vector3(18.0, 2.4, 0.0), Vector3(80, 2.0, 0))
	while main.busy:
		await process_frame
	for i in 20:
		await process_frame
	await shot(tag + "_14_stand", cam, Vector3(-24, 5, 14), Vector3(4, 1.5, 0))
	await shot(tag + "_15_stand_back", cam, Vector3(0, 6, -20), Vector3(-60, 4, 0))


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://journey"
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	main.hud.visible = false
	main.player.frozen = true
	main.player.global_position = main.train.to_global(Vector3(0, 1.3, 0))
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 62
	cam.far = 3000.0
	main.term.run("LEAVE_CHECKPOINT")
	var d1: Dictionary = main.route[0][0]
	d1.biome = args[1] if args.size() > 1 else "DESERT"
	d1.weather = "CLEAR"
	await trip("a", d1, cam)
	var d2: Dictionary = main.route[1][0]
	d2.biome = args[2] if args.size() > 2 else "ARCTIC"
	d2.weather = "CLEAR"
	if args.size() > 3:
		main.hours = float(args[3])
	await trip("b", d2, cam)
	quit()
