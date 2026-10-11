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
	var setup := 0.0
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
		setup += RenderingServer.get_frame_setup_time_cpu()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	print("%-22s frame %5.2f ms (worst %5.1f)  process %5.2f  physics %5.2f  setup %5.2f  render-cpu %5.2f  gpu %5.2f  draws %5d  objects %5d  prims %7dk" % [label, ms, worst,
		proc / n, phys / n, setup / n, cpu_r / n, gpu / n, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
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
	var lights: Array = main.find_children("*", "Light3D", true, false)
	var shadowed: Array = lights.filter(func(l): return l.shadow_enabled and l.visible)
	var bodies: Array = main.find_children("*", "CollisionObject3D", true, false)
	var meshes: Array = main.find_children("*", "MeshInstance3D", true, false)
	var audio: Array = main.find_children("*", "AudioStreamPlayer3D", true, false)
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
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # (the game's own settings turned it back on)
	Engine.max_fps = 0
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
	_mesh_census(fac)
	if OS.get_cmdline_user_args().has("breakdown"):
		await _breakdown(fac)
	quit()


## How the facility's meshes break down: merged chunks and their surfaces, distinct materials and
## textures, and what's left unmerged (by why).
func _mesh_census(fac) -> void:
	var chunks := 0
	var surfaces := 0
	var mats := {}
	var texs := {}
	var unmerged := {}
	for mi: MeshInstance3D in fac.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree():
			continue
		if mi.mesh is ArrayMesh and mi.get_parent() in [fac, fac.low_root]:
			chunks += 1
			surfaces += mi.mesh.get_surface_count()
			for k in mi.mesh.get_surface_count():
				var m = mi.mesh.surface_get_material(k)
				mats[m] = true
				if m is StandardMaterial3D:
					texs[[m.albedo_texture, m.uv1_scale, m.emission_enabled]] = true
			continue
		var why := "other"
		var n: Node = mi
		while n != null and n != fac:
			if n.has_meta("live"):
				why = "live"
				break
			if n.get_script() != null:
				why = "script " + n.get_script().resource_path.get_file()
				break
			if n is RigidBody3D:
				why = "rigid"
				break
			n = n.get_parent()
		unmerged[why] = unmerged.get(why, 0) + 1
	print("merged chunks %d, surfaces %d, materials %d, texture+tile combos %d" % [chunks, surfaces, mats.size(), texs.size()])
	print("unmerged: ", unmerged)
	var others := {}
	for mi: MeshInstance3D in fac.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh is ArrayMesh and mi.get_parent() in [fac, fac.low_root]:
			continue
		var n: Node = mi
		var plain := true
		while n != null and n != fac:
			if n.has_meta("live") or n.get_script() != null:
				plain = false
				break
			n = n.get_parent()
		if plain:
			var k := "%s in %s (%s)" % [mi.mesh.get_class() if mi.mesh else "null", mi.get_parent().name.left(12), "vis" if mi.is_visible_in_tree() else "hidden"]
			others[k] = others.get(k, 0) + 1
	var ok := others.keys()
	ok.sort_custom(func(a, b): return others[a] > others[b])
	for k in ok.slice(0, 12):
		print("   other %4d  %s" % [others[k], k])
	var owners := {}
	for mi: MeshInstance3D in fac.find_children("*", "MeshInstance3D", true, false):
		var n: Node = mi.get_parent()
		while n != null and n != fac and n.get_script() == null and not n.has_meta("live"):
			n = n.get_parent()
		if n == null or n == fac:
			continue
		var k: String = (n.prompt if "prompt" in n else String(n.name)) + " | " + (n.get_script().resource_path.get_file() if n.get_script() else "live")
		owners[k] = owners.get(k, 0) + 1
	var ks := owners.keys()
	ks.sort_custom(func(a, b): return owners[a] > owners[b])
	for k in ks.slice(0, 15):
		print("   %4d  %s" % [owners[k], k])


## What each thing costs in the facility: the same spot with one thing off at a time.
func _breakdown(fac) -> void:
	var c: Vector2i = fac.layout.cells[0]
	var o: Vector3 = fac.to_global(Vector3(c.x * 12.0, 0.05, c.y * 12.0))
	look(o + Vector3(-4, 0, -4), o + Vector3(6, 1.2, 6))
	main.player.frozen = true
	await measure("fac baseline")
	var lights: Array = main.find_children("*", "Light3D", true, false)
	var shadowed: Array = lights.filter(func(l): return l.shadow_enabled)
	for l in shadowed:
		l.shadow_enabled = false
	await measure("  no shadows")
	for l in lights:
		if is_instance_valid(l):
			l.visible = false
	await measure("  no lights at all")
	for l in lights:
		if is_instance_valid(l):
			l.visible = true
	for l in shadowed:
		if is_instance_valid(l):
			l.shadow_enabled = true
	var mobs: Array = get_nodes_in_group("monsters")
	for m in mobs:
		m.process_mode = Node.PROCESS_MODE_DISABLED
	await measure("  monsters off (%d)" % mobs.size())
	for m in mobs:
		m.process_mode = Node.PROCESS_MODE_INHERIT
	var picks: Array = main.find_children("*", "RigidBody3D", true, false)
	for q in picks:
		q.process_mode = Node.PROCESS_MODE_DISABLED
	await measure("  rigid bodies off (%d)" % picks.size())
	for q in picks:
		q.process_mode = Node.PROCESS_MODE_INHERIT
	var snd: Array = root.find_children("*", "AudioStreamPlayer3D", true, false)
	for q in snd:
		q.process_mode = Node.PROCESS_MODE_DISABLED
	await measure("  3D sounds stopped (%d)" % snd.size())
	for q in snd:
		q.process_mode = Node.PROCESS_MODE_INHERIT
	var cats := {}
	for mi: MeshInstance3D in fac.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh is ArrayMesh and mi.get_parent() in [fac, fac.low_root]:
			continue
		var why := "other"
		var n: Node = mi
		while n != null and n != fac:
			if n.has_meta("live"):
				why = "live"
				break
			if n.get_script() != null:
				why = n.get_script().resource_path.get_file()
				break
			n = n.get_parent()
		if not cats.has(why):
			cats[why] = []
		cats[why].append(mi)
	for k in cats:
		var shown: Array = cats[k].filter(func(m): return is_instance_valid(m) and m.visible)
		for m in shown:
			m.visible = false
		await measure("  hide %s (%d)" % [k, shown.size()], 60)
		for m in shown:
			if is_instance_valid(m):
				m.visible = true
	for dist in [30.0, 22.0]:
		for l in lights:
			if is_instance_valid(l) and l.distance_fade_enabled:
				l.distance_fade_begin = minf(l.distance_fade_begin, dist)
		await measure("  lights fade at %d m" % dist)
	fac.visible = false
	await measure("  facility hidden")
	fac.visible = true
	main.level.visible = false
	await measure("  level hidden")
	main.level.visible = true
	main.train.visible = false
	await measure("  train hidden")
	main.train.visible = true
	if OS.get_cmdline_user_args().has("short"):
		quit()
		return
	# Each script that runs every frame, switched off on its own (process only; physics stays).
	var by: Dictionary = {}
	for n in root.find_children("*", "", true, false):
		if n.is_processing() and n.get_script() != null:
			var k: String = n.get_script().resource_path.get_file()
			if not by.has(k):
				by[k] = []
			by[k].append(n)
	for k in by:
		for n in by[k]:
			n.set_process(false)
		await measure("  -%s x%d" % [k, by[k].size()], 60)
		for n in by[k]:
			n.set_process(true)
	main.env.volumetric_fog_enabled = false
	main.env.ssao_enabled = false
	main.env.glow_enabled = false
	await measure("  no fog/ssao/glow")
	main.env.volumetric_fog_enabled = true
	main.env.ssao_enabled = true
	main.env.glow_enabled = true
	main.player.cam.far = 30.0
	await measure("  camera far 30 m")
