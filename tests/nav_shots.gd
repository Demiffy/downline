# The baked navigation mesh drawn over the facility (fullbright), around every mezzanine and pit
# stair, so gaps in it show. Needs a window. Run: tests/run.sh 240 --path . -s tests/nav_shots.gd -- <out_dir> [THEME]
extends SceneTree

var main
var out := "user://nav"
var theme := "FACTORY"


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


func _run() -> void:
	debug_navigation_hint = true   # (before any region exists, or it is never drawn)
	NavigationServer3D.set_debug_enabled(true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = theme
	stop.rooms = 26
	main.player.global_position = Vector3(0, 1.3, 0)
	Engine.set_meta("fast_test", true)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	var fac = main.level.facility
	for t in 12:
		if fac.kinds.values().has("atrium"):
			break
		main.level.queue_free()
		main.level = null
		await process_frame
		main._load_level(stop)
		await frames(3)
		fac = main.level.facility
	main.hud.visible = false
	main.player.set_physics_process(false)
	main.player.global_position = main.level.elevator_pos + Vector3(0, 0.5, -8)
	root.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	var giz = load("res://src/pathdebug.gd").new()
	giz.main = main
	giz.graph = false
	main.add_child(giz)
	var n := 0
	for c in fac.stairs:
		if fac.kinds.get(c, "") != "atrium" and n >= 3:
			continue
		var s: Dictionary = fac.stairs[c]
		var hi: Vector3 = fac.to_global(s.high)
		var lo: Vector3 = fac.to_global(s.low)
		var mid := (hi + lo) / 2.0
		var d := (lo - hi) * Vector3(1, 0, 1)
		var side := d.normalized().cross(Vector3.UP)
		var cam := Camera3D.new()
		main.add_child(cam)
		cam.look_at_from_position(mid + side * 3.6 - d * 0.15 + Vector3(0, 1.5, 0), mid - Vector3(0, 0.6, 0))
		cam.make_current()
		await frames(8)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s_%d_%d.png" % [out, fac.kinds.get(c, "?"), c.x, c.y])
		cam.queue_free()
		n += 1
		if n >= 6:
			break
	quit()
