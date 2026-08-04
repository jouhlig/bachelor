class_name EntryWiseFitness
extends RefCounted

static func evaluate(measures: Dictionary, _config: Dictionary) -> float:
	var weights: Dictionary = _config["fitness_weights"]
	return (
		+ (measures["paired"] - measures["pitch_match"]) * 0.5
		+ (measures["paired"] - measures["duration_match"]) * 0.5
		+ measures["missing"] * weights["missing_weight"]
		+ measures["extra"] * weights["extra_weight"]
	)
