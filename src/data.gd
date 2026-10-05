# All game content lives here. Rename/replace freely — this is where "your stuff" goes.
extends RefCounted

const RES := ["steel", "copper", "rubber", "plastic"]
const RES_SHORT := {"steel": "STL", "copper": "CU", "rubber": "RUB", "plastic": "PLA"}
const RES_COLOR := {
	"steel": Color(0.6, 0.63, 0.67),
	"copper": Color(0.82, 0.42, 0.18),
	"rubber": Color(0.13, 0.13, 0.14),
	"plastic": Color(0.25, 0.7, 0.95),
}
# Credits paid per unit when shredded; rerolled every day.
const BASE_PRICE := {"steel": 3.0, "copper": 5.0, "rubber": 4.0, "plastic": 2.0}

# kind defaults to "scrap". res = what the shredder turns it into.
const ITEMS := {
	"BENT_SPRING": {"name": "Bent Spring", "res": {"steel": 2}, "size": Vector3(0.15, 0.3, 0.15)},
	"BROKEN_SPEAKER": {"name": "Broken Speaker", "res": {"plastic": 1, "rubber": 1, "copper": 1, "steel": 2}, "size": Vector3(0.4, 0.5, 0.35)},
	"COOKING_PAN": {"name": "Cooking Pan", "res": {"steel": 2}, "size": Vector3(0.45, 0.08, 0.3)},
	"COPPER_INGOT": {"name": "Copper Ingot", "res": {"copper": 3}, "size": Vector3(0.3, 0.1, 0.12)},
	"COPPER_PIPE": {"name": "Copper Pipe", "res": {"copper": 2}, "size": Vector3(0.08, 0.08, 0.7)},
	"EMPTY_CAN": {"name": "Empty Can", "res": {"steel": 1}, "size": Vector3(0.1, 0.15, 0.1)},
	"HAMMER": {"name": "Hammer", "res": {"plastic": 1, "steel": 2}, "size": Vector3(0.1, 0.06, 0.4)},
	"HAZARD_CONE": {"name": "Hazard Cone", "res": {"plastic": 3}, "size": Vector3(0.35, 0.6, 0.35), "color": Color(1, 0.45, 0.05)},
	"LARGE_SCREW": {"name": "Large Screw", "res": {"steel": 2}, "size": Vector3(0.08, 0.35, 0.08)},
	"MILK_JUG": {"name": "Milk Jug", "res": {"plastic": 2}, "size": Vector3(0.2, 0.3, 0.2), "color": Color(0.92, 0.92, 0.88)},
	"OLD_BOOT": {"name": "Old Boot", "res": {"rubber": 2}, "size": Vector3(0.15, 0.25, 0.32)},
	"OLD_CLOCK": {"name": "Old Clock", "res": {"plastic": 2, "copper": 1, "steel": 1}, "size": Vector3(0.3, 0.3, 0.1)},
	"PENNY": {"name": "Penny", "res": {"copper": 1}, "size": Vector3(0.1, 0.04, 0.1)},
	"RED_COPPER_PAN": {"name": "Red Copper Pan", "res": {"copper": 2, "steel": 1}, "size": Vector3(0.35, 0.08, 0.35)},
	"RUBBER_BAND_BALL": {"name": "Rubber Band Ball", "res": {"rubber": 2}, "size": Vector3(0.18, 0.18, 0.18)},
	"RUBBER_TIRE": {"name": "Rubber Tire", "res": {"rubber": 5}, "size": Vector3(0.6, 0.6, 0.2)},
	"SCISSORS": {"name": "Scissors", "res": {"plastic": 1, "steel": 2}, "size": Vector3(0.08, 0.04, 0.22)},
	"STEEL_INGOT": {"name": "Steel Ingot", "res": {"steel": 3}, "size": Vector3(0.3, 0.1, 0.12)},
	"TOY_DINO": {"name": "Toy Dino", "res": {"plastic": 2}, "size": Vector3(0.2, 0.25, 0.3), "color": Color(0.3, 0.8, 0.3)},
	"TOY_TRUCK": {"name": "Toy Truck", "res": {"plastic": 2, "rubber": 1}, "size": Vector3(0.3, 0.2, 0.2), "color": Color(0.9, 0.8, 0.1)},
	"WATER_BOTTLE": {"name": "Water Bottle", "res": {"plastic": 2, "steel": 1}, "size": Vector3(0.1, 0.3, 0.1)},
	"WATER_POUCH": {"name": "Water Pouch", "res": {"rubber": 3}, "size": Vector3(0.3, 0.1, 0.25)},
	"PUMP_GASKET": {"name": "Pump Gasket", "res": {"rubber": 2}, "size": Vector3(0.3, 0.05, 0.3)},
	"WIRE_SPOOL": {"name": "Wire Spool", "res": {"plastic": 1, "copper": 3}, "size": Vector3(0.3, 0.3, 0.3)},

	"FLASHLIGHT": {"name": "Flashlight", "kind": "tool", "price": 35, "charge": 200.0, "res": {"plastic": 1, "copper": 1},
		"size": Vector3(0.07, 0.07, 0.3), "color": Color(0.95, 0.8, 0.15), "desc": "Beam light. Click to toggle."},
	"LANTERN": {"name": "Lantern", "kind": "tool", "price": 55, "charge": 285.0, "res": {"copper": 1, "steel": 1},
		"size": Vector3(0.18, 0.3, 0.18), "color": Color(0.9, 0.6, 0.2), "desc": "Lights all around you. Click to toggle."},
	"SCANNER": {"name": "Scanner", "kind": "equip", "price": 90, "res": {},
		"size": Vector3(0.15, 0.2, 0.08), "color": Color(0.2, 0.9, 0.6), "desc": "Equipment. F / middle mouse to scan nearby."},
	"BACKPACK": {"name": "Backpack", "kind": "equip", "price": 80, "res": {},
		"size": Vector3(0.4, 0.5, 0.25), "color": Color(0.35, 0.4, 0.2), "desc": "Equipment. +1 inventory slot."},
}

const SHOP := ["FLASHLIGHT", "LANTERN", "SCANNER", "BACKPACK"]

# Facility looks. *_kind = texture from art.gd; band = lower wall stripe.
const THEMES := {
	"FACTORY": {"floor_kind": "concrete", "floor": Color(0.75, 0.7, 0.65), "wall_kind": "concrete", "wall": Color(0.85, 0.8, 0.74),
		"band_kind": "rust", "band": Color(0.9, 0.85, 0.8), "ceil_kind": "metal", "ceiling": Color(0.5, 0.48, 0.45),
		"light": Color(1, 0.72, 0.42), "light_chance": 0.45, "props": 5, "bulkheads": 1, "weight": 4},
	"LAB": {"floor_kind": "tiles", "floor": Color(0.85, 0.85, 0.82), "wall_kind": "tiles", "wall": Color(0.9, 0.92, 0.9),
		"band_kind": "metal", "band": Color(0.55, 0.7, 0.68), "ceil_kind": "concrete", "ceiling": Color(0.9, 0.9, 0.9),
		"light": Color(0.75, 0.95, 1.0), "light_chance": 0.5, "props": 4, "bulkheads": 1, "weight": 3},
	"FLESH": {"floor_kind": "flesh", "floor": Color(0.7, 0.6, 0.6), "wall_kind": "flesh", "wall": Color(0.9, 0.8, 0.8),
		"band_kind": "flesh", "band": Color(0.6, 0.45, 0.45), "ceil_kind": "flesh", "ceiling": Color(0.5, 0.4, 0.4),
		"light": Color(1, 0.35, 0.35), "light_chance": 0.3, "props": 4, "bulkheads": 3, "weight": 2},
	"BACKROOMS": {"floor_kind": "carpet", "floor": Color.WHITE, "wall_kind": "wallpaper", "wall": Color.WHITE,
		"band_kind": "wallpaper", "band": Color(0.75, 0.7, 0.6), "ceil_kind": "tiles", "ceiling": Color(0.85, 0.83, 0.75),
		"light": Color(1, 1, 0.82), "light_chance": 0.8, "props": 1, "bulkheads": 0, "weight": 1},
}

const WEATHERS := ["CLEAR", "CLEAR", "CLEAR", "SANDSTORM", "ACID_RAIN"]


static func kind(id: String) -> String:
	return ITEMS[id].get("kind", "scrap")


static func scrap_ids() -> Array:
	return ITEMS.keys().filter(func(k): return kind(k) == "scrap")


static func random_scrap(rng: RandomNumberGenerator) -> String:
	var ids := scrap_ids()
	return ids[rng.randi() % ids.size()]


static func color(id: String) -> Color:
	var d: Dictionary = ITEMS[id]
	if d.has("color"):
		return d.color
	var best := ""
	for r in d.res:
		if best == "" or d.res[r] > d.res[best]:
			best = r
	return RES_COLOR.get(best, Color.GRAY)


static func res_text(res: Dictionary) -> String:
	var parts := PackedStringArray()
	for r in RES:
		if res.get(r, 0) > 0:
			parts.append("%d %s" % [res[r], RES_SHORT[r]])
	return ", ".join(parts)
