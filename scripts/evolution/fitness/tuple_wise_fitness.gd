class_name TupleWiseFitness
extends RefCounted

static func evaluate(measures: Dictionary, _config: Dictionary) -> float:
	var weights: Dictionary = _config["fitness_weights"]
	return (
		+ measures["paired"] - measures["event_match"]
		+ measures["missing"] * weights["missing_weight"]
		+ measures["extra"] * weights["extra_weight"]
	)
