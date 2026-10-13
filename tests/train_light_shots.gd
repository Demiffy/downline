# Light and the train's walls, at night at a station: from the platform (the car's lamps light the
# platform only through its windows), and from inside with a bare tunnel lamp just outside the wall
# (it mustn't light the inside). Each with the fix on and off (main.TRAIN_BIT). Needs a window.
# Run: tests/run.sh 150 --path . -s tests/train_light_shots.gd -- <dir> playground
extends SceneTree

var main
var pg
var out := ""


func _initialize() -> void:
	_run()


func snap(name: String) -> void:
	for i in 12:
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
	while not pg._ready_done:
		await process_frame
	for c in pg._pages["SITES"].find_children("*", "Button", true, false):   # (out in the open)
		if (c as Button).text == "DESERT":
			c.pressed.emit()
	for i in 6:
		await process_frame
	while not pg._ready_done or main.busy:
		await process_frame
	main.hud.visible = false
	pg.strip.visible = false
	main.hours = 23.0
	var t: Node3D = main.train
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	# A bare lamp outside the crew car's wall, as a tunnel lamp passes.
	var lamp := OmniLight3D.new()
	lamp.omni_range = 9.0
	lamp.light_energy = 2.0
	lamp.light_color = Color(1.0, 0.78, 0.5)
	main.add_child(lamp)
	lamp.global_position = t.to_global(Vector3(2.0, 2.6, -3.0))
	for fix in [true, false]:
		lamp.visible = false
		cam.look_at_from_position(t.to_global(Vector3(0.0, 4.0, -10.0)), t.to_global(Vector3(0.0, 0.3, -1.5)))
		for i in 4:
			await process_frame
		if not fix:   # as it was: nothing skips the train, its lamps shadowless
			t.lamp_shadows(false)
		await snap("outside_%s" % ("fix" if fix else "old"))
		lamp.visible = true
		cam.look_at_from_position(t.to_global(Vector3(2.0, 2.0, 1.5)), t.to_global(Vector3(2.0, 1.8, -2.0)))
		for i in 4:
			await process_frame
		if not fix:
			lamp.light_cull_mask |= main.TRAIN_BIT
		await snap("inside_%s" % ("fix" if fix else "old"))
	quit()
