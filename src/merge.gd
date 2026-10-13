# Mesh merging: everything is built from hundreds of small primitives, which costs one draw call
# each. bake() folds the static ones under a node into one mesh per material per chunk of space
# (so culling still works), and frees the originals. Collision bodies are kept.
# Left alone: anything with a script (doors, pickups, monsters, interactables...), anything marked
# live() (animated: spinning, swaying, blinking), and hidden meshes.
extends RefCounted


## Mark a node (and its subtree) as animated so bake() leaves it alone.
static func live(n: Node) -> void:
	n.set_meta("live", true)


static var _arrays := {}   # primitive params -> mesh arrays (CPU-generated, so no GPU readback)
static var _lock := Mutex.new()   # (merges run on worker threads: two can be at it at once)
const FAR := 140.0            # no merged chunk is drawn further off than this


## indoors: floors and ceilings (wide, flat slabs) cast no shadows. Under a roof of lamps they only
## ever shadow the void behind them, and each one costs every shadowed lamp near it two passes.
## far: how far off a chunk still draws (the checkpoint's basin is wider than a station's view).
static func bake(root: Node3D, chunk := 12.0, indoors := false, far := FAR, mark := Callable()) -> void:
	if Engine.has_meta("no_merge"):   # debugging: keep every primitive as its own node
		return
	var groups := {}    # "cx,cy,cz|shadow" -> {mat_id: [Buf, Material]}
	var victims: Array[MeshInstance3D] = []
	_lock.lock()
	if _arrays.size() > 6000:
		_arrays.clear()   # random prop sizes make most shapes one-offs; don't keep them forever
	_lock.unlock()
	var items := []   # [mesh instance, its transform under root]
	_gather(root, Transform3D.IDENTITY, items)
	# `mark`, when given, is awaited every so often: the caller spreads the work over frames (level.gd,
	# line.gd). Nothing here is random, so where it pauses changes nothing.
	if mark.is_valid():
		# The arithmetic (every vertex of every piece moved into place) on a worker thread while the
		# game runs on; only primitives (CPU-made arrays): anything else is read here, after.
		var prim := items.filter(func(it): return it[0].mesh is PrimitiveMesh)
		for k in prim.size():   # (made here, before the thread reads it: a slice at a time, it's thousands)
			prim[k][0].mesh.get_aabb()
			if k % 150 == 149:
				await mark.call("")
		var task := WorkerThreadPool.add_task(_take_all.bind(prim, chunk, groups, victims, indoors))
		var tree := Engine.get_main_loop() as SceneTree
		while not WorkerThreadPool.is_task_completed(task):
			await tree.process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		var k2 := 0
		for it in items:
			if not it[0].mesh is PrimitiveMesh:
				_take(it[0], it[1], chunk, groups, victims, indoors)
				k2 += 1
				if k2 % 40 == 39:
					await mark.call("")
	else:
		_take_all(items, chunk, groups, victims, indoors)
	var built := []
	for key in groups:
		if mark.is_valid():
			await mark.call("")
		var am := ArrayMesh.new()
		var g: Dictionary = groups[key]
		for mid in g:
			var b: Buf = g[mid][0]
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = b.v
			arr[Mesh.ARRAY_NORMAL] = b.n
			arr[Mesh.ARRAY_TEX_UV] = b.uv
			arr[Mesh.ARRAY_COLOR] = b.c
			var mat: Material = g[mid][1]
			if mid is String:
				arr[Mesh.ARRAY_TEX_UV2] = b.uv2
				mat = load("res://src/art.gd").array_material(mid == "arr1")
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			am.surface_set_material(am.get_surface_count() - 1, mat)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.cast_shadow = int(key.get_slice("|", 1))
		var ext := am.get_aabb().size
		if maxf(ext.x, ext.z) < far * 0.5:   # (a huge piece, the ground or a long run of rail, is measured
			mi.visibility_range_end = far    #  from its middle: culled like this it vanishes under your feet)
		built.append(mi)
	if not is_instance_valid(root):
		return
	for mi in built:   # (all at once, as the originals go: never doubled up, never missing)
		root.add_child(mi)
	for v in victims:   # (the originals are hidden at once, freed a batch at a time)
		if is_instance_valid(v):
			v.visible = false
	for k in victims.size():
		if mark.is_valid() and k % 300 == 299:
			await mark.call("")
		var v := victims[k]
		if not is_instance_valid(v):
			continue
		if v.get_child_count() == 0:
			v.get_parent().remove_child(v)
			v.free()
		else:
			v.mesh = null
			v.visible = true


## Every mesh under n that can be merged, with its transform relative to the root.
static func _gather(n: Node, t: Transform3D, items: Array) -> void:
	for c in n.get_children():
		if not c is Node3D or c.get_script() != null or c.has_meta("live") or not c.visible:
			continue
		if c is RigidBody3D or c is CharacterBody3D or c is Area3D:
			continue
		var ct: Transform3D = t * c.transform
		if c is MeshInstance3D and c.mesh != null and c.material_overlay == null:
			items.append([c, ct])
		_gather(c, ct, items)


static func _take_all(items: Array, chunk: float, groups: Dictionary, victims: Array[MeshInstance3D], indoors: bool) -> void:
	for it in items:
		_take(it[0], it[1], chunk, groups, victims, indoors)


static func _take(mi: MeshInstance3D, ct: Transform3D, chunk: float, groups: Dictionary, victims: Array[MeshInstance3D], indoors: bool) -> void:
	var centre := ct * mi.mesh.get_aabb().get_center()
	var cell := ((centre + Vector3.ONE * chunk / 2.0) / chunk).floor()   # rooms sit centred on multiples of 12
	var shadow: int = mi.cast_shadow
	var ext := ct.basis.get_scale() * mi.mesh.get_aabb().size
	var longest := maxf(ext.x, maxf(ext.y, ext.z))
	if longest < 0.3:
		shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # clutter: shadows cost more than they show
	if indoors and ext.y < 0.4 and ext.x > 1.5 and ext.z > 1.5:
		shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # a floor or ceiling slab
	var key := "%d,%d,%d|%d" % [cell.x, cell.y, cell.z, shadow]
	if not groups.has(key):
		groups[key] = {}
	for s in mi.mesh.get_surface_count():
		var mat: Material = mi.material_override
		if mat == null:
			mat = mi.get_surface_override_material(s)
		if mat == null:
			mat = mi.mesh.surface_get_material(s)
		var tint := Color.WHITE
		var layer := Vector2(-1.0, 0.0)
		var mid: Variant = mat.get_instance_id() if mat else 0
		if mat != null and mat.has_meta("arr"):   # art.gd's textures: all in one surface (see array_material)
			var arr: Vector3 = mat.get_meta("arr")
			tint = mat.get_meta("vc_tint")
			layer = Vector2(arr.x, arr.y)
			mid = "arr%d" % int(arr.z)
			mat = null
		if not groups[key].has(mid):
			groups[key][mid] = [Buf.new(), mat]
		groups[key][mid][0].add(_mesh_arrays(mi.mesh, s), ct, tint, layer)
	victims.append(mi)


## Flat (non-indexed) [verts, normals, uvs] for a surface, without touching the GPU: primitives
## regenerate theirs on the CPU, cached by shape, so merging is just whole-array transforms.
static func _mesh_arrays(m: Mesh, s: int) -> Array:
	var k = _shape_key(m)
	_lock.lock()
	var hit = _arrays.get(k)
	_lock.unlock()
	if hit != null:
		return hit
	var st := SurfaceTool.new()
	st.create_from_arrays((m as PrimitiveMesh).get_mesh_arrays() if m is PrimitiveMesh else m.surface_get_arrays(s))
	st.deindex()
	var a := st.commit_to_arrays()
	var uv = a[Mesh.ARRAY_TEX_UV]
	if uv == null:
		uv = PackedVector2Array()
		uv.resize((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	var out := [a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_NORMAL], uv]
	_lock.lock()
	_arrays[k] = out
	_lock.unlock()
	return out


static func _shape_key(m: Mesh) -> Variant:
	if m is BoxMesh:
		return ["B", m.size]
	if m is CylinderMesh:
		return ["C", m.top_radius, m.bottom_radius, m.height, m.radial_segments, m.rings]
	if m is SphereMesh:
		return ["S", m.radius, m.height, m.radial_segments, m.rings, m.is_hemisphere]
	if m is TorusMesh:
		return ["T", m.inner_radius, m.outer_radius, m.rings, m.ring_segments]
	if m is CapsuleMesh:
		return ["K", m.radius, m.height, m.radial_segments, m.rings]
	if m is PrismMesh:
		return ["P", m.size, m.left_to_right]
	if m is QuadMesh or m is PlaneMesh:
		return ["Q", m.get_class(), m.size]
	return m.get_instance_id()   # ponytail: anything else is read once from the GPU


## Growing vertex buffers for one merged surface.
class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var uv2 := PackedVector2Array()

	func add(a: Array, xf: Transform3D, tint := Color.WHITE, layer := Vector2(-1.0, 0.0)) -> void:
		var verts: PackedVector3Array = a[0]
		v.append_array(xf * verts)
		n.append_array(Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO) * (a[1] as PackedVector3Array))
		uv.append_array(a[2])
		var cols := PackedColorArray()
		cols.resize(verts.size())
		cols.fill(tint)
		c.append_array(cols)
		if layer.x >= 0.0:
			var l2 := PackedVector2Array()
			l2.resize(verts.size())
			l2.fill(layer)
			uv2.append_array(l2)
