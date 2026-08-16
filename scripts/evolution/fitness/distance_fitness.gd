class_name DistanceFitness
extends RefCounted

# shared helper class for tonnetz and pitch distance

static func evaluate(measures: Dictionary, config: Dictionary) -> float:
	var weights: Dictionary = config["fitness_weights"]
	return (
		+ measures["distance"] * weights["distance_weight"]
		+ measures["duration"] * weights["duration_match_weight"]
		+ measures["missing_events"] * weights["missing_weight"]
		+ measures["extra_events"] * weights["extra_weight"]
	)
