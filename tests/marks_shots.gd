# Hit marks (marks.gd): a shotgun blast at a wall and three crowbar swings at it, in the playground,
# then the wall close up. Needs a window. Run: tests/run.sh 200 --path . -s tests/marks_shots.gd -- <dir> playground
extends SceneTree

var main
var pg
var out := ""


func _initialize() -> void:
	_run()


func snap(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	while pg == null:
		for c in main.get_children():
			if c.get_script() != null and c.get_script().resource_path.ends_with("playground.gd"):
				pg = c
		await process_frame
	while not pg._ready_done:
		await process_frame
	pg.strip.visible = false
	var p = main.player
	await create_timer(1.0).timeout
	# Face the nearest wall, 2 m off it.
	var space = p.get_world_3d().direct_space_state
	var best := {}
	for k in 16:
		var dir := Vector3(sin(TAU * k / 16.0), 0, cos(TAU * k / 16.0))
		var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0, 1.5, 0), p.global_position + Vector3(0, 1.5, 0) + dir * 12.0, 1)
		var h: Dictionary = space.intersect_ray(q)
		if not h.is_empty() and (best.is_empty() or h.position.distance_to(p.global_position) < best.position.distance_to(p.global_position)) and h.position.distance_to(p.global_position) > 2.5:
			best = h
	var n: Vector3 = best.normal
	p.global_position = Vector3(best.position.x, p.global_position.y, best.position.z) + n * 2.2
	p.rotation.y = atan2(n.x, n.z)
	p.head.rotation.x = 0.0
	p.light_on = true
	await create_timer(0.5).timeout
	p._shoot(load("res://src/data.gd").ITEMS["SHOTGUN"])
	for k in 3:
		var from: Vector3 = p.cam.global_position
		var q2 := PhysicsRayQueryParameters3D.create(from, from - p.cam.global_transform.basis.z * 3.0 + Vector3(0, -0.4 + k * 0.4, 0), 1)
		var h2: Dictionary = space.intersect_ray(q2)
		if not h2.is_empty():
			main.mark(h2.position, h2.normal, "gouge", p.cb_right())
	await create_timer(0.1).timeout
	await snap("marks_hit")
	await create_timer(1.0).timeout
	await snap("marks_wall")
	quit()
