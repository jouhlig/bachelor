class_name RandomParentSelection
extends RefCounted

# picks a random parents (uniform selection)

static func select(population: Array, _config: Dictionary):
	if population.is_empty():
		return null

	return population[randi_range(0, population.size() - 1)]
