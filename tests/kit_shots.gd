# The employee model (front, back, side, helmet close-up), the ragdoll after it falls, and the
# photo: in hand, held up close, both sides of the print, pinned to the train wall. Needs a window.
# Run: tests/run.sh 240 --path . -s tests/kit_shots.gd -- <out_dir>
extends SceneTree

const Suit = preload("res://src/suit.gd")

var main
var lvl
var out := "user://kit"


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
	stop.biome = "DESERT"
	main.player.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	await frames(20)
	lvl = main.level
	var fac = lvl.facility
	lvl.hazards.events.clear()
	for n in lvl.get_children():
		if n.is_in_group("monsters") or n.is_in_group("wraiths"):
			n.queue_free()
	main.player.hp = 1e9
	main.hud.visible = false
	var room := Vector3.ZERO
	for c in fac.layout.cells:
		if not fac.kinds[c] in ["start", "pit", "tunnel", "atrium", "vault"] and not lvl.hazards.flooded.has(c) and not lvl.hazards.gassed.has(c):
			room = fac.to_global(Vector3(c.x * 12.0, 0, c.y * 12.0))
			break
	var spot := room + Vector3(0, 0.0, 0)
	var fill := OmniLight3D.new()
	fill.omni_range = 10.0
	fill.light_energy = 2.0
	fill.light_color = Color(1, 0.92, 0.82)
	main.add_child(fill)
	fill.global_position = spot + Vector3(-1.4, 2.4, -1.6)
	main.player.set_physics_process(false)

	# --- the employee ---
	var fig := Node3D.new()
	lvl.add_child(fig)
	fig.global_position = spot
	Suit.standing(fig)
	look(spot + Vector3(0.6, 1.2, -2.6), spot + Vector3(0, 0.95, 0))
	await shot("suit_front")
	look(spot + Vector3(-1.2, 1.3, 2.4), spot + Vector3(0, 0.95, 0))
	fill.global_position = spot + Vector3(-1.4, 2.4, 1.6)
	await shot("suit_back")
	look(spot + Vector3(-2.6, 1.1, -0.3), spot + Vector3(0, 0.95, 0))
	await shot("suit_side")
	fill.global_position = spot + Vector3(-0.6, 2.0, -1.2)
	look(spot + Vector3(0.25, 1.7, -0.8), spot + Vector3(0, 1.6, 0))
	await shot("suit_helmet")
	look(spot + Vector3(0.25, 0.4, -0.85), spot + Vector3(0.1, 0.15, 0))
	await shot("suit_boots")
	fig.queue_free()

	# --- the ragdoll falls ---
	var r = main.spawn_item("REMAINS", spot, -1.0, lvl)
	r.pose = "stand"
	await main.get_tree().create_timer(3.0).timeout
	fill.global_position = r.global_position + Vector3(-1.0, 2.2, -1.0)
	look(r.global_position + Vector3(-1.6, 1.5, -1.4), r.global_position + Vector3(0, 0.1, 0))
	await shot("ragdoll_fallen")
	var d = main.spawn_item("REMAINS", spot + Vector3(2.0, 0, 0), -1.0, lvl)
	await main.get_tree().create_timer(3.0).timeout
	look(d.global_position + Vector3(0.2, 1.6, -1.8), d.global_position)
	await shot("ragdoll_dropped")
	r.queue_free()
	d.queue_free()

	# --- the photo ---
	var vp := SubViewport.new()
	vp.size = Vector2i(320, 270)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	main.add_child(vp)
	var fig2 := Node3D.new()
	lvl.add_child(fig2)
	fig2.global_position = spot + Vector3(0, 0, 0)
	Suit.standing(fig2)
	var pc := Camera3D.new()
	pc.fov = 48.0
	vp.add_child(pc)
	pc.look_at_from_position(spot + Vector3(0.5, 1.6, -3.0), spot + Vector3(0, 1.2, 0))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var tex := ImageTexture.create_from_image(vp.get_texture().get_image())
	vp.queue_free()
	fig2.queue_free()
	var e := {"tex": tex, "stamp": "STN A   09:38"}
	main.hud.visible = true
	main.player.slots[0] = {"id": "PHOTO", "charge": -1.0, "extra": e}
	main.player.sel = 0
	look(spot + Vector3(-3.0, 1.6, 0), spot + Vector3(2, 1.2, 0))
	await frames(20)
	await shot("photo_hand")
	main.player._use()
	await frames(30)
	await shot("photo_inspect")
	main.player._use()
	main.player.slots[0] = null
	main.hud.visible = false
	var p = main.spawn_item("PHOTO", spot + Vector3(0, 0.2, 0), -1.0, lvl)
	p.set_extra(e)
	await main.get_tree().create_timer(1.0).timeout
	fill.global_position = p.global_position + Vector3(0.3, 0.8, 0.2)
	look(p.global_position + Vector3(0, 0.45, 0.2), p.global_position)
	await shot("photo_floor_front")
	p.global_rotation = Vector3(PI, 0.4, 0)
	p.freeze = true
	await frames(3)
	look(p.global_position + Vector3(0, 0.45, 0.2), p.global_position)
	await shot("photo_floor_back")
	p.queue_free()
	# Pinned on the train wall, three of them.
	main.player.global_position = Vector3(0, 1.3, 0)
	for k in 3:
		main.pin_photo({"id": "PHOTO", "charge": -1.0, "extra": e}, main.train.to_global(Vector3(-4.6 + k * 0.28, 1.75 - (k % 2) * 0.12, -1.9)), main.train.global_basis.z)
	await frames(5)
	look(main.train.to_global(Vector3(-4.3, 1.65, -0.6)), main.train.to_global(Vector3(-4.3, 1.68, -1.9)))
	await shot("photo_pinned")
	quit()
