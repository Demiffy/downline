# Blood smeared along the floor (blood.gd smear): a hurt walk (narrow) and a crawl (wide) along a bend,
# on the station's ground and on the train's floor, fresh and then dried. Needs a window.
# Run: tests/run.sh 150 --path . -s tests/smear_shots.gd -- <dir> playground
extends SceneTree

const Blood = preload("res://src/blood.gd")
var main
var pg
var out := ""


func _initialize() -> void:
	_run()


func snap(name: String) -> void:
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func trail(host: Node3D, from: Vector3, dir: Vector3, n: int, width: float) -> void:
	var at := from
	for i in n:
		var next := at + dir.rotated(Vector3.UP, i * 0.12) * 0.7
		Blood.smear(host, at, next, width)
		at = next


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
	for c in pg._pages["SITES"].find_children("*", "Button", true, false):   # (out in the open, by day)
		if (c as Button).text == "DESERT":
			c.pressed.emit()
	for i in 6:
		await process_frame
	while not pg._ready_done or main.busy:
		await process_frame
	main.hud.visible = false
	pg.strip.visible = false
	main.hours = 12.0
	var t: Node3D = main.train
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	# On the train's floor, down the aisle.
	trail(t, t.to_global(Vector3(4.0, 1.1, 0.4)), t.global_basis * Vector3(-1, 0, 0), 9, 0.2)
	trail(t, t.to_global(Vector3(4.0, 1.1, -0.6)), t.global_basis * Vector3(-1, 0, 0), 9, 0.4)
	cam.look_at_from_position(t.to_global(Vector3(5.5, 3.0, 0.0)), t.to_global(Vector3(0.5, 1.0, 0.0)))
	await snap("train_fresh")
	# Out on the ground beside the train.
	var g := t.to_global(Vector3(-2.0, 0.5, -6.0))
	trail(main.level, g, t.global_basis * Vector3(1, 0, 0), 10, 0.2)
	trail(main.level, g + t.global_basis * Vector3(0, 0, -1.2), t.global_basis * Vector3(1, 0, 0), 10, 0.4)
	cam.look_at_from_position(g + t.global_basis * Vector3(-1.5, 2.6, -0.6), g + t.global_basis * Vector3(3.0, 0.0, -0.6))
	await snap("ground_fresh")
	for d in t.find_children("*", "Decal", true, false) + main.level.find_children("*", "Decal", true, false):
		d.modulate = Color(0.42, 0.3, 0.3)   # (dried)
	await snap("ground_dry")
	quit()
