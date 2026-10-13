# The checkpoint's lorries and forklifts (yard_life.gd): from above with every path drawn (forward
# green, backing up red); then following one lorry round its delivery (on the road, turning in, the
# three-point turn backing up), and a forklift picking up a pallet and backing out. Needs a window.
# Run: tests/run.sh 300 --path . -s tests/vehicle_shots.gd -- <dir>
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


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await wait(12.0)
	main.hud.visible = false
	main.player.global_position = Vector3(0, 0.1, 75)
	var yl: Node = main.level.find_child("YardLife", true, false)
	cam = Camera3D.new()
	main.add_child(cam)
	cam.current = true
	# From above: the paths.
	var im := ImmediateMesh.new()
	var lines := MeshInstance3D.new()
	lines.mesh = im
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.vertex_color_use_as_albedo = true
	lm.no_depth_test = true
	im.surface_begin(Mesh.PRIMITIVE_LINES, lm)
	for v in yl._vehicles:
		for leg in v.legs:
			var pts: PackedVector3Array = leg.pts
			for i in pts.size() - 1:
				im.surface_set_color(Color(0.2, 1, 0.3) if leg.dir > 0 else Color(1, 0.2, 0.2))
				im.surface_add_vertex(pts[i] + Vector3(0, 0.3, 0))
				im.surface_add_vertex(pts[i + 1] + Vector3(0, 0.3, 0))
	im.surface_end()
	main.add_child(lines)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.rotation = Vector3(-PI / 2, 0, 0)
	for v in [["map", Vector3(0, 150, 70), 120.0], ["east_end", Vector3(52, 150, 98), 22.0], ["ring_east", Vector3(138, 150, 41), 18.0], ["lift_e", Vector3(66, 150, 58), 18.0], ["lift_w", Vector3(-142, 150, 41), 22.0]]:
		cam.size = v[2]
		cam.global_position = v[1]
		await wait(0.4)
		await snap(v[0])
	lines.queue_free()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 55.0
	# Follow the first lorry for a while, from beside and a little behind.
	var tv: Dictionary = yl._vehicles[0]
	var k := 0
	var a := Time.get_ticks_msec()
	while Time.get_ticks_msec() - a < 70000 and k < 16:
		await wait(0.1)
		var n: Node3D = tv.node
		if (Time.get_ticks_msec() - a) % 4000 < 110:
			cam.look_at_from_position(n.global_position + n.global_basis * Vector3(-7.0, 3.5, 6.0), n.global_position + Vector3(0, 1.4, 0))
			await snap("truck_%02d_leg%d_%s" % [k, tv.leg, "back" if tv.legs[tv.leg].dir < 0 else "fwd"])
			k += 1
	# A lorry from the front and from the cab side, close: the driver, the lamps.
	var rv: Dictionary = yl._vehicles[1]
	for side in [["front", Vector3(1.5, 2.4, -9.0)], ["cab", Vector3(-3.2, 2.6, -2.6)]]:
		var n: Node3D = rv.node
		cam.look_at_from_position(n.global_position + n.global_basis * side[1], n.global_position + n.global_basis * Vector3(-0.4, 2.2, -2.6))
		await wait(0.05)
		await snap("lorry_" + side[0])
	# A forklift.
	var fv: Dictionary = yl._vehicles[3]
	k = 0
	a = Time.get_ticks_msec()
	while Time.get_ticks_msec() - a < 70000 and k < 16:
		await wait(0.1)
		var n: Node3D = fv.node
		if (Time.get_ticks_msec() - a) % 4000 < 110:
			cam.look_at_from_position(n.global_position + n.global_basis * Vector3(-4.0, 2.4, -1.0), n.global_position + Vector3(0, 0.8, 0))
			await snap("fork_%02d_leg%d" % [k, fv.leg])
			k += 1
	quit()
