extends "res://editor/inspector.gd"
## The chart maker's Rules tab: how this fight works. A Change Rules node can
## alter these mid-fight.


func refresh() -> void:
	_clear()
	_title("Rules", Color("c8ff6b"))
	var rules: Dictionary = editor.chart["rules"]
	for p in ChartDefs.RULE_PARAMS:
		_row(p, rules[p["name"]], func(v):
			editor.set_param(rules, p["name"], v, false)
			if p["name"] == "battle_type":
				refresh.call_deferred())
	if ChartDefs.uses_frames(editor.chart):
		_note("The timeline now counts frames, 60 a second. Nodes already on it keep their numbers: what was beat 32 is now frame 32, so an existing chart needs re-timing.")
