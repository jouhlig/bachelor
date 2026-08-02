class_name EventDistance
extends RefCounted

static func measure(
	generated_event: Dictionary,
	target_event: Dictionary,
	distance_fn: Callable
) -> Dictionary:
	var generated_anchor = generated_event.get("anchor")
	var target_anchor = target_event.get("anchor")
	var anchor_distance := 0.0
	if generated_anchor != target_anchor:
		anchor_distance = distance_fn.call(
			generated_anchor,
			target_anchor
		)
	var duration_distance: float = abs(_get_event_duration(generated_event) - _get_event_duration(target_event))
	var pitch_match := _anchors_have_same_pitch(generated_anchor, target_anchor)

	return {
		"distance": anchor_distance,
		"duration": duration_distance,
		"anchor_match": 1.0 if anchor_distance == 0.0 else 0.0,
		"pitch_match": 1.0 if pitch_match else 0.0,
		"duration_match": 1.0 if duration_distance == 0.0 else 0.0,
		"event_match": 1.0 if pitch_match and duration_distance == 0.0 else 0.0
	}

static func get_score_total_duration(events: Array) -> float:
	var total_duration := 0.0

	for index in range(events.size()):
		total_duration += _get_event_duration(events[index])

	return total_duration

static func _get_event_duration(event: Dictionary) -> float:
	return float(event.get("duration_beats", 0.0))

static func _anchors_have_same_pitch(anchor_a, anchor_b) -> bool:
	if anchor_a is TonnetzNode and anchor_b is TonnetzNode:
		return anchor_a.pitch == anchor_b.pitch

	if anchor_a is TriangleArea and anchor_b is TriangleArea:
		var pitches_a: Array[int] = anchor_a.get_pitches()
		var pitches_b: Array[int] = anchor_b.get_pitches()
		pitches_a.sort()
		pitches_b.sort()
		return pitches_a == pitches_b

	return false
