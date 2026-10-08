# Path gizmos for the playground ([P]): drawn on top of everything, every frame.
#   room graph   white dots on each room (upper floor) and blue on the lower floor, grey links between
#                rooms, a red link through each SHUT bulkhead (not walkable while shut)
#   per monster  yellow line to the waypoint it's heading for, cyan polyline along its route,
#                faint magenta line to where it actually wants to go, a cross at that goal.
#                The yellow turns orange, then red, the longer it has gone without real progress.
#   stuck spots  a red post wherever the unstuck failsafe had to step a monster forward
#   navmesh      green edges of the baked walkable surface within 18 m of the camera
extends MeshInstance3D

const CELL := 12.0
const PIT := 3.0

var main
var graph := true
var _mesh := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()


func _ready() -> void:
	mesh = _mesh
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.no_depth_test = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.render_priority = 10
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	extra_cull_margin = 16384.0


func _process(_delta: float) -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var lines := 0
	var fac = main.level.facility if main.level != null else null
	if fac != null and graph:
		lines += _graph(fac)
	if fac != null and fac.nav != null:
		lines += _navmesh(fac)
	for m in main.get_tree().get_nodes_in_group("monsters"):
		if not "dbg_target" in m or m.dbg_target == Vector3.INF:
			continue
		var at: Vector3 = m.global_position + Vector3(0, 0.15, 0)
		var stuck: float = clampf(m._anchor_t / 3.0, 0.0, 1.0)
		var c := Color(1, 0.9, 0.1).lerp(Color(1, 0.1, 0.05), stuck)
		_line(at, m.dbg_next + Vector3(0, 0.1, 0), c)
		var prev := at
		for p in (m.nav_path if not m.nav_path.is_empty() else m._route):
			_line(prev, p, Color(0.2, 0.95, 1.0))
			prev = p
		_line(at, m.dbg_target + Vector3(0, 0.1, 0), Color(1, 0.3, 1, 0.35))
		_cross(m.dbg_target + Vector3(0, 0.1, 0), 0.35, Color(1, 0.3, 1))
		lines += 4
	var monster_script = load("res://src/monster.gd")
	for s in monster_script.unstuck_spots:
		var p: Vector3 = s[0]
		_line(p, p + Vector3(0, 2.5, 0), Color(1, 0, 0))
		_cross(p + Vector3(0, 0.05, 0), 0.5, Color(1, 0, 0))
		lines += 3
	if lines == 0:   # an empty surface is an error
		_line(Vector3.ZERO, Vector3.ZERO, Color.TRANSPARENT)
	_mesh.surface_end()


func _graph(fac) -> int:
	var shut := {}
	for code in fac.doors:
		if not fac.doors[code].get_meta("open"):
			var e: Array = fac.layout.doors[code]
			shut[e] = true
	var n := 0
	for id in fac.cell_of_id:
		var c: Vector2i = fac.cell_of_id[id]
		var low: bool = fac.layer_of_id[id] == 1
		var p: Vector3 = _node_pos(fac, c, low)
		_cross(p, 0.3, Color(0.4, 0.6, 1.0) if low else Color(1, 1, 1))
		for other in fac.astar.get_point_connections(id):
			if other > id:
				_line(p, _node_pos(fac, fac.cell_of_id[other], fac.layer_of_id[other] == 1), Color(0.75, 0.75, 0.75, 0.55))
				n += 1
	for e in shut:   # a red bar across the doorway of each shut bulkhead
		var a: Vector3 = _node_pos(fac, e[0], false)
		var b: Vector3 = _node_pos(fac, e[1], false)
		_line(a, b, Color(1, 0.15, 0.1))
		var mid := (a + b) / 2.0
		_cross(mid, 0.8, Color(1, 0.15, 0.1))
	return n + 1


func _navmesh(fac) -> int:
	var nm: NavigationMesh = fac.nav.navigation_mesh
	var cam := get_viewport().get_camera_3d()
	if nm == null or cam == null:
		return 0
	var xf: Transform3D = fac.nav.global_transform
	var verts := nm.vertices
	var eye := cam.global_position
	var n := 0
	for i in nm.get_polygon_count():
		var poly := nm.get_polygon(i)
		var first: Vector3 = xf * verts[poly[0]]
		if first.distance_to(eye) > 18.0:
			continue
		for k in poly.size():
			var a: Vector3 = xf * verts[poly[k]]
			var b: Vector3 = xf * verts[poly[(k + 1) % poly.size()]]
			_line(a + Vector3(0, 0.03, 0), b + Vector3(0, 0.03, 0), Color(0.2, 1.0, 0.35, 0.8))
			n += 1
	return n


func _node_pos(fac, c: Vector2i, low: bool) -> Vector3:
	return fac.to_global(Vector3(c.x * CELL, (-PIT if low else 0.0) + 0.4, c.y * CELL))


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(b)


func _cross(p: Vector3, r: float, c: Color) -> void:
	_line(p - Vector3(r, 0, 0), p + Vector3(r, 0, 0), c)
	_line(p - Vector3(0, 0, r), p + Vector3(0, 0, r), c)
	_line(p - Vector3(0, r * 0.6, 0), p + Vector3(0, r * 0.6, 0), c)
