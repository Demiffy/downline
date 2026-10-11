# The build this pack was exported from. tools/export.sh stamps these for the export and
# puts them back afterwards; "dev" means running from the project.
#   SEQ   counts commits, so a bigger one is newer (the updater compares these).
#   BASE  the exe a pack needs. Bump it by hand when project.godot changes (an update pack can't
#         change project settings); players are then told to get the full zip again. An engine
#         upgrade is caught on its own (version.json carries the Godot version).
extends RefCounted

const BUILD := "dev"
const SEQ := 0
const BASE := 1

