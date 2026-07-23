class_name BeatBasedComparison
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
				measures["paired"] += overlap_duration
				var event_measures := EventDistanceScript.measure(
				generated_range["event"],
				target_range["event"],
				distance_fn
			)
				measures["distance"] += event_measures["distance"] * overlap_duration
				measures["anchor_match"] += event_measures["anchor_match"] * overlap_duration
				measures["pitch_match"] += event_measures["pitch_match"] * overlap_duration
				measures["event_match"] += event_measures["event_match"] * overlap_duration

		if generated_range["end"] < target_range["end"] or is_equal_approx(generated_range["end"], target_range["end"]):
			generated_index += 1
		if target_range["end"] < generated_range["end"] or is_equal_approx(target_range["end"], generated_range["end"]):
			target_index += 1

	measures["extra"] = _get_uncovered_duration(generated_ranges, target_ranges)
	measures["missing"] = _get_uncovered_duration(target_ranges, generated_ranges)
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

static func _get_uncovered_duration(source_ranges: Array, cover_ranges: Array) -> float:
	var uncovered_duration := 0.0
	var cover_index := 0

	for source_range in source_ranges:
		var beat: float = source_range["start"]
		var source_end: float = source_range["end"]

		while cover_index < cover_ranges.size() and cover_ranges[cover_index]["end"] <= beat:
			cover_index += 1

		var local_cover_index := cover_index
		while beat < source_end:
			if local_cover_index >= cover_ranges.size() or cover_ranges[local_cover_index]["start"] >= source_end:
				uncovered_duration += source_end - beat
				break

			if cover_ranges[local_cover_index]["start"] > beat:
				uncovered_duration += cover_ranges[local_cover_index]["start"] - beat
				beat = cover_ranges[local_cover_index]["start"]

			beat = max(beat, min(source_end, cover_ranges[local_cover_index]["end"]))
			local_cover_index += 1

	return uncovered_duration

static func _get_event_duration(event: Dictionary) -> float:
	return float(event.get("duration_beats", 0.0))
