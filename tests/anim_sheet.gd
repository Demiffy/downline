# Animation contact sheet: builds one animated prop in an empty lit scene, takes N screenshots spread
# over a time span, and saves them as one image (a grid, each tile stamped with its time).
#   godot --path . -s tests/anim_sheet.gd -- <engine|engine_side|engine_close|pumpjack|shed> <out.png> [span_s] [frames]
# Default span is one full cycle (engine: one turn of the crank, 0.25 s; pumpjack: one stroke, 3.4 s).
extends SceneTree

var cam: Camera3D


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var what: String = args[0] if args.size() > 0 else "engine"
	var out: String = args[1] if args.size() > 1 else "/tmp/anim.png"
	var span: float = float(args[2]) if args.size() > 2 else (3.4 if what == "pumpjack" else 0.25)
	var n: int = int(args[3]) if args.size() > 3 else 8
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.34, 0.38)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.72)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	world.add_child(sun)
	var P = load("res://src/props.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	world.add_child(floor_mi)
	cam = Camera3D.new()
	cam.fov = 55
	world.add_child(cam)
	match what:
		"pumpjack":
			P.pumpjack(world, Vector3.ZERO, 0.0)
			_look(Vector3(1.0, 3.0, 10.5), Vector3(0.6, 2.6, 0))
		"shed":   # (still: a turntable instead)
			var holder := Node3D.new()
			world.add_child(holder)
			P.tin_shed(holder, Vector3.ZERO, 0.0, rng)
			holder.set_script(null)
			var tw := holder.create_tween().set_loops()
			tw.tween_property(holder, "rotation:y", TAU, span)
			_look(Vector3(0, 2.4, -7.5), Vector3(0, 1.3, 0))
		"engine_close":
			P.generator(world, Vector3.ZERO, 0.0, rng, 3.0)
			_look(Vector3(-0.15, 1.25, -1.0), Vector3(-0.15, 1.2, 0))
		"engine_side":
			P.generator(world, Vector3.ZERO, 0.0, rng, 3.0)
			_look(Vector3(-0.35, 1.15, -1.7), Vector3(-0.35, 1.1, 0))   # the open side, away from the day tank
		_:
			P.generator(world, Vector3.ZERO, 0.0, rng, 3.0)
			_look(Vector3(0.9, 1.7, -2.9), Vector3(-0.3, 1.1, 0))
	for i in 20:
		await process_frame
	var tiles: Array[Image] = []
	var t0 := Time.get_ticks_msec()
	for k in n:
		var due := t0 + int(k * span / maxf(1.0, n - 1.0) * 1000.0) if n > 1 else t0
		while Time.get_ticks_msec() < due:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.resize(img.get_width() / 2, img.get_height() / 2)
		_stamp(img, Time.get_ticks_msec() - t0)
		tiles.append(img)
	var cols := 4
	var rows := ceili(float(n) / cols)
	var tw := tiles[0].get_width()
	var th := tiles[0].get_height()
	var sheet := Image.create(tw * cols, th * rows, false, tiles[0].get_format())
	for k in tiles.size():
		sheet.blit_rect(tiles[k], Rect2i(0, 0, tw, th), Vector2i((k % cols) * tw, (k / cols) * th))
	sheet.save_png(out)
	print("saved ", out, "  (", n, " frames over ", span, " s)")
	quit()


func _look(from: Vector3, at: Vector3) -> void:
	cam.position = from
	cam.look_at_from_position(from, at, Vector3.UP)


## Time label in the corner, drawn as blocky digits (no fonts needed in an Image).
func _stamp(img: Image, ms: int) -> void:
	var txt := "%d" % ms
	var glyph := {"0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111", "4": "101101111001001",
		"5": "111100111001111", "6": "111100111101111", "7": "111001001001001", "8": "111101111101111", "9": "111101111001111"}
	img.fill_rect(Rect2i(6, 6, 18 * txt.length() + 30, 34), Color(0, 0, 0, 0.8))
	for i in txt.length():
		var g: String = glyph[txt[i]]
		for b in 15:
			if g[b] == "1":
				img.fill_rect(Rect2i(12 + i * 18 + (b % 3) * 5, 10 + (b / 3) * 5, 5, 5), Color(1, 0.8, 0.3))
	img.fill_rect(Rect2i(12 + txt.length() * 18, 30, 4, 4), Color(1, 0.8, 0.3))   # (ms)
