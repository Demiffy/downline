# Arctic station look: clear and in a blizzard. Needs a window.
# Run: godot --path . -s tests/arctic_shots.gd -- <out_dir>
extends SceneTree

var main
var out := "user://shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	_run()


func look(pos: Vector3, at: Vector3) -> void:
	var p = main.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	var d := at - (pos + Vector3(0, 1.6, 0))
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func shot(name: String) -> void:
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/arctic_%s.png" % [out, name])
	print("saved ", name)


func _run() -> void:
	Engine.set_meta("fast_test", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.biome = "ARCTIC"
	stop.weather = "CLEAR"
	main.player.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	Engine.remove_meta("fast_test")
	main.hours = 11.0
	main.player.hp = 1e9
	for m in main.get_tree().get_nodes_in_group("monsters"):
		m.queue_free()
	var lvl = main.level
	look(Vector3(0, lvl.ground_y(0, 22), 22), Vector3(0, 3, 60))
	await shot("clear_1")
	var h: Vector3 = lvl._houses[1] if lvl._houses.size() > 1 else lvl._houses[0]
	var from := h + Vector3(10, 0, -9)
	from.y = lvl.ground_y(from.x, from.z)
	look(from, h + Vector3(0, 3, 0))
	await shot("clear_house")
	look(Vector3(-20, lvl.ground_y(-20, -20), -20), Vector3(-80, 8, -120))
	await shot("clear_2")
	stop.weather = "BLIZZARD"
	look(Vector3(0, lvl.ground_y(0, 22), 22), Vector3(0, 3, 60))
	await shot("blizzard_1")
	look(from, h + Vector3(0, 3, 0))
	await shot("blizzard_house")
	quit()
