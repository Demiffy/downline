# Multiplayer: ENet over plain IP (the host forwards a port; everyone else joins by address).
# Lives at /root/Net and survives scene reloads (a restart keeps the session).
#
# Host-authoritative. The host runs the world: monsters, items, hazards, the clock, credits and the
# route. Each player runs only their own body. Levels are rebuilt from the same seed on every
# machine, so only things that move or change are sent:
#   entities  items, ragdolls and creatures get a net id ("E12") and are mirrored on clients
#             (spawn, transform at 15 Hz, a few state vars, free, events like death)
#   players   each owner sends its pose 20 times a second; others show a puppet (puppet.gd)
#   state     credits, clock, quota, route... a snapshot from the host 4 times a second
#   events    travel, hazards, doors, interactions, alerts, game over: sent as they happen
#   voice     each owner's microphone, cleaned up, 24 kHz 16-bit frames, to everyone (voice.gd)
# Single player never touches any of this: `active` is false and every check passes.
extends Node

const Pickup = preload("res://src/pickup.gd")
const Ragdoll = preload("res://src/ragdoll.gd")
const Puppet = preload("res://src/puppet.gd")
const Voice = preload("res://src/voice.gd")
const Sfx = preload("res://src/sfx.gd")
const Data = preload("res://src/data.gd")
const Blood = preload("res://src/blood.gd")
const Version = preload("res://src/version.gd")
const Settings = preload("res://src/settings.gd")
const Suit = preload("res://src/suit.gd")

const PORT := 24565
const MAX_PLAYERS := 6
const SYNC_HZ := 15.0
const SYNC_BYTES := 1100   # the most entity sync goes in one packet (under the MTU)
const POSE_HZ := 30.0
const STATE_HZ := 4.0

signal roster_changed
signal joined          # client: connected and welcomed
signal failed(why: String)
signal left(why: String)

var main                       # the current game (main.gd); re-attached after every reload
var my_name := "EMPLOYEE"
var roster := {}               # peer id -> {name}
var started := false           # the host has pressed START (lobby over)
var puppets := {}              # peer id -> puppet node (in the current main)
var voice                      # voice.gd
var ents := {}                 # net id -> node (host: everything registered; client: mirrors)
var _next_id := 1
var _last := {}                # host: net id -> last sent [tag, pos, quat]
var _vars_sent := {}           # host: net id -> last sent vars
var _pending := []             # client: spawns waiting for their level to load
var _targets := {}             # client: net id -> [tag, pos, quat, parts]
var _tbuf := {}                # client: net id -> the last few [arrival time, tag, pos, quat] (played back a beat late)
const MIRROR_DELAY := 0.13     # how far behind the host's updates mirrors are shown (two sync periods)
var _sync_t := 0.0
var _pose_t := 0.0
var _pose_n := 0
var _state_t := 0.0
var _term_peer := -1           # host: running a terminal command for this peer
var _term_out: PackedStringArray = []
var _confirms := {}            # host: peer -> pending YES/NO callable
var _no_fwd := false           # playing a sound that came over the network: don't send it back


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _drop("Could not reach the host."))
	multiplayer.server_disconnected.connect(func(): _drop("The host closed the session."))
	Sfx.net_hook = _sfx_hook
	voice = Voice.new()
	voice.net = self
	voice.main = main   # (attach() ran before we were in the tree: the first game would never be heard otherwise)
	add_child(voice)


## ENet throttles a connection it thinks is congested by quietly dropping unreliable packets (the
## voice, everyone's position). After a station arrives (a burst of hundreds of spawns from the
## host) it would decide the host's line was congested and keep dropping the host's voice: the
## crew stopped hearing the host. We'd rather send everything and let late voice frames be late.
func _no_throttle(id: int) -> void:
	var mp := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if mp == null:
		return
	var pp := mp.get_peer(id)
	if pp != null:
		pp.throttle_configure(5000, ENetPacketPeer.PACKET_THROTTLE_SCALE, 0)   # (never throttle down)


## The one Net, made on first use and kept across scene reloads.
static func get_or_make(tree: SceneTree) -> Node:
	var n := tree.root.get_node_or_null("Net")
	if n == null:
		n = load("res://src/net.gd").new()
		n.name = "Net"
		tree.root.add_child.call_deferred(n)   # (the root may be busy adding the game right now)
	return n


# --- state ------------------------------------------------------------------------------------

var active: bool:
	get: return is_inside_tree() and multiplayer != null and multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

var is_host: bool:
	get: return active and multiplayer.is_server()

## True where the world is simulated: single player, or the host.
func authority() -> bool:
	return not active or multiplayer.is_server()


func me() -> int:
	return multiplayer.get_unique_id() if active else 1


func name_of(peer: int) -> String:
	return String(roster.get(peer, {}).get("name", "EMPLOYEE %d" % peer))


# --- hosting / joining ------------------------------------------------------------------------

func host(port: int, player_name: String) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return "Could not open port %d (%s)." % [port, error_string(err)]
	peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	my_name = _clean(player_name)
	roster = {1: {"name": my_name, "look": Settings.look()}}
	started = false
	roster_changed.emit()
	return ""


func join(address: String, port: int, player_name: String) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), port)
	if err != OK:
		return "Could not connect to %s:%d (%s)." % [address, port, error_string(err)]
	peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	my_name = _clean(player_name)
	started = false
	return ""


func leave() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	roster = {}
	started = false
	_clear_world()


func _clear_world() -> void:
	for p in puppets.values():
		if is_instance_valid(p):
			p.queue_free()
	puppets.clear()
	ents.clear()
	_last.clear()
	_vars_sent.clear()
	_pending.clear()
	_targets.clear()
	_tbuf.clear()
	_confirms.clear()


func _drop(why: String) -> void:
	var was := active or roster.size() > 0
	leave()
	failed.emit(why)
	if was:
		left.emit(why)


static func _clean(s: String) -> String:
	var t := s.strip_edges().to_upper().left(16)
	return t if t != "" else "EMPLOYEE"


func _on_connected() -> void:
	_hello.rpc_id(1, my_name, Version.BUILD)
	_look.rpc_id(1, Settings.look())


## Your look changed (the crew editor): everyone's copy of you changes too.
func send_look() -> void:
	if not active:
		return
	if is_host:
		if roster.has(1):
			roster[1]["look"] = Settings.look()
			_roster.rpc(roster)
			roster_changed.emit()
	else:
		_look.rpc_id(1, Settings.look())


@rpc("any_peer", "reliable")
func _look(look: Array) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if roster.has(id) and look.size() == 3:
		roster[id]["look"] = [int(look[0]), int(look[1]), int(look[2])]
		_roster.rpc(roster)
		roster_changed.emit()
		dress_puppets()


func look_of(peer: int) -> Array:
	return roster.get(peer, {}).get("look", [0, 0, 0])


## Each crewmate's body in their own look, their name on their pack.
func dress_puppets() -> void:
	for id in puppets:
		var pup = puppets[id]
		if is_instance_valid(pup) and pup.has_node("Body"):
			Suit.apply_look(pup.get_node("Body"), look_of(id), name_of(id))


func _on_peer_connected(id: int) -> void:
	if voice:
		voice.add_peer(id)
	_no_throttle(id)


func _on_peer_disconnected(id: int) -> void:
	if voice:
		voice.remove_peer(id)
	var who := name_of(id)
	roster.erase(id)
	_confirms.erase(id)
	if puppets.has(id):
		if is_instance_valid(puppets[id]):
			puppets[id].queue_free()
		puppets.erase(id)
	if is_host:
		_roster.rpc(roster)
	roster_changed.emit()
	if main and started:
		main.hud.msg("%s left the shift." % who)


@rpc("any_peer", "reliable")
func _hello(player_name: String, build := "unknown") -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if roster.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	var mine: String = Version.BUILD
	if build != mine and mine != "dev" and build != "dev":   # (different code would desync)
		_version_mismatch.rpc_id(id, mine)
		get_tree().create_timer(1.0).timeout.connect(func(): multiplayer.multiplayer_peer.disconnect_peer(id))
		return
	var n := _clean(player_name)
	var taken: Array = roster.values().map(func(r): return r.name)
	var k := 2
	var base := n
	while n in taken:   # two of the same name: number them
		n = "%s %d" % [base.left(13), k]
		k += 1
	roster[id] = {"name": n}
	_roster.rpc(roster)
	roster_changed.emit()
	if started:   # joining a shift already under way: bring them up to date
		_welcome(id)


@rpc("authority", "reliable")
func _version_mismatch(host_build: String) -> void:
	_drop("Different builds: the host is on %s, you are on %s. Whoever is behind: restart the game to update (or get the latest zip from github.com/Demiffy/downline/releases)." % [host_build, Version.BUILD])


@rpc("authority", "reliable")
func _roster(r: Dictionary) -> void:
	roster = r
	dress_puppets()
	roster_changed.emit()
	joined.emit()


## Host: the lobby's over, start the shift (everyone already sits at the same checkpoint).
func start() -> void:
	if not is_host:
		return
	started = true
	_started.rpc()
	for id in roster:
		if id != 1:
			_welcome(id)


@rpc("authority", "reliable")
func _started() -> void:
	started = true
	roster_changed.emit()


# --- attaching to a game ----------------------------------------------------------------------

## main.gd calls this from _ready (every scene load).
func attach(m) -> void:
	main = m
	puppets.clear()
	ents.clear()
	_last.clear()
	_vars_sent.clear()
	_pending.clear()
	_targets.clear()
	_tbuf.clear()
	if voice:
		voice.main = m


## Host: everything a newcomer needs: where we are, the state, every entity.
func _welcome(id: int) -> void:
	if main == null:
		return
	if main.busy:   # mid-travel: try again when the train has arrived
		get_tree().create_timer(1.0).timeout.connect(_welcome.bind(id))
		return
	_world.rpc_id(id, main.stop, main.level_seed, main.level_serial, main.net_state())
	for nid in ents:
		var n = ents[nid]
		if is_instance_valid(n):
			_send_spawn(nid, n, id)
	_vars_sent.clear()   # (and everything's state again on the next sync, for the newcomer)
	_last.clear()
	main.net_welcomed(id)


@rpc("authority", "reliable")
func _world(stop: Dictionary, seed: int, serial: int, state: Dictionary) -> void:
	if main == null:
		return
	for p in main.get_tree().get_nodes_in_group("pickups"):   # our own starter kit: the host's is the real one
		p.queue_free()
	main.net_world(stop, seed, serial, state)
	started = true
	roster_changed.emit()


# --- per frame --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not active or main == null or not is_instance_valid(main):
		return
	_pose_t -= delta
	if _pose_t <= 0.0 and started:
		_pose_t = 1.0 / POSE_HZ
		_send_pose()
	if is_host:
		_sync_t -= delta
		if _sync_t <= 0.0:
			_sync_t = 1.0 / SYNC_HZ
			_send_sync()
		_state_t -= delta
		if _state_t <= 0.0 and started:
			_state_t = 1.0 / STATE_HZ
			_state.rpc(main.net_state())
	else:
		_apply_targets(delta)


# --- tags: which frame a position is measured in ------------------------------------------------

## "T" the train, "L" the current level, "W" the world. Moving frames (the level slides past during
## travel) carry what's on them.
func tag_of(n: Node3D) -> String:
	if main.train.is_ancestor_of(n):
		return "T"
	if main.level != null and main.level.is_ancestor_of(n):
		if _has_lift() and main.level.elevator.inside(n.global_position):
			return "E"   # in the lift cab: measured from the cab, so it rides smoothly on every machine
		return "L"
	return "W"


func frame(tag: String) -> Transform3D:
	match tag:
		"T": return main.train.global_transform
		"E": return main.level.elevator.cab.global_transform if _has_lift() else (main.level.global_transform if main.level != null else Transform3D.IDENTITY)
		"L": return main.level.global_transform if main.level != null else Transform3D.IDENTITY
	return Transform3D.IDENTITY


func _has_lift() -> bool:
	return main.level != null and main.level.elevator != null and is_instance_valid(main.level.elevator.cab)


func frame_node(tag: String) -> Node3D:
	match tag:
		"T": return main.train
		"E": return main.level.elevator.cab if _has_lift() else (main.level if main.level != null else main)
		"L": return main.level if main.level != null else main
	return main


# --- players ----------------------------------------------------------------------------------

func _send_pose() -> void:
	var p = main.player
	if p == null:
		return
	var tag := "T" if main.train.on_board(p.global_position) else ("L" if main.level != null else "W")
	if tag == "L" and _has_lift() and main.level.elevator.inside(p.global_position):
		tag = "E"   # riding the lift: where in the cab (each machine runs its own cab, a beat apart)
	var local: Vector3 = frame(tag).affine_inverse() * p.global_position
	var held = p.slots[p.sel]
	var pose := [tag, local, p.global_rotation.y - frame(tag).basis.get_euler().y, p.head.rotation.x, p.shape.height,
		held.id if held != null else "", p.light_on and held != null and held.get("charge", 0.0) > 0.0, p.dead, p.in_train,
		voice.speaking if voice else false, main.level_serial, p.is_on_floor(), p.headlamp_on, p.crack_tier]
	_pose_n += 1
	if _pose_n % 30 == 1:   # health and what's in their pockets (the STATUS command): once a second is plenty
		pose.append_array([int(p.hp), p.slots.map(func(s): return s.id if s != null else "")])
	_pose.rpc(pose)


@rpc("any_peer", "unreliable_ordered", "call_remote", 1)
func _pose(pose: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if main == null or not started:
		return
	var pup = puppets.get(id)
	if pup == null or not is_instance_valid(pup):
		pup = Puppet.new()
		pup.main = main
		pup.net = self
		pup.peer = id
		pup.display_name = name_of(id)
		pup.name = "Puppet%d" % id
		main.add_child(pup)
		puppets[id] = pup
		Suit.apply_look(pup.get_node("Body"), look_of(id), name_of(id))
		if voice:
			voice.attach_puppet(id, pup)
	pup.set_pose(pose)


## Host -> the player who owns a body: something happened to you.
func to_owner(peer: int, kind: String, a = null, b = null) -> void:
	if peer == me():
		_owner_effect(kind, a, b)
	else:
		_owner.rpc_id(peer, kind, a, b)


@rpc("authority", "reliable")
func _owner(kind: String, a, b) -> void:
	_owner_effect(kind, a, b)


func _owner_effect(kind: String, a, b) -> void:
	var p = main.player
	if p == null:
		return
	match kind:
		"hurt": p.net_hurt(a, b)
		"shake": p.shake(a)
		"blind": p.blind = maxf(p.blind, a)
		"light_off": p.light_on = false
		"drop": p.drop_held()
		"trapped": p.trapped = p if a else null   # (any non-null holds you)
		"teleport": p.global_position = frame(String(a)) * Vector3(b)
		"fog": main.hud.fog_visor(a)
		"take": p.consume(a)
		"grant": p.take(wire_to_item(a))
		"fling": p.velocity = a
		"photos": main.photo_log = a.map(func(w): return wire_to_extra(w))
		"msg": main.hud.msg(a)
		"snatched": _snatched()
		"alert": main.hud.alert(a)
		"tinnitus": p.ring_ears()
		"drain":
			var it = p.slots[p.sel]
			if it != null and it.get("charge", -1.0) > 0.0:
				it.charge = maxf(0.0, it.charge - float(a))


func _snatched() -> void:
	Sfx.play(main, "slurp", null, 2.0, 0.6)
	await main.hud.fade(1.0, 0.15)
	await get_tree().create_timer(1.6).timeout
	await main.hud.fade(0.0, 0.4)


# --- world state & events ---------------------------------------------------------------------

@rpc("authority", "reliable", "call_remote", 2)
func _state(s: Dictionary) -> void:
	if main and not is_host:
		main.net_apply_state(s)


## Host -> everyone else: something happened that they must see too. main.net_event(name, args).
func event(ev: String, args: Array = []) -> void:
	if is_host:
		_event.rpc(ev, args)


@rpc("authority", "reliable")
func _event(ev: String, args: Array) -> void:
	if main and is_instance_valid(main):
		main.net_event(ev, args)


## Anyone -> host: please do this (client requests). main.net_request(peer, what, args).
func request(what: String, args: Array = []) -> void:
	if is_host or not active:
		main.net_request(me(), what, args)
	else:
		_request.rpc_id(1, what, args)


@rpc("any_peer", "reliable")
func _request(what: String, args: Array) -> void:
	if is_host and main:
		main.net_request(multiplayer.get_remote_sender_id(), what, args)


# --- interactables ----------------------------------------------------------------------------

## Pressing E on something shared (doors, the lift, bulkheads, crates, the breaker, the lever...):
## the host runs it, then everyone else runs it too (their world-changing side effects, like
## spawning items, are the host's only).
func interact(it: Node, who: Node) -> void:
	var key: String = it.net_key()
	if is_host:
		it.run(who)
		_interacted.rpc(key, me())
	else:
		_interact_req.rpc_id(1, key)


@rpc("any_peer", "reliable")
func _interact_req(key: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	var it = find_interact(key)
	if it == null:
		return
	it.run(puppets.get(id))
	_interacted.rpc(key, id)


@rpc("authority", "reliable", "call_remote")
func _interacted(key: String, peer: int) -> void:
	var it = find_interact(key)
	if it != null:
		it.run(main.player if peer == me() else puppets.get(peer))


func find_interact(key: String) -> Node:
	if main == null:
		return null
	for it in main.get_tree().get_nodes_in_group("interactables"):
		if is_instance_valid(it) and it.net_key() == key:
			return it
	return null


# --- terminal ---------------------------------------------------------------------------------

## Client: this command changes the world, so the host runs it; its output comes back here.
func term_remote(line: String) -> void:
	_term_cmd.rpc_id(1, line)


@rpc("any_peer", "reliable")
func _term_cmd(line: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	_term_peer = id
	_term_out = []
	var a: Array = main.term.parse(line)
	if not a.is_empty() and _confirms.has(id) and a[0] in ["YES", "Y", "NO", "N"]:
		var c: Callable = _confirms[id]
		_confirms.erase(id)
		if a[0] in ["YES", "Y"]:
			c.call()
		else:
			main.term.say("Cancelled.")
	else:
		main.term.run_quiet(line)
		if main.term.confirm.is_valid():   # it asked YES/NO: keep the question for them, not for us
			_confirms[id] = main.term.confirm
			main.term.confirm = Callable()
	var out := _term_out
	_term_peer = -1
	_term_reply.rpc_id(id, out, _confirms.has(id))


## Host terminal: route a line of output to whoever asked (when running a remote command).
func term_capture(text: String) -> bool:
	if _term_peer < 0:
		return false
	_term_out.append(text)
	return true


@rpc("authority", "reliable")
func _term_reply(lines: PackedStringArray, asks: bool) -> void:
	if main == null:
		return
	for l in lines:
		main.term.say(l)
	if asks:
		main.term.confirm = func(): term_remote("YES")
		main.term.decline = func(): term_remote("NO")


# --- entities ---------------------------------------------------------------------------------

## Host: start mirroring this node. info: {"k": "item", "id", "charge", "extra"} / {"k": "rag", "pose"} /
## {"k": "mob", "script"}.
func register(n: Node3D, info: Dictionary) -> void:
	if not active or not is_host:
		return
	var nid := _next_id
	_next_id += 1
	n.name = "E%d" % nid
	n.set_meta("net_id", nid)
	n.set_meta("net_info", info)
	ents[nid] = n
	if started:
		_send_spawn(nid, n, 0)


func _send_spawn(nid: int, n: Node3D, to: int) -> void:
	if not n.is_inside_tree():
		n.ready.connect(_send_spawn.bind(nid, n, to), CONNECT_ONE_SHOT)
		return
	var tag := tag_of(n)
	var xf: Transform3D = frame(tag).affine_inverse() * n.global_transform
	var info: Dictionary = n.get_meta("net_info").duplicate()
	if info.k == "item":
		info.extra = extra_to_wire(n.extra if "extra" in n else {})
		info.frozen = n.freeze
	var args := [nid, info, tag, xf.origin, xf.basis.get_rotation_quaternion(), main.level_serial]
	if to == 0:
		_spawn.rpc(args)
	else:
		_spawn.rpc_id(to, args)


@rpc("authority", "reliable")
func _spawn(args: Array) -> void:
	if main == null:
		return
	if args[2] in ["L", "E"] and args[5] != main.level_serial:
		if args[5] > main.level_serial:
			_pending.append(args)   # for a level we haven't built yet
		return
	_make_mirror(args)


## Client: build the mirror of a host entity.
func _make_mirror(args: Array) -> void:
	var nid: int = args[0]
	if ents.has(nid) and is_instance_valid(ents[nid]):
		return
	var info: Dictionary = args[1]
	var parent := frame_node("L" if args[2] == "E" else args[2])   # (a mirror in the lift still belongs to the stop)
	var n: Node3D
	match info.k:
		"item":
			var p := Pickup.new()
			p.setup(info.id, info.charge)
			n = p
		"rag":
			var r := Ragdoll.new()
			r.pose = info.get("pose", "drop")
			r.puppet = true
			n = r
		"mob":
			var m = load(info.script).new()
			m.main = main
			m.level = main.level
			n = m
	n.name = "E%d" % nid
	n.set_meta("net_id", nid)
	n.set_meta("net_puppet", true)
	if info.has("look"):
		seed(info.look)   # its random looks (a scrapper's shell, a gloe's colour...) come out as the host's
	parent.add_child(n)
	if info.has("look"):
		randomize()
	n.global_transform = frame(args[2]) * Transform3D(Basis(args[4]), args[3])
	match info.k:
		"item":
			n.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			n.freeze = true
			n.set_extra(wire_to_extra(info.get("extra", {})))
			n.set_physics_process(false)
			n.contact_monitor = false
		"mob":
			n.set_physics_process(false)
			n.set_process(false)
			n.add_to_group("net_mobs")
	ents[nid] = n
	_targets[nid] = [args[2], args[3], args[4], null]


## main.gd calls this after building a level, so spawns that arrived early can land.
func level_loaded() -> void:
	var waiting := _pending.duplicate()
	_pending.clear()
	for a in waiting:
		if a[5] == main.level_serial:
			_make_mirror(a)
		elif a[5] > main.level_serial:
			_pending.append(a)


var _sync_n := 0

func _send_sync() -> void:
	_sync_n += 1
	var batch := []
	var gone := []
	for nid in ents.keys():
		var n = ents[nid]
		if not is_instance_valid(n) or not n.is_inside_tree() or n.is_queued_for_deletion():
			gone.append(nid)
			continue
		var tag := tag_of(n)
		var xf: Transform3D = frame(tag).affine_inverse() * n.global_transform
		var q: Quaternion = xf.basis.get_rotation_quaternion()
		var entry := [nid, tag, xf.origin, q]
		var prev = _last.get(nid)
		var moved: bool = prev == null or prev[0] != tag or (prev[1] as Vector3).distance_to(xf.origin) > 0.004 or (prev[2] as Quaternion).angle_to(q) > 0.01 \
			or (_sync_n + nid) % 30 == 0   # (resent now and then: a lost packet doesn't leave it stuck)
		var parts = null
		if n.get_meta("net_info").k == "rag" and "parts" in n and not n.parts.is_empty():
			parts = []
			for pn in n.parts.values():
				var pxf: Transform3D = frame(tag).affine_inverse() * pn.global_transform
				parts.append([pxf.origin, pxf.basis.get_rotation_quaternion()])
			moved = moved or n.parts.values().any(func(b): return b.linear_velocity.length() > 0.02)
		var vars = null
		if n.get_meta("net_info").k == "mob":   # only what changed (numbers that drift, like timers, 5 times a second)
			var full := _mob_vars(n)
			var sent: Dictionary = _vars_sent.get(nid, {})
			if (_sync_n + nid) % 15 == 0:
				sent = {}   # all of it now and then (these packets can get lost)
			var diff := {}
			for k in full:
				var v = full[k]
				if not sent.has(k) or (sent[k] != v and (not (v is float) or _sync_n % 3 == 0)):
					diff[k] = v
					sent[k] = v
			_vars_sent[nid] = sent
			if not diff.is_empty():
				vars = diff
				moved = true
		if not moved:
			continue
		_last[nid] = [tag, xf.origin, q]
		entry.append(parts)
		entry.append(vars)
		batch.append(entry)
	for nid in gone:
		ents.erase(nid)
		_last.erase(nid)
		_vars_sent.erase(nid)
	if not gone.is_empty():
		_freed.rpc(gone)
	# Small packets, each under the network's MTU (~1400 bytes): a bigger unreliable packet is cut
	# into pieces, and losing any piece loses the lot.
	var chunk := []
	var size := 0
	for e in batch:
		var b := var_to_bytes(e).size()
		if not chunk.is_empty() and size + b > SYNC_BYTES:
			_sync.rpc(chunk, main.level_serial)
			chunk = []
			size = 0
		chunk.append(e)
		size += b
	if not chunk.is_empty():
		_sync.rpc(chunk, main.level_serial)


## A creature's simple script variables (bools, numbers), and who it's after (a player, sent as
## "@var": their peer id, 0 for nobody): enough for its animation to follow along on the clients.
func _mob_vars(n: Node) -> Dictionary:
	var d := {}
	for prop in _var_list(n):
		var v = n.get(prop.name)
		var t: int = prop.type
		if t in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT]:
			d[prop.name] = snappedf(v, 0.01) if t == TYPE_FLOAT else v
		elif v == null and t == TYPE_NIL:   # (untyped: a "who"; typed node refs are its own parts)
			d["@" + prop.name] = 0
		elif v is Node and is_instance_valid(v) and v.is_in_group("players"):
			d["@" + prop.name] = v.peer if "peer" in v and v.peer != 0 else 1
	return d


var _var_lists := {}   # script -> the properties worth sending (looked up once)

func _var_list(n: Node) -> Array:
	var sc: Script = n.get_script()
	if not _var_lists.has(sc):
		var l := []
		for prop in sc.get_script_property_list():
			if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or prop.name in ["dead", "health", "unstuck_count", "main", "level"]:
				continue   # (death comes as an event)
			if prop.type in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_NIL, TYPE_OBJECT]:
				l.append(prop)
		_var_lists[sc] = l
	return _var_lists[sc]


## A player by peer id, as this machine has them: us, a puppet, or nobody.
func player_of(peer: int) -> Node:
	if peer == 0 or main == null:
		return null
	if peer == me():
		return main.player
	var p = puppets.get(peer)
	return p if p != null and is_instance_valid(p) else null


@rpc("authority", "unreliable_ordered", "call_remote", 3)
func _sync(batch: Array, serial: int) -> void:
	if main == null:
		return
	for e in batch:
		if e[1] in ["L", "E"] and serial != main.level_serial:
			continue
		_targets[e[0]] = [e[1], e[2], e[3], e[4]]
		var buf: Array = _tbuf.get(e[0], [])
		if not buf.is_empty() and buf[-1][1] != e[1]:
			buf.clear()
		buf.append([Time.get_ticks_msec() / 1000.0, e[1], e[2], e[3]])
		while buf.size() > 6:
			buf.pop_front()
		_tbuf[e[0]] = buf
		var n = ents.get(e[0])
		if e[5] != null and n != null and is_instance_valid(n):
			for k: String in e[5]:
				if k.begins_with("@"):
					n.set(k.substr(1), player_of(e[5][k]))
				else:
					n.set(k, e[5][k])


@rpc("authority", "reliable")
func _freed(ids: Array) -> void:
	for nid in ids:
		var n = ents.get(nid)
		if n != null and is_instance_valid(n) and not n.is_queued_for_deletion():
			n.queue_free()
		ents.erase(nid)
		_targets.erase(nid)
		_tbuf.erase(nid)


## Client: ease every mirror toward where the host last said it was.
func _apply_targets(delta: float) -> void:
	var k := minf(1.0, delta * 14.0)
	for nid in _targets.keys():
		var n = ents.get(nid)
		if n == null or not is_instance_valid(n):
			_targets.erase(nid)
			continue
		if n.get("dead") == true:
			continue   # dying: its own fall plays out here (death_anim), not the host's frames
		var t: Array = _targets[nid]
		var want: Transform3D = _buffered(nid, t)
		var far: bool = n.global_position.distance_to(want.origin) > 4.0
		n.global_transform = want if far else n.global_transform.interpolate_with(want, minf(1.0, delta * 30.0))
		if t[3] != null and "parts" in n and not n.parts.is_empty():
			var i := 0
			for pn in n.parts.values():
				if i < t[3].size():
					var pw: Transform3D = frame(t[0]) * Transform3D(Basis(t[3][i][1]), t[3][i][0])
					pn.global_transform = pn.global_transform.interpolate_with(pw, k)
				i += 1
		if n.is_in_group("net_mobs") and n.has_method("net_visual"):
			n.net_visual(delta)


## Where a mirror was MIRROR_DELAY ago, between the two updates either side (or the latest).
func _buffered(nid: int, t: Array) -> Transform3D:
	var buf: Array = _tbuf.get(nid, [])
	if buf.size() < 2:
		return frame(t[0]) * Transform3D(Basis(t[2]), t[1])
	var now := Time.get_ticks_msec() / 1000.0 - MIRROR_DELAY
	for i in range(buf.size() - 1, 0, -1):
		var a: Array = buf[i - 1]
		var b: Array = buf[i]
		if now >= a[0] and now <= b[0]:
			var k: float = (now - a[0]) / maxf(b[0] - a[0], 0.001)
			var q: Quaternion = (a[3] as Quaternion).slerp(b[3], k)
			return frame(b[1]) * Transform3D(Basis(q), (a[2] as Vector3).lerp(b[2], k))
	var last: Array = buf[-1] if now > buf[-1][0] else buf[0]
	return frame(last[1]) * Transform3D(Basis(last[3] as Quaternion), last[2])


## Host -> everyone: something happened to an entity (death, a hit, a bite...). The mirror runs it.
func ent_event(n: Node, ev: String, args: Array = []) -> void:
	if is_host and n.has_meta("net_id"):
		_ent_event.rpc(n.get_meta("net_id"), ev, args)


@rpc("authority", "reliable")
func _ent_event(nid: int, ev: String, args: Array) -> void:
	var n = ents.get(nid)
	if n != null and is_instance_valid(n) and n.has_method("net_event"):
		n.net_event(ev, args)


func id_of(n: Node) -> int:
	return n.get_meta("net_id", -1) if n != null else -1


func puppet_mirror(n: Node) -> bool:
	return n != null and n.has_meta("net_puppet")


# --- items over the wire ----------------------------------------------------------------------

static func extra_to_wire(e: Dictionary) -> Dictionary:
	var w := {}
	for k in e:
		if e[k] is Texture2D:
			var img: Image = e[k].get_image().duplicate()
			img.clear_mipmaps()
			w[k] = {"jpg": img.save_jpg_to_buffer(0.85)}   # (a grainy print: ~20 KB, where a PNG was ~250)
		else:
			w[k] = e[k]
	return w


static func wire_to_extra(w: Dictionary) -> Dictionary:
	var e := {}
	for k in w:
		if w[k] is Dictionary and (w[k].has("png") or w[k].has("jpg")):
			var img := Image.new()
			if w[k].has("jpg"):
				img.load_jpg_from_buffer(w[k].jpg)
			else:
				img.load_png_from_buffer(w[k].png)
			img.generate_mipmaps()
			e[k] = ImageTexture.create_from_image(img)
		else:
			e[k] = w[k]
	return e


static func item_to_wire(it: Dictionary) -> Dictionary:
	var w := it.duplicate()
	w.extra = extra_to_wire(it.get("extra", {}))
	return w


static func wire_to_item(w: Dictionary) -> Dictionary:
	var it := w.duplicate()
	it.extra = wire_to_extra(w.get("extra", {}))
	return it


# --- sound ------------------------------------------------------------------------------------

## Sfx.play asks this first. Creatures and items are heard as the host hears them; your own sounds
## (footsteps, coughs, a dropped wrench) go out to everyone else.
const PRIVATE_SOUNDS := ["error", "ding", "tinnitus", "heartbeat", "beep_ui"]   # yours alone (the HUD's, your ears')

func _sfx_hook(parent: Node, sound: String, pos, db: float, pitch: float) -> bool:
	if not active or _no_fwd or main == null or not is_instance_valid(main) or parent == null:
		return true
	var src := _sound_src(parent)
	if src == "":
		return true
	if pos == null:   # a sound "in your head" (your grunt, a swish, a click): the others hear it from you
		if src != "me" or sound in PRIVATE_SOUNDS or main.player == null:
			return true
		_sfx.rpc(sound, main.player.global_position + Vector3(0, 1.4, 0), db, pitch)
		return true
	if is_host:
		_sfx.rpc(sound, pos, db, pitch)
		return true
	if src == "ent":
		return false   # the host sends these
	_sfx.rpc(sound, pos, db, pitch)
	return true


func _sound_src(n: Node) -> String:
	var p := n
	while p != null and p != main:
		if p == main.player:
			return "me"
		if p.has_meta("net_id"):
			return "ent"
		p = p.get_parent()
	return ""


@rpc("any_peer", "unreliable", "call_remote", 4)
func _sfx(sound: String, pos: Vector3, db: float, pitch: float) -> void:
	if main == null or not is_instance_valid(main):
		return
	_no_fwd = true
	Sfx.play(main, sound, pos, db, pitch)
	_no_fwd = false


# --- your body, as others see it ---------------------------------------------------------------

## Blood you spilled: the same splat on everyone's floor.
func blood(parent: Node3D, pos: Vector3, size: float) -> void:
	if not active or not started:
		return
	var tag := "T" if parent == main.train else ("L" if parent == main.level else "W")
	_blood.rpc(tag, frame(tag).affine_inverse() * pos, size, main.level_serial)


@rpc("any_peer", "unreliable", "call_remote", 4)
func _blood(tag: String, local: Vector3, size: float, serial: int) -> void:
	if main == null or (tag == "L" and serial != main.level_serial):
		return
	Blood.spill(frame_node(tag), frame(tag) * local, size)


## Something you did with your hands (a swing, a shot): your puppet does it on everyone's screen.
func act(kind: String, arg = null) -> void:
	if active and started:
		_act.rpc(kind, arg)


@rpc("any_peer", "reliable", "call_remote")
func _act(kind: String, arg) -> void:
	var pup = puppets.get(multiplayer.get_remote_sender_id())
	if pup != null and is_instance_valid(pup):
		pup.act(kind, arg)


# --- voice ------------------------------------------------------------------------------------

func send_voice(frame_bytes: PackedByteArray) -> void:
	if active and started:
		_voice.rpc(frame_bytes)


@rpc("any_peer", "unreliable", "call_remote", 5)
func _voice(frame_bytes: PackedByteArray) -> void:
	if voice:
		voice.receive(multiplayer.get_remote_sender_id(), frame_bytes)

