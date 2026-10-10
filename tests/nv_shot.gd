# Night vision in a dark facility room: before (no goggles), with the goggles, and the headlamp.
# Run: tests/run.sh 200 --path . -s tests/nv_shot.gd -- <out_dir>
extends SceneTree
var main
func _initialize() -> void:
	_run()
func shot(n: String) -> void:
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "/" + n + ".png")
	print("saved ", n)
func _run() -> void:
	Engine.set_meta("fast_test", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 20: await process_frame
	for n in main.get_children():
		if n.has_method("_show_title"): n.queue_free()
	main.rng.seed = 31
	main.term.run("LEAVE_CHECKPOINT")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	main.term.close()
	while main.busy: await process_frame
	Engine.remove_meta("fast_test")
	main.upgrades["NIGHT_VISION"] = true
	var p = main.player
	p.set_physics_process(false)
	p.frozen = true
	main.level.hazards.power_fail()   # (the lights out: what the goggles are for)
	var at: Vector3 = main.level.facility.random_point(main.level.rng)
	p.global_position = at
	p.rotation.y = 0.4
	await create_timer(1.0).timeout
	await shot("nv_0_dark")
	p.nv_on = true
	await shot("nv_1_goggles")
	p.rotation.y = 2.2
	await shot("nv_2_goggles_other_way")
	quit(0)
