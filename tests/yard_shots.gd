# The checkpoint's life: the clerk at the shop window, the crane carrying a bale, a train going by.
# Needs a window. Run: godot --path . -s tests/yard_shots.gd -- <out_dir>
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
	var life = main.level.get_node("YardLife")
	var lvl = main.level
	# The clerk, from in front of the window.
	p.global_position = lvl.to_global(Vector3(-14.0, 0.1, 10.6))
	p.look_at(lvl.to_global(Vector3(-14.0, 0.1, 14.0)))
	p.rotation = Vector3(0, p.rotation.y, 0)
	p.head.rotation.x = -0.05
	life.clerk_stamp()
	await shot(out, "y_clerk", 40)
	# The crane, partway through its job.
	life._job = 3
	life._x = 1.0
	life._drop = 2.0
	life._load.visible = true
	p.global_position = lvl.to_global(Vector3(34.0, 0.1, 4.0))
	p.look_at(lvl.to_global(Vector3(20.0, 5.0, 20.0)))
	p.rotation = Vector3(0, p.rotation.y, 0)
	p.head.rotation.x = 0.35
	await shot(out, "y_crane", 30)
	# A train on the far line.
	life._next_train = 0.0
	await process_frame
	await process_frame   # (sent during the frame after)
	life._train_x = 0.0
	p.global_position = lvl.to_global(Vector3(-6.0, 0.1, -17.0))
	p.look_at(lvl.to_global(Vector3(4.0, 1.5, -27.0)))
	p.rotation = Vector3(0, p.rotation.y, 0)
	p.head.rotation.x = 0.05
	await shot(out, "y_train", 10)
	quit()
