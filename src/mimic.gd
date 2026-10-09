# The Mimic: a rusty barrel like the ones everywhere, if you don't look closely. It gives itself away:
# a dark puddle of drool under it, the lid sitting a finger's width open with teeth behind it, a
# slow swell when someone comes near, the odd wet twitch. Get within arm's reach and the lid flips
# open and a long barbed tongue lashes out; step back in time and it bites air. Then (or the moment
# you hit it) it sprouts legs and scuttles off to hide somewhere else. Not shown on the minimap.
extends "res://src/monster.gd"

enum { HIDE, BITE, FLEE }
const REACH := 1.25
const BITE_TIME := 0.6
const BITE_DMG := 35.0
const RUN := 6.0
const SEG := 0.13         # tongue segment length
const SEGS := 10

var state := HIDE
var _t := 0.0
var _goal := Vector3.ZERO
var _body: Node3D
var _lid: Node3D
var _tongue: Node3D
var _tsegs: Array[Node3D] = []
var ext := 0.0            # how far the tongue is out, 0..1 (synced to copies)
var _droop := 0.0         # dead: the tongue lolls to the floor
var _aim := 0.0           # the pitch the tongue lashes at (0 = level)
var _legs: Array[Node3D] = []
var _twitch := 0.0
var _breath := 0.0


func _ready() -> void:
	_setup_body(0.36, 1.0)
	health = 60.0
	hit_kind = "metal"
	add_to_group("hide_on_map")
	_body = Node3D.new()
	add_child(_body)
	var tints := [Color(0.45, 0.55, 0.7), Color(0.75, 0.35, 0.25), Color(0.5, 0.6, 0.35), Color(0.8, 0.7, 0.4)]
	var t: Color = tints[randi() % tints.size()]
	A.cyl(_body, 0.33, 0.85, Vector3(0, 0.45, 0), "rust", t)
	for y in [0.18, 0.72]:
		A.cyl(_body, 0.345, 0.04, Vector3(0, y, 0), "metal", Color(0.6, 0.6, 0.6))
	A.cyl(_body, 0.3, 0.02, Vector3(0, 0.87, 0), "flesh", Color(0.25, 0.05, 0.05))   # dark wet inside
	for i in 16:   # a ring of teeth just under the rim
		var a := TAU * i / 16.0
		var tooth := A.seg(_body, Vector3(sin(a) * 0.3, 0.83, cos(a) * 0.3), Vector3(sin(a) * 0.25, 0.92, cos(a) * 0.25), 0.022, 0.003, "cream", Color(0.92, 0.88, 0.72))
		tooth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Drool: a dark glossy puddle round its foot, and a run down one side.
	var puddle := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.5
	pm.bottom_radius = 0.5
	pm.height = 0.006
	puddle.mesh = pm
	var wet := StandardMaterial3D.new()
	wet.albedo_color = Color(0.12, 0.05, 0.05)
	wet.roughness = 0.05
	wet.metallic_specular = 1.0
	puddle.material_override = wet
	add_child(puddle)
	puddle.position = Vector3(0.08, 0.008, 0.05)
	puddle.scale = Vector3(1.0, 1.0, 0.7)
	var run := A.box(_body, Vector3(0.06, 0.5, 0.01), Vector3(0.0, 0.62, 0.333), "flesh", Color(0.2, 0.05, 0.05), false, 0.3)
	run.material_override = wet
	_lid = Node3D.new()
	_body.add_child(_lid)
	_lid.position = Vector3(0, 0.89, 0.33)
	A.cyl(_lid, 0.335, 0.05, Vector3(0, 0, -0.33), "rust", t.darkened(0.1))
	_lid.rotation.x = 0.07   # never quite shut
	_build_tongue()
	for i in 2:
		var leg := Node3D.new()
		_body.add_child(leg)
		leg.position = Vector3(-0.16 + i * 0.32, 0.12, 0)
		A.seg(leg, Vector3.ZERO, Vector3(0, -0.32, 0.04), 0.06, 0.045, "flesh", Color(0.9, 0.55, 0.55))
		A.seg(leg, Vector3(0, -0.32, 0.04), Vector3(0, -0.6, -0.04), 0.045, 0.035, "flesh", Color(0.85, 0.5, 0.5))
		A.sphere(leg, 0.06, Vector3(0, -0.6, -0.06), "flesh", Color(0.8, 0.45, 0.45), 0.0, 0.6)
		leg.scale = Vector3(1, 0.01, 1)
		_legs.append(leg)
	_twitch = randf_range(5.0, 12.0)


## Ten tapered, slightly flattened segments, each hung off the one before, ending in a hooked barb.
func _build_tongue() -> void:
	_tongue = Node3D.new()
	_body.add_child(_tongue)
	_tongue.position = Vector3(0, 0.86, 0.0)   # rooted in the open top, pointing up out of it
	_tongue.rotation.x = PI / 2.0
	var parent: Node3D = _tongue
	var skin := Color(0.92, 0.42, 0.48)
	for i in SEGS:
		var seg := Node3D.new()
		parent.add_child(seg)
		var r0 := lerpf(0.11, 0.035, float(i) / SEGS)
		var r1 := lerpf(0.11, 0.035, float(i + 1) / SEGS)
		var m := A.seg(seg, Vector3.ZERO, Vector3(0, 0, -SEG * 1.08), r0, r1, "flesh", skin.darkened(i * 0.02))
		m.scale = Vector3(1.0, 1.0, 0.7)   # flat, like a tongue, not a hose
		A.sphere(seg, r0 * 0.95, Vector3.ZERO, "flesh", skin, 0.0, 0.7)   # (rounds off the joint)
		if i == SEGS - 1:   # the barb: three hooked teeth
			for k in 3:
				var a := (k - 1) * 0.7
				A.seg(seg, Vector3(0, 0, -SEG), Vector3(sin(a) * 0.06, 0.03, -SEG - 0.07), 0.016, 0.002, "cream", Color(0.92, 0.88, 0.72))
		_tsegs.append(seg)
		parent = seg
	_pose_tongue(0.0)


## Lay the tongue out: `ext` of it unrolled up out of the lid, then bending over toward `_aim` (the
## pitch it lashes at: your face), writhing as it goes; dead, it flops over and lolls down.
func _pose_tongue(_delta: float) -> void:
	_tongue.visible = ext > 0.03
	if not _tongue.visible:
		return
	var tt := Time.get_ticks_msec() / 1000.0
	var bend := 0.0 if _droop > 0.0 else (PI / 2.0 - _aim) * clampf(ext * 1.4, 0.0, 1.0)   # from straight up to the aim, over the first segments
	for i in _tsegs.size():
		var seg := _tsegs[i]
		seg.position = Vector3(0, 0, 0 if i == 0 else -SEG * ext)
		var over := -bend / 4.0 if i >= 1 and i <= 4 else 0.0
		var writhe := sin(tt * 9.0 + i * 0.8) * 0.16 * ext * (1.0 - _droop)
		# (dead, the barrel lies on its side: the floor is off to the tongue's side, so it sags that way)
		seg.rotation = Vector3(over + writhe, sin(tt * 6.0 + i * 1.3) * 0.1 * ext * (1.0 - _droop) + _droop * (0.32 if i > 0 else 0.0), 0)


func _physics_process(delta: float) -> void:
	_t += delta
	match state:
		HIDE:
			stand_still(delta)
			ext = move_toward(ext, 0.0, delta * 4.0)
			_twitch -= delta
			if _twitch <= 0.0:
				_twitch = randf_range(5.0, 12.0)
				show_act("twitch")
			var near = nearest_player(7.0)
			_breath += delta * (2.4 if near != null else 0.8)
			_body.scale = Vector3(1.0 + sin(_breath) * (0.025 if near != null else 0.008), 1.0, 1.0 + sin(_breath) * (0.025 if near != null else 0.008))
			var p = nearest_player(REACH, true)
			if p != null:
				_bite_start()
		BITE:
			stand_still(delta)
			var p = nearest_player(REACH + 0.5, true)
			if p != null:
				face(p.global_position, delta, 20.0)
				var to: Vector3 = _body.to_local(p.global_position + Vector3(0, 1.4, 0)) - _tongue.position
				_aim = lerpf(_aim, atan2(to.y, Vector2(to.x, to.z).length()), minf(1.0, delta * 12.0))   # over the rim at your face
			ext = minf(1.0, ext + delta / (BITE_TIME * 0.8))
			if _t >= BITE_TIME and _t - delta < BITE_TIME:
				if p != null and p.global_position.distance_to(global_position) < REACH + 0.4:
					p.hurt(BITE_DMG, "Bitten by a barrel. It was a mimic.")
					Sfx.play(self, "snap", global_position + Vector3.UP, 4.0, 0.7)
				else:
					Sfx.play(self, "snap", global_position + Vector3.UP, -2.0, 0.9)   # bit air
			if _t >= BITE_TIME + 0.5:
				_flee_start()
		FLEE:
			ext = move_toward(ext, 0.25, delta * 3.0)   # trailing out of the lid as it runs
			var v := walk_to(_goal, RUN, delta, 12.0)
			_run_anim()
			if v == Vector3.ZERO or _t > 12.0:
				_hide()
	_pose_tongue(delta)


func _run_anim() -> void:
	_body.position.y = 0.55 + absf(sin(_anim * 3.0)) * 0.08
	_body.rotation.z = sin(_anim * 3.0) * 0.12
	for i in 2:
		_legs[i].rotation.x = sin(_anim * 3.0 + PI * i) * 0.8
	_lid.rotation.x = 0.4 + absf(sin(_anim * 6.0)) * 0.5


func act(what: String, _args: Array) -> void:
	if what == "twitch":   # the lid lifts, just a crack, with a wet sound
		Sfx.play(self, "slurp", global_position + Vector3(0, 0.9, 0), -14.0, 1.4)
		var tw := create_tween()
		tw.tween_property(_lid, "rotation:x", 0.22, 0.08)
		tw.tween_property(_lid, "rotation:x", 0.07, 0.15)


func _bite_start() -> void:
	state = BITE
	_t = 0.0
	Sfx.play(self, "hiss", global_position + Vector3.UP, 2.0)
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", 1.9, 0.12).set_trans(Tween.TRANS_BACK)


## Off it runs (`away_from`: somewhere far from whoever hit it).
func _flee_start(away_from := Vector3.INF) -> void:
	state = FLEE
	_t = 0.0
	_body.scale = Vector3.ONE
	if level and level.facility:
		_goal = level.facility.random_point(level.rng, true)
		if away_from != Vector3.INF:
			for tries in 6:   # the far side of the site from you
				var g: Vector3 = level.facility.random_point(level.rng, true)
				if g.distance_to(away_from) > _goal.distance_to(away_from):
					_goal = g
	else:
		_goal = global_position + Vector3(8, 0, 8)
	for leg in _legs:
		create_tween().tween_property(leg, "scale:y", 1.0, 0.25)


func _hide() -> void:
	state = HIDE
	_t = 0.0
	stand_still(0.016)
	_body.position.y = 0.0
	_body.rotation.z = 0.0
	_lid.rotation.x = 0.07
	for leg in _legs:
		leg.scale.y = 0.01
		leg.rotation.x = 0.0


# --- hits and death ---

## Hit: it squeals and runs for it, whatever it was doing.
func react_to_hit(by) -> void:
	if state != FLEE:
		Sfx.play(self, "shriek", global_position + Vector3.UP, 0.0, 1.2)
		_flee_start(by.global_position if by != null else Vector3.INF)


## Rolls over on its side, lid hanging open, the tongue lolling out across the floor.
func death_anim() -> void:
	Sfx.play(self, "creak", global_position + Vector3.UP, 4.0, 0.45)
	ext = 0.85
	_droop = 1.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_lid, "rotation:x", 2.3, 0.3).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_body, "rotation:z", 1.45, 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_body, "position:y", 0.38, 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	for leg in _legs:
		tw.tween_property(leg, "scale:y", 0.6, 0.4)
		tw.tween_property(leg, "rotation:x", 1.2, 0.8)
	get_tree().create_timer(0.55, false).timeout.connect(Sfx.play.bind(self, "clank", global_position, 2.0, 0.6))
	get_tree().create_timer(0.9, false).timeout.connect(_pose_tongue.bind(0.0))


func is_hunting() -> bool:
	return state == BITE


var _shown := -1

func net_visual(delta: float) -> void:
	if state != _shown:
		var s := state
		match s:
			BITE: _bite_start()
			FLEE: _flee_start()
			HIDE: _hide()
		state = s
		_shown = s
	if state == FLEE:
		var moved := 0.0 if _mirror_prev == Vector3.INF else global_position.distance_to(_mirror_prev)
		_mirror_prev = global_position
		_anim += moved
		_run_anim()
	_pose_tongue(delta)
