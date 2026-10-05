# Close-up screenshots of the elevator headframe. Needs a window.
# Run: godot --path . -s tests/headframe_shot.gd -- <out_dir>
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
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


## Puts the camera at `pos` looking at `at` (player gravity off so it can float).
func look(pos: Vector3, at: Vector3) -> void:
	var p = main.player
	p.global_position = pos - Vector3(0, 1.6, 0)
	var d := at - pos
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(30)
	main.term.run("LEAVE_CHECKPOINT")
	main.player.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	while main.busy:
		await process_frame
	await frames(20)
	main.player.set_physics_process(false)

	main.hud.visible = false
	var e: Vector3 = main.level.elevator_pos
	var top := e + Vector3(0, 15, 0)
	look(e + Vector3(-9, 18, -9), top)
	await shot("hf_top_diag")
	look(e + Vector3(0, 16.5, -7), top + Vector3(0, 1, 0))
	await shot("hf_top_front")
	look(e + Vector3(7, 16, 0.5), top + Vector3(0, 1, 0))
	await shot("hf_top_side")
	look(e + Vector3(-14, 8, -18), e + Vector3(0, 9, 0))
	await shot("hf_whole")
	look(e + Vector3(2.5, 13, -2.5), e + Vector3(0, 16, 0))
	await shot("hf_under_deck")
	quit()
