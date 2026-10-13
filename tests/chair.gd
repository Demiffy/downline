# The office chair (office_chair.gd) on the train: sit in it, roll forward with W (the chair comes
# along under you), turn (its seat turns with you), get up with space; then walk into it empty and it
# rolls off. With a dir: a picture of you sat in it, from the side. Needs a window for the picture.
# Run: tests/run.sh 120 --headless --path . -s tests/chair.gd   (or without --headless: -- <dir>)
extends SceneTree

var main
var fails := 0


func _initialize() -> void:
	_run()


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func wait(secs: float) -> void:
	var a := Time.get_ticks_msec()
	while Time.get_ticks_msec() - a < secs * 1000.0:
		await physics_frame


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	var t0 := Time.get_ticks_msec()
	while (main.train == null or get_nodes_in_group("office_chairs").is_empty() or not main.player.is_on_floor()) and Time.get_ticks_msec() - t0 < 15000:
		await physics_frame
	await wait(0.3)
	var chairs: Array = get_nodes_in_group("office_chairs")
	check(chairs.size() >= 1, "an office chair on the train (%d)" % chairs.size())
	var c = chairs[0]
	var p = main.player
	p.global_position = c.global_position + Vector3(0.0, 0.1, 0.0) + c.top.global_basis.z * -0.8
	await wait(0.5)
	p.sit(c)
	await wait(0.6)
	check(p.seat == c and c.taken, "sat in it")
	check(p.anim.emote == "CHAIR", "sat down (the pose)")
	var from: Vector3 = c.global_position
	p.rotation.y = main.train.global_rotation.y + PI / 2.0   # (facing down the aisle: room to roll)
	Input.action_press("move_forward")
	await wait(1.2)
	Input.action_release("move_forward")
	await wait(0.4)
	var moved: float = Vector2(c.global_position.x - from.x, c.global_position.z - from.z).length()
	check(moved > 0.6, "W rolls it along (%.2f m)" % moved)
	check(Vector2(c.global_position.x - p.global_position.x, c.global_position.z - p.global_position.z).length() < 0.05, "it stays under you")
	p.rotation.y += 1.2
	await wait(0.3)
	check(absf(angle_difference(c.top.global_rotation.y, p.global_rotation.y)) < 0.05, "its seat turns with you (its back behind you)")
	var shots := ""
	for a in OS.get_cmdline_user_args():
		shots = a
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
		main.hud.visible = false
		var cam := Camera3D.new()
		main.add_child(cam)
		var lp: Vector3 = main.train.to_local(p.global_position)   # (from along the car's aisle, inside it)
		var cl := Vector3(lp.x - 2.2, 2.3, clampf(lp.z + 1.3, -1.6, 1.6))
		cam.look_at_from_position(main.train.to_global(cl), p.global_position + Vector3(0, 0.7, 0))
		cam.make_current()
		await wait(0.5)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shots + "/chair_sat.png")
		p.rotation.y = main.train.global_rotation.y - PI / 2.0   # (back down the aisle: a shove off)
		await wait(0.4)
		Input.action_press("move_forward")
		await wait(0.12)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shots + "/chair_jolt.png")
		await wait(0.5)
		Input.action_release("move_forward")
		await wait(0.18)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shots + "/chair_stop.png")
		cam.queue_free()
		main.hud.visible = true
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	await wait(0.4)
	check(p.seat == null and not c.taken, "space gets you up")
	check(p.anim.emote == "", "...standing")
	# Empty: walk into it and it rolls off.
	c.global_position = main.train.to_global(Vector3(1.0, 1.0, 0.15))   # (out in the aisle, room to roll)
	var at: Vector3 = c.global_position
	p.global_position = main.train.to_global(Vector3(2.4, 1.1, 0.15))
	p.look_at(Vector3(at.x, p.global_position.y, at.z), Vector3.UP)
	await wait(0.3)
	Input.action_press("move_forward")
	await wait(1.4)
	Input.action_release("move_forward")
	await wait(0.8)
	var rolled: float = Vector2(c.global_position.x - at.x, c.global_position.z - at.z).length()
	check(rolled > 0.3, "walked into, it rolls off (%.2f m)" % rolled)
	print("chair.gd: " + ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit()
