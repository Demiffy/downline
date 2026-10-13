# Game state + the loop:
#   CHECKPOINT --LEAVE_CHECKPOINT--> 3 stations (ROUTE_TO, one day each) --> CHECKPOINT (shred, meet quota) ...
extends Node3D

const Data = preload("res://src/data.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")
const Player = preload("res://src/player.gd")
const Pickup = preload("res://src/pickup.gd")
const Ragdoll = preload("res://src/ragdoll.gd")
const A = preload("res://src/art.gd")
const Level = preload("res://src/level.gd")
const Hud = preload("res://src/hud.gd")
const Terminal = preload("res://src/terminal.gd")
const Train = preload("res://src/train.gd")
const Facility = preload("res://src/facility.gd")
const Settings = preload("res://src/settings.gd")
const Menu = preload("res://src/menu.gd")
const ScanFx = preload("res://src/scanfx.gd")
const Save = preload("res://src/save.gd")
const Blast = preload("res://src/blast.gd")
const Marks = preload("res://src/marks.gd")
const Line = preload("res://src/line.gd")

const DAY_SECONDS := 720.0   # real seconds from 08:00 to 24:00
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
var sky_mat: ShaderMaterial   # (weather.gd's sky)
var weather   # weather.gd
var line      # line.gd: the country between stops, and the trip through it

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
var _cp_items := 0         # shredded at this checkpoint (the shift report)
var _lost_from := 0        # stats.lost when this assignment began
var _reported := false     # the shift report's been given at this checkpoint
var report                 # report.gd
var _rank_bonus_paid := 0
var _amb: Array[AudioStreamPlayer] = []
var _amb_i := 0
var _amb_bed := ""
var _space := ""
var _sting := 10.0
var _travelling := false   # between pulling out and arriving: leaving the train strands you
var _stranded := false
var _arriving := false     # the train's running into the platform: stepping off then just drops you at the station
var _missed := false       # the train left without you (you weren't aboard when it pulled out)
var _fee_charged := 0
var _recovering := false   # mid write-off (death / left behind): nothing else can end the run now
var _remains_t := 0.0     # looking for remains brought aboard, twice a second
var _acid_t := {}         # player -> seconds out in the acid rain
const RECOVERY_PAY := 20   # the Bureau's fee for bringing a body back
const REPLACEMENT_FEE := 40     # what the Bureau charges for a replacement employee...
const REPLACEMENT_STEP := 20    # ...and how much dearer each one is than the last, this assignment
const REPLACEMENT_MAX := 140
const WIPE_RECALL := 0.5        # hours left on the clock when a whole crew is lost at a stop
var fees := 0             # replacement fees charged this assignment (the shift report)
var _down := {}           # host: who's died lately -> when (msec), to tell when the whole crew's gone
var bank := {}            # the Bureau's bonded stock: resource -> units banked at the checkpoint, kept between assignments
var divert_bank := false  # the shredder's diverter: false sells everything, true banks whatever's past the quota
var _banked_now := 0      # units banked at this checkpoint visit (the shift report)
var _cycle_value := 0.0   # what this shredder cycle was worth at today's prices, sold or banked
var crew_size := 1        # how many were on the crew when the assignment was issued (the quota's sized for them)
var busy := false
var over := false
var _letter := 0
var upgrades := {}        # name -> true
var logs_unlocked := 0
var stats := {"assignments": 0, "shredded": 0, "earned": 0, "lost": 0}
var best := 0
var _cam_index := 0
var _orders: Array = []   # item ids waiting for the delivery handcar
var _handcar: Node3D
var _handcar_busy := false
const BEST_PATH := "user://best_run.json"
const GUIDE_PATH := "user://field_guide.json"
var guide := {"seen": {}, "killed": {}}
var photo_log: Array = []     # every photo taken this run, oldest first: [{tex, stamp}, ...] (the pause menu shows them)
var crew_pockets := {}        # host: what each crewmate last had on them, by name (a save keeps it; they get it back on joining)
var save_path := Save.PATH
var autosaves := false        # the real game saves the run; tests turn it on themselves
var _autosave_t := 120.0
const AUTOSAVE_EVERY := 120.0
var net                   # /root/Net (net.gd): the multiplayer session, if any
var level_seed := 0       # the seed the current stop was built from (sent to anyone joining)
var level_serial := 0     # how many stops have been built this run (keeps late messages off the wrong level)
const NET_CMDS := ["BUY", "STOCK", "ROUTE_TO", "LEAVE_CHECKPOINT", "OPEN_BULKHEAD", "CLOSE_BULKHEAD", "BUY_UPGRADE"]   # the host runs these   # the field guide: kinds identified, and how many killed


# Light and the train's walls. A lamp with no shadow shines through any wall, so: the train's own
# body is on its own render layer (TRAIN_BIT, given to whatever's built into it as it arrives:
# _on_node_added). While the camera's inside the train, every shadowless lamp out in the world
# (tunnel lamps, platform lamps) skips that layer, so none shines in through the walls; outside, they
# light the hull as ever, and the train's own lamps cast shadows instead (`train.lamp_shadows`), so
# their light only gets out through the windows. Nothing moves at a stand: those shadows are drawn once.
const TRAIN_BIT := 1 << 6
var _world_lights: Array = []
var _cam_in_train := true   # (so a start outside it turns the train lamps' shadows on)


func _on_node_added(n: Node) -> void:
	if train == null or not train.is_ancestor_of(n):
		if n is Light3D and not n is DirectionalLight3D:
			_world_lights.append(n)
			_mask_light(n)
		return
	if n is GeometryInstance3D and (n as GeometryInstance3D).layers == 1:
		var p := n.get_parent()
		while p != train:   # (not a crewmate's suit, nor anything carried or dropped aboard)
			if p is CharacterBody3D or p is RigidBody3D:
				return
			p = p.get_parent()
		(n as GeometryInstance3D).layers = TRAIN_BIT


func _mask_light(l: Light3D) -> void:
	if _cam_in_train and not l.shadow_enabled:
		l.light_cull_mask &= ~TRAIN_BIT
	else:
		l.light_cull_mask |= TRAIN_BIT


func _train_light() -> void:
	var cam := get_viewport().get_camera_3d()
	var inside: bool = cam != null and train.contains(cam.global_position)
	if inside == _cam_in_train:
		return
	_cam_in_train = inside
	_world_lights = _world_lights.filter(func(l): return is_instance_valid(l))
	for l: Light3D in _world_lights:
		_mask_light(l)
	train.lamp_shadows(not inside)


var _script_run := OS.get_cmdline_args().has("-s") and DisplayServer.get_name() != "headless"   # (a test script with a window, not the game)
var _drawn := 1   # frames drawn since the last _process (counted for a test script)


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	if _script_run:
		RenderingServer.frame_post_draw.connect(func(): _drawn += 1)
	preload("res://src/mark.gd").apply()   # (the window's icon, when the game's run straight: the playground, tests)
	if Engine.has_meta("hush"):   # (the launcher's quiet while loading: over a moment after we're up)
		get_tree().create_timer(0.6).timeout.connect(func(): Engine.remove_meta("hush"))
	Sfx.setup()
	rng.randomize()
	if Engine.has_meta("test_seed"):   # (a test that needs a particular kind of site: the same route every time)
		rng.seed = int(Engine.get_meta("test_seed"))
	net = load("res://src/net.gd").get_or_make(get_tree())
	net.attach(self)
	net.left.connect(_on_net_left)
	_load_guide.call_deferred()
	_setup_input()
	_setup_world()
	train = Train.new()
	train.name = "Train"
	add_child(train)
	train.build(open_terminal)
	train.add_charger(func(): player.recharge())
	line = Line.new()
	line.name = "Line"
	line.main = self
	add_child(line)
	report = load("res://src/report.gd").new()
	report.main = self
	add_child(report)
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
	autosaves = get_tree().current_scene == self and not "playground" in OS.get_cmdline_user_args()
	if get_tree().current_scene == self and not "playground" in OS.get_cmdline_user_args() and not net.active:
		var lobby = load("res://src/lobby.gd").new()   # title screen: solo, host or join
		lobby.main = self
		add_child(lobby)


func players() -> Array:
	return get_tree().get_nodes_in_group("players")


func has_upgrade(name: String) -> bool:
	return upgrades.has(name)


## When the train leaves a station: midnight, or 01:00 with the OVERTIME_PERMIT.
func depart_hour() -> float:
	return 25.0 if has_upgrade("OVERTIME_PERMIT") else 24.0


func charge_max(id: String) -> float:
	if Data.kind(id) == "weapon":   # shells, not battery: what it holds
		return float(Data.ITEMS[id].get("magazine", Data.ITEMS[id].get("charge", 1.0)))
	if Data.kind(id) == "ammo":
		return float(Data.ITEMS[id].get("charge", 1.0))
	return float(Data.ITEMS[id].get("charge", 1.0)) * (1.6 if has_upgrade("BATTERY_PACK") else 1.0)


func open_shop() -> void:
	if level and level.has_node("YardLife"):
		level.get_node("YardLife").clerk_stamp()
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


func spawn_item(id: String, pos: Vector3, charge := -1.0, parent: Node = null, pose := "drop") -> Node3D:
	if not net.authority():
		return null   # the host makes items; we see its copies
	if id == "REMAINS":   # a body, not a box: it's a ragdoll
		var r := Ragdoll.new()
		r.pose = pose
		(parent if parent != null else (level if level != null else train)).add_child(r)
		r.global_position = pos
		net.register(r, {"k": "rag", "pose": pose})
		return r
	var p := Pickup.new()
	p.setup(id, charge)
	if parent == null:
		parent = level if level != null else train
	parent.add_child(p)
	p.global_position = pos
	net.register(p, {"k": "item", "id": id, "charge": p.charge})
	return p


## A hit's mark on the world (marks.gd), here and for the crew: on the train if it's there, else the stop.
func mark(pos: Vector3, normal: Vector3, kind: String, along := Vector3.ZERO) -> void:
	var host: Node3D = train if train.on_board(pos) else (level if level != null else self)
	Marks.hit(host, pos, normal, kind, along)
	net.mark(host, pos, normal, kind, along)


## Something made a sound at pos audible within radius. Blind monsters care.
func noise(pos: Vector3, radius: float) -> void:
	if not net.authority():
		net.request("noise", [pos, radius])   # creatures only listen on the host
		return
	for m in get_tree().get_nodes_in_group("hearing"):
		var d: float = m.global_position.distance_to(pos)
		if d < radius and _carries(pos, m.global_position, radius):
			m.hear(pos)
	for m in get_tree().get_nodes_in_group("ground_listeners"):
		m.hear(pos)


## Does a sound made at `from` reach a listener at `to`? Straight across open space, yes. Through a
## wall or a shut bulkhead it keeps only 30% of its reach (a footstep, a couple of metres; a bang,
## the room next door). Otherwise the way you could walk it, round corners, losing reach as it goes.
func _carries(from: Vector3, to: Vector3, radius: float) -> bool:
	if _clear_line(from + Vector3.UP * 0.5, to + Vector3.UP):
		return true
	if from.distance_to(to) < radius * 0.3:
		return true
	var fac = level.facility if level != null else null
	if fac == null or fac.nav == null or from.y > UNDERGROUND_Y or to.y > UNDERGROUND_Y:
		return false
	var path: PackedVector3Array = fac.nav_path(from, to)
	if path.size() < 2 or path[-1].distance_to(to) > 1.5:
		return false
	var length := from.distance_to(path[0])
	for i in path.size() - 1:
		length += path[i].distance_to(path[i + 1])
	return length < radius * 0.6


func _clear_line(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	q.exclude = get_tree().get_nodes_in_group("monsters").map(func(m): return m.get_rid())
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func explode(pos: Vector3, radius: float, dmg: float, cause: String) -> void:
	net.event("explode", [pos, radius, dmg, cause])   # (everyone sees the flash; only the host's damage counts)
	for p in players():
		var d: float = pos.distance_to(p.global_position + Vector3.UP)
		if d < radius and _blast_reaches(pos, p):
			p.hurt(dmg * (1.0 - d / radius), cause)
			if not p.dead and p == player:
				hud.msg(cause)   # blasts often come from round a corner; say what it was
	Sfx.play(self, "boom", pos, 8.0)
	Blast.at(self, pos, radius, "flesh" if "pulsator" in cause.to_lower() else "fire")
	noise(pos, 25.0)
	if player.global_position.distance_to(pos) < radius * 2.5:
		player.shake(0.06 * clampf(1.0 - player.global_position.distance_to(pos) / (radius * 2.5), 0.2, 1.0))


## Does a blast at `pos` get to player p? Walls, floors and closed doors stop it: it needs a clear
## line to their head, chest or knees.
func _blast_reaches(pos: Vector3, p) -> bool:
	var space := get_world_3d().direct_space_state
	var from := pos + Vector3(0, 0.6, 0)
	for h in [1.6, 1.0, 0.4]:
		var q := PhysicsRayQueryParameters3D.create(from, p.global_position + Vector3(0, h, 0), 1)
		q.exclude = get_tree().get_nodes_in_group("monsters").map(func(m): return m.get_rid())
		if space.intersect_ray(q).is_empty():
			return true
	return false


func scan(origin: Vector3, radius: float) -> void:
	var hits := []
	for p in get_tree().get_nodes_in_group("pickups"):
		var d := origin.distance_to(p.global_position)
		if d <= radius and not train.contains(p.global_position) and Data.kind(p.id) != "remains":
			var res: Dictionary = Data.ITEMS[p.id].res
			var worth := 0.0
			for r in res:
				worth += res[r] * prices.get(r, 0.0)
			var detail := Data.res_text(res) + ("   ~%d cr" % roundi(worth) if worth > 0.0 else "")
			if Data.is_heavy(p.id):
				detail = "HEAVY   " + detail
			hits.append(_hit(p, d, "scrap", Data.ITEMS[p.id].name.to_upper(), detail, Data.ITEMS[p.id].size.y * 0.5 + 0.3, Data.value_units(p.id)))
	for m in get_tree().get_nodes_in_group("monsters") + get_tree().get_nodes_in_group("fauna"):
		var d := origin.distance_to(m.global_position)
		if d <= radius:
			var kind := creature_kind(m)
			var fresh := guide_seen(kind)
			var label: String = Data.GUIDE[kind].name if Data.GUIDE.has(kind) else "UNKNOWN ENTITY"
			hits.append(_hit(m, d, "entity", label, ("NEW FIELD GUIDE ENTRY" if fresh else "%d m" % roundi(d)), 2.3))
	for t in get_tree().get_nodes_in_group("scan_targets"):   # breaker panel, airdrops
		var d := origin.distance_to(t.global_position)
		if d <= radius * 1.5:
			hits.append(_hit(t, d, "poi", t.get_meta("scan_name"), "%d m" % roundi(d), 2.2))
	var now := Time.get_ticks_msec() / 1000.0
	for h in hits:   # (the minimap shows what the scanner found, and nothing else)
		if h.kind in ["scrap", "entity"]:
			scanned[h.node] = [h.node.global_position, now, h.kind]
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


# --- field guide -----------------------------------------------------------------------

## A creature's field-guide key: its script's name (warden.gd -> "warden").
static func creature_kind(n: Node) -> String:
	var sc: Script = n.get_script()
	return sc.resource_path.get_file().get_basename() if sc else ""


## Logs a creature in the field guide. True if this was the first time.
func guide_seen(kind: String) -> bool:
	if not Data.GUIDE.has(kind) or guide.seen.has(kind):
		return false
	guide.seen[kind] = true
	_save_guide()
	hud.alert("FIELD GUIDE: new entry, %s   (terminal: GUIDE %s)" % [Data.GUIDE[kind].name, kind.to_upper()])
	Sfx.play(self, "blip", null, -4.0, 0.8)
	return true


func guide_killed(kind: String) -> void:
	if not Data.GUIDE.has(kind):
		return
	guide.killed[kind] = int(guide.killed.get(kind, 0)) + 1
	_save_guide()


## Only the real game keeps the guide on disk (test scripts run without a current scene).
func _keeps_files() -> bool:
	return is_inside_tree() and get_tree().current_scene == self


func _load_guide() -> void:
	if not _keeps_files() or not FileAccess.file_exists(GUIDE_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(GUIDE_PATH))
	if d is Dictionary:
		guide.seen = d.get("seen", {})
		guide.killed = d.get("killed", {})


func _save_guide() -> void:
	if not _keeps_files():
		return
	var f := FileAccess.open(GUIDE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(guide))


func _c_guide(a) -> void:
	var kinds: Array = Data.GUIDE.keys()
	if a.is_empty():
		term.say("B.R.M. FIELD GUIDE   %d of %d identified" % [guide.seen.size(), kinds.size()])
		for k in kinds:
			if guide.seen.has(k):
				var kills: int = guide.killed.get(k, 0)
				term.say("  %-12s threat: %-9s%s" % [k.to_upper(), Data.GUIDE[k].threat, ("  killed: %d" % kills) if kills > 0 else ""])
			else:
				term.say("  ??????????   (scan it to identify)")
		term.say("GUIDE <name> to read an entry.")
		return
	var known: Array = kinds.filter(func(k): return guide.seen.has(k)).map(func(k): return k.to_upper())
	var want := Terminal.complete(String(a[0]).to_upper(), known)
	if not want in known:
		term.error("No entry for '%s'. Unidentified creatures have to be scanned first." % a[0])
		return
	var e: Dictionary = Data.GUIDE[want.to_lower()]
	var kills: int = guide.killed.get(want.to_lower(), 0)
	term.say("----- %s -----   threat: %s%s" % [e.name, e.threat, ("   killed: %d" % kills) if kills > 0 else ""])
	term.say("FOUND:   %s\nSIGNS:   %s\nHABITS:  %s\nCOUNTER: %s\n-----" % [e.where, e.signs, e.habits, e.counter])


func _hit(node: Node3D, d: float, kind: String, name: String, detail: String, lift: float, value := 0) -> Dictionary:
	return {"node": node, "d": d, "kind": kind, "name": name, "detail": detail, "lift": lift, "value": value,
		"lit": false, "t": 0.0, "meshes": [], "tag": null, "ring": null}


# --- frame loop ----------------------------------------------------------------

func _unhandled_key_input(e: InputEvent) -> void:
	# F11 or Alt+Enter: fullscreen on/off. The UI scales with the window (stretch mode canvas_items).
	# Mac: Cmd+Ctrl+F (the system shortcut) or Option+Return.
	if e is InputEventKey and e.pressed and not e.echo and (e.keycode == KEY_F11 or (e.keycode == KEY_ENTER and e.alt_pressed) \
			or (e.keycode == KEY_F and e.meta_pressed and e.ctrl_pressed)):
		Settings.v.window_mode = 0 if DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN] else 1
		Settings.apply(self)
		Settings.save()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _script_run:   # a test's window kept behind yours: the OS calls it hidden and Godot stops drawing, so its shots would wait for ever
		if _drawn == 0:
			RenderingServer.force_draw(false)
		_drawn = 0
	if over:
		if Input.is_action_just_pressed("restart") and net.authority():
			net.event("restart")
			get_tree().reload_current_scene()
		return
	player.in_train = train.contains(player.global_position)
	_train_light()
	_autosave_t -= delta
	if _autosave_t <= 0.0:
		_autosave_t = AUTOSAVE_EVERY
		autosave()
	_remains_t -= delta
	if _remains_t <= 0.0 and not _recovering and level != null and net.authority():
		_remains_t = 0.5
		_check_remains()
	if _travelling and not _recovering:
		var aboard: bool = train.on_board(player.global_position)
		if not aboard and player.get_parent() == self and player.process_mode != Node.PROCESS_MODE_DISABLED:
			_step_off()
		elif aboard and player.get_parent() != self:
			_step_on()
	if _travelling:   # out on the flatcar, it's falling on you (none in a tunnel)
		var fw := weather_now()
		if stop.get("biome", "") == "ARCTIC" and fw != "BLIZZARD":
			fw = "SNOW"
		player.set_weather("" if player.in_train or line.dark > 0.3 else fw)
	if _stranded and not _recovering and player.global_position.distance_to(train.to_global(Vector3(0, 1.3, 0))) > 40.0:
		_left_behind()   # it's got away from you
	_track_motion(delta)
	if not at_checkpoint and not busy and level != null:
		hours += 16.0 * delta / DAY_SECONDS
		var leave := depart_hour()
		if hours >= leave - 2.0 and warned == 0:   # the one warning: two hours out
			warned = 1
			hud.alert("WARNING: the train departs in two hours. Get back aboard.")
			Sfx.play(self, "alarm", null, -4.0)
		if hours >= leave and net.authority():
			_auto_depart()
		if net.authority():   # the spawn director and the site's events run on the host
			level.tick(delta, hours)
		_weather(delta)
	_update_env()
	_sound_space(delta)
	var t := "CHECKPOINT" if at_checkpoint else ""   # (no clock on the visor: the train's clocks tell the time)
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
		q = _board_text()
		if level.shredder != null and level.shredder.running:
			q += "
>> SHREDDING ...  +%d CR" % level.shredder.run_pay
		level.board.text = q
	hud.update_player(player)


func _quota_text() -> String:
	var s := ("CREDITS: %d\n" % credits) if credits >= 0 else ("IN DEBT: %d CR\n" % -credits)
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


## The readout over the shredder: the quota, then where the surplus is going and what's in stock.
func _board_text() -> String:
	var s := _quota_text()
	s += "\nDIVERTER: %s" % ("BANK SURPLUS" if divert_bank else "SELL ALL")
	var stock := Data.res_text(bank)
	s += "\nBONDED STOCK: %s" % (stock if stock != "" else "EMPTY")
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
	if level and pos.y < level.water_y + 0.05:
		return "water"   # (wading a swamp's pools)
	if level and level.on_boards(pos):
		return "wood"
	return Data.biome(stop.get("biome", "DESERT")).step


## Reverb follows where you are; an ambience bed per place; now and then something far off underground.
func _sound_space(delta: float) -> void:
	var under: bool = player.global_position.y < UNDERGROUND_Y
	var space := "underground" if under else ("tunnel" if line.dark > 0.5 else ("train" if player.in_train else "outside"))
	if space != _space:
		_space = space
		Sfx.set_space(space)
	var bed := "wind"
	var bed_db := -30.0
	if under and level and level.facility:
		bed = "amb_" + String(level.facility.theme_id).to_lower()
		bed_db = -24.0 if bed != "amb_backrooms" else -19.0
	elif at_checkpoint:
		bed = "amb_yard"
		bed_db = -27.0
	elif player.in_train:
		bed_db = -36.0
	if bed == "wind" and weather_now() in ["BLIZZARD", "SANDSTORM", "STORM"]:
		bed_db += 9.0   # a storm howls
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
		_sting = randf_range(18.0, 38.0) if late else randf_range(28.0, 60.0)
		var pool := ["far_bang", "groan", "pipe_knock", "far_steps", "drip"]
		if level.facility.theme_id == "FLESH":
			pool = ["groan", "drip", "far_steps", "far_screech"]
		if late:
			pool.append("far_screech")
		var dir := Vector3(1, 0, 0).rotated(Vector3.UP, randf() * TAU)
		var at: Vector3 = player.global_position + dir * randf_range(12.0, 26.0) + Vector3(0, 1.5, 0)
		Sfx.play(level, pool[randi() % pool.size()], at, randf_range(-14.0, -7.0), randf_range(0.85, 1.1))


func _weather(delta: float) -> void:
	var under: bool = player.global_position.y < UNDERGROUND_Y
	var acid: bool = stop.get("weather", "") == "ACID_RAIN"
	var w: String = stop.get("weather", "")
	if stop.get("biome", "") == "ARCTIC" and w != "BLIZZARD":
		w = "SNOW"
	player.set_weather("" if under or player.in_train else ("ACID_RAIN" if acid else w))   # (RAIN, STORM, SNOW... OVERCAST and CLEAR: nothing falls)
	if acid and net.authority() and not has_upgrade("ACID_SHIELD"):
		for p in players():
			if not p.dead and not p.in_train and p.global_position.y > UNDERGROUND_Y and not _roofed(p.global_position):
				_acid_t[p] = _acid_t.get(p, 0.0) + delta
				if _acid_t[p] > 4.0:   # a few seconds before it eats through the suit, then a slow burn
					p.hurt(0.75 * delta, "Dissolved in acid rain.")
			else:
				_acid_t[p] = maxf(0.0, _acid_t.get(p, 0.0) - delta * 2.0)


func _roofed(pos: Vector3) -> bool:
	var from := pos + Vector3(0, 1.9, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 40, 0), 1)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# --- travel ---------------------------------------------------------------------

## Builds a stop. `sliced` (on the way there, in the tunnel): a few milliseconds a frame while the
## train runs on (level.gd), `level_building` meanwhile; otherwise all at once.
var level_building := false

func _load_level(s: Dictionary, seed := -1, sliced := false) -> void:
	_enter(s, seed)
	seed(level_seed)   # every random choice in the build (props, clutter...) the same on every machine
	level = Level.new()
	level.main = self
	level.name = "Level"
	if sliced:
		level.process_mode = Node.PROCESS_MODE_DISABLED   # (nothing in it stirs till the train's there)
	add_child(level)
	level_building = sliced
	var building = level
	await level.build(s, assignment, level_seed, sliced)
	if not is_instance_valid(building):
		return
	level_building = false
	randomize()
	if not _travelling:   # (on the way, the line lays itself as the train comes)
		line.settle(level)
	net.level_loaded()


## The stop becomes the current one: its seed, the day's prices, the clock.
func _enter(s: Dictionary, seed := -1) -> void:
	stop = s
	level_serial += 1
	level_seed = seed if seed >= 0 else rng.randi()
	at_checkpoint = s.theme == "CHECKPOINT"
	_cp_value = 0.0
	_cp_items = 0
	_reported = false
	_banked_now = 0
	_rank_bonus_paid = 0
	payload_rank = "-"
	hours = 8.0
	warned = 0
	for r in Data.RES:
		prices[r] = snappedf(Data.BASE_PRICE[r] * rng.randf_range(0.7, 1.4), 0.1)


func _depart(s: Dictionary, seed := -1) -> void:
	if busy or over:
		return
	if net.active:   # everyone travels together; the host picks the next stop's seed
		if net.is_host:
			seed = rng.randi()
			net.event("travel", [s, seed])
		elif seed < 0:
			return
	if seed < 0:
		seed = rng.randi()
	busy = true
	term.close()
	hud.msg("Train departing for %s..." % s.letter)
	Sfx.play(self, "horn", null, -15.0)
	train.set_doors(false)   # (the doors roll shut before it pulls out)
	await get_tree().create_timer(1.5 * Data.pace(), false).timeout
	if over:
		return
	_missed = not train.on_board(player.global_position)   # (you'll watch it go, and can still run for it)
	await _travel(s, seed)


## The trip itself (line.gd): it pulls out, runs the line, goes into a tunnel, comes out at the next
## stop and draws up at the platform. Step off on the way and the world carries you off with it:
## get back aboard before the train's got away, or it's LEFT BEHIND.
func _travel(s: Dictionary, seed := -1) -> void:
	_travelling = true
	if level != null and get_tree().get_nodes_in_group("pickups").any(func(p): return p.id == "REMAINS" and level.is_ancestor_of(p)):
		hud.msg("Remains left behind at station %s." % stop.get("letter", "?"))
	for p in get_tree().get_nodes_in_group("pickups"):
		if train.contains(p.global_position):
			p.reparent(train)
	if level != null:
		level.process_mode = Node.PROCESS_MODE_DISABLED
	await line.ride(s, seed)
	_travelling = false
	_arriving = false
	_missed = false
	level.process_mode = Node.PROCESS_MODE_INHERIT
	if player.get_parent() == level:   # hopped off as it rolled in: you're at the station anyway
		_set_player_parent(self)
	Sfx.play(self, "horn", null, -18.0, 0.8)
	train.set_doors(true)
	busy = false
	autosave()
	if at_checkpoint:
		hud.alert("CHECKPOINT. Throw scrap into the SHREDDER and pull the lever.")
	else:
		hud.msg("Arrived at station %s: %s facility, %s." % [s.letter, s.theme, s.biome])
		if s.weather != "CLEAR":
			hud.alert("WEATHER ALERT: %s" % s.weather.replace("_", " "))
			Sfx.play(self, "alarm", null, -4.0)


## Deep in the tunnel (line.gd): the stop we left is gone, the next one is built here, out of sight,
## a slice a frame (main.level is the new one from the start; `level_building` till it's done).
## As the train pulls out (line.gd): the next stop's buildings and facility, built hidden far down
## the line a slice a frame (nothing spawned yet, nothing sent to the crew), so the tunnel only has
## the quick part left.
var next_level: Node3D

func _prebuild(s: Dictionary, seed: int) -> void:
	var lv = Level.new()
	lv.main = self
	lv.name = "LevelNext"
	lv.process_mode = Node.PROCESS_MODE_DISABLED
	lv.visible = false
	add_child(lv)
	next_level = lv
	level_building = true
	await lv.build_geometry(s, assignment, seed, true)
	if is_instance_valid(lv):
		lv.set_meta("built", true)


func _journey_build(s: Dictionary, seed: int) -> void:
	if s.theme == "CHECKPOINT":
		stage = -1
		departed = false
		submitted = {}
	else:
		stage += 1
		taken.append(s.letter)
	if level != null:
		level.name = "LevelGone"   # (line.gd frees it; the new one must be "Level": doors and buttons are keyed by it)
	_enter(s, seed)
	level = next_level
	next_level = null
	level.name = "Level"
	level.visible = true
	level_building = true
	while is_instance_valid(level) and not level.has_meta("built"):   # (its buildings may still be going up)
		await get_tree().process_frame
	var lv = level
	await lv.populate(true)
	if not is_instance_valid(lv):
		return
	level_building = false
	randomize()
	net.level_loaded()


## Off the train while it moves. You stay in the world (whatever's under you carries you off as the
## train goes) and can still move: run for it, or watch it go.
func _step_off() -> void:
	player.velocity = Vector3.ZERO
	var on: Node3D = line
	if level != null:
		var l: Vector3 = level.to_local(player.global_position)
		var half := 270.0 if at_checkpoint else 100.0
		if absf(l.x) < half and absf(l.z) < half:
			on = level
			level.process_mode = Node.PROCESS_MODE_INHERIT   # paused bodies drop out of physics: wake the world you're standing in
	_set_player_parent(on)
	if _arriving:
		hud.msg("You drop off the side as the train rolls in.")
		return
	_stranded = true
	if not _missed:
		hud.alert("YOU STEPPED OFF THE TRAIN. GET BACK ON.")
		Sfx.play(self, "horn", null, -15.0, 0.7)


func _step_on() -> void:
	_set_player_parent(self)
	if _stranded:
		_stranded = false
		_missed = false
		hud.msg("You haul yourself back aboard.")


## The train's got away from you: written off, recovered aboard, and on to wherever it's going.
func _left_behind() -> void:
	if _missed:
		await _write_off("LEFT BEHIND", "The train departed on schedule. You did not.")
	else:
		await _write_off("LEFT BEHIND", "You stepped off a moving train. It did not stop for you.")
	_missed = false
	await hud.fade(0.0, 1.2)


func _set_player_parent(n: Node) -> void:
	player.reparent(n)
	player.process_mode = Node.PROCESS_MODE_INHERIT


## Being left behind doesn't end the run. The Bureau recovers you onto the train as it heads for
## the next stop and writes off the scrap you were carrying. Cargo already aboard is kept.
func _write_off(title: String, cause: String) -> void:
	_recovering = true
	player.frozen = true
	_set_player_parent(self)   # (off whatever it was standing on: the stop behind is about to go)
	player.process_mode = Node.PROCESS_MODE_DISABLED   # (and held there, not falling, till it's recovered)
	stats.lost += 1
	var lost := 0
	for it in player.slots:
		if it != null and Data.kind(it.id) == "scrap":
			lost += 1
	Sfx.play(self, "alarm", null, -4.0, 0.8)
	await hud.fade(0.85, 1.2)
	hud.big("%s\n%s\n\nThe Bureau has recovered you.\n%d item%s of scrap you were carrying written off." % [title, cause, lost, "" if lost == 1 else "s"])
	await get_tree().create_timer(4.0, false).timeout
	await hud.fade(1.0, 0.8)
	hud.big("")
	for i in player.slots.size():
		if player.slots[i] != null and Data.kind(player.slots[i].id) == "scrap":
			player.slots[i] = null
	_set_player_parent(self)
	player.revive(train.to_global(Vector3(-3, 1.3, 0)))
	_stranded = false
	_recovering = false


## Wheels, steam and camera shake follow how fast the line is going by.
func _track_motion(delta: float) -> void:
	if delta <= 0.0:
		return
	train.speed = lerpf(train.speed, line.v if line.riding else 0.0, minf(1.0, delta * 8.0))
	if player.in_train and absf(train.speed) > 0.5:
		player.shake(clampf(absf(train.speed) * 0.0007, 0.0, 0.018))


func _auto_depart() -> void:
	var dest: Dictionary = CHECKPOINT_STOP if stage >= 2 else route[stage + 1][rng.randi() % route[stage + 1].size()]
	hud.alert("AUTOMATIC DEPARTURE")
	_depart(dest)


## The MAIN DRIVE lever was thrown (the host decides): the shredder runs a cycle over whatever's
## in the hopper, paying for each item as it goes through (shred_item), then sums up (shred_done).
func shred() -> void:
	if not at_checkpoint or level == null or not net.authority() or level.shredder == null:
		return
	if level.shredder.running:
		hud.msg("It's already running.")
		return
	var items := []
	for p in get_tree().get_nodes_in_group("pickups"):
		if level.hopper.has_point(p.global_position) and Data.kind(p.id) != "remains" and not p.is_queued_for_deletion() and p is RigidBody3D:
			items.append(p)
	if items.is_empty():
		hud.msg("The shredder is empty. Throw scrap over the rim first.")
		Sfx.play(self, "error", null, -6.0)
		level.shredder.dry_run()
		return
	level.shredder.run(items)


## Host: one item went through the cutters. Its resources count; its credits are paid now.
## With the diverter on BANK, whatever's past the quota goes into the bonded stock unpaid instead.
func shred_item(id: String) -> float:
	var res: Dictionary = Data.ITEMS[id].res
	var pay := 0.0
	var banked := 0
	for r in res:
		var units: int = res[r]
		var short: int = maxi(0, quota.get(r, 0) - submitted.get(r, 0)) if assignment > 0 else 0
		var to_bank: int = maxi(0, units - short) if divert_bank else 0
		submitted[r] = submitted.get(r, 0) + units - to_bank
		if to_bank > 0:
			bank[r] = bank.get(r, 0) + to_bank
			banked += to_bank
		pay += (units - to_bank) * sell_price(r)
		_cycle_value += units * prices[r]
	credits += roundi(pay)
	stats.shredded += 1
	stats.earned += roundi(pay)
	if banked > 0:
		_banked_now += banked
		_stock_changed()
	return pay


## What a unit of `r` fetches today.
func sell_price(r: String) -> float:
	return prices[r] * (1.15 if has_upgrade("MARKET_CONTACTS") else 1.0)


## The bonded stock changed: the bales in the hall follow it (everyone's, through the state).
func _stock_changed() -> void:
	if at_checkpoint and level != null and level.has_method("show_stock"):
		level.show_stock(bank)


## Host: the diverter's handle was turned.
func toggle_divert() -> void:
	if not net.authority():
		return
	divert_bank = not divert_bank
	if level != null and level.get("shredder") != null:
		level.shredder.set_divert(divert_bank)
	var say := "DIVERTER: BANK. Anything past the quota goes to the bonded stock, unpaid." if divert_bank else "DIVERTER: SELL. Everything shredded is paid at today's prices."
	hud.msg(say)


## Host: the cycle's over.
func shred_done(n: int, got: Dictionary, pay: float) -> void:
	if n == 0:
		return
	hud.msg("Shredded %d items: %s   +%d credits" % [n, Data.res_text(got), roundi(pay)])
	_cp_items += n
	var value := _cycle_value
	_cycle_value = 0.0
	_after_submit(value)


## Host: resources went in (a shredder cycle, or stock drawn): rank them, and open the gate once the quota's met.
func _after_submit(value: float) -> void:
	var was := payload_rank
	_rank_payload(value)
	if assignment > 0 and not departed and _quota_met() and level.gate_light.light_color.g < 0.5:
		stats.assignments += 1
		level.open_gate()
		net.event("gate")
		hud.alert("QUOTA MET. Gate unlocked. LEAVE_CHECKPOINT when ready.")
		_reported = true
		_report()
	elif _reported and payload_rank != was:
		_report()   # (a better grade: stamped again)
	autosave()


## Host: the shift report for this checkpoint, to everyone.
func _report() -> void:
	var quota_value := 0.0
	for r in Data.RES:
		quota_value += quota.get(r, 0) * prices[r]
	var d := [assignment, "CHECKPOINT   %02d:%02d" % [int(hours) % 24, int(fmod(hours, 1.0) * 60.0)], _cp_items, roundi(_cp_value),
		roundi(100.0 * _cp_value / maxf(quota_value, 1.0)), stats.lost - _lost_from, players().size(), payload_rank, fees, _banked_now]
	report.show_report(d)
	net.event("report", [d])


## Payload rank for this checkpoint: everything shredded here against what the quota is worth.
## Climbing a rank pays a one-off Bureau bonus.
func _rank_payload(value: float) -> void:
	_cp_value += value
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
	_lost_from = stats.lost
	departed = true
	submitted = {}
	fees = 0
	crew_size = maxi(1, players().size())
	for r in Data.RES:
		quota[r] = quota_units(assignment, crew_size, rng.randf_range(0.6, 1.4))
	route = []
	taken = []
	stage = -1
	for i in 3:
		var opts := []
		for j in rng.randi_range(2, 3):
			opts.append(_gen_stop())
		route.append(opts)
	# Once an assignment, one of the choices is a landmark stop (Data.LANDMARK_STOPS).
	var at := 0 if Engine.has_meta("force_dam") else rng.randi_range(0, 2)
	var pick: int = 0 if Engine.has_meta("force_dam") else rng.randi() % route[at].size()
	route[at][pick] = _landmark_stop("DAM", route[at][pick])
	level.open_gate()
	net.event("gate")
	Sfx.play(self, "horn", null, -15.0)
	term.say("\nASSIGNMENT %d ISSUED.  Quota: %s" % [assignment, Data.res_text(quota)])
	if crew_size > 1:
		term.say("Quota sized for a crew of %d." % crew_size)
	_c_map([])


## How many units of a resource an assignment asks for: more each time, climbing faster after the
## first few, and more for a bigger crew (a third again for each extra hand). `roll` is the luck of the draw.
static func quota_units(n: int, crew: int, roll: float) -> int:
	var base := 3.0 + 3.0 * n + 0.6 * n * n
	return maxi(2, roundi(base * (1.0 + 0.35 * (maxi(crew, 1) - 1)) * roll))


func _gen_stop() -> Dictionary:
	var letter := char(65 + _letter % 26)
	_letter += 1
	var pool := []
	for t in Data.THEMES:
		for k in Data.THEMES[t].weight:
			pool.append(t)
	var biome := _pick_biome()
	var b := Data.biome(biome)
	var weather: String = Data.WEATHERS[rng.randi() % Data.WEATHERS.size()]
	if weather == "SANDSTORM" and biome != "DESERT":
		weather = b.storm   # (sand only blows in the desert)
	elif weather == "STORM" and biome == "ARCTIC":
		weather = "BLIZZARD"   # the snow's version of a storm
	elif not b.wet and weather in ["RAIN", "ACID_RAIN"]:
		weather = "OVERCAST"   # (it snows there anyway)
	return {
		"letter": letter,
		"theme": pool[rng.randi() % pool.size()],
		"rooms": 14 + assignment * 4 + rng.randi_range(0, 8),   # (big: wings down long corridors)
		"weather": weather,
		"biome": biome,
	}


## A landmark stop in place of `was` (its letter and weather kept): its own facility type and name, in
## country that suits it.
func _landmark_stop(kind: String, was: Dictionary) -> Dictionary:
	var lm: Dictionary = Data.LANDMARK_STOPS[kind]
	var o := was.duplicate()
	o.theme = lm.theme
	o.landmark = kind
	o.name = lm.names[rng.randi() % lm.names.size()]
	if not o.biome in lm.biomes:
		o.biome = lm.biomes[rng.randi() % lm.biomes.size()]
		var b := Data.biome(o.biome)
		if o.weather == "SANDSTORM" and o.biome != "DESERT":
			o.weather = b.storm
		elif o.weather == "STORM" and o.biome == "ARCTIC":
			o.weather = "BLIZZARD"
		elif not b.wet and o.weather in ["RAIN", "ACID_RAIN"]:
			o.weather = "OVERCAST"
	return o


## A surface biome for a new stop, by the table's chances.
func _pick_biome() -> String:
	var total := 0
	for k in Data.BIOMES:
		total += Data.BIOMES[k].chance
	var roll := rng.randi() % total
	for k in Data.BIOMES:
		roll -= Data.BIOMES[k].chance
		if roll < 0:
			return k
	return "DESERT"


func _ram_gate() -> void:
	term.close()
	busy = true
	hud.alert("RAMMING SPEED")
	Sfx.play(self, "horn", null, -9.0)
	await get_tree().create_timer(2.5, false).timeout
	Sfx.play(self, "boom", null, 4.0)
	game_over("ASSIGNMENT FAILED\nThe gate held. The train did not.\nYou have been factored in.")


func game_over(text: String) -> void:
	if over:
		return
	net.event("game_over", [text])
	over = true
	busy = true
	player.frozen = true
	term.close()
	if net.authority() and autosaves:
		Save.delete(save_path)   # (the run's over: nothing to continue)
	if stats.assignments > best:
		best = stats.assignments
		var f := FileAccess.open(BEST_PATH, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"best": best}))
	var photos := pinned_photos()
	hud.big("%s\n\nAssignments: %d    Shredded: %d    Credits: %d\nTimes recovered: %d    Photos pinned: %d    Field guide: %d/%d\nBest run: %d assignments\n\n%s"
		% [text, stats.assignments, stats.shredded, stats.earned, stats.lost, photos.size(), guide.seen.size(), Data.GUIDE.size(), best,
		"[R] restart" if net.authority() else "Waiting for the host to restart..."])
	hud.memento(photos)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Dying doesn't end the run. You wake aboard as a "replacement", an hour later, at the same stop.
## Your remains lie where you fell, with whatever you were holding scattered round them. Carry them
## back aboard and the Bureau pays a small recovery fee. Cargo already on the train is never touched.
func _on_died(cause: String) -> void:
	if _recovering:
		return
	_recovering = true
	if not net.active:
		busy = true
	var fell: Vector3 = player.global_position
	var yaw: float = player.rotation.y
	_fee_charged = replacement_fee()   # (what the host is about to charge for this one)
	await get_tree().create_timer(1.5, false).timeout
	if over:
		return
	if net.authority():
		died_world(fell, yaw, net.my_name)
	else:
		var tag: String = "L" if level != null else "W"
		net.request("died", [tag, net.frame(tag).affine_inverse() * fell, yaw])
	player.frozen = true
	Sfx.play(self, "alarm", null, -4.0, 0.8)
	await hud.fade(0.85, 1.2)
	var fee := "The Bureau has issued a replacement: %d credits, docked from the crew's account." % _fee_charged
	if at_checkpoint or level == null:
		hud.big("YOU DIED\n%s\n\n%s" % [cause, fee])
	else:
		hud.big("YOU DIED\n%s\n\n%s One hour lost.\nYour remains are where you fell, with what you were carrying.\nBring them aboard for a %d credit recovery fee." % [cause, fee, RECOVERY_PAY])
	await get_tree().create_timer(4.5, false).timeout
	await hud.fade(1.0, 0.6)
	hud.big("")
	_set_player_parent(self)
	player.revive(train.to_global(Vector3(-3 + randf_range(-1.0, 1.0), 1.3, randf_range(-0.6, 0.6))))
	_recovering = false
	if not net.active:
		busy = false
	await hud.fade(0.0, 1.2)


## Host: someone died at `fell`. Their remains drop there and an hour of the shift is lost.
func died_world(fell: Vector3, yaw: float, who: String) -> void:
	var fee := replacement_fee()
	stats.lost += 1
	credits -= fee   # (it can put the crew in debt: the shredder pays it off)
	fees += fee
	if net.active:
		net.event("msg", ["The Bureau has docked %d credits for %s's replacement." % [fee, who]])
	var now := Time.get_ticks_msec()
	_down[who] = now
	for k in _down.keys():
		if now - _down[k] > 12000:
			_down.erase(k)
	if level == null or at_checkpoint:
		return
	var r = spawn_item("REMAINS", fell, -1.0, level, "stand")   # you drop where you stood
	if r:
		r.rotation.y = yaw
		if net.active:
			r.set_meta("who", who)   # (if it gets up again, it's still them)
	hours = minf(hours + 1.0, 24.0)
	if net.active and who != net.my_name:
		hud.alert("%s DIED. Their remains are where they fell." % who)
	if net.active:
		net.event("alert", ["%s DIED. Their remains are where they fell." % who])
	var crew := players().size()
	if crew > 1 and _down.size() >= crew and hours < depart_hour() - WIPE_RECALL:
		_recall()


## Replacement for the next death: dearer for each one already this assignment.
func replacement_fee() -> int:
	return mini(REPLACEMENT_FEE + REPLACEMENT_STEP * (stats.lost - _lost_from), REPLACEMENT_MAX)


## Host: the whole crew was lost at once. The Bureau writes the stop off and calls the train on.
func _recall() -> void:
	hours = depart_hour() - WIPE_RECALL
	warned = 1
	var say := "ALL CREW LOST. The Bureau is recalling the train: departure in thirty minutes."
	hud.alert(say)
	net.event("alert", [say])
	Sfx.play(self, "horn", null, -6.0)


# --- saving the run ---------------------------------------------------------------------------

## Write the run to disk (solo, or the host). Not while the train's on its way somewhere.
func autosave() -> bool:
	if not autosaves or not net.authority() or over or busy or _travelling or level == null or (level.get("shredder") != null and level.shredder.running):
		return false
	_autosave_t = AUTOSAVE_EVERY
	if net.active:
		net.event("pockets?")   # (the answers are kept for the next save)
	return Save.write(self, save_path)


## Pick up a saved run where it was left (from the title screen, before the shift starts).
func continue_run() -> bool:
	if not Save.restore(self, save_path):
		return false
	hud.msg("Run continued: assignment %d, %s." % [assignment, "the checkpoint" if at_checkpoint else "station %s" % stop.get("letter", "?")])
	return true


## Host: a crewmate just joined. Their pockets from a saved run, and the run's photos.
func net_welcomed(peer: int) -> void:
	var who: String = net.name_of(peer)
	if crew_pockets.has(who):
		for w in crew_pockets[who]:
			if w != null:
				net.to_owner(peer, "grant", w)
		crew_pockets.erase(who)
	if not photo_log.is_empty():
		net.to_owner(peer, "photos", photo_log.map(func(e): return net.extra_to_wire(e)))


## A photo was taken (the host says): into the run's album.
func add_photo(e: Dictionary) -> void:
	photo_log.append(e)
	if net.is_host:
		net.event("photo", [net.extra_to_wire(e)])


## Every photo pinned up on the train, oldest first: [{tex, stamp}, ...].
func pinned_photos() -> Array:
	var out := []
	for p in get_tree().get_nodes_in_group("pickups"):
		if p.id == "PHOTO" and p.has_node("Tack") and train.is_ancestor_of(p) and not p.is_queued_for_deletion():
			out.append(p.extra)
	return out


## A photo pinned to a wall of the train: picture out, top up, a drawing pin through the top.
## It stays put (and stays with the train) until someone takes it down again with E.
func pin_photo(it: Dictionary, at: Vector3, normal: Vector3) -> void:
	if not net.authority():
		net.request("pin", [net.item_to_wire(it), train.to_local(at), train.global_basis.inverse() * normal])
		return
	var p = spawn_item("PHOTO", at + normal * 0.005, -1.0, train)
	p.freeze = true
	var up := (Vector3.UP - normal * Vector3.UP.dot(normal)).normalized()
	var z := -up
	p.global_basis = Basis(normal.cross(z), normal, z)
	p.set_extra(it.get("extra", {}))
	p.pin()
	net.ent_event(p, "pin")
	Sfx.play(p, "click", p.global_position, -6.0, 0.7)


## Remains brought aboard (dropped inside, or carried in): the Bureau takes them and pays its fee.
func _check_remains() -> void:
	var remains = null
	for p in get_tree().get_nodes_in_group("pickups"):
		if p.id == "REMAINS" and train.contains(p.global_position) and not p.is_queued_for_deletion():
			remains = p
	var slot: int = player.slots.find_custom(func(it): return it != null and it.id == "REMAINS")
	var carrier = null   # (a crewmate carrying them aboard)
	for pup in net.puppets.values():
		if is_instance_valid(pup) and pup.in_train and pup.slots[0] != null and pup.slots[0].id == "REMAINS":
			carrier = pup
	if remains == null and not (slot >= 0 and player.in_train) and carrier == null:
		return
	if remains != null:
		remains.queue_free()
	elif slot >= 0 and player.in_train:
		player.slots[slot] = null
	else:
		net.to_owner(carrier.peer, "take", "REMAINS")
	credits += RECOVERY_PAY
	stats.earned += RECOVERY_PAY
	Sfx.play(self, "ding", null, -6.0, 0.8)
	hud.alert("REMAINS RECOVERED. The Bureau pays a %d credit recovery fee." % RECOVERY_PAY)
	net.event("alert", ["REMAINS RECOVERED. The Bureau pays a %d credit recovery fee." % RECOVERY_PAY])


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
	term.add("BALANCE", 0, "BALANCE                   your credits", func(_a): term.say("Balance: %d credits" % credits if credits >= 0 else "[color=#ff6a5a]In debt: %d credits.[/color] The shredder's takings pay it off first." % -credits))
	term.add("MARKET", 0, "MARKET                    quota + today's resource prices", _c_market)
	term.add("STOCK", 0, "STOCK [SELL|SUBMIT <res>]  bonded stock: banked surplus", _c_stock)
	term.add("SHOP", 0, "SHOP                      items for sale", _c_shop)
	term.add("BUY", 1, "BUY <item> [n]            order items (shorthand ok: BUY MED 2)", _c_buy)
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
	term.add("STATUS", 0, "STATUS                    check crew vitals and inventory", _c_status)
	term.add("VIEW_CAM", 1, "VIEW_CAM <n>              watch a camera (arrows pan)", _c_view_cam)
	term.add("NEXT_CAM", 0, "NEXT_CAM                  next camera", func(_a): _c_view_cam([str(_cam_index + 2)]))
	term.add("PREV_CAM", 0, "PREV_CAM                  previous camera", func(_a): _c_view_cam([str(_cam_index)]))
	term.add("TOGGLE_LIGHT", 0, "TOGGLE_LIGHT              camera floodlight on/off", _c_toggle_light)
	term.add("EXIT_CAMS", 0, "EXIT_CAMS                 close the camera feed", func(_a): term.hide_monitor())
	term.add("MINIMAP", 0, "MINIMAP                   facility map (needs MINIMAP)", _c_minimap)
	term.add("EXIT_MINIMAP", 0, "EXIT_MINIMAP              close the map", func(_a): term.hide_monitor())
	term.add("LIST_LOGS", 0, "LIST_LOGS                 uploaded data logs", _c_list_logs)
	term.add("READ", 1, "READ <log>                read a data log", _c_read)
	term.add("GUIDE", 0, "GUIDE [name]              field guide to the creatures you've scanned", _c_guide)
	term.add("CLEAR", 0, "CLEAR                     clear the screen", func(_a): term.clear())
	for name in NET_CMDS:   # with a crew, the host runs anything that changes the world
		var fn: Callable = term.commands[name].fn
		term.commands[name].fn = func(a):
			if net.active and not net.is_host:
				net.term_remote(" ".join([name] + Array(a)))
			else:
				fn.call(a)


func _c_status(_a) -> void:
	term.say("CREW STATUS:")
	var active = players()
	for p in active:
		var n = p.display_name if "display_name" in p else net.my_name
		var state = "DECEASED" if p.dead else ("%.0f%%" % p.hp)
		var inv = []
		if "inventory" in p and p.inventory.size() > 0:
			inv = p.inventory.filter(func(i): return i != "")
		elif "slots" in p:
			inv = p.slots.filter(func(s): return s != null).map(func(s): return s.id)
		var items = ", ".join(inv) if inv.size() > 0 else "empty hands"
		term.say("  %s: %s  |  [color=#a08b73]%s[/color]" % [n, state, items])
	term.say(" ")

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


## The bonded stock: surplus banked at the shredder, kept for a later quota or a better price.
func _c_stock(a) -> void:
	if a.is_empty():
		term.say("BONDED STOCK (banked surplus, held at the checkpoint):")
		var any := false
		for r in Data.RES:
			if bank.get(r, 0) > 0:
				any = true
				term.say("  %-8s %3d units   worth %d CR today" % [r.to_upper(), bank[r], roundi(bank[r] * sell_price(r))])
		if not any:
			term.say("  Empty. Turn the shredder's DIVERTER to BANK to keep surplus past the quota.")
		term.say("Diverter: %s" % ("BANK SURPLUS" if divert_bank else "SELL ALL"))
		term.say("STOCK SELL <res|ALL> sells at today's price.  STOCK SUBMIT <res|ALL> puts it toward the quota (unpaid).")
		return
	if not at_checkpoint:
		term.error("The bonded stock is held at the checkpoint.")
		return
	var how: String = a[0].to_upper()
	if not how in ["SELL", "SUBMIT"]:
		term.error("STOCK SELL <res|ALL> or STOCK SUBMIT <res|ALL>.")
		return
	var which: Array = Data.RES.duplicate()
	if a.size() > 1 and a[1].to_upper() != "ALL":
		var r := Terminal.complete(a[1].to_lower(), Data.RES)
		if not r in Data.RES:
			term.error("Unknown resource '%s': STEEL, COPPER, RUBBER, PLASTIC or ALL." % a[1])
			return
		which = [r]
	if how == "SELL":
		var pay := 0.0
		var sold := {}
		for r in which:
			if bank.get(r, 0) > 0:
				sold[r] = bank[r]
				pay += bank[r] * sell_price(r)
				bank.erase(r)
		if sold.is_empty():
			term.error("Nothing of that in stock.")
			return
		credits += roundi(pay)
		stats.earned += roundi(pay)
		term.say("Sold from stock: %s   +%d credits." % [Data.res_text(sold), roundi(pay)])
		Sfx.play(self, "ding", null, -8.0)
	else:
		if assignment == 0 or departed:
			term.error("No quota to submit to. Stock can go toward the next assignment's quota at the next checkpoint.")
			return
		var drawn := {}
		var value := 0.0
		for r in which:
			var n: int = mini(bank.get(r, 0), maxi(0, quota.get(r, 0) - submitted.get(r, 0)))
			if n > 0:
				drawn[r] = n
				submitted[r] = submitted.get(r, 0) + n
				bank[r] -= n
				if bank[r] <= 0:
					bank.erase(r)
				value += n * prices[r]
		if drawn.is_empty():
			term.error("Nothing in stock that the quota still needs.")
			return
		term.say("Submitted from stock: %s." % Data.res_text(drawn))
		_after_submit(value)
	_stock_changed()


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
	term.say("A delivery handcar is on its way to the back of the train (%s)." % ("a few seconds" if has_upgrade("QUICK_DELIVERY") else "about twenty seconds"))
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
			var tag: String = o.letter + ("[%s]" % o.landmark if o.has("landmark") else "")
			row += (">%s< " if chosen else " %s  ") % tag
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
	var size := "LARGE" if o.rooms < 22 else ("SPRAWLING" if o.rooms < 30 else "VAST")
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
	if o.has("landmark"):
		var lm: Dictionary = Data.LANDMARK_STOPS[o.landmark]
		term.say("LANDMARK: %s %s\n  %s" % [o.name, o.landmark, lm.desc])
	term.say("STATION %s\n  Facility:  %s\n  Size:      %s (%d sectors)\n  Surface:   %s\n  Weather:   %s\n  Hazards:   %s\n  Sightings: frequent %s%s"
		% [o.letter, "POWERHOUSE" if o.theme == "DAM" else o.theme, size, o.rooms, "%s (%s)" % [o.biome, Data.biome(o.biome).desc], o.weather.replace("_", " ") if has_upgrade("WEATHERVANE") else "UNKNOWN (needs WEATHERVANE)",
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
	if open and level != null and level.facility != null and a[0].to_upper() == level.facility.vault_code:
		term.error("VAULT %s: remote opening disabled. Keycard required at the door." % a[0].to_upper())
		return
	if open and level != null and level.facility != null and a[0].to_upper() == level.facility.twin_code:
		term.error("BLAST DOOR %s: twin-key. Both levers on site, pulled together." % a[0].to_upper())
		return
	if level == null or level.facility == null or not level.facility.set_door(a[0], open):
		term.error("No bulkhead '%s' at this station." % a[0])
		return
	if a[0] == level.facility.secure_code and open:
		term.say("ACCESS CODE ACCEPTED. Records room unsealed.")
		return
	term.say("Bulkhead %s %s." % [a[0], "opened" if open else "closed"])


# --- world setup ------------------------------------------------------------------

func _setup_input() -> void:
	Settings.load_file()
	Settings.apply_binds()   # (the keys you can rebind, as you've bound them)
	if not InputMap.has_action("restart"):
		InputMap.add_action("restart")
		var e := InputEventKey.new()
		e.physical_keycode = KEY_R
		InputMap.action_add_event("restart", e)


func _setup_world() -> void:
	env = Environment.new()
	weather = load("res://src/weather.gd").new()
	weather.main = self
	add_child(weather)
	sky_mat = weather.mat
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL   # (the cloud drifts: its reflections catch up over a few frames)
	sky.radiance_size = Sky.RADIANCE_SIZE_64
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
	# Bounced light (SDFGI, the "gi" setting): worked out from the real walls round the camera, so light
	# spreads round corners and through doorways and a room walled off from a lamp stays dark.
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.15
	env.sdfgi_bounce_feedback = 0.5
	env.sdfgi_enabled = bool(Settings.v.get("gi", false))
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


## Weather on the line: a front the train runs into or out of (line_events.gd) blends the stop's
## weather toward `line_weather` by `line_mix` (0 the stop's, 1 the front's).
var line_weather := ""
var line_mix := 0.0
var followers := 0   # something on the line followed the train: one more of them at the next stop

func weather_now() -> String:   # what's falling / blowing right now, for sounds and particles
	var w: String = "CLEAR" if at_checkpoint else stop.get("weather", "CLEAR")
	return line_weather if line_weather != "" and line_mix >= 0.5 else w


const _COVER := {"CLEAR": 0.3, "OVERCAST": 0.85, "RAIN": 0.92, "STORM": 1.0, "SANDSTORM": 0.55, "ACID_RAIN": 0.85, "BLIZZARD": 1.0}
const _DENSITY := {"SANDSTORM": 0.09, "BLIZZARD": 0.11, "ACID_RAIN": 0.03, "RAIN": 0.03, "STORM": 0.045, "OVERCAST": 0.018}


func _update_env() -> void:
	var under: bool = player.global_position.y < UNDERGROUND_Y
	var h := 11.0 if at_checkpoint else hours
	var day := clampf(remap(h, 16.5, 21.0, 1.0, 0.0), 0.0, 1.0)
	var dusk := clampf(1.0 - absf(h - 18.5) / 2.5, 0.0, 1.0)
	var dawn := clampf(remap(h, 7.5, 10.5, 1.0, 0.0), 0.0, 1.0)   # the run starts early: a low, gold morning
	var bio := Data.biome("DESERT" if at_checkpoint else stop.get("biome", "DESERT"))
	var w: String = "CLEAR" if at_checkpoint else stop.get("weather", "CLEAR")
	var w2: String = line_weather if line_weather != "" else w
	var m := line_mix if line_weather != "" else 0.0
	var flash: float = weather.flash if weather else 0.0
	train.headlight.light_energy = maxf(lerpf(6.0, 1.5, day), 7.0 * line.dark)   # (full beam in a tunnel)
	sun.visible = not under
	if under:   # (lightning still finds its way down through the cracks, faintly)
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color.BLACK
		env.ambient_light_color = Color(0.5, 0.45, 0.4).lerp(Color(0.7, 0.78, 1.0), clampf(flash * 3.0, 0.0, 1.0))
		env.ambient_light_energy = 0.12 + flash * 0.5
		env.volumetric_fog_density = 0.03
		env.volumetric_fog_albedo = Color(0.45, 0.38, 0.32)
		env.volumetric_fog_emission = Color.BLACK
		return
	# How much cloud, and how much it dims the sun.
	var cover: float = lerpf(_COVER.get(w, 0.3), _COVER.get(w2, 0.3), m)
	var dim := clampf(1.0 - (cover - 0.4) * 0.9, 0.35, 1.0)
	# Hazy wasteland: dusty orange by day (gold at dawn), rust-red at dusk, near black at night.
	var haze: Color = bio.haze
	haze = haze.lerp(Color(0.95, 0.66, 0.4), dawn * 0.5)
	var sky_day: Color = (bio.sky as Color).lerp(Color(0.5, 0.42, 0.42), dawn * 0.4)
	var sky_dusk := Color(0.5, 0.18, 0.08)
	var night := Color(0.02, 0.015, 0.02)
	var grey := (Color(0.42, 0.42, 0.42) if w != "ACID_RAIN" else Color(0.4, 0.45, 0.3)).lerp(Color(0.42, 0.42, 0.42) if w2 != "ACID_RAIN" else Color(0.4, 0.45, 0.3), m)
	sun.light_energy = 1.4 * day * dim
	sun.light_color = (bio.sun as Color).lerp(Color(1, 0.62, 0.35), dawn * 0.6).lerp(Color(1, 0.45, 0.2), dusk)   # cold light on snow
	sun.rotation_degrees.x = -8.0 - 50.0 * sin(PI * clampf((h - 6.0) / 16.0, 0.0, 1.0))
	env.background_mode = Environment.BG_SKY
	var top := sky_day.lerp(sky_dusk, dusk).lerp(night, 1.0 - day)
	var horizon := haze.lerp(Color(0.7, 0.3, 0.12), dusk).lerp(night, 1.0 - day)
	var murk := clampf((cover - 0.5) * 1.6, 0.0, 0.8)   # heavy cloud greys everything out
	top = top.lerp(grey * maxf(day, 0.04) * 0.8, murk)
	horizon = horizon.lerp(grey * maxf(day, 0.05), murk * 0.8)
	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", horizon)
	sky_mat.set_shader_parameter("ground_color", top.darkened(0.5))
	sky_mat.set_shader_parameter("sun_color", sun.light_color * day * dim)
	sky_mat.set_shader_parameter("cloud_color", horizon.lerp(top, 0.3).lerp(Color(0.85, 0.8, 0.75) * maxf(day, 0.06), 0.25 * day) * (0.9 if cover < 0.6 else 0.7))
	sky_mat.set_shader_parameter("clouds", cover)
	sky_mat.set_shader_parameter("stars", clampf(1.0 - day * 1.5, 0.0, 1.0) * clampf(1.0 - (cover - 0.3) * 1.6, 0.0, 1.0))
	env.ambient_light_color = haze.lerp(grey, murk * 0.6).lerp(Color(0.75, 0.8, 1.0), clampf(flash, 0.0, 1.0))
	env.ambient_light_energy = lerpf(0.04, 0.45, day) * lerpf(1.0, 0.8, murk) + flash * 0.8
	var density: float = lerpf(_DENSITY.get(w, 0.012), _DENSITY.get(w2, 0.012), m) + float(bio.fog)
	env.volumetric_fog_density = density
	var fog_col := haze.lerp(grey, murk * 0.7)
	var fog_of := func(ww: String) -> Color:
		if ww == "ACID_RAIN":
			return Color(0.55, 0.65, 0.35)
		if ww == "BLIZZARD":
			return Color(0.84, 0.88, 0.94)
		if ww == "SANDSTORM":   # (thick with blown sand: browner than the haze)
			return haze.lerp(Color(0.62, 0.44, 0.28), 0.45)
		return fog_col
	fog_col = (fog_of.call(w) as Color).lerp(fog_of.call(w2), m)
	var bz := lerpf(1.0 if w == "BLIZZARD" else 0.0, 1.0 if w2 == "BLIZZARD" else 0.0, m)
	if bz > 0.0:   # white-out: the sun a dim disc, everything washed blue-grey
		sun.light_energy *= lerpf(1.0, 0.35, bz)
		sky_mat.set_shader_parameter("top_color", top.lerp(Color(0.62, 0.66, 0.72) * maxf(day, 0.05), 0.8 * bz))
		sky_mat.set_shader_parameter("horizon_color", horizon.lerp(Color(0.75, 0.78, 0.84) * maxf(day, 0.05), 0.8 * bz))
	env.volumetric_fog_albedo = fog_col
	env.volumetric_fog_emission = fog_col * lerpf(0.12, 0.4, bz) * day
	# In a tunnel: no sky light, and the bore thick with old diesel smoke (it hides both ends).
	var cave: float = line.dark
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED if cave > 0.6 else Environment.REFLECTION_SOURCE_BG
	if cave > 0.0:
		env.ambient_light_energy *= 1.0 - 0.94 * cave
		env.volumetric_fog_density = lerpf(env.volumetric_fog_density, 0.03, cave)
		env.volumetric_fog_albedo = env.volumetric_fog_albedo.lerp(Color(0.3, 0.28, 0.26), cave)
		env.volumetric_fog_emission = env.volumetric_fog_emission.lerp(Color.BLACK, cave)


# --- progression / terminal features ---------------------------------------------------
	# Night vision: the tube amplifies what little light there is. Brighten the scene itself (so the
	# goggles have a real picture to work with, not black pixels), then hud.gd turns it green.
	if player.nv_on and not player.dead:
		env.ambient_light_energy = env.ambient_light_energy * 5.0 + 0.35
		env.tonemap_exposure = 2.4
		env.volumetric_fog_density *= 0.35   # (the tube sees through haze better than the eye)
	else:
		env.tonemap_exposure = 1.1

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
		"INFIRMARY", "WEATHERVANE":
			train.show_upgrade(u)
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
	var secs := (5.0 if has_upgrade("QUICK_DELIVERY") else 18.0) * Data.pace()
	net.event("handcar", [secs])
	var tw := create_tween()
	tw.tween_property(_handcar, "position:x", stop_x, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if tw.is_running():   # a long frame can finish it before we get here
		await tw.finished
	var batch := _orders.duplicate()
	_orders.clear()
	for i in batch.size():
		spawn_item(batch[i], train.to_global(Vector3(stop_x + rng.randf_range(-0.8, 0.8), 1.2 + i * 0.25, rng.randf_range(-0.6, 0.6))), -1.0, train)
	Sfx.play(self, "screech", train.to_global(Vector3(stop_x, 0.4, 0)), -14.0, 0.45)   # brakes on the rail
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
	for c in cells + fac.lower.keys():
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var span := Vector2(hi - lo) + Vector2.ONE
	var area := ctrl.size - Vector2(40, 80)
	var cs := minf(area.x / span.x, area.y / span.y)
	var off := Vector2(20, 60) + (area - span * cs) / 2.0
	var to_map := func(world: Vector3) -> Vector2:
		var l: Vector3 = fac.to_local(world) / Facility.CELL
		return off + (Vector2(l.x, l.z) - Vector2(lo) + Vector2(0.5, 0.5)) * cs
	var blue := Color(0.45, 0.7, 1.0)
	for c in fac.lower:   # the lower floor, drawn underneath and a little offset
		if fac.low_kinds[c] == "pit":
			continue
		var lp := off + Vector2(c - lo) * cs + Vector2.ONE * cs * 0.16
		ctrl.draw_rect(Rect2(lp, Vector2.ONE * cs * 0.76), Color(blue, 0.12))
		ctrl.draw_rect(Rect2(lp, Vector2.ONE * cs * 0.76), Color(blue, 0.55), false, 1.5)
		for n in fac.lower[c]:
			if n.x > c.x or n.y > c.y:
				var mid := off + (Vector2(c - lo) + Vector2(n - lo)) * cs / 2.0 + Vector2.ONE * cs * 0.54
				ctrl.draw_rect(Rect2(mid - Vector2.ONE * cs * 0.08, Vector2.ONE * cs * 0.16), Color(blue, 0.5))
	for c in cells:
		var p := off + Vector2(c - lo) * cs
		# Big rooms run on into their neighbours: no inset, no outline on those sides.
		var same := func(d: Vector2i) -> bool: return fac.group_of.has(c) and fac.group_of.get(c + d, -1) == fac.group_of[c]
		var l0: float = 0.0 if same.call(Vector2i(-1, 0)) else 0.08
		var r0: float = 1.0 if same.call(Vector2i(1, 0)) else 0.92
		var t0: float = 0.0 if same.call(Vector2i(0, -1)) else 0.08
		var b0: float = 1.0 if same.call(Vector2i(0, 1)) else 0.92
		var a := p + Vector2(l0, t0) * cs
		var z := p + Vector2(r0, b0) * cs
		ctrl.draw_rect(Rect2(a, z - a), Color(amber, 0.16 if fac.group_of.has(c) else 0.12))
		for side in [[Vector2i(-1, 0), Vector2(l0, t0), Vector2(l0, b0)], [Vector2i(1, 0), Vector2(r0, t0), Vector2(r0, b0)],
				[Vector2i(0, -1), Vector2(l0, t0), Vector2(r0, t0)], [Vector2i(0, 1), Vector2(l0, b0), Vector2(r0, b0)]]:
			if not same.call(side[0]):
				ctrl.draw_line(p + side[1] * cs, p + side[2] * cs, Color(amber, 0.7), 2.0)
		if fac.group_of.has(c) and fac.groups[fac.group_of[c]].cells[0] == c:
			ctrl.draw_string(font, p + Vector2(cs * 0.12, cs * 0.3), String(fac.groups[fac.group_of[c]].kind).replace("_", " ").to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, int(cs * 0.14), Color(amber, 0.8))
		for n in fac.layout.links[c]:
			if (n.x > c.x or n.y > c.y) and not same.call(n - c):
				var mid := off + (Vector2(c - lo) + Vector2(n - lo)) * cs / 2.0 + Vector2.ONE * cs * 0.5
				ctrl.draw_rect(Rect2(mid - Vector2.ONE * cs * 0.12, Vector2.ONE * cs * 0.24), Color(amber, 0.35))
		if c == Vector2i.ZERO:
			ctrl.draw_string(font, p + Vector2(cs * 0.15, cs * 0.55), "LIFT", HORIZONTAL_ALIGNMENT_LEFT, -1, int(cs * 0.22), amber)
		elif fac.kinds[c] in ["pit", "stairwell"]:
			ctrl.draw_string(font, p + Vector2(cs * 0.15, cs * 0.55), "B-2", HORIZONTAL_ALIGNMENT_LEFT, -1, int(cs * 0.22), blue)
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
		ctrl.draw_string(font, mp + Vector2(cs * 0.1, -cs * 0.08), "????" if code == fac.secure_code and not open else code, HORIZONTAL_ALIGNMENT_LEFT, -1, int(cs * 0.2), Color(1, 0.85, 0.3))
	for n in scanned:   # only what the scanner has found
		if is_instance_valid(n) and scanned[n][0].y < UNDERGROUND_Y:
			var sc: bool = scanned[n][2] == "scrap"
			ctrl.draw_circle(to_map.call(scanned[n][0]), maxf(2.0, cs * 0.035) if sc else maxf(3.0, cs * 0.05), Color(0.4, 1, 0.5) if sc else Color(1, 0.15, 0.1))
	if player.global_position.y < UNDERGROUND_Y:
		var pp: Vector2 = to_map.call(player.global_position)
		var fwd := Vector2(-sin(player.rotation.y), -cos(player.rotation.y))
		var side := Vector2(-fwd.y, fwd.x)
		ctrl.draw_colored_polygon(PackedVector2Array([pp + fwd * 9, pp - fwd * 6 + side * 6, pp - fwd * 6 - side * 6]), Color.WHITE)
	ctrl.draw_string(font, Vector2(20, ctrl.size.y - 16), "green: scrap scanned   red: entity scanned   bulkheads   BRK breaker   blue tint flooded   lime gas   blue outline: lower floor B-2", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(amber, 0.8))


## Heading-up HUD minimap round you (MINIMAP upgrade), underground only. The plan of the floor
## you're on (built once per site and drawn in two calls), the lift, the ways down; scrap and
## creatures only where your scanner last saw them (creatures fade out); your crew as a ping every
## five seconds; you in the middle.
var _mm_level: Node = null
var _mm_floors := {}     # false (B-1) / true (B-2) -> {"fill": [PackedVector2Array], "walls": PackedVector2Array, "labels": [[pos, text, colour]]}
var scanned := {}        # node -> [world position when scanned, time scanned, "scrap"/"entity"]
var _mm_ping := 0.0
var _mm_crew: Array = [] # [world position, name] at the last ping

const MM_PX := 3.4       # pixels per metre
const PING_EVERY := 5.0
const SCAN_FADE := 20.0  # seconds a scanned creature's mark stays on the map


func draw_minimap(ctrl: Control, center: Vector2, radius: float) -> void:
	if not has_upgrade("MINIMAP") or level == null or level.facility == null or player.global_position.y > UNDERGROUND_Y:
		return
	var fac = level.facility
	if _mm_level != level:
		_mm_build(fac)
	var font := ThemeDB.fallback_font
	var me: Vector3 = fac.to_local(player.global_position)
	var down: bool = me.y < -1.0
	var yaw: float = player.rotation.y
	ctrl.draw_rect(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2), Color(0.02, 0.02, 0.015, 0.72))
	# The plan: facility metres -> map pixels, heading up, in one transform.
	var xf := Transform2D(yaw, Vector2.ONE * MM_PX, 0.0, center) * Transform2D(0.0, -Vector2(me.x, me.z))
	ctrl.draw_set_transform_matrix(xf)
	var fl: Dictionary = _mm_floors[down]
	var col := Color(0.45, 0.7, 1.0) if down else Color(1, 0.62, 0.22)
	for poly in fl.fill:
		ctrl.draw_colored_polygon(poly, Color(col, 0.15))
	ctrl.draw_multiline(fl.walls, Color(col, 0.85), 2.0 / MM_PX)
	ctrl.draw_set_transform_matrix(Transform2D.IDENTITY)
	var to_map := func(world: Vector3) -> Vector2:
		var l: Vector3 = fac.to_local(world)
		return xf * Vector2(l.x, l.z)
	var clip := Rect2(center - Vector2.ONE * (radius - 4), Vector2.ONE * (radius - 4) * 2)
	for lb in fl.labels:
		var at: Vector2 = xf * Vector2(lb[0])
		if clip.has_point(at):
			ctrl.draw_string(font, at + Vector2(-16, 4), lb[1], HORIZONTAL_ALIGNMENT_CENTER, 32, 12, lb[2])
	if not down:   # the lift cab, lit when it's down here waiting
		var lp: Vector2 = to_map.call(level.elevator.global_position)
		var waiting: bool = not level.elevator.at_top and not level.elevator.moving
		if clip.has_point(lp):
			ctrl.draw_rect(Rect2(lp - Vector2(7, 7), Vector2(14, 14)), Color(1, 0.85, 0.3, 0.9 if waiting else 0.5), waiting, -1.0 if waiting else 2.0)
	# What the scanner found: scrap where it lies (until someone takes it), creatures where they were.
	var now := Time.get_ticks_msec() / 1000.0
	for n in scanned.keys():
		var e: Array = scanned[n]
		if not is_instance_valid(n) or n.is_queued_for_deletion() or (e[2] == "entity" and now - e[1] > SCAN_FADE):
			scanned.erase(n)
			continue
		if absf(e[0].y - player.global_position.y) > 4.0:
			continue
		var at: Vector2 = to_map.call(e[0])
		if not clip.has_point(at):
			continue
		if e[2] == "scrap":
			ctrl.draw_circle(at, 2.4, Color(0.5, 1.0, 0.55, 0.85))
		else:
			ctrl.draw_circle(at, 4.0, Color(1, 0.15, 0.1, clampf(1.0 - (now - e[1]) / SCAN_FADE, 0.15, 1.0)))
	# The crew: a ping every few seconds, fading.
	if now - _mm_ping >= PING_EVERY:
		_mm_ping = now
		_mm_crew.clear()
		for pup in net.puppets.values():
			if is_instance_valid(pup) and pup.visible and not pup.dead:
				_mm_crew.append([pup.global_position, pup.display_name.left(8)])
	var fade := clampf(1.0 - (now - _mm_ping) / 2.0, 0.0, 1.0)
	if fade > 0.0:
		for c in _mm_crew:
			var at: Vector2 = to_map.call(c[0])
			if clip.has_point(at):
				var g := Color(0.5, 1.0, 0.55, fade)
				ctrl.draw_arc(at, 4.0 + (1.0 - fade) * 10.0, 0.0, TAU, 20, g, 2.0)
				ctrl.draw_circle(at, 3.0, g)
				ctrl.draw_string(font, at + Vector2(7, -5), c[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, g)
	# You.
	ctrl.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -9), center + Vector2(6, 6), center + Vector2(-6, 6)]), Color.WHITE)
	ctrl.draw_rect(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2), Color(0.95, 0.93, 0.88, 0.8), false, 2.0)
	ctrl.draw_string(font, center + Vector2(-radius + 6, -radius + 15), "B-2" if down else "B-1", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.62, 0.22, 0.9))


## The plan of both floors, in facility metres: a fill per room and every wall as line segments,
## with a doorway gap where rooms link (big rooms open inside); labels for the lift and ways down.
func _mm_build(fac) -> void:
	_mm_level = level
	_mm_floors.clear()
	scanned.clear()
	var half := Facility.CELL * 0.5
	for down in [false, true]:
		var here: Dictionary = fac.lower if down else fac.layout.links
		var fill: Array = []
		var walls := PackedVector2Array()
		var labels: Array = []
		for c in here:
			var o := Vector2(c.x * Facility.CELL, c.y * Facility.CELL)
			var big: bool = not down and fac.group_of.has(c)
			var inset := 0.0 if big else half * 0.1
			var h := half - inset
			fill.append(PackedVector2Array([o + Vector2(-h, -h), o + Vector2(h, -h), o + Vector2(h, h), o + Vector2(-h, h)]))
			for d in Facility.DIRS:
				if big and fac.group_of.get(c + d, -1) == fac.group_of[c]:
					continue
				var dv := Vector2(d.x, d.y)
				var along := Vector2(-dv.y, dv.x)
				var linked: bool = here[c].has(c + d)
				for s in [-1.0, 1.0]:
					walls.append(o + dv * h + along * s * h)
					walls.append(o + dv * h + along * s * (1.3 if linked else 0.0))
			var kind: String = fac.low_kinds.get(c, "") if down else fac.kinds.get(c, "")
			if not down and c == Vector2i.ZERO:
				labels.append([o, "LIFT", Color(1, 0.85, 0.3)])
			elif kind in ["pit", "stairwell"]:
				labels.append([o, "UP" if down else "B-2", Color(0.45, 0.7, 1.0)])
		_mm_floors[down] = {"fill": fill, "walls": walls, "labels": labels}


# --- multiplayer: what net.gd calls ---------------------------------------------------------

## The session ended under us (the host left, the connection dropped): back to the title screen.
func _on_net_left(why: String) -> void:
	hud.alert("CONNECTION LOST: %s" % why)
	await get_tree().create_timer(2.5).timeout
	get_tree().reload_current_scene()


## Host: the shared state, four times a second.
func net_state() -> Dictionary:
	return {"credits": credits, "assignment": assignment, "quota": quota, "submitted": submitted, "prices": prices,
		"route": route, "taken": taken, "stage": stage, "departed": departed, "hours": hours, "warned": warned,
		"upgrades": upgrades, "logs": logs_unlocked, "stats": stats, "rank": payload_rank, "letter": _letter,
		"over": over, "fees": fees, "bank": bank, "divert": divert_bank, "banked_now": _banked_now, "crew": crew_size, "lost_from": _lost_from}


## Client: take the host's state.
func net_apply_state(st: Dictionary) -> void:
	credits = st.credits
	assignment = st.assignment
	quota = st.quota
	submitted = st.submitted
	prices = st.prices
	route = st.route
	taken = st.taken
	stage = st.stage
	if st.departed and not departed and at_checkpoint and level != null:
		level.open_gate()
	departed = st.departed
	if absf(st.hours - hours) > 0.05:
		hours = st.hours
	warned = st.warned
	for u in st.upgrades:   # the train's upgrades are everyone's
		if not upgrades.has(u):
			upgrades[u] = true
			match u:
				"BETTER_BOOTS": player.max_stamina = player.MAX_STAMINA * 2.0
				"STORAGE_CAR": train.add_storage_car()
				"DIGITAL_CLOCK": train.add_digital_clock()
				"INFIRMARY", "WEATHERVANE": train.show_upgrade(u)
	logs_unlocked = st.logs
	stats = st.stats
	payload_rank = st.rank
	_letter = st.letter
	fees = st.get("fees", 0)
	_lost_from = st.get("lost_from", _lost_from)
	crew_size = st.get("crew", 1)
	_banked_now = st.get("banked_now", 0)
	var was_bank := bank
	bank = st.get("bank", {})
	if bank != was_bank:
		_stock_changed()
	if st.get("divert", false) != divert_bank:
		divert_bank = st.get("divert", false)
		if at_checkpoint and level != null and level.get("shredder") != null:
			level.shredder.set_divert(divert_bank)


## Client: something the host says happened.
func net_event(ev: String, args: Array) -> void:
	match ev:
		"travel": _depart(args[0], args[1])
		"game_over": game_over(args[0])
		"restart": get_tree().reload_current_scene()
		"explode": _explode_fx(args[0], args[1], args[2], args[3])
		"bolt": weather.strike(args)
		"report": report.show_report(args[0])
		"gate":
			if level != null and level.has_method("open_gate"):
				level.open_gate()
		"handcar": _handcar_fx(args[0])
		"shredder":
			if level != null and level.get("shredder") != null:
				level.shredder.net_event(args)
		"alert": hud.alert(args[0])
		"msg": hud.msg(args[0])
		"door":
			if level != null and level.facility != null:
				level.facility.set_door(args[0], args[1], args[2])
		"hz":
			if level != null and level.hazards != null:
				level.hazards.net_event(args)
		"site":
			if level != null and level.get("site") != null:
				level.site.net_event(args)
		"director":
			if level != null and level.get("director") != null:
				level.director.net_event(args)
		"wedge":
			var d = _door_by_key(args[0])
			if d != null and d.has_method("set_wedged"):
				d.set_wedged(args[1], args[2])
		"photo": photo_log.append(net.wire_to_extra(args[0]))
		"pockets?":
			var mine: Array = player.slots.filter(func(it): return it != null)
			if player.equip != null:
				mine.append(player.equip)
			net.request("pockets", [mine.map(func(it): return net.item_to_wire(it))])


## Host: a crewmate asks for something.
func net_request(peer: int, what: String, args: Array) -> void:
	var who = net.puppets.get(peer) if peer != net.me() else player
	match what:
		"noise": noise(args[0], args[1])
		"pick":   # they want to pick something up
			var n = net.ents.get(args[0])
			if n == null or not is_instance_valid(n) or n.is_queued_for_deletion() or not n.is_in_group("pickups"):
				return
			var it := {"id": n.id, "charge": n.charge, "extra": n.extra}
			n.queue_free()
			net.to_owner(peer, "grant", net.item_to_wire(it))
		"drop":   # they let go of something (args: item, frame tag, local pos, velocity)
			var it: Dictionary = net.wire_to_item(args[0])
			var pos: Vector3 = net.frame(args[1]) * Vector3(args[2])
			var p = spawn_item(it.id, pos, it.charge, net.frame_node(args[1]) if args[1] != "W" else null)
			if p:
				p.set_extra(it.get("extra", {}))
				if "linear_velocity" in p:
					p.linear_velocity = args[3]
		"pin": pin_photo(net.wire_to_item(args[0]), train.to_global(args[1]), train.global_basis * Vector3(args[2]))
		"hit":   # they hit a creature (args: net id, damage, from)
			var m = net.ents.get(args[0])
			if m != null and is_instance_valid(m) and m.has_method("take_hit"):
				m.take_hit(args[1], args[2], who)
		"died": died_world(net.frame(args[0]) * Vector3(args[1]), args[2], net.name_of(peer))
		"wedge":
			var d = _door_by_key(args[0])
			if d != null and d.has_method("set_wedged") and not d.wedged:
				wedge_door(d)
		"pockets":
			if peer != net.me():
				crew_pockets[net.name_of(peer)] = args[0]


## Jam a swing door shut (the host does it, then everyone's copy).
func wedge_door(door: Node) -> void:
	if net.authority():
		door.set_wedged(true)
		net.event("wedge", [door.net_key(), true, false])
	else:
		net.request("wedge", [door.net_key()])


func _door_by_key(key: String) -> Node:
	var it = net.find_interact(key)
	return it.get_parent().get_parent() if it != null else null


## A weapon landed on a creature: the host decides what that does.
func hit_entity(m: Node, dmg: float, from: Vector3) -> void:
	if net.puppet_mirror(m):
		net.request("hit", [net.id_of(m), dmg, from])
	else:
		m.take_hit(dmg, from, player)


## Client, joining: build the stop the crew is at and step aboard.
func net_world(s: Dictionary, seed: int, serial: int, st: Dictionary) -> void:
	net_apply_state(st)
	if level != null:
		level.queue_free()
		level = null
	level_serial = serial - 1   # (_load_level counts it back up)
	_load_level(s, seed)
	net_apply_state(st)
	hours = st.hours
	_set_player_parent(self)
	player.global_position = train.to_global(Vector3(-2.0, 1.3, 0.0))
	player.velocity = Vector3.ZERO


func _explode_fx(pos: Vector3, radius: float, dmg: float, cause: String) -> void:
	Sfx.play(self, "boom", pos, 8.0)
	Blast.at(self, pos, radius, "flesh" if "pulsator" in cause.to_lower() else "fire")
	if player.global_position.distance_to(pos) < radius * 2.5:
		player.shake(0.06 * clampf(1.0 - player.global_position.distance_to(pos) / (radius * 2.5), 0.2, 1.0))


func _handcar_fx(secs: float) -> void:
	if _handcar == null:
		_handcar = train.make_handcar()
	var stop_x: float = train.rear_x() - 2.0
	_handcar.position.x = stop_x - 70.0
	create_tween().tween_property(_handcar, "position:x", stop_x, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


