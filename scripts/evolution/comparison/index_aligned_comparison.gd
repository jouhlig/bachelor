class_name IndexAlignedComparison
extends RefCounted

const EventDistanceScript = preload("res://scripts/evolution/comparison/event_distance.gd")

static func compare(generated_events: Array, target_events: Array, config: Dictionary) -> Dictionary:
	var measures := {
		"distance": 0.0,
		"duration": 0.0,
		"total_duration": 0.0,
		"paired": 0.0,
		"missing": 0.0,
		"extra": 0.0,
		"anchor_match": 0.0,
		"pitch_match": 0.0,
		"event_match": 0.0
	}
	measures["total_duration"] = abs(
		EventDistanceScript.get_score_total_duration(generated_events)
		- EventDistanceScript.get_score_total_duration(target_events)
	)

	var distance_fn: Callable = config["distance_fn"]
	var pair_count: int = min(generated_events.size(), target_events.size())
	measures["paired"] = float(pair_count)
	for index in range(pair_count):
		var generated_event: Dictionary = generated_events[index]
		var target_event: Dictionary = target_events[index]
		var event_measures := EventDistanceScript.measure(generated_event, target_event, distance_fn)
		measures["distance"] += event_measures["distance"]
		measures["duration"] += event_measures["duration"]
		measures["anchor_match"] += event_measures["anchor_match"]
		measures["pitch_match"] += event_measures["pitch_match"]
		measures["event_match"] += event_measures["event_match"]

	for index in range(pair_count, generated_events.size()):
		measures["extra"] += 1.0

	for index in range(pair_count, target_events.size()):
		measures["missing"] += 1.0

	return measures
