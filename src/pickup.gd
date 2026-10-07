# A physical item lying in the world: scrap, tools, equipment.
extends RigidBody3D

const Data = preload("res://src/data.gd")
const Items = preload("res://src/items.gd")
const Sfx = preload("res://src/sfx.gd")

var id := ""
var charge := -1.0  # battery seconds for tools, -1 for everything else
var extra := {}     # per-item data that travels with it (a photo's picture)
var _age := 0.0       # quiet while it settles after spawning
var _last_hit := 0.0
var _impact := "thunk"
var _impact_pitch := 1.0


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
	# What it sounds like when it hits something: metal clanks, the rest thunks.
	var res: Dictionary = d.get("res", {})
	var metal: int = res.get("steel", 0) + res.get("copper", 0)
	var soft: int = res.get("rubber", 0) + res.get("plastic", 0)
	_impact = "clank" if metal > soft else "thunk"
	_impact_pitch = clampf(1.6 - mass * 0.08, 0.55, 1.5) * (1.3 if res.get("plastic", 0) > res.get("rubber", 0) else 1.0)
	if id == "REMAINS":   # the scanner and site map point you to them
		add_to_group("scan_targets")
		set_meta("scan_name", "YOUR REMAINS")
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_hit)


## Per-item data (keeps it when picked up and dropped again). A photo shows its picture.
func set_extra(e: Dictionary) -> void:
	extra = e
	show_picture(self, e)


## Put the picture in `e` on the photo model under `root` (world pickup or the one in your hand).
static func show_picture(root: Node, e: Dictionary) -> void:
	var pic := root.find_child("Pic", true, false) as MeshInstance3D
	if pic == null or not e.has("tex"):
		return
	var m := (pic.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.albedo_color = Color.WHITE
	m.albedo_texture = e.tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pic.material_override = m


func _physics_process(delta: float) -> void:
	_age += delta
	_last_hit -= delta


func _on_hit(_body: Node) -> void:
	var v := linear_velocity.length()
	if _age < 2.0 or _last_hit > 0.0 or v < 1.6 or freeze:
		return
	_last_hit = 0.15
	Sfx.play(self, _impact, global_position, clampf(-16.0 + v * 2.5, -16.0, 2.0), _impact_pitch * randf_range(0.92, 1.08))
	var main = get_tree().current_scene
	if main and main.has_method("noise") and v > 3.0:
		main.noise(global_position, minf(4.0 + v * 1.5 + mass * 0.4, 18.0))   # dropped junk carries
