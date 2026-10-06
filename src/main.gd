# Game state + the loop:
#   CHECKPOINT --LEAVE_CHECKPOINT--> 3 stations (ROUTE_TO, one day each) --> CHECKPOINT (shred, meet quota) ...
extends Node3D

const Data = preload("res://src/data.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")
const Player = preload("res://src/player.gd")
const Pickup = preload("res://src/pickup.gd")
const Level = preload("res://src/level.gd")
const Hud = preload("res://src/hud.gd")
const Terminal = preload("res://src/terminal.gd")
const Train = preload("res://src/train.gd")
const Facility = preload("res://src/facility.gd")
const Settings = preload("res://src/settings.gd")
const Menu = preload("res://src/menu.gd")
const ScanFx = preload("res://src/scanfx.gd")

const DAY_SECONDS := 720.0   # real seconds from 08:00 to 24:00
const SLIDE := 150.0         # metres the world slides past during departure/arrival
const SLIDE_SECS := 5.5
const UNDERGROUND_Y := -20.0
const CHECKPOINT_STOP := {"theme": "CHECKPOINT", "letter": "CHECKPOINT"}

var rng := RandomNumberGenerator.new()
var player
var train
var level
var hud
var term
var menu
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var _last_level_x := 0.0
var _last_train_x := 0.0

var credits := 60
var assignment := 0
var quota := {}
var submitted := {}      # shredded this checkpoint visit
var prices := {}
var route: Array = []    # 3 stages, each an Array of stop dicts
var taken: Array = []    # letters chosen so far
var stage := -1          # index into route of where we are; -1 = checkpoint
var at_checkpoint := true
var departed := false    # LEAVE_CHECKPOINT done for this checkpoint visit
var stop := {}
var hours := 8.0
var warned := 0
var payload_rank := "-"
var _cp_value := 0.0
var _rank_bonus_paid := 0
var _amb: Array[AudioStreamPlayer] = []
var _amb_i := 0
var _amb_bed := ""
var _space := ""
var _sting := 10.0
var _travelling := false   # between pulling out and arriving: leaving the train strands you
var _stranded := false
var busy := false
var over := false
var _letter := 0
var upgrades := {}        # name -> true
var logs_unlocked := 0
var stats := {"assignments": 0, "shredded": 0, "earned": 0}
var best := 0
var _cam_index := 0
var _orders: Array = []   # item ids waiting for the delivery handcar
var _handcar: Node3D
var _handcar_busy := false
const BEST_PATH := "user://best_run.json"


func _ready() -> void:
	Sfx.setup()
	rng.randomize()
	_setup_input()
	_setup_world()
	train = Train.new()
	add_child(train)
	train.build(open_terminal)
	hud = Hud.new()
	add_child(hud)
	term = Terminal.new()
	add_child(term)
	term.closed.connect(_on_terminal_closed)
	term.status_fn = func(): return "%s     %02d:%02d     CREDITS %d" % ["CHECKPOINT" if at_checkpoint else "STATION %s" % stop.get("letter", "?"), int(hours) % 24, int(fmod(hours, 1.0) * 60.0), credits]
	_register_commands()
	if "playground" in OS.get_cmdline_user_args():
		var pg = load("res://src/playground.gd").new()
		pg.main = self
		add_child.call_deferred(pg)
	player = Player.new()
	player.main = self
	add_child(player)
	player.position = Vector3(-3, 1.3, 0)
	player.rotation.y = -PI / 2
	player.died.connect(_on_died)
	menu = Menu.new()
	menu.main = self
	add_child(menu)
	Settings.load_file()
	Settings.apply(self)
	for k in 2:   # two ambience players so beds can crossfade
		var a := AudioStreamPlayer.new()
		a.bus = "Ambience"
		a.volume_db = -80.0
		add_child(a)
		_amb.append(a)
	_load_level(CHECKPOINT_STOP)
	spawn_item("FLASHLIGHT", Vector3(5.6, 2.0, -1.5), -1.0, train)
	spawn_item("SCANNER", Vector3(5.15, 2.0, -1.5), -1.0, train)   # beside the flashlight, clear of the monitors
	var f := FileAccess.open(BEST_PATH, FileAccess.READ)
	if f:
		best = int(JSON.parse_string(f.get_as_text()).get("best", 0))
	hud.msg("Welcome aboard, employee. Starter kit is on the desk by the terminal.")
	hud.msg("Use the terminal at the front of the train ([E]). Type LEAVE_CHECKPOINT.")


func players() -> Array:
	return get_tree().get_nodes_in_group("players")


func has_upgrade(name: String) -> bool:
	return upgrades.has(name)


func charge_max(id: String) -> float:
	return float(Data.ITEMS[id].get("charge", 1.0)) * (1.6 if has_upgrade("BATTERY_PACK") else 1.0)


func open_shop() -> void:
	open_terminal()
	term.run("UPGRADES")


func upload_disk() -> void:
	Sfx.play(self, "scan", null, -4.0, 0.7)
	if logs_unlocked >= Data.LOGS.size():
		credits += 15
		hud.msg("All logs already on file. The Bureau pays 15 credits for the media.")
		return
	var name: String = Data.LOGS[logs_unlocked][0]
	logs_unlocked += 1
	hud.alert("LOG UPLOADED: %s   (terminal: READ %s)" % [name, name])


func spawn_item(id: String, pos: Vector3, charge := -1.0, parent: Node = null) -> RigidBody3D:
	var p := Pickup.new()
	p.setup(id, charge)
	if parent == null:
		parent = level if level != null else train
	parent.add_child(p)
	p.global_position = pos
	return p


## Something made a sound at pos audible within radius. Blind monsters care.
func noise(pos: Vector3, radius: float) -> void:
	for m in get_tree().get_nodes_in_group("hearing"):
		if m.global_position.distance_to(pos) < radius:
			m.hear(pos)
	for m in get_tree().get_nodes_in_group("ground_listeners"):
		m.hear(pos)


func explode(pos: Vector3, radius: float, dmg: float, cause: String) -> void:
	for p in players():
		var d: float = pos.distance_to(p.global_position + Vector3.UP)
		if d < radius:
			p.hurt(dmg * (1.0 - d / radius), cause)
			if not p.dead and p == player:
				hud.msg(cause)   # blasts often come from round a corner; say what it was
	Sfx.play(self, "boom", pos, 8.0)
	var l := B.omni(self, Vector3.ZERO, Color(1, 0.6, 0.3), 10.0, 14.0)
	l.global_position = pos + Vector3.UP
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.7)
	tw.tween_callback(l.queue_free)
	noise(pos, 25.0)


func scan(origin: Vector3, radius: float) -> void:
	var hits := []
	for p in get_tree().get_nodes_in_group("pickups"):
		var d := origin.distance_to(p.global_position)
		if d <= radius and not train.contains(p.global_position):
			var res: Dictionary = Data.ITEMS[p.id].res
			var worth := 0.0
			for r in res:
				worth += res[r] * prices.get(r, 0.0)
			var detail := Data.res_text(res) + ("   ~%d cr" % roundi(worth) if worth > 0.0 else "")
			if Data.is_heavy(p.id):
				detail = "HEAVY   " + detail
			hits.append(_hit(p, d, "scrap", Data.ITEMS[p.id].name.to_upper(), detail, Data.ITEMS[p.id].size.y * 0.5 + 0.3, Data.value_units(p.id)))
	for m in get_tree().get_nodes_in_group("monsters"):
		var d := origin.distance_to(m.global_position)
		if d <= radius:
			hits.append(_hit(m, d, "entity", "UNKNOWN ENTITY", "%d m" % roundi(d), 2.3))
	for t in get_tree().get_nodes_in_group("scan_targets"):   # breaker panel, airdrops
		var d := origin.distance_to(t.global_position)
		if d <= radius * 1.5:
			hits.append(_hit(t, d, "poi", t.get_meta("scan_name"), "%d m" % roundi(d), 2.2))
	hits.sort_custom(func(a, b): return a.d < b.d)
	# Name tags: the most valuable finds first, never two on top of each other; everything still glows.
	var by_value := hits.duplicate()
	by_value.sort_custom(func(a, b): return a.value > b.value if a.value != b.value else a.d < b.d)
	var tagged: Array[Vector3] = []
	for h in by_value:
		var at: Vector3 = h.node.global_position
		h.tag_ok = h.kind != "scrap" or (tagged.size() < 8 and tagged.all(func(q): return q.distance_to(at) > 1.3))
		if h.tag_ok and h.kind == "scrap":
			tagged.append(at)
	var lines := PackedStringArray()
	for h in hits.slice(0, 10):
		lines.append("%-18s %3dm" % [h.name.left(18), int(h.d)])
	hud.set_scan("SCAN  %d in range\n%s" % [hits.size(), "\n".join(lines)])
	var fx := ScanFx.new()
	fx.main = self
	add_child(fx)
	fx.start(player.cam, origin + Vector3(0, 1.0, 0), radius, hits)
	Sfx.play(self, "scan", null, -4.0)


func _hit(node: Node3D, d: float, kind: String, name: String, detail: String, lift: float, value := 0) -> Dictionary:
	return {"node": node, "d": d, "kind": kind, "name": name, "detail": detail, "lift": lift, "value": value,
		"lit": false, "t": 0.0, "meshes": [], "tag": null, "ring": null}


# --- frame loop ----------------------------------------------------------------

func _unhandled_key_input(e: InputEvent) -> void:
	# F11 or Alt+Enter: fullscreen on/off. The UI scales with the window (stretch mode canvas_items).
	# Mac: Cmd+Ctrl+F (the system shortcut) or Option+Return.
	if e is InputEventKey and e.pressed and not e.echo and (e.keycode == KEY_F11 or (e.keycode == KEY_ENTER and e.alt_pressed) \
			or (e.keycode == KEY_F and e.meta_pressed and e.ctrl_pressed)):
		Settings.v.fullscreen = not DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		Settings.apply(self)
		Settings.save()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if over:
		if Input.is_action_just_pressed("restart"):
			get_tree().reload_current_scene()
		return
	player.in_train = train.contains(player.global_position)
	if _travelling and not _stranded and not train.on_board(player.global_position):
		_strand()
	_track_motion(delta)
	if not at_checkpoint and not busy:
		hours += 16.0 * delta / DAY_SECONDS
		if hours >= 20.0 and warned == 0:
			warned = 1
			hud.alert("WARNING: return to the train before automatic departure at 24:00")
			Sfx.play(self, "alarm", null, -4.0)
		if hours >= 23.0 and warned == 1:
			warned = 2
			hud.alert("FINAL WARNING: automatic departure in one hour")
			Sfx.play(self, "alarm", null, -4.0)
		if hours >= 24.0:
			_auto_depart()
		level.tick(delta, hours)
		_weather(delta)
	_update_env()
	_sound_space(delta)
	var t := "CHECKPOINT" if at_checkpoint else "%02d:%02d" % [int(hours) % 24, int(fmod(hours, 1.0) * 60.0)]
	var q := _quota_text()
	hud.set_status(t, q, "CHECKPOINT" if at_checkpoint else "STATION %s" % stop.get("letter", "?"))
	train.set_clock(hours, "CHECKPOINT" if at_checkpoint else "STATION %s" % stop.get("letter", "?"))
	if term.booted:
		train.screen_label.text = term.screen_text(13, 36)
	var market := "SCRAP MARKET\n"
	for r in Data.RES:
		market += "%-8s %4.1f\n" % [r.to_upper(), prices[r]]
	train.market_label.text = market + "CREDITS %d" % credits
	if at_checkpoint and level and level.board:
		level.board.text = q
	hud.update_player(player)


func _quota_text() -> String:
	var s := "CREDITS: %d\n" % credits
	if assignment == 0:
		return s + "NO ACTIVE ASSIGNMENT"
	var shredding := at_checkpoint and not departed
	var train_res := _count(_items_in(func(p): return train.contains(p.global_position)))
	s += "ASSIGNMENT %d %s:\n" % [assignment, "(SHREDDED)" if shredding else "(ON TRAIN)"]
	for r in Data.RES:
		var have: int = submitted.get(r, 0) if shredding else train_res.get(r, 0)
		s += "[%2d/%2d] %s%s\n" % [have, quota[r], r.to_upper(), "  OK" if have >= quota[r] else ""]
	if shredding:
		s += "on train: %s\nPAYLOAD RANK: %s" % [Data.res_text(train_res), payload_rank]
	return s


func _items_in(filter: Callable) -> Array:
	return get_tree().get_nodes_in_group("pickups").filter(filter)


func _count(items: Array) -> Dictionary:
	var c := {}
	for p in items:
		var res: Dictionary = Data.ITEMS[p.id].res
		for r in res:
			c[r] = c.get(r, 0) + res[r]
	return c


## Which footstep a surface makes: train floor, lift cage, facility floor by theme, platform, sand/snow.
func surface_at(pos: Vector3) -> String:
	if level != null and level.elevator != null and level.elevator.inside(pos):
		return "metal"
	if train.on_board(pos):
		return "wood" if train.contains(pos) else "metal"
	if pos.y < UNDERGROUND_Y and level != null and level.facility != null:
		if level.hazards and level.hazards.wet(pos):
			return "water"
		var c: Vector2i = level.facility.cell_at(pos)
		if level.facility.kinds.get(c, "") in ["pit", "tunnel"] and pos.y > level.facility.global_position.y - 0.5:
			return "metal"   # catwalks and grate walkways
		match String(level.facility.theme.floor_kind):
			"tiles", "ceiling_tile": return "tiles"
			"carpet": return "carpet"
			"flesh": return "flesh"
			"grate", "riveted", "metal", "rust": return "metal"
			"wood": return "wood"
		return "concrete"
	if at_checkpoint:
		return "concrete"
	var l: Vector3 = level.to_local(pos) if level else pos
	if absf(l.x) < 14.5 and l.z > 2.3 and l.z < 6.6 and pos.y > 0.7:
		return "wood"
	if level and Vector2(pos.x - level.elevator_pos.x, pos.z - level.elevator_pos.z).length() < 7.0:
		return "concrete"
	return "snow" if stop.get("biome", "") == "ARCTIC" else "sand"


## Reverb follows where you are; an ambience bed per place; now and then something far off underground.
func _sound_space(delta: float) -> void:
	var under: bool = player.global_position.y < UNDERGROUND_Y
	var space := "underground" if under else ("train" if player.in_train else "outside")
	if space != _space:
		_space = space
		Sfx.set_space(space)
	var bed := "wind"
	var bed_db := -20.0
	if under and level and level.facility:
		bed = "amb_" + String(level.facility.theme_id).to_lower()
		bed_db = -12.0 if bed != "amb_backrooms" else -6.0
	elif at_checkpoint:
		bed = "amb_yard"
		bed_db = -16.0
	elif player.in_train:
		bed_db = -28.0
	if bed != _amb_bed:
		_amb_bed = bed
		var old: AudioStreamPlayer = _amb[_amb_i]
		_amb_i = 1 - _amb_i
		var new: AudioStreamPlayer = _amb[_amb_i]
		new.stream = Sfx.stream(bed)
		new.volume_db = -60.0
		new.play(randf() * 4.0)
		var tw := create_tween().set_parallel()
		tw.tween_property(old, "volume_db", -80.0, 2.0)
		tw.tween_property(new, "volume_db", bed_db, 2.0)
	elif not busy:
		_amb[_amb_i].volume_db = move_toward(_amb[_amb_i].volume_db, bed_db, delta * 10.0)
	if not under or level == null or busy:
		return
	_sting -= delta
	if _sting <= 0.0:
		var late := hours >= 20.0
		_sting = randf_range(6.0, 14.0) if late else randf_range(9.0, 22.0)
		var pool := ["far_bang", "groan", "drip", "pipe_knock", "far_steps", "drip"]
		if level.facility.theme_id == "FLESH":
			pool = ["groan", "drip", "drip", "far_steps", "far_screech"]
		if late:
			pool.append("far_screech")
		var dir := Vector3(1, 0, 0).rotated(Vector3.UP, randf() * TAU)
		var at: Vector3 = player.global_position + dir * randf_range(12.0, 26.0) + Vector3(0, 1.5, 0)
		Sfx.play(level, pool[randi() % pool.size()], at, randf_range(-4.0, 2.0), randf_range(0.85, 1.1))


func _weather(delta: float) -> void:
	var under: bool = player.global_position.y < UNDERGROUND_Y
	var acid: bool = stop.get("weather", "") == "ACID_RAIN"
	player.set_weather("" if under else ("ACID_RAIN" if acid else ("SNOW" if stop.get("biome", "") == "ARCTIC" else stop.get("weather", ""))))
	if acid and not under and not player.dead and not player.in_train and not _roofed(player.global_position):
		player.hurt(4.0 * delta, "Dissolved in acid rain.")


func _roofed(pos: Vector3) -> bool:
	var from := pos + Vector3(0, 1.9, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 40, 0), 1)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# --- travel ---------------------------------------------------------------------

func _load_level(s: Dictionary) -> void:
	stop = s
	at_checkpoint = s.theme == "CHECKPOINT"
	_cp_value = 0.0
	_rank_bonus_paid = 0
	payload_rank = "-"
	hours = 8.0
	warned = 0
	for r in Data.RES:
		prices[r] = snappedf(Data.BASE_PRICE[r] * rng.randf_range(0.7, 1.4), 0.1)
	level = Level.new()
	level.main = self
	add_child(level)
	level.build(s, assignment, rng.randi())


func _depart(s: Dictionary) -> void:
	if busy or over:
		return
	busy = true
	term.close()
	hud.msg("Train departing for %s..." % s.letter)
	Sfx.play(self, "horn", null, -2.0)
	await get_tree().create_timer(1.5 * Data.pace(), false).timeout
	if over:
		return
	if not train.contains(player.global_position):
		# You watch it leave.
		var tw := create_tween()
		tw.tween_property(train, "position:x", SLIDE * 2, SLIDE_SECS * Data.pace() * 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		if tw.is_running():   # a long frame can finish it before we get here
			await tw.finished
		game_over("LEFT BEHIND\nThe train departed on schedule. You did not.")
		return
	for p in get_tree().get_nodes_in_group("pickups"):
		if train.contains(p.global_position):
			p.reparent(train)
	_travelling = true
	# The world slides backwards while the train "pulls away".
	level.process_mode = Node.PROCESS_MODE_DISABLED
	var out := create_tween()
	out.tween_property(level, "position:x", -SLIDE, SLIDE_SECS * Data.pace()).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer((SLIDE_SECS - 1.5) * Data.pace(), false).timeout
	if over or _stranded:
		return
	await hud.fade(1.0, 1.5 * Data.pace())
	if over or _stranded:
		return
	level.queue_free()
	level = null
	if s.theme == "CHECKPOINT":
		stage = -1
		departed = false
		submitted = {}
	else:
		stage += 1
		taken.append(s.letter)
	await get_tree().create_timer(1.0 * Data.pace(), false).timeout
	if over or _stranded:
		return
	_load_level(s)
	level.process_mode = Node.PROCESS_MODE_DISABLED
	level.position.x = SLIDE
	_last_level_x = SLIDE
	var inn := create_tween()
	inn.tween_property(level, "position:x", 0.0, SLIDE_SECS * Data.pace()).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await hud.fade(0.0, 1.5 * Data.pace())
	if inn.is_running():   # a long frame can finish it before we get here
		await inn.finished
	if over or _stranded:
		return
	_travelling = false
	level.process_mode = Node.PROCESS_MODE_INHERIT
	Sfx.play(self, "horn", null, -8.0, 0.8)
	busy = false
	if at_checkpoint:
		hud.alert("CHECKPOINT. Throw scrap into the SHREDDER and pull the lever.")
	else:
		hud.msg("Arrived at station %s: %s facility, %s." % [s.letter, s.theme, s.biome])
		if s.weather != "CLEAR":
			hud.alert("WEATHER ALERT: %s" % s.weather.replace("_", " "))
			Sfx.play(self, "alarm", null, -4.0)


## Stepped off while the train is moving: you stay with the world (it carries you away from the
## train instead of leaving you over nothing), watch it go, and that's the run.
func _strand() -> void:
	_stranded = true
	_travelling = false
	player.velocity = Vector3.ZERO
	if level != null:
		player.reparent(level)   # the level is paused while it slides, so you ride along with it
	else:
		player.process_mode = Node.PROCESS_MODE_DISABLED   # between stations: just hang on
	hud.alert("You stepped off the train.")
	Sfx.play(self, "horn", null, -4.0, 0.7)
	if hud.fade_r.color.a > 0.0:
		await hud.fade(0.0, 0.6)
	await get_tree().create_timer(2.5, false).timeout
	game_over("LEFT BEHIND\nYou stepped off a moving train. It did not stop for you.")


## Wheels, steam and camera shake follow how fast the world is moving past the train.
func _track_motion(delta: float) -> void:
	if delta <= 0.0:
		return
	var lx: float = level.position.x if level else _last_level_x
	var v: float = (_last_level_x - lx) / delta + (train.position.x - _last_train_x) / delta
	_last_level_x = lx
	_last_train_x = train.position.x
	train.speed = lerpf(train.speed, v, minf(1.0, delta * 8.0))
	if player.in_train and absf(train.speed) > 0.5:
		player.shake(clampf(absf(train.speed) * 0.0015, 0.0, 0.025))


func _auto_depart() -> void:
	var dest: Dictionary = CHECKPOINT_STOP if stage >= 2 else route[stage + 1][rng.randi() % route[stage + 1].size()]
	hud.alert("AUTOMATIC DEPARTURE")
	_depart(dest)


func shred() -> void:
	if not at_checkpoint or level == null:
		return
	var got := {}
	var n := 0
	for p in get_tree().get_nodes_in_group("pickups"):
		if level.hopper.has_point(p.global_position):
			var res: Dictionary = Data.ITEMS[p.id].res
			for r in res:
				got[r] = got.get(r, 0) + res[r]
			n += 1
			p.queue_free()
	if n == 0:
		hud.msg("The shredder is empty. Throw scrap over the rim first.")
		Sfx.play(self, "error", null, -6.0)
		return
	var pay := 0.0
	for r in got:
		submitted[r] = submitted.get(r, 0) + got[r]
		pay += got[r] * prices[r]
	credits += roundi(pay)
	stats.shredded += n
	stats.earned += roundi(pay)
	level.shred_fx()
	Sfx.play(self, "boom", level.hopper.get_center(), -2.0, 0.6)
	hud.msg("Shredded %d items: %s   +%d credits" % [n, Data.res_text(got), roundi(pay)])
	_rank_payload(pay)
	if assignment > 0 and not departed and _quota_met() and level.gate_light.light_color.g < 0.5:
		stats.assignments += 1
		level.open_gate()
		hud.alert("QUOTA MET. Gate unlocked. LEAVE_CHECKPOINT when ready.")


## Payload rank for this checkpoint: everything shredded here against what the quota is worth.
## Climbing a rank pays a one-off Bureau bonus.
func _rank_payload(pay: float) -> void:
	_cp_value += pay
	var quota_value := 0.0
	for r in Data.RES:
		quota_value += quota.get(r, 0) * prices[r]
	if quota_value <= 0.0:
		return
	var ratio := _cp_value / quota_value
	var ranks := [["S", 2.0, 150], ["A", 1.5, 80], ["B", 1.0, 30], ["C", 0.6, 0], ["D", 0.0, 0]]
	for rk in ranks:
		if ratio >= rk[1]:
			payload_rank = rk[0]
			var bonus: int = rk[2]
			if bonus > _rank_bonus_paid:
				credits += bonus - _rank_bonus_paid
				stats.earned += bonus - _rank_bonus_paid
				hud.alert("PAYLOAD RANK %s   (%d%% of quota value)   Bureau bonus +%d" % [payload_rank, roundi(ratio * 100.0), bonus - _rank_bonus_paid])
				Sfx.play(self, "ding", null, -2.0, 1.2)
				_rank_bonus_paid = bonus
			else:
				hud.alert("PAYLOAD RANK %s   (%d%% of quota value)" % [payload_rank, roundi(ratio * 100.0)])
			break


func _quota_met() -> bool:
	for r in Data.RES:
		if submitted.get(r, 0) < quota.get(r, 0):
			return false
	return true


func _start_assignment() -> void:
	assignment += 1
	departed = true
	submitted = {}
	for r in Data.RES:
		quota[r] = maxi(2, roundi((3.0 + 3.0 * assignment) * rng.randf_range(0.6, 1.4)))
	route = []
	taken = []
	stage = -1
	for i in 3:
		var opts := []
		for j in rng.randi_range(2, 3):
			opts.append(_gen_stop())
		route.append(opts)
	level.open_gate()
	Sfx.play(self, "horn", null, -2.0)
	term.say("\nASSIGNMENT %d ISSUED.  Quota: %s" % [assignment, Data.res_text(quota)])
	_c_map([])


func _gen_stop() -> Dictionary:
	var letter := char(65 + _letter % 26)
	_letter += 1
	var pool := []
	for t in Data.THEMES:
		for k in Data.THEMES[t].weight:
			pool.append(t)
	return {
		"letter": letter,
		"theme": pool[rng.randi() % pool.size()],
		"rooms": 8 + assignment * 3 + rng.randi_range(0, 6),
		"weather": Data.WEATHERS[rng.randi() % Data.WEATHERS.size()],
		"biome": "ARCTIC" if rng.randf() < 0.25 else "DESERT",
	}


func _ram_gate() -> void:
	term.close()
	busy = true
	hud.alert("RAMMING SPEED")
	Sfx.play(self, "horn", null, 0.0)
	await get_tree().create_timer(2.5, false).timeout
	Sfx.play(self, "boom", null, 4.0)
	game_over("ASSIGNMENT FAILED\nThe gate held. The train did not.\nYou have been factored in.")


func game_over(text: String) -> void:
	if over:
		return
	over = true
	busy = true
	player.frozen = true
	term.close()
	if stats.assignments > best:
		best = stats.assignments
		var f := FileAccess.open(BEST_PATH, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"best": best}))
	hud.big("%s\n\nAssignments completed: %d    Items shredded: %d    Credits earned: %d\nBest run: %d assignments\n\n[R] restart"
		% [text, stats.assignments, stats.shredded, stats.earned, best])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_died(cause: String) -> void:
	await get_tree().create_timer(1.5, false).timeout
	game_over("YOU DIED\n%s\nThe Bureau thanks you for your contribution." % cause)


func open_terminal() -> void:
	if over:
		return
	player.frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	term.open()


func _on_terminal_closed() -> void:
	if over:
		return
	player.frozen = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- terminal commands -------------------------------------------------------------

func _register_commands() -> void:
	term.add("HELP", 0, "HELP                      list commands", _c_help)
	term.add("BALANCE", 0, "BALANCE                   your credits", func(_a): term.say("Balance: %d credits" % credits))
	term.add("MARKET", 0, "MARKET                    quota + today's resource prices", _c_market)
	term.add("SHOP", 0, "SHOP                      items for sale", _c_shop)
	term.add("BUY", 1, "BUY <item> [n]            order items (shorthand ok: BUY FLA 2)", _c_buy)
	term.add("MAP", 0, "MAP                       assignment route", _c_map)
	term.add("VIEW_STATION", 1, "VIEW_STATION <letter>     station details", _c_view)
	term.add("ROUTE_TO", 1, "ROUTE_TO <letter>         depart now (CHECKPOINT after 3 stops)", _c_route)
	term.add("LEAVE_CHECKPOINT", 0, "LEAVE_CHECKPOINT          start the next assignment", _c_leave)
	term.add("SCAN_TRAIN", 0, "SCAN_TRAIN                resources stored on the train",
		_c_scan.bind("TRAIN", func(p): return train.contains(p.global_position)))
	term.add("SCAN_SURFACE", 0, "SCAN_SURFACE              resources left on the surface",
		_c_scan.bind("SURFACE", func(p): return p.global_position.y > UNDERGROUND_Y and not train.contains(p.global_position)))
	term.add("SCAN_FACILITY", 0, "SCAN_FACILITY             resources left in the facility",
		_c_scan.bind("FACILITY", func(p): return p.global_position.y <= UNDERGROUND_Y))
	term.add("OPEN_BULKHEAD", 1, "OPEN_BULKHEAD <code>      open a facility bulkhead", _c_bulkhead.bind(true))
	term.add("CLOSE_BULKHEAD", 1, "CLOSE_BULKHEAD <code>     close a facility bulkhead", _c_bulkhead.bind(false))
	term.add("UPGRADES", 0, "UPGRADES                  checkpoint shop upgrades", _c_upgrades)
	term.add("BUY_UPGRADE", 1, "BUY_UPGRADE <name>        buy an upgrade (at a checkpoint)", _c_buy_upgrade)
	term.add("LIST_CAMS", 0, "LIST_CAMS                 security cameras at this site", _c_list_cams)
	term.add("VIEW_CAM", 1, "VIEW_CAM <n>              watch a camera (arrows pan)", _c_view_cam)
	term.add("NEXT_CAM", 0, "NEXT_CAM                  next camera", func(_a): _c_view_cam([str(_cam_index + 2)]))
	term.add("PREV_CAM", 0, "PREV_CAM                  previous camera", func(_a): _c_view_cam([str(_cam_index)]))
	term.add("TOGGLE_LIGHT", 0, "TOGGLE_LIGHT              camera floodlight on/off", _c_toggle_light)
	term.add("EXIT_CAMS", 0, "EXIT_CAMS                 close the camera feed", func(_a): term.hide_monitor())
	term.add("MINIMAP", 0, "MINIMAP                   facility map (needs MINIMAP)", _c_minimap)
	term.add("EXIT_MINIMAP", 0, "EXIT_MINIMAP              close the map", func(_a): term.hide_monitor())
	term.add("LIST_LOGS", 0, "LIST_LOGS                 uploaded data logs", _c_list_logs)
	term.add("READ", 1, "READ <log>                read a data log", _c_read)
	term.add("CLEAR", 0, "CLEAR                     clear the screen", func(_a): term.clear())


func _c_help(_a) -> void:
	var names: Array = term.commands.keys()
	names.sort()
	for n in names:
		term.say("  " + term.commands[n].usage)


func _c_market(_a) -> void:
	term.say("Credits: %d" % credits)
	var parts := PackedStringArray()
	for r in Data.RES:
		parts.append("%s %.1f" % [r.to_upper(), prices[r]])
	term.say("Market today (credits per unit shredded):  " + "   ".join(parts))
	if assignment > 0:
		term.say("Assignment %d quota: %s" % [assignment, Data.res_text(quota)])


func _c_shop(_a) -> void:
	term.say("SHOP   (delivered to the cargo car)   balance: %d" % credits)
	for id in Data.SHOP:
		var d: Dictionary = Data.ITEMS[id]
		term.say("  %-12s %4d   %s" % [id, d.price, d.desc])


func _c_buy(a) -> void:
	var id := Terminal.complete(a[0], Data.SHOP)
	if not (id in Data.SHOP):
		term.error("Unknown item '%s'. Type SHOP." % a[0])
		return
	var n := clampi(a[1].to_int(), 1, 10) if a.size() > 1 else 1
	var cost: int = Data.ITEMS[id].price * n
	if cost > credits:
		term.error("Insufficient credits: %d needed, %d available." % [cost, credits])
		return
	credits -= cost
	for i in n:
		_orders.append(id)
	term.say("Purchased %d x %s for %d credits." % [n, Data.ITEMS[id].name, cost])
	term.say("A delivery handcar is on its way to the back of the train (%s)." % ("a few seconds" if has_upgrade("QUICK_DELIVERY") else "about a minute"))
	_dispatch_handcar()
	Sfx.play(self, "ding", null, -8.0)


func _c_map(_a) -> void:
	if route.is_empty():
		term.say("No active route. Use LEAVE_CHECKPOINT.")
		return
	term.say("ASSIGNMENT %d ROUTE      you are at: %s" % [assignment, stop.letter])
	for i in 3:
		var row := "  STOP %d:  " % (i + 1)
		for o in route[i]:
			var chosen: bool = i < taken.size() and taken[i] == o.letter
			row += (">%s< " if chosen else " %s  ") % o.letter
		if i == stage + 1:
			row += "   <- next"
		term.say(row)
	term.say("  STOP 4:  CHECKPOINT" + ("   <- next" if stage >= 2 else ""))
	term.say("VIEW_STATION <letter> for details, ROUTE_TO <letter> to depart.")


func _find_stop(letter: String) -> Dictionary:
	for stage_opts in route:
		for o in stage_opts:
			if o.letter == letter:
				return o
	return {}


func _c_view(a) -> void:
	var o := _find_stop(a[0])
	if o.is_empty():
		term.error("No station '%s' on this route." % a[0])
		return
	var size := "SMALL" if o.rooms < 14 else ("MEDIUM" if o.rooms < 22 else "LARGE")
	var hz := PackedStringArray()
	for h in Data.SITE_HAZARDS[o.theme]:
		hz.append(Data.HAZARD_NAMES[h])
	var often := PackedStringArray()
	var never := PackedStringArray()
	for k in Data.HABITAT[o.theme]:
		var w: float = Data.HABITAT[o.theme][k]
		if w >= 1.4:
			often.append(k.to_upper())
		elif w == 0.0:
			never.append(k.to_upper())
	term.say("STATION %s\n  Facility:  %s\n  Size:      %s (%d sectors)\n  Surface:   %s\n  Weather:   %s\n  Hazards:   %s\n  Sightings: frequent %s%s"
		% [o.letter, o.theme, size, o.rooms, o.biome, o.weather.replace("_", " ") if has_upgrade("WEATHERVANE") else "UNKNOWN (needs WEATHERVANE)",
		", ".join(hz), ", ".join(often), ("   none: " + ", ".join(never)) if not never.is_empty() else ""])


func _c_route(a) -> void:
	var t: String = a[0]
	if busy:
		term.error("The train is already in motion.")
		return
	if at_checkpoint and not departed:
		term.error("The gate is closed. Use LEAVE_CHECKPOINT.")
		return
	var nxt := stage + 1
	if nxt >= 3:
		if "CHECKPOINT".begins_with(t):
			_depart(CHECKPOINT_STOP)
		else:
			term.error("Final stop reached. ROUTE_TO CHECKPOINT.")
		return
	for o in route[nxt]:
		if o.letter == t:
			_depart(o)
			return
	var letters := PackedStringArray()
	for o in route[nxt]:
		letters.append(o.letter)
	term.error("Invalid destination. Next stop options: " + ", ".join(letters))


func _c_leave(_a) -> void:
	if not at_checkpoint:
		term.error("The train is not at a checkpoint.")
		return
	if departed:
		term.error("Assignment already issued. Use ROUTE_TO.")
		return
	if assignment > 0 and not _quota_met():
		term.say("[color=#ff6a5a]WARNING: assignment quota not met. The gate will not open.[/color]")
		term.say("Proceed anyway? (YES/NO)")
		term.confirm = _ram_gate
		return
	_start_assignment()


func _c_scan(_a, where: String, filter: Callable) -> void:
	var items := _items_in(filter)
	var c := _count(items)
	term.say("%s: %d items   STEEL %d   COPPER %d   RUBBER %d   PLASTIC %d"
		% [where, items.size(), c.get("steel", 0), c.get("copper", 0), c.get("rubber", 0), c.get("plastic", 0)])
	if items.is_empty() and where != "TRAIN":
		term.say("Area has been cleared of scrap, good work.")


func _c_bulkhead(a, open: bool) -> void:
	if level != null and not level.powered():
		term.error("Bulkhead control offline: site power failure. Reset the main breaker.")
		return
	if level == null or level.facility == null or not level.facility.set_door(a[0], open):
		term.error("No bulkhead '%s' at this station." % a[0])
		return
	term.say("Bulkhead %s %s." % [a[0], "opened" if open else "closed"])


# --- world setup ------------------------------------------------------------------

func _setup_input() -> void:
	var keys := {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"sprint": KEY_SHIFT, "crouch": KEY_CTRL, "jump": KEY_SPACE, "interact": KEY_E,
		"drop": KEY_Q, "drop_equip": KEY_C, "scan": KEY_F, "restart": KEY_R,
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var e := InputEventKey.new()
		e.physical_keycode = keys[action]
		InputMap.action_add_event(action, e)


func _setup_world() -> void:
	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_detail_spread = 1.5
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_color = Color(1, 0.82, 0.62)
	sun.directional_shadow_max_distance = 120.0
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)


func _update_env() -> void:
	var under: bool = player.global_position.y < UNDERGROUND_Y
	var h := 11.0 if at_checkpoint else hours
	var day := clampf(remap(h, 16.5, 21.0, 1.0, 0.0), 0.0, 1.0)
	var dusk := clampf(1.0 - absf(h - 18.5) / 2.5, 0.0, 1.0)
	var arctic: bool = stop.get("biome", "") == "ARCTIC"
	var weather: String = stop.get("weather", "CLEAR")
	train.headlight.light_energy = lerpf(6.0, 1.5, day)
	sun.visible = not under
	if under:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color.BLACK
		env.ambient_light_color = Color(0.5, 0.45, 0.4)
		env.ambient_light_energy = 0.12
		env.volumetric_fog_density = 0.03
		env.volumetric_fog_albedo = Color(0.45, 0.38, 0.32)
		env.volumetric_fog_emission = Color.BLACK
		return
	# Hazy wasteland: dusty orange by day, rust-red at dusk, near black at night.
	var haze := Color(0.82, 0.6, 0.42) if not arctic else Color(0.78, 0.8, 0.85)
	var sky_day := Color(0.62, 0.45, 0.32) if not arctic else Color(0.55, 0.6, 0.7)
	var sky_dusk := Color(0.5, 0.18, 0.08)
	var night := Color(0.02, 0.015, 0.02)
	sun.light_energy = 1.4 * day
	sun.light_color = Color(1, 0.85, 0.65).lerp(Color(1, 0.45, 0.2), dusk)
	sun.rotation_degrees.x = -8.0 - 50.0 * sin(PI * clampf((h - 6.0) / 16.0, 0.0, 1.0))
	env.background_mode = Environment.BG_SKY
	var top := sky_day.lerp(sky_dusk, dusk).lerp(night, 1.0 - day)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = haze.lerp(Color(0.7, 0.3, 0.12), dusk).lerp(night, 1.0 - day)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = top.darkened(0.5)
	env.ambient_light_color = haze
	env.ambient_light_energy = lerpf(0.04, 0.45, day)
	var density: float = {"SANDSTORM": 0.09, "ACID_RAIN": 0.03}.get(weather, 0.012) + (0.01 if arctic else 0.0)
	env.volumetric_fog_density = density
	var fog_col := haze
	if weather == "ACID_RAIN":
		fog_col = Color(0.55, 0.65, 0.35)
	env.volumetric_fog_albedo = fog_col
	env.volumetric_fog_emission = fog_col * 0.12 * day


# --- progression / terminal features ---------------------------------------------------

func _c_upgrades(_a) -> void:
	term.say("UPGRADES   (permanent for this run; buy at a checkpoint)   balance: %d" % credits)
	for u in Data.UPGRADES:
		var d: Dictionary = Data.UPGRADES[u]
		term.say("  %-15s %4s   %s" % [u, "OWNED" if has_upgrade(u) else str(d.price), d.desc])


func _c_buy_upgrade(a) -> void:
	var u := Terminal.complete(a[0], Data.UPGRADES.keys())
	if not Data.UPGRADES.has(u):
		term.error("Unknown upgrade '%s'. Type UPGRADES." % a[0])
		return
	if not at_checkpoint:
		term.error("Upgrades can only be installed at a checkpoint.")
		return
	if has_upgrade(u):
		term.error("%s is already installed." % u)
		return
	var price: int = Data.UPGRADES[u].price
	if price > credits:
		term.error("Insufficient credits: %d needed, %d available." % [price, credits])
		return
	credits -= price
	upgrades[u] = true
	match u:
		"BETTER_BOOTS":
			player.max_stamina = player.MAX_STAMINA * 2.0
		"STORAGE_CAR":
			train.add_storage_car()
		"DIGITAL_CLOCK":
			train.add_digital_clock()
	Sfx.play(self, "ding", null, -6.0)
	term.say("%s installed." % u)


func _cams() -> Array:
	if level == null or level.facility == null or not level.powered():
		return []
	return level.facility.cameras


func _c_list_cams(_a) -> void:
	if level != null and not level.powered():
		term.error("NO SIGNAL: site power failure. Reset the main breaker.")
		return
	var cams := _cams()
	if cams.is_empty():
		term.say("No security cameras at this location.")
		return
	term.say("Scanning for cameras.....\n%d camera(s) found:" % cams.size())
	for c in cams:
		term.say("  [%s]" % c.name)
	term.say("Use VIEW_CAM <n> to view a feed. Arrow keys pan.")


func _c_view_cam(a) -> void:
	if level != null and not level.powered():
		term.error("NO SIGNAL: site power failure. Reset the main breaker.")
		return
	var cams := _cams()
	if cams.is_empty():
		term.error("No security cameras at this location.")
		return
	var n := String(a[0]).replace("CAM_", "").to_int()
	if n < 1 or n > cams.size():
		term.error("No camera %s. Cameras 1-%d." % [a[0], cams.size()])
		return
	_cam_index = n - 1
	term.show_camera(cams[_cam_index].node, cams[_cam_index].name)
	term.say("Loading feed %s..." % cams[_cam_index].name)


func _c_toggle_light(_a) -> void:
	var cams := _cams()
	if cams.is_empty() or not term.monitor.visible or not term.feed.visible:
		term.error("View a camera first.")
		return
	var l: SpotLight3D = cams[_cam_index].light
	l.visible = not l.visible
	term.say("Floodlight %s." % ("on" if l.visible else "off"))


func _c_minimap(_a) -> void:
	if not has_upgrade("MINIMAP"):
		term.error("Requires the MINIMAP upgrade.")
		return
	term.show_map(draw_site_map, "SITE MAP  %s" % stop.get("letter", ""))


func _c_list_logs(_a) -> void:
	if logs_unlocked == 0:
		term.say("No logs on file. Data disks can be found inside the facilities.")
		return
	term.say("LOGS ON FILE:")
	for i in logs_unlocked:
		term.say("  %s" % Data.LOGS[i][0])


func _c_read(a) -> void:
	for i in logs_unlocked:
		if Data.LOGS[i][0] == Terminal.complete(a[0], [Data.LOGS[i][0]]):
			term.say("----- %s -----\n%s\n-----" % [Data.LOGS[i][0], Data.LOGS[i][1]])
			return
	term.error("No log named '%s' on file. Type LIST_LOGS." % a[0])


## Rolls the handcar in from behind the train with everything ordered so far.
func _dispatch_handcar() -> void:
	if _handcar_busy or _orders.is_empty():
		return
	_handcar_busy = true
	if _handcar == null:
		_handcar = train.make_handcar()
	var stop_x: float = train.rear_x() - 2.0
	_handcar.position.x = stop_x - 70.0
	var secs := (6.0 if has_upgrade("QUICK_DELIVERY") else 45.0) * Data.pace()
	var tw := create_tween()
	tw.tween_property(_handcar, "position:x", stop_x, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if tw.is_running():   # a long frame can finish it before we get here
		await tw.finished
	var batch := _orders.duplicate()
	_orders.clear()
	for i in batch.size():
		spawn_item(batch[i], train.to_global(Vector3(stop_x + rng.randf_range(-0.8, 0.8), 1.2 + i * 0.25, rng.randf_range(-0.6, 0.6))), -1.0, train)
	Sfx.play(self, "ding", train.to_global(Vector3(stop_x, 1.5, 0)), 0.0)
	hud.msg("Delivery arrived on the handcar at the back of the train.")
	_handcar_busy = false
	_dispatch_handcar()


# --- maps -------------------------------------------------------------------------------

## Whole-site map for the terminal: rooms, doors, bulkheads, scrap, monsters, you.
func draw_site_map(ctrl: Control) -> void:
	var font := ThemeDB.fallback_font
	var amber := Color(1, 0.62, 0.22)
	if level == null or level.facility == null:
		ctrl.draw_string(font, Vector2(20, 60), "NO SITE AT THIS STOP", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, amber)
		return
	var fac = level.facility
	var cells: Array = fac.layout.cells
	var lo := Vector2i(999, 999)
	var hi := Vector2i(-999, -999)
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var span := Vector2(hi - lo) + Vector2.ONE
	var area := ctrl.size - Vector2(40, 80)
	var cs := minf(area.x / span.x, area.y / span.y)
	var off := Vector2(20, 60) + (area - span * cs) / 2.0
	var to_map := func(world: Vector3) -> Vector2:
		var l: Vector3 = fac.to_local(world) / Facility.CELL
		return off + (Vector2(l.x, l.z) - Vector2(lo) + Vector2(0.5, 0.5)) * cs
	for c in cells:
		var p := off + Vector2(c - lo) * cs
		ctrl.draw_rect(Rect2(p + Vector2.ONE * cs * 0.08, Vector2.ONE * cs * 0.84), Color(amber, 0.12))
		ctrl.draw_rect(Rect2(p + Vector2.ONE * cs * 0.08, Vector2.ONE * cs * 0.84), Color(amber, 0.7), false, 2.0)
		for n in fac.layout.links[c]:
			if n.x > c.x or n.y > c.y:
				var mid := off + (Vector2(c - lo) + Vector2(n - lo)) * cs / 2.0 + Vector2.ONE * cs * 0.5
				ctrl.draw_rect(Rect2(mid - Vector2.ONE * cs * 0.12, Vector2.ONE * cs * 0.24), Color(amber, 0.35))
		if c == Vector2i.ZERO:
			ctrl.draw_string(font, p + Vector2(cs * 0.15, cs * 0.55), "LIFT", HORIZONTAL_ALIGNMENT_LEFT, -1, int(cs * 0.22), amber)
	var hz = level.hazards
	for c in hz.flooded:
		ctrl.draw_rect(Rect2(off + Vector2(c - lo) * cs + Vector2.ONE * cs * 0.1, Vector2.ONE * cs * 0.8), Color(0.3, 0.55, 1.0, 0.22))
	for c in hz.gassed:
		ctrl.draw_rect(Rect2(off + Vector2(c - lo) * cs + Vector2.ONE * cs * 0.1, Vector2.ONE * cs * 0.8), Color(0.6, 0.9, 0.2, 0.25))
	if hz.breaker:
		var bp: Vector2 = to_map.call(hz.breaker.global_position)
		ctrl.draw_rect(Rect2(bp - Vector2.ONE * cs * 0.07, Vector2.ONE * cs * 0.14), Color(1, 0.85, 0.2) if hz.power else Color(1, 0.2, 0.1))
		ctrl.draw_string(font, bp + Vector2(cs * 0.1, cs * 0.05), "BRK", HORIZONTAL_ALIGNMENT_LEFT, -1, int(cs * 0.18), Color(1, 0.85, 0.3))
	for code in fac.doors:
		var door: Node3D = fac.doors[code]
		var mp: Vector2 = to_map.call(door.global_position)
		var open: bool = door.get_meta("open")
		ctrl.draw_circle(mp, cs * 0.09, Color(0.3, 1, 0.3) if open else Color(1, 0.25, 0.15))
		ctrl.draw_string(font, mp + Vector2(cs * 0.1, -cs * 0.08), code, HORIZONTAL_ALIGNMENT_LEFT, -1, int(cs * 0.2), Color(1, 0.85, 0.3))
	for p in get_tree().get_nodes_in_group("pickups"):
		if p.global_position.y < UNDERGROUND_Y:
			ctrl.draw_circle(to_map.call(p.global_position), maxf(2.0, cs * 0.035), Color(0.4, 1, 0.5))
	for m in get_tree().get_nodes_in_group("monsters"):
		if not m.is_in_group("hide_on_map"):
			ctrl.draw_circle(to_map.call(m.global_position), maxf(3.0, cs * 0.05), Color(1, 0.15, 0.1))
	if player.global_position.y < UNDERGROUND_Y:
		var pp: Vector2 = to_map.call(player.global_position)
		var fwd := Vector2(-sin(player.rotation.y), -cos(player.rotation.y))
		var side := Vector2(-fwd.y, fwd.x)
		ctrl.draw_colored_polygon(PackedVector2Array([pp + fwd * 9, pp - fwd * 6 + side * 6, pp - fwd * 6 - side * 6]), Color.WHITE)
	ctrl.draw_string(font, Vector2(20, ctrl.size.y - 16), "green: scrap   red: entity   dots on walls: bulkheads   BRK: breaker   blue: flooded   lime: gas", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(amber, 0.8))


## Heading-up HUD minimap around the player (MINIMAP upgrade, underground only).
func draw_minimap(ctrl: Control, center: Vector2, radius: float) -> void:
	if not has_upgrade("MINIMAP") or level == null or level.facility == null or player.global_position.y > UNDERGROUND_Y:
		return
	var fac = level.facility
	var px := 3.2  # pixels per metre
	ctrl.draw_rect(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2), Color(0, 0, 0, 0.55))
	ctrl.draw_set_transform(center, player.rotation.y, Vector2.ONE)
	var me: Vector3 = fac.to_local(player.global_position)
	for c in fac.layout.cells:
		var rel := Vector2(c.x * Facility.CELL - me.x, c.y * Facility.CELL - me.z) * px
		if rel.length() > radius + Facility.CELL * px:
			continue
		var half := Facility.CELL * px * 0.45
		ctrl.draw_rect(Rect2(rel - Vector2.ONE * half, Vector2.ONE * half * 2), Color(1, 0.62, 0.22, 0.65), false, 2.0)
		for n in fac.layout.links[c]:
			var d := Vector2(n.x - c.x, n.y - c.y)
			ctrl.draw_line(rel + d * half, rel + d * Facility.CELL * px * 0.5, Color(1, 0.62, 0.22, 0.65), 3.0)
	for m in get_tree().get_nodes_in_group("monsters"):
		if m.is_in_group("hide_on_map"):
			continue
		var l: Vector3 = fac.to_local(m.global_position)
		var rel := Vector2(l.x - me.x, l.z - me.z) * px
		if rel.length() < radius:
			ctrl.draw_circle(rel, 3.5, Color(1, 0.15, 0.1))
	ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ctrl.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -8), center + Vector2(6, 6), center + Vector2(-6, 6)]), Color.WHITE)
	ctrl.draw_rect(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2), Color(0.95, 0.93, 0.88, 0.8), false, 2.0)
