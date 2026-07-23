class_name PitchMatchFitness
extends RefCounted

static func evaluate(measures: Dictionary, config: Dictionary) -> float:
	var weights: Dictionary = config["fitness_weights"]
	return (
		+ measures["paired"] - measures["pitch_match"]
		+ measures["total_duration"] * weights["total_duration_weight"]
		+ measures["missing"] * weights["missing_event_weight"]
		+ measures["extra"] * weights["extra_event_weight"]
	)
