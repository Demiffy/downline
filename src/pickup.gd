# A physical item lying in the world: scrap, tools, equipment.
extends RigidBody3D

const Data = preload("res://src/data.gd")
const Items = preload("res://src/items.gd")

var id := ""
var charge := -1.0  # battery seconds for tools, -1 for everything else


func setup(item_id: String, c := -1.0) -> void:
	id = item_id
	var d: Dictionary = Data.ITEMS[id]
	charge = c if c >= 0.0 else float(d.get("charge", -1.0))
	add_to_group("pickups")
	add_to_group("movable")
	collision_layer = 2
	collision_mask = 1 | 2
	var size: Vector3 = d.size
	mass = 0.5 + size.x * size.y * size.z * 40.0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	add_child(cs)
	add_child(Items.build(id))
