# The checkpoint and the train: aerial views and the train's interior. Needs a window.
# Run: godot --path . -s tests/cp_shots.gd -- <out_dir>
extends SceneTree


func _initialize() -> void:
	_run()


func shot(out: String, name: String, frames := 20) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	main.hud.visible = false
	var p = main.player
	p.frozen = true
	var cam := Camera3D.new()
	cam.far = 2000.0
	main.add_child(cam)
	cam.current = true
	var t: Vector3 = main.train.global_position
	for v in [["air_high", Vector3(-60, 70, 80), Vector3(0, 0, 0)], ["air_low", Vector3(50, 25, -50), Vector3(0, 0, 5)],
			["ground_edge", Vector3(-30, 2, 30), Vector3(-200, 5, 120)], ["ground_yard", Vector3(10, 2, -5), Vector3(20, 3, 25)]]:
		cam.global_position = t + v[1]
		cam.look_at(t + v[2])
		await shot(out, "cp_" + v[0], 30)
	cam.current = false
	p.cam.current = true
	for v in [["in_front", Vector3(-6.0, 1.0, 0.0), 90.0, 0.0], ["in_back", Vector3(6.0, 1.0, 0.5), -90.0, 0.0], ["in_side", Vector3(0.0, 1.0, -1.2), 0.0, -0.1]]:
		p.global_position = t + v[1]
		p.rotation = Vector3(0, deg_to_rad(v[2]), 0)
		p.head.rotation.x = v[3]
		await shot(out, "tr_" + v[0], 20)
	quit()
