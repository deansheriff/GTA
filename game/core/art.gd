class_name Art
extends RefCounted
## Painted art (generated, see docs/art/PROVENANCE.md) with a graceful fallback: every caller keeps
## its code-drawn placeholder when a texture is missing, so the game always runs.

static var _cache := {}


static func tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var full := "res://art/" + path
	var t: Texture2D = load(full) if ResourceLoader.exists(full) else null
	_cache[path] = t
	return t


static func sheet_info(path: String) -> Dictionary:
	var full := "res://art/" + path.trim_suffix(".png") + ".json"
	if not FileAccess.file_exists(full):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(full))
	return parsed if parsed is Dictionary else {}
