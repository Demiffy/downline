# The things on the facility's walls you have to use or read: the twin-key levers (up, pulled), the
# main breaker (on, tripped) and the code chalked on a wall, each from in front, through the
# playground's own buttons. Needs a window.
# Run: tests/run.sh 300 --path . -s tests/wall_shots.gd -- <dir> playground [THEME]
extends SceneTree

var out := ""
var main
var pg
var cam: Camera3D


func _initialize() -> void:
	_run()


func shot(name: String, target: Node3D, out_dist: float, up: float, local_out := Vector3(0, 0, 1), aim_y := 0.0) -> void:
	var n: Vector3 = (target.global_transform.basis * local_out).normalized()
	var at: Vector3 = target.global_position + Vector3(0, aim_y, 0)
	cam.global_position = at + n * out_dist + Vector3(0, up, 0) + target.global_transform.basis.x.normalized() * out_dist * 0.35
	cam.look_at(at)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func press(page: String, label: String) -> void:
	for c in pg._pages[page].find_children("*", "Button", true, false):
		if (c as Button).text == label:
			c.pressed.emit()
	for i in 6:
		await process_frame
	while not pg._ready_done or main.busy:
		await process_frame


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
	main.hud.visible = false
	cam = Camera3D.new()
	main.add_child(cam)
	cam.fov = 60
	var lamp := OmniLight3D.new()   # (a flashlight's worth of light)
	lamp.omni_range = 9.0
	lamp.light_energy = 2.5
	cam.add_child(lamp)
	lamp.position = Vector3(0.4, 0.3, 0)
	for i in 6:   # (not every site has a twin-key room: build another till one does)
		if not main.level.facility.twin_levers.is_empty():
			break
		await press("WORLD", "FACTORY")
	var fac = main.level.facility
	pg.frozen = true
	for i in 30:
		await process_frame
	cam.current = true
	if not fac.twin_levers.is_empty():
		var lv: Node3D = fac.twin_levers[0]
		await shot("1_lever_up", lv, 1.5, 0.2)
		await shot("1b_lever_side", lv, 1.2, 0.1, Vector3(1, 0, 0.6))
		lv.pull()
		await create_timer(0.4).timeout
		await shot("2_lever_pulled", lv, 1.5, 0.2)
		await shot("2b_lever_pulled_side", lv, 1.2, 0.1, Vector3(1, 0, 0.6))
		await shot("2c_lever_room", lv, 4.5, 0.4)
		await shot("2d_other_lever_room", fac.twin_levers[1], 4.5, 0.4)
	var hz = main.level.hazards
	await shot("3_breaker_on", hz.breaker, 1.8, 1.5, Vector3(0, 0, -1), 1.4)
	await shot("3b_breaker_side", hz.breaker, 1.6, 1.5, Vector3(1, 0, -0.7), 1.4)
	hz.power_fail()
	await create_timer(1.5).timeout
	await shot("4_breaker_tripped", hz.breaker, 1.8, 1.5, Vector3(0, 0, -1), 1.4)
	if fac.clue_at != Vector3.INF:
		var t := Node3D.new()
		main.add_child(t)
		var best: Vector3 = fac.clue_n
		t.global_position = fac.clue_at
		t.look_at(fac.clue_at - best)
		await shot("5_code_on_wall", t, 3.0, 0.0)
		await shot("5b_code_room", t, 6.0, 0.3)
	quit()
