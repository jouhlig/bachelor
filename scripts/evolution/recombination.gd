class_name Recombination
extends RefCounted

# mix two L-systems into one child

const Individual = preload("res://scripts/evolution/individual.gd")

static func recombine(
	parent_a: Individual,
	parent_b: Individual,
	_config: Dictionary
) -> Individual:
	var child_rules: Dictionary = {}
	var iterations: int = parent_a.lsystem.iterations
	var rule_count := parent_a.lsystem.rules.size()

	var recombination_count := 0
	#recombine the rules of the two parents to create a child
	for key in parent_a.lsystem.rules.keys():
		if randf() < 1.0 / float(rule_count):
			child_rules[key] = parent_b.lsystem.rules.get(key)
			recombination_count += 1
		else:
			child_rules[key] = parent_a.lsystem.rules.get(key)
	if recombination_count == 0:
		var production_key = parent_a.lsystem.rules.keys()[randi_range(0, rule_count - 1)]
		child_rules[production_key] = parent_b.lsystem.rules.get(production_key)

	var child_initial_dir := parent_a.initial_dir
	var child_initial_edge := parent_a.initial_edge
	if randf() < 0.5:
		child_initial_dir = parent_b.initial_dir
		child_initial_edge = parent_b.initial_edge

	var child_axiom := parent_a.lsystem.axiom
	if randf() < 0.5:
		child_axiom = parent_b.lsystem.axiom

	var child_lsystem := parent_a.lsystem.duplicate_system()

	child_lsystem.apply_generated_state(
		child_axiom,
		child_rules,
		LSystem.generate_string(child_axiom, child_rules, iterations)
	)
	return Individual.new(child_lsystem, INF, child_initial_dir, child_initial_edge)
