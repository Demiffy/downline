# Path probe: a dozen walkers (probe_walker.gd, the monsters' own pathing) roam each facility theme
# for a long while, across both floors, with the bulkheads as the game leaves them. Every stuck
# event is logged; then the worst spots are photographed up close in fullbright with the path
# gizmos on (pathdebug.gd), plus a top-down overview of each site. Needs a window.
# Run: tests/run.sh 900 --path . -s tests/path_probe.gd -- <out_dir> [secs per theme] [THEME ...]
extends SceneTree

const Walker = preload("res://tests/probe_walker.gd")
const Monster = preload("res://src/monster.gd")

var main
var out := "user://probe"
var secs := 45.0
var themes := ["FACTORY", "LAB", "FLESH", "BACKROOMS"]
var report := PackedStringArray()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		secs = float(args[1])
	if args.size() > 2:
		themes = Array(args.slice(2))
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func say(s: String) -> void:
	print(s)
	report.append(s)


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.weather = "CLEAR"
	stop.rooms = 24
	main.player.global_position = Vector3(0, 1.3, 0)
	Engine.set_meta("fast_test", true)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	main.player.hp = 1e9
	main.hud.visible = false
	for theme in themes:
		stop.theme = theme
		main.level.queue_free()
		main.level = null
		await process_frame
		main._load_level(stop)
		await frames(3)
		await _probe(theme)
	var f := FileAccess.open(out + "/report.txt", FileAccess.WRITE)
	f.store_string("\n".join(report))
	quit()


func _probe(theme: String) -> void:
	var lvl = main.level
	var fac = lvl.facility
	lvl.hazards.events.clear()
	lvl.hazards.set_physics_process(false)
	for m in main.get_tree().get_nodes_in_group("monsters"):
		m.queue_free()
	main.player.global_position = lvl.elevator_pos + Vector3(0, 0.5, -8)   # up top: watches nothing below
	main.player.set_physics_process(false)
	Monster.unstuck_spots.clear()
	root.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	var walkers: Array = []
	for i in 12:
		var w = Walker.new()
		w.main = main
		w.level = lvl
		lvl.add_child(w)
		w.global_position = fac.random_point(lvl.rng, true)
		walkers.append(w)
	# While they roam, show them from above with the gizmos on (the player stays up top, out of sight).
	var live = load("res://src/pathdebug.gd").new()
	live.main = main
	main.add_child(live)
	var top := _top_cam(fac)
	Engine.time_scale = 3.0
	await main.get_tree().create_timer(secs * 3.0).timeout   # (game time)
	Engine.time_scale = 1.0
	top.queue_free()
	live.queue_free()
	var events: Array = []
	var arrivals := 0
	for w in walkers:
		arrivals += w.arrivals
		events.append_array(w.events)
	var shut: Array = fac.doors.keys().filter(func(c): return not fac.doors[c].get_meta("open"))
	say("== %s: %d rooms (+%d lower), %d bulkheads shut, %.0f s game time x 12 walkers: %d arrivals, %d stuck events" % [
		theme, fac.layout.cells.size(), fac.lower.size(), shut.size(), secs * 3.0, arrivals, events.size()])
	# Cluster the events by spot (2 m), worst first.
	var clusters: Array = []   # [position, count, [events]]
	for e in events:
		var p: Vector3 = e[0]
		var hit = null
		for c in clusters:
			if c[0].distance_to(p) < 2.0:
				hit = c
				break
		if hit == null:
			clusters.append([p, 1, [e]])
		else:
			hit[1] += 1
			hit[2].append(e)
	clusters.sort_custom(func(a, b): return a[1] > b[1])
	for c in clusters.slice(0, 8):
		var p: Vector3 = c[0]
		var e: Array = c[2][0]
		var cell: Vector2i = fac.cell_at(p)
		var lp: Vector3 = fac.to_local(p)
		var low: bool = lp.y < -1.0
		var kind: String = (fac.low_kinds.get(cell, "?") if low else fac.kinds.get(cell, "?"))
		var whats := {}
		for x in c[2]:
			whats[x[3]] = whats.get(x[3], 0) + 1
		say("   x%d  %s %s%s at %s (in-room %s)  next %s  goal %s  %s" % [c[1], kind, cell, " B-2" if low else "", lp.snapped(Vector3.ONE * 0.1),
			(lp - Vector3(cell.x * 12.0, lp.y, cell.y * 12.0)).snapped(Vector3.ONE * 0.1), fac.to_local(e[2]).snapped(Vector3.ONE * 0.1) if e[2] != Vector3.INF else "-",
			fac.to_local(e[1]).snapped(Vector3.ONE * 0.1) if e[1] != Vector3.INF else "-", whats])
	# Pictures: gizmos on, fullbright, walkers frozen where they are.
	for w in walkers:
		w.set_physics_process(false)
	var gizmos = load("res://src/pathdebug.gd").new()
	gizmos.main = main
	main.add_child(gizmos)
	root.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	await _overview(theme, fac)
	for i in mini(4, clusters.size()):
		var c: Array = clusters[i]
		var p: Vector3 = c[0]
		var e: Array = c[2][0]
		var w = walkers[i]   # stand one of them back on the spot, heading the way it was
		w.global_position = p
		w.goal = e[1]
		w.set_physics_process(true)
		await main.get_tree().create_timer(0.4).timeout
		w.set_physics_process(false)
		var cam := Camera3D.new()
		cam.fov = 70.0
		main.add_child(cam)
		var back: Vector3 = (p - e[2]) * Vector3(1, 0, 1)
		back = back.normalized() if back.length() > 0.1 else Vector3(1, 0, 0)
		cam.look_at_from_position(p + back * 3.2 + Vector3(0, 2.4, 0) + back.cross(Vector3.UP) * 1.2, p + Vector3(0, 0.4, 0))
		cam.make_current()
		await shot("%s_stuck_%d" % [theme.to_lower(), i])
		cam.look_at_from_position(p + Vector3(0.01, 2.8, 0), p)
		await shot("%s_stuck_%d_top" % [theme.to_lower(), i])
		cam.queue_free()
	root.debug_draw = Viewport.DEBUG_DRAW_DISABLED
	gizmos.queue_free()
	main.player.cam.make_current()
	for w in walkers:
		w.queue_free()


## The whole site from just under the ceiling, looking straight down (orthographic).
func _overview(theme: String, fac) -> void:
	var cam := _top_cam(fac)
	await shot("%s_overview" % theme.to_lower())
	cam.queue_free()


func _top_cam(fac) -> Camera3D:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in fac.layout.cells:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x), maxf(hi.y, c.y))
	var mid := (lo + hi) / 2.0 * 12.0
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(hi.x - lo.x, (hi.y - lo.y) * 16.0 / 9.0) * 12.0 + 14.0
	cam.near = 0.05
	cam.far = 30.0
	main.add_child(cam)
	cam.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), fac.to_global(Vector3(mid.x, 2.3, mid.y)))
	cam.make_current()
	return cam
