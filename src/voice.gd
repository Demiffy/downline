# Proximity voice. Your microphone is captured (a muted "Mic" bus with an AudioEffectCapture),
# brought down to 16 kHz mono, cut into 20 ms frames, mu-law coded to a byte per sample and sent to
# everyone while you speak (open mic with a level gate, or push-to-talk on V).
# Each other player's voice plays from their helmet on a 3D player (generator at 16 kHz) through the
# World bus, so it picks up the room's echo, and it fades with distance:
#   line of sight            clear
#   round a corner           a doorway between you: quieter and duller, with the extra distance
#   through a wall           heavily muffled; through two walls, gone
# Loud talking also carries to creatures that hunt by sound (main.noise), walls muffling it as usual.
extends Node

const Settings = preload("res://src/settings.gd")

const RATE := 16000
const FRAME := 320            # 20 ms at 16 kHz
const MAX_QUEUE := 12         # frames buffered per speaker before we drop the oldest (latency cap)
const START_AT := 2           # frames to buffer before starting (rides out network jitter)

var net
var main
var speaking := false         # you, right now (the HUD and your pose show it)
var level := 0.0              # your mic level, 0..1 (the HUD meter)
var _capture: AudioEffectCapture
var _mic: AudioStreamPlayer
var _phase := 0.0
var _acc := 0.0
var _acc_n := 0
var _frame := PackedFloat32Array()
var _hang := 0.0
var _noise_cd := 0.0
var _peers := {}              # peer -> {player, queue, started, occ_t, db, cut}
static var _encode_table := PackedByteArray()
static var _decode_table := PackedFloat32Array()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tables()
	_buses()
	if DisplayServer.get_name() == "headless" or not ProjectSettings.get_setting("audio/driver/enable_input", false):
		return
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = "Mic"
	add_child(_mic)


func _buses() -> void:
	if AudioServer.get_bus_index("Mic") < 0:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, "Mic")
		AudioServer.set_bus_mute(i, true)   # you don't hear yourself
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.5
		AudioServer.add_bus_effect(i, _capture)
	else:
		_capture = AudioServer.get_bus_effect(AudioServer.get_bus_index("Mic"), 0)
	if AudioServer.get_bus_index("Voice") < 0:
		var v := AudioServer.bus_count
		AudioServer.add_bus(v)
		AudioServer.set_bus_name(v, "Voice")
		AudioServer.set_bus_send(v, "World" if AudioServer.get_bus_index("World") >= 0 else "Master")   # (the room's echo)


## Start or stop listening to the microphone (only while in a session, and only if it's on).
func _want_mic() -> bool:
	return net != null and net.active and net.started and bool(Settings.v.get("mic_on", true))


func _process(delta: float) -> void:
	if _mic:
		var want := _want_mic()
		if want and not _mic.playing:
			_mic.play()
		elif not want and _mic.playing:
			_mic.stop()
			_capture.clear_buffer()
	if _capture and _mic and _mic.playing:
		var n := _capture.get_frames_available()
		if n > 0:
			_feed(_capture.get_buffer(n))
	_hang -= delta
	_noise_cd -= delta
	speaking = _hang > 0.0
	for id in _peers:
		_play(id, delta)


## Microphone samples at the mix rate in; 16 kHz frames out. A box filter on the way down keeps
## the worst of the aliasing out.
func _feed(buf: PackedVector2Array) -> void:
	var step := AudioServer.get_mix_rate() / float(RATE)
	for s in buf:
		_acc += (s.x + s.y) * 0.5
		_acc_n += 1
		_phase += 1.0
		if _phase >= step:
			_phase -= step
			_frame.append(_acc / _acc_n)
			_acc = 0.0
			_acc_n = 0
			if _frame.size() >= FRAME:
				_send_frame(_frame)
				_frame = PackedFloat32Array()


## Tests (and anything synthetic) can feed 16 kHz samples straight in.
func inject(samples16k: PackedFloat32Array) -> void:
	for s in samples16k:
		_frame.append(s)
		if _frame.size() >= FRAME:
			_send_frame(_frame)
			_frame = PackedFloat32Array()


func _send_frame(f: PackedFloat32Array) -> void:
	var gain := float(Settings.v.get("mic_gain", 1.0))
	var sum := 0.0
	for i in f.size():
		f[i] = clampf(f[i] * gain, -1.0, 1.0)
		sum += f[i] * f[i]
	var rms := sqrt(sum / f.size())
	level = lerpf(level, clampf(rms * 6.0, 0.0, 1.0), 0.5)
	var ptt := int(Settings.v.get("voice_mode", 0)) == 1
	var open: bool = Input.is_action_pressed("push_to_talk") if ptt and InputMap.has_action("push_to_talk") else rms > float(Settings.v.get("voice_gate", 0.02))
	if open:
		_hang = 0.06 if ptt else 0.35   # open mic: keep the gate open between words
	if _hang <= 0.0:
		return
	if not net:
		return
	net.send_voice(encode(f))
	if rms > 0.06 and _noise_cd <= 0.0 and main and is_instance_valid(main) and main.player and not main.player.dead:
		_noise_cd = 0.5
		main.noise(main.player.global_position + Vector3(0, 1.5, 0), 6.0 + rms * 90.0)   # shouting carries


# --- mu-law ------------------------------------------------------------------------------------

static func _tables() -> void:
	if not _decode_table.is_empty():
		return
	_decode_table.resize(256)
	for b in 256:
		var u := ~b & 0xFF
		var sgn := -1.0 if u & 0x80 else 1.0
		var e := (u >> 4) & 0x07
		var m := u & 0x0F
		var mag := (((m << 3) + 0x84) << e) - 0x84
		_decode_table[b] = sgn * mag / 32768.0
	_encode_table.resize(65536 >> 2)   # 14-bit magnitude -> code (sign added after)
	for i in _encode_table.size():
		var x := (i << 2) + 0x84
		var e := 7
		var mask := 0x4000
		while e > 0 and not (x & mask):
			e -= 1
			mask >>= 1
		var m := (x >> (e + 3)) & 0x0F
		_encode_table[i] = (e << 4) | m


static func encode(f: PackedFloat32Array) -> PackedByteArray:
	_tables()
	var out := PackedByteArray()
	out.resize(f.size())
	for i in f.size():
		var v := int(clampf(f[i], -1.0, 1.0) * 32635.0)
		var sgn := 0x80 if v < 0 else 0
		var mag := absi(v)
		out[i] = ~(sgn | _encode_table[mini(mag >> 2, _encode_table.size() - 1)]) & 0xFF
	return out


static func decode(b: PackedByteArray) -> PackedFloat32Array:
	_tables()
	var out := PackedFloat32Array()
	out.resize(b.size())
	for i in b.size():
		out[i] = _decode_table[b[i]]
	return out


# --- hearing others ------------------------------------------------------------------------------

func add_peer(id: int) -> void:
	if _peers.has(id):
		return
	var p := AudioStreamPlayer3D.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.3
	p.stream = gen
	p.bus = "Voice"
	p.unit_size = 4.0
	p.max_distance = 32.0
	p.attenuation_filter_cutoff_hz = 20500.0
	p.attenuation_filter_db = 0.0
	p.panning_strength = 1.0
	add_child(p)
	_peers[id] = {"player": p, "queue": [], "started": false, "occ_t": 0.0, "db": 0.0, "cut": 20500.0, "pup": null, "frames": 0}


func remove_peer(id: int) -> void:
	if _peers.has(id):
		_peers[id].player.queue_free()
		_peers.erase(id)


## Their voice comes out of their helmet from now on.
func attach_puppet(id: int, pup: Node3D) -> void:
	add_peer(id)
	_peers[id].pup = pup


func receive(id: int, bytes: PackedByteArray) -> void:
	add_peer(id)
	var p: Dictionary = _peers[id]
	p.queue.append(decode(bytes))
	p.frames += 1
	while p.queue.size() > MAX_QUEUE:
		p.queue.pop_front()


## Frames received from a peer (tests).
func frames_from(id: int) -> int:
	return _peers.get(id, {}).get("frames", 0)


func _play(id: int, delta: float) -> void:
	var p: Dictionary = _peers[id]
	var player: AudioStreamPlayer3D = p.player
	var pup = p.pup
	if pup == null or not is_instance_valid(pup) or not pup.is_inside_tree():
		p.queue.clear()
		return
	player.global_position = pup.head.global_position if "head" in pup and pup.head else pup.global_position + Vector3(0, 1.6, 0)
	p.occ_t -= delta
	if p.occ_t <= 0.0:
		p.occ_t = 0.1
		var o := _occlusion(pup)
		p.db = o[0]
		p.cut = o[1]
	player.volume_db = lerpf(player.volume_db, p.db + linear_to_db(maxf(float(Settings.v.get("voice_vol", 1.0)), 0.0001)), minf(1.0, delta * 10.0))
	player.attenuation_filter_cutoff_hz = lerpf(player.attenuation_filter_cutoff_hz, p.cut, minf(1.0, delta * 10.0))
	if not p.started:
		if p.queue.size() >= START_AT:
			p.started = true
			player.play()
		else:
			return
	if not player.playing:
		player.play()
	var pb := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	while not p.queue.is_empty() and pb.get_frames_available() >= FRAME:
		var f: PackedFloat32Array = p.queue.pop_front()
		var st := PackedVector2Array()
		st.resize(f.size())
		for i in f.size():
			st[i] = Vector2(f[i], f[i])
		pb.push_buffer(st)
	if p.queue.is_empty() and pb.get_frames_available() > FRAME * 10:
		p.started = false   # ran dry: buffer up again before restarting


## [volume dB, low-pass cutoff Hz] for a voice reaching you from this puppet.
func _occlusion(pup) -> Array:
	if main == null or not is_instance_valid(main) or main.player == null or pup.dead:
		return [-80.0, 20500.0]
	var ear: Vector3 = main.player.cam.global_position
	var mouth: Vector3 = pup.head.global_position
	var space: PhysicsDirectSpaceState3D = main.player.get_world_3d().direct_space_state
	var walls := 0
	var from := ear
	for i in 3:   # count the solid things between you
		var q := PhysicsRayQueryParameters3D.create(from, mouth, 1, [main.player.get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		walls += 1
		from = hit.position + (mouth - ear).normalized() * 0.45   # step through it (walls are ~0.3 thick)
	if walls == 0:
		return [0.0, 20500.0]
	# Is there a way round (a doorway, the stairs)? Then you hear it round the corner.
	var fac = main.level.facility if main.level != null else null
	if fac != null and fac.nav != null:
		var path: PackedVector3Array = fac.nav_path(main.player.global_position, pup.global_position)
		if path.size() >= 2:
			var length := 0.0
			for i in path.size() - 1:
				length += path[i].distance_to(path[i + 1])
			var straight := ear.distance_to(mouth)
			if path[-1].distance_to(pup.global_position) < 1.5 and length < 28.0 and length < straight * 2.2 + 4.0:
				var extra := length - straight
				return [-4.0 - extra * 0.7, clampf(4200.0 - extra * 260.0, 900.0, 4200.0)]
	if walls == 1:
		return [-20.0, 520.0]   # through a wall: a dull murmur
	return [-80.0, 300.0]       # two walls or more: nothing
