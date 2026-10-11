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
static var _indoors := false
const FAR := 140.0            # no merged chunk is drawn further off than this


## indoors: floors and ceilings (wide, flat slabs) cast no shadows. Under a roof of lamps they only
## ever shadow the void behind them, and each one costs every shadowed lamp near it two passes.
static func bake(root: Node3D, chunk := 12.0, indoors := false) -> void:
	if Engine.has_meta("no_merge"):   # debugging: keep every primitive as its own node
		return
	var groups := {}    # "cx,cy,cz|shadow" -> {mat_id: [Buf, Material]}
	var victims: Array[MeshInstance3D] = []
	if _arrays.size() > 6000:
		_arrays.clear()   # random prop sizes make most shapes one-offs; don't keep them forever
	_indoors = indoors
	_collect(root, Transform3D.IDENTITY, chunk, groups, victims)
	for key in groups:
		var am := ArrayMesh.new()
		var g: Dictionary = groups[key]
		for mid in g:
			var b: Buf = g[mid][0]
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = b.v
			arr[Mesh.ARRAY_NORMAL] = b.n
			arr[Mesh.ARRAY_TEX_UV] = b.uv
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			am.surface_set_material(am.get_surface_count() - 1, g[mid][1])
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.cast_shadow = int(key.get_slice("|", 1))
		var ext := am.get_aabb().size
		if maxf(ext.x, ext.z) < FAR * 0.5:   # (a huge piece, the ground or a long run of rail, is measured
			mi.visibility_range_end = FAR    #  from its middle: culled like this it vanishes under your feet)
		root.add_child(mi)
	for v in victims:
		if v.get_child_count() == 0:
			v.get_parent().remove_child(v)
			v.free()
		else:
			v.mesh = null


static func _collect(n: Node, t: Transform3D, chunk: float, groups: Dictionary, victims: Array[MeshInstance3D]) -> void:
	for c in n.get_children():
		if not c is Node3D or c.get_script() != null or c.has_meta("live") or not c.visible:
			continue
		if c is RigidBody3D or c is CharacterBody3D or c is Area3D:
			continue
		var ct: Transform3D = t * c.transform
		if c is MeshInstance3D and c.mesh != null and c.material_overlay == null:
			var mi: MeshInstance3D = c
			var centre := ct * mi.mesh.get_aabb().get_center()
			var cell := ((centre + Vector3.ONE * chunk / 2.0) / chunk).floor()   # rooms sit centred on multiples of 12
			var shadow: int = mi.cast_shadow
			var ext := ct.basis.get_scale() * mi.mesh.get_aabb().size
			var longest := maxf(ext.x, maxf(ext.y, ext.z))
			if longest < 0.3:
				shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # clutter: shadows cost more than they show
			if _indoors and ext.y < 0.4 and ext.x > 1.5 and ext.z > 1.5:
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
				var mid := mat.get_instance_id() if mat else 0
				if not groups[key].has(mid):
					groups[key][mid] = [Buf.new(), mat]
				groups[key][mid][0].add(_mesh_arrays(mi.mesh, s), ct)
			victims.append(mi)
		_collect(c, ct, chunk, groups, victims)


## Flat (non-indexed) [verts, normals, uvs] for a surface, without touching the GPU: primitives
## regenerate theirs on the CPU, cached by shape, so merging is just whole-array transforms.
static func _mesh_arrays(m: Mesh, s: int) -> Array:
	var k = _shape_key(m)
	if _arrays.has(k):
		return _arrays[k]
	var st := SurfaceTool.new()
	st.create_from_arrays((m as PrimitiveMesh).get_mesh_arrays() if m is PrimitiveMesh else m.surface_get_arrays(s))
	st.deindex()
	var a := st.commit_to_arrays()
	var uv = a[Mesh.ARRAY_TEX_UV]
	if uv == null:
		uv = PackedVector2Array()
		uv.resize((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	_arrays[k] = [a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_NORMAL], uv]
	return _arrays[k]


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

	func add(a: Array, xf: Transform3D) -> void:
		v.append_array(xf * (a[0] as PackedVector3Array))
		n.append_array(Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO) * (a[1] as PackedVector3Array))
		uv.append_array(a[2])
