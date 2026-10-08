# Every big room (halls.gd) on a few sites per theme: a wide shot from a high corner in game light
# (with a soft fill so the set piece reads), and a top-down plan. Needs a window.
# Run: tests/run.sh 600 --path . -s tests/halls_shots.gd -- <out_dir> [THEME ...]
extends SceneTree

const Halls = preload("res://src/halls.gd")

var main
var out := "user://halls"
var themes := ["LAB", "FACTORY", "FLESH", "BACKROOMS"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		themes = Array(args.slice(1))
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


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.weather = "CLEAR"
	main.player.global_position = Vector3(0, 1.3, 0)
	Engine.set_meta("fast_test", true)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	main.hud.visible = false
	main.player.set_physics_process(false)
	var seen := {}
	for theme in themes:
		for site in 3:
			stop.theme = theme
			stop.rooms = 26
			main.level.queue_free()
			main.level = null
			await process_frame
			main._load_level(stop)
			await frames(4)
			main.level.hazards.events.clear()
			for m in main.get_tree().get_nodes_in_group("monsters"):
				m.queue_free()
			var fac = main.level.facility
			main.player.global_position = main.level.elevator_pos + Vector3(0, 0.5, -8)
			for g in fac.groups:
				var key := "%s_%s" % [g.kind, g.shape]
				if seen.get(key, 0) >= 1:
					continue
				seen[key] = seen.get(key, 0) + 1
				await _show(fac, g, key)
	quit()


func _show(fac, g: Dictionary, key: String) -> void:
	var f := Halls.frame(g)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in g.cells:
		lo = Vector2(minf(lo.x, c.x * 12.0 - 6.0), minf(lo.y, c.y * 12.0 - 6.0))
		hi = Vector2(maxf(hi.x, c.x * 12.0 + 6.0), maxf(hi.y, c.y * 12.0 + 6.0))
	var mid := (lo + hi) / 2.0
	var fill := OmniLight3D.new()
	fill.omni_range = 26.0
	fill.light_energy = 0.7
	fill.light_color = Color(1, 0.92, 0.82)
	fill.shadow_enabled = false
	fac.add_child(fill)
	fill.position = Vector3(mid.x, 3.2, mid.y)
	var cam := Camera3D.new()
	cam.fov = 82.0
	fac.add_child(cam)
	# From just inside the corner farthest from the room's middle-ish, looking across it.
	var corner := Vector3(lo.x + 1.6, 2.6, lo.y + 1.6)
	var best := -1.0
	for cx in [lo.x + 1.6, hi.x - 1.6]:
		for cz in [lo.y + 1.6, hi.y - 1.6]:
			var cc: Vector2i = Halls.cell_of(Vector3(cx, 0, cz))
			if not cc in g.cells:
				continue   # (the empty corner of an L)
			var d := Vector2(cx, cz).distance_to(mid)
			if d > best:
				best = d
				corner = Vector3(cx, 2.6, cz)
	cam.look_at_from_position(fac.to_global(corner), fac.to_global(Vector3(mid.x, 0.6, mid.y)))
	cam.make_current()
	await shot(key + "_wide")
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = maxf(hi.x - lo.x, hi.y - lo.y) + 1.0
	top.near = 0.05
	top.far = 10.0
	fac.add_child(top)
	top.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(mid.x, 3.55, mid.y))
	top.make_current()
	root.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	await shot(key + "_plan")
	root.debug_draw = Viewport.DEBUG_DRAW_DISABLED
	top.queue_free()
	cam.queue_free()
	fill.queue_free()
