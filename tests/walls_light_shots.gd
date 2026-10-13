# Light, fog and weather against walls, at night at a station (main._shadow_tick, TRAIN_BIT,
# train._sealed): the train from beside it (the car's lamps light the ground only through its
# windows), from the platform, inside it with a blizzard blowing and thick fog (none inside), and
# the bottom of the lift shaft (the shaft's lamps don't light the landing through its walls).
# Needs a window. Run: tests/run.sh 150 --path . -s tests/walls_light_shots.gd -- <dir> playground
extends SceneTree

var main
var pg
var out := ""


func _initialize() -> void:
	_run()


func snap(name: String) -> void:
	for i in 30:   # (the shadow budget looks round every 0.2 s; far lamps come back in 0.25 s)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	while pg == null:
		for c in main.get_children():
			if c.get_script() != null and c.get_script().resource_path.ends_with("playground.gd"):
				pg = c
		await process_frame
	while not pg._ready_done or main.busy:
		await process_frame
	main.hud.visible = false
	pg.strip.visible = false
	main.hours = 22.5
	var t: Node3D = main.train
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.look_at_from_position(t.to_global(Vector3(-4.0, 1.7, -8.0)), t.to_global(Vector3(2.0, 1.0, 0.0)))
	await snap("beside")
	cam.look_at_from_position(t.to_global(Vector3(0.0, 16.0, -6.0)), t.to_global(Vector3(0.0, 0.0, -4.0)))
	await snap("from_above")
	cam.look_at_from_position(t.to_global(Vector3(-4.0, 2.2, 6.5)), t.to_global(Vector3(3.0, 1.0, 0.0)))
	await snap("platform")
	main.player.global_position = t.to_global(Vector3(0, 1.1, 0))   # (the weather follows you)
	main.player.set_weather("BLIZZARD")
	main.env.volumetric_fog_density = 0.08
	cam.look_at_from_position(t.to_global(Vector3(6.0, 2.6, 1.2)), t.to_global(Vector3(-6.0, 1.8, -0.5)))
	await snap("inside_blizzard")
	cam.look_at_from_position(t.to_global(Vector3(3.0, 2.6, -5.0)), t.to_global(Vector3(3.0, 2.0, 0.0)))
	await snap("outside_blizzard")
	main.player.set_weather("")
	var el = main.level.elevator
	cam.look_at_from_position(el.to_global(Vector3(1.2, el.bottom + 1.6, -5.5)), el.to_global(Vector3(0.0, el.bottom + 1.4, 0.0)))
	await snap("lift_bottom")
	quit()
