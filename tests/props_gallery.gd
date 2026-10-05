# Builds every prop / furniture piece in a lit studio, 4 per shot, and saves screenshots. Needs a window.
# Run: godot --path . -s tests/props_gallery.gd -- <out_dir>
extends SceneTree

const A = preload("res://src/art.gd")
const P = preload("res://src/props.gd")
const Merge = preload("res://src/merge.gd")

var main
var out := "user://props_gallery"


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
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var studio := Node3D.new()
	main.add_child(studio)
	studio.position = Vector3(0, 200, 0)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(14, 14)
	floor.mesh = pm
	floor.material_override = A.mat("concrete", Color(0.8, 0.78, 0.75), 2.0)
	studio.add_child(floor)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.8, 0.5, 0)
	key.light_energy = 1.2
	key.shadow_enabled = true
	studio.add_child(key)
	var fill := OmniLight3D.new()
	fill.omni_range = 12.0
	fill.light_energy = 1.0
	studio.add_child(fill)
	fill.position = Vector3(-2, 3, 3)
	var builders := [
		["chair", func(n): P.chair(n, Vector3.ZERO, PI)],
		["table", func(n): P.table(n, Vector3.ZERO, 0.0)],
		["desk", func(n): A.desk(n, Vector3.ZERO, PI, rng)],
		["filing_cabinet", func(n): P.filing_cabinet(n, Vector3.ZERO, PI)],
		["locker", func(n): A.locker(n, Vector3.ZERO, PI)],
		["shelf_unit", func(n): A.shelf_unit(n, Vector3.ZERO, PI, rng)],
		["crate", func(n): A.crate(n, Vector3.ZERO, 0.9, rng)],
		["barrel", func(n): A.barrel(n, Vector3.ZERO, rng)],
		["vending", func(n): P.vending(n, Vector3.ZERO, PI, rng)],
		["fridge", func(n): P.fridge(n, Vector3.ZERO, PI)],
		["server_rack", func(n): P.server_rack(n, Vector3.ZERO, PI, rng)],
		["control_panel", func(n): P.control_panel(n, Vector3.ZERO, PI, rng)],
		["lab_bench", func(n): P.lab_bench(n, Vector3.ZERO, PI, rng)],
		["gurney", func(n): P.gurney(n, Vector3.ZERO, PI * 0.5)],
		["counter", func(n): P.counter(n, Vector3.ZERO, PI)],
		["generator", func(n): P.generator(n, Vector3.ZERO, PI, rng)],
		["specimen_tank", func(n): P.specimen_tank(n, Vector3.ZERO, rng)],
		["lamp_post", func(n): A.lamp_post(n, Vector3.ZERO, Color(1, 0.8, 0.5))],
		["car_wreck", func(n): P.car_wreck(n, Vector3.ZERO, PI * 0.4, rng)],
		["telephone_pole", func(n): A.telephone_pole(n, Vector3.ZERO)],
	]
	var page := 0
	while page * 4 < builders.size():
		var holder := Node3D.new()
		studio.add_child(holder)
		var names := []
		for k in 4:
			var i := page * 4 + k
			if i >= builders.size():
				break
			var slot := Node3D.new()
			holder.add_child(slot)
			slot.position = Vector3(k * 2.6 - 3.9, 0, 0)
			builders[i][1].call(slot)
			names.append(builders[i][0])
		Merge.bake(holder, 6.0)
		var big := page == 4   # outdoor page: step back
		var p = main.player
		p.global_position = studio.global_position + (Vector3(0, 0.6, 9.5) if big else Vector3(0, -0.2, 4.6))
		p.rotation.y = 0.0
		p.head.rotation.x = -0.05 if big else -0.28
		await frames(8)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/props_%d.png" % [out, page])
		print("saved props_%d: %s" % [page, ", ".join(names)])
		holder.queue_free()
		page += 1
	quit()
