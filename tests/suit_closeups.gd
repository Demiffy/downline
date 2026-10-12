# The crew suit (suit.gd) under a studio light from every side and up close, to check it piece by
# piece: whole figure from six sides; head front/side/back/top; chest, pack, hips, hands, knees, boots
# (and their soles), shoulders; then poses that open the joints (mid-stride, arms up, crouched,
# sitting, reaching across). Needs a window.
# Run: tests/run.sh 200 --path . -s tests/suit_closeups.gd -- <dir> [suit helmet mark visor pack ...look]
extends SceneTree

const Suit = preload("res://src/suit.gd")
const A = preload("res://src/art.gd")

var out := ""
var cam: Camera3D
var fig: Node3D
var parts: Dictionary


func _initialize() -> void:
	_run()


func shot(name: String, from: Vector3, at: Vector3, fov := 30.0) -> void:
	cam.fov = fov
	cam.global_position = from
	cam.look_at(at, Vector3.UP if absf((at - from).normalized().y) < 0.98 else Vector3.FORWARD)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var look: Array = []
	for a in args.slice(1):
		look.append(int(a))
	var w := Node3D.new()
	root.add_child(w)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.33, 0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.72)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	for l in [[Vector3(-0.8, 0.7, 0), 1.3], [Vector3(-0.4, -2.6, 0), 0.6], [Vector3(-0.3, 2.2, 0), 0.5]]:   # key, fill, back
		var d := DirectionalLight3D.new()
		d.rotation = l[0]
		d.light_energy = l[1]
		d.shadow_enabled = l[1] > 1.0
		w.add_child(d)
	A.box(w, Vector3(6, 0.1, 6), Vector3(0, -0.05, 0), "concrete", Color(0.55, 0.55, 0.55), false, 1.0)
	cam = Camera3D.new()
	w.add_child(cam)
	cam.current = true
	fig = Node3D.new()
	w.add_child(fig)
	parts = Suit.standing(fig)
	if not look.is_empty():
		Suit.apply_look(fig, look, "EMPLOYEE")
	else:
		Suit.apply_look(fig, [0, 0, 0], "EMPLOYEE")
	await process_frame
	var c := Vector3(0, 0.95, 0)
	for v in [["a_front", Vector3(0, 1.0, -4.2)], ["a_back", Vector3(0, 1.0, 4.2)], ["a_left", Vector3(-4.2, 1.0, 0)], ["a_right", Vector3(4.2, 1.0, 0)], ["a_34front", Vector3(-2.9, 1.3, -2.9)], ["a_34back", Vector3(2.9, 1.3, 2.9)]]:
		await shot(v[0], v[1], c)
	var head := Vector3(0, 1.68, 0)
	await shot("b_head_front", head + Vector3(0.0, 0.05, -1.0), head, 25.0)
	await shot("b_head_side", head + Vector3(1.0, 0.05, 0.0), head, 25.0)
	await shot("b_head_back", head + Vector3(0.3, 0.1, 1.0), head, 25.0)
	await shot("b_head_top", head + Vector3(0.2, 1.0, -0.2), head, 25.0)
	await shot("b_head_below", head + Vector3(0.2, -0.6, -0.7), head, 25.0)
	await shot("c_chest", Vector3(0.3, 1.4, -1.3), Vector3(0, 1.3, 0), 25.0)
	await shot("c_pack", Vector3(0.4, 1.45, 1.3), Vector3(0, 1.3, 0.1), 28.0)
	await shot("c_hips_front", Vector3(0.3, 1.0, -1.1), Vector3(0, 0.98, 0), 25.0)
	await shot("c_hips_side", Vector3(1.1, 1.0, -0.2), Vector3(0, 0.98, 0), 25.0)
	await shot("c_shoulder", Vector3(-0.9, 1.55, -0.6), Vector3(-0.2, 1.4, 0), 22.0)
	await shot("c_armpit", Vector3(-0.8, 1.2, 0.1), Vector3(-0.2, 1.35, 0), 25.0)
	var hl: Vector3 = (parts.forearm_l as Node3D).to_global(Vector3(0, -0.33, 0))
	var hr: Vector3 = (parts.forearm_r as Node3D).to_global(Vector3(0, -0.33, 0))
	await shot("d_hand_l_out", hl + Vector3(-0.45, 0.05, -0.15), hl, 20.0)
	await shot("d_hand_l_in", hl + Vector3(0.35, 0.05, -0.3), hl, 20.0)
	await shot("d_hand_r_front", hr + Vector3(0.1, 0.05, -0.5), hr, 20.0)
	await shot("d_hand_r_back", hr + Vector3(0.2, 0.1, 0.45), hr, 20.0)
	await shot("e_knees", Vector3(0.4, 0.55, -1.0), Vector3(0, 0.5, 0), 25.0)
	await shot("e_boots_front", Vector3(0.2, 0.25, -0.9), Vector3(0, 0.08, 0), 25.0)
	await shot("e_boots_side", Vector3(0.9, 0.2, -0.1), Vector3(0.1, 0.08, -0.05), 25.0)
	await shot("e_boots_back", Vector3(0.3, 0.3, 0.9), Vector3(0, 0.1, 0), 25.0)
	# Poses that open the joints.
	var poses := {
		"f_stride": {"thigh_l": Vector3(-0.55, 0, 0), "shin_l": Vector3(0.35, 0, 0), "thigh_r": Vector3(0.5, 0, 0), "shin_r": Vector3(0.9, 0, 0), "upper_arm_l": Vector3(0.5, 0, -0.1), "upper_arm_r": Vector3(-0.5, 0, 0.1), "forearm_l": Vector3(0.6, 0, 0), "forearm_r": Vector3(0.2, 0, 0)},
		"f_arms_up": {"upper_arm_l": Vector3(0, 0, -2.6), "upper_arm_r": Vector3(0, 0, 2.6), "forearm_l": Vector3(0.3, 0, 0), "forearm_r": Vector3(0.3, 0, 0)},
		"f_crouch": {"pelvis": Vector3(0.0, 0, 0), "thigh_l": Vector3(-1.5, 0, -0.1), "shin_l": Vector3(2.0, 0, 0), "thigh_r": Vector3(-1.2, 0, 0.1), "shin_r": Vector3(2.2, 0, 0), "torso": Vector3(-0.4, 0, 0)},
		"f_reach": {"upper_arm_r": Vector3(-1.4, -0.6, 0.6), "forearm_r": Vector3(0.9, 0, 0), "upper_arm_l": Vector3(-1.6, 0, 0), "forearm_l": Vector3(0.1, 0, 0), "torso": Vector3(0.15, 0.4, 0), "head": Vector3(0.2, -0.3, 0)},
	}
	for pn in poses:
		for k in parts:
			parts[k].rotation = Vector3.ZERO
		var p: Dictionary = poses[pn]
		for k in p:
			parts[k].rotation = p[k]
		fig.position.y = -0.38 if pn == "f_crouch" else 0.0
		await shot(pn + "_side", Vector3(2.6, 1.1, -0.4), Vector3(0, 0.85, 0), 34.0)
		await shot(pn + "_34", Vector3(-1.9, 1.2, -1.9), Vector3(0, 0.85, 0), 34.0)
		if pn == "f_arms_up":
			await shot(pn + "_pit", Vector3(-0.6, 1.3, -0.9), Vector3(-0.25, 1.5, 0), 26.0)
		if pn == "f_crouch":
			await shot(pn + "_knee", Vector3(0.5, 0.35, -0.9), Vector3(0, 0.25, -0.15), 28.0)
	quit()
