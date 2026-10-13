# The sky by hour (weather.gd's SKY): dawn and dusk toward the sun (the warm band on the horizon),
# and at night the moon, the stars and the galaxy's band. Needs a window.
# Run: tests/run.sh 200 --path . -s tests/sky_night_shots.gd -- <dir> playground
extends SceneTree

var main
var pg
var out := ""


func _initialize() -> void:
	_run()


func snap(name: String) -> void:
	for i in 8:
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
	main.stop.weather = "CLEAR"
	main.hud.visible = false
	pg.strip.visible = false
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 70
	var lv = main.level   # (out in the open, away from the buildings; the player stands there too, so it's "outside")
	var p: Vector3 = lv.to_global(Vector3(20, lv.ground_y(20, 55) + 1.7, 55))
	main.player.global_position = p - Vector3(0, 1.5, 0) + Vector3(0, 0, -4.0)   # (beside the camera, not round it)
	for hr in [[6.4, "dawn"], [19.6, "dusk"], [23.0, "night"]]:
		main.hours = hr[0]
		await create_timer(0.3).timeout
		var sun: Vector3 = -main.sun.global_transform.basis.z   # (toward the light)
		var flat := Vector3(-sun.x, 0, -sun.z).normalized()
		cam.look_at_from_position(p, p + flat * 10.0 + Vector3(0, 1.2, 0))
		await snap("%s_sun_side" % hr[1])
		if hr[1] == "night":
			cam.look_at_from_position(p, p + Vector3(sun.x, 0, sun.z).normalized() * 10.0 + Vector3(0, 8.0, 0))
			await snap("night_moon_side")
			cam.look_at_from_position(p, p + Vector3(0.1, 10.0, 0.3))
			await snap("night_up")
	quit()
