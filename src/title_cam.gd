# The title screen's camera (lobby.gd): slow dolly shots around the checkpoint while the menu is
# up, each a few metres of travel with a breath of handheld sway, a lean toward the mouse and a
# soft focus on the distance, dipping through dark from one to the next. When the shift starts it
# flies into the player's eyes and hands over (fly_to).
extends Camera3D

signal shot_changed(caption: String)
signal arrived

# Relative to the train: [from, to, look from, look to, fov, caption]. The menu covers the left of
# the screen, so each one keeps its subject right of centre.
const SHOTS := [
	[Vector3(26.0, 1.5, -10.5), Vector3(21.0, 2.0, -8.6), Vector3(12.0, 2.6, 6.5), Vector3(11.5, 2.3, 6.2), 44.0, "LOCOMOTIVE 07  ·  CHECKPOINT"],
	[Vector3(-39.0, 3.4, 8.5), Vector3(-31.5, 2.7, 5.8), Vector3(-6.0, 2.6, 2.5), Vector3(-3.0, 2.2, 2.0), 50.0, "BUREAU YARD  ·  TRACK 3"],
	[Vector3(8.0, 3.3, 16.5), Vector3(1.5, 2.8, 15.0), Vector3(-7.5, 1.8, 0.0), Vector3(-9.5, 1.8, 0.0), 54.0, "RECLAMATION SHED  ·  THE SHREDDER"],
	[Vector3(7.0, 2.25, 1.3), Vector3(4.2, 2.05, 1.1), Vector3(-6.0, 1.5, -1.2), Vector3(-7.0, 1.45, -1.0), 58.0, "ABOARD  ·  CAR 1"],
]
const LENGTH := 11.0   # seconds on a shot
const DIP := 0.7       # through dark between them

var origin := Transform3D.IDENTITY   # the train's
var ears := Transform3D.IDENTITY     # where the player's head is: the sound is heard from there
var _listener: AudioListener3D
var _i := 0
var _t := 0.0
var _clock := 0.0
var _lean := Vector2.ZERO
var _fade: ColorRect
var _flying := false


func _ready() -> void:
	var dof := CameraAttributesPractical.new()
	dof.dof_blur_far_enabled = true
	dof.dof_blur_far_distance = 26.0
	dof.dof_blur_far_transition = 30.0
	dof.dof_blur_amount = 0.06
	attributes = dof
	var layer := CanvasLayer.new()
	layer.layer = 24   # (under the menu)
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.055, 0.05, 0.045)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	layer.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The world is heard from the player's head all along, not from the camera: cutting across the
	# yard would jump every sound's volume at once (a click), and the fly-in ends there anyway.
	_listener = AudioListener3D.new()
	add_child(_listener)
	_listener.top_level = true
	_listener.global_transform = ears
	_listener.make_current()
	_i = randi() % SHOTS.size()
	current = true
	_place(0.0)
	shot_changed.emit.call_deferred(SHOTS[_i][5])


func _process(delta: float) -> void:
	if _flying:
		return
	_clock += delta
	_t += delta
	if _t >= LENGTH:
		_t = 0.0
		_i = (_i + 1) % SHOTS.size()
		shot_changed.emit(SHOTS[_i][5])
	_fade.modulate.a = maxf(clampf(1.0 - _t / DIP, 0.0, 1.0), clampf((_t - (LENGTH - DIP)) / DIP, 0.0, 1.0))
	var vp := get_viewport()
	var m := vp.get_mouse_position() / Vector2(vp.get_visible_rect().size) - Vector2(0.5, 0.5)
	_lean = _lean.lerp(m.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)), minf(delta * 2.0, 1.0))
	_place(_t / LENGTH)


func _place(u: float) -> void:
	var s: Array = SHOTS[_i]
	var e := u * u * (3.0 - 2.0 * u) * 0.6 + u * 0.4   # (moving all the way, easing at the ends)
	var pos: Vector3 = origin * (s[0] as Vector3).lerp(s[1], e)
	var look: Vector3 = origin * (s[2] as Vector3).lerp(s[3], e)
	pos += Vector3(sin(_clock * 0.71) * 0.035, sin(_clock * 0.53 + 1.3) * 0.03, sin(_clock * 0.37 + 0.4) * 0.02)
	global_position = pos
	look_at(look, Vector3.UP)
	rotate_object_local(Vector3.UP, -_lean.x * 0.035)
	rotate_object_local(Vector3.RIGHT, -_lean.y * 0.02)
	rotate_object_local(Vector3.FORWARD, sin(_clock * 0.29) * 0.004)
	fov = s[4]
	attributes.dof_blur_far_distance = (look - pos).length() + 6.0


## Fly into `to` (the player's eyes) over `secs`, then emit arrived. A long way off (a saved run
## somewhere else): through dark instead.
func fly_to(to: Camera3D, secs := 1.3) -> void:
	_flying = true
	var from := global_transform
	var f0 := fov
	var tw := create_tween()
	if from.origin.distance_to(to.global_position) > 45.0:
		tw.tween_property(_fade, "modulate:a", 1.0, 0.35)
		tw.tween_callback(func(): global_transform = to.global_transform; fov = to.fov)
		tw.tween_property(_fade, "modulate:a", 0.0, 0.45)
	else:
		tw.tween_property(_fade, "modulate:a", 0.0, 0.2)
		tw.parallel().tween_method(func(k: float):
			var w := k * k * (3.0 - 2.0 * k)
			global_transform = from.interpolate_with(to.global_transform, w)
			fov = lerpf(f0, to.fov, w)
			attributes.dof_blur_amount = 0.06 * (1.0 - w), 0.0, 1.0, secs)
	tw.tween_callback(func():
		_listener.clear_current()
		arrived.emit())
