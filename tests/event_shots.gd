# The things that happen on the line, forced on and photographed as they happen: the dead halt and
# the figure on it, a squall's wall coming at you and the inside of it, the freight coming through the
# loop, the power failing in the tunnel, the thing in the headlight and going past the windows.
# Needs a window; real time.
# Run: godot --path . -s tests/event_shots.gd -- <out_dir> [hour] [events, comma separated]
extends SceneTree

var out := ""
var main
var cam: Camera3D


func _initialize() -> void:
	_run()


func shot(name: String, pos: Vector3, at: Vector3) -> void:
	cam.global_position = main.train.to_global(pos)
	cam.look_at(main.train.to_global(at))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name, " s=%.0f" % main.line.s)


func until(f: Callable) -> bool:
	while main.line.riding and not f.call():
		await process_frame
	return main.line.riding


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://events"
	DirAccess.make_dir_recursive_absolute(out)
	Engine.set_meta("force_events", (args[2] if args.size() > 2 else "halt,freight,power,thing,squall").split(","))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	main.hud.visible = false
	main.player.frozen = true
	main.player.global_position = main.train.to_global(Vector3(-3, 1.3, 0))
	cam = Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 64
	cam.far = 3000.0
	main.term.run("LEAVE_CHECKPOINT")
	for trip in 2:
		var d: Dictionary = main.route[trip][0]
		d.biome = "DESERT"
		d.weather = "CLEAR"
		if trip == 1 and args.size() > 1 and args[1] != "-":
			main.hours = float(args[1])
		main.term.run("ROUTE_TO " + d.letter)
		while not main.line.riding:
			await process_frame
		if trip == 0:
			while main.busy:
				await process_frame
			continue
		var l = main.line
		var ev = l.events
		var t: Dictionary = l._segs.filter(func(g): return g.kind == "tunnel" and g.b > 0.0)[0]
		var legA: Array = l._segs.filter(func(g): return g.kind == "open" and g.leaving and g.a >= 0.0)
		if ev._fgo != INF:
			await until(func(): return ev._fmoving and ev._fhead - (l.s + 17.8) < 200.0)
			await shot("11_freight_coming", Vector3(17.9, 2.6, -0.4), Vector3(120, 2.0, -21.0))
			await until(func(): return ev._fmoving and ev._fhead < l.s + 8.0)
			await shot("12_freight_window", Vector3(0.5, 2.3, 0.6), Vector3(1.5, 2.0, -8.0))
			await shot("13_freight_outside", Vector3(-25, 8.0, 12.0), Vector3(30, 1.5, -18.0))
		if not legA.is_empty() and legA[0].halt != INF:
			var hx: float = legA[0].halt
			await until(func(): return l.s > hx - 45.0)
			await shot("01_halt_ahead", Vector3(15.0, 3.0, 1.6), Vector3(60, 1.5, 6))
			await until(func(): return l.s > hx - 6.0)
			await shot("02_halt_window", Vector3(-1.0, 2.3, 1.2), Vector3(-1.0, 2.0, 8.0))
			await until(func(): return l.s > hx + 60.0)
			await shot("03_halt_behind", Vector3(-14.5, 2.6, 1.0), Vector3(-80, 1.5, 4))
		if ev._thing_at != INF:   # watched from a window, as a crew would see it
			cam.global_position = main.train.to_global(Vector3(-1.2, 2.2, 1.0))
			await until(func(): return ev._tstate == "chase" and ev._tx > l.s + ev._twin - 10.0)
			await shot("05_thing_coming", Vector3(-1.2, 2.6, 1.6), Vector3(-6.0, 1.8, 4.0))
			await until(func(): return ev._tstate == "pace" and ev._tt > 0.8)
			await shot("06_thing_at_the_window", Vector3(-1.2, 2.6, 1.4), Vector3(-1.0, 2.0, 6.0))
			await until(func(): return ev._tstate == "pace" and ev._tt > 2.0)
			await shot("07_thing_at_the_window_wide", Vector3(-2.6, 2.6, -1.0), Vector3(-0.8, 2.0, 6.0))
		if ev._power != Vector2.INF:
			await until(func(): return main.train._emerg[0][0].light_energy > 1.5 or l.s > ev._power.y - 5.0)
			await shot("04_power_out", Vector3(-6.0, 2.2, 0.6), Vector3(7.0, 1.6, -0.6))
			await until(func(): return l.s > ev._power.y + 2.0)
			await shot("08_power_back", Vector3(-6.0, 2.2, 0.6), Vector3(7.0, 1.6, -0.6))
		if not ev._wx.is_empty():
			await until(func(): return l.s > t.b + 40.0)
			await shot("09_squall_ahead", Vector3(17.9, 2.6, 0.0), Vector3(120, 8.0, 0))
			await until(func(): return main.line_mix > 0.9)
			await shot("10_in_the_squall", Vector3(-1.5, 2.4, 1.0), Vector3(-1.5, 2.2, 6.0))
			await shot("10b_in_the_squall_ahead", Vector3(17.9, 2.6, 0.0), Vector3(80, 3.0, 0))
		while main.busy:
			await process_frame
	quit()
