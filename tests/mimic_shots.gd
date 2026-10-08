# The mimic: hiding (its tells), mid-bite with the tongue out, and dead. Needs a window.
# Run: tests/run.sh 150 --path . -s tests/mimic_shots.gd -- <out_dir>
extends SceneTree

var main
var lvl
var out := "user://mimic"


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
	var d := at - pos
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func spawn(path: String, pos: Vector3) -> Node:
	var m = load(path).new()
	m.main = main
	m.level = lvl
	lvl.add_child(m)
	m.global_position = pos
	return m


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(20)
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = "FACTORY"
	stop.weather = "CLEAR"
	stop.biome = "DESERT"
	main.player.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	await frames(20)
	lvl = main.level
	var fac = lvl.facility
	for n in lvl.get_children():
		if n.is_in_group("monsters"):
			n.queue_free()
	main.player.set_physics_process(false)
	main.player.hp = 1e9
	main.hud.visible = false
	var room := Vector3.ZERO
	for c in fac.layout.cells:
		if fac.kinds[c] in ["storage", "office", "machine", "break", "lab", "collapsed"]:
			room = fac.to_global(Vector3(c.x * 12.0, 0, c.y * 12.0))
			break
	var fill := OmniLight3D.new()
	fill.omni_range = 9.0
	fill.light_energy = 1.4
	fill.light_color = Color(1, 0.85, 0.7)
	main.add_child(fill)
	var spot := room + Vector3(0.0, 0.05, 0)
	var cam := room + Vector3(-3.2, 1.5, 0.6)

	var m = spawn("res://src/mimic.gd", spot)
	m.set_physics_process(false)
	m.rotation.y = PI / 2 - 0.5
	fill.global_position = spot + Vector3(-1.5, 2.5, 1.5)
	look(spot + Vector3(-2.2, 1.5, 0.5), spot + Vector3(0, 0.5, 0))
	await shot("mimic_hidden")
	look(spot + Vector3(-0.9, 1.5, 0.3), spot + Vector3(0, 0.85, 0))
	await shot("mimic_lid")
	m._bite_start()
	for i in 40:
		m.ext = minf(1.0, i / 20.0)
		m._aim = 0.2
		m._pose_tongue(0.016)
		await process_frame
	look(spot + Vector3(-2.2, 1.4, 1.2), spot + Vector3(-0.6, 0.9, 0))
	await shot("mimic_bite")
	m.die()
	await frames(80)
	look(spot + Vector3(-1.8, 1.6, 1.4), spot + Vector3(0, 0.3, 0))
	await shot("mimic_dead")
	quit(0)
