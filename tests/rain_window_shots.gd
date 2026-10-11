# Rain on the train's windows at a stand, at half speed and at full speed (the water driven back
# along the glass). Needs a window.
# Run: godot --path . -s tests/rain_window_shots.gd -- <out_dir>
extends SceneTree


func _initialize() -> void:
	_run()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://rain"
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	main.hud.visible = false
	main.player.frozen = true
	main.weather.set_process(false)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 55
	cam.global_position = main.train.to_global(Vector3(-1.2, 2.5, 1.3))
	cam.look_at(main.train.to_global(Vector3(-1.2, 2.45, 2.2)))
	for w in [0.0, 0.5, 1.0]:
		RenderingServer.global_shader_parameter_set("rain_amount", 1.0)
		RenderingServer.global_shader_parameter_set("rain_wind", w)
		for i in 20:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/rain_%d.png" % [out, int(w * 100)])
	quit()
