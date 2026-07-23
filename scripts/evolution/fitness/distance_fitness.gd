class_name DistanceFitness
extends RefCounted

static func evaluate(measures: Dictionary, config: Dictionary) -> float:
	var weights: Dictionary = config["fitness_weights"]
	return (
		+ measures["distance"] * weights["distance_weight"]
		+ measures["duration"] * weights["duration_weight"]
		+ measures["total_duration"] * weights["total_duration_weight"]
		+ measures["missing"] * weights["missing_event_weight"]
		+ measures["extra"] * weights["extra_event_weight"]
	)
