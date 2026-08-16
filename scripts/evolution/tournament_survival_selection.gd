class_name TournamentSurvivalSelection
extends RefCounted

# run tournament to select survivors from population (tournament selection) 

static func select(candidates: Array, survivor_count: int, config: Dictionary) -> Array:
	var survivors: Array = []
	var remaining := candidates.duplicate()

	while survivors.size() < survivor_count and not remaining.is_empty():
		var winner_index := _select_winner_index(remaining, config)
		survivors.append(remaining[winner_index])
		remaining.remove_at(winner_index)

	survivors.sort_custom(func(a, b): return a.fitness < b.fitness)
	return survivors

static func _select_winner_index(population: Array, config: Dictionary) -> int:
	var count: int = min(config["tournament_size"], population.size())
	var best_index := -1

	for _i in range(count):
		var candidate_index := randi_range(0, population.size() - 1)
		var candidate = population[candidate_index]

		if best_index == -1 or candidate.fitness < population[best_index].fitness:
			best_index = candidate_index

	return best_index
