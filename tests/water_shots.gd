# Water: a puddle on a facility floor in the flashlight, a flooded room with rings round your feet as
# you wade, rain puddles round the train with the rain ringing on them. Needs a window.
# Run: godot --path . -s tests/water_shots.gd -- <out_dir> [seed]
extends SceneTree

var out := "user://shots"
var main


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func shot(name: String, frames := 30) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.rng.seed = int(OS.get_cmdline_user_args()[1]) if OS.get_cmdline_user_args().size() > 1 else 7
	main.term.run("LEAVE_CHECKPOINT")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	while main.busy:
		await process_frame
	main.hud.visible = false
	var fac = main.level.facility
	for n in main.level.get_children():
		if n.is_in_group("monsters"):
			n.free()
	var p = main.player
	p.frozen = true
	p.slots[0] = {"id": "FLASHLIGHT", "charge": 100.0}
	p.sel = 0
	p.light_on = true
	# A puddle on a facility floor, with the flashlight on it.
	var puds: Array = fac.find_children("*", "Decal", true, false)
	print("puddles: ", puds.size(), "  drips: ", fac._drips.size())
	if not puds.is_empty():
		var d: Vector3 = puds[0].global_position
		p.global_position = d + Vector3(2.2, 0.1, 0.4)
		p.look_at(Vector3(d.x, p.global_position.y, d.z))
		p.rotation = Vector3(0, p.rotation.y, 0)
		p.head.rotation.x = -0.55
		await shot("w_puddle", 40)
	# A flooded room: wade across it.
	var c: Vector2i = fac.layout.cells[min(2, fac.layout.cells.size() - 1)]
	main.level.hazards._flood(c)
	var o: Vector3 = fac.to_global(Vector3(c.x * fac.CELL, 0.1, c.y * fac.CELL))
	p.global_position = o + Vector3(-3, 0, -2)
	p.rotation = Vector3(0, deg_to_rad(-135), 0)
	p.head.rotation.x = -0.45
	for i in 40:
		p.global_position += Vector3(0.05, 0, 0.03)
		await process_frame
	await shot("w_flood", 2)
	# Outside in the rain.
	main.stop.weather = "RAIN"
	main.weather._level = null
	p.global_position = main.train.global_position + Vector3(10, 0.5, -8)
	p.look_at(main.train.global_position + Vector3(0, 0.5, 0))
	p.rotation = Vector3(0, p.rotation.y, 0)
	p.head.rotation.x = -0.35
	p.light_on = false
	await shot("w_rain_puddles", 240)
	var ahead: Vector3 = p.global_position - p.global_transform.basis.z * 3.0
	var hit: Dictionary = p.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(ahead + Vector3(0, 5, 0), ahead + Vector3(0, -5, 0), 1))
	print("ground ahead: ", hit.get("position", "none"), " collider layer ", hit.get("collider").collision_layer if hit.has("collider") else -1)
	load("res://src/art.gd").puddle(main.level, hit.position, 3.0, 0.3)
	await shot("w_puddle_near", 30)
	quit()
