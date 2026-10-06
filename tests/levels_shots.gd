# Screenshots of two-level rooms (pit stairs, mezzanine), doors and floor papers. Needs a window.
# Run: godot --path . -s tests/levels_shots.gd -- <out_dir>
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
	await frames(5)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/lv_%s.png" % [out, name])
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
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = "FACTORY"
	stop.rooms = 26
	main.player.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	var fac = main.level.facility
	var tries := 0
	while tries < 12 and not (fac.kinds.values().has("pit") and fac.kinds.values().has("atrium") and fac.stairs.size() >= 2):
		tries += 1
		main.level.queue_free()
		main.level = null
		await process_frame
		main._load_level(stop)
		await frames(2)
		fac = main.level.facility
	Engine.remove_meta("fast_test")
	main.level.hazards.set_physics_process(false)
	for m in main.get_tree().get_nodes_in_group("monsters"):
		m.queue_free()
	var p = main.player
	p.hp = 1e9
	p.slots[0] = {"id": "FLASHLIGHT", "charge": 99999.0}
	p.light_on = true
	main.get_viewport().debug_draw = Viewport.DEBUG_DRAW_UNSHADED   # fullbright, to see the geometry
	for c in fac.stairs:
		var s: Dictionary = fac.stairs[c]
		var hi: Vector3 = fac.to_global(s.high)
		var lo: Vector3 = fac.to_global(s.low)
		var k: String = fac.kinds[c]
		var axis: Vector3 = (lo - hi)
		axis.y = 0
		axis = axis.normalized()
		var side := axis.cross(Vector3.UP)
		var o: Vector3 = fac.to_global(Vector3(c.x * 12.0, 0, c.y * 12.0))
		var floor_y: float = lo.y - 0.5
		var eye: Vector3 = Vector3(o.x, floor_y, o.z) + (Vector3(o.x, 0, o.z) - Vector3(hi.x, 0, hi.z)).normalized() * 3.5   # across the room, looking at the flight
		look(eye, (hi + lo) / 2.0)
		await shot("%s_%d_%d_from_below" % [k, c.x, c.y])
		look(hi - axis * 1.2 + Vector3(0, -0.5, 0), lo)
		await shot("%s_%d_%d_from_above" % [k, c.x, c.y])
	main.get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
	# A door, closed, straight on.
	for d in fac.get_children():
		if d.get_script() != null and d.get_script().resource_path.ends_with("door.gd"):
			d.set_open(false)
			await frames(40)
			var mid: Vector3 = d.global_position + d.global_transform.basis.x * 1.2
			look(mid + d.global_transform.basis.z * 2.5 + Vector3(0, 0.05 - 0.0, 0), mid + Vector3(0, 1.3, 0))
			await shot("door_closed")
			d.set_open(true)
			await frames(40)
			await shot("door_open")
			break
	quit()
