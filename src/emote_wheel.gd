# The emote wheel: hold the emote key (G) and it comes up in the middle of the visor, two rings of it:
# the inner one for saying something to the crew (BodyAnim.SOCIAL), the outer one for fooling about
# (BodyAnim.FUN). Push the mouse a little toward one for the inner ring, further for the outer; let
# go to do it. Let go without choosing and nothing happens (and an emote that's playing stops).
# Drawn in the HUD's amber on soot, like the rest of the visor.
extends Control

const BodyAnim = preload("res://src/body_anim.gd")
const AMBER := Color(1.0, 0.66, 0.3)
const INK := Color(1.0, 0.93, 0.8)
const SOOT := Color(0.06, 0.05, 0.04, 0.82)
const INNER := 95.0    # how far the mouse goes (in its own pixels) before the outer ring
const REACH := 170.0

var pick := ""
var _aim := Vector2.ZERO
var _t := 0.0
var font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "monospace"])
	f.font_weight = 700
	font = f


func open() -> void:
	visible = true
	pick = ""
	_aim = Vector2.ZERO
	_t = 0.0
	queue_redraw()


## Let go: what was picked ("" for none).
func close() -> String:
	visible = false
	return pick


func aim(rel: Vector2) -> void:
	_aim = (_aim + rel).limit_length(REACH)
	pick = ""
	if _aim.length() > 28.0:
		var ring: Array = BodyAnim.SOCIAL if _aim.length() < INNER else BodyAnim.FUN
		var n := ring.size()
		var a := fposmod(_aim.angle() + PI / 2.0 + PI / n, TAU)   # (0 at the top, clockwise)
		pick = ring[int(a / TAU * n) % n]
	queue_redraw()


func _process(delta: float) -> void:
	if visible:
		_t = minf(1.0, _t + delta * 8.0)
		queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var s := minf(size.x, size.y) / 1080.0 * lerpf(0.85, 1.0, _t)
	_ring(c, BodyAnim.SOCIAL, 90.0 * s, 225.0 * s, s, 19)
	_ring(c, BodyAnim.FUN, 235.0 * s, 385.0 * s, s, 17)
	draw_circle(c, 84.0 * s, Color(SOOT.r, SOOT.g, SOOT.b, 0.9 * _t))
	var title := "EMOTE" if pick == "" else pick
	var fs := int(18 * s)
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string(font, c + Vector2(-tw / 2.0, fs * 0.35), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(AMBER.r, AMBER.g, AMBER.b, _t))
	if _aim.length() > 4.0:   # where the mouse is pushing
		var r := lerpf(0.0, 360.0 * s, _aim.length() / REACH)
		draw_circle(c + _aim.normalized() * r, 6.0 * s, Color(INK.r, INK.g, INK.b, _t))


func _ring(c: Vector2, names: Array, r0: float, r1: float, s: float, px: int) -> void:
	var n := names.size()
	var gap := 0.018
	for i in n:
		var a0 := -PI / 2.0 - PI / n + TAU * i / n + gap
		var a1 := a0 + TAU / n - gap * 2.0
		var on: bool = names[i] == pick
		var pts := PackedVector2Array()
		for k in 13:
			var a := lerpf(a0, a1, k / 12.0)
			pts.append(c + Vector2(cos(a), sin(a)) * r1 * (1.03 if on else 1.0))
		for k in 13:
			var a := lerpf(a1, a0, k / 12.0)
			pts.append(c + Vector2(cos(a), sin(a)) * r0)
		var fill := Color(AMBER.r, AMBER.g, AMBER.b, 0.85 * _t) if on else Color(SOOT.r, SOOT.g, SOOT.b, SOOT.a * _t)
		draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		draw_polyline(pts, Color(AMBER.r, AMBER.g, AMBER.b, (0.9 if on else 0.4) * _t), 2.0 * s, true)
		var mid := (a0 + a1) / 2.0
		var at := c + Vector2(cos(mid), sin(mid)) * (r0 + r1) / 2.0
		var fs := int(px * s)
		var words: PackedStringArray = String(names[i]).split(" ")   # (two words on two lines)
		for w in words.size():
			var tw := font.get_string_size(words[w], HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			var y := at.y + fs * 0.35 + (w - (words.size() - 1) / 2.0) * fs * 1.1
			draw_string(font, Vector2(at.x - tw / 2.0, y), words[w], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.08, 0.06, 0.04, _t) if on else Color(INK.r, INK.g, INK.b, 0.9 * _t))
