# Frame cost across the whole game (needs a window): the checkpoint (aboard and out in the yard),
# a station's surface, its facility. At each spot: frame time, CPU (process + physics), GPU time,
# draw calls, objects, primitives; then the scene's totals (nodes, lights, physics bodies, nodes
# that run _process every frame), to see where the time goes.
# Run: godot --path . -s tests/perf_tour.gd -- [THEME]
extends SceneTree

var main
var theme := "FACTORY"
var vp: RID


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		theme = args[0]
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func look(pos: Vector3, at: Vector3) -> void:
	var p = main.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	var d := at - (pos + Vector3(0, 1.6, 0))
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func measure(label: String, n := 120) -> void:
	await frames(20)
	var t0 := Time.get_ticks_usec()
	var proc := 0.0
	var phys := 0.0
	var gpu := 0.0
	var cpu_r := 0.0
	var worst := 0.0
	var last := Time.get_ticks_usec()
	for i in n:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu_r += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	print("%-22s frame %5.2f ms (worst %5.1f)  process %5.2f  physics %5.2f  render-cpu %5.2f  gpu %5.2f  draws %5d  objects %5d  prims %7dk" % [label, ms, worst,
		proc / n, phys / n, cpu_r / n, gpu / n, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000])


func census(label: String) -> void:
	var all: Array = main.find_children("*", "", true, false)
	var procs := 0
	var phys := 0
	var by_script := {}
	for n in all:
		if n.is_processing() or n.is_physics_processing():
			if n.is_processing():
				procs += 1
			if n.is_physics_processing():
				phys += 1
			var sc: Script = n.get_script()
			var k: String = sc.resource_path.get_file() if sc else n.get_class()
			by_script[k] = by_script.get(k, 0) + 1
	var lights := main.find_children("*", "Light3D", true, false)
	var shadowed := lights.filter(func(l): return l.shadow_enabled and l.visible)
	var bodies := main.find_children("*", "CollisionObject3D", true, false)
	var meshes := main.find_children("*", "MeshInstance3D", true, false)
	var audio := main.find_children("*", "AudioStreamPlayer3D", true, false)
	print("%s: nodes %d, meshes %d, lights %d (%d shadowed), collision objects %d, 3D audio %d, processing %d, physics-processing %d" % [label, all.size(), meshes.size(), lights.size(), shadowed.size(), bodies.size(), audio.size(), procs, phys])
	var keys := by_script.keys()
	keys.sort_custom(func(a, b): return by_script[a] > by_script[b])
	var line := "   per-frame:"
	for k in keys.slice(0, 14):
		line += " %s x%d," % [k, by_script[k]]
	print(line)


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	vp = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(30)
	main.hud.visible = true
	var t: Vector3 = main.train.global_position
	census("checkpoint")
	look(t + Vector3(-3, 0.2, 0), t + Vector3(6, 1.5, 0))
	await measure("cp: in the car")
	look(t + Vector3(-8, 1.6, 6), t + Vector3(30, 2, -30))
	await measure("cp: platform")
	look(t + Vector3(0, 0.2, 30), t + Vector3(0, 4, 80))
	await measure("cp: to the office")
	look(t + Vector3(45, 0.2, 30), t + Vector3(110, 8, 80))
	await measure("cp: to the works")
	look(t + Vector3(-30, 0.2, -14), t + Vector3(40, 2, -45))
	await measure("cp: the yard")
	look(t + Vector3(-45, 0.2, 40), t + Vector3(-110, 4, 60))
	await measure("cp: the terminal")
	# A station.
	Engine.set_meta("fast_test", true)
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = theme
	stop.rooms = 24
	main.player.global_position = main.train.global_position + Vector3(0, 1.3, 0)
	main.rng.seed = 20261009
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	Engine.remove_meta("fast_test")
	await frames(30)
	census("station")
	t = main.train.global_position
	look(t + Vector3(0, 0.2, 6), t + Vector3(0, 2, 40))
	await measure("st: off the train")
	look(t + Vector3(20, 0.2, 20), t + Vector3(60, 2, 60))
	await measure("st: the surface")
	var fac = main.level.facility
	for i in 4:
		var c: Vector2i = fac.layout.cells[i * 2]
		var o: Vector3 = fac.to_global(Vector3(c.x * 12.0, 0.05, c.y * 12.0))
		look(o + Vector3(-4, 0, -4), o + Vector3(6, 1.2, 6))
		await measure("st: facility %d" % i)
	quit()
