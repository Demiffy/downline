# Your own suit as other cameras see it (holding what you hold, headlamp lit), a crewmate's lit
# headlamp, and scanner tags over night vision. Needs a window.
extends SceneTree
const Puppet = preload("res://src/puppet.gd")
var main
var out := ""
func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0]
	_run()
func shot(n: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + n + ".png")
	print("saved ", n)
func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30: await process_frame
	for n in main.get_children():
		if n.has_method("_show_title"): n.queue_free()
	var p = main.player
	p.set_physics_process(false)
	p.frozen = true
	main.upgrades["HEADLAMP"] = true
	main.upgrades["NIGHT_VISION"] = true
	p.global_position = Vector3(-6.0, 0.06, 9.0)
	p.slots[0] = {"id": "CROWBAR", "charge": -1.0, "extra": {}}
	p.sel = 0
	p.headlamp_on = true
	await process_frame
	# Our own suit through another camera (as an observer's photo or a camera feed sees it).
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 480)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.cull_mask = 0xFFFFF & ~2
	vp.add_child(cam)
	cam.look_at_from_position(p.global_position + Vector3(1.2, 1.4, -2.4), p.global_position + Vector3(0, 1.0, 0))
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out + "/photo_of_us.png")
	print("saved photo_of_us")
	vp.queue_free()
	# A crewmate with the headlamp on.
	var pup := Puppet.new()
	pup.main = main
	pup.net = main.net
	pup.peer = 55
	pup.display_name = "CREW"
	main.add_child(pup)
	pup.set_pose(["W", Vector3(-6.0, 0.06, 12.0), 0.0, 0.0, 1.8, "FLASHLIGHT", false, false, false, false, main.level_serial, true, true])
	p.headlamp_on = false
	p.rotation.y = PI
	for i in 20: await process_frame
	await shot("crew_headlamp")
	# Scanner over night vision.
	p.equip = {"id": "SCANNER", "charge": 100.0, "extra": {}}
	for id in ["WRENCH", "TOY_TRUCK", "GEAR"]:
		main.spawn_item(id, p.global_position + Vector3(randf_range(-1.5, 1.5), 1.0, 4.0 + randf_range(0, 2)))
	p.nv_on = true
	for i in 30: await process_frame
	p._scan_cd = 0.0
	p._scan()
	await create_timer(1.2).timeout
	await shot("scan_over_nv")
	quit(0)
