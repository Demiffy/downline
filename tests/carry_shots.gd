# What you and your crewmates hold, as seen: the lantern in your hand beside one on the floor, a body
# over your shoulder, and a crewmate (puppet) with a lantern, a body, a heavy item and their head
# turned. Needs a window. Run: tests/run.sh 200 --path . -s tests/carry_shots.gd -- <out_dir>
extends SceneTree

const Puppet = preload("res://src/puppet.gd")

var main
var out := "user://carry"


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


func look(pos: Vector3, at: Vector3) -> void:
	var p = main.player
	p.global_position = pos - Vector3(0, 1.6, 0)
	p.velocity = Vector3.ZERO
	var d := at - pos
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func hold(id: String, lit := false) -> void:
	main.player.slots[0] = {"id": id, "charge": 100.0, "extra": {}}
	main.player.sel = 0
	main.player.light_on = lit
	await frames(4)


func pup_pose(pup, pos: Vector3, yaw: float, held: String, lit := false, pitch := 0.0) -> void:
	pup.set_pose(["W", pos, yaw, pitch, 1.8, held, lit, false, false, false, main.level_serial, true])


func _run() -> void:
	Engine.set_meta("fast_test", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(30)
	for n in main.get_children():
		if n.has_method("_show_title"):
			n.queue_free()   # (the title screen)
	main.player.set_physics_process(false)
	main.player.frozen = true
	main.hud.visible = false
	# 1. Lantern in hand, lit, with the same lantern on the floor in front.
	main.spawn_item("LANTERN", Vector3(-1.2, 1.1, 0.6), -1.0, main.train)
	look(Vector3(-2.6, 2.6, 0.2), Vector3(-1.2, 1.15, 0.6))
	await hold("LANTERN", true)
	await shot("fp_lantern")
	await hold("FLASHLIGHT", true)
	await shot("fp_flashlight")
	# 2. A body over your shoulder.
	await hold("REMAINS")
	look(Vector3(-2.6, 2.6, 0.2), Vector3(2.0, 2.4, 0.2))
	await shot("fp_remains")
	look(Vector3(-2.6, 2.6, 0.2), Vector3(2.0, 1.4, 0.2))
	await shot("fp_remains_down")
	await hold("ENGINE_BLOCK")
	await shot("fp_heavy")
	main.player.slots[0] = null
	await frames(4)
	# 3. Crewmates: out on the checkpoint yard in daylight.
	var poses := [["LANTERN", true, 0.0], ["REMAINS", false, 0.0], ["ENGINE_BLOCK", false, 0.0], ["FLASHLIGHT", true, 0.0], ["SHOTGUN", false, 0.0]]
	var pups := []
	for i in poses.size():
		var pup := Puppet.new()
		pup.main = main
		pup.net = main.net
		pup.peer = 50 + i
		pup.display_name = "CREW %d" % i
		main.add_child(pup)
		pups.append(pup)
		pup_pose(pup, Vector3(-7.0 + i * 2.0, 0.06, 9.8), 0.0, poses[i][0], poses[i][1])
	await frames(30)
	look(Vector3(-3.0, 2.4, 4.6), Vector3(-3.0, 1.0, 9.8))
	await shot("crew_front")
	look(Vector3(2.5, 1.7, 11.0), Vector3(-3.0, 1.0, 9.8))
	await shot("crew_side")
	# Head turned: looking 40 degrees off to the side, then 120 (the body has to follow).
	for p in pups:
		pup_pose(p, p._target_pos, 0.7, p._held_id, p.light_on)
	await frames(40)
	look(Vector3(-3.0, 2.4, 4.6), Vector3(-3.0, 1.0, 9.8))
	await shot("crew_glance")
	for p in pups:
		pup_pose(p, p._target_pos, 2.1, p._held_id, p.light_on)
	await frames(60)
	await shot("crew_turned")
	quit(0)
