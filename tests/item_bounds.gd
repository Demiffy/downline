# Every item model's visual bounds against its Data size (the physics box): off-centre or oversized
# models look wrong in hand and float or sink on the floor. Prints the ones that are off.
# Run: tests/run.sh 120 --headless --path . -s tests/item_bounds.gd
extends SceneTree

const Data = preload("res://src/data.gd")
const Items = preload("res://src/items.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var bad := 0
	for id in Data.ITEMS:
		var m: Node3D = Items.build(id)
		root.add_child(m)
		var box := AABB()
		var first := true
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			var b: AABB = _rel(m, mi) * mi.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var size: Vector3 = Data.ITEMS[id].size
		var c := box.get_center()
		var off := c.length()
		var over := (box.size - size)
		var worst := maxf(over.x, maxf(over.y, over.z))
		if off > 0.02 or worst > 0.06 or (box.size - size).abs().x > 0.15 or (box.size - size).abs().z > 0.15:
			bad += 1
			print("%-20s centre %s  model %s  data %s" % [id, c.snapped(Vector3.ONE * 0.005), box.size.snapped(Vector3.ONE * 0.005), size])
		m.free()
	print("item_bounds: %d off" % bad)
	quit(0)


func _rel(root_n: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != root_n:
		t = (c as Node3D).transform * t
		c = c.get_parent()
	return t
