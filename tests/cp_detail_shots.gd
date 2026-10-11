# Close looks round the checkpoint (needs a window): the shop clerk, the gatehouse and its guard,
# a floodlight tower's head, the reclamation hall in and out, the yard shunter, a freight engine on
# the far line, the view across the basin.
# Run: godot --path . -s tests/cp_detail_shots.gd -- <out_dir>
extends SceneTree


func shot(out: String, name: String, frames := 20) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func _initialize() -> void:
	_run()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 40:
		await process_frame
	main.hud.visible = false
	main.player.frozen = true
	var lv: Node3D = main.level
	var cam := Camera3D.new()
	cam.far = 2000.0
	main.add_child(cam)
	cam.current = true
	var life: Node = lv.find_children("*", "", false, false).filter(func(n): return n.get_script() != null and n.get_script().resource_path.ends_with("yard_life.gd"))[0]
	life.set_meta("shots", true)
	var views := [
		["clerk_front", Vector3(-14.0, 1.7, 10.6), Vector3(-14.0, 1.4, 13.0)],
		["clerk_side", Vector3(-12.2, 1.6, 12.4), Vector3(-14.0, 1.2, 13.1)],
		["gate_front", Vector3(23.0, 1.7, 5.3), Vector3(20.0, 1.0, 5.3)],
		["gate_side", Vector3(19.0, 1.8, 8.5), Vector3(20.2, 1.0, 5.3)],
		["flood_top", Vector3(-62.0, 17.0, 26.0), Vector3(-70.0, 16.5, 30.0)],
		["flood_low", Vector3(-62.0, 1.7, 22.0), Vector3(-70.0, 12.0, 30.0)],
		["hall_front", Vector3(0.0, 3.0, -6.0), Vector3(0.0, 6.0, 14.0)],
		["hall_corner", Vector3(18.0, 4.0, 2.0), Vector3(0.0, 6.0, 14.0)],
		["hall_back", Vector3(-14.0, 6.0, 32.0), Vector3(0.0, 6.0, 14.0)],
		["hall_inside", Vector3(-6.0, 1.7, 9.0), Vector3(3.0, 5.0, 18.0)],
		["hall_roof", Vector3(4.0, 1.7, 10.0), Vector3(0.0, 8.5, 15.0)],
		["far_east", Vector3(-60.0, 1.7, 20.0), Vector3(160.0, 4.0, -10.0)],
		["far_west", Vector3(60.0, 1.7, -5.0), Vector3(-160.0, 4.0, -40.0)],
	]
	for v in views:
		cam.global_position = lv.to_global(v[1])
		cam.look_at(lv.to_global(v[2]))
		await shot(out, "d_" + v[0], 30)
	# The shunter, wherever it's got to, and a freight engine brought out of the tunnel.
	var sh: Node3D = life._shunt
	cam.global_position = sh.global_position + Vector3(7.0, 2.2, 6.0)
	cam.look_at(sh.global_position + Vector3(0, 1.8, 0))
	await shot(out, "d_shunter", 20)
	cam.global_position = sh.global_position + Vector3(-1.0, 2.0, -7.5)
	cam.look_at(sh.global_position + Vector3(1.0, 1.8, 0))
	await shot(out, "d_shunter_side", 20)
	if life._train == null:
		life._send_train()
	life._train_x = 0.0
	life._train.position.x = 0.0
	life.set_process(false)
	var tp: Vector3 = life._train.global_position
	var d: float = life._train_dir
	cam.global_position = tp + Vector3(d * 14.0, 2.5, 8.0)
	cam.look_at(tp + Vector3(d * 2.0, 2.0, 0))
	await shot(out, "d_freight", 20)
	cam.global_position = tp + Vector3(d * 2.0, 2.0, 9.0)
	cam.look_at(tp + Vector3(0, 2.2, 0))
	await shot(out, "d_freight_side", 20)
	quit()
