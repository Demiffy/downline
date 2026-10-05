# Mesh merging: everything is built from hundreds of small primitives, which costs one draw call
# each. bake() folds the static ones under a node into one mesh per material per chunk of space
# (so culling still works), and frees the originals. Collision bodies are kept.
# Left alone: anything with a script (doors, pickups, monsters, interactables...), anything marked
# live() (animated: spinning, swaying, blinking), and hidden meshes.
extends RefCounted


## Mark a node (and its subtree) as animated so bake() leaves it alone.
static func live(n: Node) -> void:
	n.set_meta("live", true)


static func bake(root: Node3D, chunk := 12.0) -> void:
	var groups := {}    # "cx,cy,cz|shadow" -> {mat_id: [SurfaceTool, Material]}
	var victims: Array[MeshInstance3D] = []
	_collect(root, Transform3D.IDENTITY, chunk, groups, victims)
	for key in groups:
		var am := ArrayMesh.new()
		var g: Dictionary = groups[key]
		for mid in g:
			var st: SurfaceTool = g[mid][0]
			st.commit(am)
			am.surface_set_material(am.get_surface_count() - 1, g[mid][1])
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.cast_shadow = int(key.get_slice("|", 1))
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
			var key := "%d,%d,%d|%d" % [cell.x, cell.y, cell.z, mi.cast_shadow]
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
					var st := SurfaceTool.new()
					groups[key][mid] = [st, mat]
				groups[key][mid][0].append_from(mi.mesh, s, ct)
			victims.append(mi)
		_collect(c, ct, chunk, groups, victims)
