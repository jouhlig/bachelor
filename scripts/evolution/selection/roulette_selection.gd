class_name RouletteSelection
extends RefCounted

static func select(population: Array, _config: Dictionary):
	if population.is_empty():
		return null

	var weights: Array[float] = []
	var total_weight := 0.0

	for individual in population:
		var weight: float = 1.0 / (1.0 + individual.fitness)
		weights.append(weight)
		total_weight += weight

	if total_weight <= 0.0:
		push_error("Roulette selection requires a positive total weight.")
		return null

	var pick := randf() * total_weight
	var cursor := 0.0

	for index in range(population.size()):
		cursor += weights[index]
		if pick <= cursor:
			return population[index]

	push_error("Roulette selection failed to pick an individual.")
	return null
