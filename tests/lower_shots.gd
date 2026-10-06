# Screenshots of the lower floor: a stairwell from above, its stairs from below, basement rooms. Needs a window.
# Run: godot --path . -s tests/lower_shots.gd -- <out_dir> [THEME]
extends SceneTree

var main
var out := "user://shots"
var theme := "LAB"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		theme = args[1]
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/lo_%s_%s.png" % [out, theme.to_lower(), name])
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
	stop.theme = theme
	stop.rooms = 22
	main.player.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	var fac = main.level.facility
	Engine.remove_meta("fast_test")
	main.level.hazards.set_physics_process(false)
	for m in main.get_tree().get_nodes_in_group("monsters"):
		m.queue_free()
	var p = main.player
	p.hp = 1e9
	p.slots[0] = {"id": "FLASHLIGHT", "charge": 99999.0}
	p.light_on = true
	var k := 0
	for c in fac.stairs:
		var s: Dictionary = fac.stairs[c]
		if not s.vertical or k >= 2:
			continue
		k += 1
		var hi: Vector3 = fac.to_global(s.high)
		var lo: Vector3 = fac.to_global(s.low)
		var axis: Vector3 = lo - hi
		axis.y = 0
		axis = axis.normalized()
		var o: Vector3 = fac.to_global(Vector3(c.x * 12.0, 0, c.y * 12.0))
		var away: Vector3 = (Vector3(o.x, 0, o.z) - Vector3(hi.x, 0, hi.z))
		away.y = 0
		look(hi - axis * 2.0 + away.normalized() * 2.5 + Vector3(0, -0.5, 0), (hi + lo) / 2.0)
		await shot("%s_%d_%d_above" % [fac.kinds[c], c.x, c.y])
		look(lo + axis * 2.0 + away.normalized() * 1.5 + Vector3(0, -0.45, 0), hi)
		await shot("%s_%d_%d_below" % [fac.kinds[c], c.x, c.y])
	var j := 0
	for c in fac.lower:
		if fac.low_kinds[c] in ["pit", "stairwell"] or j >= 4:
			continue
		var lo: Vector3 = fac.to_global(Vector3(c.x * 12.0, -3.0 + 0.05, c.y * 12.0))
		look(lo + Vector3(-4.5, 0, -4.5), lo + Vector3(2, 1.0, 2))
		await shot("room_%s_%d" % [fac.low_kinds[c], j])
		j += 1
	quit()
