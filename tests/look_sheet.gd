# Crew looks side by side, front and back. Needs a window.
# Run: godot --path . -s tests/look_sheet.gd -- <out_dir>
extends SceneTree

const Suit = preload("res://src/suit.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var w := Node3D.new()
	root.add_child(w)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.2, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.2
	w.add_child(sun)
	var looks := [[0, 0, 0], [1, 2, 1], [2, 5, 2], [3, 1, 3], [4, 3, 4], [5, 4, 5], [6, 6, 1], [7, 7, 2]]
	var figs := []
	for i in looks.size():
		var b := Node3D.new()
		w.add_child(b)
		b.position = Vector3((i - 3.5) * 0.85, 0, 0)
		Suit.standing(b)
		Suit.apply_look(b, looks[i], "CREW %d" % i)
		figs.append(b)
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.position = Vector3(0, 1.2, 5.2)
	cam.look_at(Vector3(0, 1.0, 0))
	cam.current = true
	for k in 2:
		for f in figs:
			f.rotation.y = 0.0 if k == 0 else PI
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/looks_%s.png" % [out, "front" if k == 0 else "back"])
	cam.position = Vector3(-1.1, 1.75, 1.2)
	cam.look_at(Vector3(-0.42, 1.65, 0))
	for f in figs:
		f.rotation.y = -0.9
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/looks_heads.png" % out)
	quit()
