class_name DistanceFitness
extends RefCounted

static func evaluate(measures: Dictionary, config: Dictionary) -> float:
	var weights: Dictionary = config["fitness_weights"]
	return (
		+ measures["distance"] * weights["distance_weight"]
		+ measures["total_duration"] * weights["total_duration_weight"]
	)
