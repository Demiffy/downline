# The checkpoint's people (yard_life.gd): a worker walking, side on, in six moments; the gate's man at
# his desk; the welder; the one on his break; then a worker passing you close (does he look, wave?).
# Needs a window. Run: tests/run.sh 150 --path . -s tests/yard_people_shots.gd -- <dir>
extends SceneTree

var main
var out := ""


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


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await wait(12.0)
	main.hud.visible = false
	var yl: Node = main.level.find_child("YardLife", true, false)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 45.0
	# A walker, followed side on.
	var w: Dictionary = yl._people[0]
	var n: Node3D = w.node
	for k in 6:
		var fwd := -n.global_basis.z
		var side := fwd.cross(Vector3.UP).normalized()
		cam.look_at_from_position(n.global_position + side * 3.6 + Vector3(0, 1.2, 0), n.global_position + Vector3(0, 0.95, 0))
		await snap("walk_%d" % k)
		await wait(0.22)
	for pair in [["guard", 11, 2.6, 1.9], ["welder", 10, 2.4, 2.6], ["break", 12, 2.6, 1.6]]:
		var m: Node3D = yl._people[pair[1]].node
		var front: Vector3 = -m.global_basis.z
		cam.look_at_from_position(m.global_position + front * pair[2] + m.global_basis.x * 0.5 + Vector3(0, pair[3], 0), m.global_position + Vector3(0, 0.9, 0))
		await wait(1.0)
		await snap(pair[0])
	# You, walking past a worker close by: seen from the side, both of you in view.
	var p = main.player
	var wd: Dictionary = yl._people[1]
	var w2: Node3D = wd.node
	wd.greeted = -99.0
	p.global_position = w2.global_position + -w2.global_basis.z * 3.0 + w2.global_basis.x * 0.8
	var k := 0
	for i in 60:
		await wait(0.1)
		if i % 15 == 5 or (wd.anim.emote != "" and k < 4):
			var mid: Vector3 = (p.global_position + w2.global_position) / 2.0
			var side: Vector3 = (w2.global_position - p.global_position).cross(Vector3.UP).normalized()
			cam.look_at_from_position(mid + side * 4.5 + Vector3(0, 1.6, 0), mid + Vector3(0, 1.0, 0))
			await snap("passing_%d" % k)
			k += 1
			if k >= 4:
				break
	quit()
