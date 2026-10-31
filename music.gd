extends ColorRect

# --- SONG CONFIGURATION (Phonky Tribu) ---
const BPM = 160.0
const BEAT_DURATION = 60.0 / BPM # Exactly 0.375 seconds per beat
const TOTAL_SONG_SECONDS = 286.0 # 4 minutes * 60 + 46 seconds

var time_left = TOTAL_SONG_SECONDS:
	set(value):
		time_left = clamp(value, 0.0, TOTAL_SONG_SECONDS)
		update_clock_display()
		if time_left <= 0:
			trigger_time_out_loss()

var beat_timer = 0.0

@onready var clock_label = $"timerbox/time left"
@onready var energy_bar = $"energybox/current energy"

func _process(delta: float) -> void:
	if time_left > 0:
		time_left -= delta
		handle_bpm_pulses(delta)

func handle_bpm_pulses(delta: float):
	beat_timer += delta
	if beat_timer >= BEAT_DURATION:
		beat_timer -= BEAT_DURATION
		on_musical_beat()

func on_musical_beat():
	# This function triggers EXACTLY 160 times a minute!
	# Pulse the energy bar container or text box slightly on the beat
	var pulse_tween = create_tween()
	var ui_box = $"."
	
	# Scale up slightly on the hit, then drop back down instantly
	ui_box.scale = Vector2(1.03, 1.03)
	pulse_tween.tween_property(ui_box, "scale", Vector2(1.0, 1.0), BEAT_DURATION * 0.5)


func update_clock_display():
	var minutes = int(time_left) / 60
	var seconds = int(time_left) % 60
	
	# Use standard digital clock formatting
	clock_label.text = "%02d:%02d" % [minutes, seconds]

func trigger_time_out_loss():
	print("Song ended! Instantly losing match.")
	$"../purple".hp = 0
	$"../violet".hp = 0
