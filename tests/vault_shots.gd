# The vault: its door and keycard reader from outside, the strongroom from the door, the deposit
# boxes, the cage, the table, a pried-open box, and the keycard where it was left. Needs a window.
# Run: tests/run.sh 200 --path . -s tests/vault_shots.gd -- <out_dir> [THEME]
extends SceneTree

var main
var out := "user://vault"
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
	await frames(8)
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
	Engine.set_meta("fast_test", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(20)
	for n in main.get_children():
		if n.has_method("_show_title"):
			n.queue_free()
	main.hud.visible = false
	main.rng.seed = 99
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = theme
	stop.rooms = 16
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	Engine.remove_meta("fast_test")
	main.player.set_physics_process(false)
	main.player.frozen = true
	main.player.light_on = false
	var fac = main.level.facility
	if fac.vault_code == "":
		print("no vault on this site")
		quit(1)
		return
	for n in main.level.get_children():
		if n.is_in_group("monsters"):
			n.queue_free()
	await frames(20)
	var vc: Vector3 = fac.to_global(Vector3(fac.vault_cell.x * fac.CELL, 0, fac.vault_cell.y * fac.CELL))
	var door: Node3D = fac.doors[fac.vault_code]
	var dpos: Vector3 = door.global_position
	var out_dir: Vector3 = (dpos - vc) * Vector3(1, 0, 1)
	out_dir = out_dir.normalized()
	# Outside: the door, its surround, the reader.
	look(Vector3(dpos.x, 0, dpos.z) + out_dir * 4.0 + Vector3(0, fac.global_position.y + 1.7, 0) + Vector3(out_dir.z, 0, -out_dir.x) * 1.0, dpos)
	await shot("v1_door_outside")
	var reader = fac.find_children("*", "StaticBody3D", true, false).filter(func(n): return n.has_meta("vault_reader"))[0]
	look(reader.global_position + out_dir * 0.9 + Vector3(0, 0.1, 0), reader.global_position)
	await shot("v2_reader")
	fac.open_vault()
	await create_timer(1.6).timeout
	# Inside, from the doorway, then round the room.
	var inside := Vector3(dpos.x, fac.global_position.y + 1.7, dpos.z) - out_dir * 1.0
	look(inside, vc + Vector3(0, fac.global_position.y + 1.0 - vc.y, 0) - out_dir * 3.0)
	await shot("v3_from_door")
	var side := Vector3(out_dir.z, 0, -out_dir.x)
	look(vc + Vector3(0, fac.global_position.y + 1.7 - vc.y, 0) - side * 1.5, vc + side * 6.0 + Vector3(0, fac.global_position.y + 1.4 - vc.y, 0))
	await shot("v4_deposit_wall")
	var boxes: Array = fac.supplies.filter(func(b): return b.has_meta("deposit"))
	if not boxes.is_empty():
		fac._open_deposit(boxes[0])
		await create_timer(1.0).timeout
		look(boxes[0].global_position + boxes[0].global_transform.basis.z * 1.6 + Vector3(0, 0.6, 0), boxes[0].global_position)
		await shot("v5_box_open")
	look(vc + Vector3(0, fac.global_position.y + 1.9 - vc.y, 0) + out_dir * 2.0, vc + Vector3(0, fac.global_position.y + 0.8 - vc.y, 0) - out_dir * 3.0)
	await shot("v6_table_cage")
	var card = main.get_tree().get_nodes_in_group("pickups").filter(func(n): return n.id == "VAULT_KEYCARD")
	if not card.is_empty():
		main.player.light_on = true
		look(card[0].global_position + Vector3(0.6, 1.0, 0.6), card[0].global_position)
		await shot("v7_keycard")
	quit(0)
