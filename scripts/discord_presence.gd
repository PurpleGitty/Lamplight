class_name DiscordPresence
extends Node
## Shows what you're up to on your Discord profile: making scraps or locales, or which
## scrap or locale you're playing and how far into its song you are. It talks straight to
## the Discord app on this computer through its local pipe, so there's nothing extra to
## install, and if Discord isn't open it just keeps quietly checking every so often.
## Windows only: that's the only place Godot can open Discord's connection.

## The Discord application this shows up as ("Playing Lamplight"), with its icon. Made
## at discord.com/developers/applications. Blank turns the whole thing off. Not a secret:
## every status shows it.
const CLIENT_ID := "1574471430048055316"
const RETRY_SECONDS := 15.0
## Discord allows 5 updates every 20 seconds.
const MIN_GAP_SECONDS := 4.0
## How far the song can drift from the last update before it's sent again.
const DRIFT_SECONDS := 2.0

var _thread: Thread
var _mutex := Mutex.new()
var _wake := Semaphore.new()
# Shared with the thread, behind _mutex
var _outgoing: Variant = null # the activity to send next; null clears it
var _has_outgoing := false
var _connected := false
var _quitting := false
# Main thread only
var _shown_key := ""
var _shown_start := 0.0
var _last_send := -100.0
var _check_in := 0.0
var _retry_in := 0.0


static func supported() -> bool:
	return CLIENT_ID != "" and OS.get_name() == "Windows"


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS # pausing should say so, not freeze it
	_thread = Thread.new()
	_thread.start(_run)


func _exit_tree() -> void:
	_mutex.lock()
	_quitting = true
	_mutex.unlock()
	_wake.post()
	_thread.wait_to_finish()


# --- what to show ---

func _process(delta: float) -> void:
	_check_in -= delta
	_retry_in -= delta
	if _check_in > 0.0:
		return
	_check_in = 1.0
	var activity: Variant = _activity() if GameSettings.values["discord_status"] else null
	var key := ""
	var start := 0.0
	if activity != null:
		var plain: Dictionary = activity.duplicate(true)
		if plain.has("timestamps"):
			start = float(plain["timestamps"]["start"]) / 1000.0
			plain.erase("timestamps")
			plain["timed"] = true
		key = JSON.stringify(plain)
	var changed := key != _shown_key or absf(start - _shown_start) > DRIFT_SECONDS
	_mutex.lock()
	var connected := _connected
	_mutex.unlock()
	# Discord might have been opened since: try again now and then
	if not connected and activity != null and _retry_in <= 0.0:
		changed = true
	if not changed or Time.get_ticks_msec() / 1000.0 - _last_send < MIN_GAP_SECONDS:
		return
	_shown_key = key
	_shown_start = start
	_last_send = Time.get_ticks_msec() / 1000.0
	_retry_in = RETRY_SECONDS
	_mutex.lock()
	_outgoing = activity
	_has_outgoing = true
	_mutex.unlock()
	_wake.post()


## What the player's doing right now, as a Discord activity.
func _activity() -> Variant:
	var scene := get_tree().current_scene
	if scene == null:
		return _make("In the menus")
	match scene.scene_file_path:
		"res://editor/attack_editor.tscn":
			return _make("Making scraps")
		"res://editor/locale_editor.tscn":
			return _make("Making locales")
	if scene is Battle:
		var battle: Battle = scene
		var conductor: Conductor = battle.conductor
		var playing := conductor != null and conductor.playing and not get_tree().paused
		var song_at := conductor.song_position if playing else -1.0
		if Battle.tutorial:
			return _make("Learning the ropes", "In the tutorial" if not get_tree().paused else "Paused")
		if Battle.return_scene != "" and Overworld.locale_to_play != "":
			return _make("Exploring " + _file_title(Overworld.locale_to_play), "In a fight" if playing else "Paused", song_at)
		var what := "Playing " + _file_title(Battle.chart_to_play) if Battle.chart_to_play != "" else "In a fight"
		return _make(what, _enemy_names(battle) if playing else "Paused", song_at)
	if scene is Overworld:
		var overworld: Overworld = scene
		var music := overworld.music
		var song_at := -1.0
		if music.playing and not music.stream_paused and not get_tree().paused:
			song_at = music.get_playback_position()
		var where := str(overworld.room.get("name", "")) if overworld.room is Dictionary else ""
		return _make("Exploring " + _file_title(Overworld.locale_to_play), where if not get_tree().paused else "Paused", song_at)
	return _make("In the menus")


func _make(details: String, state := "", song_at := -1.0) -> Dictionary:
	var activity := {"details": _fit(details)} # the picture is the Discord app's own icon
	if state != "":
		activity["state"] = _fit(state)
	if song_at >= 0.0:
		# Discord counts up from here by itself, so it shows the song's time
		activity["timestamps"] = {"start": int((Time.get_unix_time_from_system() - song_at) * 1000.0)}
	return activity


## Discord turns down text under 2 or over 128 characters.
static func _fit(text: String) -> String:
	text = text.strip_edges()
	if text.length() < 2:
		text = (text + "  ").left(2)
	return text.left(128)


static func _file_title(path: String) -> String:
	var title := path.get_file().get_basename()
	return title if title != "" else "a locale"


static func _enemy_names(battle: Battle) -> String:
	var names := []
	for enemy in battle.enemies:
		if is_instance_valid(enemy) and enemy.display_name != "" and not names.has(enemy.display_name):
			names.append(enemy.display_name)
	return "vs " + ", ".join(names) if not names.is_empty() else ""


# --- talking to Discord, on its own thread so a slow reply never stalls the game ---

func _run() -> void:
	var pipe: FileAccess = null
	var nonce := 0
	while true:
		_wake.wait()
		_mutex.lock()
		var quitting := _quitting
		var has := _has_outgoing
		var activity: Variant = _outgoing
		_has_outgoing = false
		_mutex.unlock()
		if quitting:
			break
		if not has:
			continue
		if pipe == null:
			pipe = _open()
		var sent := false
		if pipe != null:
			nonce += 1
			var args := {"pid": OS.get_process_id(), "activity": activity}
			sent = _send(pipe, 1, {"cmd": "SET_ACTIVITY", "args": args, "nonce": str(nonce)}) and _reply(pipe) != null
			if not sent:
				pipe.close()
				pipe = null
		_mutex.lock()
		_connected = sent
		_mutex.unlock()
	if pipe != null:
		pipe.close() # Discord takes the status down when the game's gone


## Discord's open connection, said hello to, or null if it isn't running.
func _open() -> FileAccess:
	for i in 10:
		var pipe := FileAccess.open("\\\\?\\pipe\\discord-ipc-%d" % i, FileAccess.READ_WRITE)
		if pipe == null:
			continue
		if _send(pipe, 0, {"v": 1, "client_id": CLIENT_ID}):
			var hello: Variant = _reply(pipe)
			if hello is Dictionary and hello.get("evt") == "READY":
				return pipe
		pipe.close()
	return null


## One message: what kind it is, how long, then the JSON.
func _send(pipe: FileAccess, op: int, body: Dictionary) -> bool:
	var data := JSON.stringify(body).to_utf8_buffer()
	var head := PackedByteArray()
	head.resize(8)
	head.encode_u32(0, op)
	head.encode_u32(4, data.size())
	pipe.store_buffer(head + data)
	pipe.flush()
	return pipe.get_error() == OK


## Discord's answer, or null if the connection's gone or it said no.
func _reply(pipe: FileAccess) -> Variant:
	var head := pipe.get_buffer(8)
	if head.size() < 8:
		return null
	var op := head.decode_u32(0)
	var size := head.decode_u32(4)
	if size > 65536:
		return null
	var body: Variant = JSON.parse_string(pipe.get_buffer(size).get_string_from_utf8())
	if op != 1 or not body is Dictionary or body.get("evt") == "ERROR":
		return null
	return body
