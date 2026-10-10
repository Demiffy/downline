# Explosions: a roomba's (fire) and a pulsator's (flesh), at a few moments each. Needs a window.
# Run: tests/run.sh 120 --path . -s tests/blast_shots.gd -- <out_dir>
extends SceneTree
var main
func _initialize() -> void:
	_run()
func shot(n: String) -> void:
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
	p.global_position = Vector3(-6.0, 0.06, 18.0)
	p.rotation.y = 0.0
	p.head.rotation.x = -0.05
	var at := Vector3(-6.0, 0.6, 10.0)
	for kind in ["fire", "flesh"]:
		main.explode(at, 5.0, 0.0, "A pulsator burst next to you." if kind == "flesh" else "A roomba went off.")
		for t in [0.08, 0.25, 0.6, 1.5, 3.5]:
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < int((t - (0.0 if t == 0.08 else 0.0)) * 1000) and false:
				await process_frame
			await create_timer(t if t == 0.08 else t - [0.08, 0.25, 0.6, 1.5, 3.5][[0.08, 0.25, 0.6, 1.5, 3.5].find(t) - 1]).timeout
			await shot("%s_%.2f" % [kind, t])
		await create_timer(2.0).timeout
	quit(0)
