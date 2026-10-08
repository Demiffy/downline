# Anything the player can press E on. hold_time > 0 means "hold E".
# With a crew, shared things (doors, the lift, bulkheads, crates, the breaker, the lever...) go
# through the host, which runs them for everyone (net.gd). Personal ones (terminals) stay local.
# Every machine builds the same world, so an interactable is found by where it is: its position
# in its frame (the train, the stop, or the creature/item it belongs to), to the centimetre.
extends StaticBody3D

var prompt := "Use"
var hold_time := 0.0
var action := Callable()
var shared := true
var _key := ""


func _ready() -> void:
	add_to_group("interactables")
	_make_key.call_deferred()   # once whoever built it has put it in place


func interact(who: Node) -> void:
	var net = get_tree().root.get_node_or_null("Net")
	if shared and net and net.active:
		net.interact(self, who)
	else:
		run(who)


static var who_now = null   # who's pressing it, while its action runs (messages go to them)


## Do it (net.gd calls this on every machine for shared things).
func run(who) -> void:
	if action.is_valid():
		who_now = who
		action.call()
		who_now = null


func net_key() -> String:
	if _key == "":
		_make_key()
	return _key


func _make_key() -> void:
	if not is_inside_tree():
		return
	var root: Node3D = null
	var tag := "M"
	var n := get_parent()
	while n != null and n is Node3D:
		if n.has_meta("net_id") or n.has_meta("net_puppet"):
			root = n
			tag = String(n.name)
			break
		if n.name == "Train":
			root = n
			tag = "T"
			break
		if n.name == "Level":
			root = n
			tag = "L"
			break
		n = n.get_parent()
	var p: Vector3 = root.to_local(global_position) if root else global_position
	_key = "%s|%d|%d|%d" % [tag, roundi(p.x * 100.0), roundi(p.y * 100.0), roundi(p.z * 100.0)]
