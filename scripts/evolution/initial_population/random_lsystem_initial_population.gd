class_name RandomLSystemInitialPopulation
extends RefCounted

const Individual = preload("res://scripts/evolution/individual.gd")
const TonnetzConfigResource = preload("res://config/config.tres")

static func create_initial(config: Dictionary) -> Array:
	var population: Array = []
	var start_states: Array[Dictionary] = _get_start_states(config.get("target_origin"))

	while population.size() < config["mu"]:
		var start_state: Dictionary = start_states.pick_random()
		var axiom: String = LSystem.TERMINALS.pick_random()
		population.append(Individual.new(
			LSystemFactory.random_with_axiom(TonnetzConfigResource, axiom),
			INF,
			start_state["initial_dir"],
			start_state["initial_edge"]
		))

	return population

static func _get_start_states(origin) -> Array[Dictionary]:
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
