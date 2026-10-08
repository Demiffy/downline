# Screenshots of hazards and events. Needs a window.
# Run: godot --path . -s tests/hazard_shots.gd -- <out_dir> [THEME]
extends SceneTree

var main
var out := "user://shots"
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


func secs(t: float) -> void:
	await main.get_tree().create_timer(t).timeout


func shot(name: String) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, theme.to_lower(), name])
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
	var p = main.player
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = theme
	stop.rooms = 20
	stop.weather = "CLEAR"
	p.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	Engine.remove_meta("fast_test")
	p.hp = 1e9
	p.slots[0] = {"id": "FLASHLIGHT", "charge": 99999.0}
	p.sel = 0
	p.light_on = true
	var lvl = main.level
	var fac = lvl.facility
	var hz = lvl.hazards
	hz.events.clear()
	for n in lvl.get_children():
		if n.is_in_group("monsters") or (n.get_script() and n.get_script().resource_path.get_file() in ["snatcher.gd", "bear_trap.gd", "gloe.gd"]):
			n.queue_free()
	var rooms: Array = fac.layout.cells.filter(func(c): return not fac.kinds[c] in ["start", "pit", "vault", "atrium", "tunnel"] and not hz.flooded.has(c) and not hz.gassed.has(c))
	if hz.flooded.is_empty():
		hz._flood(rooms.pop_back())
	if hz.cables.is_empty():
		var c: Vector2i = hz.flooded.keys()[0]
		hz._cable(c, Vector3(c.x * 12.0, 0, c.y * 12.0))
	if hz.gassed.is_empty():
		hz._gas(rooms.pop_back())
	if hz.steams.is_empty():
		hz._steam_room(rooms.pop_back())
	# Flood + live cable.
	var cb: Dictionary = hz.cables[0]
	var cc: Vector3 = fac.to_global(Vector3(cb.cell.x * 12.0, 0, cb.cell.y * 12.0))
	var from: Vector3 = cc + Vector3(-signf(cb.at.x - cc.x) * 1.5, 0.05, -signf(cb.at.z - cc.z) * 1.5)   # on the walkway cross
	look(from, cb.at + Vector3(0, 0.6, 0))
	await frames(5)
	print("flash=", p.flash, " hp=", p.hp, " hud flash a=", main.hud.flash_r.color.a, " pos=", p.global_position, " cable=", cb.at)
	await shot("flood")
	cb.state = 1
	cb.t = 0.6
	await secs(0.65)
	await shot("cable_arc")
	# Gas.
	var gc: Vector2i = hz.gassed.keys()[0]
	var go: Vector3 = fac.to_global(Vector3(gc.x * 12.0, 0, gc.y * 12.0))
	look(go + Vector3(-4.5, 0.05, -0.5), go + Vector3(2, 1, 0))
	p.slots[1] = {"id": "GAS_MASK", "charge": -1.0}
	await secs(1.5)
	await shot("gas")
	look(go + Vector3(4.5, 0.05, 4.5), go + Vector3(-2, 0.6, -2))
	await secs(0.5)
	await shot("gas_across")
	var bc = fac.find_children("*", "SpotLight3D", true, false).filter(func(l): return l.light_color.g < 0.6 and l.light_color.r > 0.9)
	if not bc.is_empty():
		var bp: Vector3 = bc[0].get_parent().global_position
		var side := (bp - go) * Vector3(1, 0, 1)
		look(bp - side.normalized() * 2.2 + side.normalized().cross(Vector3.UP) * 1.6 + Vector3(0, -2.6, 0), bp)   # from the side, close: is it on the wall?
		await secs(0.3)
		await shot("gas_beacon")
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:   # from the next room, looking in at the doorway
		if fac.layout.links[gc].has(gc + d) and not fac.kinds.get(gc + d, "") in ["pit", "stairwell", "atrium"]:
			var dv := Vector3(d.x, 0, d.y)
			look(go + dv * 8.6 + Vector3(0, 0.05, 0), go + dv * 5.0 + Vector3(0, 0.4, 0))
			await secs(0.5)
			await shot("gas_doorway")
			break
	# Steam.
	var st: Dictionary = hz.steams[0]
	var side: Vector3 = st.dir.cross(Vector3.UP).normalized()
	look(st.at + st.dir * 2.0 + side * 3.2 - Vector3(0, 1.35, 0), st.at + st.dir * 1.6)
	st.state = 1
	st.t = 0.0
	await secs(0.6)
	await shot("steam")
	st.state = 0
	st.t = 99.0
	st.fx.core.emitting = false
	# Breaker.
	var br: Node3D = hz.breaker
	look(br.global_position + br.global_transform.basis.z * -2.2 + br.global_transform.basis.x * 0.6, br.global_position + Vector3(0, 1.3, 0))
	await shot("breaker")
	hz.power_fail()
	await secs(1.6)
	await shot("breaker_dark")
	look(fac.to_global(Vector3(4.5, 0.05, 4.5)), fac.to_global(Vector3(-2, 1.4, -3)))
	p.light_on = false
	await shot("blackout")
	p.light_on = true
	hz.restore()
	await secs(2.0)
	# Tremor debris.
	look(fac.to_global(Vector3(4.5, 0.05, 4.5)), fac.to_global(Vector3(0, 0.6, 0)))
	hz.tremor()
	await secs(2.0)
	await shot("tremor")
	await secs(3.0)
	# Airdrop.
	main.hours = 15.0
	p.light_on = false
	look(lvl.elevator_pos + Vector3(0, 0.3, -8), lvl.elevator_pos + Vector3(0, 0.3, -40))
	Engine.set_meta("fast_test", true)
	hz.airdrop()
	await secs(0.6)
	Engine.remove_meta("fast_test")
	var crate: Node3D = null
	for n in main.get_tree().get_nodes_in_group("scan_targets"):
		if n.get_meta("scan_name") == "AIRDROP":
			crate = n
	if crate == null:   # still falling: find the newest supply crate under the level
		for n in lvl.get_children():
			if n.has_meta("lid"):
				crate = n
	await secs(0.2)
	look(crate.global_position + Vector3(6, 0, 6) - Vector3(0, crate.global_position.y - lvl.ground_y(crate.global_position.x + 6, crate.global_position.z + 6), 0), crate.global_position + Vector3(0, 3, 0))
	await shot("airdrop_fall")
	await secs(1.8)
	main.hours = 20.5
	var cp: Vector3 = crate.global_position
	look(cp + Vector3(5, lvl.ground_y(cp.x + 5, cp.z + 4) - cp.y, 4), cp + Vector3(0, 0.8, 0))
	await secs(1.0)
	await shot("airdrop_flare")
	quit()
