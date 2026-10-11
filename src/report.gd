# The shift report: when the quota's met at a checkpoint, a Bureau form slides in at the side of the
# visor, its lines typed out (assignment, scrap shredded, its value against the quota, the crew's
# losses), then the grade is stamped across it in red with a thud. Everyone on the crew gets it
# (net event "report"); shredding more and climbing a rank stamps it again. It goes by itself.
extends CanvasLayer

const Sfx = preload("res://src/sfx.gd")

const PAPER := Color(0.9, 0.86, 0.76)
const INK := Color(0.16, 0.14, 0.12)
const RED := Color(0.78, 0.1, 0.08)
const GRADE_WORD := {"S": "EXEMPLARY", "A": "COMMENDED", "B": "APPROVED", "C": "ACCEPTED", "D": "SUBSTANDARD"}

var main
var _card: Control
var _lines: Label
var _stamp: Control
var _mono := SystemFont.new()
var _tw: Tween


func _ready() -> void:
	layer = 15
	_mono.font_names = PackedStringArray(["Consolas", "Menlo", "DejaVu Sans Mono", "monospace"])
	_mono.font_weight = 700


## [assignment, checkpoint name, items, value, quota %, losses, crew size, grade]
func show_report(d: Array) -> void:
	if _card:
		_card.queue_free()
	if _tw:
		_tw.kill()
	var vp := get_viewport().get_visible_rect().size
	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.size = Vector2(380, 360)
	_card.pivot_offset = _card.size / 2.0
	add_child(_card)
	var rest := Vector2(vp.x - _card.size.x - 60, vp.y * 0.5 - _card.size.y * 0.5 + 30)
	_card.position = rest + Vector2(460, 0)
	_card.rotation = deg_to_rad(2.5)
	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.35)
	shadow.size = _card.size
	shadow.position = Vector2(6, 8)
	_card.add_child(shadow)
	var paper := ColorRect.new()
	paper.color = PAPER
	paper.size = _card.size
	_card.add_child(paper)
	var band := ColorRect.new()   # the Bureau's header band
	band.color = Color(0.32, 0.27, 0.2)
	band.size = Vector2(_card.size.x, 44)
	_card.add_child(band)
	var head := _label("BUREAU OF RECLAIMED MATERIALS\nFIELD ASSIGNMENT %d  ·  SHIFT REPORT" % d[0], 12, PAPER)
	head.position = Vector2(16, 6)
	_card.add_child(head)
	_lines = _label("", 14, INK)
	_lines.position = Vector2(18, 58)
	_card.add_child(_lines)
	var text := "%s\n\nSCRAP SHREDDED ..... %d\nVALUE .............. %d CR\nOF QUOTA ........... %d%%\nCREW ............... %d\nLOSSES ............. %d" % [d[1], d[2], d[3], d[4], d[6], d[5]]
	_tw = create_tween()
	_tw.tween_property(_card, "position", rest, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tw.tween_callback(Sfx.play.bind(self, "rustle", null, -10.0))
	_tw.tween_method(func(k: float):
		_lines.text = text.left(int(k))
		if int(k) % 4 == 0:
			Sfx.play(self, "key", null, -20.0, randf_range(1.0, 1.3)), 0.0, float(text.length()), 1.6)
	_tw.tween_interval(0.25)
	_tw.tween_callback(stamp.bind(d[7]))
	_tw.tween_interval(6.0)
	_tw.tween_property(_card, "position", rest + Vector2(460, 0), 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tw.tween_callback(func():
		_card.queue_free()
		_card = null)


## The grade, stamped down: big, red, a little crooked, with a thud you feel.
func stamp(grade: String) -> void:
	if _card == null:
		return
	if _stamp:
		_stamp.queue_free()
	_stamp = Control.new()
	_stamp.size = Vector2(190, 120)
	_stamp.pivot_offset = _stamp.size / 2.0
	_stamp.position = Vector2(_card.size.x - 215, _card.size.y - 138)
	_stamp.rotation = deg_to_rad(randf_range(-16.0, -8.0))
	_card.add_child(_stamp)
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(RED, 0.06)
	sb.border_color = Color(RED, 0.85)
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(8)
	box.add_theme_stylebox_override("panel", sb)
	box.size = _stamp.size
	_stamp.add_child(box)
	var letter := _label(grade, 64, Color(RED, 0.9))
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.size = Vector2(_stamp.size.x, 80)
	letter.position = Vector2(0, 8)
	_stamp.add_child(letter)
	var word := _label(GRADE_WORD.get(grade, ""), 14, Color(RED, 0.9))
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.size = Vector2(_stamp.size.x, 20)
	word.position = Vector2(0, 90)
	_stamp.add_child(word)
	_stamp.scale = Vector2.ONE * 2.6
	_stamp.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_stamp, "scale", Vector2.ONE, 0.13).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_stamp, "modulate:a", 1.0, 0.1)
	tw.chain().tween_callback(func():
		Sfx.play(self, "stamp", null, 2.0)
		if main and main.player:
			main.player.shake(0.03)
		var j := create_tween()   # the card jolts under it
		j.tween_property(_card, "rotation", _card.rotation + deg_to_rad(-1.2), 0.05)
		j.tween_property(_card, "rotation", _card.rotation, 0.2).set_trans(Tween.TRANS_ELASTIC))


func _label(t: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", _mono)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l
