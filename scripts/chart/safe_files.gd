class_name SafeFiles
extends RefCounted
## The one gate every sprite, sound and font goes through, because charts and scraps
## come from other people. Godot's load() can run scripts hidden in a resource file,
## so it's only ever used on the game's own files. Everything else has to be a plain
## media file: the right extension, the right bytes at the start, and a path on this
## PC. It's then decoded as an image, sound or font and nothing else.

const IMAGES := ["png", "jpg", "jpeg", "webp"]
const SOUNDS := ["mp3", "ogg", "wav"]
const FONTS := ["ttf", "otf", "woff", "woff2"]
const VIDEOS := ["ogv"] # the only video Godot can play; MP4s get converted (see VideoImport)
const GAME_FONTS := FONTS + ["tres"] # the game's own fonts include a few .tres variations
const SCRAPS := ["scrp"] # a fight inside a locale; read by ScrapFile, not run
const ALL := IMAGES + SOUNDS + FONTS + VIDEOS + SCRAPS
const MAX_IMAGE_SIDE := 16384 # bigger than any graphics card takes, and a way to eat memory
const HEAD_BYTES := 32 # enough to recognise any of these files


## One of the game's own files, safe to give to load().
static func is_game_file(path: String, types: Array) -> bool:
	return path.begins_with("res://") and not path.contains("..") \
		and path.get_extension().to_lower() in types and ResourceLoader.exists(path)


## A real media file of one of these types, safe to decode directly.
static func is_media_file(path: String, types: Array) -> bool:
	if not is_local_path(path):
		return false
	var type := path.get_extension().to_lower()
	if type not in types or not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	return file != null and bytes_match(type, file.get_buffer(HEAD_BYTES))


## On this PC: not on a network, not relative, no climbing out of a folder.
static func is_local_path(path: String) -> bool:
	var clean := path.replace("\\", "/")
	if clean == "" or clean.begins_with("//") or clean.contains(".."):
		return false
	if clean.begins_with("res://") or clean.begins_with("user://"):
		return not clean.get_slice("://", 1).contains(":")
	if clean.contains("://"):
		return false
	# C:/folder/file.png. Any other colon is a Windows hidden data stream.
	var is_drive := clean.length() > 2 and clean[1] == ":" and clean[2] == "/" and clean[0].to_lower() >= "a" and clean[0].to_lower() <= "z"
	if is_drive:
		return not clean.substr(2).contains(":")
	return clean.begins_with("/") and not clean.contains(":")


## Whether a file's first bytes really are this type, whatever it's named.
static func bytes_match(type: String, data: PackedByteArray) -> bool:
	match type:
		"png":
			return _starts(data, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) and _png_size_ok(data)
		"jpg", "jpeg":
			return _starts(data, [0xFF, 0xD8, 0xFF])
		"webp":
			return _text_at(data, 0, "RIFF") and _text_at(data, 8, "WEBP")
		"wav":
			return _text_at(data, 0, "RIFF") and _text_at(data, 8, "WAVE")
		"ogg", "ogv":
			return _text_at(data, 0, "OggS")
		"scrp":
			return _text_at(data, 0, "PK")
		"mp3":
			return _text_at(data, 0, "ID3") or (data.size() > 1 and data[0] == 0xFF and data[1] & 0xE0 == 0xE0)
		"ttf":
			return _starts(data, [0, 1, 0, 0]) or _text_at(data, 0, "true")
		"otf":
			return _text_at(data, 0, "OTTO") or _starts(data, [0, 1, 0, 0])
		"woff":
			return _text_at(data, 0, "wOFF")
		"woff2":
			return _text_at(data, 0, "wOF2")
	return false


static func _starts(data: PackedByteArray, expected: Array) -> bool:
	if data.size() < expected.size():
		return false
	for i in expected.size():
		if data[i] != expected[i]:
			return false
	return true


static func _text_at(data: PackedByteArray, at: int, text: String) -> bool:
	var wanted := text.to_ascii_buffer()
	if data.size() < at + wanted.size():
		return false
	for i in wanted.size():
		if data[at + i] != wanted[i]:
			return false
	return true


## A PNG says how big it is near the start, before anything has to be decoded.
static func _png_size_ok(data: PackedByteArray) -> bool:
	if data.size() < 24:
		return false
	var width := (data[16] << 24) | (data[17] << 16) | (data[18] << 8) | data[19]
	var height := (data[20] << 24) | (data[21] << 16) | (data[22] << 8) | data[23]
	return width > 0 and height > 0 and width <= MAX_IMAGE_SIDE and height <= MAX_IMAGE_SIDE
