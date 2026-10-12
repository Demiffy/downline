# The shift report: when the quota's met at a checkpoint, a Bureau form is slapped up at the side of
# the visor for the whole crew (net event "report"). Torn off a pad (a perforated top, punch holes,
# grain, a fold, somebody's coffee ring); the Bureau seal and FORM 27-B; the shift's figures typed
# into a ruled table; a gauge filling past the quota line; the crew's last photograph paper-clipped
# to the corner; the supervisor's scrawl; a barcode. Then the grade comes down: a round inked seal,
# lettered round its rim, struck crooked with a thud that jolts the sheet and spatters ink.
# Shredding more and climbing a rank stamps it again. It goes by itself.
extends CanvasLayer

const Sfx = preload("res://src/sfx.gd")

const PAPER := Color(0.91, 0.87, 0.77)
const INK := Color(0.13, 0.12, 0.11)
const FADED := Color(0.13, 0.12, 0.11, 0.55)
const RED := Color(0.74, 0.08, 0.06)
const W := 440.0
const H := 650.0
const GRADE_WORD := {"S": "EXEMPLARY", "A": "COMMENDED", "B": "APPROVED", "C": "ACCEPTED", "D": "SUBSTANDARD"}
const PAPER_SHADER := """
shader_type canvas_item;
uniform vec2 size = vec2(440.0, 650.0);
uniform vec4 paper : source_color = vec4(0.91, 0.87, 0.77, 1.0);
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 px = UV * size;
	// Torn off the pad: a perforated top edge.
	float tooth = abs(fract(px.x / 9.0) - 0.5) * 7.0;
	if (px.y < tooth) discard;
	// Punch holes.
	if (length(px - vec2(size.x * 0.3, 20.0)) < 7.0 || length(px - vec2(size.x * 0.7, 20.0)) < 7.0) discard;
	vec3 c = paper.rgb;
	c *= 0.93 + 0.07 * noise(px * 0.9) + 0.04 * (noise(px * 0.05) - 0.5);   // grain and blotch
	c *= 1.0 - 0.12 * smoothstep(0.35, 0.0, min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)) * 3.0);   // edges yellowed
	float crease = abs(px.y - size.y * 0.62);   // folded once
	c *= 1.0 - 0.07 * smoothstep(3.0, 0.0, crease) + 0.03 * smoothstep(8.0, 2.0, crease) * step(size.y * 0.62, px.y);
	float ring = abs(length(px - vec2(size.x * 0.18, size.y * 0.8)) - 38.0);   // a mug was put down on it
	c = mix(c, c * vec3(0.78, 0.62, 0.45), smoothstep(4.0, 0.5, ring) * 0.55 * (0.6 + 0.4 * noise(px * 0.3)));
	COLOR = vec4(c, 1.0);
}
"""
const INK_SHADER := """
shader_type canvas_item;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec4 t = texture(TEXTURE, UV) * COLOR;
	vec2 p = FRAGCOORD.xy;
	float n = noise(p * 0.35) * 0.6 + noise(p * 0.08) * 0.4;   // a rubber stamp never inks evenly
	t.a *= smoothstep(0.18, 0.42, n);
	COLOR = t;
}
"""

var main
var _card: Control
var _ink: Control       # the stamp (drawn, then worn by the ink shader)
var _mono := SystemFont.new()
var _type := SystemFont.new()
var _d: Array = []
var _reveal := 0.0      # 0..1: how much of the form's been typed
var _gauge := 0.0       # 0..1 of the gauge's travel
var _sign := 0.0        # the signature, written
var _splats: Array = [] # ink flung off the stamp [pos, radius]
var _tw: Tween
var _sig_pts := PackedVector2Array()


func _ready() -> void:
	layer = 15
	_mono.font_names = PackedStringArray(["Consolas", "Menlo", "DejaVu Sans Mono", "monospace"])
	_mono.font_weight = 700
	_type.font_names = PackedStringArray(["Courier New", "Courier", "Consolas", "monospace"])
	_type.font_weight = 700
	var rng := RandomNumberGenerator.new()   # the supervisor's scrawl, the same every time
	rng.seed = 27
	var x := 0.0
	for i in 60:
		x += rng.randf_range(1.5, 4.0)
		_sig_pts.append(Vector2(x, sin(i * 0.9) * rng.randf_range(4.0, 11.0) + rng.randf_range(-2.0, 2.0)))


## [assignment, place and time, items, value, % of quota, losses, crew size, grade, replacement fees, units banked]
func show_report(d: Array) -> void:
	_d = d
	if _tw:
		_tw.kill()
	if _card:
		_card.queue_free()
	_reveal = 0.0
	_gauge = 0.0
	_sign = 0.0
	_splats.clear()
	var vp := get_viewport().get_visible_rect().size
	var k := clampf(vp.y / 1080.0 * 1.12, 0.65, 1.5)
	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.size = Vector2(W, H)
	_card.pivot_offset = Vector2(W / 2.0, H / 2.0)
	_card.scale = Vector2.ONE * k
	add_child(_card)
	var shadow := ColorRect.new()   # cast on the visor glass
	shadow.color = Color(0, 0, 0, 0.4)
	shadow.size = Vector2(W, H)
	shadow.position = Vector2(10, 14)
	_card.add_child(shadow)
	var paper := ColorRect.new()
	paper.size = Vector2(W, H)
	var pm := ShaderMaterial.new()
	pm.shader = Shader.new()
	pm.shader.code = PAPER_SHADER
	paper.material = pm
	_card.add_child(paper)
	var face := Control.new()   # everything printed, typed and written on it
	face.size = Vector2(W, H)
	face.draw.connect(_draw_face.bind(face))
	_card.add_child(face)
	_card.set_meta("face", face)
	_clip_photo()
	var rest := Vector2(vp.x - W * k - 70.0 * k + (W * k - W) / 2.0, (vp.y - H) / 2.0 + 10.0)
	_card.position = rest + Vector2(0, vp.y)
	_card.rotation = deg_to_rad(9.0)
	_tw = create_tween()
	_tw.tween_callback(Sfx.play.bind(self, "rustle", null, -6.0))
	_tw.tween_property(_card, "position", rest, 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tw.parallel().tween_property(_card, "rotation", deg_to_rad(-2.0), 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tw.tween_method(_set_reveal, 0.0, 1.0, 1.8)
	_tw.tween_method(func(v: float): _gauge = v; face.queue_redraw(), 0.0, 1.0, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tw.tween_method(func(v: float): _sign = v; face.queue_redraw(), 0.0, 1.0, 0.7)
	_tw.tween_interval(0.25)
	_tw.tween_callback(stamp.bind(d[7]))
	_tw.tween_interval(8.0)
	_tw.tween_property(_card, "position", rest + Vector2(0, vp.y), 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tw.parallel().tween_property(_card, "rotation", deg_to_rad(-12.0), 0.6)
	_tw.tween_callback(func():
		_card.queue_free()
		_card = null)


func _set_reveal(v: float) -> void:
	if int(v * 60.0) != int(_reveal * 60.0):
		Sfx.play(self, "key", null, -18.0, randf_range(0.95, 1.3))   # the typewriter
	_reveal = v
	_card.get_meta("face").queue_redraw()


## The crew's latest photograph, clipped to the top corner.
func _clip_photo() -> void:
	var log: Array = main.photo_log if main and "photo_log" in main else []
	if log.is_empty() or not log.back().has("tex"):
		return
	var holder := Control.new()
	holder.position = Vector2(W - 112, 18)   # (hanging off the sheet's edge)
	holder.rotation = deg_to_rad(7.0)
	_card.add_child(holder)
	var border := ColorRect.new()
	border.color = Color(0.95, 0.94, 0.9)
	border.size = Vector2(140, 118)
	holder.add_child(border)
	var pic := TextureRect.new()
	pic.texture = log.back().tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.position = Vector2(7, 7)
	pic.size = Vector2(126, 94)
	holder.add_child(pic)
	var clip := Control.new()   # a paperclip over its top edge
	clip.draw.connect(func():
		var pts := PackedVector2Array([Vector2(52, 30), Vector2(52, -6), Vector2(60, -14), Vector2(68, -6), Vector2(68, 22), Vector2(62, 28), Vector2(57, 22), Vector2(57, 0)])
		clip.draw_polyline(pts, Color(0.62, 0.64, 0.66), 2.5, true)
		clip.draw_polyline(pts, Color(0.9, 0.92, 0.95, 0.6), 1.0, true))
	holder.add_child(clip)


func _draw_face(f: Control) -> void:
	if _d.is_empty():
		return
	var shown := _reveal * 14.0   # how many of the form's parts are typed yet
	# The Bureau seal: rails under a ring.
	var sc := Vector2(52, 74)
	f.draw_arc(sc, 26, 0, TAU, 40, INK, 2.0, true)
	f.draw_arc(sc, 21, 0, TAU, 40, INK, 1.0, true)
	f.draw_string(_mono, sc + Vector2(-17, 5), "BRM", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)
	for k in [-1.0, 1.0]:
		f.draw_line(sc + Vector2(-16, 12 + k * 2.0), sc + Vector2(16, 12 + k * 2.0), INK, 1.0)
	f.draw_string(_mono, Vector2(90, 58), "BUREAU OF RECLAIMED MATERIALS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, FADED)
	f.draw_string(_type, Vector2(88, 88), "SHIFT REPORT", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, INK)
	f.draw_string(_mono, Vector2(90, 106), "FORM 27-B  ·  FIELD ASSIGNMENT %02d" % int(_d[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, FADED)
	f.draw_string(_mono, Vector2(28, 140), "CONFIDENTIAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(RED, 0.8))
	f.draw_line(Vector2(24, 152), Vector2(W - 24, 152), INK, 2.0)
	# The figures: a ruled table, typed in one by one.
	var rows := [["LOCATION", str(_d[1])], ["SCRAP SHREDDED", "%d ITEMS" % int(_d[2])], ["VALUE RECLAIMED", "%d CR" % int(_d[3])],
		["CREW ON SHIFT", str(_d[6])], ["CREW LOST", str(_d[5])]]
	if _d.size() > 9:   # (newer reports: what the replacements cost, and the surplus banked)
		rows.append(["REPLACEMENT FEES", ("-%d CR" % int(_d[8])) if int(_d[8]) > 0 else "NIL"])
		rows.append(["SURPLUS TO STOCK", ("%d UNITS" % int(_d[9])) if int(_d[9]) > 0 else "NIL"])
	var y := 182.0
	for i in rows.size():
		if shown > i + 1:
			f.draw_string(_mono, Vector2(28, y), rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, FADED)
			var vtxt: String = rows[i][1]
			var chars := int(clampf((shown - i - 1) * 12.0, 0.0, vtxt.length()))
			f.draw_string(_type, Vector2(W - 28 - _type.get_string_size(vtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, y), vtxt.left(chars), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
		f.draw_line(Vector2(24, y + 9), Vector2(W - 24, y + 9), Color(INK, 0.18), 1.0)
		y += 30.0
	# The gauge: how far past the quota.
	y += 14.0
	f.draw_string(_mono, Vector2(28, y), "OF QUOTA", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, FADED)
	var pct := float(_d[4])
	f.draw_string(_type, Vector2(W - 90, y), "%d%%" % roundi(pct * _gauge), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
	var bar := Rect2(28, y + 12, W - 56, 16)
	f.draw_rect(bar, Color(INK, 0.08))
	var full := clampf(pct / 200.0, 0.0, 1.0) * _gauge
	f.draw_rect(Rect2(bar.position, Vector2(bar.size.x * full, bar.size.y)), Color(0.2, 0.42, 0.22) if pct >= 100.0 else Color(0.75, 0.45, 0.1))
	for t in 9:   # ticks every 25%
		var tx := bar.position.x + bar.size.x * t / 8.0
		f.draw_line(Vector2(tx, bar.end.y), Vector2(tx, bar.end.y + (6 if t % 2 == 0 else 3)), INK, 1.0)
	var qx := bar.position.x + bar.size.x * 0.5   # the quota line
	f.draw_line(Vector2(qx, bar.position.y - 5), Vector2(qx, bar.end.y + 5), RED, 2.0)
	f.draw_string(_mono, Vector2(qx - 18, bar.end.y + 20), "QUOTA", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(RED, 0.85))
	f.draw_rect(bar, INK, false, 1.0)
	# Signed off.
	var sy := H - 150.0
	f.draw_line(Vector2(28, sy), Vector2(200, sy), INK, 1.0)
	f.draw_string(_mono, Vector2(28, sy + 16), "FIELD SUPERVISOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, FADED)
	if _sign > 0.0:
		var n := int(_sig_pts.size() * _sign)
		if n > 1:
			var pts := PackedVector2Array()
			for i in n:
				pts.append(Vector2(40, sy - 14) + _sig_pts[i] * Vector2(0.95, 0.9))
			f.draw_polyline(pts, Color(0.12, 0.16, 0.36), 1.6, true)
	# A barcode and the form's serial.
	var bx := 28.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_d[0]) * 977 + int(_d[3])
	while bx < 190.0:
		var bw := rng.randi_range(1, 3)
		f.draw_rect(Rect2(bx, H - 64, bw, 34), INK)
		bx += bw + rng.randi_range(1, 3)
	f.draw_string(_mono, Vector2(28, H - 18), "No. %06d-%02d" % [rng.randi() % 1000000, int(_d[0])], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, FADED)
	# Ink flung off the stamp.
	for s in _splats:
		f.draw_circle(s[0], s[1], Color(RED, 0.8))


## The grade, struck: a round seal, lettered round its rim, the grade large in the middle.
func stamp(grade: String) -> void:
	if _card == null:
		return
	if _ink:
		_ink.queue_free()
	var face: Control = _card.get_meta("face")
	_ink = Control.new()
	_ink.size = Vector2(220, 220)
	_ink.pivot_offset = _ink.size / 2.0
	_ink.position = Vector2(W - 238, H - 250)
	_ink.rotation = deg_to_rad(randf_range(-22.0, -10.0))
	var im := ShaderMaterial.new()
	im.shader = Shader.new()
	im.shader.code = INK_SHADER
	_ink.material = im
	_ink.draw.connect(func():
		var c := _ink.size / 2.0
		var red := Color(RED, 0.92)
		_ink.draw_arc(c, 104, 0, TAU, 72, red, 6.0, true)
		_ink.draw_arc(c, 94, 0, TAU, 72, red, 2.0, true)
		_ink.draw_arc(c, 62, 0, TAU, 64, red, 2.5, true)
		var rim := "BUREAU OF RECLAIMED MATERIALS  ·  INSPECTED  ·  "   # round the rim
		for i in rim.length():
			var a := -PI / 2.0 + TAU * i / rim.length()
			_ink.draw_set_transform(c + Vector2(cos(a), sin(a)) * 78.0, a + PI / 2.0)
			_ink.draw_char(_mono, Vector2(-4, 5), rim[i], 13, red)
		_ink.draw_set_transform(Vector2.ZERO)
		var gs := _type.get_string_size(grade, HORIZONTAL_ALIGNMENT_LEFT, -1, 92)
		_ink.draw_string(_type, c + Vector2(-gs.x / 2.0, 30), grade, HORIZONTAL_ALIGNMENT_LEFT, -1, 92, red)
		var word: String = GRADE_WORD.get(grade, "")
		var ws := _mono.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		_ink.draw_rect(Rect2(c.x - ws.x / 2.0 - 8, c.y + 44, ws.x + 16, 20), red, false, 2.0)
		_ink.draw_string(_mono, c + Vector2(-ws.x / 2.0, 59), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, red))
	_card.add_child(_ink)
	_ink.scale = Vector2.ONE * 3.2
	_ink.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_ink, "scale", Vector2.ONE, 0.14).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_ink, "modulate:a", 1.0, 0.1)
	tw.chain().tween_callback(func():
		Sfx.play(self, "stamp", null, 3.0)
		if main and main.player:
			main.player.shake(0.035)
		var centre: Vector2 = _ink.position + _ink.size / 2.0
		for i in 14:   # spatter
			var a := randf() * TAU
			_splats.append([centre + Vector2(cos(a), sin(a)) * randf_range(108.0, 150.0), randf_range(1.0, 3.5)])
		face.queue_redraw()
		var r0 := _card.rotation   # the sheet jolts under the blow
		var j := create_tween()
		j.tween_property(_card, "rotation", r0 + deg_to_rad(-1.6), 0.05)
		j.parallel().tween_property(_card, "position", _card.position + Vector2(0, 6), 0.05)
		j.tween_property(_card, "rotation", r0, 0.35).set_trans(Tween.TRANS_ELASTIC)
		j.parallel().tween_property(_card, "position", _card.position, 0.35).set_trans(Tween.TRANS_ELASTIC))
