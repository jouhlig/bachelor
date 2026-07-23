class_name RandomLSystemInitialPopulation
extends RefCounted

const Individual = preload("res://scripts/evolution/individual.gd")
const TonnetzConfigResource = preload("res://config/config.tres")

static func create_initial(config: Dictionary) -> Array:
	var population: Array = []
	var start_states: Array[Dictionary] = _get_start_states(config.get("target_origin"))

	while population.size() < config["mu"]:
		var start_state: Dictionary = start_states.pick_random()
		population.append(Individual.new(
			LSystemFactory.random(TonnetzConfigResource),
			INF,
			start_state["initial_dir"],
			start_state["initial_edge"]
		))

	return population

static func _get_start_states(origin) -> Array[Dictionary]:
	var states: Array[Dictionary] = []

	if origin is TonnetzNode:
		states.append({
			"initial_dir": TonnetzBuilder.AXIAL_DIRECTIONS.pick_random(),
			"initial_edge": 0
		})
	else:
		states.append({
			"initial_dir": Vector2i(1, 0),
			"initial_edge": randi_range(0, 2)
		})

	return states
