# Every upgrade you can see: storage car, digital clock, infirmary, weathervane, armoured suits,
# headlamp and night vision. Needs a window.
# Run: tests/run.sh 200 --path . -s tests/upgrade_shots.gd -- <out_dir>
extends SceneTree

const Puppet = preload("res://src/puppet.gd")
var main
var out := "user://upgrades"


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
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func look(pos: Vector3, at: Vector3) -> void:
	var p = main.player
	p.global_position = pos - Vector3(0, 1.6, 0)
	p.velocity = Vector3.ZERO
	var d := at - pos
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(30)
	for n in main.get_children():
		if n.has_method("_show_title"):
			n.queue_free()
	main.hud.visible = false
	main.player.set_physics_process(false)
	main.player.frozen = true
	main.credits = 99999
	for u in main.Data.UPGRADES:
		main.term.run("BUY_UPGRADE " + u)
	main.term.close()
	await frames(20)
	var t = main.train
	var shots := [
		["u_infirmary", Vector3(3.0, 2.3, 0.2), Vector3(4.8, 1.4, 1.6)],
		["u_infirmary_close", Vector3(4.2, 2.0, 0.9), Vector3(5.6, 1.3, 1.7)],
		["u_digital_clock", Vector3(6.6, 2.8, 0.2), Vector3(8.06, 3.34, 0)],
		["u_weathervane", Vector3(-0.8, 4.6, 1.6), Vector3(0.6, 4.8, 0)],
		["u_storage_car_outside", Vector3(-12.0, 2.4, 6.0), Vector3(-14.0, 2.0, 0)],
		["u_storage_car_inside", Vector3(-9.5, 2.6, 0.0), Vector3(-17.0, 1.5, 0)],
		["u_charger_close", Vector3(1.6, 2.4, 0.1), Vector3(1.6, 2.0, -1.9)],
		["u_charger_wide", Vector3(-0.2, 2.4, 1.2), Vector3(1.9, 1.6, -1.9)],
		["u_clock", Vector3(6.6, 2.7, 0.4), Vector3(7.3, 2.6, -1.96)],
		["u_car_front", Vector3(-3.0, 2.5, 0.6), Vector3(7.5, 2.3, -0.4)],
		["u_car_back", Vector3(5.0, 2.5, 0.6), Vector3(-7.5, 2.0, 0.0)],
		["u_car_wall_n", Vector3(1.5, 2.4, 1.6), Vector3(4.0, 2.4, -2.0)],
		["u_car_wall_s", Vector3(1.5, 2.4, -1.4), Vector3(4.0, 2.2, 2.0)],
		["u_roof", Vector3(-6.0, 6.5, 6.0), Vector3(2.0, 4.0, 0.0)],
	]
	for sh in shots:
		look(t.to_global(sh[1]), t.to_global(sh[2]))
		await shot(sh[0])
	look(t.to_global(Vector3(2.6, 2.2, 5.2)), t.to_global(Vector3(3.2, 1.9, 2.2)))
	await shot("u_door_open")
	t.set_doors(false)
	await frames(90)
	await shot("u_door_shut")
	look(t.to_global(Vector3(2.9, 2.0, 2.9)), t.to_global(Vector3(2.6, 2.2, 2.3)))
	await shot("u_door_close")
	t.set_doors(true)
	await frames(90)
	var pup := Puppet.new()
	pup.main = main
	pup.net = main.net
	pup.peer = 90
	pup.display_name = "ARMOURED"
	main.add_child(pup)
	pup.set_pose(["W", Vector3(-6.0, 0.06, 9.0), 0.0, 0.0, 1.8, "", false, false, false, false, main.level_serial, true, true])
	await frames(30)
	look(Vector3(-6.0, 1.75, 7.6), Vector3(-6.0, 1.3, 9.0))
	await shot("u_armor_front_close")
	look(Vector3(-6.0, 1.9, 7.9), Vector3(-6.0, 1.75, 9.0))
	await shot("u_helmet_headlamp_close")
	look(Vector3(-4.7, 1.6, 9.8), Vector3(-6.0, 1.2, 9.0))
	await shot("u_armor_side_close")
	look(Vector3(-6.0, 1.7, 10.6), Vector3(-6.0, 1.2, 9.0))
	await shot("u_armor_back_close")
	# Through your own eyes: night vision on.
	main.player.nv_on = true
	look(Vector3(-6.0, 1.7, 6.0), Vector3(-6.0, 1.2, 9.0))
	main.hud.visible = true
	await shot("u_night_vision_view")
	main.player.nv_on = false
	main.player.headlamp_on = true
	await shot("u_headlamp_view")
	main.hud.visible = false
	# The winch truck at a station's lift.
	main.term.run("LEAVE_CHECKPOINT")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	main.term.close()
	while main.busy:
		await process_frame
	await frames(30)
	var ep: Vector3 = main.level.elevator_pos
	look(ep + Vector3(-14.0, 6.0, 14.0), ep + Vector3(4.0, 3.0, 0))
	await shot("u_winch_truck_wide")
	var truck: Node3D = main.level.get_node_or_null("WinchTruck")
	if truck != null:
		for v in [["front", Vector3(-6.0, 2.0, 4.5)], ["side", Vector3(0.5, 1.9, 6.5)], ["rear", Vector3(6.5, 2.6, 4.0)], ["deck", Vector3(1.0, 4.5, 3.0)]]:
			look(truck.global_position + truck.global_basis * v[1], truck.global_position + truck.global_basis * Vector3(0.3, 1.4, 0))
			await shot("u_winch_truck_" + v[0])
	quit(0)
