# Close-up screenshots of every entity in a lit room (frozen in a characteristic pose). Needs a window.
# Run: godot --path . -s tests/gallery.gd -- <out_dir>
extends SceneTree

var main
var lvl
var out := "user://gallery"


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

	var entries := [
		["statue", "res://src/statue.gd", 1.4],
		["marionette", "res://src/marionette.gd", 1.0],
		["mimic", "res://src/mimic.gd", 0.6],
		["warden", "res://src/warden.gd", 1.6],
		["pulsator", "res://src/pulsator.gd", 0.7],
		["roomba", "res://src/roomba.gd", 0.15],
		["scrapper", "res://src/scrapper.gd", 0.2],
		["bear_trap", "res://src/bear_trap.gd", 0.05],
		["observer", "res://src/observer.gd", 1.5],
		["wraith", "res://src/wraith.gd", 1.5],
	]
	for e in entries:
		var m = spawn(e[1], spot)
		m.set_physics_process(false)
		m.rotation.y = PI / 2 - 0.5   # face the camera (-x)
		fill.global_position = spot + Vector3(-1.5, 2.5, 1.5)
		var h: float = e[2]
		var dist := 3.2 if h > 0.5 else 1.6
		look(spot + Vector3(-dist, maxf(h, 0.6) + 0.3, 0.5 * dist / 3.2), spot + Vector3(0, h, 0))
		match e[0]:
			"marionette":
				await shot("marionette_crouched")
				m._rise = 1.0
				m._anim = 1.0
				m._apply_pose(1.0)
			"mimic":
				await shot("mimic_disguised")
				m._bite_start()
				await frames(30)
			"pulsator":
				m.chasing = true
				m.fuse = 3.5
				m._animate(0.016, true)
		await shot(e[0])
		m.queue_free()
		await frames(2)
	# Snatcher: look up at the dripping vent, then trigger it.
	var vent = spawn("res://src/snatcher.gd", Vector3(spot.x, fac.global_position.y + fac.H, spot.z))
	vent.set_physics_process(false)
	look(spot + Vector3(-2.5, 1.6, 0), spot + Vector3(0, 3.6, 0))
	await frames(60)
	await shot("snatcher_vent")
	vent._maw.visible = true
	vent._maw.position.y = -1.0
	look(spot + Vector3(-3.0, 1.6, 0), spot + Vector3(0, 2.3, 0))
	await shot("snatcher_maw")
	vent.queue_free()
	var g = spawn("res://src/gloe.gd", spot + Vector3(0, 1.5, 0))
	g.set_process(false)
	fill.light_energy = 0.0
	look(spot + Vector3(-2.5, 1.6, 0.3), spot + Vector3(0, 1.5, 0))
	await shot("gloe")
	g.queue_free()
	# Leviathan mid-leap on the surface.
	main.player.global_position = Vector3(0, 1.3, 0)
	await frames(10)
	var lev = spawn("res://src/leviathan.gd", Vector3.ZERO)
	var target := Vector3(lvl.elevator_pos.x + 16, 0, lvl.elevator_pos.z - 10)
	lev._target = target
	lev._dir = Vector3(1, 0, 0)
	lev.state = lev.ERUPT
	lev._worm.visible = true
	lev._t = 1.15
	lev._process(0.0)
	lev.set_process(false)
	look(target + Vector3(-6, 3, -26), target + Vector3(6, 9, 0))
	await frames(20)
	await shot("leviathan")
	quit()
