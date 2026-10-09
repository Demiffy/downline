# Screenshots of the pause menu and settings pages. Needs a window.
# Run: godot --path . -s tests/menu_shot.gd -- <out_dir>
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


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(40)
	main.menu.open()
	await shot("m1_pause")
	main.menu._show_settings(true)
	await shot("m2_controls")
	main.menu._tab("VIDEO")
	await shot("m3_video")
	main.menu._tab("AUDIO")
	await shot("m4_audio")
	main.menu._on_action("restart")
	main.menu._show_settings(false)
	await shot("m5_confirm")
	main.menu._confirm = ""
	main.menu.close()
	# The run's photographs in the pause menu (some made-up prints).
	for i in 7:
		var img := Image.create(320, 270, false, Image.FORMAT_RGB8)
		var c := Color.from_hsv(0.07 + i * 0.02, 0.5, 0.25 + 0.06 * i)
		img.fill(c)
		for k in 400:
			img.set_pixel(randi() % 320, randi() % 270, c.lightened(0.4))
		img.fill_rect(Rect2i(120, 60 + i * 5, 80, 160), c.darkened(0.6))   # (a figure)
		main.photo_log.append({"tex": ImageTexture.create_from_image(img), "stamp": "STN %s   %02d:%02d" % [char(65 + i), 10 + i, i * 7]})
	main.photo_log.append({"stamp": "STN H   21:40"})   # (one that didn't come out)
	main.menu.open()
	await shot("m6_album")
	var holder = main.menu._album_grid.get_child(2)
	main.menu._hold_up(main.photo_log[2], 2)
	await shot("m7_held_up")
	main.menu.close()
	# The title screen with a saved run to continue.
	main.save_path = "user://shot_run.save"
	main.autosaves = true
	main.term.run("LEAVE_CHECKPOINT")
	main.Save.write(main, main.save_path)
	var lobby = load("res://src/lobby.gd").new()
	lobby.main = main
	main.add_child(lobby)
	await frames(10)
	await shot("m8_title_continue")
	main.Save.delete(main.save_path)
	quit()
