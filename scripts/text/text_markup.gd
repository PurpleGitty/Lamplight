class_name TextMarkup
extends RefCounted
## Lamplight's text formatting for dialogue, flavor text and status messages.
## Written BBCode-style (the attack editor's text editor adds the tags for you):
##
##   [wave]...[/wave]       wavy letters          [shake]...[/shake]  shaky letters
##   [swirl]...[/swirl]     letters circle        [rainbow]...        colour cycling
##   [astral]...[/astral]   each letter shakes as it appears, with faint shaking
##                          copies behind it, then settles into normal text
##   [pulse]...[/pulse]     flashing              [color=#ff4040]...  coloured
##   [tiny]...[/tiny]       small text            [big]...[/big]      large text
##   [spaced]...[/spaced]   letters spread out    [u] underline   [s] strikethrough
##   [time=1.5]...[/time]   this part takes 1.5 seconds to type (0 = appears at once)
##   [quiet]...[/quiet]     no typing blips
##   [pause=0.5]            wait half a second here before typing on
##   [lb] [rb]              a literal [ or ]
##
## Tags can be nested. Unknown tags are shown as plain text.

const TAGS := ["astral", "wave", "shake", "swirl", "rainbow", "pulse", "color", "tiny", "big", "spaced", "u", "s", "time", "quiet"]
const TINY_FONT = preload("res://fonts/PixelOperator8.ttf")
const QUIET_CHARS := " \n.,!?*-'\""

## Shakes letters briefly as they appear. On the ghost copies it also fades
## them out, and hides them for good once the letter has settled.
class AstralEffect extends RichTextEffect:
	const SETTLE_TIME := 0.45
	var writer # the Typewriter, for the clock
	var times: PackedFloat32Array # when each letter of the whole text appears
	var first := 0 # this run's first letter in `times`
	var ghost := false

	func _process_custom_fx(fx: CharFXTransform) -> bool:
		var i: int = mini(first + fx.relative_index, times.size() - 1)
		var age: float = (writer.elapsed - times[i]) if writer else INF
		var left := 1.0 - clampf(age / SETTLE_TIME, 0.0, 1.0)
		if age < 0.0 or left <= 0.0:
			if ghost:
				fx.color.a = 0.0
			return true
		var reach := (5.0 if ghost else 2.0) * left
		fx.offset += Vector2(randf_range(-reach, reach), randf_range(-reach, reach))
		if ghost:
			fx.color.a *= 0.4 * left
		return true


## One run of text with the same formatting.
class Segment:
	var text := ""
	var mods := {} # tag -> value ("" when the tag has no value)
	var pause_before := 0.0


static func parse(markup: String) -> Array:
	var segments := []
	var stack := [] # [[tag, value], ...] currently open
	var buffer := ""
	var pause := 0.0
	var i := 0
	while i < markup.length():
		var c := markup[i]
		var close := markup.find("]", i) if c == "[" else -1
		if close == -1:
			buffer += c
			i += 1
			continue
		var tag := markup.substr(i + 1, close - i - 1)
		var name := tag.trim_prefix("/").get_slice("=", 0).strip_edges().to_lower()
		var value := tag.get_slice("=", 1).strip_edges() if "=" in tag else ""
		if tag == "lb" or tag == "rb":
			buffer += "[" if tag == "lb" else "]"
		elif name == "pause" and not tag.begins_with("/"):
			if _flush(segments, buffer, stack, pause):
				pause = 0.0
			buffer = ""
			pause += value.to_float()
		elif name in TAGS:
			if _flush(segments, buffer, stack, pause):
				pause = 0.0
			buffer = ""
			if tag.begins_with("/"):
				for k in range(stack.size() - 1, -1, -1):
					if stack[k][0] == name:
						stack.remove_at(k)
						break
			else:
				stack.append([name, value])
		else:
			buffer += "[" + tag + "]" # not ours: show it as written
		i = close + 1
	_flush(segments, buffer, stack, pause)
	return segments


## Adds `buffer` as a segment. Returns true if it added one (so the pending pause was used).
static func _flush(segments: Array, buffer: String, stack: Array, pause: float) -> bool:
	if buffer == "":
		return false
	var seg := Segment.new()
	seg.text = buffer
	seg.pause_before = pause
	for entry in stack:
		seg.mods[entry[0]] = entry[1]
	segments.append(seg)
	return true


## The text with all formatting removed.
static func plain(markup: String) -> String:
	var out := ""
	for seg in parse(markup):
		out += seg.text
	return out


## Fills `label` with the formatted text. `char_time` is the normal seconds per
## letter. Returns {"times": when each letter appears, "quiet": no-blip flags,
## "plain": the text without tags}. `writer` runs [astral] text's clock; with
## `ghost` on, only the faint copies of [astral] letters are drawn.
static func build(label: RichTextLabel, markup: String, char_time: float, writer = null, ghost := false) -> Dictionary:
	label.bbcode_enabled = true
	label.clear()
	var base_font: Font = label.get_theme_font("normal_font")
	var base_size: int = label.get_theme_font_size("normal_font_size")
	var times := PackedFloat32Array()
	var quiet := PackedByteArray()
	var plain_text := ""
	var t := 0.0
	var segments := parse(markup)

	# Work out the timing first, since [astral] needs it while building
	for seg in segments:
		t += seg.pause_before
		var per := char_time
		if seg.mods.has("time"):
			per = seg.mods["time"].to_float() / maxf(seg.text.length(), 1.0)
		for ch in seg.text:
			t += per
			times.append(t)
			quiet.append(1 if seg.mods.has("quiet") or ch in QUIET_CHARS else 0)

	for seg in segments:
		var m: Dictionary = seg.mods
		var pops := 0
		var first_letter := plain_text.length()
		if ghost and not m.has("astral"):
			label.push_color(Color(0, 0, 0, 0)) # copies only draw the astral letters
			pops += 1
		elif m.has("color"):
			label.push_color(Color.from_string(m["color"], Color.WHITE))
			pops += 1
		var font: Font = base_font
		var size := base_size
		if m.has("tiny"):
			font = TINY_FONT
			size = 8
		elif m.has("big"):
			size = base_size * 2
		if m.has("spaced"):
			var spaced := FontVariation.new()
			spaced.base_font = font
			spaced.spacing_glyph = int(m["spaced"]) if m["spaced"] != "" else 3
			font = spaced
		label.push_font(font, size)
		pops += 1
		if m.has("u"):
			label.push_underline()
			pops += 1
		if m.has("s"):
			label.push_strikethrough()
			pops += 1

		if m.has("astral"):
			var fx := AstralEffect.new()
			fx.writer = writer
			fx.times = times
			fx.first = first_letter
			fx.ghost = ghost
			label.push_customfx(fx, {})
			pops += 1

		var open := ""
		var close := ""
		for effect in [["wave", "[wave amp=24.0 freq=6.0]", "[/wave]"],
				["shake", "[shake rate=24.0 level=6]", "[/shake]"],
				["swirl", "[tornado radius=2.0 freq=6.0]", "[/tornado]"],
				["rainbow", "[rainbow freq=0.4 sat=0.7 val=1.0]", "[/rainbow]"],
				["pulse", "[pulse freq=2.0 color=#ffffff40 ease=-2.0]", "[/pulse]"]]:
			if m.has(effect[0]):
				open += effect[1]
				close = effect[2] + close
		label.append_text(open + seg.text.replace("[", "[lb]") + close)
		for k in pops:
			label.pop()

		plain_text += seg.text
	return {"times": times, "quiet": quiet, "plain": plain_text}


## Types formatted text into a RichTextLabel over time.
##   var writer := TextMarkup.Typewriter.new()
##   writer.start(label, markup, 0.03)
##   each frame: if writer.update(delta): play a blip
class Typewriter extends RefCounted:
	var label: RichTextLabel
	var times := PackedFloat32Array()
	var quiet := PackedByteArray()
	var elapsed := 0.0
	var shown := 0
	var ghosts: Array[RichTextLabel] = [] # faint copies behind [astral] text

	func start(target: RichTextLabel, markup: String, char_time: float) -> void:
		label = target
		for old in ghosts:
			old.queue_free()
		ghosts.clear()
		var built := TextMarkup.build(label, markup, char_time, self)
		times = built["times"]
		quiet = built["quiet"]
		elapsed = 0.0
		shown = 0
		label.visible_characters = 0
		if "[astral]" in markup:
			for i in 2:
				var copy := RichTextLabel.new()
				copy.show_behind_parent = true
				copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
				copy.scroll_active = false
				copy.clip_contents = false
				copy.horizontal_alignment = label.horizontal_alignment
				copy.size = label.size
				copy.add_theme_font_override("normal_font", label.get_theme_font("normal_font"))
				copy.add_theme_font_size_override("normal_font_size", label.get_theme_font_size("normal_font_size"))
				copy.add_theme_color_override("default_color", label.get_theme_color("default_color"))
				copy.add_theme_constant_override("line_separation", label.get_theme_constant("line_separation"))
				label.add_child(copy)
				TextMarkup.build(copy, markup, char_time, self, true)
				copy.visible_characters = 0
				ghosts.append(copy)

	## Advances the typing. Returns true if a letter that should blip appeared.
	func update(delta: float) -> bool:
		if label == null:
			return false
		elapsed += delta # keeps going after the typing's done, so [astral] letters finish settling
		for copy in ghosts:
			copy.size = label.size
		if not is_typing():
			return false
		var blip := false
		while shown < times.size() and times[shown] <= elapsed:
			if quiet[shown] == 0:
				blip = true
			shown += 1
		label.visible_characters = shown if is_typing() else -1
		for copy in ghosts:
			copy.visible_characters = label.visible_characters
		return blip

	func is_typing() -> bool:
		return shown < times.size()

	func finish() -> void:
		shown = times.size()
		if not times.is_empty():
			elapsed = maxf(elapsed, times[-1])
		if label:
			label.visible_characters = -1
		for copy in ghosts:
			copy.visible_characters = -1
