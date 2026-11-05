class_name VideoImport
extends RefCounted
## Godot can only play Ogg Theora video (.ogv): H.264, the usual MP4 video, is
## patented, so it can't be built into the engine. So MP4s and the like get converted
## once, when a creator picks them in an editor, and the game and scraps only ever
## have to read plain .ogv files. Only a file the creator picked in the file dialog
## is ever converted: nothing in a chart or locale can start this.

const OUTPUT_FOLDER := "Lamplight/Videos"
const CONVERTS := ["mp4", "m4v", "mov", "mkv", "webm", "avi"]
const FILTERS := ["*.mp4,*.m4v,*.mov,*.mkv,*.webm,*.avi,*.ogv;Videos"]
const NO_FFMPEG := "Converting MP4s needs ffmpeg installed (ffmpeg.org). Or pick a video that's already .ogv."


static func has_converter() -> bool:
	return OS.execute("ffmpeg", ["-version"]) == 0


static func output_for(source: String) -> String:
	var documents := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var folder := documents.path_join(OUTPUT_FOLDER) if documents != "" else "user://videos"
	DirAccess.make_dir_recursive_absolute(folder)
	return folder.path_join(source.get_file().get_basename() + ".ogv")


## Calls on_done with {"path": the .ogv, "error": ""} once it's ready, on the main thread.
## It runs on a thread, since a long video takes a while.
static func convert_video(source: String, on_done: Callable) -> void:
	if source.get_extension().to_lower() == "ogv":
		on_done.call({"path": source, "error": ""})
		return
	if source.get_extension().to_lower() not in CONVERTS:
		on_done.call({"path": "", "error": "That isn't a video file I can read."})
		return
	var thread := Thread.new()
	var output := output_for(source)
	thread.start(func():
		var args := PackedStringArray(["-y", "-loglevel", "error", "-i", ProjectSettings.globalize_path(source), "-c:v", "libtheora", "-q:v", "7", "-c:a", "libvorbis", "-q:a", "5", ProjectSettings.globalize_path(output)])
		var code := OS.execute("ffmpeg", args) if has_converter() else -1
		var result := {"path": output, "error": ""}
		if code == -1:
			result = {"path": "", "error": NO_FFMPEG}
		elif code != 0 or not FileAccess.file_exists(output):
			result = {"path": "", "error": "ffmpeg couldn't convert %s." % source.get_file()}
		_finish.call_deferred(thread, on_done, result))


static func _finish(thread: Thread, on_done: Callable, result: Dictionary) -> void:
	thread.wait_to_finish()
	on_done.call(result)
