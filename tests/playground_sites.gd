# The playground's newer tools work: every button on the SITES page and every emote on the PLAYER
# page pressed in turn (rebuilding as each biome, each landmark and the dam stop, the dam's spots, the
# puzzles, the site's day, one trip with every line event forced), checking what each should do.
# Run: tests/run.sh 600 --headless --path . -s tests/playground_sites.gd -- playground
extends SceneTree

var fails := 0
var main
var pg


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	_run()


func press(page: String, label: String) -> void:
	var b := _find(pg._pages[page], label)
	if b == null:
		check(false, "button '%s' is on the %s page" % [label, page])
		return
	b.pressed.emit()
	for i in 6:
		await process_frame
	while not pg._ready_done or main.busy:
		await process_frame


func _find(n: Node, label: String) -> Button:
	for c in n.find_children("*", "Button", true, false):
		if (c as Button).text == label:
			return c
	return null


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	while main.get_node_or_null("Playground") == null and not main.get_children().any(func(c): return c.get_script() != null and c.get_script().resource_path.ends_with("playground.gd")):
		await process_frame
	for c in main.get_children():
		if c.get_script() != null and c.get_script().resource_path.ends_with("playground.gd"):
			pg = c
	while not pg._ready_done:
		await process_frame
	check(pg._pages.has("SITES"), "the playground has a SITES page")
	for b in ["DESERT", "ARCTIC", "FOREST", "SWAMP", "CITY"]:
		await press("SITES", b)
		check(main.level.biome == b and main.player.global_position.y > -10.0, "rebuilt as %s, and you're up top" % b)
	for k in ["CHAPEL", "LOOKOUT", "FARM", "FUEL"]:
		await press("SITES", k)
		check(main.level.landmark == k, "the %s landmark stands there" % k)
	await press("SITES", "To the landmark")
	check(main.player.global_position.distance_to(main.level.to_global(main.level._landmark_at)) < 20.0, "...and you can go to it")
	await press("SITES", "Build the dam stop")
	check(main.level.dam and main.level.facility.theme_id == "DAM", "the dam stop is built")
	for spot in ["Spillway basin", "Foot of the stairs", "Crest road", "The windings (below)"]:
		var before: Vector3 = main.player.global_position
		await press("SITES", spot)
		check(main.player.global_position.distance_to(before) > 1.0, "the dam: %s" % spot)
	var wet: int = main.level.hazards.flooded.size()
	await press("SITES", "Sluices (18:00)")
	check(main.level.hazards.flooded.size() > wet, "the sluices open and rooms flood")
	for b in ["Records room door", "Code on the wall", "Twin-key blast door", "To a lever", "Burst a main", "Lockdown", "Lockdown over", "Lift fault", "Director scare", "Clock to 18:00"]:
		await press("SITES", b)
	check(main.level.elevator.get("crawl") == null or main.level.elevator.crawl >= 3.0, "the lift crawls after its fault")
	check(absf(main.hours - 18.0) < 0.1, "the clock goes to 18:00")
	await press("WORLD", "Up / down  [F9]")   # (somewhere with a floor under you)
	for i in 30:
		await process_frame
	for em in pg.BodyAnim.EMOTES:
		await press("PLAYER", String(em).capitalize())
		check(main.player.anim.emote == em, "emote: %s" % em)
		main.player.emote("")
	var letter: String = main.stop.letter
	Engine.set_meta("fast_test", true)   # (the ride itself at ten times: the events still fire on the way)
	await press("SITES", "All of them")
	Engine.remove_meta("fast_test")
	check(main.stop.letter != letter and not main.busy, "a trip with every line event forced arrives at the next stop (%s -> %s)" % [letter, main.stop.letter])
	print("playground_sites.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
