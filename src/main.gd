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
	_register_commands()
	player = Player.new()
	player.main = self
	add_child(player)
	player.position = Vector3(-3, 1.3, 0)
	player.rotation.y = -PI / 2
	player.died.connect(_on_died)
	var drone := AudioStreamPlayer.new()
	drone.stream = Sfx.stream("drone")
	drone.volume_db = -22.0
	add_child(drone)
	drone.play()
	_load_level(CHECKPOINT_STOP)
	spawn_item("FLASHLIGHT", Vector3(5.6, 2.0, -1.5), -1.0, train)
	spawn_item("SCANNER", Vector3(6.62, 2.0, -1.6), -1.0, train)
	var f := FileAccess.open(BEST_PATH, FileAccess.READ)
	if f:
		best = int(JSON.parse_string(f.get_as_text()).get("best", 0))
	hud.msg("Welcome aboard, employee. Starter kit is on the shelf.")
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
		if d <= radius:
			hits.append([d, Data.ITEMS[p.id].name, p, false])
	for m in get_tree().get_nodes_in_group("monsters"):
		var d := origin.distance_to(m.global_position)
		if d <= radius:
			hits.append([d, "UNKNOWN ENTITY", m, true])
	hits.sort_custom(func(a, b): return a[0] < b[0])
	var lines := PackedStringArray()
	for h in hits.slice(0, 10):
		lines.append("%-18s %3dm" % [h[1], int(h[0])])
		var tag := B.label(h[2], h[1], Vector3(0, 0.7, 0), 40, Color(1, 0.3, 0.3) if h[3] else Color(0.6, 1, 0.8))
		tag.no_depth_test = true
		tag.fixed_size = true
		tag.pixel_size = 0.0006
		get_tree().create_timer(4.0).timeout.connect(func(): if is_instance_valid(tag): tag.queue_free())
	hud.set_scan("SCAN  %d in range\n%s" % [hits.size(), "\n".join(lines)])
	Sfx.play(self, "scan", null, -6.0)


# --- frame loop ----------------------------------------------------------------

func _process(delta: float) -> void:
	if over:
		if Input.is_action_just_pressed("restart"):
			get_tree().reload_current_scene()
		return
	player.in_train = train.contains(player.global_position)
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
	var t := "CHECKPOINT" if at_checkpoint else "%02d:%02d" % [int(hours) % 24, int(fmod(hours, 1.0) * 60.0)]
	var q := _quota_text()
	hud.set_status(t, q, "CHECKPOINT" if at_checkpoint else "STATION %s" % stop.get("letter", "?"))
	train.clock_label.text = t
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
		s += "on train: %s" % Data.res_text(train_res)
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
	await get_tree().create_timer(1.5).timeout
	if over:
		return
	if not train.contains(player.global_position):
		# You watch it leave.
		var tw := create_tween()
		tw.tween_property(train, "position:x", SLIDE * 2, SLIDE_SECS * 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await tw.finished
		game_over("LEFT BEHIND\nThe train departed on schedule. You did not.")
		return
	for p in get_tree().get_nodes_in_group("pickups"):
		if train.contains(p.global_position):
			p.reparent(train)
	# The world slides backwards while the train "pulls away".
	level.process_mode = Node.PROCESS_MODE_DISABLED
	var out := create_tween()
	out.tween_property(level, "position:x", -SLIDE, SLIDE_SECS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(SLIDE_SECS - 1.5).timeout
	await hud.fade(1.0, 1.5)
	if over:
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
	await get_tree().create_timer(1.0).timeout
	_load_level(s)
	level.process_mode = Node.PROCESS_MODE_DISABLED
	level.position.x = SLIDE
	_last_level_x = SLIDE
	var inn := create_tween()
	inn.tween_property(level, "position:x", 0.0, SLIDE_SECS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await hud.fade(0.0, 1.5)
	await inn.finished
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
	if assignment > 0 and not departed and _quota_met() and level.gate_light.light_color.g < 0.5:
		stats.assignments += 1
		level.open_gate()
		hud.alert("QUOTA MET. Gate unlocked. LEAVE_CHECKPOINT when ready.")


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
	await get_tree().create_timer(2.5).timeout
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
	await get_tree().create_timer(1.5).timeout
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
	term.say("STATION %s\n  Facility:  %s\n  Size:      %s (%d sectors)\n  Surface:   %s\n  Weather:   %s"
		% [o.letter, o.theme, size, o.rooms, o.biome, o.weather.replace("_", " ") if has_upgrade("WEATHERVANE") else "UNKNOWN (needs WEATHERVANE)"])


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
	Sfx.play(self, "ding", null, -6.0)
	term.say("%s installed." % u)


func _cams() -> Array:
	if level == null or level.facility == null:
		return []
	return level.facility.cameras


func _c_list_cams(_a) -> void:
	var cams := _cams()
	if cams.is_empty():
		term.say("No security cameras at this location.")
		return
	term.say("Scanning for cameras.....\n%d camera(s) found:" % cams.size())
	for c in cams:
		term.say("  [%s]" % c.name)
	term.say("Use VIEW_CAM <n> to view a feed. Arrow keys pan.")


func _c_view_cam(a) -> void:
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
	var secs := 6.0 if has_upgrade("QUICK_DELIVERY") else 45.0
	var tw := create_tween()
	tw.tween_property(_handcar, "position:x", stop_x, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
	ctrl.draw_string(font, Vector2(20, ctrl.size.y - 16), "green: scrap   red: entity   dots on walls: bulkheads", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(amber, 0.8))


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
