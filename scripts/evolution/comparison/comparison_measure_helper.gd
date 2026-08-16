class_name ComparisonMeasureHelper
extends RefCounted

static func create() -> Dictionary:
	return {
		"distance": 0.0,
		"duration": 0.0,
		"total_duration": 0.0,
		"paired": 0.0,
		"missing": 0.0,
		"extra": 0.0,
		"missing_events": 0.0,
		"extra_events": 0.0,
		"anchor_match": 0.0,
		"pitch_match": 0.0,
		"duration_match": 0.0,
		"event_match": 0.0
	}

static func add_pair(measures: Dictionary, event_measures: Dictionary, factor: float = 1.0) -> void:
	measures["paired"] += factor
	measures["distance"] += event_measures["distance"] * factor
	measures["duration"] += event_measures["duration"] * factor
	measures["anchor_match"] += event_measures["anchor_match"] * factor
	measures["pitch_match"] += event_measures["pitch_match"] * factor
	measures["duration_match"] += event_measures["duration_match"] * factor
	measures["event_match"] += event_measures["event_match"] * factor

static func add_extra(measures: Dictionary, amount: float = 1.0) -> void:
	measures["extra"] += amount
	measures["extra_events"] += amount

static func add_missing(measures: Dictionary, amount: float = 1.0) -> void:
	measures["missing"] += amount
	measures["missing_events"] += amount
