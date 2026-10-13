# The cold (player.gd, hud.breathe, Suit.set_vapour): on an arctic stop, your breath misting the
# visor (a few moments apart, at rest and blown), and your suit steaming seen from outside.
# Needs a window. Run: tests/run.sh 200 --path . -s tests/cold_shots.gd -- <dir> playground
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
	pg.strip.visible = false
	main.hours = 11.0
	var lv = main.level
	main.player.global_position = lv.to_global(Vector3(20, lv.ground_y(20, 50) + 0.3, 50))
	await create_timer(2.0).timeout
	for k in 6:   # a breath every few seconds: catch one blooming
		await create_timer(0.55).timeout
		await snap("breath_%d" % k)
	main.player.stamina = 0.0   # blown
	await create_timer(1.6).timeout
	await snap("breath_blown")
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	var p: Vector3 = main.player.global_position
	main.hud.visible = false
	cam.look_at_from_position(p + Vector3(1.3, 1.7, 1.3), p + Vector3(0, 1.4, 0))
	await create_timer(2.0).timeout
	await snap("vapour")
	quit()
