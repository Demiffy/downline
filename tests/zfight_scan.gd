# Usage: godot --headless --path . -s tests/zfight_scan.gd -- [THEME]
# Finds coplanar, same-facing, overlapping faces between boxes (z-fighting) in a facility region.
extends SceneTree
func _initialize() -> void:
	_run()
func _run() -> void:
	Engine.set_meta("fast_test", true)
	Engine.set_meta("no_merge", true)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10: await process_frame
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "FACTORY"
	stop.rooms = 24
	main.player.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy: await process_frame
	var fac = main.level.facility
	var boxes := []
	for mi: MeshInstance3D in fac.find_children("*", "MeshInstance3D", true, false):
		if not (mi.mesh is BoxMesh) or not mi.is_visible_in_tree():
			continue
		var b: Basis = mi.global_transform.basis.orthonormalized()
		var ok := true
		for v in [b.x, b.y, b.z]:
			if absf(absf(v.x) + absf(v.y) + absf(v.z) - 1.0) > 0.001:
				ok = false
		if not ok:
			continue
		var bb: AABB = fac.global_transform.affine_inverse() * (mi.global_transform * mi.get_aabb())
		boxes.append([bb, mi.material_override, mi])
	print("boxes ", boxes.size())
	var hits := {}
	var n := 0
	for i in boxes.size():
		var a: AABB = boxes[i][0]
		for j in range(i + 1, boxes.size()):
			var c: AABB = boxes[j][0]
			if boxes[i][1] == boxes[j][1]:
				continue
			if not a.grow(0.002).intersects(c):
				continue
			for ax in 3:
				var o1 := (ax + 1) % 3
				var o2 := (ax + 2) % 3
				var ov1 := minf(a.end[o1], c.end[o1]) - maxf(a.position[o1], c.position[o1])
				var ov2 := minf(a.end[o2], c.end[o2]) - maxf(a.position[o2], c.position[o2])
				if ov1 < 0.03 or ov2 < 0.03:
					continue
				for e in ([[a.end[ax], c.end[ax]]] if ax == 1 else [[a.end[ax], c.end[ax]], [a.position[ax], c.position[ax]]]):   # (bottoms rest on floors: unseen)
					if absf(e[0] - e[1]) < 0.0015:
						var key := "%s|%s" % [boxes[i][2].get_parent().name, str(Vector3(snappedf(a.get_center().x, 0.5), snappedf(e[0], 0.01), snappedf(a.get_center().z, 0.5)))]
						var at := a.get_center()
						var cell: Vector2i = Vector2i(roundi(at.x / 12.0), roundi(at.z / 12.0))
						var lbl := "%s/%s ax%d plane %.3f  A %s  B %s  in %s(%s)" % [_mat(boxes[i][1]), _mat(boxes[j][1]), ax, e[0], a.size.snapped(Vector3.ONE * 0.01), c.size.snapped(Vector3.ONE * 0.01), cell, fac.kinds.get(cell, "?")]
						if not hits.has(lbl):
							hits[lbl] = 0
						hits[lbl] += 1
	var keys := hits.keys()
	keys.sort_custom(func(x, y): return hits[x] > hits[y])
	for k in keys.slice(0, 60):
		print(hits[k], "x  ", k)
	print("total ", keys.size())
	quit()

func _mat(m) -> String:
	if m is StandardMaterial3D:
		return "%s%s" % [m.albedo_texture.get_meta("kind", "") if m.albedo_texture else "", m.albedo_color.to_html(false)]
	return "?"
