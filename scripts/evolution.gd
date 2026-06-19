class_name Evolution
extends RefCounted

const POPULATION_SIZE := 80
const MAX_MUTATION_OPS := 4
const MAX_PRODUCTION_LENGTH := 16
const TERMINALS := ["l", "r", "s", "u", "d", "1", "2", "4", "8"]

var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()

func build_selection_debug_text(selection: Dictionary, selected_actions: Array) -> String:
	var lines := []
	var selection_start := float(selection.get("start_beat", 0.0))
	var selection_end := float(selection.get("end_beat", 0.0))
	var source_nodes := _get_unique_action_source_nodes(selected_actions)
	var mutation_source_nodes := _get_mutation_source_nodes(selected_actions)
	var enclosing_node := _get_lowest_common_ancestor(mutation_source_nodes)
	var current_target_nodes := _get_target_production_nodes(selected_actions)

	lines.append("Selected beat range: %.2f to %.2f" % [selection_start, selection_end])
	lines.append("What you are looking at:")
	lines.append("  Actions are the played notes/steps inside the selected bars.")
	lines.append("  Final symbols are the finished L-system characters that caused those actions.")
	lines.append("  A provenance node is an ancestor in the L-system derivation tree.")
	lines.append("")
	lines.append("Counts:")
	lines.append("  Selected actions: %d" % selected_actions.size())
	lines.append("  Final symbols behind those actions: %d" % source_nodes.size())
	lines.append("  Final symbols influencing the selection: %d" % mutation_source_nodes.size())
	lines.append("")
	lines.append("Selected actions / notes:")
	lines.append("  Each row shows: start beat, duration, pitch, and the final symbols that created it.")
	lines.append("  Example: symbol 's' at final position 4 means the 5th character in the generated string.")
	lines.append("")
	lines.append("Summary: actions %d | final symbols %d | symbols influencing selection %d" % [
		selected_actions.size(),
		source_nodes.size(),
		mutation_source_nodes.size()
	])

	for i in range(min(selected_actions.size(), 10)):
		lines.append("  %s" % _format_debug_action(selected_actions[i]))

	if selected_actions.size() > 10:
		lines.append("  ... %d more" % (selected_actions.size() - 10))

	lines.append("")
	lines.append("Selected final symbols:")
	lines.append("  These are leaves of the derivation tree. Their span is usually one position.")

	for i in range(min(source_nodes.size(), 12)):
		lines.append("  %s" % _format_debug_symbol_node(source_nodes[i]))

	if source_nodes.size() > 12:
		lines.append("  ... %d more" % (source_nodes.size() - 12))

	lines.append("")
	lines.append("Paths from final symbols to shared enclosing node:")
	lines.append("  This shows the steps upward through the derivation tree.")

	if enclosing_node is SymbolNode:
		for i in range(min(mutation_source_nodes.size(), 8)):
			lines.append("  %s" % _format_debug_path_to_ancestor(mutation_source_nodes[i], enclosing_node))

		if mutation_source_nodes.size() > 8:
			lines.append("  ... %d more" % (mutation_source_nodes.size() - 8))
	else:
		lines.append("  (none)")

	lines.append("")
	lines.append("Shared enclosing provenance node:")
	lines.append("  This is the common ancestor that contains the selected mutation symbols.")

	if enclosing_node is SymbolNode:
		lines.append("  %s" % _format_debug_symbol_node(enclosing_node))
		lines.append("  Derivation path: %s" % _format_debug_node_chain(enclosing_node))
	else:
		lines.append("  (none)")

	lines.append("")
	lines.append("Current mutation target nodes:")
	lines.append("  These are the provenance nodes whose private production rules would be mutated right now.")

	if current_target_nodes.is_empty():
		lines.append("  (none)")
	else:
		for target_node in current_target_nodes:
			lines.append("  %s" % _format_debug_symbol_node(target_node))

	return "\n".join(lines)

# Build a private-rule mutation proposal. Nothing is applied to the L-system here.
func create_mutation_proposal(
	selection: Dictionary,
	selected_actions: Array,
	current_system: LSystem,
	voice: Dictionary,
	interpreter
) -> Dictionary:
	# Basic guardrails before doing provenance and mutation work.
	if selected_actions.is_empty():
		return _failure("No selected actions were found for this voice.")

	if current_system == null:
		return _failure("The selected voice does not exist anymore.")

	if voice.is_empty():
		return _failure("Could not find the playing score for this voice.")

	# Target the provenance node currently responsible for the selected actions.
	var target_nodes = _get_target_production_nodes(selected_actions)

	if target_nodes.is_empty():
		return _failure("No provenance node was found for the selected actions.")

	var specialized = LSystem.specialize_for_nodes(current_system, target_nodes)
	var mutation_symbols: Array = specialized.get("mutation_symbols", [])

	if mutation_symbols.is_empty():
		return _failure("The selected provenance node could not be copied into a private mutable rule.")

	var score: Array = voice.get("score", [])

	if score.is_empty():
		return _failure("The selected voice has an empty score.")

	var start_anchor = score[0].get("anchor")

	if not start_anchor or not start_anchor.has_method("get_center"):
		return _failure("The selected voice has no valid start anchor.")

	var local_range = _get_selection_local_range(selection, voice)

	if local_range.is_empty():
		return _failure("The selected bars could not be mapped into this voice's loop.")

	var original_loop_length := float(voice.get("loop_length", 0.0))

	# Keep the evolutionary search simple: mutate freely, then score candidates afterwards.
	var best_candidate := {}
	var best_fitness := -INF

	for i in range(POPULATION_SIZE):
		var candidate_rules: Dictionary = specialized["rules"].duplicate(true)

		_mutate_private_rules(candidate_rules, mutation_symbols)
		var generated = LSystem.generate_tree(
			specialized["axiom"],
			candidate_rules,
			current_system.iterations
		)
		var candidate_actions = interpreter.set_actions(
			generated["string"],
			generated["final_nodes"],
			start_anchor.get_center()
		)
		var fitness = _score_evolution_candidate(
			score,
			candidate_actions,
			local_range,
			original_loop_length
		)

		if fitness > best_fitness:
			best_fitness = fitness
			best_candidate = {
				"rules": candidate_rules,
				"generated_string": generated["string"],
				"final_nodes": generated["final_nodes"],
				"actions": candidate_actions
			}

	if best_candidate.is_empty() or best_fitness < 0.0:
		return _failure("No mutation candidate passed the current scoring checks.")

	return {
		"ok": true,
		"candidate": {
			"axiom": specialized["axiom"],
			"rules": best_candidate["rules"],
			"generated_string": best_candidate["generated_string"],
			"final_nodes": best_candidate["final_nodes"],
			"fitness": best_fitness,
			"mutation_symbols": mutation_symbols,
			"original_rules": specialized["rules"],
			"original_generated_string": current_system.generated_string,
			"start_position": start_anchor.get_center(),
			"old_start_beat": float(voice.get("start_beat", CL.get_time_beat()))
		}
	}

func build_mutation_proposition_text(candidate: Dictionary) -> String:
	var lines := []
	var mutation_symbols: Array = candidate.get("mutation_symbols", [])
	var original_rules: Dictionary = candidate.get("original_rules", {})
	var candidate_rules: Dictionary = candidate.get("rules", {})

	lines.append("Mutation proposal")
	lines.append("  Nothing has been applied yet.")
	lines.append("  Press Apply to rewrite the private L-system rules, or Cancel to keep the current system.")
	lines.append("")
	lines.append("Candidate score: %.2f" % float(candidate.get("fitness", 0.0)))
	lines.append("Private rules proposed for mutation:")

	for symbol in mutation_symbols:
		lines.append("  %s: %s -> %s" % [
			symbol,
			str(original_rules.get(symbol, "")),
			str(candidate_rules.get(symbol, ""))
		])

	lines.append("")
	lines.append("Generated string:")
	lines.append("  before: %s" % str(candidate.get("original_generated_string", "")))
	lines.append("  after:  %s" % str(candidate.get("generated_string", "")))

	return "\n".join(lines)

func build_failure_text(reason: String) -> String:
	var lines := []
	lines.append("No mutation proposal")
	lines.append("  %s" % reason)
	lines.append("")
	lines.append("Nothing has been changed.")
	return "\n".join(lines)

func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"message": message
	}

func _format_debug_action(action: Dictionary) -> String:
	var start_beat := float(action.get("absolute_start_beat", action.get("start_beat", 0.0)))
	var duration := float(action.get("duration_beats", 0.0))
	var sources := []

	for source_node in _get_action_source_nodes(action):
		sources.append("symbol '%s' at final position %d" % [
			source_node.symbol,
			source_node.final_start
		])

	return "starts %.2f, lasts %.2f beats, pitch %s, caused by: %s" % [
		start_beat,
		duration,
		_describe_action_pitch(action),
		", ".join(sources) if not sources.is_empty() else "-"
	]

func _describe_action_pitch(action: Dictionary) -> String:
	var anchor = action.get("anchor")

	if anchor is TonnetzNode:
		return str(anchor.pitch)

	if anchor is TriangleArea:
		var pitches := []

		for node in anchor.nodes:
			if node is TonnetzNode:
				pitches.append(str(node.pitch))

		return "/".join(pitches) if not pitches.is_empty() else "triangle"

	return "-"

func _format_debug_symbol_node(node: SymbolNode) -> String:
	return "symbol '%s', generation %d, covers final positions %d to %d, child slot %d" % [
		node.symbol,
		node.generation,
		node.final_start,
		node.final_end,
		node.child_index
	]

func _format_debug_node_chain(node: SymbolNode) -> String:
	var chain := []
	var current: SymbolNode = node

	while current != null:
		chain.append("'%s' gen %d span %d-%d" % [
			current.symbol,
			current.generation,
			current.final_start,
			current.final_end
		])
		current = current.parent

	chain.reverse()
	return " > ".join(chain)

func _format_debug_path_to_ancestor(node: SymbolNode, ancestor: SymbolNode) -> String:
	var chain := []
	var current: SymbolNode = node

	while current != null:
		chain.append("'%s' generation %d covers %d-%d" % [
			current.symbol,
			current.generation,
			current.final_start,
			current.final_end
		])

		if current == ancestor:
			break

		current = current.parent

	return " -> ".join(chain)

func _get_action_source_nodes(action: Dictionary) -> Array:
	var source_nodes: Array = action.get("source_nodes", [])

	if source_nodes.is_empty() and action.has("source_node"):
		source_nodes = [action["source_node"]]

	var valid_nodes := []

	for source_node in source_nodes:
		if source_node is SymbolNode:
			valid_nodes.append(source_node)

	return valid_nodes

func _get_unique_action_source_nodes(selected_actions: Array) -> Array:
	var unique_nodes := {}

	for action in selected_actions:
		for source_node in _get_action_source_nodes(action):
			unique_nodes[source_node] = true

	return unique_nodes.keys()

func _get_mutation_source_nodes(selected_actions: Array) -> Array:
	var unique_nodes := {}

	for action in selected_actions:
		for source_node in _get_action_source_nodes(action):
			unique_nodes[source_node] = true

	return unique_nodes.keys()

func _get_lowest_common_ancestor(nodes: Array) -> SymbolNode:
	if nodes.is_empty():
		return null

	var first_node = nodes[0]

	if not (first_node is SymbolNode):
		return null

	var candidate: SymbolNode = first_node

	while candidate != null:
		var shared := true

		for node in nodes:
			if not (node is SymbolNode) or not _symbol_node_has_ancestor(node, candidate):
				shared = false
				break

		if shared:
			return candidate

		candidate = candidate.parent

	return null

func _symbol_node_has_ancestor(node: SymbolNode, ancestor: SymbolNode) -> bool:
	var current: SymbolNode = node

	while current != null:
		if current == ancestor:
			return true

		current = current.parent

	return false

func _get_target_production_nodes(selected_actions: Array) -> Array:
	var source_nodes := _get_mutation_source_nodes(selected_actions)
	var enclosing_node := _get_lowest_common_ancestor(source_nodes)

	if enclosing_node is SymbolNode:
		return [enclosing_node]

	return []

# Mutate only the copied/private production rules selected by provenance.
func _mutate_private_rules(rules: Dictionary, mutation_symbols: Array) -> void:
	for symbol in mutation_symbols:
		var production := str(rules.get(symbol, ""))
		var mutation_count := rng.randi_range(1, MAX_MUTATION_OPS)

		for i in range(mutation_count):
			production = _mutate_production_once(production)

		if production.is_empty():
			production = _random_terminal()

		rules[symbol] = production

# Choose one simple mutation operator for one production string.
func _mutate_production_once(production: String) -> String:
	var op := rng.randi_range(0, 2)

	if production.is_empty():
		return _random_terminal()

	match op:
		# insert a random symbol
		0:
			if production.length() >= MAX_PRODUCTION_LENGTH:
				return production

			var index := rng.randi_range(0, production.length())
			return production.substr(0, index) + _random_terminal() + production.substr(index)
		# delete a random symbol
		1:
			if production.length() <= 1:
				return production

			var index := rng.randi_range(0, production.length() - 1)
			return production.substr(0, index) + production.substr(index + 1)
		# replace a random symbol
		2:
			var index := rng.randi_range(0, production.length() - 1)
			return production.substr(0, index) + _random_terminal() + production.substr(index + 1)
		
	return production

func _random_terminal() -> String:
	return TERMINALS[rng.randi_range(0, TERMINALS.size() - 1)]

func _get_selection_local_range(selection: Dictionary, voice: Dictionary) -> Dictionary:
	var loop_length := float(voice.get("loop_length", 0.0))
	var voice_start_beat := float(voice.get("start_beat", 0.0))
	var absolute_start := float(selection.get("start_beat", 0.0))
	var absolute_end := float(selection.get("end_beat", 0.0))

	if loop_length <= 0.0 or absolute_end <= absolute_start:
		return {}

	var local_start := fposmod(absolute_start - voice_start_beat, loop_length)
	var local_end := local_start + (absolute_end - absolute_start)

	return {
		"start": local_start,
		"end": local_end,
		"duration": absolute_end - absolute_start
	}

# Compute how useful a mutation candidate is. Preservation constraints belong here,
# not inside the mutation operators.
func _score_evolution_candidate(
	original_actions: Array,
	candidate_actions: Array,
	local_range: Dictionary,
	original_loop_length: float
) -> float:
	if candidate_actions.size() < 2:
		return -INF

	var candidate_loop_length := float(candidate_actions[-1].get("start_beat", 0.0))

	if not is_equal_approx(candidate_loop_length, original_loop_length):
		return -INF

	var start_beat := float(local_range["start"])
	var duration := float(local_range["duration"])
	var original_segment = _get_local_actions_in_wrapped_range(
		original_actions,
		start_beat,
		duration,
		original_loop_length
	)
	var candidate_segment = _get_local_actions_in_wrapped_range(
		candidate_actions,
		start_beat,
		duration,
		original_loop_length
	)

	if candidate_segment.is_empty():
		return -INF

	var difference_score: float = _get_action_difference_score(original_segment, candidate_segment)
	var density_score: float = 1.0 / (1.0 + abs(candidate_segment.size() - original_segment.size()))

	return difference_score + density_score

func _get_local_actions_in_range(score: Array, start_beat: float, end_beat: float) -> Array:
	var actions := []

	for action in score:
		var action_start := float(action.get("start_beat", 0.0))
		var action_end := action_start + float(action.get("duration_beats", 0.0))

		if action_start >= end_beat or action_end <= start_beat:
			continue

		actions.append(action)

	return actions

func _get_local_actions_in_wrapped_range(
	score: Array,
	start_beat: float,
	duration: float,
	loop_length: float
) -> Array:
	var actions := []

	if duration <= 0.0 or loop_length <= 0.0:
		return actions

	var remaining := duration
	var cursor := fposmod(start_beat, loop_length)

	while remaining > 0.0:
		var segment_end = min(loop_length, cursor + remaining)
		actions.append_array(_get_local_actions_in_range(score, cursor, segment_end))
		remaining -= segment_end - cursor
		cursor = 0.0

	return actions

func _get_action_difference_score(original_segment: Array, candidate_segment: Array) -> float:
	var shared_count = min(original_segment.size(), candidate_segment.size())
	var differences := 0.0

	for i in range(shared_count):
		if original_segment[i].get("anchor") != candidate_segment[i].get("anchor"):
			differences += 1.0

		if int(original_segment[i].get("pen_status", -1)) != int(candidate_segment[i].get("pen_status", -1)):
			differences += 0.5

		if not is_equal_approx(
			float(original_segment[i].get("duration_beats", 0.0)),
			float(candidate_segment[i].get("duration_beats", 0.0))
		):
			differences += 0.5

	differences += abs(candidate_segment.size() - original_segment.size()) * 0.25

	return differences
