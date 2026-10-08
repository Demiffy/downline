# The new kit, as seen: the HUD minimap underground with a crewmate and the lift, the headlamp, night
# vision in a dark room, the charging rack on the train, and the new items laid out on a table.
# Needs a window. Run: tests/run.sh 240 --path . -s tests/gear_shots.gd -- <out_dir>
extends SceneTree

const Puppet = preload("res://src/puppet.gd")
const Data = preload("res://src/data.gd")

var main
var out := "user://gear"


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
	for u in ["MINIMAP", "HEADLAMP", "NIGHT_VISION"]:
		main.upgrades[u] = true
	# The charging rack, on the train.
	look(main.train.to_global(Vector3(2.0, 2.4, 0.4)), main.train.to_global(Vector3(2.0, 2.2, -1.8)))
	main.hud.visible = false
	await shot("charger")
	# Items on the floor of the crew car.
	var ids := ["MEDKIT", "FLARE", "NOISEMAKER", "ADRENALINE", "WARDEN_LENS", "VINTAGE_CAMERA", "MARIONETTE_STRINGS", "MIMIC_TOOTH", "PULSATOR_SAC", "MINERS_HELMET"]
	for i in ids.size():
		var p = main.spawn_item(ids[i], main.train.to_global(Vector3(-6.0 + (i % 5) * 0.55, 1.15, -0.3 + (i / 5) * 0.6)), -1.0, main.train)
		p.freeze = true
	await frames(10)
	look(main.train.to_global(Vector3(-4.9, 2.1, 1.2)), main.train.to_global(Vector3(-4.9, 1.05, 0.0)))
	await shot("items")
	# To a station.
	Engine.set_meta("fast_test", true)
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = "FACTORY"
	stop.weather = "CLEAR"
	stop.biome = "DESERT"
	main.player.global_position = main.train.to_global(Vector3(0, 1.3, 0))
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	await frames(20)
	Engine.remove_meta("fast_test")
	var lvl = main.level
	var fac = lvl.facility
	lvl.hazards.events.clear()
	main.player.hp = 1e9
	# Surface minimap: arrows to the lift.
	main.hud.visible = true
	look(main.train.to_global(Vector3(2.0, 2.6, 5.0)), main.train.to_global(Vector3(2.0, 2.0, 30.0)))
	await shot("minimap_surface")
	# Underground: a crewmate a room over, and the lift.
	var room: Vector3 = fac.to_global(Vector3(12, 0, 0)) if fac.layout.links.has(Vector2i(1, 0)) else fac.to_global(Vector3(0, 0, 12))
	var pup := Puppet.new()
	pup.main = main
	pup.net = main.net
	pup.peer = 77
	pup.display_name = "DEMIK"
	main.add_child(pup)
	main.net.puppets[77] = pup
	pup.set_pose(["W", fac.to_global(Vector3(3, 0.05, 2)), 0.8, 0.0, 1.8, "LANTERN", true, false, false, false, main.level_serial, true, true])
	look(room + Vector3(0, 1.7, 0), fac.to_global(Vector3(0, 1.2, 0)))
	await frames(20)
	await shot("minimap_facility")
	# Lights out: the headlamp, then night vision.
	main.hud.visible = false
	for l in fac.find_children("*", "OmniLight3D", true, false):
		l.visible = false
	main.player.headlamp_on = true
	await shot("headlamp")
	main.player.headlamp_on = false
	await shot("dark")
	main.player.nv_on = true
	main.hud.visible = true
	await shot("night_vision")
	main.net.puppets.erase(77)
	quit(0)
