class_name InitialPopulation
extends RefCounted

const Individual = preload("res://scripts/evolution/individual.gd")

static func create_initial(config: Dictionary) -> Array:
	var population: Array = []
	#create identity rules (l->l, r->r, u->u, d->d etc)
	var rules: Dictionary = _identity_rules()
	#create all possible start states (=directions) based on the origin (node/triangle)
	var start_states: Array[Dictionary] = _get_start_states(config.get("target_origin"))
	var combination_index := 0

	while population.size() < config["mu"]:
		var axiom := str(LSystem.TERMINALS[
			(combination_index / start_states.size()) % LSystem.TERMINALS.size()
		])
		var start_state: Dictionary = start_states[combination_index % start_states.size()]
		var generated_string := LSystem.generate_string(axiom, rules, config["iterations"])
		var lsystem := LSystem.new(
			axiom,
			rules.duplicate(true),
			generated_string,
			config["iterations"]
		)
		population.append(Individual.new(
			lsystem,
			INF,
			start_state["initial_dir"],
			start_state["initial_edge"]
		))
		combination_index += 1

	return population

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
