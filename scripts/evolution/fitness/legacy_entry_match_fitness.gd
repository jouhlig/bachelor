class_name LegacyEntryMatchFitness
extends RefCounted

static func evaluate(measures: Dictionary, config: Dictionary) -> float:
	var weights: Dictionary = config["fitness_weights"]
	return (
		+ (measures["paired"] - measures["pitch_match"]) * weights["pitch_weight"]
		+ (measures["paired"] - measures["duration_match"]) * weights["duration_match_weight"]
		+ measures["total_duration"] * weights["total_duration_weight"]
		+ measures["missing"] * weights["missing_weight"]
		+ measures["extra"] * weights["extra_weight"]
	)
