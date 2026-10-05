# Lays every item out on the floor of a lit room, 6 per shot, and saves screenshots. Needs a window.
# Run: godot --path . -s tests/scrap_gallery.gd -- <out_dir>
extends SceneTree

const Data = preload("res://src/data.gd")
const Items = preload("res://src/items.gd")

var main
var out := "user://scrap_gallery"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(30)
	main.player.set_physics_process(false)
	main.hud.visible = false
	main.player.arm.visible = false
	# A clean little studio far from everything.
	var studio := Node3D.new()
	main.add_child(studio)
	studio.position = Vector3(0, 200, 0)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	floor.mesh = pm
	floor.material_override = load("res://src/art.gd").mat("concrete", Color(0.8, 0.78, 0.75), 2.0)
	studio.add_child(floor)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.9, 0.6, 0)
	key.light_energy = 1.3
	key.shadow_enabled = true
	studio.add_child(key)
	var fill := OmniLight3D.new()
	fill.omni_range = 8.0
	fill.light_energy = 1.0
	studio.add_child(fill)
	fill.position = Vector3(-1.5, 2.0, 2.0)
	var ids := Data.ITEMS.keys()
	var page := 0
	while page * 6 < ids.size():
		var made := []
		for k in 6:
			var i := page * 6 + k
			if i >= ids.size():
				break
			var id: String = ids[i]
			var m := Items.build(id)
			studio.add_child(m)
			var size: Vector3 = Data.ITEMS[id].size
			m.position = Vector3((k % 3) * 0.55 - 0.55, size.y / 2.0, (k / 3) * 0.5 - 0.35)
			m.rotation.y = 0.5
			made.append(m)
		var p = main.player
		p.global_position = studio.global_position + Vector3(0, -0.75, 1.05)
		p.rotation.y = 0.0
		p.head.rotation.x = -0.62
		await frames(8)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/items_%d.png" % [out, page])
		print("saved items_%d: %s" % [page, ", ".join(ids.slice(page * 6, page * 6 + 6))])
		for m in made:
			m.queue_free()
		page += 1
	quit()
