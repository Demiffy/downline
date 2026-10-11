# The settings screen, each tab, from the title screen (and once from the pause menu). Needs a window.
# Run: godot --path . -s tests/settings_shots.gd -- <out_dir>
extends SceneTree

var out := "user://shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func shot(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func _run() -> void:
	await process_frame
	change_scene_to_file("res://main.tscn")
	await process_frame
	await process_frame
	var main = current_scene
	var lobby
	for c in main.get_children():
		if c.get_script() == load("res://src/lobby.gd"):
			lobby = c
	await create_timer(2.5).timeout
	await shot("s0_title")
	var ui = lobby._settings
	ui.open()
	for t in ui.TABS:
		ui.show_tab(t)
		await shot("s1_" + t.to_lower())
	ui.show_tab("CONTROLS")
	ui.close()
	lobby._solo()
	await create_timer(2.5).timeout
	main.menu.open()
	main.menu._show_settings(true)
	main.menu._tab("VIDEO")
	await shot("s2_pause_video")
	quit()
