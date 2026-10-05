# Visual check: poses the player around the world and saves screenshots. Needs a window (not headless).
# Run: godot --path . -s tests/shots.gd -- <out_dir> [THEME]
# Facility room shots get a temporary fill light so the dressing is visible (the real game is darker).
extends SceneTree

var main
var out := "user://shots"
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


func secs(t: float) -> void:
	await main.get_tree().create_timer(t).timeout


func shot(name: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func look(pos: Vector3, at: Vector3) -> void:
	var p = main.player
	p.global_position = pos
	var d := at - (pos + Vector3(0, 1.6, 0))
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(40)
	main.player.hp = 100
	main.player.slots[0] = {"id": "FLASHLIGHT", "charge": 200.0}
	look(Vector3(-5, 1.05, 1.2), Vector3(6.6, 1.6, -1.8))
	await shot("01_train_interior")
	look(Vector3(25, 0.1, 8), Vector3(14, 1.8, 0))
	await shot("02_locomotive")
	look(Vector3(-4, 1.05, 5.0), Vector3(-9, 1.5, 13))
	await shot("03_checkpoint_shop_shredder")
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = theme
	stop.rooms = 26
	stop.weather = "CLEAR"
	stop.biome = "DESERT"
	main.player.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	await frames(30)
	var lvl = main.level
	var el = lvl.elevator
	var e: Vector3 = lvl.elevator_pos
	look(Vector3(-3, 1.05, 5.5), e + Vector3(0, 6, 0))
	await shot("04_station")
	look(e + Vector3(-12, lvl.ground_y(e.x - 12, e.z - 16) + 0.1, -16), e + Vector3(0, 8, 0))
	await shot("05_headframe")
	look(e + Vector3(1.2, 0.2, -6.0), e + Vector3(0, 1.4, 0))
	await shot("06_lift_landing_open")
	look(el.cab.global_position + Vector3(0.6, 0.2, 1.0), el.cab.global_position + Vector3(0, 1.3, -4))
	el.ride()
	await secs(0.7)
	await shot("07_doors_closing")
	while el.moving:
		await process_frame
	await frames(30)
	look(el.cab.global_position + Vector3(0.3, 0.2, 1.0), el.cab.global_position + Vector3(0, 1.3, -6))
	await shot("08_bottom_landing")
	var fac = lvl.facility
	var done := {}
	for c in fac.layout.cells:
		var kind: String = fac.kinds[c]
		if done.has(kind) or kind == "start":
			continue
		done[kind] = true
		var o: Vector3 = fac.to_global(Vector3(c.x * 12.0, 0, c.y * 12.0))
		var fill := OmniLight3D.new()
		fill.omni_range = 16.0
		fill.light_energy = 1.3
		fill.light_color = Color(1, 0.85, 0.7)
		main.add_child(fill)
		fill.global_position = o + Vector3(0, 3.0, 0)
		if kind == "pit":
			look(o + Vector3(0, 0.2, 0), o + Vector3(4, -2.5, 4))
		elif kind == "tunnel":
			var axis := Vector3(1, 0, 0) if fac.layout.links[c].has(c + Vector2i(1, 0)) else Vector3(0, 0, 1)
			look(o + axis * 5.0 + Vector3(0, 0.2, 0), o - axis * 6.0 + Vector3(0, 1.4, 0))
		else:
			look(o + Vector3(1.0, 0.2, 1.0), o + Vector3(-4, 0.6, -4))
		await shot("room_%s" % kind)
		look(o + Vector3(-1.0, 0.2, -1.0), o + Vector3(4, 0.6, 4))
		await shot("room_%s_b" % kind)
		fill.queue_free()
	main.hours = 20.5
	look(Vector3(-20, 0.1, 9), Vector3(4, 2, 0))
	await frames(10)
	await shot("99_night_train")
	quit()
