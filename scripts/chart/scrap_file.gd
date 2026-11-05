class_name ScrapFile
extends RefCounted
## .scrp ("scrap") files: one fight in one file, ready to pass around. A scrap is
## a zip holding scrap.json (what kind of file this is), chart.json (the fight)
## and assets/ (every sprite, sound and song the fight uses).
##
## Inside a scrap the chart points at its assets as "scrap://name.png". Reading
## one unpacks the assets to a cache and points the chart at those, so the rest of
## the game just sees a normal chart with normal file paths.
##
## Scraps come from other people, so nothing in one is trusted: only real sprite,
## sound and font files are unpacked (see SafeFiles), only into the cache, and a
## chart can't point at files elsewhere on the PC or on a network.

const EXTENSION := "scrp"
const FORMAT := 1
const MANIFEST := "scrap.json"
const CHART := "chart.json"
const ASSET_FOLDER := "assets/"
const ASSET_PREFIX := "scrap://"
const CACHE := "user://scrap_cache/"
const CACHE_DONE := ".done"
const ASSET_TYPES := SafeFiles.ALL
const MAX_SCRAP_BYTES := 1 << 30 # 1 GB: far more than a fight needs
const NOT_PATHS := ["text", "formula"] # words and maths, which can look like a path by accident
const LIST_FOLDER := "Lamplight/Scraps"

## Why the last read failed, in words for the player.
static var last_error := ""
## Files the last write couldn't find, so they aren't in the scrap.
static var last_missing: Array = []


static func is_scrap(path: String) -> bool:
	return path.get_extension().to_lower() == EXTENSION


## Where scraps live: a folder in Documents that's easy to find and drop files into.
static func folder() -> String:
	var documents := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var path := documents.path_join(LIST_FOLDER) if documents != "" else "user://scraps"
	if DirAccess.make_dir_recursive_absolute(path) != OK:
		path = "user://scraps"
		DirAccess.make_dir_recursive_absolute(path)
	return path


## Every scrap in the folder, sorted by name.
static func list() -> Array:
	var found := []
	var base := folder()
	for file_name in DirAccess.get_files_at(base):
		if is_scrap(file_name):
			found.append(base.path_join(file_name))
	found.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	return found


## A path for a new file that doesn't overwrite one that's already there.
static func unused_path(base_name: String) -> String:
	var base := folder()
	var path := base.path_join("%s.%s" % [base_name, EXTENSION])
	var number := 2
	while FileAccess.file_exists(path):
		path = base.path_join("%s_%d.%s" % [base_name, number, EXTENSION])
		number += 1
	return path


# --- reading ---

## The fight in a scrap, ready to play or edit, or {} (see last_error).
static func read(path: String) -> Dictionary:
	var zip := ZIPReader.new()
	if _too_big(path) or zip.open(path) != OK:
		return _fail("%s isn't a scrap file, or it's damaged." % path.get_file())
	var chart := _read_chart(zip, path)
	if not chart.is_empty():
		var cache := _unpack(zip, path)
		chart = _resolve(chart, cache)
	zip.close()
	return chart


## Just the fight's details, for showing it in a list: nothing gets unpacked.
static func peek(path: String) -> Dictionary:
	var zip := ZIPReader.new()
	if _too_big(path) or zip.open(path) != OK:
		return _fail("%s isn't a scrap file, or it's damaged." % path.get_file())
	var chart := _read_chart(zip, path)
	zip.close()
	return chart


static func _too_big(path: String) -> bool:
	return FileAccess.get_size(path) > MAX_SCRAP_BYTES


static func _read_chart(zip: ZIPReader, path: String) -> Dictionary:
	if not zip.file_exists(MANIFEST) or not zip.file_exists(CHART):
		return _fail("%s isn't a scrap file, or it's damaged." % path.get_file())
	var manifest = JSON.parse_string(zip.read_file(MANIFEST).get_string_from_utf8())
	if not manifest is Dictionary or not manifest.get("format") is float:
		return _fail("%s isn't a scrap file, or it's damaged." % path.get_file())
	if manifest["format"] > FORMAT:
		return _fail("%s was made by a newer version of the game." % path.get_file())
	var parsed = JSON.parse_string(zip.read_file(CHART).get_string_from_utf8())
	if not _well_formed(parsed):
		return _fail("The fight inside %s is damaged." % path.get_file())
	var chart := ChartDefs.parse_chart(JSON.stringify(_strip_outside_paths(parsed)))
	if chart.is_empty():
		return _fail("The fight inside %s is damaged." % path.get_file())
	last_error = ""
	return chart


static func _fail(message: String) -> Dictionary:
	last_error = message
	return {}


## Checks the shape parse_chart relies on, so a bad file is refused rather than
## breaking halfway through a fight.
static func _well_formed(chart: Variant) -> bool:
	if not chart is Dictionary:
		return false
	for key in ["turn_events", "text_events", "meta_events", "board_events", "party", "enemies", "objects"]:
		if chart.has(key) and not chart[key] is Array:
			return false
	if chart.has("rules") and not chart["rules"] is Dictionary:
		return false
	for key in ["turn_events", "text_events", "meta_events", "board_events"]:
		if not _events_ok(chart.get(key, [])):
			return false
	for key in ["party", "enemies"]:
		for entry in chart.get(key, []):
			if not entry is Dictionary:
				return false
	for obj in chart.get("objects", []):
		if not obj is Dictionary or not obj.get("id") is float or not obj.get("events") is Array:
			return false
		if not _events_ok(obj["events"]):
			return false
	return true


static func _events_ok(events: Array) -> bool:
	for ev in events:
		if not ev is Dictionary or not ev.get("type") is String:
			return false
		if not ev.get("id") is float or not ev.get("beat") is float:
			return false
		if not ev.get("params", {}) is Dictionary:
			return false
	return true


## Blanks anything pointing outside the scrap and the game's own files.
static func _strip_outside_paths(value: Variant) -> Variant:
	if value is String:
		return "" if _points_outside(value) else value
	if value is Array:
		return value.map(func(item): return _strip_outside_paths(item))
	if value is Dictionary:
		var clean := {}
		for key in value:
			clean[key] = value[key] if key in NOT_PATHS else _strip_outside_paths(value[key])
		return clean
	return value


static func _points_outside(text: String) -> bool:
	var clean := text.replace("\\", "/").to_lower()
	if clean.begins_with("//") or clean.begins_with("user:") or clean.begins_with("uid:") or clean.begins_with("file:"):
		return true
	if clean.begins_with("res:") and clean.contains(".."):
		return true
	# C:/... or C:file, or /file on the current drive, or climbing out of a folder
	if clean.length() > 1 and clean[1] == ":":
		return true
	return text.get_extension() != "" and (clean.begins_with("/") or clean.begins_with("../"))


## Unpacks a scrap's assets. Same contents, same cache folder, so opening a scrap
## twice is instant and a changed one never shows old files.
static func _unpack(zip: ZIPReader, path: String) -> String:
	var cache := CACHE + FileAccess.get_md5(path) + "/"
	if FileAccess.file_exists(cache + CACHE_DONE):
		return cache
	DirAccess.make_dir_recursive_absolute(cache)
	for entry in zip.get_files():
		if not _safe_asset(entry):
			continue
		var data := zip.read_file(entry)
		if not SafeFiles.bytes_match(entry.get_extension().to_lower(), data):
			continue # named like a sprite or sound, but it isn't one
		var out := FileAccess.open(cache + entry.get_file(), FileAccess.WRITE)
		if out:
			out.store_buffer(data)
	var done := FileAccess.open(cache + CACHE_DONE, FileAccess.WRITE)
	if done:
		done.store_string("ok")
	return cache


## Only plain sprite, sound and font files sitting directly in assets/ get unpacked.
static func _safe_asset(entry: String) -> bool:
	if not entry.begins_with(ASSET_FOLDER) or entry.contains("\\") or entry.contains(":"):
		return false
	var file_name := entry.trim_prefix(ASSET_FOLDER)
	if file_name == "" or file_name.contains("/") or file_name.begins_with("."):
		return false
	return file_name.get_extension().to_lower() in ASSET_TYPES


static func _resolve(value: Variant, cache: String) -> Variant:
	if value is String:
		if not value.begins_with(ASSET_PREFIX):
			return value
		var file_name: String = value.trim_prefix(ASSET_PREFIX).get_file()
		var local := cache + file_name
		return local if FileAccess.file_exists(local) else ""
	if value is Array:
		return value.map(func(item): return _resolve(item, cache))
	if value is Dictionary:
		for key in value:
			value[key] = _resolve(value[key], cache)
	return value


## Clears out unpacked files. The menu calls this, when nothing is using them.
static func clear_cache() -> void:
	# (a fight's scraps and a locale's assets are in here; the menu's only called when neither's open)
	ChartDefs.forget_loaded_files()
	if not DirAccess.dir_exists_absolute(CACHE):
		return
	for sub in DirAccess.get_directories_at(CACHE):
		var dir := CACHE + sub + "/"
		for file_name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir + file_name)
		DirAccess.remove_absolute(dir)


# --- writing ---

## Saves a fight and everything it uses as one file. A failed save leaves any
## existing file as it was.
static func write(chart: Dictionary, path: String) -> Error:
	last_missing = []
	var assets := {} # where the file is now -> its name in the scrap
	var packed: Variant = _collect(chart.duplicate(true), assets)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temp := path + ".saving"
	var zip := ZIPPacker.new()
	var err := zip.open(temp)
	if err != OK:
		return err
	err = _add(zip, MANIFEST, JSON.stringify({"format": FORMAT, "game": "Lamplight"}, "\t").to_utf8_buffer())
	if err == OK:
		err = _add(zip, CHART, JSON.stringify(packed, "\t").to_utf8_buffer())
	for source in assets:
		if err != OK:
			break
		err = _add(zip, ASSET_FOLDER + assets[source], FileAccess.get_file_as_bytes(source))
	zip.close()
	if err == OK:
		err = DirAccess.rename_absolute(temp, path)
	if err != OK:
		DirAccess.remove_absolute(temp)
	return err


static func _add(zip: ZIPPacker, entry: String, data: PackedByteArray) -> Error:
	var err := zip.start_file(entry)
	if err != OK:
		return err
	err = zip.write_file(data)
	zip.close_file()
	return err


## Finds every asset the chart uses, wherever it's mentioned, and swaps its path
## for its name in the scrap. Assets only built into the game stay as they are.
static func _collect(value: Variant, assets: Dictionary) -> Variant:
	if value is String:
		return _pack_path(value, assets)
	if value is Array:
		return value.map(func(item): return _collect(item, assets))
	if value is Dictionary:
		for key in value:
			value[key] = _collect(value[key], assets)
	return value


static func _pack_path(text: String, assets: Dictionary) -> String:
	if not text.is_absolute_path() or text.get_extension().to_lower() not in ASSET_TYPES:
		return text
	if not FileAccess.file_exists(text):
		if not text.begins_with("res://"):
			last_missing.append(text)
		return text
	if not assets.has(text):
		assets[text] = _unused_name(text.get_file(), assets)
	return ASSET_PREFIX + assets[text]


static func _unused_name(file_name: String, assets: Dictionary) -> String:
	var used := assets.values().map(func(n): return n.to_lower())
	var candidate := file_name
	var number := 2
	while candidate.to_lower() in used:
		candidate = "%s_%d.%s" % [file_name.get_basename(), number, file_name.get_extension()]
		number += 1
	return candidate
