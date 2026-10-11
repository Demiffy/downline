# Every creature, frozen and lit, from four sides: a sheet per creature for checking the models.
# Needs a window. Run: godot --path . -s tests/creature_sheet.gd -- <out_dir> [name...]
extends SceneTree

const KINDS := ["husk", "marionette", "mimic", "observer", "pulsator", "roomba", "scrapper", "siren", "statue", "warden", "wraith", "snatcher", "gloe"]
var main


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://shots"
	var only: Array = args.slice(1)
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.rng.seed = 7
	main.term.run("LEAVE_CHECKPOINT")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	while main.busy:
		await process_frame
	main.hud.visible = false
	var lvl = main.level
	var fac = lvl.facility
	for n in lvl.get_children():
		if n.is_in_group("monsters") or n.is_in_group("fauna"):
			n.free()
	var p = main.player
	p.frozen = true
	var spot: Vector3 = main.train.global_position + Vector3(6, 0, -14)   # open ground beside the line
	var hit: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3(0, 30, 0), spot + Vector3(0, -30, 0), 1))
	if not hit.is_empty():
		spot = hit.position + Vector3(0, 0.05, 0)
	main.hours = 12.0
	main.stop.weather = "CLEAR"
	p.global_position = spot + Vector3(0, 0, 40)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	var fill := OmniLight3D.new()
	fill.omni_range = 12.0
	fill.light_energy = 1.6
	main.add_child(fill)
	var key := OmniLight3D.new()
	key.omni_range = 10.0
	key.light_energy = 2.5
	key.light_color = Color(1.0, 0.9, 0.75)
	main.add_child(key)
	for k in KINDS:
		if not only.is_empty() and not k in only:
			continue
		var c = load("res://src/%s.gd" % k).new()
		if "main" in c:
			c.main = main
		if "level" in c:
			c.level = lvl
		lvl.add_child(c)
		c.global_position = spot
		for i in 20:
			await physics_frame
		c.global_position = spot
		c.rotation = Vector3.ZERO
		c.set_physics_process(false)
		c.process_mode = Node.PROCESS_MODE_DISABLED
		var box := AABB()
		var first := true
		for mi: VisualInstance3D in c.find_children("*", "VisualInstance3D", true, false):
			if mi is MeshInstance3D and mi.is_visible_in_tree():
				var b: AABB = mi.global_transform * mi.get_aabb()
				box = b if first else box.merge(b)
				first = false
		var centre: Vector3 = box.get_center() if not first else spot + Vector3(0, 1, 0)
		var r: float = maxf(box.size.length() * 0.85, 1.2) if not first else 2.5
		fill.global_position = centre + Vector3(0, r, r)
		key.global_position = centre + Vector3(r, r * 0.6, -r * 0.4)
		var sheet: Image = null
		for a in 4:
			var ang := TAU * a / 4.0 + 0.5
			cam.global_position = centre + Vector3(sin(ang) * r, r * 0.35, cos(ang) * r)
			cam.look_at(centre)
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.resize(img.get_width() / 2, img.get_height() / 2)
			if sheet == null:
				sheet = Image.create(img.get_width() * 2, img.get_height() * 2, false, img.get_format())
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((a % 2) * img.get_width(), (a / 2) * img.get_height()))
		sheet.save_png("%s/%s.png" % [out, k])
		print("%s: size %s" % [k, box.size.snapped(Vector3.ONE * 0.01)])
		c.queue_free()
		await process_frame
	quit()
