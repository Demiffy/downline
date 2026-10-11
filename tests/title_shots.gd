# Frames of the title screen: the menu coming in over the cinematic camera, a change of shot, and
# the fly into the player's eyes when a solo shift starts. Needs a window.
# Run: godot --path . -s tests/title_shots.gd -- <out_dir>
extends SceneTree

var out := "user://shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func wait(secs: float) -> void:
	await create_timer(secs).timeout


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
	if lobby == null:
		print("FAIL no title screen")
		quit(1)
		return
	await wait(0.4)
	await shot("t0_enter")
	await wait(0.8)
	await shot("t1_enter")
	await wait(1.6)
	await shot("t2_menu")
	await wait(9.5)
	await shot("t3_next_shot")
	lobby._solo()
	await wait(0.35)
	await shot("t4_fly")
	await wait(0.6)
	await shot("t5_fly")
	await wait(1.0)
	await shot("t6_in_game")
	print("player cam current: ", main.player.cam.current, "  lobby gone: ", not is_instance_valid(lobby), "  hud: ", main.hud.visible)
	quit()
