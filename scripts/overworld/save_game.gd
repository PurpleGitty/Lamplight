class_name SaveGame
extends RefCounted
## Save files for overworlds: three slots and an autosave, per overworld, kept in
## user://saves. They're plain JSON holding only numbers and names, and everything's
## checked when read. The folder's named by a hash, so nothing in a locale file can
## choose where a save goes.

const AUTOSAVE_SLOT := 0
const SLOTS := [1, 2, 3]
const FOLDER := "user://saves/"
const VERSION := 1


static func _key(locale: Dictionary) -> String:
	var id := str(locale.get("save_id", ""))
	if id == "":
		# From before overworlds had an id: as steady as an older file can manage
		id = ",".join(locale["rooms"].map(func(r): return "%s:%s" % [r["id"], r["name"]]))
	return id.md5_text()


static func _path(locale: Dictionary, slot: int) -> String:
	return "%s%s/slot%d.json" % [FOLDER, _key(locale), slot]


static func write(locale: Dictionary, slot: int, state: Dictionary) -> Error:
	var path := _path(locale, slot)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var saved := state.duplicate(true)
	saved["version"] = VERSION
	saved["saved_at"] = Time.get_unix_time_from_system()
	# Written beside it first, so a crash halfway can't ruin an existing save
	var temp := path + ".saving"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(saved))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temp, path)


## A slot's contents, checked over, or {} if it's empty or damaged.
static func read(locale: Dictionary, slot: int) -> Dictionary:
	var path := _path(locale, slot)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	var raw: Dictionary = parsed
	var state := {
		"room": int(_number(raw, "room")), "x": _number(raw, "x"), "y": _number(raw, "y"),
		"facing": str(raw.get("facing", "down")), "seconds": _number(raw, "seconds"), "saved_at": _number(raw, "saved_at"),
		"room_name": str(raw.get("room_name", "")), "flags": {}, "items": {}, "done": {}, "shown": {}, "rules": {}, "party_hp": {},
	}
	if state["facing"] not in LocaleDefs.DIRECTIONS:
		state["facing"] = "down"
	for key in _dictionary(raw, "flags"):
		state["flags"][str(key)] = _number(raw["flags"], key)
	for key in _dictionary(raw, "party_hp"):
		state["party_hp"][str(key)] = int(_number(raw["party_hp"], key))
	for key in _dictionary(raw, "items"):
		state["items"][int(key)] = int(_number(raw["items"], key))
	for key in _dictionary(raw, "done"):
		state["done"][int(key)] = true
	for key in _dictionary(raw, "shown"):
		state["shown"][int(key)] = raw["shown"][key] == true
	for def in LocaleDefs.RULE_PARAMS:
		var rules := _dictionary(raw, "rules")
		if rules.has(def["name"]) and typeof(rules[def["name"]]) == typeof(_json_shape(def["default"])):
			state["rules"][def["name"]] = int(rules[def["name"]]) if def["type"] == "int" else rules[def["name"]]
	return state


## JSON reads every number as a float.
static func _json_shape(value: Variant) -> Variant:
	return float(value) if value is int else value


static func _number(from: Dictionary, key: Variant) -> float:
	var value: Variant = from.get(key, 0.0)
	return float(value) if (value is float or value is int) and is_finite(float(value)) else 0.0


static func _dictionary(from: Dictionary, key: String) -> Dictionary:
	var value: Variant = from.get(key)
	return value if value is Dictionary else {}


static func has_any(locale: Dictionary) -> bool:
	return latest(locale) >= 0


## The slot saved to most recently, or -1 if there are none.
static func latest(locale: Dictionary) -> int:
	var best := -1
	var when := -1.0
	for slot in [AUTOSAVE_SLOT] + SLOTS:
		var state := read(locale, slot)
		if not state.is_empty() and state["saved_at"] > when:
			when = state["saved_at"]
			best = slot
	return best


## A slot in words, for lists.
static func describe(locale: Dictionary, slot: int) -> String:
	var name_of := "AUTOSAVE" if slot == AUTOSAVE_SLOT else "SLOT %d" % slot
	var state := read(locale, slot)
	if state.is_empty():
		return "%s: EMPTY" % name_of
	var seconds := int(state["seconds"])
	return "%s: %s  %d:%02d" % [name_of, str(state["room_name"]).to_upper(), seconds / 60, seconds % 60]
