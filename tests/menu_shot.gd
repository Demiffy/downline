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
	quit()
