# The checkpoint's odd jobs and its weather (yard_life.gd): the sweeper at his broom, the smoker (a
# drag, a puff), the one pulling a pallet truck; then rain (they run for a roof and wait under it) and
# a sandstorm (leaning in, an arm over the visor). Needs a window.
# Run: tests/run.sh 120 --path . -s tests/yard_jobs_shots.gd -- <dir>
extends SceneTree

var main
var out := ""
var cam: Camera3D


func _initialize() -> void:
	_run()


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func wait(secs: float) -> void:
	var a := Time.get_ticks_msec()
	while Time.get_ticks_msec() - a < secs * 1000.0:
		await process_frame


func front(n: Node3D, dist := 3.2, h := 1.5, side := 1.2) -> void:
	cam.look_at_from_position(n.global_position - n.global_basis.z * dist + n.global_basis.x * side + Vector3(0, h, 0), n.global_position + Vector3(0, 0.9, 0))


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	Engine.set_meta("cp_weather", "CLEAR")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await wait(10.0)
	main.hud.visible = false
	main.player.global_position = Vector3(0, 0.1, 96)
	var yl: Node = main.level.find_child("YardLife", true, false)
	cam = Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 45.0
	for i in [13, 15]:
		var w: Dictionary = yl._people[i]
		print(w.special, " at ", w.node.position)
		for k in 3:
			front(w.node, 1.4, 1.4, 3.2)   # (from the side)
			await wait(0.35)
		await snap("job_" + w.special)
	var s: Dictionary = yl._people[14]
	front(s.node, 2.2, 1.6, 0.5)
	await snap("job_smoke")
	yl._start_act(s, "drag")
	await wait(1.0)
	front(s.node, 2.2, 1.6, 0.5)
	await snap("job_smoke_drag")
	await wait(2.0)
	await snap("job_smoke_puff")
	Engine.set_meta("cp_weather", "RAIN")
	await wait(1.0)
	var runner: Dictionary = yl._people[15]
	var heading := 0
	for w in yl._people:
		if w.cover != Vector3.INF:
			heading += 1
	print("rain: %d of %d heading for cover" % [heading, yl._people.size()])
	front(runner.node, 4.0, 1.8, 2.0)
	await snap("rain_run")
	await wait(9.0)
	var under := 0
	for w in yl._people:
		if w.cover != Vector3.INF and w.node.position.distance_to(w.cover) < 0.6:
			under += 1
	print("rain: %d under cover" % under)
	front(runner.node, 4.0, 1.8, 2.0)
	await wait(0.3)
	await snap("rain_sheltered")
	Engine.set_meta("cp_weather", "SANDSTORM")
	await wait(10.0)   # (back out to work)
	var walker: Dictionary = yl._people[0]
	walker.greeted = 1e9   # (no waving at the camera)
	for k in 3:
		front(walker.node, 3.5, 1.6, 2.5)
		await wait(0.3)
	await snap("sand_walk")
	print("yard_jobs_shots: done")
	quit()
