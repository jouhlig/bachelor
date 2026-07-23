class_name TargetScoreStore
extends RefCounted

static func load_scores(path: String, builder: TonnetzBuilder) -> Array[Dictionary]:
	if not FileAccess.file_exists(path):
		return []

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not read target scores: %s" % path)
		return []

	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Array):
		push_error("Target score file has no score array: %s" % path)
		return []

	var scores: Array[Dictionary] = []
	for score_data in parsed:
		var score := _deserialize_score(score_data, builder)
		if not score.is_empty():
			scores.append(score)

	return scores

static func save_scores(path: String, scores: Array[Dictionary]) -> void:
	var serialized_scores: Array[Dictionary] = []
	for score in scores:
		serialized_scores.append(_serialize_score(score))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write target scores: %s" % path)
		return

	file.store_string(JSON.stringify(serialized_scores, "\t"))

static func _serialize_score(score: Dictionary) -> Dictionary:
	var serialized_events: Array[Dictionary] = []

	for event in score.get("score", []):
		serialized_events.append({
			"anchor": _serialize_anchor(event.get("anchor")),
			"duration_beats": float(event.get("duration_beats", 0.0))
		})

	return {
		"name": str(score.get("name", "")),
		"score": serialized_events
	}

static func _serialize_anchor(anchor) -> Dictionary:
	if anchor is TonnetzNode:
		return {
			"type": "node",
			"q": int(anchor.q),
			"r": int(anchor.r)
		}

	if anchor is TriangleArea:
		var nodes: Array = []
		var coords: Array[Vector2i] = anchor.get_node_coords()
		coords.sort()
		for coord in coords:
			nodes.append([coord.x, coord.y])
		return {
			"type": "triangle",
			"nodes": nodes
		}

	return {}

static func _deserialize_score(score_data, builder: TonnetzBuilder) -> Dictionary:
	if not (score_data is Dictionary):
		return {}

	var events: Array[Dictionary] = []
	for event_data in score_data.get("score", []):
		var anchor = _deserialize_anchor(event_data.get("anchor", {}), builder)
		if anchor == null:
			return {}

		events.append({
			"anchor": anchor,
			"duration_beats": float(event_data.get("duration_beats", 0.0))
		})

	return {
		"name": str(score_data.get("name", "")),
		"score": events
	}

static func _deserialize_anchor(anchor_data, builder: TonnetzBuilder):
	if not (anchor_data is Dictionary):
		return null

	if anchor_data.get("type") == "node":
		return builder.nodes.get(Vector2i(
			int(anchor_data.get("q", 0)),
			int(anchor_data.get("r", 0))
		))

	if anchor_data.get("type") == "triangle":
		var key := _triangle_key_from_serialized_nodes(anchor_data.get("nodes", []))
		for triangle in builder.triangles:
			if _triangle_key_from_coords(triangle.get_node_coords()) == key:
				return triangle

	return null

static func _triangle_key_from_serialized_nodes(nodes: Array) -> String:
	var coords: Array[Vector2i] = []
	for coord in nodes:
		if coord is Array and coord.size() >= 2:
			coords.append(Vector2i(int(coord[0]), int(coord[1])))
	return _triangle_key_from_coords(coords)

static func _triangle_key_from_coords(coords: Array) -> String:
	var parts := PackedStringArray()
	var sorted_coords := coords.duplicate()
	sorted_coords.sort()
	for coord in sorted_coords:
		parts.append("%d,%d" % [coord.x, coord.y])
	return "|".join(parts)
