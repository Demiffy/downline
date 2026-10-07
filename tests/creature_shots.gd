# The observer and the wraith: model close-ups under a fill light, then the real thing in game light
# (following you, the flash, the photo it leaves; the wraith stalking, burning in a flashlight beam).
# Needs a window. Run: tests/run.sh 200 --path . -s tests/creature_shots.gd -- <out_dir> [THEME]
extends SceneTree

var main
var lvl
var fac
var out := "user://creatures"
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


func shot(name: String) -> void:
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func look(pos: Vector3, at: Vector3) -> void:
	var p = main.player
	p.global_position = pos - Vector3(0, 1.6, 0)
	p.velocity = Vector3.ZERO
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
	stop.theme = theme
	stop.weather = "CLEAR"
	stop.biome = "DESERT"
	main.player.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	await frames(20)
	lvl = main.level
	fac = lvl.facility
	lvl.hazards.events.clear()
	for n in lvl.get_children():
		if n.is_in_group("monsters") or n.is_in_group("wraiths"):
			n.queue_free()
	main.player.hp = 1e9
	main.hud.visible = false
	var room := Vector3.ZERO
	for c in fac.layout.cells:
		if fac.kinds[c] in ["storage", "office", "break", "lab"] and not lvl.hazards.flooded.has(c) and not lvl.hazards.gassed.has(c):
			room = fac.to_global(Vector3(c.x * 12.0, 0, c.y * 12.0))
			break
	if room == Vector3.ZERO:
		for c in fac.layout.cells:
			if not fac.kinds[c] in ["start", "pit", "tunnel", "atrium", "vault"] and not lvl.hazards.flooded.has(c):
				room = fac.to_global(Vector3(c.x * 12.0, 0, c.y * 12.0))
				break
	var spot := room + Vector3(0.0, 0.05, 0)
	var fill := OmniLight3D.new()
	fill.omni_range = 9.0
	fill.light_energy = 1.5
	fill.light_color = Color(1, 0.88, 0.75)
	main.add_child(fill)
	fill.global_position = spot + Vector3(-1.8, 2.6, 1.6)
	main.player.set_physics_process(false)

	# --- Observer: the model ---
	var ob = spawn("res://src/observer.gd", spot)
	await frames(3)
	ob.set_physics_process(false)
	ob.rotation.y = PI / 2 - 0.5
	ob._plant_feet()
	ob._animate(1.0)
	look(spot + Vector3(-3.6, 1.8, 1.4), spot + Vector3(0, 1.1, 0))
	await shot("observer_front")
	look(spot + Vector3(1.0, 1.5, 3.4), spot + Vector3(0, 1.1, 0))
	await shot("observer_side")
	look(spot + Vector3(-1.1, 1.9, 0.5), ob._tilt.global_position)
	await shot("observer_camera")
	look(spot + Vector3(-1.0, 1.1, -0.9), spot + Vector3(0, 1.2, 0))
	await shot("observer_hub_photos")
	# Mid-stride: let it walk a few steps, then freeze it.
	ob.set_physics_process(true)
	ob.state = ob.LURK
	ob._cool = 999.0
	ob._goal = spot + Vector3(0, 0, 4.0)
	look(spot + Vector3(-4.2, 1.7, 2.0), spot + Vector3(0, 1.0, 2.0))
	await frames(40)
	ob.set_physics_process(false)
	await shot("observer_walking")
	ob.global_position = spot
	ob._plant_feet()

	# --- Observer in game light: behind you; you turn round; the flash; the photo ---
	fill.light_energy = 0.0
	main.player.set_physics_process(true)
	main.player.slots[0] = {"id": "FLASHLIGHT", "charge": 999.0}
	main.player.sel = 0
	main.player.light_on = true
	ob.set_physics_process(true)
	ob._cool = 0.0
	ob.state = ob.FOLLOW
	ob._prey = main.player
	ob._creep = 3.0
	var me := spot + Vector3(-3.5, 1.6, 0)
	look(me, me + Vector3(-4, 0, 0))   # facing away
	await frames(150)
	look(me, ob._lens.global_position)   # turn round
	main.hud.visible = true
	await frames(12)
	await shot("observer_turned_round")
	while ob.state == ob.CHARGE:
		await process_frame
	await frames(1)
	await shot("observer_flash")
	await frames(30)
	await shot("observer_blinded")
	main.hud.visible = false
	main.player.blind = 0.0
	await main.get_tree().create_timer(1.5).timeout
	var photos: Array = main.get_tree().get_nodes_in_group("photos")
	if not photos.is_empty():
		var ph: Node3D = photos[0]
		main.player.set_physics_process(false)
		fill.light_energy = 0.8
		fill.global_position = ph.global_position + Vector3(0.3, 1.0, 0.3)
		look(ph.global_position + Vector3(0.0, 0.3, 0.1), ph.global_position)
		await shot("observer_photo")
		look(ph.global_position + Vector3(-1.2, 1.6, 0.6), ph.global_position)
		await shot("observer_photo_standing")
	ob.queue_free()
	for ph in photos:
		ph.queue_free()

	# --- Wraith: the model ---
	look(spot + Vector3(-6.0, 1.6, 0), spot)   # well clear of where it appears
	main.player.set_physics_process(false)
	main.player.light_on = false
	fill.light_energy = 1.5
	fill.global_position = spot + Vector3(-1.8, 2.6, 1.6)
	var wr = spawn("res://src/wraith.gd", spot)
	await frames(3)
	wr.set_physics_process(false)
	wr._dark.visible = false   # (just for the model shots)
	wr.state = wr.STALK
	wr.rotation.y = PI / 2 - 0.5
	for i in 40:
		wr._t += 0.05
		wr._animate(0.05)
	look(spot + Vector3(-3.4, 1.8, 1.3), spot + Vector3(0, 1.3, 0))
	await shot("wraith_front")
	look(spot + Vector3(1.4, 1.6, 3.2), spot + Vector3(0, 1.2, 0))
	await shot("wraith_side")
	look(spot + Vector3(-1.2, 2.2, 0.4), wr._head.global_position)
	await shot("wraith_head")
	look(spot + Vector3(2.4, 1.2, -1.2), spot + Vector3(0, 0.6, 0.3))
	await shot("wraith_back_chain")
	# --- Wraith in game light ---
	fill.light_energy = 0.0
	wr._dark.visible = true
	wr.global_position = spot
	wr.set_physics_process(true)
	main.player.set_physics_process(true)
	main.hud.visible = true
	look(spot + Vector3(-7.0, 1.6, 0.4), spot + Vector3(0, 1.4, 0))
	await frames(25)
	await shot("wraith_stalking_dark")
	main.player.light_on = true   # the flashlight's still in slot 0
	await frames(20)
	await shot("wraith_burning")
	quit()
