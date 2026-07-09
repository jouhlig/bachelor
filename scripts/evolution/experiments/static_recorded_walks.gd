class_name StaticRecordedWalks
extends RefCounted

const WALKS: Array[Dictionary] = [
	{
		"name": "long_walk",
		"events": [
			{"anchor": {"type": "node", "q": 5, "r": -3}, "duration_beats": 1.000000},
			{"anchor": {"type": "node", "q": 6, "r": -3}, "duration_beats": 1.000000},
			{"anchor": {"type": "node", "q": 7, "r": -4}, "duration_beats": 1.000000},
			{"anchor": {"type": "node", "q": 8, "r": -5}, "duration_beats": 1.000000},
			{"anchor": {"type": "node", "q": 8, "r": -6}, "duration_beats": 1.000000},
			{"anchor": {"type": "node", "q": 9, "r": -6}, "duration_beats": 1.000000},
			{"anchor": {"type": "node", "q": 9, "r": -5}, "duration_beats": 1.000000},
			{"anchor": {"type": "node", "q": 10, "r": -6}, "duration_beats": 1.000000},
			{"anchor": {"type": "node", "q": 10, "r": -7}, "duration_beats": 1.000000},
			{"anchor": {"type": "node", "q": 9, "r": -7}, "duration_beats": 1.000000},
			{"anchor": {"type": "node", "q": 8, "r": -7}, "duration_beats": 1.000000},
			{"anchor": {"type": "node", "q": 7, "r": -6}, "duration_beats": 1.000000}
		]
	},
	{
		"name": "short_walk",
		"events": [
			{"anchor": {"type": "node", "q": 6, "r": -3}, "duration_beats": 1.000000},
			{"anchor": {"type": "node", "q": 7, "r": -4}, "duration_beats": 1.000000},
			{"anchor": {"type": "node", "q": 8, "r": -5}, "duration_beats": 1.000000},
			{"anchor": {"type": "node", "q": 8, "r": -6}, "duration_beats": 1.000000}
		]
	},
	{
		"name": "triangle_walk",
		"events": [
			{"anchor": {"type": "triangle", "nodes": [[5, -3], [6, -4], [6, -3]]}, "duration_beats": 1.000000},
			{"anchor": {"type": "triangle", "nodes": [[6, -4], [6, -3], [7, -4]]}, "duration_beats": 1.000000},
			{"anchor": {"type": "triangle", "nodes": [[6, -3], [7, -4], [7, -3]]}, "duration_beats": 1.000000},
			{"anchor": {"type": "triangle", "nodes": [[7, -4], [7, -3], [8, -4]]}, "duration_beats": 1.000000},
			{"anchor": {"type": "triangle", "nodes": [[7, -4], [8, -5], [8, -4]]}, "duration_beats": 1.000000},
			{"anchor": {"type": "triangle", "nodes": [[8, -5], [8, -4], [9, -5]]}, "duration_beats": 1.000000},
			{"anchor": {"type": "triangle", "nodes": [[8, -5], [9, -6], [9, -5]]}, "duration_beats": 1.000000},
			{"anchor": {"type": "triangle", "nodes": [[8, -6], [8, -5], [9, -6]]}, "duration_beats": 1.000000},
			{"anchor": {"type": "triangle", "nodes": [[8, -6], [9, -7], [9, -6]]}, "duration_beats": 1.000000},
			{"anchor": {"type": "triangle", "nodes": [[9, -7], [9, -6], [10, -7]]}, "duration_beats": 1.000000}
		]
	}
]

static func build_walks(builder: TonnetzBuilder) -> Array[Dictionary]:
	var walks: Array[Dictionary] = []

	for walk_data in WALKS:

		var score := _build_score(walk_data["events"], builder)

		walks.append({
			"name": str(walk_data["name"]),
			"score": score,
			"origin": score[0]["anchor"]
		})

	return walks

static func _build_score(events: Array, builder: TonnetzBuilder) -> Array:
	var score: Array = []

	for event in events:
		if not event.has("anchor") or not event.has("duration_beats"):
			push_error("Static recorded walk event requires anchor and duration_beats.")
			return []

		var anchor = _get_anchor(event["anchor"], builder)

		score.append({
			"anchor": anchor,
			"duration_beats": float(event["duration_beats"])
		})

	return score

static func _get_anchor(anchor_data: Dictionary, builder: TonnetzBuilder):

	match str(anchor_data["type"]):
		"node":

			return builder.nodes.get(Vector2i(
				int(anchor_data["q"]),
				int(anchor_data["r"])
			))
		"triangle":

			return _find_triangle(anchor_data["nodes"], builder)

	push_error("Recorded walk anchor requires type 'node' or 'triangle'.")
	return null

static func _find_triangle(node_data: Array, builder: TonnetzBuilder):
	var target_coords: Array[Vector2i] = []
	for coord in node_data:
		target_coords.append(Vector2i(int(coord[0]), int(coord[1])))
	target_coords.sort()

	for triangle in builder.triangles:
		var triangle_coords: Array[Vector2i] = triangle.get_node_coords()
		triangle_coords.sort()
		if triangle_coords == target_coords:
			return triangle

	return null
