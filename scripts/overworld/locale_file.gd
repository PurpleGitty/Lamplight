class_name LocaleFile
extends RefCounted
## .lcal files: a whole overworld in one file, packed just like a scrap (see
## ScrapFile): a zip of scrap.json, locale.json and assets/, nothing in it trusted.

const EXTENSION := "lcal"
const LOCALE := "locale.json"
const LIST_FOLDER := "Lamplight/Locales"

static var last_error := ""
static var last_missing: Array = []


static func is_locale(path: String) -> bool:
	return path.get_extension().to_lower() == EXTENSION


static func folder() -> String:
	if GameSettings.mobile:
		DirAccess.make_dir_recursive_absolute("user://locales")
		return "user://locales"
	var documents := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var path := documents.path_join(LIST_FOLDER) if documents != "" else "user://locales"
	if DirAccess.make_dir_recursive_absolute(path) != OK:
		path = "user://locales"
		DirAccess.make_dir_recursive_absolute(path)
	return path


static func list() -> Array:
	var found := []
	var base := folder()
	for file_name in DirAccess.get_files_at(base):
		if is_locale(file_name):
			found.append(base.path_join(file_name))
	found.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	return found


static func unused_path(base_name: String) -> String:
	var base := folder()
	var path := base.path_join("%s.%s" % [base_name, EXTENSION])
	var number := 2
	while FileAccess.file_exists(path):
		path = base.path_join("%s_%d.%s" % [base_name, number, EXTENSION])
		number += 1
	return path


## Brings a .scrp or .lcal into the game from anywhere the phone's file picker can reach.
## It works out which it is from what's inside, whatever the file's called. Returns where
## it went, or "" (see last_error).
static func import_file(source: String) -> String:
	var data := FileAccess.get_file_as_bytes(source)
	if data.is_empty():
		last_error = "Couldn't read that file."
		return ""
	if data.size() > ScrapFile.MAX_SCRAP_BYTES or not SafeFiles.bytes_match("scrp", data):
		last_error = "That isn't a scrap or overworld file."
		return ""
	var temp := "user://importing.tmp"
	var out := FileAccess.open(temp, FileAccess.WRITE)
	if out == null:
		last_error = "Couldn't save it."
		return ""
	out.store_buffer(data)
	out.close()
	var zip := ZIPReader.new()
	var folder_to := ""
	var extension := ""
	if zip.open(temp) == OK:
		if zip.file_exists(LOCALE):
			folder_to = folder()
			extension = EXTENSION
		elif zip.file_exists(ScrapFile.CHART):
			folder_to = ScrapFile.folder()
			extension = ScrapFile.EXTENSION
		zip.close()
	if folder_to == "":
		DirAccess.remove_absolute(temp)
		last_error = "That isn't a scrap or overworld file."
		return ""
	# Only the file's own name, cleaned up, and never replacing one that's there
	var base := source.uri_decode().get_file().get_basename().validate_filename().left(48)
	if base == "" or base == ".":
		base = "Imported"
	var path := folder_to.path_join("%s.%s" % [base, extension])
	var number := 2
	while FileAccess.file_exists(path):
		path = folder_to.path_join("%s_%d.%s" % [base, number, extension])
		number += 1
	var err := DirAccess.rename_absolute(temp, path)
	if err != OK:
		DirAccess.remove_absolute(temp)
		last_error = "Couldn't save it."
		return ""
	last_error = ""
	return path


## The overworld in a file, ready to play or edit, or {} (see last_error).
static func read(path: String) -> Dictionary:
	if FileAccess.get_size(path) > ScrapFile.MAX_SCRAP_BYTES:
		return _fail("%s is too big." % path.get_file())
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return _fail("%s isn't a locale file, or it's damaged." % path.get_file())
	if not zip.file_exists(LOCALE):
		zip.close()
		return _fail("%s isn't a locale file, or it's damaged." % path.get_file())
	var parsed: Variant = JSON.parse_string(zip.read_file(LOCALE).get_string_from_utf8())
	if not parsed is Dictionary:
		zip.close()
		return _fail("The overworld inside %s is damaged." % path.get_file())
	var cache := ScrapFile._unpack(zip, path)
	zip.close()
	var locale := LocaleDefs.clean(ScrapFile._resolve(ScrapFile._strip_outside_paths(parsed), cache))
	if locale.is_empty():
		return _fail("The overworld inside %s is damaged." % path.get_file())
	last_error = ""
	return locale


## What's needed to list its saves: nothing gets unpacked.
static func peek(path: String) -> Dictionary:
	var zip := ZIPReader.new()
	if FileAccess.get_size(path) > ScrapFile.MAX_SCRAP_BYTES or zip.open(path) != OK or not zip.file_exists(LOCALE):
		return {}
	var parsed: Variant = JSON.parse_string(zip.read_file(LOCALE).get_string_from_utf8())
	zip.close()
	return LocaleDefs.clean(parsed)


static func _fail(message: String) -> Dictionary:
	last_error = message
	return {}


## Saves it and everything it uses as one file. A failed save leaves any existing
## file as it was.
static func write(locale: Dictionary, path: String) -> Error:
	ScrapFile.last_missing = []
	var assets := {}
	var packed: Variant = ScrapFile._collect(locale.duplicate(true), assets)
	last_missing = ScrapFile.last_missing
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temp := path + ".saving"
	var zip := ZIPPacker.new()
	var err := zip.open(temp)
	if err != OK:
		return err
	err = ScrapFile._add(zip, ScrapFile.MANIFEST, JSON.stringify({"format": ScrapFile.FORMAT, "game": "Lamplight"}, "\t").to_utf8_buffer())
	if err == OK:
		err = ScrapFile._add(zip, LOCALE, JSON.stringify(packed).to_utf8_buffer())
	for source in assets:
		if err != OK:
			break
		err = ScrapFile._add(zip, ScrapFile.ASSET_FOLDER + assets[source], FileAccess.get_file_as_bytes(source))
	zip.close()
	if err == OK:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		err = DirAccess.rename_absolute(temp, path)
	if err != OK:
		DirAccess.remove_absolute(temp)
	return err
