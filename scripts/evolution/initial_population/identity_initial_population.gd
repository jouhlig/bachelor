class_name InitialPopulation
extends RefCounted

const Individual = preload("res://scripts/evolution/individual.gd")

static func create_initial(config: Dictionary) -> Array:
	var population: Array = []
	#create identity rules (l->l, r->r, u->u, d->d etc)
	var rules: Dictionary = _identity_rules()
	#create all possible start states (=directions) based on the origin (node/triangle)
	var start_states: Array[Dictionary] = _get_start_states(config.get("target_origin"))

	for start_state in start_states:
		for axiom in LSystem.TERMINALS:
			population.append(_create_individual(axiom, rules, start_state, config))

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

static func _get_start_states(origin) -> Array[Dictionary]:
	var states: Array[Dictionary] = []

	#nodes have 6 possible starting directions
	if origin is TonnetzNode:
		for direction in TonnetzBuilder.AXIAL_DIRECTIONS:
			states.append({
				"initial_dir": direction,
				"initial_edge": 0
			})
	#triangles have 3 possible starting edges
	else:
		for edge in range(3):
			states.append({
				"initial_dir": Vector2i(1, 0),
				"initial_edge": edge
			})

	return states

static func _identity_rules() -> Dictionary:
	var rules := {}
	for symbol in LSystem.TERMINALS:
		rules[symbol] = symbol
	return rules
