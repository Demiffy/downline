# The sky and what falls from it, above ground: a sky with drifting cloud, stars at night and the
# sun's disc (main._update_env sets its colours by the hour and the weather), rain heard outside and
# drumming on the train's roof, drops running down its windows (the "rain_amount" shader global),
# and in a storm, lightning: the sky lit white, a flash from above, the thunder after.
# The host calls the strikes so everyone sees the same flash (net event "bolt").
extends Node

const Sfx = preload("res://src/sfx.gd")
const A = preload("res://src/art.gd")

const SKY := """
shader_type sky;
render_mode use_debanding;
uniform vec3 top_color = vec3(0.6, 0.45, 0.3);
uniform vec3 horizon_color = vec3(0.8, 0.6, 0.4);
uniform vec3 ground_color = vec3(0.3, 0.22, 0.16);
uniform vec3 sun_color = vec3(1.0, 0.8, 0.6);
uniform vec3 cloud_color = vec3(0.6, 0.5, 0.42);
uniform float clouds = 0.3;
uniform float stars = 0.0;
uniform float flash = 0.0;
uniform vec2 drift = vec2(0.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.55));
	if (h < 0.0) col = mix(horizon_color, ground_color, clamp(-h * 5.0, 0.0, 1.0));
	// Stars: only at night, only above the haze.
	if (stars > 0.0 && h > 0.02) {
		vec2 sp = d.xz / (h + 0.25) * 160.0;
		vec2 cell = floor(sp);
		float r = hash(cell);
		float tw = 0.75 + 0.25 * sin(TIME * (1.0 + r * 3.0) + r * 40.0);
		float dist = length(fract(sp) - vec2(hash(cell + 3.1), hash(cell + 7.7)));
		col += vec3(0.9, 0.92, 1.0) * step(0.985, r) * smoothstep(0.12, 0.0, dist) * stars * tw * smoothstep(0.02, 0.25, h);
	}
	// The sun: a soft glow and its disc.
	float sd = 0.0;
	if (LIGHT0_ENABLED) {
		sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
		col += sun_color * (pow(sd, 18.0) * 0.35 + pow(sd, 400.0) * 1.2 + smoothstep(0.9993, 0.9996, sd) * 4.0);
	}
	// Cloud: a layer overhead, thinning to the horizon, lit warm on the sun's side.
	if (h > -0.05) {
		vec2 uv = d.xz / (max(h, 0.0) + 0.18) * 0.55 + drift;
		float c = fbm(uv * 1.4) * 0.65 + fbm(uv * 4.3 - drift * 1.7) * 0.35;
		float th = mix(0.7, 0.18, clouds);   // (how much of the sky the cloud takes)
		float cover = smoothstep(th, th + 0.2, c) * smoothstep(-0.05, 0.18, h);
		float body = smoothstep(th, th + 0.45, c);   // thick in the middle, thin at the edges
		vec3 cc = cloud_color * mix(1.25, 0.55, body * clouds) + sun_color * pow(sd, 6.0) * 0.3 * (1.0 - body * 0.6);
		col = mix(col, cc, cover * 0.95);
		col += flash * vec3(0.75, 0.8, 1.0) * (0.25 + cover * 1.6);
	} else {
		col += flash * vec3(0.75, 0.8, 1.0) * 0.15;
	}
	COLOR = col;
}
"""

var main
var mat: ShaderMaterial
var flash := 0.0            # the sky lit by lightning (falls back to 0)
var _rain := 0.0            # 0..1, eased: windows, sounds
var _bolt: DirectionalLight3D
var _next := 8.0            # (host) seconds to the next strike
var _out: AudioStreamPlayer
var _roof: AudioStreamPlayer
var _drift := Vector2.ZERO
var _level = null           # the station the puddles were laid for
var _puddles: Array = []    # [centre, radius] outdoors, when it's raining
var _drop_t := 0.0


static func _global() -> void:
	if not Engine.has_meta("rain_amount"):   # (the global, made once; asking the server for its list is editor-only)
		RenderingServer.global_shader_parameter_add("rain_amount", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
		RenderingServer.global_shader_parameter_add("rain_wind", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
		Engine.set_meta("rain_amount", true)


func _ready() -> void:
	_global()
	mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY
	mat.shader = sh
	_bolt = DirectionalLight3D.new()   # the flash, from high up somewhere
	_bolt.light_color = Color(0.78, 0.84, 1.0)
	_bolt.light_energy = 0.0
	_bolt.visible = false
	add_child(_bolt)
	for k in ["rain", "rain_roof"]:
		var p := AudioStreamPlayer.new()
		p.stream = Sfx.stream(k)
		p.volume_db = -80.0
		p.bus = "Ambience" if AudioServer.get_bus_index("Ambience") >= 0 else "Master"
		add_child(p)
		if k == "rain":
			_out = p
		else:
			_roof = p


## How hard it's raining where the train is (0..1).
func raining() -> float:
	if main == null or main.at_checkpoint:
		return 0.0
	var dry: float = 1.0 - main.line.dark if main.line != null else 1.0   # (none in a tunnel)
	match main.stop.get("weather", ""):
		"RAIN", "ACID_RAIN": return 0.75 * dry
		"STORM": return 1.0 * dry
	return 0.0


func _process(delta: float) -> void:
	if main == null or main.player == null:
		return
	var p = main.player
	var under: bool = p.global_position.y < main.UNDERGROUND_Y
	_rain = move_toward(_rain, raining(), delta * 0.3)
	RenderingServer.global_shader_parameter_set("rain_amount", _rain)
	RenderingServer.global_shader_parameter_set("rain_wind", clampf(absf(main.train.speed) / 24.0, 0.0, 1.0) if main.train != null else 0.0)
	# The rain as you hear it: all round outside, on the roof aboard, a far hiss down below.
	var outside_db := linear_to_db(maxf(_rain, 0.0001)) - (6.0 if not p.in_train else 22.0) - (26.0 if under else 0.0)
	var roof_db := linear_to_db(maxf(_rain, 0.0001)) - 8.0 if p.in_train and not under else -80.0
	_loop(_out, outside_db, delta)
	_loop(_roof, roof_db, delta)
	# Cloud drifts on the wind.
	_drift += Vector2(0.004, 0.0015) * delta * (3.0 if main.stop.get("weather", "") in ["STORM", "SANDSTORM", "BLIZZARD"] else 1.0)
	mat.set_shader_parameter("drift", _drift)
	# Puddles round the station when it's wet, the rain ringing on them.
	if _level != null and not is_instance_valid(_level):   # (the stop's gone: the train's moved on)
		_level = null
		_puddles.clear()
	if main.level != _level and not main._travelling:   # (laid round the train once it's stood at the platform)
		_level = main.level
		_puddles.clear()
		if _level != null and raining() > 0.0:
			_lay_puddles()
	if _rain > 0.1 and not _puddles.is_empty() and not under:
		_drop_t -= delta * _rain
		while _drop_t <= 0.0:
			_drop_t += 0.035
			var pd: Array = _puddles[randi() % _puddles.size()]
			if pd[0].distance_to(p.global_position) < 22.0:
				var at: Vector3 = pd[0] + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * pd[1] * 0.6
				_ripple(at)
	flash = move_toward(flash, 0.0, delta * 3.5)
	mat.set_shader_parameter("flash", flash)
	_bolt.light_energy = flash * 2.2
	_bolt.visible = flash > 0.01 and not under
	if main.stop.get("weather", "") == "STORM" and not main.at_checkpoint and main.net.authority():
		_next -= delta
		if _next <= 0.0:
			_next = randf_range(7.0, 24.0)
			var args := [randf_range(-70.0, -35.0), randf() * 360.0, randf_range(0.4, 3.0)]
			strike(args)
			main.net.event("bolt", args)


func _ripple(at: Vector3) -> void:
	if is_instance_valid(_level) and not _level.is_queued_for_deletion():
		A.ripple(_level, at, randf_range(0.2, 0.4), 0.55)


## Water lying in the low spots round the train: found by dropping a line onto the ground.
func _lay_puddles() -> void:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var c: Vector3 = main.train.global_position
	for i in 70:
		var at := c + Vector3(randf_range(-34, 34), 0, randf_range(-22, 22))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3(0, 30, 0), at + Vector3(0, -30, 0), 1))
		if hit.is_empty() or hit.normal.y < 0.92:
			continue
		var r := randf_range(1.0, 2.6)
		A.puddle(_level, hit.position, r * 2.0, randf() * TAU)
		_puddles.append([hit.position + Vector3(0, 0.01, 0), r])


func _loop(pl: AudioStreamPlayer, db: float, delta: float) -> void:
	if db <= -60.0:
		if pl.playing:
			pl.volume_db = move_toward(pl.volume_db, -80.0, delta * 30.0)
			if pl.volume_db <= -79.0:
				pl.stop()
		return
	if not pl.playing:
		pl.volume_db = -60.0
		pl.play(randf() * 4.0)
	pl.volume_db = move_toward(pl.volume_db, db, delta * 20.0)


## A strike: [pitch of the flash from above, its heading, seconds to the thunder].
func strike(args: Array) -> void:
	if main == null or main.player == null:
		return
	_bolt.rotation_degrees = Vector3(args[0], args[1], 0)
	var under: bool = main.player.global_position.y < main.UNDERGROUND_Y
	_flicker(under)
	await get_tree().create_timer(float(args[2]), false).timeout
	if not is_inside_tree():
		return
	var a := AudioStreamPlayer.new()   # (everyone hears their own: not through the net)
	a.stream = Sfx.stream("thunder")
	a.volume_db = (-6.0 if not main.player.in_train else -10.0) - (16.0 if under else 0.0) - float(args[2]) * 2.0
	a.pitch_scale = randf_range(0.8, 1.1)
	a.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
	add_child(a)
	a.finished.connect(a.queue_free)
	a.play()
	if float(args[2]) < 1.0 and not under:
		main.player.shake(0.012)


## The flash: a double flicker, the way lightning stutters. Below ground, a faint one through the cracks.
func _flicker(under: bool) -> void:
	var peak := 0.25 if under else 1.0
	for k in [peak, peak * 0.3, peak * 0.85]:
		flash = maxf(flash, k)
		await get_tree().create_timer(randf_range(0.05, 0.11), false).timeout
		if not is_inside_tree():
			return
