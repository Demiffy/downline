# The siren's three ways of moving (lurking, creeping, loping) and the husk walking like a crewmate,
# side on, mid-stride. Needs a window.
# Run: tests/run.sh 200 --path . -s tests/siren_shots.gd -- <out_dir>
extends SceneTree

var main
var out := "user://siren"


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
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(20)
	for n in main.get_children():
		if n.has_method("_show_title"):
			n.queue_free()
	main.hud.visible = false
	main.player.set_physics_process(false)
	main.player.frozen = true
	get_root().get_viewport().debug_draw = Viewport.DEBUG_DRAW_UNSHADED   # (flat light: it's the shapes we want to see)
	var at := Vector3(-8.0, 0.06, 8.0)   # out on the checkpoint yard
	var p = main.player
	p.global_position = at + Vector3(4.2, -0.4, 0.0)
	p.rotation.y = PI / 2.0   # looking along -x, at it side on
	p.head.rotation.x = -0.05
	var s = load("res://src/siren.gd").new()
	s.main = main
	s.level = main.level
	main.level.add_child(s)
	s.global_position = at
	s.rotation.y = 0.0   # facing -z: we see its left side
	s.set_physics_process(false)
	for mode in [["lurk_idle", s.LURK, 0.0], ["lurk_walk", s.LURK, 1.6], ["creep", s.STALK, 2.4], ["lope", s.FLEE, 9.0]]:
		s.state = mode[1]
		s.velocity = Vector3(0, 0, -mode[2])
		for i in 70:
			s._t += 1.0 / 60.0
			s._animate(1.0 / 60.0)
			await process_frame
		await shot("siren_" + mode[0])
	s.queue_free()
	var h = load("res://src/husk.gd").new()
	h.main = main
	h.level = main.level
	main.level.add_child(h)
	h.global_position = at
	h.set_physics_process(false)
	h.set_who("TOMAS")
	h.velocity = Vector3(0, 0, -1.6)
	for i in 50:
		h._anim += 1.6 / 60.0
		h._animate(1.0 / 60.0)
		await process_frame
	await shot("husk_walk")
	quit(0)
