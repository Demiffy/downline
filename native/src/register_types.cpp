// The game's C++ classes, registered with Godot when the extension loads (bin/downline.gdextension).
#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/core/class_db.hpp>
#include "mesh_merge.h"

using namespace godot;

static void initialize(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE)
		return;
	GDREGISTER_CLASS(MeshMerge);
}

static void uninitialize(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE)
		return;
	MeshMerge::shutdown();
}

extern "C" GDExtensionBool GDE_EXPORT downline_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize);
	init_obj.register_terminator(uninitialize);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
