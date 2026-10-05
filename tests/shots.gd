# Visual check: poses the player around the world and saves screenshots. Needs a window (not headless).
# Run: godot --path . -s tests/shots.gd -- <out_dir>
extends SceneTree

var main
var out := "user://shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func look(pos: Vector3, at: Vector3) -> void:
	var p = main.player
	p.global_position = pos
	var d := at - (pos + Vector3(0, 1.6, 0))
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func wait_idle() -> void:
	while main.busy:
		await process_frame


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(40)
	main.player.hp = 1e9
	main.player.slots[0] = {"id": "FLASHLIGHT", "charge": 200.0}
	look(Vector3(-5, 1.05, 1.2), Vector3(6.6, 1.6, -1.8))
	await shot("01_train_interior_front")
	look(Vector3(5, 1.05, 1.0), Vector3(-6, 1.5, -1.5))
	await shot("02_train_interior_cargo")
	main.open_terminal()
	main.term.run("HELP")
	main.term.run("LEAVE_CHECKPOINT")
	await frames(150)
	await shot("03_terminal")
	main.term.close()
	look(Vector3(-3, 1.05, 4.5), Vector3(0, 1.0, 13))
	await shot("04_checkpoint_shredder")
	look(Vector3(-22, 0.1, 9), Vector3(4, 2.5, 0))
	await shot("05_train_exterior")
	main.player.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	await main.get_tree().create_timer(3.4).timeout
	look(Vector3(1.0, 1.05, 1.6), Vector3(4, 1.6, 6))
	await shot("06_departing")
	await wait_idle()
	await frames(30)
	var lvl = main.level
	var el = lvl.elevator
	look(Vector3(-2, 1.05, 4.0), lvl.elevator_pos + Vector3(0, 3, 0))
	await shot("07_station_platform")
	look(lvl.elevator_pos + Vector3(-4, 0.1, -16), lvl.elevator_pos + Vector3(0, 3, 0))
	await shot("08_elevator_building")
	look(el.global_position + Vector3(0.5, 0.2, 0.8), el.global_position + Vector3(0, 1.4, -4))
	el.ride()
	await main.get_tree().create_timer(5.0).timeout
	await shot("09_elevator_riding")
	while el.moving:
		await process_frame
	await frames(20)
	main.player.light_on = true
	look(el.cab.global_position + Vector3(0, 0.2, -4.5), el.cab.global_position + Vector3(0, 1.2, -14))
	await shot("10_facility_flashlight")
	var fac = lvl.facility
	var cells: Array = fac.layout.cells
	var c: Vector2i = cells[mini(3, cells.size() - 1)]
	var o: Vector3 = fac.to_global(Vector3(c.x * 12.0, 0, c.y * 12.0))
	look(o + Vector3(4.5, 0.2, 4.5), o + Vector3(-3, 1.0, -3))
	await shot("11_facility_room")
	main.player.light_on = false
	await shot("12_facility_room_dark")
	main.hours = 20.5
	look(Vector3(-18, 0.1, 10), Vector3(0, 2, 0))
	await frames(10)
	await shot("13_night_train")
	quit()
