class_name SkipAheadComparison
extends RefCounted

# This class finds the best event alignment
# It can skip ahead in either list
# A bad pair is allowed, but it costs more

const EventDistanceScript = preload("res://scripts/evolution/comparison/event_distance.gd")
const ComparisonMeasureHelperScript = preload("res://scripts/evolution/comparison/comparison_measure_helper.gd")
const SKIP_COST := 1.0
const NON_STRICT_PAIR_COST := 1.5

static func compare(generated_events: Array, target_events: Array, config: Dictionary) -> Dictionary:
	var measures := ComparisonMeasureHelperScript.create()
	measures["total_duration"] = abs(
		EventDistanceScript.get_score_total_duration(generated_events)
		- EventDistanceScript.get_score_total_duration(target_events)
	)
	var alignment := _build_alignment_path(generated_events, target_events)

	for step in alignment:
		if step["type"] == "pair":
			var event_measures := EventDistanceScript.measure(
				generated_events[int(step["generated_index"])],
				target_events[int(step["target_index"])],
				config["distance_fn"]
			)
			ComparisonMeasureHelperScript.add_pair(measures, event_measures)
		elif step["type"] == "extra":
			ComparisonMeasureHelperScript.add_extra(measures)
		elif step["type"] == "missing":
			ComparisonMeasureHelperScript.add_missing(measures)

	return measures

static func _build_alignment_path(
	generated_events: Array,
	target_events: Array
) -> Array:
	# Table for pair, skip left, and skip right.
	var generated_count := generated_events.size()
	var target_count := target_events.size()
	var costs := _create_filled_matrix(generated_count + 1, target_count + 1, 0.0)
	var actions := _create_filled_matrix(generated_count + 1, target_count + 1, "")

	for generated_index in range(1, generated_count + 1):
		costs[generated_index][0] = costs[generated_index - 1][0] + SKIP_COST
		actions[generated_index][0] = "extra"

	for target_index in range(1, target_count + 1):
		costs[0][target_index] = costs[0][target_index - 1] + SKIP_COST
		actions[0][target_index] = "missing"

	for generated_index in range(1, generated_count + 1):
		for target_index in range(1, target_count + 1):
			var pair_cost := 0.0 if _has_strict_event_match(
				generated_events[generated_index - 1],
				target_events[target_index - 1]
			) else NON_STRICT_PAIR_COST
			var best_cost: float = costs[generated_index - 1][target_index - 1] + pair_cost
			var best_action := "pair"
			var extra_cost: float = costs[generated_index - 1][target_index] + SKIP_COST
			if extra_cost < best_cost:
				best_cost = extra_cost
				best_action = "extra"
			var missing_cost: float = costs[generated_index][target_index - 1] + SKIP_COST
			if missing_cost < best_cost:
				best_cost = missing_cost
				best_action = "missing"
			costs[generated_index][target_index] = best_cost
			actions[generated_index][target_index] = best_action

	return _reconstruct_alignment_path(actions, generated_count, target_count)

static func _has_strict_event_match(generated_event: Dictionary, target_event: Dictionary) -> bool:
	# Only pair when anchor and length both match.
	if generated_event.get("anchor") != target_event.get("anchor"):
		return false

	return is_equal_approx(
		float(generated_event.get("duration_beats", 0.0)),
		float(target_event.get("duration_beats", 0.0))
	)

static func _reconstruct_alignment_path(actions: Array, generated_count: int, target_count: int) -> Array:
	# Rebuild the chosen path from the table.
	var alignment: Array = []
	var generated_index := generated_count
	var target_index := target_count

	while generated_index > 0 or target_index > 0:
		var action: String = actions[generated_index][target_index]
		if action == "pair":
			alignment.push_front({
				"type": action,
				"generated_index": generated_index - 1,
				"target_index": target_index - 1
			})
			generated_index -= 1
			target_index -= 1
		elif action == "extra":
			alignment.push_front({"type": action})
			generated_index -= 1
		elif action == "missing":
			alignment.push_front({"type": action})
			target_index -= 1

	return alignment

static func _create_filled_matrix(rows: int, columns: int, value) -> Array:
	var matrix: Array = []
	for _row in range(rows):
		var row: Array = []
		for _column in range(columns):
			row.append(value)
		matrix.append(row)
	return matrix
