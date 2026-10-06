# Close looks at walls, doorways and props in a facility, to catch flickering (coplanar) faces.
# Run: godot --path . -s tests/zfight_shots.gd -- <out_dir> [THEME]
extends SceneTree

var main
var out := "user://shots"
var theme := "BACKROOMS"


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
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/z_%s_%s.png" % [out, theme.to_lower(), name])


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
	stop.rooms = 14
	main.player.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	var p = main.player
	p.hp = 1e9
	p.slots[0] = {"id": "FLASHLIGHT", "charge": 99999.0}
	p.light_on = true
	var fac = main.level.facility
	var n := 0
	for c in fac.layout.cells:
		if fac.kinds[c] in ["pit", "tunnel"] or n >= 8:
			continue
		var o: Vector3 = fac.to_global(Vector3(c.x * 12.0, 0.05, c.y * 12.0))
		for d in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
			look(o - d * 2.5 + Vector3(d.z, 0, d.x) * 1.5, o + d * 6.0 + Vector3(0, 1.2, 0))
			await shot("%d" % n)
			n += 1
	# Open swing doors, seen along the wall from close by.
	var k := 0
	for d in fac.get_children():
		if d.get_script() != null and d.get_script().resource_path.ends_with("door.gd") and k < 3:
			if not d.open:
				d.set_open(true)
			await frames(40)
			var hinge: Vector3 = d.global_position
			var across: Vector3 = d.global_transform.basis.x
			var out: Vector3 = d.global_transform.basis.z
			look(hinge + out * 2.2 - across * 0.6 + Vector3(0, 0.05, 0), hinge + across * 0.3 + Vector3(0, 1.2, 0))
			await shot("door%d" % k)
			k += 1
	quit()
