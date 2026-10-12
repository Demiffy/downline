# The facility's long corridors: looking down a few of them from one end, and the floor plan
# (plan.json: cells, kinds, corridors, links) to draw how far the wings sprawl.
# Run: tests/run.sh 400 --path . --resolution 1280x720 -s tests/corridor_shots.gd -- <out_dir> [THEME] [ROOMS]
extends SceneTree

var main
var out := "user://corridors"


func _initialize() -> void:
	_run()


func shot(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else out
	var theme: String = args[1] if args.size() > 1 else "FACTORY"
	DirAccess.make_dir_recursive_absolute(out)
	Engine.set_meta("fast_test", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = theme
	stop.rooms = int(args[2]) if args.size() > 2 else 30
	stop.weather = "CLEAR"
	main.player.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	Engine.remove_meta("fast_test")
	main.hud.visible = false
	main.player.frozen = true
	var fac = main.level.facility
	for n in main.level.get_children():
		if n.is_in_group("monsters"):
			n.queue_free()
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 70
	cam.far = 600.0
	main.player.visible = false
	var torch := SpotLight3D.new()   # (a flashlight on the camera: the player's is hidden with it)
	cam.add_child(torch)
	torch.spot_range = 40.0
	torch.spot_angle = 28.0
	torch.light_energy = 3.0
	torch.light_color = Color(1, 0.93, 0.8)
	var corr: Dictionary = fac.layout.corridor
	print("rooms ", fac.layout.cells.size(), " corridor cells ", corr.size())
	# A corridor's ends: walk each straight run of corridor cells and stand at one end looking down it.
	var seen := {}
	var k := 0
	for c in corr:
		if seen.has(c) or k >= 3:
			continue
		var l: Array = fac.layout.links[c]
		var d: Vector2i = l[0] - c
		var a: Vector2i = c
		while corr.has(a - d):
			a -= d
		var b: Vector2i = c
		while corr.has(b + d):
			b += d
		var n := 0
		var x := a
		while true:
			seen[x] = true
			n += 1
			if x == b:
				break
			x += d
		if n < 2:
			continue
		var from: Vector3 = fac.to_global(Vector3(a.x * 12.0, 0, a.y * 12.0) - Vector3(d.x, 0, d.y) * 5.0)
		var to: Vector3 = fac.to_global(Vector3(b.x * 12.0, 0, b.y * 12.0) + Vector3(d.x, 0, d.y) * 6.0)
		main.player.global_position = from + Vector3(0, 0.1, 0) - Vector3(d.x, 0, d.y) * 3.0
		cam.global_position = from + Vector3(0, 1.65, 0)
		cam.look_at(to + Vector3(0, 1.4, 0))
		await shot("corridor_%d_%dcells" % [k, n])
		k += 1
	# The plan, for drawing elsewhere: every cell with its kind, corridor or not, and its links.
	var plan := []
	for c in fac.layout.cells:
		var l := []
		for n in fac.layout.links[c]:
			l.append([n.x, n.y])
		plan.append({"x": c.x, "y": c.y, "kind": fac.kinds.get(c, ""), "corridor": corr.has(c), "links": l})
	var f := FileAccess.open(out + "/plan.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(plan))
	f.close()
	quit()
