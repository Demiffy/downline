# Voice playback on one machine: frames "arrive" from a crewmate standing a few metres away and
# must come out of the Voice bus (measured at the bus meter), from the very first game (the Net hub
# is made after main, so voice.main has to be set late; once it wasn't, and nobody heard anybody).
# Run: tests/run.sh 120 --headless --path . -s tests/voice_play.gd
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
	Engine.set_meta("fast_test", true)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var v = main.net.voice
	check(v.main == main, "the voice knows the game it's in")
	var pup := Puppet.new()
	pup.main = main
	pup.net = main.net
	pup.peer = 99
	pup.display_name = "TALKY"
	main.add_child(pup)
	v.attach_puppet(99, pup)
	var bus := AudioServer.get_bus_index("Voice")
	var peak := -200.0
	var phase := 0.0
	for k in 120:   # 2.4 s of a 300 Hz tone, at the pace it's spoken
		var f := PackedFloat32Array()
		for i in Voice.FRAME:
			f.append(sin(phase) * 0.4)
			phase += TAU * 300.0 / Voice.RATE
		v.receive(99, Voice.packet(k, f))
		await create_timer(0.02).timeout
		peak = maxf(peak, AudioServer.get_bus_peak_volume_left_db(bus, 0))
	await create_timer(1.0).timeout
	var pp: Dictionary = v._peers[99]
	check(pp.db > -10.0, "a crewmate in the same room is heard at full level (%.1f dB)" % pp.db)
	check(pp.frames == 120 and pp.queue.is_empty(), "every frame went to their voice player (%d, %d left over)" % [pp.frames, pp.queue.size()])
	check(pp.player.playing, "their voice player is playing")
	check(pp.fills <= 6, "a steady stream needs almost no fillers (they used to come every frame, each one a tick): %d in 120 frames" % pp.fills)
	# A bumpy line: frames arriving in swapped pairs, every ninth one lost. It still plays through.
	for k in 120:
		var j := 200 + (k ^ 1)   # (out of order)
		if j % 9 == 0:
			await create_timer(0.02).timeout
			continue
		var f := PackedFloat32Array()
		f.resize(Voice.FRAME)
		f.fill(0.2)
		v.receive(99, Voice.packet(j, f))
		await create_timer(0.02).timeout
	await create_timer(0.5).timeout
	check(pp.frames_in.is_empty(), "a bumpy line: out-of-order frames sorted, lost ones covered, nothing stuck (%d left)" % pp.frames_in.size())
	check(pp.delay > Voice.START_AT or pp.delay == Voice.START_AT, "...the jitter buffer adapts (%d frames)" % pp.delay)
	# The radio: frames sent over a walkie come out of yours, only if you carry one.
	var tone := func(seq0: int, n: int) -> void:
		for k in n:
			var f := PackedFloat32Array()
			f.resize(Voice.FRAME)
			f.fill(0.3)
			v.receive(99, Voice.packet(seq0 + k, f, 1))
			await create_timer(0.02).timeout
	await tone.call(400, 30)
	await create_timer(0.4).timeout
	check(pp.radio_frames == 0, "without a walkie you don't hear the radio (%d frames)" % pp.radio_frames)
	main.player.slots[2] = {"id": "WALKIE", "charge": 100.0, "extra": {}}
	await tone.call(500, 30)
	await create_timer(0.4).timeout
	check(pp.radio_frames >= 25 and pp.radio != null and pp.radio.playing, "with a walkie, their radio comes through (%d frames)" % pp.radio_frames)
	main.player.slots[1] = {"id": "WALKIE", "charge": 50.0, "extra": {}}
	main.player.sel = 1
	check(main.player.transmitting(), "holding a walkie keys it")
	# After travelling to a station (the level is rebuilt; the puppet stands by you there), the
	# voice still plays. (Someone heard nothing once the crew reached a station.)
	main.player.slots[1] = null
	main.player.slots[2] = null
	main.term.run("LEAVE_CHECKPOINT")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	main.term.close()
	var seq := 700
	var talk := func(n: int) -> void:
		for k in n:
			var f := PackedFloat32Array()
			f.resize(Voice.FRAME)
			for i in Voice.FRAME:
				f[i] = sin(TAU * 300.0 * i / Voice.RATE) * 0.4
			v.receive(99, Voice.packet(seq, f))
			seq = (seq + 1) & 0xFFFF
			await create_timer(0.02).timeout
	while main.busy:   # (they keep talking all through the trip)
		await talk.call(5)
	pup.global_position = main.player.global_position + Vector3(1.5, 0, 0)
	pup.set_pose(["W", main.player.global_position + Vector3(1.5, 0, 0), 0.0, 0.0, 1.8, "", false, false, main.train.contains(main.player.global_position), false, main.level_serial, true])
	await create_timer(0.5).timeout
	var played0: int = pp.played
	var f0: int = pp.frames
	await talk.call(60)
	await create_timer(0.5).timeout
	check(pp.frames - f0 == 60 and pp.played - played0 >= 50, "at a station, a crewmate's voice still plays (%d of %d frames played, %.1f dB)" % [pp.played - played0, pp.frames - f0, pp.db])
	# The game freezes for a few seconds (a station being built) while they talk: the buffer runs
	# dry, frames come in a heap afterwards, and then they go on talking. It must catch up and
	# carry on playing (it used to race ahead, call every new frame too late, and fall silent).
	await talk.call(20)
	OS.delay_msec(2500)
	for k in 125:   # (what piled up in those 2.5 s, all at once)
		var f := PackedFloat32Array()
		f.resize(Voice.FRAME)
		f.fill(0.3)
		v.receive(99, Voice.packet(seq, f))
		seq = (seq + 1) & 0xFFFF
	await process_frame
	var played1: int = pp.played
	await talk.call(80)
	await create_timer(0.5).timeout
	check(pp.played - played1 >= 60, "after the game froze for a few seconds, their voice plays on (%d of 80 frames, %d resyncs)" % [pp.played - played1, pp.resyncs])
	# Outdoors, a post or a rock or a dune between you doesn't cut a voice off.
	var me: Vector3 = main.player.global_position
	main.player.global_position = Vector3(me.x, me.y, me.z)
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.4, 3.0, 3.0)
	cs.shape = bs
	wall.add_child(cs)
	main.add_child(wall)
	var mid: Vector3 = (main.player.cam.global_position + pup.head.global_position) / 2.0
	wall.global_position = mid
	var wall2 := wall.duplicate()
	main.add_child(wall2)
	wall2.global_position = mid + (pup.head.global_position - main.player.cam.global_position).normalized() * 0.5
	await physics_frame
	await physics_frame
	var o: Array = v._occlusion(pup)
	check(main.player.global_position.y > main.UNDERGROUND_Y and o[0] > -12.0, "outdoors, two posts between you only muffle a crewmate a little (%.1f dB)" % o[0])
	wall.queue_free()
	wall2.queue_free()
	print("(Voice bus peak %.1f dB; the headless audio driver does not always mix)" % peak)
	print("voice_play.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
