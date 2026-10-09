# The playground's tools: the status strip, each page of the panel, the new spawns. Needs a window.
# Run: tests/run.sh 300 --path . -s tests/playground_shots.gd -- <out_dir> playground LAB
extends SceneTree

var main
var pg
var out := "user://pg"


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
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	for n in main.get_children():
		if n.get_script() != null and n.get_script().resource_path.ends_with("playground.gd"):
			pg = n
	if pg == null:
		print("no playground (pass 'playground' after --)")
		quit(1)
		return
	while not pg._ready_done:
		await process_frame
	await frames(30)
	await shot("pg1_strip")
	for t in ["CREATURES", "ITEMS", "PLAYER", "WORLD"]:
		if not pg.panel.visible:
			pg._hotkey(KEY_TAB)
		pg._tab(t)
		await shot("pg2_" + t.to_lower())
	pg._hotkey(KEY_TAB)
	# The new ones: a siren and a husk ahead, and a body that's about to get up.
	var p = main.player
	var ahead: Vector3 = p.global_position - p.global_transform.basis.z * 6.0
	for path in ["res://src/siren.gd", "res://src/husk.gd"]:
		var m = load(path).new()
		m.main = main
		m.level = main.level
		main.level.add_child(m)
		m.global_position = ahead + p.global_transform.basis.x * (1.2 if path.ends_with("husk.gd") else -1.2)
	await frames(30)
	await shot("pg3_new_creatures")
	pg.god = false
	main.player.hurt(60.0, "test")
	await frames(10)
	await shot("pg4_hurt")
	main.player.hp = 100.0
	await pg._go_checkpoint()
	await frames(40)
	await shot("pg5_checkpoint")
	quit(0)
