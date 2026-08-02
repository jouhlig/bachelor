class_name TargetStepInitialPopulation
extends RefCounted

const Individual = preload("res://scripts/evolution/individual.gd")
const MutationScript = preload("res://scripts/evolution/mutation.gd")

static func create_initial(config: Dictionary) -> Array:
	var population: Array = []
	var rules: Dictionary = LSystem.identity_rules()
	var start_states := _get_target_start_states(config)

	for start_state in start_states:
		for axiom in LSystem.TERMINALS:
			population.append(_create_individual(axiom, rules, start_state, config))

	var combination_index := 0
	while population.size() < config["mu"]:
		var individual = population[combination_index % population.size()].copy()
		MutationScript.mutate(individual, config)
		population.append(individual)
		combination_index += 1

	return population

static func _create_individual(
	axiom: String,
	rules: Dictionary,
	start_state: Dictionary,
	config: Dictionary
) -> Individual:
	var generated_string := LSystem.generate_string(axiom, rules, config["iterations"])
	var lsystem := LSystem.new(
		axiom,
		rules.duplicate(true),
		generated_string,
		config["iterations"]
	)
	return Individual.new(
		lsystem,
		INF,
		start_state["initial_dir"],
		start_state["initial_edge"]
	)

static func _get_target_start_states(config: Dictionary) -> Array[Dictionary]:
	var target_score: Array = config.get("target_score", [])
	if target_score.size() >= 2:
		var start_state := _get_start_state_between(
			target_score[0].get("anchor"),
			target_score[1].get("anchor")
		)
		if not start_state.is_empty():
			return [start_state]

	return _get_all_start_states(config.get("target_origin"))

static func _get_start_state_between(current_anchor, next_anchor) -> Dictionary:
	if current_anchor == null or next_anchor == null:
		return {}

	for key in current_anchor.neighbors.keys():
		if current_anchor.neighbors[key] == next_anchor:
			if current_anchor is TonnetzNode:
				return {
					"initial_dir": key,
					"initial_edge": 0
				}
			if current_anchor is TriangleArea:
				return {
					"initial_dir": Vector2i(1, 0),
					"initial_edge": int(key)
				}

	return {}

static func _get_all_start_states(origin) -> Array[Dictionary]:
	var states: Array[Dictionary] = []

	if origin is TonnetzNode:
		for direction in TonnetzBuilder.AXIAL_DIRECTIONS:
			states.append({
				"initial_dir": direction,
				"initial_edge": 0
			})
	else:
		for edge in range(3):
			states.append({
				"initial_dir": Vector2i(1, 0),
				"initial_edge": edge
			})

	return states
