class_name Mutation
extends RefCounted

# mutates an individual
# add, delete, or replace a symbol in the production of a rule

static func mutate(individual, config: Dictionary) -> Individual:
	mutate_lsystem(individual.lsystem, config)
	mutate_start_state(individual, config)
	individual.fitness = INF
	return individual

static func mutate_start_state(individual, config: Dictionary) -> Individual:
	if randf() >= float(config.get("start_state_mutation_rate", 0.0)):
		return individual

	var origin = config.get("target_origin")
	if origin is TonnetzNode:
		individual.initial_dir = _random_direction_except(individual.initial_dir)
	elif origin is TonnetzTriangle:
		individual.initial_edge = _random_edge_except(individual.initial_edge)

	return individual

static func mutate_lsystem(
	lsystem: LSystem,
	config: Dictionary,
) -> LSystem:
	var candidate_rules: Dictionary = lsystem.rules.duplicate(true)
	
	var mutation_count := 0
	for key in candidate_rules.keys():
		var production := str(candidate_rules.get(key))

		if randf() < (1.0 / float(LSystem.TERMINALS.size())):
			production = _mutate_production_once(production)
			mutation_count += 1

		candidate_rules[key] = production
	if mutation_count == 0:
		var production_key := _random_terminal()
		var production := str(candidate_rules.get(production_key))
		candidate_rules[production_key] = _mutate_production_once(production)

	lsystem.apply_generated_state(
		lsystem.axiom,
		candidate_rules,
		LSystem.generate_string(lsystem.axiom, candidate_rules, lsystem.iterations)
	)
	return lsystem


static func _mutate_production_once(production: String) -> String:
	var available_ops := [0, 1, 2]

	var ok : bool = false
	var chosen_op := 0
	while ok == false:
		chosen_op = randi_range(0, available_ops.size() - 1)

		if production.length() <= 1 && available_ops[chosen_op] == 1:
			available_ops.remove_at(chosen_op)
		else:
			ok = true

	match int(available_ops[chosen_op]):
		0:
			return _insert_random_symbol(production)
		1:
			return _delete_random_symbol(production)
		2:
			return _replace_random_symbol(production)

	return production

static func _insert_random_symbol(production: String) -> String:
	var index := randi_range(0, production.length())
	return production.substr(0, index) + _random_terminal() + production.substr(index)

static func _delete_random_symbol(production: String) -> String:
	if production.length() <= 1:
		push_error("Cannot delete symbol from production with length <= 1")
		return production
	var index := randi_range(0, production.length() - 1)
	return production.substr(0, index) + production.substr(index + 1)

static func _replace_random_symbol(production: String) -> String:
	if production.is_empty():
		push_error("Cannot replace symbol in empty production")
		return _random_terminal()

	var index := randi_range(0, production.length() - 1)
	return production.substr(0, index) + _random_terminal() + production.substr(index + 1)

static func _random_terminal() -> String:
	return LSystem.TERMINALS[randi_range(0, LSystem.TERMINALS.size() - 1)]

static func _random_direction_except(current_direction: Vector2i) -> Vector2i:
	var directions := TonnetzBuilder.AXIAL_DIRECTIONS.duplicate()
	directions.erase(current_direction)
	return directions.pick_random()

static func _random_edge_except(current_edge: int) -> int:
	var edges := [0, 1, 2]
	edges.erase(posmod(current_edge, 3))
	return int(edges.pick_random())
