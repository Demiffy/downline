# Facility lighting: a ceiling grate's shaft of light, the flashlight's beam in the haze, a room in
# a power failure (red emergency lamps, a turning beacon). Needs a window.
# Run: godot --path . -s tests/light_shots.gd -- <out_dir>
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
	var grates: Array = fac.find_children("*", "SpotLight3D", true, false).filter(func(l): return absf(l.rotation.x + PI / 2.0) < 0.01)
	print("grates: ", grates.size(), " made ", fac._grates, " theme ", fac.theme_id, "  flickering: ", fac.flicker.size())
	# A grate in a room we know (the one shot below), looked up at from a few metres off.
	var gc: Vector2i = fac.layout.cells[min(2, fac.layout.cells.size() - 1)]
	var lo := Vector3(gc.x * fac.CELL, 0, gc.y * fac.CELL)
	fac._grate(lo + Vector3(1.0, 0, 1.0), Color(1, 0.85, 0.6))
	var go: Vector3 = fac.to_global(lo)
	p.global_position = go + Vector3(-2.2, 0.1, -2.2)
	p.look_at(go + Vector3(1.0, 0.1, 1.0))
	p.rotation.x = 0
	p.rotation.z = 0
	p.head.rotation.x = 0.5
	await shot("l_grate", 60)
	var gl = fac.find_children("*", "SpotLight3D", true, false).filter(func(l): return absf(l.rotation.x + PI / 2.0) < 0.01).back()
	print("lamp at ", gl.global_position, " energy ", gl.light_energy, " range ", gl.spot_range, " visible ", gl.is_visible_in_tree(), " dir ", -gl.global_transform.basis.z)
	# A room, lights out, by flashlight.
	var c: Vector2i = fac.layout.cells[min(2, fac.layout.cells.size() - 1)]
	var o: Vector3 = fac.to_global(Vector3(c.x * fac.CELL, 0.1, c.y * fac.CELL))
	p.global_position = o + Vector3(-3, 0, -3)
	p.look_at(o + Vector3(3, 0, 3))
	p.rotation.x = 0
	p.head.rotation.x = -0.05
	await shot("l_room", 30)
	main.level.hazards.power_fail()
	await create_timer(2.5).timeout   # (the stutter before it goes dark is real time, however fast the frames)
	await shot("l_power_fail", 120)
	p.slots[0] = {"id": "FLASHLIGHT", "charge": 100.0}
	p.sel = 0
	p.light_on = true
	p._held_changed() if p.has_method("_held_changed") else null
	await shot("l_flashlight", 30)
	quit()
