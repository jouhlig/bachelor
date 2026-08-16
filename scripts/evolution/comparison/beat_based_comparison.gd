class_name BeatBasedComparison
extends RefCounted

# compares two action lists based on alignment in concern to beats

const EventDistanceScript = preload("res://scripts/evolution/comparison/event_distance.gd")
const ComparisonMeasureHelperScript = preload("res://scripts/evolution/comparison/comparison_measure_helper.gd")

static func compare(generated_events: Array, target_events: Array, config: Dictionary) -> Dictionary:
	var measures := ComparisonMeasureHelperScript.create()
	var generated_total_duration := EventDistanceScript.get_score_total_duration(generated_events)
	var target_total_duration := EventDistanceScript.get_score_total_duration(target_events)
	measures["total_duration"] = abs(generated_total_duration - target_total_duration)

	var distance_fn: Callable = config["distance_fn"]
	var generated_ranges := _get_event_ranges(generated_events)
	var target_ranges := _get_event_ranges(target_events)
	var generated_index := 0
	var target_index := 0

	while generated_index < generated_ranges.size() and target_index < target_ranges.size():
		var generated_range: Dictionary = generated_ranges[generated_index]
		var target_range: Dictionary = target_ranges[target_index]
		var overlap_start: float = max(generated_range["start"], target_range["start"])
		var overlap_end: float = min(generated_range["end"], target_range["end"])
		var overlap_duration: float = overlap_end - overlap_start

		if overlap_duration > 0.0:
			var event_measures := EventDistanceScript.measure(
				generated_range["event"],
				target_range["event"],
				distance_fn
			)
			ComparisonMeasureHelperScript.add_pair(measures, event_measures, overlap_duration)

		if generated_range["end"] < target_range["end"] or is_equal_approx(generated_range["end"], target_range["end"]):
			generated_index += 1
		if target_range["end"] < generated_range["end"] or is_equal_approx(target_range["end"], generated_range["end"]):
			target_index += 1

	_set_overhead_measures(measures, generated_ranges, target_ranges, generated_total_duration, target_total_duration)
	measures["duration"] = measures["extra"] + measures["missing"]

	return measures

static func _get_event_ranges(events: Array) -> Array:
	var ranges: Array = []
	var beat := 0.0

	for event in events:
		var duration := _get_event_duration(event)
		var event_range := {
			"event": event,
			"start": beat,
			"end": beat + duration
		}
		ranges.append(event_range)
		beat = event_range["end"]

	return ranges

static func _set_overhead_measures(
	measures: Dictionary,
	generated_ranges: Array,
	target_ranges: Array,
	generated_total_duration: float,
	target_total_duration: float
) -> void:
	if generated_total_duration > target_total_duration:
		measures["extra"] = generated_total_duration - target_total_duration
		measures["extra_events"] = _count_overhead_events(generated_ranges, target_total_duration)
	elif target_total_duration > generated_total_duration:
		measures["missing"] = target_total_duration - generated_total_duration
		measures["missing_events"] = _count_overhead_events(target_ranges, generated_total_duration)

static func _count_overhead_events(ranges: Array, limit_beat: float) -> float:
	var overhead_count := 0.0

	for event_range in ranges:
		if float(event_range["start"]) >= limit_beat:
			overhead_count += 1.0

	return overhead_count

static func _get_event_duration(event: Dictionary) -> float:
	return float(event.get("duration_beats", 0.0))
