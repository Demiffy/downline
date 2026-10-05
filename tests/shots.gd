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
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func look(pos: Vector3, at: Vector3) -> void:
	var p = main.player
	p.global_position = pos
	var d := at - (pos + Vector3(0, 1.6, 0))
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(30)
	main.player.hp = 1e9
	look(Vector3(-4, 0.1, 0.8), Vector3(6.6, 1.3, -1.8))
	await frames(10)
	await shot("01_train")
	main.open_terminal()
	main.term.run("HELP")
	main.term.run("LEAVE_CHECKPOINT")
	await frames(120)
	await shot("02_terminal")
	main.term.close()
	look(Vector3(2, 0.1, 6), Vector3(0, 1.0, 13))
	await frames(10)
	await shot("03_checkpoint")
	main.player.global_position = Vector3(0, 0.3, 0)  # be on the train when it leaves
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	while main.busy:
		await process_frame
	await frames(30)
	var lvl = main.level
	look(Vector3(0, 0.1, 2.5), lvl.booths[0] + Vector3(0, 2, 0))
	await frames(10)
	await shot("04_surface_day")
	main.player.global_position = lvl.booths[1] + Vector3(0, 0.1, -3.5)
	main.player.slots[0] = {"id": "FLASHLIGHT", "charge": 200.0}
	main.player.sel = 0
	main.player.light_on = true
	main.player.equip = {"id": "SCANNER", "charge": -1.0}
	look(lvl.booths[1] + Vector3(0, 0.1, -3.5), lvl.booths[1] + Vector3(0, 1.2, -12))
	await frames(20)
	await shot("05_facility_flashlight")
	main.player._scan_cd = 0.0
	main.player._scan()
	await frames(20)
	await shot("06_scan")
	main.player.light_on = false
	await frames(5)
	await shot("07_facility_dark")
	main.hours = 21.5
	look(Vector3(-12, 0.1, 6), Vector3(0, 1.5, 0))
	await frames(20)
	await shot("08_surface_night_train")
	quit()
