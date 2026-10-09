# Proximity voice. Your microphone is captured (a muted "Mic" bus with an AudioEffectCapture) and
# cleaned up before anyone hears it:
#   high-pass at 90 Hz (desk thumps, hum, the DC some mics carry)
#   a proper low-pass ahead of the resampler (three Butterworth stages), then resampled to 24 kHz
#   a noise gate with a 40 ms look-back (the first syllable isn't clipped) that fades in and out
#   smooth auto gain (quiet mics brought up to a speaking level, at most 4x) and a soft limiter
# then cut into 20 ms frames, sent as 16-bit PCM with a sequence number (open mic, or push-to-talk V).
# Each other player's voice goes through a jitter buffer that grows when the line is bumpy, fills
# lost frames with a fade of the last one, and plays from their helmet on a 3D player through the
# Voice bus (a touch of room, not the whole echo), fading with distance:
#   line of sight            clear
#   round a corner           a doorway between you: quieter and duller, with the extra distance
#   through a wall           heavily muffled; through two walls, gone
# Loud talking also carries to creatures that hunt by sound (main.noise), walls muffling it as usual.
extends Node

const Settings = preload("res://src/settings.gd")

const RATE := 24000
const FRAME := 480            # 20 ms at 24 kHz
const START_AT := 3           # frames buffered before a speaker starts (rides out network jitter)
const MAX_DELAY := 8          # the most the jitter buffer grows to (160 ms)
const LOOKBACK := 2           # frames kept from before the gate opened (the start of a word)
const TARGET_RMS := 0.11      # what the auto gain aims a speaking voice at
const MAX_AGC := 4.0

var net
var main
var speaking := false         # you, right now (the HUD and your pose show it)
var level := 0.0              # your mic level, 0..1 (the HUD meter)
var raw_level := 0.0          # your mic before the gate and auto gain (the settings meter, against the gate)
var _capture: AudioEffectCapture
var _mic: AudioStreamPlayer
var _mic_quiet := 0.0          # seconds the mic has delivered nothing while on
var mic_restarts := 0          # (how often the watchdog had to start it again)
var _hang := 0.0
var _noise_cd := 0.0
var _seq := 0
# Capture chain state.
var _hp_x := 0.0
var _hp_y := 0.0
var _lp := [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]   # three biquad stages: [z1, z2]
var _lp_coef := PackedFloat32Array()  # b0 b1 b2 a1 a2 for the mic's mix rate
var _lp_rate := 0.0
var _pos := 0.0               # resampler: where the next output sample falls between input samples
var _prev := 0.0              # the last filtered input sample
var _frame := PackedFloat32Array()
var _back: Array = []         # the last LOOKBACK frames, for when the gate opens
var _open := 0.0              # the gate's own smooth gain, 0..1
var _agc := 1.0
var _self: AudioStreamPlayer  # "hear yourself" in the settings: your own voice, as the crew gets it
# What the siren steals: short clips of what each of you has said (the host keeps them).
var clips := {}               # peer -> Array of PackedFloat32Array at RATE
var _rec := {}                # peer -> [samples so far, time of the last frame]
const CLIPS_EACH := 6
var _self_q: Array = []
var _peers := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_buses()
	_radio_bus()
	if DisplayServer.get_name() == "headless" or not ProjectSettings.get_setting("audio/driver/enable_input", false):
		return
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = "Mic"
	add_child(_mic)


## Start capturing again from scratch: a new microphone stream, an empty capture buffer.
func _restart_mic() -> void:
	_mic_quiet = 0.0
	_mic.stop()
	_mic.stream = AudioStreamMicrophone.new()
	if _capture:
		_capture.clear_buffer()
	_mic.play()
	mic_restarts += 1


func _buses() -> void:
	if AudioServer.get_bus_index("Mic") < 0:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, "Mic")
		AudioServer.set_bus_mute(i, true)   # you don't hear yourself
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 1.0
		AudioServer.add_bus_effect(i, _capture)
	else:
		_capture = AudioServer.get_bus_effect(AudioServer.get_bus_index("Mic"), 0)
	if AudioServer.get_bus_index("Voice") < 0:
		var v := AudioServer.bus_count
		AudioServer.add_bus(v)
		AudioServer.set_bus_name(v, "Voice")
		AudioServer.set_bus_send(v, "Master")   # clean: its own small room, not the facility's whole echo
		var rev := AudioEffectReverb.new()   # (the Radio bus, below, is dry: it's in your ear)
		rev.room_size = 0.35
		rev.damping = 0.6
		rev.wet = 0.07
		rev.dry = 1.0
		AudioServer.add_bus_effect(v, rev)


func _radio_bus() -> void:
	if AudioServer.get_bus_index("Radio") < 0:
		var r := AudioServer.bus_count
		AudioServer.add_bus(r)
		AudioServer.set_bus_name(r, "Radio")
		AudioServer.set_bus_send(r, "Master")


## Start or stop listening to the microphone (only while in a session and it's on, or while you
## test it in the settings).
func _want_mic() -> bool:
	if bool(Settings.v.get("mic_test", false)):
		return true
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
			_mic_quiet = 0.0
		else:
			_mic_quiet += delta
		# The mic can stop delivering after the game freezes for a while (a station being built,
		# a run being loaded) while it's on: then nobody hears you again. If it goes silent, or
		# after any long stall, start it afresh.
		if _mic_quiet > 0.6 or delta > 0.35:
			_restart_mic()
	_hang -= delta
	_noise_cd -= delta
	speaking = _hang > 0.0
	for id in _peers:
		_play(id, delta)
	_play_self()
	_close_clips()


# --- capture -------------------------------------------------------------------------------------

## Butterworth low-pass (three of them in a row, 9.6 kHz) under the new Nyquist, for this mix rate.
func _design(rate: float) -> void:
	_lp_rate = rate
	var fc := minf(RATE * 0.4, rate * 0.4)
	var w := TAU * fc / rate
	var cw := cos(w)
	var alpha := sin(w) / (2.0 * 0.7071)
	var a0 := 1.0 + alpha
	_lp_coef = PackedFloat32Array([(1.0 - cw) / 2.0 / a0, (1.0 - cw) / a0, (1.0 - cw) / 2.0 / a0, -2.0 * cw / a0, (1.0 - alpha) / a0])


## Microphone samples at the mix rate in; clean 24 kHz frames out.
func _feed(buf: PackedVector2Array) -> void:
	for v in filter_only(buf, AudioServer.get_mix_rate()):
		_frame.append(v)
		if _frame.size() >= FRAME:
			_send_frame(_frame)
			_frame = PackedFloat32Array()


## The capture chain without the gate: high-pass, anti-alias low-pass, resampled to RATE.
func filter_only(buf: PackedVector2Array, rate: float) -> PackedFloat32Array:
	if rate != _lp_rate:
		_design(rate)
	var out := PackedFloat32Array()
	out.resize(int(buf.size() * RATE / rate) + 2)
	var n := 0
	var b0: float = _lp_coef[0]
	var b1: float = _lp_coef[1]
	var b2: float = _lp_coef[2]
	var a1: float = _lp_coef[3]
	var a2: float = _lp_coef[4]
	var hp_k := exp(-TAU * 90.0 / rate)
	var step := rate / float(RATE)
	# (the filter state in plain locals for speed; written back at the end)
	var hx := _hp_x
	var hy := _hp_y
	var z10: float = _lp[0][0]
	var z11: float = _lp[0][1]
	var z20: float = _lp[1][0]
	var z21: float = _lp[1][1]
	var z30: float = _lp[2][0]
	var z31: float = _lp[2][1]
	var pos := _pos
	var prev := _prev
	for s in buf:
		var x := (s.x + s.y) * 0.5
		hy = hp_k * (hy + x - hx)   # high-pass, one pole
		hx = x
		# The anti-alias low-pass: three biquads, transposed direct form II.
		var o := b0 * hy + z10
		z10 = b1 * hy - a1 * o + z11
		z11 = b2 * hy - a2 * o
		var o2 := b0 * o + z20
		z20 = b1 * o - a1 * o2 + z21
		z21 = b2 * o - a2 * o2
		var y := b0 * o2 + z30
		z30 = b1 * o2 - a1 * y + z31
		z31 = b2 * o2 - a2 * y
		# Resample: every output sample sits between the previous input and this one.
		while pos <= 1.0:
			if n >= out.size():
				out.resize(n + 64)
			out[n] = lerpf(prev, y, pos)
			n += 1
			pos += step
		pos -= 1.0
		prev = y
	_hp_x = hx
	_hp_y = hy
	_lp = [[z10, z11], [z20, z21], [z30, z31]]
	_pos = pos
	_prev = prev
	out.resize(n)
	return out


## Tests (and anything synthetic) can feed samples at RATE straight in.
func inject(samples: PackedFloat32Array) -> void:
	for s in samples:
		_frame.append(s)
		if _frame.size() >= FRAME:
			_send_frame(_frame)
			_frame = PackedFloat32Array()


func _send_frame(f: PackedFloat32Array) -> void:
	var gain := float(Settings.v.get("mic_gain", 1.0))
	var sum := 0.0
	for i in f.size():
		f[i] *= gain
		sum += f[i] * f[i]
	var rms := sqrt(sum / f.size())
	raw_level = lerpf(raw_level, rms, 0.5)
	var ptt := int(Settings.v.get("voice_mode", 0)) == 1
	var gate := float(Settings.v.get("voice_gate", 0.008))
	var talk: bool = Input.is_action_pressed("push_to_talk") if ptt and InputMap.has_action("push_to_talk") \
		else (rms > gate or (_hang > 0.0 and rms > gate * 0.55))   # (a lower bar to stay open than to open)
	var was := _hang > 0.0
	if talk:
		_hang = 0.08 if ptt else 0.45   # open mic: hold the gate open between words
	_back.append(f)
	while _back.size() > LOOKBACK + 1:
		_back.pop_front()
	if _hang <= 0.0 and _open <= 0.0:
		level = lerpf(level, 0.0, 0.5)
		return
	var out: Array = [f]
	if talk and not was:   # just opened: send what came before too, so the word starts whole
		out = _back.duplicate()
	for raw in out:
		var fr := _shape(raw, _hang > 0.0)
		level = lerpf(level, clampf(rms * _agc * 6.0, 0.0, 1.0), 0.5)
		if bool(Settings.v.get("mic_test", false)):
			_self_q.append(fr.duplicate())
			while _self_q.size() > MAX_DELAY:
				_self_q.pop_front()
		_record(net.me() if net != null else 1, fr)
		if net:
			var radio: bool = main != null and is_instance_valid(main) and main.player != null and main.player.transmitting()
			net.send_voice(packet(_seq, fr, 1 if radio else 0))
		_seq = (_seq + 1) & 0xFFFF
	if rms > 0.06 and _noise_cd <= 0.0 and main and is_instance_valid(main) and main.player and not main.player.dead:
		_noise_cd = 0.5
		main.noise(main.player.global_position + Vector3(0, 1.5, 0), 6.0 + rms * 90.0)   # shouting carries


## The gate's fade, the auto gain (eased sample by sample, no steps) and a soft limiter.
func _shape(src: PackedFloat32Array, open: bool) -> PackedFloat32Array:
	var f := src.duplicate()
	var sum := 0.0
	for v in f:
		sum += v * v
	var rms := sqrt(sum / f.size())
	var want := _agc
	if open and rms > 0.003:   # only learn from speech, never from the hiss between words
		want = clampf(TARGET_RMS / rms, 1.0, MAX_AGC)
	var g0 := _agc
	_agc = lerpf(_agc, want, 0.06 if want > _agc else 0.35)   # up slowly, down quickly
	var o0 := _open
	_open = 1.0 if open else maxf(0.0, _open - 0.34)   # opens at once (after the look-back), closes over ~60 ms
	var n := f.size()
	for i in n:
		var k := float(i) / n
		var v: float = f[i] * lerpf(g0, _agc, k) * lerpf(o0, _open, k)
		f[i] = v if absf(v) < 0.6 else signf(v) * (0.6 + 0.4 * tanh((absf(v) - 0.6) / 0.4))   # soft knee into the limit
	return f


# --- the wire ------------------------------------------------------------------------------------

## A frame on the wire: its sequence number, flags (1 = over the radio), then 16-bit samples.
static func packet(seq: int, f: PackedFloat32Array, flags := 0) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(3)
	b.encode_u16(0, seq)
	b[2] = flags
	b.append_array(encode(f))
	return b


static func encode(f: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(f.size() * 2)
	for i in f.size():
		out.encode_s16(i * 2, int(clampf(f[i], -1.0, 1.0) * 32767.0))
	return out


static func decode(b: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(b.size() / 2)
	for i in out.size():
		out[i] = b.decode_s16(i * 2) / 32767.0
	return out


## The settings' "hear yourself": your voice after all of the above, through the same coding the
## crew gets, played flat in your own ears.
func _play_self() -> void:
	if not bool(Settings.v.get("mic_test", false)):
		if _self and _self.playing:
			_self.stop()
		_self_q.clear()
		return
	if _self == null:
		_self = AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = RATE
		gen.buffer_length = 0.3
		_self.stream = gen
		add_child(_self)
	if not _self.playing:
		_self.play()
	var pb := _self.get_stream_playback() as AudioStreamGeneratorPlayback
	while pb != null and not _self_q.is_empty() and pb.get_frames_available() >= FRAME:
		_push(pb, decode(encode(_self_q.pop_front())))


static func _push(pb: AudioStreamGeneratorPlayback, f: PackedFloat32Array) -> void:
	var st := PackedVector2Array()
	st.resize(f.size())
	for i in f.size():
		st[i] = Vector2(f[i], f[i])
	pb.push_buffer(st)


# --- hearing others ------------------------------------------------------------------------------

func add_peer(id: int) -> void:
	if _peers.has(id):
		return
	var p := AudioStreamPlayer3D.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.5
	p.stream = gen
	p.bus = "Voice"
	p.unit_size = 5.0
	p.max_distance = 40.0
	p.attenuation_filter_cutoff_hz = 20500.0
	p.attenuation_filter_db = 0.0
	p.panning_strength = 0.8
	add_child(p)
	_peers[id] = {"player": p, "frames_in": {}, "next": -1, "delay": START_AT, "last": PackedFloat32Array(), "lost": 0,
		"occ_t": 0.0, "db": 0.0, "cut": 20500.0, "pup": null, "frames": 0, "queue": [], "cap": 0, "fills": 0,
		"radio": null, "radio_in": {}, "was_radio": false, "rf": [0.0, 0.0, 0.0], "radio_frames": 0, "played": 0, "last_rx": 0, "resyncs": 0}


func remove_peer(id: int) -> void:
	if _peers.has(id):
		_peers[id].player.queue_free()
		if _peers[id].radio != null:
			_peers[id].radio.queue_free()
		_peers.erase(id)


## Their voice comes out of their helmet from now on.
func attach_puppet(id: int, pup: Node3D) -> void:
	add_peer(id)
	_peers[id].pup = pup


func receive(id: int, bytes: PackedByteArray) -> void:
	if bytes.size() < 5:
		return
	add_peer(id)
	var p: Dictionary = _peers[id]
	var seq := bytes.decode_u16(0)
	p.frames += 1
	p.last_rx = Time.get_ticks_msec()
	if p.next >= 0 and _behind(seq, p.next):
		return   # too late: that moment has already played
	p.frames_in[seq] = decode(bytes.slice(3))
	_record(id, p.frames_in[seq])
	if bytes[2] & 1:
		p.radio_in[seq] = true
	if p.frames_in.size() > MAX_DELAY * 3:   # (a stall: drop the oldest)
		var keys: Array = p.frames_in.keys()
		keys.sort_custom(func(a, b): return _behind(a, b))
		p.frames_in.erase(keys[0])
	p.queue = p.frames_in.keys()   # (how many are waiting: tests and the HUD read its size)


## Has anything arrived after sequence number `seq`?
static func _ahead_of(waiting: Dictionary, seq: int) -> bool:
	for k in waiting:
		if _behind(seq, k):
			return true
	return false


## Is sequence number a before b (wrapping at 65536)?
static func _behind(a: int, b: int) -> bool:
	return ((b - a) & 0xFFFF) < 0x8000 and a != b


## Frames received from a peer (tests).
func frames_from(id: int) -> int:
	return _peers.get(id, {}).get("frames", 0)


func _play(id: int, delta: float) -> void:
	var p: Dictionary = _peers[id]
	var player: AudioStreamPlayer3D = p.player
	var pup = p.pup
	if pup == null or not is_instance_valid(pup) or not pup.is_inside_tree():
		p.frames_in.clear()
		p.queue = []
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
	var waiting: Dictionary = p.frames_in
	if p.next >= 0 and not waiting.is_empty():
		# Keep in step with what's arriving. Frames older than where we are can never play: throw
		# them out (they'd hold the buffer in "a frame went missing, skip it" forever). And if we've
		# drifted away from what they're sending, ahead or behind (after the game froze for a few
		# seconds, say), start again from what's here.
		for k in waiting.keys():
			if _behind(k, p.next):
				waiting.erase(k)
		var newest := -1
		for k in waiting.keys():
			if newest < 0 or _behind(newest, k):
				newest = k
		if newest >= 0 and ((newest - p.next) & 0xFFFF) > MAX_DELAY * 3:
			p.next = -1
			p.resyncs += 1
	if p.next < 0:   # idle: start once enough has arrived to ride out the jitter
		if waiting.size() < p.delay:
			return
		var keys: Array = waiting.keys()
		keys.sort_custom(func(a, b): return _behind(a, b))
		p.next = keys[0]
		p.lost = 0
	if not player.playing:
		player.play()
	var pb := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	if p.cap == 0:
		p.cap = pb.get_frames_available()   # (its ring buffer, empty: the real size, rounded up by Godot)
	var cap: int = p.cap
	var queued: int = cap - pb.get_frames_available()
	# Pull in what has arrived, in order, while the player has room for it.
	for guard in MAX_DELAY * 3:
		if waiting.size() > MAX_DELAY * 2:   # (their clock runs a hair fast, or a burst: drop the oldest)
			p.next = (p.next + 1) & 0xFFFF
			continue
		if waiting.has(p.next) and queued < FRAME * (p.delay + 2):
			var f: PackedFloat32Array = waiting[p.next]
			waiting.erase(p.next)
			if p.lost > 0:   # back after a gap: ease in from where the fill left off
				var from: float = p.last[p.last.size() - 1] if not p.last.is_empty() else 0.0
				for i in 120:
					var k := i / 120.0
					f[i] = lerpf(from, f[i], k * k)
			_push(pb, f)
			p.played += 1
			_radio_push(p, f, p.radio_in.has(p.next))
			p.radio_in.erase(p.next)
			queued += FRAME
			p.last = f
			p.lost = 0
			p.next = (p.next + 1) & 0xFFFF
			continue
		if queued >= FRAME:   # it has enough to play on: wait for the next frame to arrive
			break
		# About to run dry and the next frame isn't here.
		if waiting.is_empty() and p.lost > 0:   # they've stopped talking: go quiet
			p.next = -1
			p.delay = maxi(START_AT, p.delay - 1)   # (a smooth run: the buffer shrinks back)
			break
		# Lost, late, or the end of a sentence: carry on from the last sample and settle smoothly
		# to silence (no step, so no click), and skip that frame if it was lost.
		var last: PackedFloat32Array = p.last
		var s0: float = last[last.size() - 1] if not last.is_empty() else 0.0
		var fill := PackedFloat32Array()
		fill.resize(FRAME)
		for i in FRAME:
			fill[i] = s0 * exp(-i / 30.0)
		_push(pb, fill)
		_radio_push(p, fill, false)
		queued += FRAME
		p.last = fill
		p.lost += 1
		p.fills += 1
		if _ahead_of(waiting, p.next):   # a frame really went missing (later ones are here): skip it, and hold more back
			p.next = (p.next + 1) & 0xFFFF
			if p.lost == 1:
				p.delay = mini(MAX_DELAY, p.delay + 1)
		if p.lost > 6:   # the line went quiet
			p.next = -1
			break
	p.queue = waiting.keys()


# --- clips for the siren ----------------------------------------------------------------------------

## Keep what someone says (the host only: it runs the creatures).
func _record(peer: int, f: PackedFloat32Array) -> void:
	if net != null and not net.authority():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not _rec.has(peer):
		_rec[peer] = [PackedFloat32Array(), now]
	_rec[peer][0].append_array(f)
	_rec[peer][1] = now
	if _rec[peer][0].size() > RATE * 5:   # (long enough: close it here)
		_rec[peer][1] = -99.0


## A pause ends a phrase: keep it if it was a real one (most of a second to five seconds).
func _close_clips() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for peer in _rec.keys():
		if now - _rec[peer][1] < 0.45:
			continue
		var s: PackedFloat32Array = _rec[peer][0]
		_rec.erase(peer)
		if s.size() < RATE * 0.7:
			continue
		if not clips.has(peer):
			clips[peer] = []
		clips[peer].append(s.slice(0, RATE * 5))
		while clips[peer].size() > CLIPS_EACH:
			clips[peer].pop_front()


## One of the crew's phrases, any of them (empty if nobody has said anything yet).
func random_clip() -> PackedFloat32Array:
	var all: Array = []
	for peer in clips:
		all.append_array(clips[peer])
	return all[randi() % all.size()] if not all.is_empty() else PackedFloat32Array()


# --- the radio ------------------------------------------------------------------------------------

## The walkie in your pocket, in step with their voice: each frame they sent over the radio comes
## out of it (if you carry a charged walkie), band-limited, a little overdriven, hissing, with a
## squelch burst as they key up and let go; every other frame is silence, so the two stay in step.
func _radio_push(p: Dictionary, f: PackedFloat32Array, radio: bool) -> void:
	var hear: bool = radio and main != null and is_instance_valid(main) and main.player != null and main.player.has_radio()
	if p.radio == null:
		if not hear:
			p.was_radio = false
			return
		var r := AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = RATE
		gen.buffer_length = 0.5
		r.stream = gen
		r.bus = "Radio"
		add_child(r)
		r.play()
		p.radio = r
	var pb := (p.radio as AudioStreamPlayer).get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var out := PackedFloat32Array()
	out.resize(FRAME)
	var st: Array = p.rf
	var key_up: bool = hear and not p.was_radio
	var let_go: bool = not hear and p.was_radio
	for i in FRAME:
		var x: float = f[i] if hear else 0.0
		st[1] = 0.93 * (st[1] + x - st[0])   # high-pass (~ 400 Hz)
		st[0] = x
		st[2] += (st[1] - st[2]) * 0.42       # low-pass (~ 3 kHz)
		var y: float = tanh(st[2] * 2.6) * 0.55
		if hear:
			y += randf_range(-1.0, 1.0) * 0.012   # the carrier's hiss
		if (key_up and i < 1100) or (let_go and i < 1700):   # squelch: a burst of static
			y += randf_range(-1.0, 1.0) * 0.18 * (1.0 - float(i) / (1100.0 if key_up else 1700.0))
		out[i] = y
	_push(pb, out)
	if hear:
		p.radio_frames += 1
	p.was_radio = hear


## [volume dB, low-pass cutoff Hz] for a voice reaching you from this puppet.
func _occlusion(pup) -> Array:
	if (main == null or not is_instance_valid(main)) and net != null:
		main = net.main
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
	if ear.y > main.UNDERGROUND_Y and mouth.y > main.UNDERGROUND_Y:
		# Outdoors (and aboard): a post, a rock, a dune or a carriage wall in the way muffles a voice
		# a little; it never cuts it off. (Counted as walls, they used to silence the whole crew
		# once it reached a station.)
		return [-3.0 * mini(walls, 2), 6500.0 if walls == 1 else 3000.0]
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
