# The startup sequence, played by the launcher (src/updater.gd). An old CRT terminal powers on and
# reports in (the update check is its own lines: dispatch, new orders, the download), then the
# screen clears, a single amber line runs across the dark drawing DOWNLINE as it passes, and splits
# into a pair of rails under it with the sleepers ticking in. The full run plays the first time
# and after an update; otherwise a quicker one. Any key hurries it along.
#
# All of it is made here, sounds included, and it loads none of the game's scripts: whatever the
# launcher loads stays the exe's own version even once an update pack goes in over it.
extends Control

signal done

const AMBER := Color(1.0, 0.62, 0.22)
const DIM := Color(0.62, 0.55, 0.45)
const INK := Color(0.95, 0.93, 0.88)
const SOOT := Color(0.055, 0.05, 0.045)
const LEAD := 22     # labels are dotted out to this many characters
const RATE := 22050

# DOWNLINE as strokes in a 1-high cell (y down). Most start at the bottom, so they grow up off the rail.
const GLYPHS := {
	"D": [[Vector2(0, 1), Vector2(0, 0), Vector2(0.42, 0), Vector2(0.7, 0.28), Vector2(0.7, 0.72), Vector2(0.42, 1), Vector2(0, 1)]],
	"O": [[Vector2(0.22, 1), Vector2(0, 0.78), Vector2(0, 0.22), Vector2(0.22, 0), Vector2(0.48, 0), Vector2(0.7, 0.22), Vector2(0.7, 0.78), Vector2(0.48, 1), Vector2(0.22, 1)]],
	"W": [[Vector2(0, 0), Vector2(0.15, 1), Vector2(0.35, 0.4), Vector2(0.55, 1), Vector2(0.7, 0)]],
	"N": [[Vector2(0, 1), Vector2(0, 0), Vector2(0.7, 1), Vector2(0.7, 0)]],
	"L": [[Vector2(0.56, 1), Vector2(0, 1), Vector2(0, 0)]],
	"I": [[Vector2(0.03, 1), Vector2(0.03, 0)]],
	"E": [[Vector2(0.64, 1), Vector2(0, 1), Vector2(0, 0), Vector2(0.64, 0)], [Vector2(0, 0.5), Vector2(0.5, 0.5)]],
}
const ADVANCE := {"D": 0.7, "O": 0.7, "W": 0.7, "N": 0.7, "L": 0.56, "I": 0.06, "E": 0.64}
const WORD := "DOWNLINE"
const TAGLINE := "R A I L N E T   F I E L D   S E R V I C E"

enum { POWER, TERM, LOGO, END }

var full := true
var _phase := POWER
var _t := 0.0          # time in this phase
var _clock := 0.0
var _lines: Array = []     # {key, label, status (null while it waits), typed, bar (-1, or 0..1), lead}
var _cur := 0
var _pause := 0.0
var _released := false
var _hold := 0.0
var _hurry := false
var _thud_at := -1.0
var _finished := false
var _quiet := false
var _mono := SystemFont.new()
var _crt: ShaderMaterial
var _snd := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mono.font_names = PackedStringArray(["Consolas", "Menlo", "DejaVu Sans Mono", "monospace"])
	_mono.font_weight = 700
	# The glass: curvature, scanlines, a fringe of colour, a vignette; it clears for the logo.
	var glass := ColorRect.new()
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glass)
	glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform sampler2D screen: hint_screen_texture, filter_linear;
uniform float amount = 1.0;
uniform float roll = 0.0;
void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	vec2 uv = SCREEN_UV + c * dot(c, c) * 0.16 * amount;
	float ab = 0.0016 * amount;
	vec3 col = vec3(texture(screen, uv + vec2(ab, 0.0)).r, texture(screen, uv).g, texture(screen, uv - vec2(ab, 0.0)).b);
	col *= mix(1.0, 0.8 + 0.2 * sin(FRAGCOORD.y * 2.1), amount);
	col += amount * 0.018 * smoothstep(0.06, 0.0, abs(fract(SCREEN_UV.y - roll) - 0.5));
	col *= mix(1.0, smoothstep(0.86, 0.28, length(c * vec2(1.0, 1.2))), amount * 0.8 + 0.2);
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) col = vec3(0.0);
	COLOR = vec4(col, 1.0);
}
"""
	_crt = ShaderMaterial.new()
	_crt.shader = sh
	glass.material = _crt
	_sounds()
	_play("power")


## A line of the boot log. status "" is a plain line; null means it waits until status() fills it in.
func line(key: String, label: String, status = "", lead := true, before := "") -> void:
	var l := {"key": key, "label": label, "status": status, "typed": 0.0, "bar": -1.0, "lead": lead and status != ""}
	var at := _lines.size()
	for i in _lines.size():
		if _lines[i].key == before and before != "":
			at = i
	_lines.insert(at, l)


func status(key: String, text: String, label := "") -> void:
	for l in _lines:
		if l.key == key:
			l.status = text
			l.lead = true
			l.bar = -1.0
			if label != "":
				l.label = label


func progress(key: String, frac: float, text: String) -> void:
	for l in _lines:
		if l.key == key:
			l.bar = frac
			l.label = text
			l.lead = true


## The launcher has settled (up to date, updated, or given up): the log can finish.
func release() -> void:
	_released = true


func hurry() -> void:
	_hurry = true
	if _phase == LOGO and _thud_at < 0.0:
		_t = _travel_end()


func _speed() -> float:
	return (1.0 if full else 1.8) * (4.0 if _hurry else 1.0)


func _process(delta: float) -> void:
	_clock += delta
	_t += delta * _speed()
	match _phase:
		POWER:
			if _t > 0.42:
				_phase = TERM
				_t = 0.0
				_play("hum")
		TERM:
			_term(delta * _speed())
		LOGO:
			_logo()
	_crt.set_shader_parameter("roll", fmod(_clock * 0.13, 1.0))
	_crt.set_shader_parameter("amount", 1.0 if _phase <= TERM else clampf(1.0 - _t / 0.7, 0.0, 1.0))
	queue_redraw()


func _term(dt: float) -> void:
	if _cur >= _lines.size():
		if _released:
			_hold += dt
			if _hold > 0.5:
				_phase = LOGO
				_t = 0.0
				_fade("hum")
				_play("swish")
		return
	var l: Dictionary = _lines[_cur]
	var n: int = l.label.length()
	if l.typed < n:
		var was := int(l.typed)
		l.typed = minf(l.typed + dt * (150.0 if l.lead or l.status == null else 260.0), n)
		if int(l.typed) / 3 != was / 3:
			_play("tick")
		return
	if l.status == null:
		return   # (waiting on the launcher)
	_pause += dt
	if l.status != "" and _pause < 0.1 + 0.05 * (_cur % 3):
		return
	_pause = 0.0
	if l.status != "":
		_play("beep")
	_cur += 1


# --- the logo -------------------------------------------------------------------------------------

func _geom() -> Dictionary:
	var h := clampf(size.y * 0.13, 40.0, 150.0)
	var g := logo_geom(h)
	g.left = (size.x - g.width) * 0.5
	g.top = size.y * 0.5 - h * 0.62
	return g


## The word's measures at letter height h (top-left at 0,0): the menu sizes its title by this.
static func logo_geom(h: float) -> Dictionary:
	var gap := h * 0.3
	var w := 0.0
	for ch in WORD:
		w += ADVANCE[ch] * h
	w += gap * (WORD.length() - 1)
	return {"h": h, "gap": gap, "width": w, "left": 0.0, "top": 0.0, "rail": h * 1.3, "lw": maxf(h * 0.075, 2.0)}


func _travel_end() -> float:
	return 0.25 + 1.3


func _logo() -> void:
	if _thud_at < 0.0 and _t >= _travel_end():
		_thud_at = _t
		_play("clang")
	var end := _thud_at + (1.5 if full else 0.8)
	if _thud_at >= 0.0 and _t > end - 0.45 and not _quiet:
		_quiet = true   # (everything still ringing fades rather than being cut off with the scene: a click)
		for k in _snd:
			_fade(k, 0.4 / _speed())
	if _thud_at >= 0.0 and _t > end and not _finished:
		_finished = true
		done.emit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SOOT)
	match _phase:
		POWER: _draw_power()
		TERM: _draw_term(1.0)
		LOGO:
			_draw_term(clampf(1.0 - _t / 0.3, 0.0, 1.0))
			_draw_logo()


func _draw_power() -> void:
	var c := size * 0.5
	if _t < 0.14:   # a dot that stretches into a line
		var u := _t / 0.14
		var w := size.x * 0.5 * u * u
		draw_rect(Rect2(c.x - w, c.y - 1.5, w * 2.0, 3.0), INK)
		draw_rect(Rect2(c.x - w, c.y - 8.0, w * 2.0, 16.0), Color(AMBER, 0.25))
	else:   # then opens to the whole screen, glowing, and settles
		var u := clampf((_t - 0.14) / 0.2, 0.0, 1.0)
		var hh := size.y * 0.5 * (1.0 - pow(1.0 - u, 3.0))
		draw_rect(Rect2(0, c.y - hh, size.x, hh * 2.0), Color(AMBER.lerp(INK, 0.5), 0.55 * (1.0 - u) + 0.04))


func _draw_term(alpha: float) -> void:
	if alpha <= 0.0:
		return
	var fs := int(clampf(size.y / 42.0, 13.0, 24.0))
	var lh := fs * 1.5
	var x := size.x * 0.09
	var y := size.y * 0.13
	for i in mini(_cur + 1, _lines.size()):
		var l: Dictionary = _lines[i]
		var label: String = l.label.left(int(l.typed))
		var txt := label
		var typed_all: bool = int(l.typed) >= l.label.length()
		if typed_all and l.lead:
			txt += " " + ".".repeat(maxi(LEAD - l.label.length(), 2))
			if l.bar >= 0.0:
				var k := int(l.bar * 20.0)
				txt += " [" + "#".repeat(k) + "-".repeat(20 - k) + "] %3d%%" % int(l.bar * 100.0)
			elif l.status == null:
				txt += " " + "|/-\\"[int(_clock * 10.0) % 4]
			elif i < _cur:
				txt += " " + l.status
		var col: Color = INK if l.key == "head" else AMBER
		if l.status is String and (l.status.begins_with("OFFLINE") or l.status.begins_with("FAILED") or l.status.begins_with("NEEDS")):
			col = Color(1.0, 0.4, 0.3) if i < _cur else col
		var p := Vector2(x, y + i * lh)
		draw_string_outline(_mono, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(col, 0.10 * alpha))
		draw_string(_mono, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, alpha))
		if i == mini(_cur, _lines.size() - 1) and int(_clock * 2.5) % 2 == 0:   # the cursor
			var cw := _mono.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_rect(Rect2(x + cw + 3, y + i * lh - fs * 0.8, fs * 0.55, fs * 0.95), Color(AMBER, 0.85 * alpha))


func _draw_logo() -> void:
	var g := _geom()
	var h: float = g.h
	var t0 := 0.25
	if _t < t0:
		return
	var u := clampf((_t - t0) / (_travel_end() - t0), 0.0, 1.0)
	var since := _t - _thud_at if _thud_at >= 0.0 else -1.0
	var split := 1.0 - pow(1.0 - clampf(since / 0.4, 0.0, 1.0), 3.0) if since >= 0.0 else 0.0
	draw_logo(self, Vector2(g.left, g.top), h, 1.0 - pow(1.0 - u, 2.4), split, exp(-since * 4.0) if since >= 0.0 else 0.0, g.left + h, 0.7)
	# Under it, the service's name.
	if since > 0.15:
		var fs := int(clampf(h * 0.17, 11.0, 24.0))
		var n := int(clampf((since - 0.15) / 0.5, 0.0, 1.0) * TAGLINE.length())
		var tw := _mono.get_string_size(TAGLINE, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_mono, Vector2(size.x * 0.5 - tw * 0.5, g.top + g.rail + h * 0.55), TAGLINE.left(n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DIM)


## DOWNLINE in strokes over its rails, drawn onto `ci` with the word's top-left at `at` (the menu's
## title draws it too). `run` 0..1: how far the line has come (each letter drawn in as it passes);
## `split` 0..1: the one line parting into two rails, sleepers ticking in; `flash`: a glow on top.
## The line starts `from` to the left of the word (and its tail draws in from there as the rails
## part), and the rails overhang the word by `over` letter heights each side.
static func draw_logo(ci: CanvasItem, at: Vector2, h: float, run: float, split: float, flash: float, from: float, over: float, alpha := 1.0) -> void:
	var g := logo_geom(h)
	var lw: float = g.lw
	var rail: float = at.y + g.rail
	var start: float = at.x - h * over
	var stop: float = at.x + g.width + h * over
	var head := lerpf(at.x - from, stop, run)
	var col := AMBER.lerp(INK, 0.15 + 0.5 * flash)
	col.a = alpha
	var x: float = at.x
	for ch in WORD:
		var adv: float = ADVANCE[ch] * h
		var p := clampf((head - x) / (adv + h * 1.1), 0.0, 1.0) if run < 1.0 else 1.0
		p = 1.0 - pow(1.0 - p, 2.0)
		if p > 0.0:
			for stroke in GLYPHS[ch]:
				var pts := PackedVector2Array()
				for q in stroke:
					pts.append(Vector2(x, at.y) + q * h)
				_glow_line(ci, _partial(pts, p), col, lw, 1.0 + flash)
		x += adv + g.gap
	var tail := lerpf(at.x - from, start, split)
	var tip := minf(head, stop)
	var s := h * 0.07 * split
	if split > 0.0:
		var step := h * 0.24
		var n := maxi(int((stop - start) / step), 1)
		for i in n + 1:
			if float(i) / n <= split * 1.15:
				var sx := start + i * step
				_glow_line(ci, PackedVector2Array([Vector2(sx, rail - s - lw * 0.9), Vector2(sx, rail + s + lw * 0.9)]), Color(col, col.a * 0.55), lw * 0.55, 0.6)
	for k in ([-1.0, 1.0] if split > 0.0 else [0.0]):
		_glow_line(ci, PackedVector2Array([Vector2(tail, rail + k * s), Vector2(tip, rail + k * s)]), col, lw * (0.7 if split > 0.0 else 1.0), 1.0 + flash)
	if run < 1.0:   # the bright point running ahead
		ci.draw_circle(Vector2(tip, rail), lw * 4.0, Color(AMBER, 0.12 * alpha))
		ci.draw_circle(Vector2(tip, rail), lw * 1.3, Color(INK, alpha))


static func _glow_line(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float, glow: float) -> void:
	if pts.size() < 2:
		return
	for layer in [[w * 3.6, 0.04], [w * 2.0, 0.12]]:   # (segment by segment: a wide polyline spikes at sharp corners)
		for i in pts.size() - 1:
			ci.draw_line(pts[i], pts[i + 1], Color(col, col.a * layer[1] * glow), layer[0], true)
	for i in pts.size() - 1:
		ci.draw_line(pts[i], pts[i + 1], col, w, true)
	for q in pts:   # (round joints)
		ci.draw_circle(q, w * 0.5, col)


## The first `frac` of a polyline, by length.
static func _partial(pts: PackedVector2Array, frac: float) -> PackedVector2Array:
	if frac >= 1.0:
		return pts
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var left := total * frac
	var out := PackedVector2Array([pts[0]])
	for i in pts.size() - 1:
		var d := pts[i].distance_to(pts[i + 1])
		if d >= left:
			out.append(pts[i].lerp(pts[i + 1], left / d) if d > 0.0 else pts[i + 1])
			break
		out.append(pts[i + 1])
		left -= d
	return out


# --- sound ----------------------------------------------------------------------------------------

func _sounds() -> void:
	var vol := 1.0
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		vol = float(cf.get_value("settings", "vol_master", 1.0))
	var db := linear_to_db(maxf(vol, 0.0001))
	for k in ["power", "hum", "tick", "beep", "swish", "clang"]:
		var p := AudioStreamPlayer.new()
		p.stream = _wav(call("_s_" + k), k == "hum")
		p.volume_db = db + {"power": -4.0, "hum": -16.0, "tick": -14.0, "beep": -20.0, "swish": -8.0, "clang": -3.0}[k]
		p.max_polyphony = 6 if k == "tick" else 1
		add_child(p)
		_snd[k] = p


func _play(k: String) -> void:
	var p: AudioStreamPlayer = _snd.get(k)
	if p:
		p.pitch_scale = randf_range(0.85, 1.2) if k == "tick" else 1.0
		p.play()


func _fade(k: String, secs := 0.5) -> void:
	var p: AudioStreamPlayer = _snd.get(k)
	if p and p.playing:
		create_tween().tween_property(p, "volume_db", -80.0, secs)


func _wav(s: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	var b := PackedByteArray()
	b.resize(s.size() * 2)
	for i in s.size():
		b.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	w.data = b
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = s.size()
	return w


static func _buf(secs: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(secs * RATE))
	return a


func _s_power() -> PackedFloat32Array:   # the set coming on: a thump, a crackle, the flyback's whine
	var a := _buf(0.7)
	for i in a.size():
		var t := float(i) / RATE
		a[i] = sin(TAU * 52.0 * t) * exp(-t * 8.0) * 0.9 + randf_range(-1, 1) * exp(-t * 16.0) * 0.25 \
			+ sin(TAU * 7600.0 * t) * 0.025 * exp(-t * 2.5)
	return a


func _s_hum() -> PackedFloat32Array:   # mains hum, a second of it looped
	var a := _buf(1.0)
	for i in a.size():
		var t := float(i) / RATE
		a[i] = sin(TAU * 50.0 * t) * 0.5 + sin(TAU * 100.0 * t) * 0.25 + sin(TAU * 150.0 * t) * 0.12
	return a


func _s_tick() -> PackedFloat32Array:   # a key
	var a := _buf(0.02)
	var last := 0.0
	for i in a.size():
		var n := randf_range(-1, 1)
		a[i] = (n - last) * exp(-float(i) / a.size() * 7.0) * 0.6
		last = n
	return a


func _s_beep() -> PackedFloat32Array:
	var a := _buf(0.05)
	for i in a.size():
		var t := float(i) / RATE
		a[i] = (1.0 if fmod(t * 1450.0, 1.0) < 0.5 else -1.0) * 0.3 * minf(1.0, (a.size() - i) / 200.0)
	return a


func _s_swish() -> PackedFloat32Array:   # air moving as the line runs, and a rail singing
	var a := _buf(1.4)
	var lp := 0.0
	for i in a.size():
		var u := float(i) / a.size()
		var t := float(i) / RATE
		lp += (randf_range(-1, 1) - lp) * lerpf(0.03, 0.35, u)
		a[i] = (lp * 0.9 + sin(TAU * t * lerpf(320.0, 880.0, u * u)) * 0.06) * pow(sin(PI * u), 1.5)
	return a


func _s_clang() -> PackedFloat32Array:   # the rails set down: a deep thud, then they ring
	var a := _buf(2.4)
	var freqs := [523.0, 1307.0, 2462.0, 3871.0]
	var decays := [2.2, 3.2, 4.6, 6.5]
	var amps := [0.2, 0.12, 0.07, 0.04]
	for i in a.size():
		var t := float(i) / RATE
		var v := sin(TAU * 46.0 * t) * exp(-t * 3.5) * 0.85
		for k in 4:
			v += sin(TAU * freqs[k] * t) * amps[k] * exp(-t * decays[k])
		if t < 0.03:
			v += randf_range(-1, 1) * (1.0 - t / 0.03) * 0.5
		a[i] = v
	return a
