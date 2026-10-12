# The emote wheel: hold the emote key (G) and it comes up in the middle of the visor; push the mouse
# toward one and let go to do it. Let go without choosing and nothing happens (and an emote that's
# playing stops). Drawn in the HUD's amber on soot, like the rest of the visor.
extends Control

const BodyAnim = preload("res://src/body_anim.gd")
const AMBER := Color(1.0, 0.66, 0.3)
const INK := Color(1.0, 0.93, 0.8)
const SOOT := Color(0.06, 0.05, 0.04, 0.82)

var pick := -1
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
	pick = -1
	_aim = Vector2.ZERO
	_t = 0.0
	queue_redraw()


## Let go: what was picked ("" for none).
func close() -> String:
	visible = false
	return BodyAnim.EMOTES[pick] if pick >= 0 else ""


func aim(rel: Vector2) -> void:
	_aim = (_aim + rel).limit_length(140.0)
	var n := BodyAnim.EMOTES.size()
	if _aim.length() > 30.0:
		var a := fposmod(_aim.angle() + PI / 2.0 + PI / n, TAU)   # (0 at the top, clockwise)
		pick = int(a / TAU * n) % n
	else:
		pick = -1
	queue_redraw()


func _process(delta: float) -> void:
	if visible:
		_t = minf(1.0, _t + delta * 8.0)
		queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var s := minf(size.x, size.y) / 1080.0
	var r1 := 250.0 * s * lerpf(0.85, 1.0, _t)
	var r0 := 95.0 * s
	var n := BodyAnim.EMOTES.size()
	var gap := 0.025
	for i in n:
		var a0 := -PI / 2.0 - PI / n + TAU * i / n + gap
		var a1 := a0 + TAU / n - gap * 2.0
		var on := i == pick
		var pts := PackedVector2Array()
		for k in 13:
			var a := lerpf(a0, a1, k / 12.0)
			pts.append(c + Vector2(cos(a), sin(a)) * r1 * (1.04 if on else 1.0))
		for k in 13:
			var a := lerpf(a1, a0, k / 12.0)
			pts.append(c + Vector2(cos(a), sin(a)) * r0)
		var fill := Color(AMBER.r, AMBER.g, AMBER.b, 0.85 * _t) if on else Color(SOOT.r, SOOT.g, SOOT.b, SOOT.a * _t)
		draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		draw_polyline(pts, Color(AMBER.r, AMBER.g, AMBER.b, (0.9 if on else 0.45) * _t), 2.0 * s, true)
		var mid := (a0 + a1) / 2.0
		var at := c + Vector2(cos(mid), sin(mid)) * (r0 + r1) / 2.0
		var label: String = BodyAnim.EMOTES[i]
		var fs := int(22 * s)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(font, at + Vector2(-w / 2.0, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.08, 0.06, 0.04, _t) if on else Color(INK.r, INK.g, INK.b, 0.9 * _t))
	draw_circle(c, r0 - 6.0 * s, Color(SOOT.r, SOOT.g, SOOT.b, 0.9 * _t))
	var title := "EMOTE" if pick < 0 else String(BodyAnim.EMOTES[pick])
	var fs2 := int(18 * s)
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, fs2).x
	draw_string(font, c + Vector2(-tw / 2.0, fs2 * 0.35), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(AMBER.r, AMBER.g, AMBER.b, _t))
	if _aim.length() > 4.0:   # where the mouse is pushing
		draw_circle(c + _aim.normalized() * minf(_aim.length(), r0 - 18.0 * s), 6.0 * s, Color(INK.r, INK.g, INK.b, _t))
