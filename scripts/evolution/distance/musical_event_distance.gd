class_name MusicalEventDistance
extends RefCounted

static func get_distance(anchor_a, anchor_b) -> float:
	if anchor_a is TonnetzNode and anchor_b is TonnetzNode:
		return abs(float(anchor_a.pitch - anchor_b.pitch))

	if anchor_a is TriangleArea and anchor_b is TriangleArea:
		return _get_best_permutation_distance(anchor_a.get_pitches(), anchor_b.get_pitches())

	push_error("Musical distance requires matching node or triangle anchors.")
	return INF

static func _get_best_permutation_distance(pitches_a: Array[int], pitches_b: Array[int]) -> float:
	var best_distance: float = INF
	var pitch_count := pitches_a.size()

	for first_index in range(pitch_count):
		for second_index in range(pitch_count):
			if second_index == first_index:
				continue

			for third_index in range(pitch_count):
				if third_index == first_index or third_index == second_index:
					continue

				var distance: float = (
					abs(float(pitches_a[0] - pitches_b[first_index]))
					+ abs(float(pitches_a[1] - pitches_b[second_index]))
					+ abs(float(pitches_a[2] - pitches_b[third_index]))
				)
				best_distance = min(best_distance, distance)

	return best_distance / float(pitch_count)
