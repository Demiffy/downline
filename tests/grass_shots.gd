# Ground cover (grass.gd) on every biome: grass in the forest, sedge in the swamp, dry tufts in the
# desert, stalks through the arctic snow, weeds in the town: the meadow from eye height, someone
# standing in it (the blades leaning away round their legs), the same spot with nobody there, and the
# swamp. Needs a window. Run: tests/run.sh 400 --path . -s tests/grass_shots.gd -- <dir> playground [BIOME ...]
extends SceneTree

var main
var pg
var out := ""
var cam: Camera3D


func _initialize() -> void:
	_run()


func press(page: String, label: String) -> void:
	for c in pg._pages[page].find_children("*", "Button", true, false):
		if (c as Button).text == label:
			c.pressed.emit()
	for i in 6:
		await process_frame
	while not pg._ready_done or main.busy:
		await process_frame


func shot(name: String, from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


## A grassy spot on the stop's ground (one with a field tile right there).
func grassy(lv: Node3D) -> Vector3:
	for f in lv.get_children():
		if f is MultiMeshInstance3D and f.get_script() != null and f.multimesh.instance_count > 60:
			var t: Transform3D = f.multimesh.get_instance_transform(f.multimesh.instance_count / 2)
			var p: Vector3 = lv.to_global(t.origin)
			if Vector2(p.x - lv.global_position.x, p.z - lv.global_position.z).length() > 25.0:
				return p
	return lv.to_global(Vector3(10, 0, 40))


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
	cam = Camera3D.new()
	main.add_child(cam)
	cam.fov = 65
	var bios: Array = OS.get_cmdline_user_args().slice(2)   # (after <dir> playground)
	for b in (bios if not bios.is_empty() else ["FOREST", "SWAMP", "DESERT", "ARCTIC", "CITY"]):
		await press("SITES", b)
		main.hours = 11.0
		for i in 60:
			await process_frame
		main.hud.visible = false
		pg.strip.visible = false
		pg.fly = true   # (so nothing moves the player but us)
		cam.current = true
		var lv: Node3D = main.level
		var p := grassy(lv)
		main.player.global_position = p
		main.player.velocity = Vector3.ZERO
		await create_timer(0.5).timeout
		var side := Vector3(2.4, 1.1, 1.6)
		await shot(b.to_lower() + "_1_standing_in_it", p + side, p + Vector3(0, 0.4, 0))
		await shot(b.to_lower() + "_2_eye_height", p + Vector3(-1.5, 1.7, -1.5), p + Vector3(20, 0.0, 20))
		main.player.global_position = p + Vector3(0, 40, 0)   # (gone: the grass stands back up)
		await create_timer(0.6).timeout
		await shot(b.to_lower() + "_3_nobody_there", p + side, p + Vector3(0, 0.4, 0))
		cam.current = false
		main.player.cam.current = true
		pg.fly = false
	quit()
