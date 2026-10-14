// Mesh merging's heavy part (src/merge.gd keeps the rest: when, the pauses, the new nodes): finding every
// mesh under a node that can be merged, and moving each one's vertices into place in the buffers of the
// chunk, shadow setting and material it falls in. The arithmetic is the engine's own (its
// operators, Transform3D::xform inline, no fused multiply-adds: SConstruct), so the merged meshes come out
// bit for bit as GDScript's (tests/merge_native.gd); what's saved is GDScript's overhead per piece.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/classes/material.hpp>

namespace godot {

class MeshMerge : public RefCounted {
	GDCLASS(MeshMerge, RefCounted)

protected:
	static void _bind_methods();

public:
	// [[MeshInstance3D, Transform3D under root], ...]: every mesh under root that can be merged.
	static Array gather(Node3D *p_root);
	// Each item's surfaces added to groups ("cx,cy,cz|shadow" -> {material id: [verts, normals, uvs,
	// colours, uv2s, material]}), the item appended to victims.
	static void take(const Array &p_items, double p_chunk, bool p_indoors, Dictionary p_groups, Array p_victims);
	static int cache_size();
	// Pieces (mesh_merge.cpp, Pending): meshes merged straight from art.gd's s-primitives, no node.
	static void open(Node *p_root);
	static void close(Node *p_root);
	static bool piece(Node *p_owner, const Array &p_shape, const Ref<Material> &p_mat, const Vector3 &p_pos, const Vector3 &p_rot, bool p_turned);
	static bool piece_xf(Node *p_owner, const Array &p_shape, const Ref<Material> &p_mat, const Transform3D &p_xf);
	static void settle(Node *p_root);
	static Array pieces_under(Node *p_node);
	static void drop(int64_t p_id);
	static int pending();
	static void forget(const Array &p_nodes);
	static void shutdown();   // (the extension unloading: everything held let go)
	static void clear_cache();
};

} // namespace godot
