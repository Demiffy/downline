# Surface and train close-ups: houses, fence, pumpjack, horizon, loco front + side, control desk,
# lift car panel. Needs a window. Run: godot --path . -s tests/surface_shots.gd -- <out_dir>
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
	root.get_texture().get_image().save_png("%s/s_%s.png" % [out, name])
	print("saved ", name)


func look(pos: Vector3, at: Vector3) -> void:
	var p = main.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	var d := at - (pos + Vector3(0, 1.6, 0))
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _run() -> void:
	Engine.set_meta("fast_test", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	var p = main.player
	p.hp = 1e9
	# Control desk in the crew car.
	look(Vector3(6.6, 1.0, 0.6), Vector3(7.8, 2.25, 0.6))
	await shot("desk")
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = "FACTORY"
	stop.weather = "CLEAR"
	stop.biome = "DESERT"
	p.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	Engine.remove_meta("fast_test")
	main.hours = 11.0
	var lvl = main.level
	for m in main.get_tree().get_nodes_in_group("monsters"):
		m.queue_free()
	# Loco: front three-quarter and side.
	look(Vector3(20.5, lvl.ground_y(20.5, 4.0), 4.0), Vector3(17.2, 0.9, 0))
	await shot("loco_front")
	look(Vector3(14.5, lvl.ground_y(14.5, 5.0), 5.0), Vector3(14.0, 1.8, 1.3))
	await shot("loco_side")
	# Houses (the station house and the others).
	var k := 0
	for h in lvl._houses:
		if k >= 3:
			break
		var at: Vector3 = h
		var from := at + Vector3(9, 0, -11)
		from.y = lvl.ground_y(from.x, from.z)
		look(from, at + Vector3(0, 3.5, 0))
		await shot("house_%d" % k)
		k += 1
	# Whatever pumpjack / fence there is.
	for n in lvl.get_children():
		if n is StaticBody3D and n.get_child_count() > 40 and n.get_child(0) is CollisionShape3D and (n.get_child(0).shape as BoxShape3D) and is_equal_approx((n.get_child(0).shape as BoxShape3D).size.x, 8.5):
			var at: Vector3 = n.global_position
			var from: Vector3 = at + n.global_transform.basis.z * 9.0 + n.global_transform.basis.x * 3.0
			from.y = lvl.ground_y(from.x, from.z)
			look(from, at + Vector3(0, 2.5, 0))
			await shot("pumpjack")
			break
	var pj := Node3D.new()
	lvl.add_child(pj)
	var pjp := Vector3(30, lvl.ground_y(30, 30), 30)
	load("res://src/props.gd").pumpjack(pj, pjp, 0.4)
	await frames(30)
	look(pjp + Vector3(4, 0, 9), pjp + Vector3(0, 2.5, 0))
	await shot("pumpjack_new")
	# Horizon.
	look(Vector3(0, lvl.ground_y(0, 25), 25), Vector3(0, 15, 200))
	await shot("horizon")
	look(Vector3(0, lvl.ground_y(0, -25), -25), Vector3(60, 10, -200))
	await shot("horizon2")
	# Lift car panel.
	var el = lvl.elevator
	look(el.cab.global_position + Vector3(0.2, 0.05, -0.6), el.cab.global_position + Vector3(1.8, 1.4, -1.2))
	await shot("lift_panel")
	look(el.cab.global_position + Vector3(0, 0.05, 0.6), el.cab.global_position + Vector3(0, 3.0, 0))
	await shot("lift_lamp")
	quit()
