# The build version, stamped by tools/export_windows.sh at export time.
# Compared against the remote version.json to decide whether an update is available.
class_name Version
extends RefCounted

const BUILD := "dev"
