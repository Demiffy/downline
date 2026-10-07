# Weapons in hand (rest + mid-swing + shotgun kick), the photo held up close, item models on the
# floor (weapons, photo, remains), and every creature's death pose. Needs a window.
# Run: tests/run.sh 240 --path . -s tests/combat_shots.gd -- <out_dir>
extends SceneTree

var main
var lvl
var fac
var out := "user://combat"


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


func hold(id: String, charge := -1.0, extra := {}) -> void:
	main.player.slots[0] = {"id": id, "charge": charge, "extra": extra}
	main.player.sel = 0
	await frames(4)


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
	fac = lvl.facility
	lvl.hazards.events.clear()
	for n in lvl.get_children():
		if n.is_in_group("monsters") or n.is_in_group("wraiths"):
			n.queue_free()
	main.player.hp = 1e9
	var room := Vector3.ZERO
	for c in fac.layout.cells:
		if not fac.kinds[c] in ["start", "pit", "tunnel", "atrium", "vault"] and not lvl.hazards.flooded.has(c) and not lvl.hazards.gassed.has(c):
			room = fac.to_global(Vector3(c.x * 12.0, 0, c.y * 12.0))
			break
	var spot := room + Vector3(0, 0.05, 0)
	var fill := OmniLight3D.new()
	fill.omni_range = 10.0
	fill.light_energy = 1.6
	fill.light_color = Color(1, 0.88, 0.75)
	main.add_child(fill)
	fill.global_position = spot + Vector3(-1.5, 2.6, 1.2)
	main.player.set_physics_process(false)
	look(spot + Vector3(-3.0, 1.6, 0), spot + Vector3(2, 1.2, 0))

	# --- in hand ---
	for id in ["CROWBAR", "FIRE_AXE", "SHOTGUN"]:
		await hold(id, 6.0 if id == "SHOTGUN" else -1.0)
		await frames(20)
		await shot("hand_%s" % id.to_lower())
		if id == "SHOTGUN":
			main.player.arm.recoil()
			await frames(2)
			await shot("hand_shotgun_kick")
		else:
			main.player.arm.swing(1.0)
			await main.get_tree().create_timer(0.36).timeout
			await shot("hand_%s_windup" % id.to_lower())
			await main.get_tree().create_timer(0.12).timeout
			await shot("hand_%s_strike" % id.to_lower())
	# The photo: a picture taken here, from over there.
	var vp := SubViewport.new()
	vp.size = Vector2i(144, 128)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	main.add_child(vp)
	var pc := Camera3D.new()
	vp.add_child(pc)
	pc.look_at_from_position(spot + Vector3(2.5, 1.6, 1.0), main.player.global_position + Vector3(0, 1.25, 0))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var tex := ImageTexture.create_from_image(vp.get_texture().get_image())
	vp.queue_free()
	await hold("PHOTO", -1.0, {"tex": tex})
	await frames(20)
	await shot("hand_photo")
	main.player._use()
	await frames(30)
	await shot("hand_photo_inspect")
	main.player._use()
	main.player.slots[0] = null
	await frames(10)

	# --- on the floor ---
	var items := ["CROWBAR", "FIRE_AXE", "SHOTGUN", "PHOTO"]
	for i in items.size():
		var p = main.spawn_item(items[i], spot + Vector3(-0.6 + i * 0.4, 0.3, 0.0), 6.0, lvl)
		p.rotation.y = 0.3
		if items[i] == "PHOTO":
			p.set_extra({"tex": tex})
	var rem = main.spawn_item("REMAINS", spot + Vector3(0.4, 0.4, 1.4), -1.0, lvl)
	rem.rotation.y = 1.2
	await main.get_tree().create_timer(1.5).timeout
	look(spot + Vector3(-0.2, 1.1, -1.1), spot + Vector3(0.0, 0.0, 0.2))
	await shot("floor_items")
	look(spot + Vector3(-1.4, 1.5, 2.2), spot + Vector3(0.4, 0.1, 1.4))
	await shot("floor_remains")
	for n in main.get_tree().get_nodes_in_group("pickups"):
		if n.global_position.distance_to(spot) < 3.0:
			n.queue_free()

	# --- death poses ---
	var who := ["warden"] if OS.get_cmdline_user_args().has("quick") else ["warden", "observer", "marionette", "pulsator", "mimic", "roomba"]
	for name in who:
		var m = spawn("res://src/%s.gd" % name, spot)
		await frames(4)
		m.set_physics_process(false)
		m.rotation.y = PI / 2 - 0.5
		if name == "observer":
			m._plant_feet()
		look(spot + Vector3(-3.2, 1.7, 1.2), spot + Vector3(0, 0.6, 0))
		m.die()
		await main.get_tree().create_timer(2.0).timeout
		await shot("dead_%s" % name)
		m.queue_free()
		await frames(3)
	quit()
