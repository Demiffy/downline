# Frame-time probe in a real facility (needs a window). Measures several spots, then repeats with
# one expensive feature off at a time, to see what the frame time is spent on.
# Run: godot --path . -s tests/perf.gd -- [THEME]
extends SceneTree

var main
var theme := "FACTORY"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		theme = args[0]
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func measure(n := 90) -> float:
	await frames(10)
	var t0 := Time.get_ticks_usec()
	await frames(n)
	return (Time.get_ticks_usec() - t0) / 1000.0 / n


func look(pos: Vector3, at: Vector3) -> void:
	var p = main.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	var d := at - (pos + Vector3(0, 1.6, 0))
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Engine.set_meta("fast_test", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = theme
	stop.rooms = 24
	main.player.global_position = Vector3(0, 1.3, 0)
	main.rng.seed = 20261009   # (the same site every run, so runs compare)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	Engine.remove_meta("fast_test")
	var p = main.player
	p.hp = 1e9
	p.slots[0] = {"id": "FLASHLIGHT", "charge": 99999.0}
	p.light_on = true
	var fac = main.level.facility
	var spots: Array = []
	for c in fac.layout.cells.slice(0, 6):
		var o: Vector3 = fac.to_global(Vector3(c.x * 12.0, 0.05, c.y * 12.0))
		spots.append([o + Vector3(-4, 0, -4), o + Vector3(6, 1.2, 6)])
	var lights: Array = fac.find_children("*", "Light3D", true, false)
	var shadowed := lights.filter(func(l): return l.shadow_enabled)
	print("lights in facility: %d (%d with shadows)" % [lights.size(), shadowed.size()])
	var run := func(label: String) -> void:
		var worst := 0.0
		var total := 0.0
		for s in spots:
			look(s[0], s[1])
			var ms: float = await measure()
			worst = maxf(worst, ms)
			total += ms
		print("%-28s avg %.2f ms   worst %.2f ms   draws %d  objects %d" % [label, total / spots.size(), worst,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	await run.call("baseline")
	for l in shadowed:
		l.shadow_enabled = false
	await run.call("no omni shadows")
	for l in shadowed:
		l.shadow_enabled = true
	main.env.volumetric_fog_enabled = false
	await run.call("no volumetric fog")
	main.env.volumetric_fog_enabled = true
	main.env.ssao_enabled = false
	await run.call("no ssao")
	main.env.ssao_enabled = true
	main.env.glow_enabled = false
	await run.call("no glow")
	main.env.glow_enabled = true
	var parts: Array = main.get_tree().root.find_children("*", "CPUParticles3D", true, false) + main.get_tree().root.find_children("*", "GPUParticles3D", true, false)
	for q in parts:
		q.visible = false
	await run.call("no particles (%d)" % parts.size())
	for q in parts:
		q.visible = true
	for l in lights:
		l.visible = false
	await run.call("no facility lights")
	for l in lights:
		l.visible = true
	p.light_on = false
	await run.call("flashlight off")
	quit()
