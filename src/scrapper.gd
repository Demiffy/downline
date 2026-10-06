# The Scrapper: a nervous bug that wears a heap of junk as a shell. It looks like a scrap pile,
# sleeps until it hears footsteps, then scuttles away fast. Sneak up crouched and grab it (E):
# it's worth a lot of scrap. Harmless, and a bit sad.
extends "res://src/monster.gd"

const RUN := 5.5

var fleeing := 0.0
var _from := Vector3.ZERO
var _shell: Node3D
var _legs: Array[Node3D] = []
var _grab: StaticBody3D
var _chitter := 0.0


func _ready() -> void:
	_setup_body(0.3, 0.6, true)
	presence("rattle", -14.0, 2.5)
	_shell = Node3D.new()
	add_child(_shell)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var kinds := ["rust", "metal", "cream", "wood", "corrugated"]
	for i in 9:
		var s := rng.randf_range(0.12, 0.3)
		A.box(_shell, Vector3(s, s * 0.5, s * 1.2), Vector3(rng.randf_range(-0.2, 0.2), 0.18 + rng.randf() * 0.15, rng.randf_range(-0.2, 0.2)), kinds[rng.randi() % kinds.size()], Color.WHITE, false, 0.4,
			Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5)))
	A.cyl(_shell, 0.12, 0.08, Vector3(0.12, 0.33, -0.05), "metal", Color(0.15, 0.15, 0.15), false, "z")
	for x in [-0.05, 0.05]:
		A.sphere(_shell, 0.025, Vector3(x, 0.12, -0.26), "cream", Color(1, 0.85, 0.3), 3.0)
	for i in 6:
		var side := -1.0 if i < 3 else 1.0
		var leg := Node3D.new()
		add_child(leg)
		leg.position = Vector3(side * 0.18, 0.12, -0.12 + (i % 3) * 0.12)
		A.box(leg, Vector3(0.22, 0.025, 0.025), Vector3(side * 0.11, -0.04, 0), "metal", Color(0.2, 0.18, 0.15), false, 0.3, Vector3(0, 0, side * -0.5))
		leg.scale = Vector3(0.2, 1, 1)
		_legs.append(leg)
	_grab = B.interactable(self, Vector3(0.6, 0.45, 0.6), Vector3(0, 0.22, 0), Color(0, 0, 0, 0), "Grab the scrap pile", _grabbed)
	_grab.get_child(1).visible = false
	_grab.collision_layer = 2


func hear(pos: Vector3) -> void:
	if fleeing <= 0.0:
		Sfx.play(self, "chitter", global_position, 0.0)
	fleeing = 3.5
	_from = pos


func _grabbed() -> void:
	if fleeing > 0.0:
		main.hud.msg("It skitters out of reach!")
		return
	main.spawn_item("SCRAPPER_SHELL", global_position + Vector3(0, 0.4, 0), -1.0, level)
	Sfx.play(main, "pickup", null, -4.0)
	main.hud.msg("Caught the scrapper. Its shell is worth a lot.")
	queue_free()


func _physics_process(delta: float) -> void:
	fleeing -= delta
	if fleeing > 0.0:
		var away := global_position - _from
		away.y = 0.0
		if away.length() < 0.1:
			away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		walk_to(global_position + away.normalized() * 4.0, RUN, delta, 14.0)
		for i in _legs.size():
			_legs[i].scale.x = 1.0
			_legs[i].rotation.y = sin(_anim * 12.0 + i) * 0.5
		_shell.position.y = 0.06 + absf(sin(_anim * 12.0)) * 0.03
		_grab.prompt = "It's too fast to grab!"
	else:
		stand_still(delta)
		for leg in _legs:
			leg.scale.x = 0.2
		_shell.position.y = 0.0
		_grab.prompt = "Grab the scrap pile"
