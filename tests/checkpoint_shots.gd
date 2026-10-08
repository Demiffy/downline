# The checkpoint's machinery: the shredder from the hall door, into its hopper, the quota readout
# by the lever, and the delivery handcar rolling up behind the train. Needs a window.
# Run: tests/run.sh 200 --path . -s tests/checkpoint_shots.gd -- <out_dir>
extends SceneTree

var main
var out := "user://checkpoint"


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
	main.player.set_physics_process(false)
	main.player.frozen = true
	main.hud.visible = false
	main.assignment = 1
	main.quota = {"steel": 12, "copper": 8, "rubber": 10, "plastic": 8}
	main.submitted = {"steel": 5, "copper": 8, "rubber": 2, "plastic": 0}
	for id in ["WRENCH", "TOY_TRUCK", "GEAR", "CAR_BATTERY"]:
		main.spawn_item(id, Vector3(randf_range(-0.8, 0.8), 1.4, randf_range(12.4, 13.6)))
	await frames(60)
	look(Vector3(0.0, 1.7, 6.5), Vector3(0.0, 1.6, 13.0))
	await shot("shredder_front")
	look(Vector3(-3.4, 2.2, 9.4), Vector3(0.0, 1.2, 13.0))
	await shot("shredder_three_quarter")
	look(Vector3(0.0, 3.4, 10.2), Vector3(0.0, 0.5, 13.0))
	await shot("shredder_hopper")
	look(Vector3(3.45, 2.1, 9.6), Vector3(3.45, 2.3, 11.1))
	await shot("shredder_readout")
	look(Vector3(1.0, 2.0, 7.5), Vector3(0.0, 4.6, 11.1))
	await shot("shredder_sign")
	# The handcar: halfway in, then parked.
	main._orders = ["FLASHLIGHT", "CROWBAR"]
	main._dispatch_handcar()
	var rear: float = main.train.rear_x()
	await create_timer(9.0).timeout
	look(main.train.to_global(Vector3(rear - 4.0, 2.4, 4.5)), main.train.to_global(main.train.to_local(main._handcar.global_position) + Vector3(0, 1.0, 0)))
	await shot("handcar_rolling")
	while main._handcar_busy:
		await process_frame
	await frames(30)
	look(main.train.to_global(Vector3(rear - 0.5, 2.3, 3.4)), main.train.to_global(Vector3(rear - 2.0, 1.0, 0.0)))
	await shot("handcar_parked")
	quit(0)
