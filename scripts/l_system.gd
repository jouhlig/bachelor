class_name LSystem

var axiom: String
var rules: Dictionary
var generated_string: String
var iterations: int
var final_nodes: Array[SymbolNode]
var color: Color = Color.WHITE
var volume: float = 0.8
var origin = null
var start_beat = null
var origin_label: String = "Not set"
var start_label: String = "Not scheduled"

func _init(
	_axiom: String,
	_rules: Dictionary,
	_generated_string: String,
	_final_nodes: Array[SymbolNode],
	_iterations: int = 4
):
	axiom = _axiom
	rules = _rules
	generated_string = _generated_string
	final_nodes = _final_nodes
	iterations = _iterations

func regenerate() -> void:
	var generated_system = LSystem.generate_tree(axiom, rules, iterations)
	generated_string = generated_system["string"]
	final_nodes = generated_system["final_nodes"]

func set_axiom(new_axiom: String) -> void:
	if new_axiom.is_empty():
		return

	axiom = new_axiom[0]
	regenerate()

func set_iterations(new_iterations: int) -> void:
	iterations = new_iterations
	regenerate()

func set_rule(symbol: String, production: String) -> void:
	rules[symbol] = production
	regenerate()

func apply_generated_state(
	new_axiom: String,
	new_rules: Dictionary,
	new_generated_string: String,
	new_final_nodes: Array
) -> void:
	axiom = new_axiom
	rules = new_rules
	generated_string = new_generated_string
	final_nodes.assign(new_final_nodes)

func randomize(config: TonnetzConfig) -> void:
	var random_system = LSystemFactory.new_random_system(config)
	iterations = random_system["iterations"]
	apply_generated_state(
		random_system["axiom"],
		random_system["rules"],
		random_system["generated_string"],
		random_system["final_nodes"]
	)

func duplicate_system() -> LSystem:
	var generated_system = LSystem.generate_tree(axiom, rules, iterations)
	var duplicate = LSystem.new(
		axiom,
		rules.duplicate(true),
		generated_system["string"],
		generated_system["final_nodes"],
		iterations
	)
	duplicate.color = color
	duplicate.volume = volume
	return duplicate

func set_volume(new_volume: float) -> void:
	volume = clamp(new_volume, 0.0, 1.0)

func set_origin(new_origin, new_origin_label: String) -> void:
	origin = new_origin
	origin_label = new_origin_label

func set_start_beat(new_start_beat, new_start_label: String) -> void:
	start_beat = new_start_beat
	start_label = new_start_label

func get_info() -> Dictionary:
	return {
		"origin": origin,
		"start_beat": start_beat,
		"origin_label": origin_label,
		"start_label": start_label
	}


# Generate a tree with provenance information for every symbol.
# Ancestors are available through SymbolNode.parent.
static func generate_tree(axiom: String, rules: Dictionary, iterations: int) -> Dictionary:
	var current_nodes: Array[SymbolNode] = []

	for i in range(axiom.length()):
		current_nodes.append(SymbolNode.new(axiom[i], 0, null, i))

	for generation in range(iterations):
		var next_nodes: Array[SymbolNode] = []

		for parent_node in current_nodes:
			var replacement: String = rules.get(parent_node.symbol, parent_node.symbol)

			for i in range(replacement.length()):
				var child := SymbolNode.new(replacement[i], generation + 1, parent_node, i)

				parent_node.children.append(child)
				next_nodes.append(child)

		current_nodes = next_nodes

	var final_string := ""

	for i in range(current_nodes.size()):
		var node := current_nodes[i]
		final_string += node.symbol

		var current: SymbolNode = node

		while current != null:
			if current.final_start == -1 or i < current.final_start:
				current.final_start = i

			if current.final_end == -1 or i > current.final_end:
				current.final_end = i

			current = current.parent

	return {
		"string": final_string,
		"final_nodes": current_nodes
	}


# Takes character after character and substitutes according to the production rules.
static func generate_string(axiom: String, rules: Dictionary, iterations: int) -> String:
	return generate_tree(axiom, rules, iterations)["string"]

#Important for evolution: we want to make sure to copy the nodes and productions, not overwrite them
static func specialize_for_nodes(lsystem: LSystem, target_nodes: Array) -> Dictionary:
	var targets := {}
	var copied_symbols := {}
	var used_symbols = _collect_used_symbols(lsystem.axiom, lsystem.rules)
	var next_symbol_index := 0
	var new_axiom := lsystem.axiom
	var new_rules := lsystem.rules.duplicate(true)
	var mutation_symbols: Array[String] = []

	for node in target_nodes:
		if node is SymbolNode:
			targets[node] = true

	for node in target_nodes:
		if node is SymbolNode:
			next_symbol_index = _ensure_private_path(
				node,
				lsystem,
				new_rules,
				copied_symbols,
				used_symbols,
				next_symbol_index,
				targets,
				mutation_symbols
			)

	for node in copied_symbols.keys():
		var private_symbol: String = copied_symbols[node]

		if node.parent == null:
			new_axiom = _replace_symbol_at(new_axiom, node.child_index, private_symbol)
		else:
			var parent_private: String = copied_symbols[node.parent]
			var parent_production: String = new_rules[parent_private]
			new_rules[parent_private] = _replace_symbol_at(
				parent_production,
				node.child_index,
				private_symbol
			)

	var generated_system = LSystem.generate_tree(new_axiom, new_rules, lsystem.iterations)

	return {
		"axiom": new_axiom,
		"rules": new_rules,
		"generated_string": generated_system["string"],
		"final_nodes": generated_system["final_nodes"],
		"mutation_symbols": mutation_symbols
	}

static func _ensure_private_path(
	node: SymbolNode,
	lsystem: LSystem,
	new_rules: Dictionary,
	copied_symbols: Dictionary,
	used_symbols: Dictionary,
	next_symbol_index: int,
	targets: Dictionary,
	mutation_symbols: Array[String]
) -> int:
	if node == null:
		return next_symbol_index

	if node.parent != null:
		next_symbol_index = _ensure_private_path(
			node.parent,
			lsystem,
			new_rules,
			copied_symbols,
			used_symbols,
			next_symbol_index,
			targets,
			mutation_symbols
		)

	if copied_symbols.has(node):
		return next_symbol_index

	var private_symbol = _next_private_symbol(used_symbols, next_symbol_index, node.symbol)
	next_symbol_index = private_symbol["next_index"]
	copied_symbols[node] = private_symbol["symbol"]
	used_symbols[private_symbol["symbol"]] = true
	new_rules[private_symbol["symbol"]] = lsystem.rules.get(node.symbol, node.symbol)

	if targets.has(node):
		mutation_symbols.append(private_symbol["symbol"])

	return next_symbol_index

static func _collect_used_symbols(axiom: String, rules: Dictionary) -> Dictionary:
	var used := {}
	var terminal_symbols := "lrsud1248"

	for i in range(terminal_symbols.length()):
		used[terminal_symbols[i]] = true

	for i in range(axiom.length()):
		used[axiom[i]] = true

	for key in rules.keys():
		var key_string := str(key)
		for i in range(key_string.length()):
			used[key_string[i]] = true

		var production := str(rules[key])
		for i in range(production.length()):
			used[production[i]] = true

	return used

static func _next_private_symbol(
	used_symbols: Dictionary,
	start_index: int,
	original_symbol: String = ""
) -> Dictionary:
	var private_pool := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+,-./:;<=>?@[]^_{|}~"
	var preferred_symbols := _private_symbol_variants(original_symbol)

	for candidate in preferred_symbols:
		if not used_symbols.has(candidate):
			return {
				"symbol": candidate,
				"next_index": start_index
			}

	var index := start_index

	while index < private_pool.length():
		var candidate := private_pool[index]

		if not preferred_symbols.has(candidate) and not used_symbols.has(candidate):
			return {
				"symbol": candidate,
				"next_index": index + 1
			}

		index += 1

	push_error("No free private symbol left for local L-system specialization.")
	return {
		"symbol": "_",
		"next_index": index
	}

static func _private_symbol_variants(original_symbol: String) -> Array[String]:
	# Generation is character-based, so copied symbols must remain one character.
	match original_symbol:
		"l":
			return ["L"]
		"r":
			return ["R"]
		"s":
			return ["S"]
		"u":
			return ["U"]
		"d":
			return ["D"]
		"1":
			return ["I"]
		"2":
			return ["Z"]
		"4":
			return ["A"]
		"8":
			return ["B"]

	return []

static func _replace_symbol_at(text: String, index: int, replacement: String) -> String:
	if index < 0 or index >= text.length():
		return text

	return text.substr(0, index) + replacement + text.substr(index + 1)
