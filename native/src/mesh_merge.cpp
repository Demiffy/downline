#include "mesh_merge.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/primitive_mesh.hpp>
#include <godot_cpp/classes/box_mesh.hpp>
#include <godot_cpp/classes/cylinder_mesh.hpp>
#include <godot_cpp/classes/sphere_mesh.hpp>
#include <godot_cpp/classes/torus_mesh.hpp>
#include <godot_cpp/classes/capsule_mesh.hpp>
#include <godot_cpp/classes/prism_mesh.hpp>
#include <godot_cpp/classes/quad_mesh.hpp>
#include <godot_cpp/classes/plane_mesh.hpp>
#include <godot_cpp/classes/surface_tool.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/area3d.hpp>
#include <godot_cpp/classes/geometry_instance3d.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/core/object.hpp>

#include <algorithm>
#include <unordered_map>

#include <mutex>
#include <vector>
#include <cmath>

using namespace godot;

static std::mutex s_lock;
static Dictionary *s_arrays = nullptr;   // shape -> [verts, normals, uvs] (deindexed), as merge.gd's _arrays

void MeshMerge::_bind_methods() {
	ClassDB::bind_static_method("MeshMerge", D_METHOD("gather", "root"), &MeshMerge::gather);
	ClassDB::bind_static_method("MeshMerge", D_METHOD("take", "items", "chunk", "indoors", "groups", "victims"), &MeshMerge::take);
	ClassDB::bind_static_method("MeshMerge", D_METHOD("cache_size"), &MeshMerge::cache_size);
	ClassDB::bind_static_method("MeshMerge", D_METHOD("clear_cache"), &MeshMerge::clear_cache);
	ClassDB::bind_static_method("MeshMerge", D_METHOD("open", "root"), &MeshMerge::open);
	ClassDB::bind_static_method("MeshMerge", D_METHOD("close", "root"), &MeshMerge::close);
	ClassDB::bind_static_method("MeshMerge", D_METHOD("piece", "owner", "shape", "material", "pos", "rot", "turned"), &MeshMerge::piece);
	ClassDB::bind_static_method("MeshMerge", D_METHOD("piece_xf", "owner", "shape", "material", "xf"), &MeshMerge::piece_xf);
	ClassDB::bind_static_method("MeshMerge", D_METHOD("settle", "root"), &MeshMerge::settle);
	ClassDB::bind_static_method("MeshMerge", D_METHOD("pieces_under", "node"), &MeshMerge::pieces_under);
	ClassDB::bind_static_method("MeshMerge", D_METHOD("drop", "id"), &MeshMerge::drop);
	ClassDB::bind_static_method("MeshMerge", D_METHOD("pending"), &MeshMerge::pending);
	ClassDB::bind_static_method("MeshMerge", D_METHOD("forget", "nodes"), &MeshMerge::forget);
}

static Variant mul(const Variant &a, const Variant &b) {   // (the engine's own operator, as GDScript's `*`)
	Variant r;
	bool valid = false;
	Variant::evaluate(Variant::OP_MULTIPLY, a, b, r, valid);
	return r;
}

// --- pieces: primitives that never become nodes -------------------------------------------------------
// While a stop is built (open(root) .. close(root)), art.gd's s-primitives (A.sbox, ...) hand their mesh
// here instead of making a MeshInstance3D: a piece remembers its parent (the owner), its transform under
// it, its material, and where among the owner's children the node would have stood. gather() takes the
// pieces of every node it walks at exactly that place among its children, so a bake merges the same
// vertices in the same order as with the nodes. Pieces under a node the merge leaves alone (hidden, live,
// scripted) become real nodes when that bake ends (settle), and whatever is left when the build ends
// (close), so nothing is ever lost.
struct Pending {
	uint64_t id;
	Array piece;        // [[verts, normals, uvs, aabb], material]: what take() reads
	Transform3D local;  // under the owner
	int index;          // the owner's child count when it was queued...
	uint64_t anchor;    // ...and its last child then (0: none): the node would have come right after it
	uint64_t scope;
	Array key;          // the shape (merge.gd's _shape_key): enough to make the mesh again
};

static std::recursive_mutex s_plock;
static std::unordered_map<uint64_t, std::vector<Pending>> *s_pending = nullptr;   // owner -> its pieces, in order
static std::vector<uint64_t> s_scopes;
static uint64_t s_next_id = 1;
static Node3D *s_scratch = nullptr;   // (turns a position and rotation into a transform the way a Node3D does)
static StringName *s_no_pieces = nullptr;   // (made once: a StringName from a C string is a lookup each time; a
                                           //  pointer, as a static one would be built before the engine is there)

static std::unordered_map<uint64_t, std::vector<Pending>> &pending_map() {
	if (!s_pending)
		s_pending = new std::unordered_map<uint64_t, std::vector<Pending>>();
	return *s_pending;
}

// Where among n's children (0..count) each piece goes: right after its anchor if that's still there.
static int piece_pos(Node *n, const Pending &p, int count) {
	if (p.anchor == 0)
		return 0;
	Node *a = Object::cast_to<Node>(ObjectDB::get_instance(p.anchor));
	if (a && a->get_parent() == n)
		return a->get_index() + 1;
	return MIN(p.index, count);
}

static std::vector<Pending> take_pending(Node *n) {
	std::lock_guard<std::recursive_mutex> g(s_plock);
	std::vector<Pending> ps;
	if (!s_pending || s_pending->empty())
		return ps;
	auto it = s_pending->find(n->get_instance_id());
	if (it == s_pending->end())
		return ps;
	ps = std::move(it->second);
	s_pending->erase(it);
	return ps;
}

static void gather_into(Node *n, const Transform3D &t, Array &items) {
	TypedArray<Node> kids = n->get_children();
	std::vector<Pending> ps = take_pending(n);
	std::vector<int> pos(ps.size());
	if (!ps.empty() && Object::cast_to<MeshInstance3D>(n))
		n->set_meta(StringName("had_pieces"), true);   // (a mesh with pieces for children stays a node, as it would with nodes: merge.gd)
	if (!ps.empty()) {
		std::vector<std::pair<int, int>> order;   // (place, queue order): sorted, the queue order kept among equals
		for (size_t q = 0; q < ps.size(); q++)
			order.push_back({ piece_pos(n, ps[q], kids.size()), (int)q });
		std::stable_sort(order.begin(), order.end());
		std::vector<Pending> sorted;
		for (auto &o : order) {
			pos[sorted.size()] = o.first;
			sorted.push_back(std::move(ps[o.second]));
		}
		ps = std::move(sorted);
	}
	size_t pi = 0;
	auto emit = [&](const Pending &p) {
		Array it;
		it.append(p.piece);
		it.append(Transform3D(mul(t, p.local)));
		items.append(it);
	};
	for (int i = 0; i < kids.size(); i++) {
		while (pi < ps.size() && pos[pi] <= i)
			emit(ps[pi++]);
		Node3D *c = Object::cast_to<Node3D>(kids[i]);
		if (!c || c->get_script().get_type() != Variant::NIL || c->has_meta("live") || !c->is_visible())
			continue;
		if (Object::cast_to<RigidBody3D>(c) || Object::cast_to<CharacterBody3D>(c) || Object::cast_to<Area3D>(c))
			continue;
		Transform3D ct = mul(t, c->get_transform());
		MeshInstance3D *mi = Object::cast_to<MeshInstance3D>(c);
		if (mi && mi->get_mesh().is_valid() && mi->get_material_overlay().is_null()) {
			Array it;
			it.append(mi);
			it.append(ct);
			items.append(it);
		}
		gather_into(c, ct, items);
	}
	while (pi < ps.size())
		emit(ps[pi++]);
}

Array MeshMerge::gather(Node3D *p_root) {
	Array items;
	if (p_root)
		gather_into(p_root, Transform3D(), items);
	return items;
}

static Variant shape_key(const Ref<Mesh> &m) {   // (merge.gd's _shape_key)
	Array k;
	if (Ref<BoxMesh> b = m; b.is_valid()) {
		k.append("B"); k.append(b->get_size());
	} else if (Ref<CylinderMesh> c = m; c.is_valid()) {
		k.append("C"); k.append(c->get_top_radius()); k.append(c->get_bottom_radius()); k.append(c->get_height()); k.append(c->get_radial_segments()); k.append(c->get_rings());
	} else if (Ref<SphereMesh> s = m; s.is_valid()) {
		k.append("S"); k.append(s->get_radius()); k.append(s->get_height()); k.append(s->get_radial_segments()); k.append(s->get_rings()); k.append(s->get_is_hemisphere());
	} else if (Ref<TorusMesh> t = m; t.is_valid()) {
		k.append("T"); k.append(t->get_inner_radius()); k.append(t->get_outer_radius()); k.append(t->get_rings()); k.append(t->get_ring_segments());
	} else if (Ref<CapsuleMesh> cp = m; cp.is_valid()) {
		k.append("K"); k.append(cp->get_radius()); k.append(cp->get_height()); k.append(cp->get_radial_segments()); k.append(cp->get_rings());
	} else if (Ref<PrismMesh> p = m; p.is_valid()) {
		k.append("P"); k.append(p->get_size()); k.append(p->get_left_to_right());
	} else if (Ref<QuadMesh> q = m; q.is_valid()) {
		k.append("Q"); k.append(q->get_class()); k.append(q->get_size());
	} else if (Ref<PlaneMesh> pl = m; pl.is_valid()) {
		k.append("Q"); k.append(pl->get_class()); k.append(pl->get_size());
	} else {
		return (int64_t)m->get_instance_id();
	}
	return k;
}

static Array mesh_arrays(const Ref<Mesh> &m, int s) {   // (merge.gd's _mesh_arrays)
	Variant k = shape_key(m);
	{
		std::lock_guard<std::mutex> g(s_lock);
		if (!s_arrays)
			s_arrays = memnew(Dictionary);
		if (s_arrays->has(k))
			return (*s_arrays)[k];
	}
	Ref<PrimitiveMesh> pm = m;
	Ref<SurfaceTool> st;
	st.instantiate();
	st->create_from_arrays(pm.is_valid() ? pm->get_mesh_arrays() : m->surface_get_arrays(s));
	st->deindex();
	Array a = st->commit_to_arrays();
	Variant uv = a[Mesh::ARRAY_TEX_UV];
	if (uv.get_type() == Variant::NIL) {
		PackedVector2Array z;
		z.resize(PackedVector3Array(a[Mesh::ARRAY_VERTEX]).size());
		uv = z;
	}
	Array out;
	out.append(a[Mesh::ARRAY_VERTEX]);
	out.append(a[Mesh::ARRAY_NORMAL]);
	out.append(uv);
	out.append(m->get_aabb());
	std::lock_guard<std::mutex> g(s_lock);
	(*s_arrays)[k] = out;
	return out;
}

struct Slot {   // one merged surface's growing buffers (merge.gd's Buf), while a take() runs
	String key;
	Variant mid;
	PackedVector3Array v, n;
	PackedVector2Array uv, uv2;
	PackedColorArray c;
	Variant mat;
};

void MeshMerge::take(const Array &p_items, double p_chunk, bool p_indoors, Dictionary p_groups, Array p_victims) {
	std::vector<Slot> slots;
	Dictionary index;   // key -> {mid -> slot}
	auto slot_for = [&](const String &key, const Variant &mid, const Variant &mat) -> Slot & {
		if (!p_groups.has(key))
			p_groups[key] = Dictionary();
		Dictionary g = p_groups[key];
		if (!index.has(key))
			index[key] = Dictionary();
		Dictionary ix = index[key];
		if (ix.has(mid))
			return slots[(int)ix[mid]];
		Slot sl;
		sl.key = key;
		sl.mid = mid;
		sl.mat = mat;
		if (g.has(mid)) {   // (it was started by an earlier take: carry on from there)
			Array have = g[mid];
			sl.v = have[0]; sl.n = have[1]; sl.uv = have[2]; sl.c = have[3]; sl.uv2 = have[4]; sl.mat = have[5];
		} else {
			g[mid] = Array();   // (claimed now, so the groups keep merge.gd's order)
		}
		ix[mid] = (int)slots.size();
		slots.push_back(sl);
		return slots.back();
	};
	for (int i = 0; i < p_items.size(); i++) {
		Array it = p_items[i];
		Transform3D ct = it[1];
		MeshInstance3D *mi = nullptr;
		Ref<Mesh> mesh;
		Array piece;   // (a piece: no node, one surface, its arrays and box made when it was queued, shadows on)
		AABB box;
		int shadow = GeometryInstance3D::SHADOW_CASTING_SETTING_ON;
		if (it[0].get_type() == Variant::ARRAY) {
			piece = it[0];
			box = Array(piece[0])[3];
		} else {
			mi = Object::cast_to<MeshInstance3D>(it[0]);
			if (!mi)
				continue;
			mesh = mi->get_mesh();
			box = mesh->get_aabb();
			shadow = (int)mi->get_cast_shadows_setting();
		}
		Vector3 centre = mul(ct, box.get_center());
		Vector3 cell = ((centre + Vector3(1, 1, 1) * p_chunk / 2.0) / p_chunk).floor();
		Vector3 ext = mul(Variant(ct.basis).call("get_scale"), box.size);
		double longest = MAX(ext.x, MAX(ext.y, ext.z));
		if (longest < 0.3)
			shadow = GeometryInstance3D::SHADOW_CASTING_SETTING_OFF;   // clutter: shadows cost more than they show
		if (p_indoors && ext.y < 0.4 && ext.x > 1.5 && ext.z > 1.5)
			shadow = GeometryInstance3D::SHADOW_CASTING_SETTING_OFF;   // a floor or ceiling slab
		String key = vformat("%d,%d,%d|%d", (int64_t)cell.x, (int64_t)cell.y, (int64_t)cell.z, shadow);
		Transform3D nx(Variant(Variant(ct.basis).call("inverse")).call("transposed"), Vector3());
		const int surfaces = mi ? mesh->get_surface_count() : 1;
		for (int s = 0; s < surfaces; s++) {
			Ref<Material> mat;
			if (mi) {
				mat = mi->get_material_override();
				if (mat.is_null())
					mat = mi->get_surface_override_material(s);
				if (mat.is_null())
					mat = mesh->surface_get_material(s);
			} else {
				mat = piece[1];
			}
			Color tint(1, 1, 1, 1);
			Vector2 layer(-1.0, 0.0);
			Variant mid = mat.is_valid() ? Variant((int64_t)mat->get_instance_id()) : Variant((int64_t)0);
			Variant matv = mat;
			if (mat.is_valid() && mat->has_meta("arr")) {   // art.gd's textures: all in one surface
				Vector3 arr = mat->get_meta("arr");
				tint = mat->get_meta("vc_tint");
				layer = Vector2(arr.x, arr.y);
				mid = String("arr") + String::num_int64((int64_t)arr.z);
				matv = Variant();
			}
			Slot &sl = slot_for(key, mid, matv);
			Array a = mi ? mesh_arrays(mesh, s) : Array(piece[0]);
			// Moved into place straight into the buffers (ptrw(): set() is a call into the engine per element).
			// Transform3D::xform is the engine's own inline arithmetic, so the same floats as GDScript's `*`.
			PackedVector3Array verts = a[0];
			PackedVector3Array norms = a[1];
			const int64_t count = verts.size();
			const int64_t vb = sl.v.size();
			sl.v.resize(vb + count);
			Vector3 *vw = sl.v.ptrw() + vb;
			const Vector3 *vr = verts.ptr();
			for (int64_t q = 0; q < count; q++)
				vw[q] = ct.xform(vr[q]);
			const int64_t nb = sl.n.size();
			sl.n.resize(nb + norms.size());
			Vector3 *nw = sl.n.ptrw() + nb;
			const Vector3 *nr = norms.ptr();
			for (int64_t q = 0; q < norms.size(); q++)
				nw[q] = nx.xform(nr[q]);
			sl.uv.append_array(a[2]);
			const int64_t base = sl.c.size();
			sl.c.resize(base + count);
			Color *cw = sl.c.ptrw() + base;
			for (int64_t q = 0; q < count; q++)
				cw[q] = tint;
			if (layer.x >= 0.0) {
				const int64_t b2 = sl.uv2.size();
				sl.uv2.resize(b2 + count);
				Vector2 *lw = sl.uv2.ptrw() + b2;
				for (int64_t q = 0; q < count; q++)
					lw[q] = layer;
			}
		}
		if (mi)
			p_victims.append(mi);
	}
	for (Slot &sl : slots) {
		Array out;
		out.append(sl.v); out.append(sl.n); out.append(sl.uv); out.append(sl.c); out.append(sl.uv2); out.append(sl.mat);
		Dictionary g = p_groups[sl.key];
		g[sl.mid] = out;
	}
}

int MeshMerge::cache_size() {
	std::lock_guard<std::mutex> g(s_lock);
	return s_arrays ? s_arrays->size() : 0;
}

void MeshMerge::clear_cache() {
	std::lock_guard<std::mutex> g(s_lock);
	if (s_arrays) {
		memdelete(s_arrays);
		s_arrays = nullptr;
	}
}


// --- pieces (see Pending) --------------------------------------------------------------------------------

static Variant f32(const Variant &v) {   // (a float as a mesh stores it: the shape keys read back from meshes)
	return v.get_type() == Variant::FLOAT ? Variant((double)(float)(double)v) : v;
}

static Ref<Mesh> mesh_from_key(const Array &k) {   // (the mesh a shape key was read from)
	String kind = k[0];
	if (kind == "B") {
		Ref<BoxMesh> m; m.instantiate(); m->set_size(k[1]); return m;
	} else if (kind == "C") {
		Ref<CylinderMesh> m; m.instantiate();
		m->set_top_radius(k[1]); m->set_bottom_radius(k[2]); m->set_height(k[3]); m->set_radial_segments(k[4]); m->set_rings(k[5]);
		return m;
	} else if (kind == "S") {
		Ref<SphereMesh> m; m.instantiate();
		m->set_radius(k[1]); m->set_height(k[2]); m->set_radial_segments(k[3]); m->set_rings(k[4]); m->set_is_hemisphere(k[5]);
		return m;
	} else if (kind == "T") {
		Ref<TorusMesh> m; m.instantiate();
		m->set_inner_radius(k[1]); m->set_outer_radius(k[2]); m->set_rings(k[3]); m->set_ring_segments(k[4]);
		return m;
	} else if (kind == "P") {
		Ref<PrismMesh> m; m.instantiate(); m->set_size(k[1]); m->set_left_to_right(k[2]); return m;
	}
	ERR_FAIL_V_MSG(Ref<Mesh>(), "MeshMerge: unknown shape " + kind);
}

static Node *scope_of(Node *owner) {   // the open build owner is in, or null
	for (uint64_t id : s_scopes) {
		Node *r = Object::cast_to<Node>(ObjectDB::get_instance(id));
		if (r && (r == owner || r->is_ancestor_of(owner)))
			return r;
	}
	return nullptr;
}

static bool queue(Node *p_node, const Array &p_shape, const Ref<Material> &p_mat, const Transform3D &p_xf) {
	std::lock_guard<std::recursive_mutex> g(s_plock);
	Node3D *p_owner = Object::cast_to<Node3D>(p_node);   // (a mesh under anything else isn't merged: a node)
	if (!s_no_pieces)
		s_no_pieces = memnew(StringName("no_pieces"));
	if (!p_owner || s_scopes.empty() || p_owner->has_meta(*s_no_pieces))
		return false;
	Node *scope = scope_of(p_owner);
	if (!scope)
		return false;
	Array key;
	for (int i = 0; i < p_shape.size(); i++)
		key.append(f32(p_shape[i]));
	Array arrays;
	{
		std::lock_guard<std::mutex> l(s_lock);
		if (s_arrays && s_arrays->has(key))
			arrays = (*s_arrays)[key];
	}
	if (arrays.size() < 4) {   // (not met yet: the mesh made once, as a node would have it)
		Ref<Mesh> m = mesh_from_key(key);
		if (m.is_null())
			return false;
		arrays = mesh_arrays(m, 0);
		std::lock_guard<std::mutex> l(s_lock);
		if (!s_arrays)
			s_arrays = memnew(Dictionary);
		(*s_arrays)[key] = arrays;
	}
	Pending p;
	p.id = s_next_id++;
	p.piece.append(arrays);
	p.piece.append(p_mat);
	p.local = p_xf;
	p.index = p_owner->get_child_count();
	p.anchor = p.index > 0 ? p_owner->get_child(p.index - 1)->get_instance_id() : 0;
	p.scope = scope->get_instance_id();
	p.key = key;
	pending_map()[p_owner->get_instance_id()].push_back(std::move(p));
	return true;
}

bool MeshMerge::piece(Node *p_owner, const Array &p_shape, const Ref<Material> &p_mat, const Vector3 &p_pos, const Vector3 &p_rot, bool p_turned) {
	Transform3D xf;
	if (p_turned) {   // (position, then rotation, set on a Node3D: its transform, to the bit)
		std::lock_guard<std::recursive_mutex> g(s_plock);
		if (!s_scratch)
			s_scratch = memnew(Node3D);
		s_scratch->set_position(p_pos);
		s_scratch->set_rotation(p_rot);
		xf = s_scratch->get_transform();
	} else {
		xf.origin = p_pos;
	}
	return queue(p_owner, p_shape, p_mat, xf);
}

bool MeshMerge::piece_xf(Node *p_owner, const Array &p_shape, const Ref<Material> &p_mat, const Transform3D &p_xf) {
	return queue(p_owner, p_shape, p_mat, p_xf);
}

// Pieces made into real nodes, in place among the owner's children (in the order they were queued).
static void materialize(Node *owner, std::vector<Pending> &ps) {
	std::unordered_map<uint64_t, Node *> last;   // anchor -> the node last put right after it
	for (Pending &p : ps) {
		MeshInstance3D *mi = memnew(MeshInstance3D);
		mi->set_mesh(mesh_from_key(p.key));
		mi->set_material_override(Array(p.piece)[1]);
		mi->set_transform(p.local);
		auto l = last.find(p.anchor);
		Node *after = l != last.end() ? l->second : (p.anchor ? Object::cast_to<Node>(ObjectDB::get_instance(p.anchor)) : nullptr);
		owner->add_child(mi);
		int at;
		if (after && after->get_parent() == owner)
			at = after->get_index() + 1;
		else if (p.anchor == 0 && l == last.end())
			at = 0;
		else
			at = MIN(p.index, owner->get_child_count() - 1);
		owner->move_child(mi, at);
		last[p.anchor] = mi;
	}
}

// The pieces whose owner passes `pick`, out of the queue (dead owners' are dropped), owner by owner.
template <typename F>
static std::vector<std::pair<Node *, std::vector<Pending>>> pull(F pick) {
	std::lock_guard<std::recursive_mutex> g(s_plock);
	std::vector<std::pair<Node *, std::vector<Pending>>> out;
	if (!s_pending)
		return out;
	for (auto it = s_pending->begin(); it != s_pending->end();) {
		Node *owner = Object::cast_to<Node>(ObjectDB::get_instance(it->first));
		if (!owner) {
			it = s_pending->erase(it);
			continue;
		}
		std::vector<Pending> keep, go;
		for (Pending &p : it->second)
			(pick(owner, p) ? go : keep).push_back(std::move(p));
		if (!go.empty())
			out.push_back({ owner, std::move(go) });
		if (keep.empty())
			it = s_pending->erase(it);
		else {
			it->second = std::move(keep);
			++it;
		}
	}
	return out;
}

void MeshMerge::open(Node *p_root) {
	std::lock_guard<std::recursive_mutex> g(s_plock);
	s_scopes.erase(std::remove_if(s_scopes.begin(), s_scopes.end(), [](uint64_t id) { return ObjectDB::get_instance(id) == nullptr; }), s_scopes.end());   // (a build dropped half way never closed)
	if (p_root)
		s_scopes.push_back(p_root->get_instance_id());
}

void MeshMerge::close(Node *p_root) {
	if (!p_root)
		return;
	uint64_t id = p_root->get_instance_id();
	{
		std::lock_guard<std::recursive_mutex> g(s_plock);
		auto f = std::find(s_scopes.begin(), s_scopes.end(), id);
		if (f != s_scopes.end())
			s_scopes.erase(f);
	}
	for (auto &o : pull([id](Node *, const Pending &p) { return p.scope == id; }))
		materialize(o.first, o.second);
}

void MeshMerge::settle(Node *p_root) {
	if (!p_root)
		return;
	for (auto &o : pull([p_root](Node *owner, const Pending &) { return owner == p_root || p_root->is_ancestor_of(owner); }))
		materialize(o.first, o.second);
}

Array MeshMerge::pieces_under(Node *p_node) {
	std::lock_guard<std::recursive_mutex> g(s_plock);
	Array out;
	if (!s_pending || !p_node)
		return out;
	for (auto &e : *s_pending) {
		Node3D *owner = Object::cast_to<Node3D>(ObjectDB::get_instance(e.first));
		if (!owner || !(owner == p_node || p_node->is_ancestor_of(owner)))
			continue;
		Transform3D gt = owner->get_global_transform();
		for (Pending &p : e.second) {
			Array r;
			r.append((int64_t)p.id);
			r.append(owner);
			r.append(Transform3D(mul(gt, p.local)));   // (its global_transform, as a node's)
			r.append(Array(p.piece[0])[3]);
			out.append(r);
		}
	}
	return out;
}

void MeshMerge::drop(int64_t p_id) {
	std::lock_guard<std::recursive_mutex> g(s_plock);
	if (!s_pending)
		return;
	for (auto &e : *s_pending)
		for (size_t q = 0; q < e.second.size(); q++)
			if ((int64_t)e.second[q].id == p_id) {
				e.second.erase(e.second.begin() + q);
				return;
			}
}

int MeshMerge::pending() {
	std::lock_guard<std::recursive_mutex> g(s_plock);
	int n = 0;
	if (s_pending)
		for (auto &e : *s_pending)
			n += (int)e.second.size();
	return n;
}

void MeshMerge::shutdown() {
	clear_cache();
	std::lock_guard<std::recursive_mutex> g(s_plock);
	delete s_pending;
	s_pending = nullptr;
	s_scopes.clear();
	if (s_no_pieces) {
		memdelete(s_no_pieces);
		s_no_pieces = nullptr;
	}
	if (s_scratch) {
		memdelete(s_scratch);
		s_scratch = nullptr;
	}
}

// Nodes about to be freed (facility._clear_holes): pieces that came right after one now come right after
// whatever stood before it, as nodes would close up.
void MeshMerge::forget(const Array &p_nodes) {
	std::lock_guard<std::recursive_mutex> g(s_plock);
	if (!s_pending || s_pending->empty())
		return;
	std::unordered_map<uint64_t, bool> gone;
	for (int i = 0; i < p_nodes.size(); i++) {
		Node *x = Object::cast_to<Node>(p_nodes[i]);
		if (x)
			gone[x->get_instance_id()] = true;
	}
	for (int i = 0; i < p_nodes.size(); i++) {
		Node *x = Object::cast_to<Node>(p_nodes[i]);
		if (!x || !x->get_parent())
			continue;
		Node *par = x->get_parent();
		auto it = s_pending->find(par->get_instance_id());
		if (it == s_pending->end())
			continue;
		uint64_t before = 0;
		for (int k = x->get_index() - 1; k >= 0; k--) {
			uint64_t id = par->get_child(k)->get_instance_id();
			if (!gone.count(id)) {
				before = id;
				break;
			}
		}
		for (Pending &pc : it->second)
			if (pc.anchor == x->get_instance_id())
				pc.anchor = before;
	}
}
