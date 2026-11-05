class_name MathFormula
extends RefCounted
## The little language Math Attack nodes are written in: lines of `name = maths`,
## worked out once per bullet, top to bottom, every frame.
##
## Formulas come from other people's scraps, so this is a sandbox. A line is split
## into tokens and only numbers, operators and the names listed below get through,
## with everything else refused. There are no strings, no dots, no loops and no way
## to name anything in the game or on the PC. What runs is new code written from
## those tokens, never the text someone typed: every name they make up becomes v0,
## v1... Since there are no loops, the work a formula can do is known in advance, and
## one that's too heavy is refused rather than freezing the game.

const MAX_SOURCE := 12000
const MAX_LINES := 200
const MAX_TOKENS := 400 # per line
const MAX_DEPTH := 40 # brackets and calls inside each other
const MAX_BULLETS := 2000
const MAX_ITERATIONS := 256 # for mandel() and julia()
const MAX_COST := 800000 # work per frame: bullets x how much maths each one does
const CACHE_SIZE := 64

## What a formula sets, and what each one is if it doesn't. These are the values
## handed over per bullet, in this order.
const OUTPUTS := {
	"x": 0.0, "y": 0.0, "size": 8.0, "angle": 0.0, "sx": 1.0, "sy": 1.0,
	"r": 1.0, "g": 1.0, "b": 1.0, "alpha": 1.0, "show": 1.0, "hit": -1.0, "harm": 1.0, "link": 0.0, "width": 2.0,
}
const STRIDE := 15
## Colour by hue instead of r, g, b.
const COLOR_INPUTS := {"hue": 0.0, "sat": 1.0, "val": 1.0}
## What the game tells it.
const INPUTS := ["i", "n", "u", "t", "p", "sec", "soul_x", "soul_y", "w", "h"]
const CONSTANTS := {"pi": PI, "tau": TAU, "e": 2.718281828459045}

## name: [fewest values, most values, cost, what to write]. {0} is the first value.
const FUNCTIONS := {
	"sin": [1, 1, 2, "sin({0})"], "cos": [1, 1, 2, "cos({0})"], "tan": [1, 1, 2, "tan({0})"],
	"asin": [1, 1, 2, "asin({0})"], "acos": [1, 1, 2, "acos({0})"], "atan": [1, 1, 2, "atan({0})"],
	"atan2": [2, 2, 2, "atan2({0}, {1})"], "sinh": [1, 1, 2, "sinh({0})"], "cosh": [1, 1, 2, "cosh({0})"], "tanh": [1, 1, 2, "tanh({0})"],
	"sqrt": [1, 1, 2, "sqrt({0})"], "abs": [1, 1, 1, "absf({0})"], "sign": [1, 1, 1, "signf({0})"],
	"floor": [1, 1, 1, "floorf({0})"], "ceil": [1, 1, 1, "ceilf({0})"], "round": [1, 1, 1, "roundf({0})"],
	"exp": [1, 1, 2, "exp({0})"], "ln": [1, 1, 2, "log({0})"], "log": [1, 1, 2, "(log({0}) / 2.302585092994046)"],
	"pow": [2, 2, 2, "pow({0}, {1})"], "clamp": [3, 3, 1, "clampf({0}, {1}, {2})"], "lerp": [3, 3, 1, "lerpf({0}, {1}, {2})"],
	"mod": [2, 2, 1, "fposmod({0}, {1})"], "fract": [1, 1, 2, "MathFormula.fract({0})"], "step": [2, 2, 1, "(1.0 if {1} >= {0} else 0.0)"],
	"smoothstep": [3, 3, 2, "smoothstep({0}, {1}, {2})"], "rad": [1, 1, 1, "deg_to_rad({0})"], "deg": [1, 1, 1, "rad_to_deg({0})"],
	"dist": [4, 4, 2, "Vector2({0}, {1}).distance_to(Vector2({2}, {3}))"],
	"rand": [1, 1, 3, "MathFormula.rand({0})"], "noise": [1, 2, 12, ""], "tri": [1, 1, 3, "MathFormula.tri({0})"],
	"square": [1, 1, 3, "MathFormula.square({0})"], "saw": [1, 1, 3, "MathFormula.saw({0})"],
	"mandel": [3, 3, MAX_ITERATIONS, "MathFormula.mandel({0}, {1}, {2})"], "julia": [5, 5, MAX_ITERATIONS, "MathFormula.julia({0}, {1}, {2}, {3}, {4})"],
	"min": [2, 8, 1, ""], "max": [2, 8, 1, ""], "when": [3, 3, 1, "({1} if {0} > 0.0 else {2})"],
}

## For the editor's Examples menu.
const EXAMPLES := [
	{"name": "Spiral arms", "count": 150, "formula": "# Five arms that wind outward\narms = 5\nspeed = 0.25\nr = 110 * fract(u * arms + t * speed)\na = tau * floor(u * arms) / arms + r / 50 + t / 3\nx = r * cos(a)\ny = r * sin(a)\nsize = 3 + r / 14\nhue = u + t / 8\n"},
	{"name": "Wave", "count": 60, "formula": "# A travelling wave, with a gap that drifts along it\nwaves = 2\nheight = 0.3\ngap = 0.12\nx = (u - 0.5) * w\ny = sin(u * tau * waves + t * 2) * h * height\nshow = step(gap, abs(u - fract(t / 8)))\nsize = 7\nhue = 0.55 + u / 4\n"},
	{"name": "Rose curve", "count": 240, "formula": "# r = cos(k a), slowly turning\nk = 5\nradius = 56\na = u * tau\nr = radius * cos(k * a + t)\nx = r * cos(a + t / 4)\ny = r * sin(a + t / 4)\nsize = 3\nhue = abs(r) / radius\n"},
	{"name": "Wireframe (lines)", "count": 200, "formula": "# Bullets joined up into one harmful line\na = u * tau\nspeed = 0.7\nx = 54 * sin(3 * a + t * speed)\ny = 54 * sin(2 * a)\nlink = 1\nwidth = 2\nsize = 0\nhue = fract(u + t / 6)\n"},
	{"name": "Aimed fan", "count": 9, "formula": "# Fires at wherever the soul is. i is which bullet, n how many\nspread = 0.5\nspeed = 60\naim = atan2(soul_y, soul_x)\nd = speed * fract(t / 2)\nat = aim + (u - 0.5) * spread * 2\nx = d * cos(at)\ny = d * sin(at)\nangle = deg(at)\nsize = 8\nr = 1\ng = 0.4\nb = 0.3\n"},
	{"name": "Sierpinski triangle", "count": 1000, "formula": "# Each dot jumps halfway to a random corner of a triangle\nradius = 58\ncorner = floor(rand(i) * 3)\na = tau * corner / 3 + t / 4 - pi / 2\nx = when(i < 1, 0, (prev_x + radius * cos(a)) / 2)\ny = when(i < 1, 0, (prev_y + radius * sin(a)) / 2)\nsize = 2\nhit = when(i < 10, 0, 1)\nhue = corner / 3\n"},
	{"name": "Julia fractal", "count": 1600, "formula": "# A 40 x 40 grid of dots, only shown inside the fractal\nside = 40\ngx = mod(i, side) / (side - 1)\ngy = floor(i / side) / (side - 1)\nx = (gx - 0.5) * 120\ny = (gy - 0.5) * 120\nm = julia(gx * 3 - 1.5, gy * 3 - 1.5, -0.8 + 0.2 * cos(t / 3), 0.156 + 0.2 * sin(t / 3), 32)\nshow = step(0.35, m)\nsize = 3\nhit = 2\nhue = m / 2\n"},
]


class Compiled extends RefCounted:
	var program: GDScript
	var errors: Array = [] # [{"line": number from 1, "message": words}]
	var cost := 0 # work per bullet
	var code := ""

	func ok() -> bool:
		return program != null and errors.is_empty()

	## Works out every bullet into `out`.
	func run(out: PackedFloat32Array, count: int, t: float, p: float, sec: float, soul_x: float, soul_y: float, w: float, h: float) -> void:
		program.run(out, count, t, p, sec, soul_x, soul_y, w, h)


static var _cache := {}


## The formula, ready to run. Results are remembered, since a preview asks again
## every time anything in the chart changes.
static func compile(source: String) -> Compiled:
	if _cache.has(source):
		return _cache[source]
	if _cache.size() >= CACHE_SIZE:
		_cache.clear()
	var result := _Parser.new().build(source)
	_cache[source] = result
	return result


## How much a formula with this many bullets can do, or "" if it's fine.
static func too_heavy(result: Compiled, count: int) -> bool:
	return result.cost * count > MAX_COST


# --- what formulas can call beyond Godot's own maths ---

static func fract(x: float) -> float:
	return x - floorf(x)


## The same number in always gives the same "random" number out, from 0 to 1, so
## fights play the same every time and rewinding the preview works.
static func rand(x: float) -> float:
	return fract(sin(x * 12.9898 + 4.1414) * 43758.5453)


## Smooth random hills, from 0 to 1.
static func noise1(x: float) -> float:
	var cell := floorf(x)
	return lerpf(rand(cell), rand(cell + 1.0), smoothstep(0.0, 1.0, x - cell))


static func noise2(x: float, y: float) -> float:
	var cx := floorf(x)
	var cy := floorf(y)
	var fx := smoothstep(0.0, 1.0, x - cx)
	var fy := smoothstep(0.0, 1.0, y - cy)
	var top := lerpf(rand(cx + cy * 57.0), rand(cx + 1.0 + cy * 57.0), fx)
	var bottom := lerpf(rand(cx + (cy + 1.0) * 57.0), rand(cx + 1.0 + (cy + 1.0) * 57.0), fx)
	return lerpf(top, bottom, fy)


## A wave one turn long, like sin(x), from -1 to 1, in straight lines.
static func tri(x: float) -> float:
	return 1.0 - 4.0 * absf(fract(x / TAU + 0.25) - 0.5)


static func square(x: float) -> float:
	return 1.0 if fract(x / TAU) < 0.5 else -1.0


static func saw(x: float) -> float:
	return 2.0 * fract(x / TAU) - 1.0


## How long a point takes to escape: 1 if it never does, near 0 if it goes right away.
static func mandel(cx: float, cy: float, iterations: float) -> float:
	return _escape(0.0, 0.0, cx, cy, iterations)


static func julia(zx: float, zy: float, cx: float, cy: float, iterations: float) -> float:
	return _escape(zx, zy, cx, cy, iterations)


static func _escape(zx: float, zy: float, cx: float, cy: float, iterations: float) -> float:
	var most := clampi(int(iterations), 1, MAX_ITERATIONS)
	for step_number in most:
		var next := zx * zx - zy * zy + cx
		zy = 2.0 * zx * zy + cy
		zx = next
		if zx * zx + zy * zy > 4.0:
			return float(step_number) / most
	return 1.0


# --- reading a formula ---

class _Token extends RefCounted:
	var kind := "" # "number", "name" or "op"
	var text := ""
	var value := 0.0

	func _init(new_kind: String, new_text: String, new_value := 0.0) -> void:
		kind = new_kind
		text = new_text
		value = new_value


class _Parser extends RefCounted:
	var _tokens: Array = []
	var _at := 0
	var _depth := 0
	var _problem := ""
	var _cost := 0
	var _users := {} # a name someone made up -> v0, v1...
	var _assigned := {} # every name set anywhere in the formula
	var _defined := {} # names set on an earlier line
	var _prev_used := {} # names read as prev_<name> -> the variable holding it

	func build(source: String) -> Compiled:
		var result := Compiled.new()
		if source.length() > MAX_SOURCE:
			result.errors.append({"line": 1, "message": "This formula's too long (the limit is %d characters)." % MAX_SOURCE})
			return result
		var lines := source.split("\n")
		if lines.size() > MAX_LINES:
			result.errors.append({"line": MAX_LINES, "message": "This formula has too many lines (the limit is %d)." % MAX_LINES})
			return result

		# Find every name first, so prev_<name> can mention one set further down
		var parsed := []
		for number in lines.size():
			var tokens: Variant = _tokenize(lines[number])
			if tokens == null:
				result.errors.append({"line": number + 1, "message": _problem})
				continue
			if tokens.is_empty():
				continue
			if tokens.size() < 3 or tokens[0].kind != "name" or tokens[1].text != "=":
				result.errors.append({"line": number + 1, "message": "Each line should look like: name = maths"})
				continue
			var name_problem := _check_target(tokens[0].text)
			if name_problem != "":
				result.errors.append({"line": number + 1, "message": name_problem})
				continue
			_assigned[tokens[0].text] = true
			parsed.append([number, tokens])

		var body := PackedStringArray()
		for entry in parsed:
			var target: String = entry[1][0].text
			_tokens = entry[1].slice(2)
			_at = 0
			_problem = ""
			var code := _or()
			if _problem == "" and _at < _tokens.size():
				_problem = "I didn't expect \"%s\" here." % _tokens[_at].text
			if _problem != "":
				result.errors.append({"line": entry[0] + 1, "message": _problem})
				continue
			_defined[target] = true
			body.append("\t\t%s = %s" % [_local(target), code])
		result.cost = _cost + 4
		if not result.errors.is_empty():
			return result
		result.code = _write_script(body)
		var program := GDScript.new()
		program.source_code = result.code
		if program.reload() == OK:
			result.program = program
		else:
			result.errors.append({"line": 1, "message": "This formula couldn't be built."})
		return result

	func _check_target(target: String) -> String:
		if FUNCTIONS.has(target):
			return "%s is a function, so it can't be used as a name here." % target
		if CONSTANTS.has(target):
			return "%s is a constant, so it can't be changed." % target
		if target in INPUTS:
			return "%s comes from the game, so it can't be changed." % target
		if target.begins_with("prev_"):
			return "prev_ names are read only: they hold the last bullet's value."
		if target in ["and", "or", "not"]:
			return "%s is a word the maths uses." % target
		return ""

	## A line as tokens, [] if it's blank, or null if it has something not allowed in it.
	func _tokenize(line: String) -> Variant:
		var found := []
		var at := 0
		var size := line.length()
		while at < size:
			var c := line[at]
			if c in " \t\r":
				at += 1
			elif c == "#" or line.substr(at, 2) == "//":
				break
			elif _is_digit(c) or (c == "." and at + 1 < size and _is_digit(line[at + 1])):
				var start := at
				while at < size and (_is_digit(line[at]) or line[at] == "."):
					at += 1
				if at < size and line[at] in "eE" and at + 1 < size and (_is_digit(line[at + 1]) or (line[at + 1] in "+-" and at + 2 < size and _is_digit(line[at + 2]))):
					at += 2
					while at < size and _is_digit(line[at]):
						at += 1
				var text := line.substr(start, at - start)
				if text.count(".") > 1 or not is_finite(text.to_float()):
					_problem = "%s isn't a number I can use." % text
					return null
				found.append(_Token.new("number", text, text.to_float()))
			elif _is_letter(c):
				var start := at
				while at < size and (_is_letter(line[at]) or _is_digit(line[at])):
					at += 1
				found.append(_Token.new("name", line.substr(start, at - start)))
			else:
				var two := line.substr(at, 2)
				if two in ["<=", ">=", "==", "!=", "&&", "||", "**"]:
					found.append(_Token.new("op", two))
					at += 2
				elif c in "+-*/%^()<>=,!":
					found.append(_Token.new("op", c))
					at += 1
				else:
					_problem = "Formulas can't use \"%s\"." % c
					return null
			if found.size() > MAX_TOKENS:
				_problem = "This line's too long."
				return null
		return found

	static func _is_digit(c: String) -> bool:
		return c >= "0" and c <= "9"

	static func _is_letter(c: String) -> bool:
		return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"

	func _peek() -> String:
		return _tokens[_at].text if _at < _tokens.size() and _tokens[_at].kind != "number" else ""

	func _take(text: String) -> bool:
		if _peek() == text:
			_at += 1
			return true
		return false

	func _fail(message: String) -> String:
		if _problem == "":
			_problem = message
		return "0.0"

	# Lowest priority first. Everything's a float, so true is 1 and false is 0.
	func _or() -> String:
		var left := _and()
		while _problem == "" and (_take("or") or _take("||")):
			left = "(1.0 if %s > 0.0 or %s > 0.0 else 0.0)" % [left, _and()]
			_cost += 1
		return left

	func _and() -> String:
		var left := _not()
		while _problem == "" and (_take("and") or _take("&&")):
			left = "(1.0 if %s > 0.0 and %s > 0.0 else 0.0)" % [left, _not()]
			_cost += 1
		return left

	func _not() -> String:
		if _take("not") or _take("!"):
			_cost += 1
			return "(1.0 if %s <= 0.0 else 0.0)" % _not_inner()
		return _compare()

	func _not_inner() -> String:
		if not _enter():
			return "0.0"
		var code := _not()
		_depth -= 1
		return code

	func _compare() -> String:
		var left := _sum()
		var op := _peek()
		while _problem == "" and op in ["<", "<=", ">", ">=", "==", "!="]:
			_at += 1
			left = "(1.0 if %s %s %s else 0.0)" % [left, op, _sum()]
			_cost += 1
			op = _peek()
		return left

	func _sum() -> String:
		var left := _product()
		var op := _peek()
		while _problem == "" and op in ["+", "-"]:
			_at += 1
			left = "(%s %s %s)" % [left, op, _product()]
			_cost += 1
			op = _peek()
		return left

	func _product() -> String:
		var left := _unary()
		while _problem == "" and _at < _tokens.size():
			var op := _peek()
			if op in ["*", "/", "%"]:
				_at += 1
				var right := _unary()
				left = "fposmod(%s, %s)" % [left, right] if op == "%" else "(%s %s %s)" % [left, op, right]
			elif _starts_value():
				left = "(%s * %s)" % [left, _unary()] # 2x, 3(a + b)
			else:
				break
			_cost += 1
		return left

	## Whether what's next could be multiplied without a *.
	func _starts_value() -> bool:
		var token: _Token = _tokens[_at]
		return token.kind == "number" or token.text == "(" or (token.kind == "name" and token.text not in ["and", "or", "not"])

	func _unary() -> String:
		if _take("-"):
			_cost += 1
			return "(-%s)" % _unary_inner()
		if _take("+"):
			return _unary_inner()
		return _power()

	func _unary_inner() -> String:
		if not _enter():
			return "0.0"
		var code := _unary()
		_depth -= 1
		return code

	func _power() -> String:
		var base := _atom()
		if _problem == "" and (_take("^") or _take("**")):
			_cost += 2
			return "pow(%s, %s)" % [base, _unary_inner()] # -x^2 is -(x^2), 2^3^2 is 2^9
		return base

	func _enter() -> bool:
		_depth += 1
		if _depth > MAX_DEPTH:
			_fail("There are too many brackets inside each other here.")
			_depth -= 1
			return false
		return true

	func _atom() -> String:
		if _at >= _tokens.size():
			return _fail("This line stops before the maths is finished.")
		var token: _Token = _tokens[_at]
		_at += 1
		if token.kind == "number":
			return var_to_str(token.value) if token.value != floorf(token.value) or absf(token.value) >= 1e15 else "%d.0" % int(token.value)
		if token.text == "(":
			if not _enter():
				return "0.0"
			var code := _or()
			_depth -= 1
			if _problem == "" and not _take(")"):
				return _fail("A bracket here isn't closed.")
			return code
		if token.kind != "name":
			return _fail("I didn't expect \"%s\" here." % token.text)
		if FUNCTIONS.has(token.text):
			return _call(token.text)
		if CONSTANTS.has(token.text):
			return var_to_str(float(CONSTANTS[token.text]))
		if token.text in INPUTS:
			return "in_" + token.text
		if token.text.begins_with("prev_"):
			var of := token.text.trim_prefix("prev_")
			if not _assigned.has(of) and not OUTPUTS.has(of):
				return _fail("Nothing sets %s, so %s has nothing to read." % [of, token.text])
			_prev_used[of] = true
			return "pv_" + _local(of).replace("o_", "")
		if OUTPUTS.has(token.text) or COLOR_INPUTS.has(token.text) or _defined.has(token.text):
			return _local(token.text)
		if _assigned.has(token.text):
			return _fail("%s is used before the line that sets it." % token.text)
		return _fail("I don't know what \"%s\" is." % token.text)

	func _call(function: String) -> String:
		if not _take("("):
			return _fail("%s needs brackets: %s(...)" % [function, function])
		if not _enter():
			return "0.0"
		var args: Array[String] = []
		if not _take(")"):
			while _problem == "":
				args.append(_or())
				if _take(")"):
					break
				if not _take(","):
					_depth -= 1
					return _fail("A bracket here isn't closed.")
		_depth -= 1
		if _problem != "":
			return "0.0"
		var info: Array = FUNCTIONS[function]
		if args.size() < info[0] or args.size() > info[1]:
			var wanted: String = str(info[0]) if info[0] == info[1] else "%d to %d" % [info[0], info[1]]
			return _fail("%s takes %s value(s), not %d." % [function, wanted, args.size()])
		_cost += int(info[2])
		match function:
			"noise":
				return "MathFormula.noise1(%s)" % args[0] if args.size() == 1 else "MathFormula.noise2(%s, %s)" % [args[0], args[1]]
			"min", "max":
				var code := args[0]
				for k in range(1, args.size()):
					code = "%sf(%s, %s)" % [function, code, args[k]]
				return code
		var written: String = info[3]
		for k in args.size():
			written = written.replace("{%d}" % k, args[k])
		return written

	## The name a variable gets in the code that actually runs.
	func _local(target: String) -> String:
		if OUTPUTS.has(target) or COLOR_INPUTS.has(target):
			return "o_" + target
		if not _users.has(target):
			_users[target] = "v%d" % _users.size()
		return _users[target]

	func _write_script(body: PackedStringArray) -> String:
		var parts := PackedStringArray()
		parts.append("extends RefCounted\n")
		parts.append("static func run(out: PackedFloat32Array, count: int, in_t: float, in_p: float, in_sec: float, in_soul_x: float, in_soul_y: float, in_w: float, in_h: float) -> void:")
		parts.append("\tvar in_n: float = float(count)")
		parts.append("\tvar last_index: float = float(maxi(count - 1, 1))")
		parts.append("\tvar slot: int = 0")
		for of in _prev_used:
			parts.append("\tvar pv_%s: float = %s" % [_local(of).replace("o_", ""), var_to_str(_default_of(of))])
		parts.append("\tfor index: int in count:")
		parts.append("\t\tvar in_i: float = float(index)")
		parts.append("\t\tvar in_u: float = in_i / last_index")
		for output in OUTPUTS:
			parts.append("\t\tvar o_%s: float = %s" % [output, var_to_str(float(OUTPUTS[output]))])
		for input in COLOR_INPUTS:
			parts.append("\t\tvar o_%s: float = %s" % [input, var_to_str(float(COLOR_INPUTS[input]))])
		for user in _users:
			parts.append("\t\tvar %s: float = 0.0" % _users[user])
		parts.append_array(body)
		if _assigned.has("hue"):
			parts.append("\t\tvar shade: Color = Color.from_hsv(fposmod(o_hue, 1.0), clampf(o_sat, 0.0, 1.0), clampf(o_val, 0.0, 1.0))")
			parts.append("\t\to_r = shade.r")
			parts.append("\t\to_g = shade.g")
			parts.append("\t\to_b = shade.b")
		var slot_offset := 0
		for output in OUTPUTS:
			parts.append("\t\tout[slot + %d] = o_%s" % [slot_offset, output])
			slot_offset += 1
		parts.append("\t\tslot += %d" % STRIDE)
		for of in _prev_used:
			var held := _local(of)
			parts.append("\t\tpv_%s = %s" % [held.replace("o_", ""), held])
		return "\n".join(parts) + "\n"

	func _default_of(of: String) -> float:
		if OUTPUTS.has(of):
			return float(OUTPUTS[of])
		return float(COLOR_INPUTS.get(of, 0.0))
