# Heat shimmer over the desert at noon ("heat_haze", weather._heat): the same view toward the horizon
# with none, then full, then a moment later (it moves). Needs a window.
# Run: tests/run.sh 150 --path . -s tests/heat_shots.gd -- <dir> playground
extends SceneTree

var main
var pg
var out := ""


func _initialize() -> void:
	_run()


func snap(name: String, frames := 20) -> void:
	for i in frames:
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
		if (c as Button).text == "DESERT":
			c.pressed.emit()
	for i in 6:
		await process_frame
	while not pg._ready_done or main.busy:
		await process_frame
	main.hud.visible = false
	pg.strip.visible = false
	main.hours = 13.0
	main.stop["weather"] = "CLEAR"
	main.player.global_position = main.train.to_global(Vector3(0, 1.1, 30))   # (out on the sand: the haze is for outside)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 45.0
	var t: Node3D = main.train
	cam.look_at_from_position(t.to_global(Vector3(-20, 3.0, 30)), t.to_global(Vector3(-160, 4.0, 60)))
	main.weather._haze = 0.0
	main.weather.set_process(false)
	RenderingServer.global_shader_parameter_set("heat_haze", 0.0)
	await snap("none")
	main.weather.set_process(true)
	main.weather._haze = 1.0
	await snap("full")
	await snap("full_later", 9)
	print("haze ", main.weather._haze, " quad ", main.weather._haze_quad.visible)
	quit()
