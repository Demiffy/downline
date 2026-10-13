# Snow on the train (the "snow_amount" global): the carriage roofs and the glass at 0, a third, two
# thirds and full, from outside on the platform and from inside at a window. Needs a window.
# Run: tests/run.sh 200 --path . -s tests/train_snow_shots.gd -- <dir> playground
extends SceneTree

var main
var pg
var out := ""


func _initialize() -> void:
	_run()


func snap(name: String) -> void:
	for i in 4:
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
	for c in pg._pages["SITES"].find_children("*", "Button", true, false):
		if (c as Button).text == "ARCTIC":
			c.pressed.emit()
	for i in 6:
		await process_frame
	while not pg._ready_done or main.busy:
		await process_frame
	main.hours = 11.0
	main.hud.visible = false
	pg.strip.visible = false
	main.weather.set_process(false)   # (we set the snow ourselves)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	var t: Node3D = main.train
	var pane: MeshInstance3D = null   # a window of the crew car, from inside
	for mi: MeshInstance3D in t.find_children("*", "MeshInstance3D", true, false):
		if mi.material_override == load("res://src/art.gd").rain_glass() and absf(t.to_local(mi.global_position).z) > 2.0 and absf(t.to_local(mi.global_position).x) < 8.0:
			pane = mi
			break
	var pl: Vector3 = t.to_local(pane.global_position)
	var inward := Vector3(0, 0, -signf(pl.z))
	for k in 4:
		var amt := k / 3.0
		RenderingServer.global_shader_parameter_set("snow_amount", amt * 0.6)
		RenderingServer.global_shader_parameter_set("glass_mist", amt * 0.85)
		cam.look_at_from_position(t.to_global(Vector3(-2.0, 8.5, -10.0)), t.to_global(Vector3(-6.0, 3.4, 0.0)))   # (from the open side, over the track)
		await snap("roof_%d" % k)
		for side in [-1.0, 1.0]:   # the crew car's side windows (train.gd _car: x -1.2, sill 1 m up the 1 m floor)
			cam.look_at_from_position(t.to_global(Vector3(-1.2, 2.5, side * 1.0)), t.to_global(Vector3(-1.2, 2.5, side * 2.4)))
			await snap("glass_%d_%d" % [k, int(side)])
	quit()
