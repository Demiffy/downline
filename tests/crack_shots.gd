# A cracked visor at each tier (cracks.gd): your own view through it in the playground (the overlay
# bending the light at the cracks, frosting round the strikes), then a crewmate's visor up close and
# from a few metres. Needs a window.
# Run: tests/run.sh 200 --path . -s tests/crack_shots.gd -- <dir> playground
extends SceneTree

const Suit = preload("res://src/suit.gd")

var main
var pg
var out := ""


func _initialize() -> void:
	_run()


func snap(name: String) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	while pg == null:
		for c in main.get_children():
			if c.get_script() != null and c.get_script().resource_path.ends_with("playground.gd"):
				pg = c
		await process_frame
	while not pg._ready_done:
		await process_frame
	pg.strip.visible = false
	pg.god = false
	main.player.god = false
	await create_timer(1.0).timeout
	for t in [1, 2, 3]:
		main.player.hp = [0, 60.0, 30.0, 10.0][t]   # (the tier follows your health)
		main.player.flash = 0.0
		await create_timer(0.4).timeout
		main.player.flash = 0.0
		await snap("view_tier%d" % t)
	main.player.hp = 100.0
	main.player.crack_tier = 0
	# A crewmate's visor: a figure in front of a camera of our own.
	var cam := Camera3D.new()
	main.add_child(cam)
	var fig := Node3D.new()
	main.add_child(fig)
	var at: Vector3 = main.player.global_position + (-main.player.global_transform.basis.z) * 3.0
	fig.global_position = at
	fig.look_at(main.player.global_position, Vector3.UP, true)
	Suit.standing(fig)
	Suit.apply_look(fig, [], "TEST")
	var lamp := OmniLight3D.new()
	lamp.omni_range = 5.0
	lamp.light_energy = 1.6
	cam.add_child(lamp)
	lamp.position = Vector3(0.4, 0.6, 0)
	cam.current = true
	var head: Vector3 = fig.to_global(Vector3(0, 1.68, 0))
	var front: Vector3 = (fig.to_global(Vector3(0, 0, -1)) - fig.global_position).normalized()
	for t in [1, 2, 3]:
		Suit.set_cracks(fig, t)
		cam.look_at_from_position(head + front * 0.55 + Vector3(0.12, 0.05, 0), head)
		await snap("suit_tier%d" % t)
	cam.look_at_from_position(head + front * 2.6 + Vector3(0.6, -0.2, 0), head + Vector3(0, -0.4, 0))
	await snap("suit_tier3_far")
	quit()
