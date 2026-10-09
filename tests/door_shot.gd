# The crew car's doors: open at a stop, shutting as it pulls out. Needs a window.
extends SceneTree
var main
func _initialize() -> void:
	_run()
func shot(n: String) -> void:
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "/" + n + ".png")
	print("saved ", n)
func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30: await process_frame
	for n in main.get_children():
		if n.has_method("_show_title"): n.queue_free()
	main.hud.visible = false
	var p = main.player
	p.set_physics_process(false)
	p.frozen = true
	main.upgrades["INFIRMARY"] = true
	main.train.show_upgrade("INFIRMARY")
	p.global_position = main.train.to_global(Vector3(0.0, 1.0, -1.2))
	var d: Vector3 = main.train.to_global(Vector3(3.6, 2.0, 2.0)) - p.cam.global_position
	p.rotation.y = atan2(-d.x, -d.z)
	await shot("doors_open_inside")
	main.train.set_doors(false)
	await create_timer(1.6).timeout
	await shot("doors_shut_inside")
	p.global_position = main.train.to_global(Vector3(2.6, 0.4, 4.2))
	var d2: Vector3 = main.train.to_global(Vector3(2.6, 2.6, 2.3)) - p.cam.global_position
	p.rotation.y = atan2(-d2.x, -d2.z)
	p.head.rotation.x = atan2(d2.y, Vector2(d2.x, d2.z).length())
	await shot("doors_shut_outside")
	quit(0)
