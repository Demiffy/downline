# The shredder and its control desk from all round, and the readout. Needs a window.
# (A cycle, the skip and the handcar: checkpoint_shots.gd.)
# Run: tests/run.sh 400 --path . -s tests/shredder_shots.gd -- <out_dir>
extends SceneTree

var main
var out := "user://shredder"


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
		main.spawn_item(id, Vector3(randf_range(-0.8, 0.8), 1.6, randf_range(12.4, 13.6)))
	await frames(40)
	var only: Array = Array(OS.get_cmdline_user_args()).slice(1)
	var views := {
		"front": [Vector3(0.0, 1.7, 6.5), Vector3(0.0, 1.6, 13.0)],
		"three_quarter": [Vector3(-3.4, 2.2, 9.4), Vector3(0.0, 1.2, 13.0)],
		"hopper": [Vector3(0.0, 3.4, 10.2), Vector3(0.0, 0.5, 13.0)],
		"controls": [Vector3(3.25, 1.7, 10.15), Vector3(3.25, 1.0, 11.0)],
		"readout": [Vector3(3.25, 1.75, 10.0), Vector3(3.25, 1.84, 11.3)],
		"desk_side": [Vector3(4.8, 1.6, 9.8), Vector3(3.0, 1.2, 11.1)],
		"side": [Vector3(-5.5, 1.9, 11.0), Vector3(0.0, 1.5, 13.6)],
		"drive": [Vector3(-4.2, 2.2, 14.0), Vector3(-1.2, 1.5, 15.3)],
		"back": [Vector3(3.0, 3.0, 19.3), Vector3(0.0, 1.8, 14.5)],
		"conveyor": [Vector3(6.6, 2.4, 11.6), Vector3(3.6, 1.0, 14.8)],
	}
	for k in views:
		if only.is_empty() or k in only:
			look(views[k][0], views[k][1])
			await shot(k)
	quit()
