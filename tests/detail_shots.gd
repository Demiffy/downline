# Close-ups for visual checks: lift landing (facility + surface), a pendant lamp, a stairwell edge,
# a basement doorway, a fume hood. Needs a window. Run: godot --path . -s tests/detail_shots.gd -- <out_dir> [THEME]
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
	root.get_texture().get_image().save_png("%s/d_%s_%s.png" % [out, theme.to_lower(), name])
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
	Engine.remove_meta("fast_test")
	var lvl = main.level
	var fac = lvl.facility
	lvl.hazards.set_physics_process(false)
	for m in main.get_tree().get_nodes_in_group("monsters"):
		m.queue_free()
	var p = main.player
	p.hp = 1e9
	p.slots[0] = {"id": "FLASHLIGHT", "charge": 99999.0}
	p.light_on = true
	var el = lvl.elevator
	if el.at_top:
		el.cab.position.y = el.bottom
		el.at_top = false
	var fo: Vector3 = fac.global_position
	look(fo + Vector3(0.6, 0.05, -5.6), fo + Vector3(0, 1.6, -2.2))
	await shot("lift_bottom")
	look(fo + Vector3(-3.5, 0.05, -5.0), fo + Vector3(0, 1.5, -2.0))
	await shot("lift_bottom_side")
	look(lvl.elevator_pos + Vector3(0.4, 0.05, -5.8), lvl.elevator_pos + Vector3(0, 1.7, -2.2))
	await shot("lift_top")
	# A pendant lamp, from below (basement lamps hang low enough to see).
	for l in fac.low_root.find_children("*", "OmniLight3D", true, false):
		if l.get_parent() != fac.low_root:
			look(l.global_position + Vector3(1.3, -2.0, 1.0), l.global_position + Vector3(0, 0.15, 0))
			await shot("pendant")
			break
	# Stairwell edge and a basement doorway.
	for c in fac.stairs:
		var s: Dictionary = fac.stairs[c]
		if fac.kinds[c] == "stairwell":
			var hi: Vector3 = fac.to_global(s.high)
			var lo: Vector3 = fac.to_global(s.low)
			var ax: Vector3 = (lo - hi) * Vector3(1, 0, 1)
			var o: Vector3 = fac.to_global(Vector3(c.x * 12.0, 0, c.y * 12.0))
			var mid: Vector3 = (hi + lo) / 2.0
			var away: Vector3 = (o - mid) * Vector3(1, 0, 1)
			look(Vector3(mid.x, o.y, mid.z) + away.normalized() * 3.2, mid + Vector3(0, 0.2, 0))
			await shot("stairwell_edge")
			look(lo + ax.normalized() * 1.0 + Vector3(0, -0.45, 0), hi + Vector3(0, 0.5, 0))
			await shot("stairwell_up")
			break
	for c in fac.lower:
		if fac.low_kinds[c] in ["pit", "stairwell"]:
			continue
		for n in fac.lower[c]:
			var door: Vector3 = fac.to_global(Vector3((c.x + n.x) * 6.0, -3.0, (c.y + n.y) * 6.0))
			var into: Vector3 = fac.to_global(Vector3(c.x * 12.0, -3.0, c.y * 12.0)) - door
			look(door + into.normalized() * 3.0 + into.normalized().cross(Vector3.UP) * 0.8 + Vector3(0, 0.05, 0), door + Vector3(0, 1.4, 0))
			await shot("basement_door")
			break
		break
	quit()
