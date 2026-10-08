# Proximity voice without a network: the mu-law codec, and how a voice reaches you through the
# facility (same room clear; through a wall muffled; round a doorway quieter and duller; far off, gone).
# Run: tests/run.sh 120 --headless --path . -s tests/voice.gd
extends SceneTree

const Voice = preload("res://src/voice.gd")
const Puppet = preload("res://src/puppet.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	_run()


func _run() -> void:
	# Codec: a tone survives the trip within a few percent.
	var tone := PackedFloat32Array()
	for i in 320:
		tone.append(sin(TAU * 440.0 * i / 24000.0) * 0.5)
	var back := Voice.decode(Voice.encode(tone))
	var err := 0.0
	for i in tone.size():
		err = maxf(err, absf(back[i] - tone[i]))
	check(back.size() == 320 and Voice.encode(tone).size() == 640 and err < 0.0002, "16-bit round trip: 320 samples in 640 bytes, worst error %.5f" % err)
	var quiet := PackedFloat32Array([0.001, -0.001, 0.0])
	var qb := Voice.decode(Voice.encode(quiet))
	check(absf(qb[0] - 0.001) < 0.0001, "...and quiet sounds keep their detail (%.5f)" % qb[0])
	# Capture: a 1 kHz tone at the mix rate comes through clean; a 15 kHz one (above what 24 kHz
	# can carry) is filtered out instead of folding back down as a whistle.
	var pass_rms := func(freq: float) -> float:
		var vc = Voice.new()
		var buf := PackedVector2Array()
		for i in 48000:
			var x := sin(TAU * freq * i / 48000.0) * 0.3
			buf.append(Vector2(x, x))
		vc._lp_rate = 0.0
		vc._design(48000.0)
		var out := vc.filter_only(buf, 48000.0)
		vc.free()
		var sum := 0.0
		for i in range(4000, out.size()):
			sum += out[i] * out[i]
		return sqrt(sum / (out.size() - 4000))
	var low: float = pass_rms.call(1000.0)
	var high: float = pass_rms.call(15000.0)
	check(absf(low - 0.3 / sqrt(2.0)) < 0.02, "the mic chain passes speech untouched (1 kHz: %.3f rms)" % low)
	check(high < low * 0.032, "...and filters out what can't be carried (15 kHz: %.4f, %.0f dB down)" % [high, linear_to_db(high / low)])
	# Occlusion in a real facility.
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.term.run("LEAVE_CHECKPOINT")
	Engine.set_meta("fast_test", true)
	var st: Dictionary = main.route[0][0]
	st.theme = "LAB"
	st.rooms = 20
	main.player.global_position = Vector3(0, 1.3, 0)
	main.rng.seed = 7   # (a fixed site: the room picked below is always there)
	main.term.run("ROUTE_TO " + st.letter)
	while main.busy:
		await process_frame
	for i in 20:
		await physics_frame
	var fac = main.level.facility
	var voice = main.net.voice
	voice.main = main
	var pup = Puppet.new()
	pup.main = main
	pup.net = main.net
	main.add_child(pup)
	await process_frame
	pup.visible = true
	pup.set_process(false)   # (no poses come in: keep it where we put it)
	var hear := func(at: Vector3) -> Array:
		pup.global_position = at
		await physics_frame
		return voice._occlusion(pup)
	# Pick a room with a doorway to a neighbour and a solid wall to another neighbour.
	var a := Vector2i(999, 999)
	var through := Vector2i.ZERO
	var walled := Vector2i.ZERO
	for c in fac.layout.cells:
		if fac.kinds[c] in ["start", "pit", "stairwell", "atrium", "tunnel", "vault"] or fac.group_of.has(c):
			continue
		var open_n = null
		var wall_n = null
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not fac.layout.links.has(n) or fac.kinds[n] in ["pit", "stairwell", "atrium", "vault"]:
				continue
			if fac.layout.links[c].has(n):
				open_n = n
			elif not fac.vents.has(fac.edge(c, n)):
				wall_n = n
		if open_n != null and wall_n != null:
			a = c
			through = open_n
			walled = wall_n
			break
	check(a != Vector2i(999, 999), "found a room with a doorway one way and a wall another")
	if a == Vector2i(999, 999):
		_done()
		return
	var o: Vector3 = fac.to_global(Vector3(a.x * 12.0, 0.05, a.y * 12.0))
	main.player.global_position = o + Vector3(1.0, 0, 1.0)
	main.player.velocity = Vector3.ZERO
	await physics_frame
	var same: Array = await hear.call(o + Vector3(-2.0, 0, -1.5))
	check(same[0] == 0.0 and same[1] > 20000.0, "same room: clear (%.0f dB, %.0f Hz)" % same)
	# Just the other side of the solid wall, close: muffled (and no short way round).
	var dw := Vector3(walled.x - a.x, 0, walled.y - a.y)
	main.player.global_position = o + dw * 4.6
	await physics_frame
	var wall: Array = await hear.call(o + dw * 7.4)
	check(wall[0] <= -10.0 and wall[1] <= 4500.0, "through a wall: muffled (%.0f dB, %.0f Hz)" % wall)
	# In the next room through the doorway, off to one side (no line of sight): round the corner.
	var dt := Vector3(through.x - a.x, 0, through.y - a.y)
	var side := Vector3(dt.z, 0, dt.x)
	main.player.global_position = o + dt * 3.0 + side * 4.0
	await physics_frame
	var corner: Array = await hear.call(o + dt * 9.0 + side * 4.0)
	check(corner[0] < 0.0 and corner[0] > -25.0 and corner[1] < 20000.0, "round a doorway: quieter and duller, but there (%.0f dB, %.0f Hz)" % corner)
	check(corner[0] > wall[0] or wall[0] <= -20.0, "...clearer than through a wall")
	# Far across the site: gone.
	var far_c: Vector2i = a
	var best := 0
	for c in fac.layout.cells:
		var d: int = absi(c.x - a.x) + absi(c.y - a.y)
		if d > best and not fac.kinds[c] in ["pit", "stairwell"]:
			best = d
			far_c = c
	main.player.global_position = o + Vector3(1.0, 0, 1.0)
	await physics_frame
	var far: Array = await hear.call(fac.to_global(Vector3(far_c.x * 12.0, 0.05, far_c.y * 12.0)))
	check(far[0] <= -20.0, "across the site, behind several walls: barely or not at all (%.0f dB)" % far[0])
	pup.dead = true
	var dead: Array = await hear.call(o + Vector3(-2.0, 0, -1.5))
	check(dead[0] <= -80.0, "the dead say nothing")
	_done()


func _done() -> void:
	print("voice.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
