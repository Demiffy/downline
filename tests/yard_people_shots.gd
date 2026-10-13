# The checkpoint's people (yard_life.gd), each thing they do, caught from the front: a walk; every
# greeting and every act (a drink, the radio, the watch, a stretch, a scratch, a crouch to look, a
# scuff, a nod) on one of them; two of them stopping for a chat (three moments); the welder at his
# beam; the one on his break; the gate's man; the hands. Needs a window.
# Run: tests/run.sh 200 --path . -s tests/yard_people_shots.gd -- <dir>
extends SceneTree

var main
var out := ""
var cam: Camera3D


func _initialize() -> void:
	_run()


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func wait(secs: float) -> void:
	var a := Time.get_ticks_msec()
	while Time.get_ticks_msec() - a < secs * 1000.0:
		await process_frame


## Hold someone where they are (no walking off mid-shot), facing the way given.
func hold(w: Dictionary, yaw: float) -> void:
	w.wait = 9999.0
	w.idle = 9999.0
	w.vel = Vector3.ZERO
	w.node.rotation.y = yaw


func front(n: Node3D, dist := 2.6, h := 1.45, look_h := 1.0, side := 0.6) -> void:
	cam.look_at_from_position(n.global_position - n.global_basis.z * dist + n.global_basis.x * side + Vector3(0, h, 0), n.global_position + Vector3(0, look_h, 0))


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await wait(12.0)
	main.hud.visible = false
	main.player.global_position = Vector3(0, 0.1, 96)   # (out of the way, out on the surface: they'd look at you)
	var yl: Node = main.level.find_child("YardLife", true, false)
	cam = Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 45.0
	var a: Dictionary = yl._people[1]   # (with a thermos)
	var an: Node3D = a.node
	an.position = Vector3(0, 0.06, 61.0)   # (out on the lot by the trucks, in the open: not wherever he'd got to)
	hold(a, PI)
	front(an)
	await wait(4.0)   # (the light settles first)
	for g in ["WAVE", "THUMBS UP", "SALUTE", "POINT", "SHRUG", "LAUGH"]:
		a.anim.play(g)
		front(an)
		await wait(0.9)
		await snap("greet_" + g.to_lower().replace(" ", "_"))
		await wait(1.6)
	for act in ["drink", "radio", "watch", "stretch", "scratch", "inspect", "scuff", "nod"]:
		yl._start_act(a, act)
		front(an)
		await wait(minf(1.0, yl.ACT_LEN[act] * 0.45))
		await snap("act_" + act)
		await wait(yl.ACT_LEN[act])
	# A chat: a second one beside the first, both held, then talking.
	var b: Dictionary = yl._people[3]
	b.node.position = an.position + an.basis * Vector3(1.6, 0, -0.6)
	hold(b, an.rotation.y)
	await wait(0.5)
	yl._start_chat(a, b, Time.get_ticks_msec() / 1000.0)
	var mid: Vector3 = (an.global_position + b.node.global_position) / 2.0
	var across: Vector3 = (b.node.global_position - an.global_position).cross(Vector3.UP).normalized()
	for k in 4:
		await wait(1.4)
		cam.look_at_from_position(mid + across * 3.2 + Vector3(0, 1.5, 0), mid + Vector3(0, 1.1, 0))
		await snap("chat_%d" % k)
	for pair in [["welder", yl.WELDER, 1.9, 1.1, 0.6], ["break", yl.BREAK, 2.2, 1.3, 0.5], ["guard", 11, 2.4, 1.8, 1.0]]:
		var m: Node3D = yl._people[pair[1]].node
		front(m, pair[2], pair[3], pair[4], 0.7)
		await wait(1.2)
		await snap(pair[0])
	# The hands, close.
	var hand: Node3D = a.parts.forearm_r
	cam.look_at_from_position(hand.global_position + hand.global_basis * Vector3(0.0, -0.3, 0) - an.global_basis.z * 0.5 + Vector3(0, 0.05, 0), hand.global_position + hand.global_basis * Vector3(0, -0.3, 0))
	await wait(0.3)
	await snap("hand")
	quit()
