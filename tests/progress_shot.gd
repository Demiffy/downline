# Screenshots of the progression/terminal features. Needs a window.
# Run: godot --path . -s tests/progress_shot.gd -- <out_dir>
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
	await frames(6)
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
	main.credits = 3000
	main.open_terminal()
	main.term.run("UPGRADES")
	main.term.run("BUY_UPGRADE STORAGE_CAR")
	main.term.run("BUY_UPGRADE MINIMAP")
	main.term.run("BUY_UPGRADE QUICK_DELIVERY")
	main.term.run("BUY_UPGRADE WEATHERVANE")
	main.term.run("BUY FLA 2")
	await frames(120)
	await shot("p1_upgrades")
	main.term.close()
	await main.get_tree().create_timer(7.0).timeout
	look(Vector3(-31, 0.1, 6), Vector3(-26, 1.0, 0))
	await shot("p2_handcar")
	look(Vector3(-9.5, 1.05, 1.2), Vector3(-19, 1.6, -1.5))
	await shot("p3_storage_car")
	main.player.global_position = Vector3(0, 1.3, 0)
	main.open_terminal()
	main.term.run("LEAVE_CHECKPOINT")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	while main.busy:
		await process_frame
	await frames(30)
	main.open_terminal()
	main.term.run("LIST_CAMS")
	main.term.run("VIEW_CAM 1")
	main.term.run("TOGGLE_LIGHT")
	await frames(90)
	await shot("p4_camera_feed")
	main.term.run("MINIMAP")
	await frames(60)
	await shot("p5_site_map")
	main.term.close()
	var el = main.level.elevator
	main.player.global_position = el.cab.global_position + Vector3(0, 0.3, 0)
	el.ride()
	while el.moving:
		await process_frame
	await frames(20)
	look(el.cab.global_position + Vector3(0, 0.2, -4.5), el.cab.global_position + Vector3(0, 1.2, -14))
	await shot("p6_hud_minimap")
	quit()
