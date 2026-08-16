class_name IndexAlignedComparison
extends RefCounted

# compares events by their position in the list

const EventDistanceScript = preload("res://scripts/evolution/comparison/event_distance.gd")
const ComparisonMeasureHelperScript = preload("res://scripts/evolution/comparison/comparison_measure_helper.gd")

static func compare(generated_events: Array, target_events: Array, config: Dictionary) -> Dictionary:
	var measures := ComparisonMeasureHelperScript.create()
	measures["total_duration"] = abs(
		EventDistanceScript.get_score_total_duration(generated_events)
		- EventDistanceScript.get_score_total_duration(target_events)
	)

	var distance_fn: Callable = config["distance_fn"]
	var pair_count: int = min(generated_events.size(), target_events.size())
	for index in range(pair_count):
		var generated_event: Dictionary = generated_events[index]
		var target_event: Dictionary = target_events[index]
		var event_measures := EventDistanceScript.measure(generated_event, target_event, distance_fn)
		ComparisonMeasureHelperScript.add_pair(measures, event_measures)

	for index in range(pair_count, generated_events.size()):
		ComparisonMeasureHelperScript.add_extra(measures)

	for index in range(pair_count, target_events.size()):
		ComparisonMeasureHelperScript.add_missing(measures)

	return measures
