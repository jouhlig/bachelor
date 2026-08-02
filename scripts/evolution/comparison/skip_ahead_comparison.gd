class_name SkipAheadComparison
extends RefCounted

const EventDistanceScript = preload("res://scripts/evolution/comparison/event_distance.gd")

const COST_MODE_EVENT_MATCH := "event_match"
const COST_MODE_PITCH_MATCH := "pitch_match"
const COST_MODE_DISTANCE := "distance"

static func compare(generated_events: Array, target_events: Array, config: Dictionary) -> Dictionary:
	var measures := {
		"distance": 0.0,
		"duration": 0.0,
		"total_duration": abs(
			EventDistanceScript.get_score_total_duration(generated_events)
			- EventDistanceScript.get_score_total_duration(target_events)
		),
		"paired": 0.0,
		"missing": 0.0,
		"extra": 0.0,
		"anchor_match": 0.0,
		"pitch_match": 0.0,
		"duration_match": 0.0,
		"event_match": 0.0
	}
	var distance_fn: Callable = config["distance_fn"]
	var alignment := _get_alignment(generated_events, target_events, distance_fn, config)

	for step in alignment:
		if step["type"] == "pair":
			var event_measures := EventDistanceScript.measure(
				generated_events[int(step["generated_index"])],
				target_events[int(step["target_index"])],
				distance_fn
			)
			_add_pair_measures(measures, event_measures)
		elif step["type"] == "extra":
			measures["extra"] += 1.0
		elif step["type"] == "missing":
			measures["missing"] += 1.0

	return measures

static func _get_alignment(
	generated_events: Array,
	target_events: Array,
	distance_fn: Callable,
	config: Dictionary
) -> Array:
	var generated_count := generated_events.size()
	var target_count := target_events.size()
	var costs := _create_matrix(generated_count + 1, target_count + 1, 0.0)
	var actions := _create_matrix(generated_count + 1, target_count + 1, "")
	var skip_cost := float(config.get("skip_ahead_skip_cost", 1.0))

	for generated_index in range(1, generated_count + 1):
		costs[generated_index][0] = costs[generated_index - 1][0] + skip_cost
		actions[generated_index][0] = "extra"

	for target_index in range(1, target_count + 1):
		costs[0][target_index] = costs[0][target_index - 1] + skip_cost
		actions[0][target_index] = "missing"

	for generated_index in range(1, generated_count + 1):
		for target_index in range(1, target_count + 1):
			var event_measures := EventDistanceScript.measure(
				generated_events[generated_index - 1],
				target_events[target_index - 1],
				distance_fn
			)
			var best_cost: float = costs[generated_index - 1][target_index - 1] + _get_pair_cost(event_measures, config)
			var best_action := "pair"
			var extra_cost: float = costs[generated_index - 1][target_index] + skip_cost
			if extra_cost < best_cost:
				best_cost = extra_cost
				best_action = "extra"
			var missing_cost: float = costs[generated_index][target_index - 1] + skip_cost
			if missing_cost < best_cost:
				best_cost = missing_cost
				best_action = "missing"
			costs[generated_index][target_index] = best_cost
			actions[generated_index][target_index] = best_action

	return _trace_alignment(actions, generated_count, target_count)

static func _get_pair_cost(event_measures: Dictionary, config: Dictionary) -> float:
	var cost_mode := str(config.get("skip_ahead_cost_mode", COST_MODE_DISTANCE))
	if cost_mode == COST_MODE_EVENT_MATCH:
		return 0.0 if float(event_measures["event_match"]) > 0.0 else float(config.get("skip_ahead_mismatch_cost", 1.5))

	if cost_mode == COST_MODE_PITCH_MATCH:
		return 0.0 if float(event_measures["pitch_match"]) > 0.0 else float(config.get("skip_ahead_mismatch_cost", 1.5))

	return (
		+ float(event_measures["distance"]) * float(config.get("skip_ahead_distance_weight", 0.5))
		+ float(event_measures["duration"]) * float(config.get("skip_ahead_duration_weight", 0.5))
	)

static func _add_pair_measures(measures: Dictionary, event_measures: Dictionary) -> void:
	measures["paired"] += 1.0
	measures["distance"] += event_measures["distance"]
	measures["duration"] += event_measures["duration"]
	measures["anchor_match"] += event_measures["anchor_match"]
	measures["pitch_match"] += event_measures["pitch_match"]
	measures["duration_match"] += event_measures["duration_match"]
	measures["event_match"] += event_measures["event_match"]

static func _trace_alignment(actions: Array, generated_count: int, target_count: int) -> Array:
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

static func _create_matrix(rows: int, columns: int, value) -> Array:
	var matrix: Array = []
	for _row in range(rows):
		var row: Array = []
		for _column in range(columns):
			row.append(value)
		matrix.append(row)
	return matrix
