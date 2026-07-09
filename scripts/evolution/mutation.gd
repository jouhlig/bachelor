class_name Mutation
extends RefCounted

const MAX_PRODUCTION_LENGTH := 8

static func mutate(individual, config: Dictionary) -> Individual:
	mutate_lsystem(individual.lsystem, config)
	individual.fitness = INF
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
		elif production.length() >= MAX_PRODUCTION_LENGTH and available_ops[chosen_op] == 0:
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
	if production.length() >= MAX_PRODUCTION_LENGTH:
		push_error("Cannot insert symbol into production with length >= MAX_PRODUCTION_LENGTH")
		return production
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
