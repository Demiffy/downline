# This session's features in game light: blood (a splat, a drip trail), the scanner naming creatures
# for the field guide, the GUIDE terminal pages, and the run-over memento board. Needs a window.
# Run: tests/run.sh 240 --path . -s tests/feature_shots.gd -- <out_dir>
extends SceneTree

const Suit = preload("res://src/suit.gd")

var main
var out := "user://features"


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


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(20)
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = "FACTORY"
	stop.weather = "CLEAR"
	main.player.global_position = Vector3(0, 1.3, 0)
	Engine.set_meta("fast_test", true)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	Engine.remove_meta("fast_test")
	var lvl = main.level
	var fac = lvl.facility
	lvl.hazards.events.clear()
	for n in lvl.get_children():
		if n.is_in_group("monsters") or n.is_in_group("wraiths"):
			n.queue_free()
	var room := Vector3.ZERO
	for c in fac.layout.cells:
		if fac.kinds[c] in ["storage", "office", "break", "machine"] and not lvl.hazards.flooded.has(c):
			room = fac.to_global(Vector3(c.x * 12.0, 0, c.y * 12.0))
			break
	var p = main.player
	p.slots[0] = {"id": "FLASHLIGHT", "charge": 999.0}
	p.sel = 0
	p.light_on = true
	p.equip = {"id": "SCANNER", "charge": -1.0}
	# Blood: three hard hits in a row, then badly hurt and walking: a trail.
	p.global_position = room + Vector3(-2, 0.1, 0)
	await frames(5)
	p.hp = 100.0
	for k in 3:
		p.hurt(25.0)
		p.global_position += Vector3(0.5, 0, 0.3)
		await frames(3)
	p.hp = 15.0
	for k in 40:   # stagger across the room
		p.global_position += Vector3(0.12, 0, -0.06)
		await main.get_tree().create_timer(0.1).timeout
	look(room + Vector3(-3.4, 1.8, 1.6), room + Vector3(-0.5, 0, -0.5))
	await frames(10)
	await shot("blood_fresh")
	p.hp = 1e9
	# Field guide: a warden and a bear trap in view, scanned.
	var w = load("res://src/warden.gd").new()
	w.main = main
	w.level = lvl
	lvl.add_child(w)
	w.global_position = room + Vector3(3.5, 0.05, 0)
	w.set_physics_process(false)
	var trap = load("res://src/bear_trap.gd").new()
	trap.main = main
	trap.level = lvl
	lvl.add_child(trap)
	trap.global_position = room + Vector3(1.0, 0.0, 1.5)
	main.guide.seen.clear()
	look(room + Vector3(-3.0, 1.6, 0.4), room + Vector3(2.0, 1.0, 0.4))
	await frames(5)
	main.scan(p.global_position, 16.0)
	await main.get_tree().create_timer(0.9).timeout
	await shot("guide_first_scan")
	await main.get_tree().create_timer(4.5).timeout
	p._scan_cd = 0.0
	main.scan(p.global_position, 16.0)
	await main.get_tree().create_timer(0.9).timeout
	await shot("guide_known_scan")
	main.guide.killed["warden"] = 2
	main.open_terminal()
	main.term.run("GUIDE")
	await frames(10)
	await shot("guide_terminal_list")
	main.term.run("CLEAR")
	main.term.run("GUIDE WARDEN")
	await main.get_tree().create_timer(2.5).timeout   # (the terminal types it out)
	await shot("guide_terminal_entry")
	main.term.close()
	# Memento: five photos of the employee pinned up, then the run ends.
	var fig := Node3D.new()
	lvl.add_child(fig)
	fig.global_position = room + Vector3(0, 0, -2.0)
	Suit.standing(fig)
	var vp := SubViewport.new()
	vp.size = Vector2i(320, 270)
	vp.msaa_3d = Viewport.MSAA_4X
	main.add_child(vp)
	var pc := Camera3D.new()
	pc.fov = 48.0
	vp.add_child(pc)
	for k in 5:
		pc.look_at_from_position(room + Vector3(-1.5 + k * 0.8, 1.6, 1.4), fig.global_position + Vector3(0, 1.2, 0))
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var tex := ImageTexture.create_from_image(vp.get_texture().get_image())
		main.pin_photo({"id": "PHOTO", "charge": -1.0, "extra": {"tex": tex, "stamp": "STN %s   %02d:%02d" % ["ABC"[k % 3], 9 + k * 2, 14 * k % 60]}},
			main.train.to_global(Vector3(-4.6 + k * 0.3, 1.7, -1.9)), main.train.global_basis.z)
	vp.queue_free()
	main.game_over("ASSIGNMENT FAILED\nThe gate held. The train did not.\nYou have been factored in.")
	await frames(20)
	await shot("memento")
	quit()
