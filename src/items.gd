# Item models: one hand-built model per scrap/tool, centred in the item's Data `size` box
# (which stays the physics shape). Used by world pickups and by the first-person hand.
# To add scrap: an entry in Data.ITEMS + a branch in build(). Unknown ids get a plain box.
extends RefCounted

const A = preload("res://src/art.gd")
const Data = preload("res://src/data.gd")
const Merge = preload("res://src/merge.gd")
const Suit = preload("res://src/suit.gd")

const X := Vector3(0, 0, PI / 2)   # rotate a y-axis cylinder/torus onto x
const Z := Vector3(PI / 2, 0, 0)   # ... onto z
const RED := Color(0.78, 0.13, 0.09)
const BLACK := Color(0.12, 0.12, 0.12)
const STEEL := Color(0.78, 0.8, 0.82)
const CREAM := Color(0.9, 0.86, 0.75)


static func build(id: String) -> Node3D:
	var r := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	match id:
		"BENT_SPRING":
			for i in 10:
				ring(r, 0.062, 0.05, Vector3(sin(i * 0.32) * 0.035, -0.135 + i * 0.03, 0), "metal", STEEL, Vector3(0.28, 0, 0.04 * i))
		"BROKEN_SPEAKER":
			box(r, Vector3(0.38, 0.48, 0.31), Vector3(0, 0, -0.01), "wood", Color(0.55, 0.42, 0.35))
			box(r, Vector3(0.35, 0.45, 0.01), Vector3(0, 0, 0.15), "rubber")
			ring(r, 0.13, 0.1, Vector3(0, -0.08, 0.16), "rubber", Color.WHITE, Z)
			cyl(r, 0.035, 0.05, Vector3(0, -0.08, 0.14), "paper", Color(0.35, 0.33, 0.3), Z, 0.105)
			ball(r, 0.032, Vector3(0, -0.08, 0.165), "rubber")
			box(r, Vector3(0.07, 0.05, 0.004), Vector3(0.05, -0.05, 0.168), "paper", Color(0.35, 0.33, 0.3), Vector3(0.3, 0, 0.5))   # torn flap
			cyl(r, 0.04, 0.02, Vector3(0, 0.14, 0.16), "metal", STEEL, Z)
			ball(r, 0.022, Vector3(0, 0.14, 0.17), "metal", Color(0.3, 0.3, 0.3))
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				ball(r, 0.008, Vector3(c.x * 0.15, c.y * 0.2, 0.158), "metal", STEEL)
			seg(r, Vector3(0.1, -0.2, -0.16), Vector3(0.14, -0.24, -0.2), 0.006, 0.006, "rubber")
		"COOKING_PAN":
			cyl(r, 0.12, 0.05, Vector3(-0.07, -0.01, 0), "metal", Color(0.4, 0.4, 0.42), Vector3.ZERO, 0.14)
			cyl(r, 0.118, 0.003, Vector3(-0.07, 0.014, 0), "rust", Color(0.4, 0.35, 0.33))
			ring(r, 0.142, 0.134, Vector3(-0.07, 0.015, 0), "metal", STEEL)
			box(r, Vector3(0.19, 0.024, 0.034), Vector3(0.14, 0.02, 0), "plastic", BLACK, Vector3(0, 0, 0.15))
			ring(r, 0.011, 0.006, Vector3(0.22, 0.032, 0), "metal", STEEL)
			for z in [-0.01, 0.01]:
				ball(r, 0.006, Vector3(0.05, 0.01, z), "metal", STEEL)
		"COPPER_INGOT", "STEEL_INGOT":
			var k := "copper" if id == "COPPER_INGOT" else "metal"
			var t := Color.WHITE if id == "COPPER_INGOT" else STEEL
			ingot(r, Vector3(0.3, 0.09, 0.12), k, t)
			box(r, Vector3(0.08, 0.003, 0.04), Vector3(-0.05, 0.046, 0), k, t.darkened(0.35))   # the stamp
		"COPPER_PIPE":
			seg(r, Vector3(0, 0, 0.27), Vector3(0, 0, -0.33), 0.027, 0.027, "copper")
			cyl(r, 0.033, 0.05, Vector3(0, 0, 0.02), "copper", Color(0.9, 0.85, 0.8), Z)
			ball(r, 0.032, Vector3(0, 0, 0.29), "copper")
			seg(r, Vector3(0, 0, 0.29), Vector3(0.0, 0.035, 0.32), 0.03, 0.03, "copper")
			cyl(r, 0.031, 0.02, Vector3(0, 0, -0.33), "copper", Color(0.8, 0.8, 0.8), Z)
		"EMPTY_CAN":
			var lab: Color = [Color(0.8, 0.2, 0.15), Color(0.2, 0.45, 0.8), Color(0.25, 0.6, 0.25)][rng.randi() % 3]
			cyl(r, 0.044, 0.12, Vector3(0, -0.005, 0), "metal", STEEL)
			cyl(r, 0.0445, 0.075, Vector3(0, -0.01, 0), "paper", lab)
			box(r, Vector3(0.03, 0.03, 0.003), Vector3(0, 0, 0.044), "paper", CREAM)
			for y in [0.054, -0.063]:
				ring(r, 0.045, 0.039, Vector3(0, y, 0), "metal", STEEL)
			box(r, Vector3(0.02, 0.003, 0.012), Vector3(0.01, 0.057, 0), "metal", STEEL)
		"HAMMER":
			seg(r, Vector3(0, 0, 0.2), Vector3(0, 0, -0.14), 0.016, 0.013, "wood")
			seg(r, Vector3(0, 0, 0.2), Vector3(0, 0, 0.07), 0.02, 0.019, "rubber", Color(0.7, 0.2, 0.15))
			box(r, Vector3(0.085, 0.034, 0.038), Vector3(0.0, 0, -0.165), "metal", Color(0.45, 0.45, 0.47))
			cyl(r, 0.021, 0.025, Vector3(0.05, 0, -0.165), "metal", STEEL, X)
			for s in [-1, 1]:
				box(r, Vector3(0.05, 0.012, 0.03), Vector3(-0.06, 0, -0.165 + s * 0.008), "metal", Color(0.45, 0.45, 0.47), Vector3(0, s * 0.15, -0.5))
		"HAZARD_CONE":
			box(r, Vector3(0.34, 0.03, 0.34), Vector3(0, -0.285, 0), "rubber")
			cyl(r, 0.13, 0.53, Vector3(0, 0, 0), "plastic", Color(1, 0.42, 0.05), Vector3.ZERO, 0.02)
			for b in [[-0.12, -0.06], [0.0, 0.07]]:
				var y0: float = b[0]
				var y1: float = b[1]
				cyl(r, 0.13 - (y0 + 0.265) * 0.2075 + 0.003, y1 - y0, Vector3(0, (y0 + y1) / 2, 0), "plastic", Color(0.95, 0.95, 0.9), Vector3.ZERO, 0.13 - (y1 + 0.265) * 0.2075 + 0.003)
		"LARGE_SCREW":
			cyl(r, 0.036, 0.03, Vector3(0, 0.155, 0), "metal", STEEL)
			box(r, Vector3(0.05, 0.01, 0.008), Vector3(0, 0.168, 0), "metal", Color(0.2, 0.2, 0.2))
			cyl(r, 0.013, 0.27, Vector3(0, 0.005, 0), "metal", STEEL)
			for i in 10:
				ring(r, 0.021, 0.012, Vector3(0, -0.11 + i * 0.024, 0), "metal", STEEL, Vector3(0.15, 0, 0))
			cyl(r, 0.002, 0.04, Vector3(0, -0.15, 0), "metal", STEEL, Vector3.ZERO, 0.013)
		"MILK_JUG":
			box(r, Vector3(0.17, 0.19, 0.17), Vector3(0, -0.045, 0), "plastic", Color(0.95, 0.95, 0.9))
			cyl(r, 0.1, 0.05, Vector3(0, 0.075, 0), "plastic", Color(0.95, 0.95, 0.9), Vector3.ZERO, 0.035)
			cyl(r, 0.03, 0.03, Vector3(0, 0.11, 0), "plastic", Color(0.95, 0.95, 0.9))
			cyl(r, 0.034, 0.022, Vector3(0, 0.135, 0), "plastic", Color(0.85, 0.15, 0.12))
			seg(r, Vector3(0.085, 0.05, 0), Vector3(0.115, 0.03, 0), 0.012, 0.012, "plastic", Color(0.95, 0.95, 0.9))
			seg(r, Vector3(0.115, 0.03, 0), Vector3(0.115, -0.06, 0), 0.012, 0.012, "plastic", Color(0.95, 0.95, 0.9))
			seg(r, Vector3(0.115, -0.06, 0), Vector3(0.085, -0.08, 0), 0.012, 0.012, "plastic", Color(0.95, 0.95, 0.9))
			box(r, Vector3(0.172, 0.08, 0.12), Vector3(0, -0.05, 0), "paper", Color(0.55, 0.75, 0.95))
		"OLD_BOOT":
			var lc := Color(0.78, 0.55, 0.36)
			box(r, Vector3(0.115, 0.024, 0.29), Vector3(0, -0.112, -0.005), "rubber", Color(0.18, 0.16, 0.15))   # sole
			box(r, Vector3(0.105, 0.03, 0.07), Vector3(0, -0.095, 0.1), "rubber", Color(0.18, 0.16, 0.15))   # heel
			seg(r, Vector3(0, -0.07, 0.07), Vector3(0, -0.078, -0.09), 0.056, 0.045, "leather", lc)   # the foot, rounded at the toe
			ball(r, 0.046, Vector3(0, -0.078, -0.09), "leather", lc.darkened(0.1), Vector3(1.15, 0.75, 1.0))   # toe cap
			cyl(r, 0.05, 0.16, Vector3(0, -0.005, 0.08), "leather", lc, Vector3(0.1, 0, 0), 0.054)   # the shaft
			seg(r, Vector3(0, -0.06, 0.09), Vector3(0, -0.07, 0.02), 0.052, 0.054, "leather", lc)   # the ankle, into the foot
			ring(r, 0.062, 0.05, Vector3(0, 0.08, 0.09), "leather", lc.darkened(0.3))   # padded collar
			box(r, Vector3(0.05, 0.12, 0.016), Vector3(0, 0.01, 0.028), "leather", lc.darkened(0.15), Vector3(-0.2, 0, 0))   # tongue
			for i in 5:   # laces criss-crossing up the front
				box(r, Vector3(0.07, 0.006, 0.008), Vector3(0, -0.05 + i * 0.026, 0.034 + i * 0.005), "canvas", CREAM, Vector3(-0.2, 0, 0.3 if i % 2 == 0 else -0.3))
		"OLD_CLOCK":
			cyl(r, 0.14, 0.06, Vector3.ZERO, "wood", Color(0.6, 0.45, 0.35), Z)
			cyl(r, 0.124, 0.002, Vector3(0, 0, 0.031), "paper", CREAM, Z)
			for i in 12:
				var a := TAU * i / 12.0
				box(r, Vector3(0.006, 0.02 if i % 3 == 0 else 0.012, 0.002), Vector3(sin(a) * 0.105, cos(a) * 0.105, 0.033), "metal", BLACK, Vector3(0, 0, -a))
			var h := rng.randf() * TAU
			var m := rng.randf() * TAU
			box(r, Vector3(0.008, 0.06, 0.002), Vector3(sin(h) * 0.028, cos(h) * 0.028, 0.035), "metal", BLACK, Vector3(0, 0, -h))
			box(r, Vector3(0.005, 0.09, 0.002), Vector3(sin(m) * 0.043, cos(m) * 0.043, 0.036), "metal", BLACK, Vector3(0, 0, -m))
			ball(r, 0.008, Vector3(0, 0, 0.037), "brass")
			ring(r, 0.142, 0.13, Vector3(0, 0, 0.032), "brass", Color.WHITE, Z)
		"PENNY":
			for i in 5:
				cyl(r, 0.04, 0.006, Vector3(rng.randf_range(-0.006, 0.006), -0.015 + i * 0.0065, rng.randf_range(-0.006, 0.006)), "copper")
			cyl(r, 0.04, 0.006, Vector3(0.03, -0.005, 0.02), "copper", Color.WHITE, Vector3(0.4, 0, 0.3))
		"RED_COPPER_PAN":
			var cu := Color(0.95, 0.55, 0.45)
			cyl(r, 0.115, 0.05, Vector3(0, -0.012, -0.04), "copper", cu, Vector3.ZERO, 0.135)
			ring(r, 0.138, 0.128, Vector3(0, 0.013, -0.04), "copper", cu)
			cyl(r, 0.127, 0.004, Vector3(0, 0.012, -0.04), "metal", Color(0.3, 0.3, 0.32))   # the dark non-stick inside
			box(r, Vector3(0.026, 0.018, 0.15), Vector3(0, 0.02, 0.165), "metal", Color(0.75, 0.75, 0.78), Vector3(-0.15, 0, 0))   # steel handle
			ring(r, 0.012, 0.006, Vector3(0, 0.032, 0.235), "metal", STEEL, Z)
		"RUBBER_BAND_BALL":
			ball(r, 0.085, Vector3.ZERO, "plastic", Color(0.55, 0.3, 0.25))
			var cols := [Color(0.85, 0.3, 0.22), Color(0.9, 0.8, 0.6), Color(0.3, 0.5, 0.9), Color(0.35, 0.75, 0.35), Color(0.95, 0.85, 0.25)]
			for i in 8:
				ring(r, 0.088, 0.08, Vector3.ZERO, "plastic", cols[i % cols.size()], Vector3(rng.randf() * TAU, rng.randf() * TAU, 0))
		"RUBBER_TIRE":
			ring(r, 0.29, 0.19, Vector3.ZERO, "rubber", Color.WHITE, Z)
			for i in 22:
				var a := TAU * i / 22.0
				box(r, Vector3(0.045, 0.012, 0.085), Vector3(cos(a), sin(a), 0) * 0.287, "rubber", Color(0.8, 0.8, 0.8), Vector3(0, 0, a + PI / 2))
			cyl(r, 0.19, 0.09, Vector3.ZERO, "metal", Color(0.55, 0.55, 0.58), Z)
			cyl(r, 0.06, 0.11, Vector3.ZERO, "metal", STEEL, Z)
			for i in 5:
				var a := TAU * i / 5.0
				cyl(r, 0.01, 0.12, Vector3(cos(a), sin(a), 0) * 0.08, "metal", STEEL, Z)
		"SCISSORS":
			for s in [-1, 1]:
				box(r, Vector3(0.012, 0.004, 0.13), Vector3(s * 0.006, s * 0.002, -0.05), "metal", STEEL, Vector3(0, s * 0.07, 0))
				ring(r, 0.03, 0.019, Vector3(s * 0.025, s * 0.002, 0.065), "plastic", Color(0.85, 0.15, 0.15))
				box(r, Vector3(0.01, 0.006, 0.04), Vector3(s * 0.012, s * 0.002, 0.03), "plastic", Color(0.85, 0.15, 0.15), Vector3(0, s * 0.4, 0))
			ball(r, 0.008, Vector3(0, 0.004, 0.012), "metal", STEEL)
		"TOY_DINO":
			var g := Color(0.4, 0.85, 0.35)
			ball(r, 0.08, Vector3(0, -0.02, 0), "plastic", g, Vector3(1, 0.85, 1.4))
			seg(r, Vector3(0, 0.0, -0.08), Vector3(0, 0.08, -0.115), 0.035, 0.028, "plastic", g)
			box(r, Vector3(0.055, 0.05, 0.08), Vector3(0, 0.095, -0.14), "plastic", g)
			for s in [-1, 1]:
				ball(r, 0.008, Vector3(s * 0.028, 0.105, -0.155), "plastic", BLACK)
				for z in [-0.05, 0.05]:
					cyl(r, 0.021, 0.07, Vector3(s * 0.045, -0.09, z), "plastic", g)
			seg(r, Vector3(0, -0.02, 0.1), Vector3(0, 0.0, 0.15), 0.04, 0.008, "plastic", g)
			for i in 5:
				box(r, Vector3(0.008, 0.03, 0.03), Vector3(0, 0.05 - absf(i - 2) * 0.008, -0.06 + i * 0.035), "plastic", Color(0.95, 0.6, 0.2), Vector3(PI / 4, 0, 0))
		"TOY_TRUCK", "TOY_FORKLIFT":
			var body := Color(0.95, 0.8, 0.15) if id == "TOY_TRUCK" else Color(1, 0.5, 0.1)
			box(r, Vector3(0.28, 0.03, 0.15), Vector3(0, -0.045, 0), "plastic", Color(0.3, 0.3, 0.3))
			for s in [-1, 1]:
				for x in [-0.08, 0.08]:
					cyl(r, 0.035, 0.03, Vector3(x, -0.065, s * 0.075), "rubber", Color.WHITE, Z)
					cyl(r, 0.018, 0.032, Vector3(x, -0.065, s * 0.075), "plastic", Color(0.85, 0.85, 0.85), Z)
			if id == "TOY_TRUCK":
				box(r, Vector3(0.09, 0.1, 0.15), Vector3(-0.09, 0.03, 0), "plastic", body)
				box(r, Vector3(0.092, 0.04, 0.12), Vector3(-0.09, 0.05, 0), "glass", Color.WHITE)
				box(r, Vector3(0.17, 0.06, 0.15), Vector3(0.05, 0.0, 0), "plastic", body)
				box(r, Vector3(0.15, 0.005, 0.13), Vector3(0.05, 0.031, 0), "plastic", body.darkened(0.4))
				for s in [-1, 1]:
					ball(r, 0.01, Vector3(-0.136, 0.0, s * 0.05), "glow", Color(1, 0.95, 0.7))
			else:
				box(r, Vector3(0.14, 0.07, 0.14), Vector3(0.04, 0.0, 0), "plastic", body)
				box(r, Vector3(0.04, 0.06, 0.12), Vector3(0.11, 0.0, 0), "plastic", Color(0.3, 0.3, 0.3))
				box(r, Vector3(0.04, 0.03, 0.06), Vector3(0.04, 0.05, 0), "plastic", BLACK)
				for s in [-1, 1]:
					for x in [-0.02, 0.09]:
						seg(r, Vector3(x, 0.03, s * 0.06), Vector3(x, 0.1, s * 0.06), 0.006, 0.006, "metal", BLACK)
					box(r, Vector3(0.015, 0.17, 0.02), Vector3(-0.07, 0.03, s * 0.045), "metal", Color(0.4, 0.4, 0.4))
					box(r, Vector3(0.1, 0.008, 0.018), Vector3(-0.12, -0.07, s * 0.04), "metal", Color(0.4, 0.4, 0.4))
				box(r, Vector3(0.13, 0.008, 0.14), Vector3(0.035, 0.105, 0), "plastic", body)
		"WATER_BOTTLE":
			var bl := Color(0.55, 0.78, 0.95)
			cyl(r, 0.042, 0.2, Vector3(0, -0.045, 0), "plastic", bl)
			for y in [-0.1, -0.04, 0.02]:
				ring(r, 0.044, 0.038, Vector3(0, y, 0), "plastic", bl.darkened(0.15))
			cyl(r, 0.042, 0.045, Vector3(0, 0.077, 0), "plastic", bl, Vector3.ZERO, 0.018)
			cyl(r, 0.019, 0.025, Vector3(0, 0.11, 0), "plastic", bl)
			cyl(r, 0.021, 0.025, Vector3(0, 0.133, 0), "metal", STEEL)
			cyl(r, 0.0435, 0.055, Vector3(0, -0.07, 0), "paper", Color(0.2, 0.45, 0.85))
			cyl(r, 0.044, 0.012, Vector3(0, -0.07, 0), "paper", CREAM)
		"WATER_POUCH":
			ball(r, 0.13, Vector3(0, -0.005, 0), "plastic", Color(0.35, 0.42, 0.3), Vector3(1, 0.33, 0.85))
			cyl(r, 0.018, 0.04, Vector3(0.1, 0.03, 0), "plastic", BLACK, Vector3(0, 0, -0.6))
			cyl(r, 0.022, 0.015, Vector3(0.115, 0.048, 0), "plastic", Color(0.2, 0.5, 0.8), Vector3(0, 0, -0.6))
			box(r, Vector3(0.28, 0.01, 0.025), Vector3(0, 0.035, 0.0), "canvas", Color(0.35, 0.35, 0.3))
		"PUMP_GASKET":
			ring(r, 0.145, 0.09, Vector3.ZERO, "rubber")
			for i in 6:
				var a := TAU * i / 6.0
				cyl(r, 0.011, 0.05, Vector3(cos(a) * 0.118, 0, sin(a) * 0.118), "metal", STEEL)
				cyl(r, 0.017, 0.012, Vector3(cos(a) * 0.118, 0.02, sin(a) * 0.118), "metal", STEEL)
		"WIRE_SPOOL":
			for s in [-1, 1]:
				cyl(r, 0.14, 0.02, Vector3(s * 0.13, 0, 0), "plastic", Color(0.9, 0.75, 0.2), X)
			cyl(r, 0.1, 0.24, Vector3.ZERO, "copper", Color.WHITE, X)
			for i in 9:
				ring(r, 0.103, 0.096, Vector3(-0.11 + i * 0.0275, 0, 0), "copper", Color.WHITE, X)
			cyl(r, 0.035, 0.27, Vector3.ZERO, "plastic", Color(0.3, 0.3, 0.3), X)
			seg(r, Vector3(0.05, 0.1, 0), Vector3(0.1, 0.14, 0.08), 0.004, 0.004, "copper")
		"FLASHLIGHT":
			var y := Color(0.95, 0.75, 0.15)
			seg(r, Vector3(0, 0, 0.14), Vector3(0, 0, -0.08), 0.027, 0.027, "plastic", y)
			seg(r, Vector3(0, 0, 0.1), Vector3(0, 0, 0.0), 0.0285, 0.0285, "knurl")
			seg(r, Vector3(0, 0, -0.08), Vector3(0, 0, -0.14), 0.028, 0.035, "plastic", y)
			cyl(r, 0.037, 0.016, Vector3(0, 0, -0.145), "metal", STEEL, Z)
			cyl(r, 0.031, 0.004, Vector3(0, 0, -0.153), "glass", Color.WHITE, Z)
			cyl(r, 0.029, 0.02, Vector3(0, 0, 0.145), "rubber", Color.WHITE, Z)
			box(r, Vector3(0.016, 0.01, 0.03), Vector3(0, 0.03, -0.04), "rubber")
		"LANTERN":
			var br := Color.WHITE
			cyl(r, 0.08, 0.035, Vector3(0, -0.13, 0), "brass", br)
			cyl(r, 0.06, 0.15, Vector3(0, -0.035, 0), "glass", br)
			ball(r, 0.025, Vector3(0, -0.04, 0), "cream", Color(0.75, 0.68, 0.55))   # the mantle (lit only in your hand)
			for i in 4:
				var a := TAU * i / 4.0 + 0.4
				seg(r, Vector3(cos(a) * 0.066, -0.115, sin(a) * 0.066), Vector3(cos(a) * 0.066, 0.045, sin(a) * 0.066), 0.005, 0.005, "brass", br)
			cyl(r, 0.072, 0.03, Vector3(0, 0.06, 0), "brass", br, Vector3.ZERO, 0.035)
			cyl(r, 0.02, 0.02, Vector3(0, 0.085, 0), "brass", br)
			ring(r, 0.06, 0.053, Vector3(0, 0.09, 0), "metal", Color(0.4, 0.4, 0.4), Z)
		"SCANNER":
			box(r, Vector3(0.09, 0.15, 0.05), Vector3(0, -0.01, 0), "plastic", Color(0.3, 0.32, 0.3))
			box(r, Vector3(0.07, 0.055, 0.003), Vector3(0, 0.03, 0.026), "glow", Color(0.3, 1, 0.6))
			box(r, Vector3(0.095, 0.06, 0.055), Vector3(0, -0.06, 0), "rubber")
			for i in 3:
				ball(r, 0.008, Vector3(-0.025 + i * 0.025, -0.02, 0.026), "plastic", [RED, Color(0.9, 0.8, 0.2), Color(0.3, 0.8, 0.3)][i])
			seg(r, Vector3(0.03, 0.065, 0), Vector3(0.03, 0.095, 0), 0.005, 0.004, "metal", BLACK)
			ball(r, 0.009, Vector3(0.03, 0.098, 0), "glow", Color(1, 0.2, 0.15))
		"BACKPACK":
			var o := Color(0.62, 0.66, 0.42)
			box(r, Vector3(0.34, 0.4, 0.18), Vector3(0, -0.03, 0), "canvas", o)
			box(r, Vector3(0.35, 0.12, 0.19), Vector3(0, 0.16, 0.005), "canvas", o.darkened(0.15), Vector3(-0.08, 0, 0))
			box(r, Vector3(0.24, 0.16, 0.05), Vector3(0, -0.1, 0.11), "canvas", o.darkened(0.08))
			for s in [-1, 1]:
				box(r, Vector3(0.05, 0.38, 0.02), Vector3(s * 0.09, -0.02, -0.1), "leather")
				box(r, Vector3(0.03, 0.2, 0.012), Vector3(s * 0.08, 0.05, 0.096), "leather")
				box(r, Vector3(0.035, 0.025, 0.01), Vector3(s * 0.08, -0.03, 0.104), "metal", STEEL)
				box(r, Vector3(0.04, 0.16, 0.06), Vector3(s * 0.19, -0.08, 0), "canvas", o.darkened(0.1))
			cyl(r, 0.05, 0.32, Vector3(0, 0.235, 0), "canvas", Color(0.5, 0.35, 0.3), X)
		"DISK":
			box(r, Vector3(0.12, 0.005, 0.12), Vector3.ZERO, "plastic", Color(0.2, 0.3, 0.7))
			box(r, Vector3(0.06, 0.006, 0.04), Vector3(0, 0, -0.04), "metal", STEEL)
			box(r, Vector3(0.09, 0.006, 0.06), Vector3(0, 0, 0.025), "paper", CREAM)
			box(r, Vector3(0.012, 0.006, 0.012), Vector3(-0.045, 0, 0.05), "plastic", BLACK)
		"SCRAPPER_SHELL":
			for i in 14:
				var p := Vector3(rng.randf_range(-0.17, 0.17), rng.randf_range(-0.1, 0.08), rng.randf_range(-0.17, 0.17))
				var kind: String = ["metal", "rust", "copper", "rubber", "plastic"][rng.randi() % 5]
				if i % 3 == 0:
					cyl(r, rng.randf_range(0.03, 0.07), rng.randf_range(0.08, 0.2), p, kind, Color.WHITE, Vector3(rng.randf() * PI, 0, rng.randf() * PI))
				else:
					box(r, Vector3(rng.randf_range(0.06, 0.18), rng.randf_range(0.03, 0.1), rng.randf_range(0.06, 0.16)), p, kind, Color.WHITE, Vector3(rng.randf(), rng.randf() * PI, rng.randf()))
		# --- heavy, two-handed ---
		"ENGINE_BLOCK":
			var blk := Color(0.42, 0.43, 0.45)
			box(r, Vector3(0.62, 0.32, 0.4), Vector3(0, -0.08, 0), "metal", blk)
			for k in 4:   # cylinder bores along the top
				cyl(r, 0.07, 0.06, Vector3(-0.22 + k * 0.145, 0.1, 0), "metal", Color(0.2, 0.2, 0.2))
				ring(r, 0.075, 0.06, Vector3(-0.22 + k * 0.145, 0.13, 0), "metal", STEEL)
			box(r, Vector3(0.66, 0.06, 0.44), Vector3(0, 0.1, 0), "metal", blk.darkened(0.15))
			box(r, Vector3(0.6, 0.12, 0.12), Vector3(0, -0.18, 0.23), "rust", Color.WHITE)   # oil pan edge
			cyl(r, 0.13, 0.05, Vector3(0.34, -0.06, 0), "metal", Color(0.3, 0.3, 0.3), X)   # flywheel stub
			ring(r, 0.14, 0.12, Vector3(0.36, -0.06, 0), "metal", STEEL, X)
			for k in 4:
				seg(r, Vector3(-0.22 + k * 0.145, 0.0, 0.2), Vector3(-0.22 + k * 0.145, -0.05, 0.3), 0.025, 0.02, "rust")
			box(r, Vector3(0.18, 0.1, 0.12), Vector3(-0.2, -0.05, -0.24), "metal", Color(0.3, 0.3, 0.3))
		"TRANSFORMER":
			var tg := Color(0.38, 0.45, 0.4)
			box(r, Vector3(0.44, 0.48, 0.34), Vector3(0, -0.06, 0), "metal", tg)
			for k in 7:   # cooling fins
				box(r, Vector3(0.02, 0.4, 0.42), Vector3(-0.19 + k * 0.063, -0.08, 0), "metal", tg.darkened(0.2))
			for k in 3:   # ceramic bushings on top
				var bx := -0.13 + k * 0.13
				cyl(r, 0.03, 0.14, Vector3(bx, 0.25, 0), "cream", Color(0.75, 0.55, 0.4))
				for j in 3:
					ring(r, 0.045, 0.028, Vector3(bx, 0.21 + j * 0.04, 0), "cream", Color(0.75, 0.55, 0.4))
				cyl(r, 0.012, 0.04, Vector3(bx, 0.33, 0), "copper")
			box(r, Vector3(0.16, 0.1, 0.002), Vector3(0, 0.0, 0.171), "paper", Color(0.9, 0.85, 0.3))
			box(r, Vector3(0.05, 0.05, 0.005), Vector3(0, 0.0, 0.173), "metal", BLACK)
		"WINDINGS":   # a stator's coils lifted out of a generator: a ring of copper bars bound in varnished tape, on a timber cradle
			var cu := Color(0.95, 0.62, 0.38)
			var tape := Color(0.32, 0.2, 0.1)
			for s in [-1, 1]:   # the cradle: two timbers and a strap
				box(r, Vector3(0.7, 0.07, 0.1), Vector3(0, -0.18, s * 0.22), "wood", Color(0.62, 0.5, 0.36))
			ring(r, 0.34, 0.2, Vector3(0, -0.06, 0), "copper", cu, Vector3.ZERO, Vector3(1, 1.6, 1))   # the bars, edge-wound
			ring(r, 0.35, 0.33, Vector3(0, -0.06, 0), "copper", cu.darkened(0.15), Vector3.ZERO, Vector3(1, 1.7, 1))
			for k in 12:   # varnished tape round the bundle
				var a := TAU * k / 12.0
				cyl(r, 0.075, 0.05, Vector3(cos(a) * 0.27, -0.06, sin(a) * 0.27), "canvas", tape, Vector3(0, -a, PI / 2.0))
			for k in 6:   # the end turns, looping up out of it
				var a := TAU * k / 6.0 + 0.3
				var p := Vector3(cos(a) * 0.27, 0.0, sin(a) * 0.27)
				seg(r, p, p + Vector3(cos(a) * 0.06, 0.14, sin(a) * 0.06), 0.022, 0.018, "copper", cu)
				seg(r, p + Vector3(cos(a) * 0.06, 0.14, sin(a) * 0.06), p + Vector3(cos(a + 0.4) * 0.07, 0.12, sin(a + 0.4) * 0.07), 0.018, 0.018, "copper", cu)
			box(r, Vector3(0.12, 0.08, 0.004), Vector3(0.3, -0.02, 0.18), "paper", Color(0.9, 0.85, 0.3), Vector3(0, 0.7, 0))   # the Bureau's salvage tag
		"CABLE_DRUM":
			for s in [-1, 1]:
				cyl(r, 0.34, 0.05, Vector3(s * 0.22, 0, 0), "wood", Color(0.75, 0.6, 0.42), X)
				for k in 6:
					var a := TAU * k / 6.0
					cyl(r, 0.018, 0.02, Vector3(s * 0.25, cos(a) * 0.25, sin(a) * 0.25), "metal", STEEL, X)
			cyl(r, 0.24, 0.4, Vector3.ZERO, "rubber", Color.WHITE, X)
			for k in 8:
				ring(r, 0.245, 0.225, Vector3(-0.18 + k * 0.052, 0, 0), "rubber", Color(0.6, 0.6, 0.6), X)
			cyl(r, 0.06, 0.52, Vector3.ZERO, "metal", Color(0.4, 0.4, 0.4), X)
			seg(r, Vector3(0.1, 0.24, 0), Vector3(0.2, 0.3, 0.25), 0.03, 0.03, "rubber")
			cyl(r, 0.035, 0.06, Vector3(0.2, 0.3, 0.28), "copper", Color.WHITE, Vector3(PI / 2, 0, 0))
		"SAFE_BOX":
			var sg := Color(0.32, 0.36, 0.33)
			box(r, Vector3(0.5, 0.56, 0.46), Vector3(0, 0, 0), "metal", sg)
			box(r, Vector3(0.42, 0.48, 0.02), Vector3(0, 0, 0.235), "metal", sg.lightened(0.08))
			ring(r, 0.07, 0.055, Vector3(0.05, 0.03, 0.25), "metal", STEEL, Z)   # dial
			cyl(r, 0.055, 0.03, Vector3(0.05, 0.03, 0.25), "metal", Color(0.75, 0.75, 0.72), Z)
			for k in 12:
				var a := TAU * k / 12.0
				box(r, Vector3(0.004, 0.012, 0.004), Vector3(0.05 + sin(a) * 0.048, 0.03 + cos(a) * 0.048, 0.267), "metal", BLACK)
			seg(r, Vector3(-0.12, -0.04, 0.26), Vector3(-0.12, -0.04, 0.32), 0.012, 0.012, "brass")
			for k in 3:
				box(r, Vector3(0.1, 0.012, 0.012), Vector3(-0.12, -0.04 + (k - 1) * 0.0, 0.32), "brass", Color.WHITE, Vector3(0, 0, k * PI / 3))
			for s in [-1, 1]:
				box(r, Vector3(0.03, 0.1, 0.03), Vector3(-0.2, s * 0.15, 0.25), "metal", Color(0.2, 0.2, 0.2))   # hinges
			box(r, Vector3(0.14, 0.04, 0.002), Vector3(0.05, 0.18, 0.247), "brass")
			for s in [-1, 1]:
				for t in [-1, 1]:
					box(r, Vector3(0.06, 0.04, 0.06), Vector3(s * 0.2, -0.3, t * 0.18), "rubber")
		# --- newer scrap ---
		"JINGLE_BELLS":
			ring(r, 0.08, 0.068, Vector3.ZERO, "canvas", Color(0.85, 0.15, 0.12))
			for i in 6:
				var a := TAU * i / 6.0
				var p := Vector3(cos(a) * 0.074, -0.01, sin(a) * 0.074)
				ball(r, 0.026, p, "brass")
				box(r, Vector3(0.03, 0.004, 0.004), p + Vector3(0, -0.012, 0), "metal", BLACK, Vector3(0, -a, 0))
			for s in [-1, 1]:
				box(r, Vector3(0.05, 0.025, 0.012), Vector3(s * 0.025, 0.02, -0.075), "canvas", Color(0.85, 0.15, 0.12), Vector3(0, 0, s * 0.3))
		"CAR_BATTERY":
			box(r, Vector3(0.28, 0.18, 0.17), Vector3(0, -0.02, 0), "plastic", Color(0.18, 0.18, 0.19))
			box(r, Vector3(0.29, 0.03, 0.175), Vector3(0, 0.085, 0), "plastic", Color(0.22, 0.22, 0.23))
			for s in [-1, 1]:
				cyl(r, 0.016, 0.03, Vector3(s * 0.1, 0.11, 0.05), "metal", Color(0.55, 0.55, 0.55))
				cyl(r, 0.022, 0.008, Vector3(s * 0.1, 0.1, 0.05), "plastic", RED if s > 0 else BLACK)
			for i in 6:
				cyl(r, 0.01, 0.006, Vector3(-0.075 + i * 0.03, 0.102, -0.04), "plastic", Color(0.3, 0.3, 0.3))
			box(r, Vector3(0.2, 0.09, 0.002), Vector3(0, -0.01, 0.086), "paper", Color(0.85, 0.75, 0.25))
			box(r, Vector3(0.18, 0.012, 0.025), Vector3(0, 0.106, -0.0), "rubber")
		"FIRE_EXTINGUISHER":
			cyl(r, 0.06, 0.36, Vector3(0, -0.06, 0), "plastic", RED)
			ball(r, 0.06, Vector3(0, 0.12, 0), "plastic", RED, Vector3(1, 0.6, 1))
			box(r, Vector3(0.121, 0.12, 0.08), Vector3(0, -0.05, 0.0), "paper", CREAM)
			cyl(r, 0.02, 0.05, Vector3(0, 0.165, 0), "metal", STEEL)
			box(r, Vector3(0.05, 0.03, 0.03), Vector3(0, 0.2, 0), "metal", STEEL)
			box(r, Vector3(0.11, 0.012, 0.025), Vector3(0.03, 0.225, 0), "metal", STEEL, Vector3(0, 0, 0.2))
			box(r, Vector3(0.09, 0.012, 0.025), Vector3(0.025, 0.195, 0), "metal", STEEL, Vector3(0, 0, -0.1))
			cyl(r, 0.014, 0.008, Vector3(-0.025, 0.2, 0.015), "paper", Color.WHITE, Z)
			seg(r, Vector3(0.02, 0.2, 0), Vector3(0.07, 0.12, 0), 0.008, 0.008, "rubber")
			seg(r, Vector3(0.07, 0.12, 0), Vector3(0.068, -0.12, 0.0), 0.008, 0.008, "rubber")
			seg(r, Vector3(0.068, -0.12, 0), Vector3(0.068, -0.16, 0), 0.008, 0.012, "plastic", BLACK)
		"GAS_CAN":
			var rd := Color(0.8, 0.15, 0.1)
			box(r, Vector3(0.26, 0.29, 0.13), Vector3(0, -0.025, 0), "metal", rd)
			for s in [-1, 1]:
				for d in [-1, 1]:
					box(r, Vector3(0.3, 0.012, 0.004), Vector3(0, -0.03, s * 0.066), "metal", rd.darkened(0.2), Vector3(0, 0, d * 0.75))
			for x in [-0.07, 0.0, 0.07]:
				seg(r, Vector3(x, 0.12, 0), Vector3(x, 0.15, 0), 0.008, 0.008, "metal", rd)
			box(r, Vector3(0.16, 0.012, 0.03), Vector3(0, 0.155, 0), "metal", rd)
			seg(r, Vector3(0.09, 0.12, 0), Vector3(0.13, 0.16, 0), 0.02, 0.016, "metal", Color(0.5, 0.5, 0.5))
			cyl(r, 0.02, 0.015, Vector3(0.135, 0.165, 0), "plastic", BLACK, Vector3(0, 0, -0.78))
		"DESK_FAN":
			var cr := Color(0.85, 0.82, 0.7)
			cyl(r, 0.12, 0.03, Vector3(0, -0.16, 0.02), "plastic", cr, Vector3.ZERO, 0.1)
			cyl(r, 0.015, 0.15, Vector3(0, -0.07, 0.03), "metal", STEEL)
			ball(r, 0.05, Vector3(0, 0.03, 0.05), "plastic", cr, Vector3(1, 1, 1.4))
			for z in [-0.015, -0.055]:
				ring(r, 0.135, 0.127, Vector3(0, 0.03, z), "metal", STEEL, Z)
			for i in 8:
				var a := TAU * i / 8.0
				seg(r, Vector3(0, 0.03, -0.06), Vector3(cos(a) * 0.13, 0.03 + sin(a) * 0.13, -0.035), 0.0025, 0.0025, "metal", STEEL)
			for i in 3:
				var a := TAU * i / 3.0
				box(r, Vector3(0.05, 0.1, 0.004), Vector3(cos(a) * 0.055, 0.03 + sin(a) * 0.055, -0.035), "plastic", Color(0.55, 0.75, 0.9), Vector3(0.3, 0, a - PI / 2))
			ball(r, 0.018, Vector3(0, 0.03, -0.04), "plastic", cr)
		"ROTARY_PHONE":
			box(r, Vector3(0.2, 0.07, 0.17), Vector3(0, -0.04, 0), "plastic", BLACK)
			box(r, Vector3(0.17, 0.05, 0.13), Vector3(0, 0.01, 0.0), "plastic", BLACK, Vector3(-0.25, 0, 0))
			cyl(r, 0.055, 0.012, Vector3(0, 0.03, 0.05), "plastic", CREAM, Vector3(-0.45, 0, 0))
			for i in 9:
				var a := TAU * i / 12.0 + 0.6
				cyl(r, 0.008, 0.014, Vector3(cos(a) * 0.038, 0.032 + sin(a) * 0.038 * 0.4, 0.05 + sin(a) * 0.038 * 0.9), "plastic", BLACK, Vector3(-0.45, 0, 0))
			seg(r, Vector3(-0.08, 0.055, -0.04), Vector3(0.08, 0.055, -0.04), 0.017, 0.017, "plastic", BLACK)
			for s in [-1, 1]:
				box(r, Vector3(0.045, 0.03, 0.06), Vector3(s * 0.09, 0.045, -0.04), "plastic", BLACK)
			for i in 5:
				ring(r, 0.012, 0.008, Vector3(0.11 + i * 0.006, -0.03, -0.04), "rubber", Color.WHITE, X)
		"TYPEWRITER":
			var gr := Color(0.4, 0.45, 0.4)
			box(r, Vector3(0.38, 0.08, 0.24), Vector3(0, -0.05, 0.02), "metal", gr)
			box(r, Vector3(0.36, 0.05, 0.12), Vector3(0, -0.02, 0.07), "metal", gr, Vector3(0.35, 0, 0))
			for row in 3:
				for i in 9:
					cyl(r, 0.011, 0.012, Vector3(-0.12 + i * 0.03 + row * 0.008, -0.003 + row * 0.018, 0.12 - row * 0.03), "plastic", CREAM)
			cyl(r, 0.026, 0.36, Vector3(0, 0.03, -0.08), "rubber", Color.WHITE, X)
			for s in [-1, 1]:
				cyl(r, 0.03, 0.01, Vector3(s * 0.185, 0.03, -0.08), "metal", BLACK, X)
				cyl(r, 0.025, 0.012, Vector3(s * 0.09, 0.0, -0.03), "plastic", BLACK)
			box(r, Vector3(0.2, 0.13, 0.002), Vector3(0, 0.1, -0.09), "paper", CREAM, Vector3(-0.2, 0, 0))
			seg(r, Vector3(-0.19, 0.03, -0.08), Vector3(-0.21, 0.06, -0.02), 0.005, 0.005, "metal", STEEL)
		"RADIO":
			box(r, Vector3(0.33, 0.2, 0.11), Vector3.ZERO, "wood", Color(0.55, 0.4, 0.3))
			box(r, Vector3(0.15, 0.14, 0.005), Vector3(-0.07, 0, 0.056), "grille")
			box(r, Vector3(0.15, 0.14, 0.004), Vector3(-0.07, 0, 0.053), "canvas", Color(0.5, 0.42, 0.3))
			box(r, Vector3(0.12, 0.05, 0.004), Vector3(0.08, 0.045, 0.056), "paper", CREAM)
			box(r, Vector3(0.003, 0.045, 0.002), Vector3(0.07, 0.045, 0.059), "metal", RED)
			for x in [0.05, 0.11]:
				cyl(r, 0.018, 0.02, Vector3(x, -0.04, 0.06), "plastic", Color(0.2, 0.15, 0.1), Z)
			seg(r, Vector3(0.14, 0.1, -0.02), Vector3(0.2, 0.24, -0.05), 0.003, 0.002, "metal", STEEL)
			ring(r, 0.07, 0.06, Vector3(0, 0.1, 0), "leather", Color.WHITE, Z, Vector3(1, 0.5, 1))
		"TOOLBOX":
			var rd := Color(0.78, 0.14, 0.08)
			box(r, Vector3(0.43, 0.12, 0.19), Vector3(0, -0.035, 0), "metal", rd)
			box(r, Vector3(0.44, 0.05, 0.2), Vector3(0, 0.05, 0), "metal", rd.darkened(0.1))
			for x in [-0.08, 0.08]:
				seg(r, Vector3(x, 0.075, 0), Vector3(x, 0.095, 0), 0.006, 0.006, "metal", STEEL)
			seg(r, Vector3(-0.09, 0.095, 0), Vector3(0.09, 0.095, 0), 0.01, 0.01, "plastic", BLACK)
			for x in [-0.17, 0.17]:
				box(r, Vector3(0.03, 0.04, 0.01), Vector3(x, 0.03, 0.1), "metal", STEEL)
		"WRENCH":
			box(r, Vector3(0.024, 0.008, 0.2), Vector3.ZERO, "metal", STEEL)
			ring(r, 0.028, 0.013, Vector3(0, 0, -0.12), "metal", STEEL)
			box(r, Vector3(0.02, 0.009, 0.03), Vector3(0, 0, -0.14), "rust", Color(0.2, 0.2, 0.2))
			ring(r, 0.022, 0.012, Vector3(0, 0, 0.12), "metal", STEEL)
		"CROWBAR":   # red gooseneck bar, paint worn back to steel where hands go
			var rd := Color(0.7, 0.12, 0.1)
			seg(r, Vector3(0, 0, -0.3), Vector3(0, 0, 0.25), 0.0125, 0.0125, "paint", rd)
			for z in [-0.12, -0.05, 0.02]:
				seg(r, Vector3(0, 0, z), Vector3(0, 0, z + 0.05), 0.0128, 0.0128, "metal", Color(0.55, 0.55, 0.57))
			var hook := [Vector3(0, 0, 0.25), Vector3(0, 0.01, 0.29), Vector3(0, 0.032, 0.315), Vector3(0, 0.06, 0.325), Vector3(0, 0.08, 0.31)]
			for i in hook.size() - 1:
				seg(r, hook[i], hook[i + 1], 0.0125, 0.0125 if i < 2 else 0.01, "paint", rd)
			for x in [-0.006, 0.006]:   # split claw
				box(r, Vector3(0.007, 0.006, 0.03), Vector3(x, 0.086, 0.29), "metal", Color(0.5, 0.5, 0.52), Vector3(0.5, 0, 0))
			box(r, Vector3(0.024, 0.007, 0.045), Vector3(0, -0.004, -0.315), "metal", Color(0.55, 0.55, 0.57), Vector3(-0.12, 0, 0))   # chisel end
			seg(r, Vector3(0, 0, -0.27), Vector3(0, 0, -0.13), 0.0168, 0.0168, "rubber")          # dipped grip
			ring(r, 0.018, 0.0155, Vector3(0, 0, -0.13), "rubber", Color.WHITE, Z)
		"LIGHT_BULB":
			ball(r, 0.038, Vector3(0, 0.025, 0), "glass")
			seg(r, Vector3(0, -0.01, 0), Vector3(0, 0.025, 0), 0.002, 0.002, "glow", Color(1, 0.7, 0.4))
			cyl(r, 0.016, 0.025, Vector3(0, -0.018, 0), "glass", Color.WHITE, Vector3.ZERO, 0.026)
			cyl(r, 0.016, 0.03, Vector3(0, -0.044, 0), "brass")
			for i in 3:
				ring(r, 0.0175, 0.014, Vector3(0, -0.053 + i * 0.009, 0), "brass")
			ball(r, 0.007, Vector3(0, -0.06, 0), "metal", BLACK)
		"GEAR":
			cyl(r, 0.11, 0.035, Vector3.ZERO, "metal", Color(0.55, 0.55, 0.57))
			for i in 16:
				var a := TAU * i / 16.0
				box(r, Vector3(0.032, 0.035, 0.028), Vector3(cos(a) * 0.12, 0, sin(a) * 0.12), "metal", Color(0.55, 0.55, 0.57), Vector3(0, -a, 0))
			cyl(r, 0.035, 0.055, Vector3.ZERO, "metal", STEEL)
			cyl(r, 0.015, 0.057, Vector3.ZERO, "rubber")
			for i in 4:
				var a := TAU * i / 4.0 + 0.4
				cyl(r, 0.022, 0.037, Vector3(cos(a) * 0.068, 0, sin(a) * 0.068), "rubber")
		"VALVE_WHEEL":
			ring(r, 0.135, 0.11, Vector3(0, 0.02, 0), "metal", RED)
			for i in 3:
				var a := TAU * i / 3.0
				seg(r, Vector3(0, 0.02, 0), Vector3(cos(a) * 0.12, 0.02, sin(a) * 0.12), 0.01, 0.01, "metal", RED)
			cyl(r, 0.03, 0.04, Vector3(0, 0.02, 0), "metal", STEEL)
			cyl(r, 0.012, 0.06, Vector3(0, -0.015, 0), "metal", STEEL)
		"PADLOCK":
			box(r, Vector3(0.08, 0.07, 0.035), Vector3(0, -0.025, 0), "brass")
			ring(r, 0.03, 0.021, Vector3(0, 0.025, 0), "metal", STEEL, Z)
			box(r, Vector3(0.008, 0.02, 0.002), Vector3(0, -0.03, 0.018), "metal", BLACK)
		"CHAIN":
			for i in 7:
				var link := ring(r, 0.028, 0.019, Vector3(-0.15 + i * 0.05, 0, 0), "metal", Color(0.6, 0.6, 0.6), Z if i % 2 == 0 else Vector3.ZERO)
				link.scale = Vector3(1.5, 1, 1)
		"TEAPOT":
			var c := Color(0.7, 0.72, 0.75)
			ball(r, 0.08, Vector3(0, -0.02, 0), "metal", c, Vector3(1, 0.85, 1))
			cyl(r, 0.045, 0.015, Vector3(0, 0.055, 0), "metal", c)
			ball(r, 0.015, Vector3(0, 0.07, 0), "plastic", BLACK)
			seg(r, Vector3(0.06, -0.03, 0), Vector3(0.12, 0.05, 0), 0.018, 0.008, "metal", c)
			ring(r, 0.045, 0.036, Vector3(-0.085, 0, 0), "plastic", BLACK, Z)
			ring(r, 0.06, 0.05, Vector3(0, -0.085, 0), "metal", c)
		"COFFEE_MUG":
			var mc: Color = [Color(0.95, 0.93, 0.88), Color(0.3, 0.5, 0.8), Color(0.8, 0.3, 0.25)][rng.randi() % 3]
			cyl(r, 0.04, 0.09, Vector3.ZERO, "plastic", mc)
			ring(r, 0.026, 0.017, Vector3(0.045, 0, 0), "plastic", mc, Z)
			cyl(r, 0.036, 0.002, Vector3(0, 0.035, 0), "rust", Color(0.4, 0.3, 0.25))
			cyl(r, 0.0405, 0.012, Vector3(0, -0.01, 0), "paper", Color(0.3, 0.3, 0.3))
		"THERMOS":
			var tc := Color(0.35, 0.55, 0.4)
			cyl(r, 0.04, 0.22, Vector3(0, -0.04, 0), "metal", tc)
			for y in [-0.14, 0.06]:
				ring(r, 0.042, 0.037, Vector3(0, y, 0), "metal", STEEL)
			cyl(r, 0.044, 0.06, Vector3(0, 0.098, 0), "plastic", Color(0.2, 0.2, 0.2), Vector3.ZERO, 0.046)
			box(r, Vector3(0.015, 0.12, 0.02), Vector3(0.048, -0.04, 0), "plastic", Color(0.2, 0.2, 0.2))
		"HELIUM_TANK":   # a party balloon tank: a fat pink cylinder, a domed top, a brass valve and a nozzle
			var pk := Color(0.95, 0.45, 0.65)
			cyl(r, 0.1, 0.32, Vector3(0, -0.04, 0), "plastic", pk)
			ball(r, 0.1, Vector3(0, 0.12, 0), "plastic", pk, Vector3(1, 0.55, 1), true)
			cyl(r, 0.022, 0.07, Vector3(0, 0.2, 0), "brass", Color(0.85, 0.7, 0.35))
			cyl(r, 0.035, 0.012, Vector3(0, 0.22, 0), "brass", Color(0.85, 0.7, 0.35))
			cyl(r, 0.01, 0.07, Vector3(0, 0.205, -0.04), "plastic", Color(0.95, 0.95, 0.95), Vector3(PI / 2.0, 0, 0))
			for k in 3:   # balloons printed round it
				var a := TAU * k / 3.0
				ball(r, 0.03, Vector3(cos(a) * 0.098, 0.0, sin(a) * 0.098), "plastic", [Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.2), Color(0.4, 0.9, 0.4)][k], Vector3(0.25, 1.1, 0.9))
		"SF6_BOTTLE":   # a lab gas bottle: grey-green, a yellow shoulder band, a valve with a guard
			var gr := Color(0.45, 0.55, 0.45)
			cyl(r, 0.07, 0.3, Vector3(0, -0.04, 0), "metal", gr)
			ball(r, 0.07, Vector3(0, 0.11, 0), "metal", gr, Vector3(1, 0.6, 1), true)
			cyl(r, 0.072, 0.04, Vector3(0, 0.07, 0), "metal", Color(0.95, 0.8, 0.15))
			cyl(r, 0.018, 0.06, Vector3(0, 0.17, 0), "brass", Color(0.8, 0.65, 0.35))
			ring(r, 0.045, 0.036, Vector3(0, 0.19, 0), "metal", Color(0.3, 0.3, 0.3))
		"WHOOPEE_CUSHION":   # a flat pink rubber bladder with a frilled neck to blow it up by
			var pk := Color(0.92, 0.38, 0.52)
			ball(r, 0.13, Vector3(0, 0, 0.02), "plastic", pk, Vector3(1.0, 0.2, 1.0))
			cyl(r, 0.03, 0.06, Vector3(0, 0, -0.13), "plastic", pk, Vector3(PI / 2.0, 0, 0))
			ring(r, 0.036, 0.024, Vector3(0, 0, -0.165), "plastic", pk.darkened(0.15), Z)
		"RUBBER_DUCK":
			var yl := Color(1, 0.85, 0.15)
			ball(r, 0.05, Vector3(0, -0.025, 0.01), "plastic", yl, Vector3(1, 0.8, 1.2))
			ball(r, 0.033, Vector3(0, 0.035, -0.025), "plastic", yl)
			box(r, Vector3(0.03, 0.012, 0.03), Vector3(0, 0.03, -0.062), "plastic", Color(1, 0.5, 0.1))
			for s in [-1, 1]:
				ball(r, 0.006, Vector3(s * 0.017, 0.045, -0.052), "plastic", BLACK)
				ball(r, 0.025, Vector3(s * 0.04, -0.02, 0.015), "plastic", yl, Vector3(0.4, 0.7, 1))
			cyl(r, 0.02, 0.03, Vector3(0, 0.0, 0.065), "plastic", yl, Vector3(-0.8, 0, 0), 0.004)
		"GAS_MASK":
			var mk := Color(0.24, 0.27, 0.22)
			ball(r, 0.08, Vector3(0, 0.01, 0.0), "rubber", mk, Vector3(1.0, 1.15, 0.62))   # the face-piece
			ball(r, 0.05, Vector3(0, -0.045, -0.03), "rubber", mk, Vector3(1.0, 0.8, 0.9))   # the snout
			for s in [-1, 1]:
				ring(r, 0.03, 0.021, Vector3(s * 0.036, 0.035, -0.046), "metal", Color(0.35, 0.36, 0.34), Z)
				cyl(r, 0.022, 0.006, Vector3(s * 0.036, 0.035, -0.046), "glass", Color(0.7, 0.8, 0.75), Z)
			cyl(r, 0.034, 0.055, Vector3(0, -0.075, -0.075), "metal", Color(0.5, 0.52, 0.42), Vector3(PI / 2 + 0.5, 0, 0))   # the filter
			for k in 3:
				ring(r, 0.036, 0.032, Vector3(0, -0.07 - k * 0.006, -0.063 - k * 0.01), "metal", Color(0.35, 0.36, 0.3), Vector3(PI / 2 + 0.5, 0, 0))
			cyl(r, 0.024, 0.006, Vector3(0, -0.091, -0.1), "metal", Color(0.2, 0.2, 0.2), Vector3(PI / 2 + 0.5, 0, 0))
			ring(r, 0.083, 0.074, Vector3(0, 0.03, 0.012), "rubber", Color(0.12, 0.12, 0.12), Vector3(0.25, 0, 0))   # the head strap
		"HARD_HAT":
			var hy := Color(1, 0.8, 0.1)
			ball(r, 0.11, Vector3(0, -0.05, 0.0), "plastic", hy, Vector3(1, 0.85, 1.15), true)
			cyl(r, 0.13, 0.01, Vector3(0, -0.05, -0.01), "plastic", hy).scale = Vector3(1, 1, 1.15)
			box(r, Vector3(0.025, 0.02, 0.12), Vector3(0, 0.037, 0), "plastic", hy)
			box(r, Vector3(0.05, 0.04, 0.003), Vector3(0, 0.0, -0.11), "paper", Color(0.9, 0.9, 0.85), Vector3(0.6, 0, 0))
		"GARDEN_HOSE":
			for i in 4:
				ring(r, 0.17 - i * 0.005, 0.148 - i * 0.005, Vector3(0, -0.04 + i * 0.026, 0), "plastic", Color(0.25, 0.6, 0.25), Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08)))
			seg(r, Vector3(0.16, 0.04, 0), Vector3(0.2, 0.05, 0.08), 0.011, 0.011, "plastic", Color(0.25, 0.6, 0.25))
			cyl(r, 0.014, 0.05, Vector3(0.2, 0.05, 0.1), "brass", Color.WHITE, Vector3(PI / 2, 0, 0), 0.008)
		"BICYCLE_WHEEL":
			ring(r, 0.285, 0.258, Vector3.ZERO, "rubber", Color.WHITE, Z)
			ring(r, 0.26, 0.245, Vector3.ZERO, "metal", STEEL, Z)
			cyl(r, 0.022, 0.06, Vector3.ZERO, "metal", STEEL, Z)
			for i in 16:
				var a := TAU * i / 16.0
				var side := 0.02 if i % 2 == 0 else -0.02
				seg(r, Vector3(0, 0, side), Vector3(cos(a) * 0.248, sin(a) * 0.248, 0), 0.0015, 0.0015, "metal", STEEL)
			cyl(r, 0.004, 0.03, Vector3(0, -0.24, 0), "metal", STEEL)
		"CIRCUIT_BOARD":
			box(r, Vector3(0.24, 0.006, 0.17), Vector3.ZERO, "pcb")
			box(r, Vector3(0.06, 0.008, 0.06), Vector3(-0.05, 0.007, 0.02), "plastic", BLACK)
			box(r, Vector3(0.04, 0.007, 0.02), Vector3(0.06, 0.006, -0.04), "plastic", BLACK)
			box(r, Vector3(0.04, 0.007, 0.02), Vector3(0.06, 0.006, 0.0), "plastic", BLACK)
			for i in 4:
				cyl(r, 0.008, 0.018, Vector3(0.03 + i * 0.02, 0.012, 0.055), "plastic", Color(0.2, 0.3, 0.7))
			box(r, Vector3(0.02, 0.012, 0.09), Vector3(-0.11, 0.009, 0), "plastic", Color(0.85, 0.85, 0.8))
			box(r, Vector3(0.05, 0.007, 0.05), Vector3(-0.05, 0.012, 0.02), "metal", STEEL)
		"KEYBOARD":
			box(r, Vector3(0.44, 0.022, 0.15), Vector3(0, -0.008, 0), "plastic", Color(0.85, 0.82, 0.72))
			box(r, Vector3(0.42, 0.006, 0.12), Vector3(0, 0.005, 0.008), "plastic", Color(0.3, 0.3, 0.3))
			for row in 4:
				for col in 14:
					box(r, Vector3(0.024, 0.012, 0.022), Vector3(-0.195 + col * 0.03 + row * 0.005, 0.012, -0.04 + row * 0.026), "plastic", Color(0.9, 0.88, 0.8) if (col + row) % 7 != 0 else Color(0.7, 0.68, 0.62))
			box(r, Vector3(0.15, 0.012, 0.022), Vector3(0, 0.012, 0.064), "plastic", Color(0.9, 0.88, 0.8))   # space bar
			seg(r, Vector3(0, 0, -0.075), Vector3(0.03, -0.01, -0.12), 0.005, 0.005, "plastic", Color(0.7, 0.7, 0.65))
		"VHS_TAPE":
			box(r, Vector3(0.188, 0.025, 0.1), Vector3.ZERO, "plastic", BLACK)
			box(r, Vector3(0.12, 0.0255, 0.06), Vector3(0, 0, 0.0), "paper", CREAM)
			box(r, Vector3(0.07, 0.026, 0.022), Vector3(0, 0, -0.025), "glass")
			for s in [-1, 1]:
				cyl(r, 0.02, 0.026, Vector3(s * 0.045, 0, -0.005), "plastic", Color(0.9, 0.9, 0.9))
		"BUCKET":
			var bc := Color(0.6, 0.62, 0.62)
			cyl(r, 0.115, 0.26, Vector3(0, -0.015, 0), "metal", bc, Vector3.ZERO, 0.135)
			cyl(r, 0.13, 0.004, Vector3(0, 0.112, 0), "rust", Color(0.3, 0.25, 0.2))
			for y in [0.11, -0.02]:
				ring(r, 0.14 if y > 0 else 0.128, 0.13 if y > 0 else 0.12, Vector3(0, y, 0), "metal", bc)
			ring(r, 0.14, 0.134, Vector3(0, 0.11, 0), "metal", STEEL, Z)
		"TIN_ROBOT":
			var rc := Color(0.75, 0.25, 0.2)
			box(r, Vector3(0.08, 0.09, 0.06), Vector3(0, -0.01, 0), "metal", rc)
			box(r, Vector3(0.06, 0.05, 0.05), Vector3(0, 0.065, 0), "metal", STEEL)
			for s in [-1, 1]:
				ball(r, 0.009, Vector3(s * 0.015, 0.07, -0.026), "glow", Color(1, 0.85, 0.3))
				seg(r, Vector3(s * 0.045, 0.02, 0), Vector3(s * 0.055, -0.04, -0.02), 0.009, 0.009, "metal", STEEL)
				box(r, Vector3(0.025, 0.06, 0.03), Vector3(s * 0.02, -0.085, 0), "metal", STEEL)
			seg(r, Vector3(0, 0.09, 0), Vector3(0, 0.115, 0), 0.003, 0.003, "metal", STEEL)
			ball(r, 0.008, Vector3(0, 0.118, 0), "plastic", RED)
			cyl(r, 0.015, 0.005, Vector3(0, 0.0, -0.031), "brass", Color.WHITE, Z)
			seg(r, Vector3(0, 0, 0.03), Vector3(0, 0, 0.05), 0.003, 0.003, "brass")
			ring(r, 0.014, 0.008, Vector3(0, 0, 0.055), "brass", Color.WHITE, X)
		"MOTOR":
			var mc := Color(0.35, 0.42, 0.55)
			cyl(r, 0.075, 0.16, Vector3.ZERO, "metal", mc, X)
			for i in 7:
				ring(r, 0.083, 0.07, Vector3(-0.065 + i * 0.022, 0, 0), "metal", mc, X)
			for s in [-1, 1]:
				cyl(r, 0.068, 0.02, Vector3(s * 0.09, 0, 0), "metal", STEEL, X)
			cyl(r, 0.05, 0.01, Vector3(-0.1, 0, 0), "copper", Color.WHITE, X)
			seg(r, Vector3(0.1, 0, 0), Vector3(0.125, 0, 0), 0.01, 0.01, "metal", STEEL)
			box(r, Vector3(0.12, 0.02, 0.17), Vector3(0, -0.085, 0), "metal", mc.darkened(0.2))
			box(r, Vector3(0.05, 0.035, 0.05), Vector3(0, 0.085, 0), "metal", mc)
		"TRUMPET":
			seg(r, Vector3(0.17, 0, 0), Vector3(-0.12, 0, 0), 0.008, 0.008, "brass")
			seg(r, Vector3(-0.12, 0, 0), Vector3(-0.22, 0, 0), 0.009, 0.058, "brass")
			seg(r, Vector3(0.1, -0.045, 0), Vector3(-0.08, -0.045, 0), 0.008, 0.008, "brass")
			seg(r, Vector3(-0.08, -0.045, 0), Vector3(-0.1, 0, 0), 0.008, 0.008, "brass")
			seg(r, Vector3(0.1, -0.045, 0), Vector3(0.13, 0, 0), 0.008, 0.008, "brass")
			for i in 3:
				cyl(r, 0.011, 0.065, Vector3(0.0 + i * 0.026, -0.02, 0), "brass")
				cyl(r, 0.013, 0.012, Vector3(0.0 + i * 0.026, 0.02, 0), "metal", CREAM)
			seg(r, Vector3(0.17, 0, 0), Vector3(0.21, 0, 0), 0.006, 0.012, "metal", STEEL)
		"BABY_DOLL":
			var sk := Color(0.95, 0.8, 0.72)
			ball(r, 0.05, Vector3(0, 0.11, 0), "plastic", sk)
			ball(r, 0.052, Vector3(0, 0.125, 0.008), "canvas", Color(0.55, 0.4, 0.25), Vector3(1, 0.7, 1), true)
			ball(r, 0.008, Vector3(-0.018, 0.115, -0.045), "plastic", Color(0.1, 0.15, 0.3))
			ball(r, 0.008, Vector3(0.018, 0.115, -0.045), "plastic", BLACK)   # one eye stuck shut
			box(r, Vector3(0.085, 0.11, 0.055), Vector3(0, 0.01, 0), "canvas", Color(0.9, 0.55, 0.6))
			for s in [-1, 1]:
				seg(r, Vector3(s * 0.05, 0.05, 0), Vector3(s * 0.07, -0.01, -0.02), 0.014, 0.012, "plastic", sk)
				seg(r, Vector3(s * 0.022, -0.045, 0), Vector3(s * 0.025, -0.15, -0.01), 0.016, 0.014, "plastic", sk)
		"GARDEN_GNOME":
			cyl(r, 0.06, 0.02, Vector3(0, -0.14, 0), "plastic", Color(0.3, 0.5, 0.25))
			cyl(r, 0.06, 0.12, Vector3(0, -0.07, 0), "plastic", Color(0.25, 0.4, 0.75), Vector3.ZERO, 0.045)
			ring(r, 0.05, 0.043, Vector3(0, -0.06, 0), "leather")
			ball(r, 0.035, Vector3(0, 0.025, 0), "plastic", Color(0.95, 0.78, 0.68))
			ball(r, 0.032, Vector3(0, -0.005, -0.02), "plastic", Color(0.95, 0.95, 0.92), Vector3(1, 1.3, 0.6))
			ball(r, 0.01, Vector3(0, 0.025, -0.035), "plastic", Color(0.95, 0.6, 0.55))
			cyl(r, 0.04, 0.11, Vector3(0, 0.095, 0.005), "plastic", RED, Vector3(0.15, 0, 0), 0.003)
		"INNER_TUBE":
			ring(r, 0.21, 0.1, Vector3.ZERO, "rubber")
			cyl(r, 0.006, 0.04, Vector3(0, 0.0, -0.1), "metal", STEEL, Z)
			for i in 2:
				var a := rng.randf() * TAU
				box(r, Vector3(0.05, 0.002, 0.04), Vector3(cos(a) * 0.16, 0.054, sin(a) * 0.16), "rubber", Color(0.6, 0.6, 0.6), Vector3(0, a, 0))
		"HOT_WATER_BOTTLE":
			var rb := Color(0.72, 0.17, 0.13)
			ball(r, 0.11, Vector3(0, -0.03, 0), "plastic", rb, Vector3(0.78, 1.0, 0.22))   # a soft rubber pillow
			for i in 5:   # moulded ribs across one face
				box(r, Vector3(0.12 - absf(i - 2) * 0.012, 0.007, 0.006), Vector3(0, -0.09 + i * 0.03, -0.022), "plastic", rb.darkened(0.25))
			cyl(r, 0.018, 0.05, Vector3(0, 0.085, 0), "plastic", rb, Vector3.ZERO, 0.022)   # the neck
			cyl(r, 0.024, 0.025, Vector3(0, 0.12, 0), "plastic", Color(0.9, 0.9, 0.85))   # stopper
			ring(r, 0.012, 0.006, Vector3(0, 0.14, 0), "plastic", Color(0.9, 0.9, 0.85), Z)
		"SPRAY_CAN":
			var sc: Color = [Color(0.85, 0.2, 0.15), Color(0.2, 0.6, 0.3), Color(0.95, 0.85, 0.2), Color(0.2, 0.3, 0.75)][rng.randi() % 4]
			cyl(r, 0.032, 0.15, Vector3(0, -0.02, 0), "metal", sc)
			cyl(r, 0.032, 0.015, Vector3(0, 0.063, 0), "metal", STEEL, Vector3.ZERO, 0.02)
			cyl(r, 0.012, 0.012, Vector3(0, 0.076, 0), "plastic", Color(0.9, 0.9, 0.9))
			box(r, Vector3(0.006, 0.006, 0.01), Vector3(0, 0.08, -0.01), "plastic", BLACK)
			ring(r, 0.033, 0.028, Vector3(0, -0.094, 0), "metal", STEEL)
		"FIRE_AXE":   # ash haft, red head, ground steel edge, back spike
			seg(r, Vector3(0, -0.02, -0.44), Vector3(0, 0, 0.37), 0.017, 0.015, "wood", Color(0.85, 0.65, 0.42))
			seg(r, Vector3(0, -0.02, -0.44), Vector3(0, -0.02, -0.32), 0.0185, 0.0185, "rubber")   # grip
			ring(r, 0.021, 0.015, Vector3(0, -0.02, -0.445), "rubber", Color.WHITE, Z)
			box(r, Vector3(0.032, 0.09, 0.07), Vector3(0, 0.0, 0.38), "paint", RED)                # eye of the head
			box(r, Vector3(0.014, 0.12, 0.1), Vector3(0, 0.09, 0.39), "paint", RED, Vector3(-0.1, 0, 0))   # cheek to the blade
			box(r, Vector3(0.008, 0.14, 0.018), Vector3(0, 0.12, 0.44), "metal", STEEL, Vector3(-0.15, 0, 0))   # edge
			seg(r, Vector3(0, -0.04, 0.38), Vector3(0, -0.13, 0.36), 0.016, 0.003, "paint", RED)   # spike
			box(r, Vector3(0.034, 0.025, 0.04), Vector3(0, 0.02, 0.33), "metal", Color(0.3, 0.3, 0.3))   # wedge collar
		"SHOTGUN":   # side-by-side coach gun: blued barrels, case-hardened action, oiled walnut, a shell cuff
			var blue := Color(0.2, 0.21, 0.24)
			var walnut := Color(0.66, 0.42, 0.27)
			var action := Color(0.62, 0.6, 0.56)
			for x in [-0.0108, 0.0108]:
				seg(r, Vector3(x, 0.035, 0.07), Vector3(x, 0.035, 0.52), 0.0108, 0.0098, "metal", blue)
				cyl(r, 0.0072, 0.006, Vector3(x, 0.035, 0.5205), "rubber", Color(0.25, 0.25, 0.25), Z)   # bore
			box(r, Vector3(0.007, 0.006, 0.45), Vector3(0, 0.0475, 0.295), "metal", blue)          # top rib
			box(r, Vector3(0.012, 0.009, 0.42), Vector3(0, 0.026, 0.3), "metal", blue)             # under rib
			ball(r, 0.0028, Vector3(0, 0.0525, 0.512), "brass")                                    # bead
			box(r, Vector3(0.046, 0.034, 0.05), Vector3(0, 0.032, 0.085), "metal", blue.lightened(0.08))   # monoblock
			box(r, Vector3(0.002, 0.0035, 0.42), Vector3(0, 0.048, 0.3), "metal", blue.lightened(0.15))    # rib file line
			# Splinter forend with checkering and its latch.
			slab(r, PackedVector2Array([Vector2(0.1, 0.03), Vector2(0.29, 0.03), Vector2(0.3, 0.02), Vector2(0.285, 0.006),
				Vector2(0.14, 0.0), Vector2(0.105, 0.008)]), 0.04, Vector3.ZERO, "wood", walnut)
			box(r, Vector3(0.0415, 0.016, 0.1), Vector3(0, 0.015, 0.19), "knurl", walnut.darkened(0.3))
			box(r, Vector3(0.012, 0.008, 0.02), Vector3(0, 0.004, 0.27), "metal", action)
			# Action: profile, side plates, hinge pin, top lever, safety, triggers, guard.
			slab(r, PackedVector2Array([Vector2(-0.095, 0.052), Vector2(0.06, 0.052), Vector2(0.06, 0.014), Vector2(0.025, -0.004),
				Vector2(-0.07, -0.012), Vector2(-0.095, 0.004)]), 0.046, Vector3.ZERO, "metal", action)
			for x in [-0.0235, 0.0235]:
				box(r, Vector3(0.002, 0.032, 0.07), Vector3(x, 0.022, -0.035), "brass", Color(0.75, 0.72, 0.66))   # engraved plates
			cyl(r, 0.008, 0.048, Vector3(0, 0.012, 0.06), "metal", blue, X)
			box(r, Vector3(0.01, 0.006, 0.05), Vector3(0.008, 0.056, -0.072), "metal", blue, Vector3(0, 0.35, 0))
			ball(r, 0.006, Vector3(0.017, 0.058, -0.094), "metal", blue)
			box(r, Vector3(0.008, 0.005, 0.016), Vector3(0, 0.056, -0.11), "metal", action)
			for z in [-0.03, -0.048]:
				box(r, Vector3(0.004, 0.024, 0.005), Vector3(0, -0.018, z), "metal", blue, Vector3(-0.35, 0, 0))
			ring(r, 0.027, 0.022, Vector3(0, -0.016, -0.04), "metal", blue, X, Vector3(1, 1, 1.35))
			# Stock: a round wrist into a pistol grip (what the hand closes on), then comb, drop and butt.
			seg(r, Vector3(0, 0.03, -0.09), Vector3(0, 0.022, -0.2), 0.02, 0.021, "wood", walnut)         # wrist
			var pg_top := Vector3(0, 0.005, -0.112)
			var pg_end := Vector3(0, -0.085, -0.172)
			seg(r, pg_top, pg_end, 0.0185, 0.02, "wood", walnut)                                           # pistol grip
			cyl(r, 0.021, 0.008, pg_end + (pg_end - pg_top).normalized() * 0.004, "metal", blue, Vector3(0.585, 0, 0))   # grip cap
			seg(r, pg_top + (pg_end - pg_top) * 0.3, pg_top + (pg_end - pg_top) * 0.75, 0.0192, 0.0198, "knurl", walnut.darkened(0.35))   # checkering
			slab(r, PackedVector2Array([Vector2(-0.18, 0.032), Vector2(-0.25, 0.034), Vector2(-0.47, 0.02),
				Vector2(-0.49, 0.018), Vector2(-0.49, -0.118), Vector2(-0.45, -0.118), Vector2(-0.25, -0.064), Vector2(-0.19, -0.05),
				Vector2(-0.17, -0.02)]), 0.042, Vector3.ZERO, "wood", walnut)
			slab(r, PackedVector2Array([Vector2(-0.3, 0.031), Vector2(-0.47, 0.02), Vector2(-0.49, 0.018), Vector2(-0.49, -0.118),
				Vector2(-0.45, -0.118), Vector2(-0.3, -0.077)]), 0.047, Vector3.ZERO, "wood", walnut.darkened(0.05))   # butt swells
			box(r, Vector3(0.05, 0.14, 0.016), Vector3(0, -0.049, -0.498), "rubber", Color.WHITE)
			box(r, Vector3(0.051, 0.141, 0.003), Vector3(0, -0.049, -0.4895), "cream", Color(0.92, 0.9, 0.85))
			# Leather shell cuff on the right of the butt, four shells.
			box(r, Vector3(0.008, 0.07, 0.11), Vector3(0.0275, -0.04, -0.37), "leather")
			for k in 4:
				cyl(r, 0.0092, 0.05, Vector3(0.037, -0.04, -0.41 + k * 0.026), "plastic", Color(0.7, 0.12, 0.08))
				cyl(r, 0.0095, 0.012, Vector3(0.037, -0.07, -0.41 + k * 0.026), "brass")
			ring(r, 0.009, 0.006, Vector3(0, -0.105, -0.42), "metal", blue, X)                       # sling swivels
			ring(r, 0.009, 0.006, Vector3(0, 0.016, 0.42), "metal", blue, X)
		"PHOTO":   # a glossy print: the picture runs nearly to the edge, rounded corners, one dog-eared
			var hw := 0.096
			var hh := 0.081
			var outline := PackedVector2Array()   # in (z, x), corners rounded, top-right folded over
			var corners := [Vector2(-hh, hw), Vector2(hh, hw), Vector2(hh, -hw), Vector2(-hh, -hw)]
			for c in 4:
				var ctr: Vector2 = corners[c] - Vector2(signf(corners[c].x), signf(corners[c].y)) * 0.006
				if c == 0:   # the dog-ear: a straight cut across the corner
					outline.append(Vector2(-hh, hw - 0.026))
					outline.append(Vector2(-hh + 0.026, hw))
					continue
				var a0 := atan2(corners[c].y - ctr.y, corners[c].x - ctr.x)
				for k in 4:
					var ang := a0 + PI / 4.0 - k * PI / 6.0   # (the outline runs clockwise)
					outline.append(ctr + Vector2(cos(ang), sin(ang)) * 0.006)
			var card := Color(0.94, 0.93, 0.89)
			slab(r, outline, 0.0016, Vector3.ZERO, "cream", card, Vector3(0, 0, -PI / 2.0))
			var flap := slab(r, PackedVector2Array([Vector2(-hh, hw - 0.026), Vector2(-hh + 0.026, hw), Vector2(-hh, hw)]), 0.0016,
				Vector3(0, 0.0, 0), "cream", card.darkened(0.08), Vector3(0, 0, -PI / 2.0))
			flap.position.y = 0.0019   # folded over onto the front: the paper back shows, the picture's corner is hidden
			var pic := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(hw * 2.0 - 0.006, hh * 2.0 - 0.006)
			pic.mesh = qm
			var pm := StandardMaterial3D.new()
			pm.albedo_color = Color(0.12, 0.11, 0.1)
			pm.roughness = 0.12
			pic.material_override = pm
			pic.name = "Pic"
			pic.set_meta("live", true)   # keeps its own material (the picture) out of the merge
			r.add_child(pic)
			pic.position = Vector3(0, 0.0009, 0)
			pic.rotation.x = -PI / 2.0
			var stamp := MeshInstance3D.new()   # typed on the back when it was taken (see Pickup.show_picture)
			stamp.mesh = QuadMesh.new()
			stamp.name = "Stamp"
			stamp.set_meta("live", true)
			stamp.visible = false
			r.add_child(stamp)
			stamp.position = Vector3(0.02, -0.0009, 0.03)
			stamp.rotation.x = PI / 2.0
		"MEDKIT":   # a dented red tin with a white cross, a carry handle and two latches
			var rd := Color(0.78, 0.12, 0.1)
			box(r, Vector3(0.3, 0.1, 0.2), Vector3(0, -0.01, 0), "metal", rd)
			box(r, Vector3(0.31, 0.02, 0.21), Vector3(0, 0.035, 0), "metal", rd.darkened(0.2))   # lid seam
			box(r, Vector3(0.09, 0.004, 0.028), Vector3(0, 0.047, 0), "cream", Color(0.95, 0.93, 0.88))
			box(r, Vector3(0.028, 0.004, 0.09), Vector3(0, 0.047, 0), "cream", Color(0.95, 0.93, 0.88))
			for s in [-1, 1]:
				box(r, Vector3(0.03, 0.03, 0.012), Vector3(s * 0.09, 0.0, 0.104), "metal", STEEL)   # latches
				seg(r, Vector3(s * 0.05, 0.048, 0), Vector3(s * 0.04, 0.075, 0), 0.007, 0.007, "metal", BLACK)
			seg(r, Vector3(-0.04, 0.075, 0), Vector3(0.04, 0.075, 0), 0.009, 0.009, "rubber")   # handle
		"WALKIE":   # a chunky handheld: rubber-armoured body, speaker grille, a stubby antenna, a knob
			var body := Color(0.2, 0.22, 0.2)
			box(r, Vector3(0.065, 0.15, 0.038), Vector3(0, -0.02, 0), "rubber", body)
			box(r, Vector3(0.068, 0.03, 0.04), Vector3(0, -0.085, 0), "plastic", Color(0.85, 0.65, 0.1))   # battery pack
			for i in 5:
				box(r, Vector3(0.045, 0.004, 0.003), Vector3(0, 0.0 + i * 0.01, 0.0195), "metal", Color(0.1, 0.1, 0.1))
			box(r, Vector3(0.04, 0.018, 0.003), Vector3(0, -0.045, 0.0195), "glow", Color(0.5, 0.9, 0.4))   # little screen
			seg(r, Vector3(0.018, 0.055, 0), Vector3(0.018, 0.16, 0), 0.007, 0.004, "rubber", Color(0.12, 0.12, 0.12))
			cyl(r, 0.009, 0.012, Vector3(-0.018, 0.062, 0), "plastic", Color(0.1, 0.1, 0.1))
			box(r, Vector3(0.008, 0.035, 0.012), Vector3(-0.036, 0.0, 0), "rubber", Color(0.12, 0.12, 0.12))   # talk button
		"DOOR_WEDGE":   # a rubber door wedge, ridged on top
			var poly := PackedVector2Array([Vector2(-0.07, -0.025), Vector2(0.07, -0.025), Vector2(0.07, 0.025)])
			slab(r, poly, 0.09, Vector3.ZERO, "rubber", Color(0.75, 0.3, 0.1))
			for i in 4:   # grip ridges across the slope
				var z := -0.045 + i * 0.03
				box(r, Vector3(0.08, 0.005, 0.008), Vector3(0, -0.025 + (z + 0.07) * 0.357 + 0.003, z), "rubber", Color(0.55, 0.2, 0.08), Vector3(-0.343, 0, 0))
		"SHELLS":   # a little card box of shells, lid open on the brass ends
			box(r, Vector3(0.12, 0.06, 0.09), Vector3(0, -0.005, 0), "cardboard", Color(0.75, 0.2, 0.12))
			box(r, Vector3(0.122, 0.012, 0.092), Vector3(0, -0.01, 0), "paper", Color(0.95, 0.85, 0.4))   # the band
			for k in 4:
				cyl(r, 0.011, 0.02, Vector3(-0.035 + k * 0.023, 0.03, 0.0), "brass", Color(0.9, 0.7, 0.3))
				cyl(r, 0.0105, 0.02, Vector3(-0.035 + k * 0.023, 0.03, 0.0), "plastic", Color(0.7, 0.12, 0.1)).position.y = 0.022
			box(r, Vector3(0.12, 0.004, 0.09), Vector3(0, 0.05, -0.06), "cardboard", Color(0.7, 0.18, 0.1), Vector3(-1.2, 0, 0))   # the lid
		"FLARE":   # a red road flare: paper tube, black striker cap, a little warning band
			cyl(r, 0.022, 0.26, Vector3(0, 0, 0.0), "paper", Color(0.78, 0.12, 0.1), Z)
			cyl(r, 0.024, 0.045, Vector3(0, 0, -0.13), "plastic", BLACK, Z)
			cyl(r, 0.023, 0.03, Vector3(0, 0, 0.06), "paper", Color(0.95, 0.85, 0.3), Z)
			cyl(r, 0.012, 0.03, Vector3(0, 0, 0.14), "metal", STEEL, Z)   # the spike end
		"NOISEMAKER":   # a wind-up alarm clock: twin bells, a hammer, a key behind
			var brass := Color(0.82, 0.62, 0.3)
			cyl(r, 0.06, 0.05, Vector3(0, -0.01, 0), "brass", brass, Z)
			cyl(r, 0.052, 0.004, Vector3(0, -0.01, 0.026), "paper", CREAM, Z)
			box(r, Vector3(0.004, 0.035, 0.003), Vector3(0, 0.005, 0.03), "metal", BLACK)
			box(r, Vector3(0.025, 0.004, 0.003), Vector3(0.01, -0.01, 0.03), "metal", BLACK)
			for s in [-1, 1]:
				ball(r, 0.028, Vector3(s * 0.04, 0.058, 0), "brass", brass, Vector3.ONE, true)
				seg(r, Vector3(s * 0.04, -0.06, 0), Vector3(s * 0.05, -0.08, 0), 0.006, 0.006, "metal", BLACK)   # feet
			seg(r, Vector3(0, 0.05, 0), Vector3(0, 0.075, 0), 0.004, 0.004, "metal", STEEL)
			box(r, Vector3(0.03, 0.012, 0.012), Vector3(0, 0.078, 0), "metal", STEEL)   # hammer
			cyl(r, 0.006, 0.03, Vector3(0, 0, -0.04), "brass", brass, Z)
			box(r, Vector3(0.04, 0.02, 0.004), Vector3(0, 0, -0.055), "brass", brass)   # key
		"ADRENALINE":   # an auto-injector: yellow barrel, orange safety cap, a window on the dose
			cyl(r, 0.018, 0.14, Vector3(0, 0, -0.01), "plastic", Color(0.95, 0.78, 0.15), Z)
			cyl(r, 0.02, 0.035, Vector3(0, 0, 0.075), "plastic", Color(0.95, 0.4, 0.1), Z)
			cyl(r, 0.015, 0.03, Vector3(0, 0, -0.085), "plastic", Color(0.3, 0.3, 0.3), Z)
			box(r, Vector3(0.012, 0.004, 0.04), Vector3(0, 0.018, 0.0), "glass", Color.WHITE)
		"WARDEN_LENS":   # its searchlight, torn out: a ribbed housing round a thick glass lens
			cyl(r, 0.17, 0.12, Vector3(0, 0, -0.02), "metal", Color(0.35, 0.36, 0.34), Z)
			cyl(r, 0.15, 0.02, Vector3(0, 0, 0.05), "glass", Color.WHITE, Z)
			ring(r, 0.175, 0.15, Vector3(0, 0, 0.05), "metal", STEEL, Z)
			for i in 5:
				ring(r, 0.172, 0.16, Vector3(0, 0, -0.07 + i * 0.022), "metal", Color(0.3, 0.3, 0.3), Z)
			seg(r, Vector3(0.05, -0.05, -0.08), Vector3(0.1, -0.12, -0.1), 0.012, 0.012, "flesh", Color(0.6, 0.2, 0.2))   # what it was wired into
			cyl(r, 0.04, 0.05, Vector3(0, 0, -0.1), "copper", Color.WHITE, Z)
		"VINTAGE_CAMERA":   # the observer's head: a bellows camera, lens out front
			box(r, Vector3(0.2, 0.18, 0.08), Vector3(0, 0, -0.1), "leather", Color(0.25, 0.22, 0.2))
			for i in 4:
				box(r, Vector3(0.17 - i * 0.02, 0.15 - i * 0.02, 0.035), Vector3(0, 0, -0.04 + i * 0.035), "rubber", Color(0.15, 0.14, 0.14))
			box(r, Vector3(0.1, 0.1, 0.03), Vector3(0, 0, 0.1), "metal", Color(0.25, 0.25, 0.25))
			cyl(r, 0.04, 0.05, Vector3(0, 0, 0.13), "metal", BLACK, Z)
			cyl(r, 0.032, 0.004, Vector3(0, 0, 0.157), "glass", Color.WHITE, Z)
			ball(r, 0.015, Vector3(0.07, 0.07, -0.1), "glow", Color(1, 0.2, 0.15))   # tally lamp
		"MARIONETTE_STRINGS":   # a coil of brass wire on a wooden control bar
			box(r, Vector3(0.24, 0.025, 0.04), Vector3(0, 0.0, 0), "wood", Color(0.7, 0.55, 0.38))
			box(r, Vector3(0.04, 0.025, 0.2), Vector3(0, 0.0, 0), "wood", Color(0.7, 0.55, 0.38))
			for i in 4:
				ring(r, 0.07 + i * 0.008, 0.066 + i * 0.008, Vector3(0.02, -0.015 - i * 0.004, 0.01), "brass", Color(0.9, 0.7, 0.35))
		"MIMIC_TOOTH":   # a long yellowed fang with a bloody root
			seg(r, Vector3(0, -0.1, 0), Vector3(0, 0.04, 0), 0.012, 0.035, "bone", Color(0.92, 0.88, 0.72))
			seg(r, Vector3(0, 0.04, 0), Vector3(0, 0.1, 0), 0.035, 0.03, "flesh", Color(0.6, 0.15, 0.12))
		"PULSATOR_SAC":   # what's left: a deflated, veined sac, still faintly warm
			ball(r, 0.16, Vector3.ZERO, "flesh", Color(0.85, 0.5, 0.48), Vector3(1.0, 0.45, 0.9))
			for i in 5:
				var a := TAU * i / 5.0
				seg(r, Vector3(cos(a) * 0.05, 0.06, sin(a) * 0.05), Vector3(cos(a) * 0.14, 0.02, sin(a) * 0.13), 0.008, 0.006, "glow", Color(0.9, 0.2, 0.1))
		"MINERS_HELMET":   # the wraith's: Bureau-issue, cracked, the lamp long dead
			var hy := Color(0.8, 0.72, 0.45)
			ball(r, 0.12, Vector3(0, -0.04, 0), "plastic", hy, Vector3(1, 0.85, 1.15), true)
			cyl(r, 0.145, 0.012, Vector3(0, -0.04, -0.01), "plastic", hy).scale = Vector3(1, 1, 1.15)
			cyl(r, 0.03, 0.03, Vector3(0, 0.03, 0.13), "metal", Color(0.3, 0.3, 0.3), Z)
			cyl(r, 0.022, 0.004, Vector3(0, 0.03, 0.146), "glass", Color.WHITE, Z)
			seg(r, Vector3(-0.06, 0.06, 0.05), Vector3(0.02, 0.02, 0.11), 0.004, 0.004, "rubber", BLACK)   # the crack
		"REMAINS":   # what's left of you, limp in your arms
			Suit.limp(r)
		"VAULT_KEYCARD":   # white plastic, a red band, a gold chip, a red LED that never quite goes out
			box(r, Vector3(0.088, 0.004, 0.056), Vector3.ZERO, "plastic", Color(0.92, 0.92, 0.9))
			box(r, Vector3(0.088, 0.0045, 0.014), Vector3(0, 0.0, -0.018), "plastic", Color(0.75, 0.1, 0.08))
			box(r, Vector3(0.014, 0.005, 0.011), Vector3(-0.025, 0.0, 0.01), "brass", Color(0.95, 0.78, 0.3))
			box(r, Vector3(0.006, 0.006, 0.006), Vector3(0.034, 0.002, 0.018), "glow", Color(1, 0.15, 0.1))
			box(r, Vector3(0.088, 0.0042, 0.006), Vector3(0, 0.0, 0.024), "plastic", Color(0.1, 0.1, 0.1))   # the magnetic stripe
		"GOLD_BAR":   # a stamped ingot, narrower on top
			var g := ingot(r, Vector3(0.2, 0.05, 0.09), "brass", Color.WHITE)
			var gm := StandardMaterial3D.new()   # polished: it catches every light in the room
			gm.albedo_color = Color(1.0, 0.76, 0.3)
			gm.metallic = 0.85
			gm.roughness = 0.22
			gm.metallic_specular = 0.8
			gm.emission_enabled = true
			gm.emission = Color(0.35, 0.22, 0.05)
			gm.emission_energy_multiplier = 0.25
			g.material_override = gm
			var stamp := box(r, Vector3(0.06, 0.002, 0.03), Vector3(0, 0.026, 0), "brass", Color(0.85, 0.62, 0.2))
			stamp.material_override = gm
		"CASH_BOX":   # a grey steel petty-cash box, handle on top, a little brass lock
			box(r, Vector3(0.3, 0.09, 0.22), Vector3(0, -0.005, 0), "metal", Color(0.45, 0.47, 0.48))
			box(r, Vector3(0.302, 0.012, 0.222), Vector3(0, 0.035, 0), "metal", Color(0.38, 0.4, 0.41))
			seg(r, Vector3(-0.06, 0.042, 0), Vector3(-0.06, 0.06, 0), 0.006, 0.006, "metal", STEEL)
			seg(r, Vector3(0.06, 0.042, 0), Vector3(0.06, 0.06, 0), 0.006, 0.006, "metal", STEEL)
			seg(r, Vector3(-0.06, 0.06, 0), Vector3(0.06, 0.06, 0), 0.006, 0.006, "metal", STEEL)
			box(r, Vector3(0.03, 0.03, 0.006), Vector3(0, 0.0, 0.112), "brass", Color(0.9, 0.7, 0.3))
		"BEARER_BONDS":   # a banded stack of engraved certificates
			box(r, Vector3(0.24, 0.045, 0.17), Vector3.ZERO, "paper", Color(0.88, 0.85, 0.72))
			box(r, Vector3(0.242, 0.047, 0.03), Vector3(0, 0, 0), "paper", Color(0.55, 0.15, 0.12))
			box(r, Vector3(0.2, 0.002, 0.13), Vector3(0, 0.0235, 0), "paper", Color(0.6, 0.75, 0.6))
		_:
			var size: Vector3 = Data.ITEMS[id].size
			box(r, size, Vector3.ZERO, "plastic", Data.color(id))
	Merge.bake(r, 1000.0)   # one mesh per material instead of dozens of parts
	return r


# --- helpers -------------------------------------------------------------------------------

static func _mat(kind: String, tint: Color) -> Material:
	if kind == "glass":
		return A.glass()
	if kind == "glow":
		return A.mat("cream", tint, 0.25, 3.0)
	return A.mat(kind, tint, 0.25)


static func _add(p: Node3D, mesh: Mesh, kind: String, tint: Color, pos: Vector3, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(kind, tint)
	p.add_child(mi)
	mi.position = pos
	mi.rotation = rot
	return mi


static func box(p: Node3D, size: Vector3, pos: Vector3, kind: String, tint := Color.WHITE, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _add(p, m, kind, tint, pos, rot)


## Cylinder along y (rotate with X / Z), radius r at the bottom and `top` at the top.
static func cyl(p: Node3D, r: float, h: float, pos: Vector3, kind: String, tint := Color.WHITE, rot := Vector3.ZERO, top := -1.0) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.bottom_radius = r
	m.top_radius = r if top < 0.0 else top
	m.height = h
	m.radial_segments = 16
	m.rings = 1
	return _add(p, m, kind, tint, pos, rot)


static func ball(p: Node3D, r: float, pos: Vector3, kind: String, tint := Color.WHITE, sc := Vector3.ONE, hemi := false) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.is_hemisphere = hemi
	m.radial_segments = 16
	m.rings = 8
	var mi := _add(p, m, kind, tint, pos, Vector3.ZERO)
	mi.scale = sc
	return mi


## Torus lying flat (around y); rotate with X / Z to stand it up.
static func ring(p: Node3D, outer: float, inner: float, pos: Vector3, kind: String, tint := Color.WHITE, rot := Vector3.ZERO, sc := Vector3.ONE) -> MeshInstance3D:
	var m := TorusMesh.new()
	m.outer_radius = outer
	m.inner_radius = inner
	m.rings = 20
	m.ring_segments = 8
	var mi := _add(p, m, kind, tint, pos, rot)
	mi.scale = sc
	return mi


## A flat outline extruded across x: `poly` is the shape in (z, y), `w` its thickness. For gun
## stocks, axe heads, prints: anything whose silhouette boxes can't make. Flat-shaded.
static func slab(p: Node3D, poly: PackedVector2Array, w: float, pos: Vector3, kind: String, tint := Color.WHITE, rot := Vector3.ZERO) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uvk := 6.0
	var tris := Geometry2D.triangulate_polygon(poly)
	for sx in [-1.0, 1.0]:   # the two faces
		var n := Vector3(sx, 0, 0)
		for i in range(0, tris.size(), 3):
			var t := [poly[tris[i]], poly[tris[i + 1]], poly[tris[i + 2]]]
			var v: Array = t.map(func(q): return Vector3(sx * w / 2.0, q.y, q.x))
			_tri(st, v, [t[0] * uvk, t[1] * uvk, t[2] * uvk], n)
	var mid := Vector2.ZERO
	for q in poly:
		mid += q / poly.size()
	var run := 0.0
	for i in poly.size():   # the edge all the way round
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := b - a
		var out2 := Vector2(e.y, -e.x).normalized()
		if out2.dot((a + b) * 0.5 - mid) < 0.0:
			out2 = -out2   # (always facing out)
		var n := Vector3(0, out2.y, out2.x)
		var q := [Vector3(-w / 2.0, a.y, a.x), Vector3(-w / 2.0, b.y, b.x), Vector3(w / 2.0, b.y, b.x), Vector3(w / 2.0, a.y, a.x)]
		var u := [Vector2(run, 0), Vector2(run + e.length(), 0), Vector2(run + e.length(), w), Vector2(run, w)]
		u = u.map(func(x): return x * uvk)
		_tri(st, [q[0], q[1], q[2]], [u[0], u[1], u[2]], n)
		_tri(st, [q[0], q[2], q[3]], [u[0], u[2], u[3]], n)
		run += e.length()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(kind, tint)
	p.add_child(mi)
	mi.position = pos
	mi.rotation = rot
	return mi


## A cast ingot: a trapezoid in section and along its length (narrower on top), `s` = the base.
static func ingot(p: Node3D, s: Vector3, kind: String, tint := Color.WHITE) -> MeshInstance3D:
	var top := Vector2(s.x * 0.82, s.z * 0.7)
	var h := s.y
	var b := [Vector3(-s.x / 2, -h / 2, -s.z / 2), Vector3(s.x / 2, -h / 2, -s.z / 2), Vector3(s.x / 2, -h / 2, s.z / 2), Vector3(-s.x / 2, -h / 2, s.z / 2)]
	var t := [Vector3(-top.x / 2, h / 2, -top.y / 2), Vector3(top.x / 2, h / 2, -top.y / 2), Vector3(top.x / 2, h / 2, top.y / 2), Vector3(-top.x / 2, h / 2, top.y / 2)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := [[t[0], t[1], t[2], t[3]], [b[3], b[2], b[1], b[0]]]
	for i in 4:
		quads.append([b[i], b[(i + 1) % 4], t[(i + 1) % 4], t[i]])
	for q in quads:
		var n: Vector3 = (q[1] - q[0]).cross(q[2] - q[0]).normalized()
		if n.dot((q[0] + q[2]) * 0.5) < 0.0:
			n = -n
		var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		_tri(st, [q[0], q[1], q[2]], [uv[0], uv[1], uv[2]], n)
		_tri(st, [q[0], q[2], q[3]], [uv[0], uv[2], uv[3]], n)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(kind, tint)
	p.add_child(mi)
	return mi


## One triangle facing `n` (Godot wants front faces clockwise seen from the front).
static func _tri(st: SurfaceTool, v: Array, uv: Array, n: Vector3) -> void:
	var order := [0, 1, 2] if (v[1] - v[0]).cross(v[2] - v[0]).dot(n) < 0.0 else [0, 2, 1]
	for k in order:
		st.set_normal(n)
		st.set_uv(uv[k])
		st.add_vertex(v[k])


## Tapered cylinder from a (radius r0) to b (radius r1).
static func seg(p: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, kind: String, tint := Color.WHITE) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.bottom_radius = r0
	m.top_radius = r1
	m.height = a.distance_to(b)
	m.radial_segments = 12
	m.rings = 1
	var mi := _add(p, m, kind, tint, Vector3.ZERO, Vector3.ZERO)
	mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, (b - a).normalized())), (a + b) / 2.0)
	return mi
