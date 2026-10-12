# The crew body's moves (body_anim.gd) as contact sheets: a suit on a plain floor, posed frame by frame
# through each cycle (walk, run, crouch-walk, backwards, sideways, standing, turning on the spot, a jump
# and its landing) and every emote, seen side-on and three-quarter. One sheet per move. Needs a window.
# Run: tests/run.sh 200 --path . -s tests/anim_shots.gd -- <dir> [move ...]
extends SceneTree

const Suit = preload("res://src/suit.gd")
const BodyAnim = preload("res://src/body_anim.gd")
const A = preload("res://src/art.gd")

var out := ""
var cam: Camera3D


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://anim"
	var only: Array = args.slice(1)
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.21, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.58)
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	A.box(world, Vector3(40, 0.2, 40), Vector3(0, -0.1, 0), "concrete", Color(0.7, 0.7, 0.68), false, 2.0)
	for i in 40:   # floor lines: the feet should plant, not skate, against them
		A.box(world, Vector3(0.03, 0.005, 40), Vector3(-10.0 + i * 0.5, 0.003, 0), "paint", Color(0.3, 0.3, 0.3), false)
	var holder := Node3D.new()
	world.add_child(holder)
	var body := Node3D.new()
	holder.add_child(body)
	var parts := Suit.standing(body)
	cam = Camera3D.new()
	cam.fov = 40
	world.add_child(cam)
	cam.current = true
	await process_frame
	# [name, velocity (local: -z ahead), crouch, on floor (per frame: callable or bool), emote, frames, seconds between]
	var moves := [
		["walk", Vector3(0, 0, -4.0), 0.0, true, "", 8, 0.065],
		["run", Vector3(0, 0, -6.5), 0.0, true, "", 8, 0.045],
		["crouch_walk", Vector3(0, 0, -2.0), 1.0, true, "", 8, 0.12],
		["backwards", Vector3(0, 0, 3.0), 0.0, true, "", 8, 0.085],
		["sideways", Vector3(3.5, 0, 0), 0.0, true, "", 8, 0.075],
		["idle", Vector3.ZERO, 0.0, true, "", 8, 0.6],
		["turn_on_spot", Vector3.ZERO, 0.0, true, "turn", 8, 0.08],
		["jump_and_land", Vector3(0, 0, -4.0), 0.0, "jump", "", 8, 0.1],
	]
	for em in BodyAnim.EMOTES:
		var t: float = minf(BodyAnim.LENGTH[em], 3.0) / 8.0 if not em in ["DANCE"] else 2.0
		moves.append([em.to_lower().replace(" ", "_"), Vector3.ZERO, 0.0, true, em, 8, t])
	for m in moves:
		if not only.is_empty() and not m[0] in only:
			continue
		var anim := BodyAnim.new()
		holder.rotation.y = 0.0
		holder.position = Vector3.ZERO
		if m[4] != "" and m[4] != "turn":
			anim.play(m[4])
		var frames := []
		var yaw := 0.0
		for f in m[5]:
			var steps := int(round(float(m[6]) / (1.0 / 60.0))) if f > 0 else 90
			for k in steps:
				var dt := 1.0 / 60.0
				var on_floor := true
				var vel: Vector3 = m[1]
				if m[3] is String:   # the jump: up for ~0.55 s from the 3rd frame, then down
					var tt: float = (f - 2) * float(m[6]) + k * dt
					on_floor = not (f >= 2 and tt < 0.55)
				if m[4] == "turn":
					yaw += dt * 2.0
				holder.rotation.y = yaw
				var world_v: Vector3 = Basis(Vector3.UP, yaw) * vel
				holder.position += world_v * dt
				anim.pose(parts, body, {"vel": world_v, "yaw": yaw, "floor": on_floor, "crouch": float(m[2]), "pitch": 0.0, "neck": 0.0, "hands": true}, dt)
				if m[4] != "" and m[4] != "turn" and anim.emote == "":
					anim.play(m[4])   # (keep it going for the sheet)
			var y_off := 0.0
			if m[3] is String:
				var tt: float = (f - 2) * float(m[6])
				y_off = 4.0 * 0.55 * tt * (1.0 - tt / 0.55) if f >= 2 and tt < 0.55 else 0.0
			body.position.y += y_off
			var c := holder.global_position + Vector3(0, 0.95 + y_off * 0.5, 0)
			var side: bool = not m[0] in ["wave", "salute", "thumbs_up", "clap", "cheer", "shrug", "beckon", "point", "dance", "sit"]
			cam.global_position = c + (Vector3(4.2, 0.3, 0) if side else Vector3(0.9, 0.5, -3.9))
			cam.look_at(c)
			await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.resize(img.get_width() / 3, img.get_height() / 3)
			frames.append(img)
			body.position.y -= y_off
		var w: int = frames[0].get_width()
		var h: int = frames[0].get_height()
		var sheet := Image.create(w * 4, h * 2, false, frames[0].get_format())
		for i in frames.size():
			sheet.blit_rect(frames[i], Rect2i(0, 0, w, h), Vector2i((i % 4) * w, (i / 4) * h))
		sheet.save_png(out + "/" + m[0] + ".png")
		print("sheet ", m[0])
	quit()
