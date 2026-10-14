# The C++ merge (MeshMerge, native/) makes exactly the meshes merge.gd's GDScript makes: the same stops
# built with each (Engine meta "gd_merge" forces the GDScript), every merged mesh compared, and timed
# (a stop built whole, and without merging at all, so the merge's own share shows).
# And pieces (art.gd's s-primitives merged with no node, Merge.open): a stop built with them is the same
# as one built with every node (Engine meta "gd_geom"): the merged meshes to the bit, and every node
# left over (colliders, lights, what the merge leaves alone) the same, in the same place in the tree.
# Run: godot --headless --path . -s tests/merge_native.gd   (env PART=stops|line|sliced: one part; STOPS=n: the first n)
extends SceneTree

const Level = preload("res://src/level.gd")
const Merge = preload("res://src/merge.gd")
const Buf = Merge.Buf

var fails := 0
var unnamed := RegEx.create_from_string("@[0-9]+")   # (unnamed nodes' numbers differ build to build)
var main


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	_run()


## Builds the stop (on its own Level, as main._load_level does) and returns what came out of it:
## [usec, [[node path, cast shadow, visibility end, [[arrays, material], ...]], ...]], the level freed.
func build(stop: Dictionary, seed_: int, mode: String, sliced := false) -> Array:
	for m in ["gd_merge", "no_merge", "gd_geom"]:
		if Engine.has_meta(m):
			Engine.remove_meta(m)
	if mode != "native":
		Engine.set_meta(mode, true)
	var made := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	Merge.stats = {"pieces": 0, "victims": 0}
	seed(seed_)
	var lv = Level.new()
	lv.main = main
	lv.name = "LevelTest"
	lv.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(lv)
	var t := Time.get_ticks_usec()
	await lv.build_geometry(stop, 1, seed_, sliced)
	t = Time.get_ticks_usec() - t
	var stats := [Merge.stats.pieces, Merge.stats.victims, Performance.get_monitor(Performance.OBJECT_NODE_COUNT) - made]
	var out := []
	var rest := []   # every other node: [path, what it is]
	var todo: Array = [lv]
	while not todo.is_empty():
		var n: Node = todo.pop_front()
		todo.append_array(n.get_children())
		if n is MeshInstance3D and n.mesh is ArrayMesh:
			var surfs := []
			for s in n.mesh.get_surface_count():
				surfs.append([n.mesh.surface_get_arrays(s), n.mesh.surface_get_material(s)])
			out.append([unnamed.sub(str(lv.get_path_to(n.get_parent())), "@", true), n.cast_shadow, n.visibility_range_end, surfs])
		elif n != lv:
			rest.append([unnamed.sub(str(lv.get_path_to(n)), "@", true), describe(n)])
	lv.free()
	for m in ["gd_merge", "no_merge", "gd_geom"]:
		if Engine.has_meta(m):
			Engine.remove_meta(m)
	return [t, out, rest, stats]


## The line round a stop (line.gd's chunks, laid all at once as line.settle does when a run starts), like
## build(): [usec of the line alone, merged meshes, other nodes, stats].
func build_line(stop: Dictionary, seed_: int, mode: String) -> Array:
	for m in ["gd_merge", "no_merge", "gd_geom"]:
		if Engine.has_meta(m):
			Engine.remove_meta(m)
	if mode != "native":
		Engine.set_meta(mode, true)
	seed(seed_)
	var lv = Level.new()
	lv.main = main
	lv.name = "LevelTest"
	lv.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(lv)
	await lv.build_geometry(stop, 1, seed_, false)
	main.level_seed = seed_
	Merge.stats = {"pieces": 0, "victims": 0}
	var made := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var t := Time.get_ticks_usec()
	main.line.settle(lv)
	t = Time.get_ticks_usec() - t
	var stats := [Merge.stats.pieces, Merge.stats.victims, Performance.get_monitor(Performance.OBJECT_NODE_COUNT) - made]
	var out := []
	var rest := []
	var line: Node = main.line
	var todo: Array = line.get_children().filter(func(c): return str(c.name).begins_with("Line"))
	while not todo.is_empty():
		var n: Node = todo.pop_front()
		todo.append_array(n.get_children())
		if n is MeshInstance3D and n.mesh is ArrayMesh:
			var surfs := []
			for s in n.mesh.get_surface_count():
				surfs.append([n.mesh.surface_get_arrays(s), n.mesh.surface_get_material(s)])
			out.append([unnamed.sub(str(line.get_path_to(n.get_parent())), "@", true), n.cast_shadow, n.visibility_range_end, surfs])
		else:
			rest.append([unnamed.sub(str(line.get_path_to(n)), "@", true), describe(n)])
	for c in line.get_children():
		if str(c.name).begins_with("Line"):
			line.remove_child(c)
			c.free()
	line._chunks.clear()
	lv.free()
	for m in ["gd_merge", "no_merge", "gd_geom"]:
		if Engine.has_meta(m):
			Engine.remove_meta(m)
	return [t, out, rest, stats]


## What a node is, enough to tell two builds' apart: its class, transform, visibility, mesh (by shape) and
## material, collision shape, layers.
func describe(n: Node) -> Array:
	var d: Array = [n.get_class(), n.get_script()]
	if n is Node3D:
		d.append_array([n.transform, n.visible, n.has_meta("live")])
	if n is GeometryInstance3D:
		d.append_array([n.cast_shadow, n.layers, n.visibility_range_end, n.material_override])
	if n is MeshInstance3D:
		d.append(Merge._shape_key(n.mesh) if n.mesh is PrimitiveMesh else n.mesh)
	if n is CollisionShape3D and n.shape != null:
		d.append_array([n.shape.get_class(), n.shape.get("size"), n.shape.get("radius"), n.shape.get("height")])
	if n is CollisionObject3D:
		d.append_array([n.collision_layer, n.collision_mask])
	return d


## Where two builds' other nodes differ ("": nowhere).
func rest_diff(a: Array, b: Array) -> String:
	if a.size() != b.size():
		var ca := {}
		for x in a:
			ca[x[0] + " " + str(x[1].slice(0, 1)) + str(x[1].slice(-1))] = ca.get(x[0] + " " + str(x[1].slice(0, 1)) + str(x[1].slice(-1)), 0) + 1
		for x in b:
			var k: String = x[0] + " " + str(x[1].slice(0, 1)) + str(x[1].slice(-1))
			ca[k] = ca.get(k, 0) - 1
		var shown := 0
		for k in ca:
			if ca[k] != 0 and shown < 12:
				print("      ", ca[k], " ", k)
				shown += 1
		return "%d other nodes vs %d" % [a.size(), b.size()]
	for i in a.size():
		if a[i][0] != b[i][0]:
			return "node %d: %s vs %s" % [i, a[i][0], b[i][0]]
		var x: Array = a[i][1]
		var y: Array = b[i][1]
		if x.size() != y.size():
			return "node %d %s: %s vs %s" % [i, a[i][0], x, y]
		for k in x.size():
			if x[k] is Object or y[k] is Object:
				if not mat_same(x[k], y[k]):
					return "node %d %s: %s vs %s" % [i, a[i][0], x[k], y[k]]
			elif typeof(x[k]) != typeof(y[k]) or x[k] != y[k]:
				return "node %d %s: %s vs %s" % [i, a[i][0], x[k], y[k]]
	return ""


## [largest difference between two builds' meshes (0.0: identical), why they don't line up ("": they do)].
func diff(a: Array, b: Array) -> Array:
	if a.size() != b.size():
		return [-1.0, "%d meshes vs %d" % [a.size(), b.size()]]
	var worst := 0.0
	var where := ""
	for i in a.size():
		for f in 3:
			if a[i][f] != b[i][f]:
				return [-1.0, "mesh %d: %s vs %s" % [i, a[i][f], b[i][f]]]
		if a[i][3].size() != b[i][3].size():
			return [-1.0, "mesh %d: %d surfaces vs %d" % [i, a[i][3].size(), b[i][3].size()]]
		for s in a[i][3].size():
			var sa: Array = a[i][3][s]
			var sb: Array = b[i][3][s]
			if not mat_same(sa[1], sb[1]):
				return [-1.0, "mesh %d under %s surface %d: material %s vs %s" % [i, a[i][0], s, sa[1], sb[1]]]
			var w := arrays_diff(sa[0], sb[0])
			if w < 0.0:
				return [-1.0, "mesh %d surface %d: arrays differ in size or kind" % [i, s]]
			if w > worst:
				where = "(worst: mesh %d under %s, surface %d)" % [i, a[i][0], s]
			worst = maxf(worst, w)
	return [worst, where if worst > 0.0 else ""]


## Two materials alike: the same one, or (a fresh one each build) the same class and stored values,
## resources among them compared the same way.
func mat_same(a: Object, b: Object, depth := 3) -> bool:
	if a == b:
		return true
	if a == null or b == null or a.get_class() != b.get_class() or a.get_script() != b.get_script() or depth == 0:
		return false
	for p in a.get_property_list():
		if not p.usage & PROPERTY_USAGE_STORAGE or p.name.begins_with("resource_"):
			continue
		var x = a.get(p.name)
		var y = b.get(p.name)
		if x is Object or y is Object:
			if not mat_same(x, y, depth - 1):
				return false
		elif typeof(x) != typeof(y) or x != y:
			return false
	return true


## Largest difference between two lists of packed arrays (null entries allowed), -1.0 if they don't line up.
func arrays_diff(xa: Array, ya: Array) -> float:
	if xa.size() != ya.size():
		return -1.0
	var worst := 0.0
	for k in xa.size():
		var x = xa[k]
		var y = ya[k]
		if typeof(x) != typeof(y) or (x != null and x.size() != y.size()):
			return -1.0
		if x == null or x == y:
			continue
		for q in x.size():
			var d = x[q] - y[q]
			if d is Vector3 or d is Vector2:
				d = d.abs()[d.abs().max_axis_index()]
			elif d is Color:
				d = maxf(maxf(absf(d.r), absf(d.g)), maxf(absf(d.b), absf(d.a)))
			worst = maxf(worst, absf(d))
	return worst


func verts(a: Array) -> int:
	var n := 0
	for mi in a:
		for s in mi[3]:
			n += (s[0][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return n


func same(name_: String, a: Array, b: Array) -> void:
	var d := diff(a[1], b[1])
	check(d[0] == 0.0, "%s: %d meshes, %d vertices, max difference %s %s" % [name_, b[1].size(), verts(b[1]), d[0], d[1]])


## gather + take alone, on a stop built unmerged: [usec, groups as [key, mid, [v, n, uv, c, uv2], material]].
func take_only(lv: Node3D, native: bool) -> Array:
	var t := Time.get_ticks_usec()
	var groups := {}
	var victims: Array[MeshInstance3D] = []
	var items := []
	if native:
		items = ClassDB.class_call_static(&"MeshMerge", &"gather", lv)
	else:
		Merge._gather(lv, Transform3D.IDENTITY, items)
	Merge._take_all(items, 16.0, groups, victims, false, native)
	t = Time.get_ticks_usec() - t
	var out := []
	for key in groups:
		for mid in groups[key]:
			var e: Array = groups[key][mid]
			var b: Array = [e[0].v, e[0].n, e[0].uv, e[0].c, e[0].uv2] if e[0] is Buf else e.slice(0, 5)
			out.append([key, mid, b, e[-1]])
	return [t, out, victims.size()]


func _run() -> void:
	check(ClassDB.class_exists("MeshMerge"), "the C++ MeshMerge is loaded (bin/downline.gdextension)")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var stops: Array = [{"theme": "CHECKPOINT", "letter": "CHECKPOINT"}]
	for i in 4:
		stops.append(main._gen_stop())
	if OS.get_environment("STOPS") != "":   # (a quicker run: the first n)
		stops = stops.slice(0, int(OS.get_environment("STOPS")))
	main.process_mode = Node.PROCESS_MODE_DISABLED   # (the title screen stays still between a sliced build's frames)
	for st in (stops if OS.get_environment("PART") in ["", "stops"] else []):   # (warm-up: the art's materials and textures, and both shape caches)
		await build(st, 7, "gd_merge")
		await build(st, 7, "native")
	var part := OS.get_environment("PART")   # ("stops", "line", "sliced": just that part; "": all)
	var tot := [0, 0]
	for st in (stops if part in ["", "stops"] else []):
		var name_: String = "%s %s" % [st.get("theme"), st.get("biome", "")]
		var none: Array = await build(st, 7, "no_merge")
		var gd: Array = await build(st, 7, "gd_merge")
		var geo: Array = await build(st, 7, "gd_geom")
		var nat: Array = await build(st, 7, "native")
		var gd2: Array = await build(st, 7, "gd_merge")
		var geo2: Array = await build(st, 7, "gd_geom")
		var nat2: Array = await build(st, 7, "native")
		same(name_ + ": GDScript twice (control)", gd, gd2)
		same(name_ + ": native merge == GDScript", gd, geo)
		same(name_ + ": pieces == nodes (merged meshes)", geo, nat)
		var rd := rest_diff(geo[2], nat[2])
		check(rd == "", "%s: pieces == nodes (the %d other nodes) %s" % [name_, nat[2].size(), rd])
		print("   %s: %d primitives merged: %d as pieces, %d as nodes (all %d as nodes without pieces)" % [name_, nat[3][0] + nat[3][1], nat[3][0], nat[3][1], geo[3][1]])
		var tg := mini(geo[0], geo2[0])
		var tn := mini(nat[0], nat2[0])
		tot[0] += tg
		tot[1] += tn
		print("   %s: whole build %.0f ms GDScript merge, %.0f ms native merge, %.0f ms native + pieces (%.0f ms saved, %.0f%%); unmerged %.0f ms" % [
			name_, gd[0] / 1000.0, tg / 1000.0, tn / 1000.0, (tg - tn) / 1000.0, 100.0 * (tg - tn) / tg, none[0] / 1000.0])
		# gather + take alone (no ArrayMesh building), on the unmerged stop, each run twice (the 2nd timed).
		Engine.set_meta("no_merge", true)
		seed(7)
		var lv = Level.new()
		lv.main = main
		lv.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(lv)
		await lv.build_geometry(st, 1, 7, false)
		Engine.remove_meta("no_merge")
		take_only(lv, false)
		take_only(lv, true)
		var tgo := take_only(lv, false)
		var tno := take_only(lv, true)
		var same_groups: bool = tgo[2] == tno[2] and tgo[1].size() == tno[1].size()
		var worst := 0.0
		for i in tgo[1].size():
			if not same_groups:
				break
			var x: Array = tgo[1][i]
			var y: Array = tno[1][i]
			var w := arrays_diff(x[2], y[2])
			same_groups = x[0] == y[0] and x[1] == y[1] and x[3] == y[3] and w >= 0.0   # (the same materials here: one build)
			worst = maxf(worst, w)
		check(same_groups and worst == 0.0, "%s: gather+take groups equal (%d pieces, %d buffers, max difference %s)" % [name_, tno[2], tno[1].size(), worst])
		print("   %s: gather+take %.0f ms GDScript, %.0f ms native (x%.1f)" % [name_, tgo[0] / 1000.0, tno[0] / 1000.0, float(tgo[0]) / maxf(tno[0], 1)])
		lv.free()
	if part in ["", "stops"]:
		print("   all %d stops: %.0f ms with nodes, %.0f ms with pieces (%.0f%% less)" % [stops.size(), tot[0] / 1000.0, tot[1] / 1000.0, 100.0 * (tot[0] - tot[1]) / tot[0]])
	# The line round the stops (its chunks are built and merged the same way, a chunk at a time).
	for st3 in (stops.slice(1, 4) if part in ["", "line"] else []):
		await build_line(st3, 5, "gd_geom")   # (warm-up)
		var geol: Array = await build_line(st3, 5, "gd_geom")
		var natl: Array = await build_line(st3, 5, "native")
		same("line by %s %s: pieces == nodes" % [st3.theme, st3.get("biome", "")], geol, natl)
		var rdl := rest_diff(geol[2], natl[2])
		check(rdl == "", "line by %s: pieces == nodes (the %d other nodes) %s" % [st3.theme, natl[2].size(), rdl])
		print("   line by %s %s: %d primitives merged, %d as pieces; laid in %.0f ms with nodes, %.0f ms with pieces" % [
			st3.theme, st3.get("biome", ""), natl[3][0] + natl[3][1], natl[3][0], geol[0] / 1000.0, natl[0] / 1000.0])
	# Sliced (as the game builds on the way): primitives on a worker thread, the rest a batch at a time.
	for st2 in (stops.slice(0, 3) if part in ["", "sliced"] else []):
		await build(st2, 11, "gd_merge", true)   # (warm-up: a texture kind first met mid-build remakes the array material)
		var gds: Array = await build(st2, 11, "gd_merge", true)
		var geos: Array = await build(st2, 11, "gd_geom", true)
		var nats: Array = await build(st2, 11, "native", true)
		# (The checkpoint's yard workers are built call_deferred: on a sliced build that runs between its
		#  frames, where the frames fall, and the items they hold draw on the global RNG then. Not the merge's.)
		for b in [gds, geos, nats]:
			b[1] = b[1].filter(func(m): return not "HeldItem" in m[0])
		same("sliced %s: native merge == GDScript" % st2.theme, gds, geos)
		same("sliced %s: pieces == nodes" % st2.theme, geos, nats)
		var rds := rest_diff(geos[2], nats[2])
		check(rds == "", "sliced %s: pieces == nodes (the %d other nodes) %s" % [st2.theme, nats[2].size(), rds])
	check(ClassDB.class_call_static(&"MeshMerge", &"pending") == 0, "no piece left waiting")
	print("merge_native.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
