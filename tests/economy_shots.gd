# The bonded stock and the shredder's diverter: the switch on the pedestal (SELL and BANK), the
# store in the hall full and empty, the readout, the shift report with fees. Needs a window.
# Run: tests/run.sh 400 --path . -s tests/economy_shots.gd -- <out_dir>
extends SceneTree

var main
var out := "user://economy"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func look(pos: Vector3, at: Vector3) -> void:
	var p = main.player
	p.global_position = pos - Vector3(0, 1.6, 0)
	p.velocity = Vector3.ZERO
	var d := at - pos
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(30)
	for n in main.get_children():
		if n.has_method("_show_title"):
			n.queue_free()
	main.player.set_physics_process(false)
	main.player.frozen = true
	main.hud.visible = false
	main.assignment = 2
	main.quota = {"steel": 14, "copper": 10, "rubber": 12, "plastic": 9}
	main.submitted = {"steel": 14, "copper": 6, "rubber": 12, "plastic": 9}
	await frames(30)
	look(Vector3(2.0, 1.45, 10.3), Vector3(2.92, 0.85, 11.0))
	await shot("diverter_sell")
	main.toggle_divert()
	await create_timer(0.5).timeout
	await shot("diverter_bank")
	look(Vector3(1.6, 1.75, 9.0), Vector3(3.2, 1.0, 11.2))
	await shot("pedestal_both")
	look(Vector3(-2.4, 1.7, 11.9), Vector3(-7.5, 1.2, 11.9))
	await shot("store_empty")
	main.bank = {"steel": 23, "copper": 7, "rubber": 14, "plastic": 2}
	main._stock_changed()
	await frames(4)
	await shot("store_full")
	look(Vector3(-3.0, 2.2, 16.0), Vector3(-7.2, 1.0, 11.6))
	await shot("store_angle")
	look(Vector3(-5.2, 1.6, 10.4), Vector3(-7.6, 0.7, 12.6))
	await shot("store_close")
	look(Vector3(1.0, 2.0, 6.0), Vector3(-6.5, 1.0, 13.0))
	await shot("hall_wide")
	look(Vector3(3.45, 2.1, 9.6), Vector3(3.45, 2.3, 11.1))
	await shot("readout")
	main.credits = -85
	main.hud.visible = true
	look(Vector3(0.0, 1.7, 6.5), Vector3(0.0, 1.6, 13.0))
	await create_timer(0.3).timeout
	await shot("hud_debt")
	main.report.show_report([2, "CHECKPOINT   21:10", 31, 412, 138, 2, 1, "B", 100, 18])
	await create_timer(4.6).timeout
	await shot("report")
	quit()
