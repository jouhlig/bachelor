class_name TournamentSelection
extends RefCounted

static func select(population: Array, config: Dictionary):
	if population.is_empty():
		return null

	var count: int = min(config["tournament_size"], population.size())
	var best = null

	for i in range(count):
		var candidate = population[randi_range(0, population.size() - 1)]

		if best == null or candidate.fitness < best.fitness:
			best = candidate

	return best
