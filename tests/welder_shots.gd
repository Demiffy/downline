# The checkpoint's welder (yard_life._weld_pose) from four sides and above, his beam and torch.
# Needs a window. Run: tests/run.sh 120 --path . -s tests/welder_shots.gd -- <dir>
extends SceneTree

var main


func _initialize() -> void:
	_run()


func wait(secs: float) -> void:
	var a := Time.get_ticks_msec()
	while Time.get_ticks_msec() - a < secs * 1000.0:
		await process_frame


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await wait(12.0)
	main.hud.visible = false
	main.player.global_position = Vector3(0, 0.1, 96)
	var yl: Node = main.level.find_child("YardLife", true, false)
	var m: Node3D = yl._people[yl.WELDER].node
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 50.0
	var lamp := OmniLight3D.new()   # (a work lamp: the shed is dim)
	lamp.omni_range = 8.0
	lamp.light_energy = 1.2
	main.add_child(lamp)
	lamp.global_position = m.global_position + Vector3(0, 2.6, 1.0)
	var at: Vector3 = m.global_position + Vector3(0, 0.7, -0.25)
	for v in [["front", Vector3(0.3, 1.3, -2.4)], ["side_r", Vector3(2.4, 1.1, -0.3)], ["side_l", Vector3(-2.4, 1.1, -0.3)], ["back", Vector3(0.4, 1.5, 2.2)], ["above", Vector3(0.6, 3.2, 0.4)]]:
		cam.look_at_from_position(m.global_position + m.global_basis * v[1], at)
		await wait(0.5)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "/welder_" + v[0] + ".png")
	quit()
