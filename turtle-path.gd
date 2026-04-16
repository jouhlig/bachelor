extends Node
class_name TurtlePath

var angle := 60.0

func build_actions(instructions: String, builder: TonnetzBuilder, start_anchor) -> Array:
	if start_anchor is TriangleArea:
		return _build_actions_for_triangles(instructions, builder, start_anchor)
	if start_anchor is TonnetzNode:
		return _build_actions_for_nodes(instructions, builder, start_anchor)
	return []

func _build_actions_for_triangles(instructions: String, builder: TonnetzBuilder, start_triangle: TriangleArea) -> Array:
	var actions = []

	if not builder or not start_triangle:
		return actions

	var current_triangle = start_triangle
	var previous_triangle = null
	var dir = Vector2.UP
	var stack = []

	for c in instructions:
		match c:
			"F":
				var next_triangle = _get_next_triangle(builder, current_triangle, dir, previous_triangle)
				if next_triangle:
					actions.append({
						"from": current_triangle.get_center(),
						"to": next_triangle.get_center()
					})
					previous_triangle = current_triangle
					current_triangle = next_triangle

			"+":
				dir = dir.rotated(deg_to_rad(angle))

			"-":
				dir = dir.rotated(deg_to_rad(-angle))

			"[":
				stack.append({
					"anchor": current_triangle,
					"previous_anchor": previous_triangle,
					"dir": dir
				})

			"]":
				if stack.size() > 0:
					var state = stack.pop_back()
					var branch_triangle: TriangleArea = state["anchor"]
					_append_path(actions, builder.get_shortest_triangle_path(current_triangle, branch_triangle))
					current_triangle = state["anchor"]
					previous_triangle = state["previous_anchor"]
					dir = state["dir"]

	return actions

func _build_actions_for_nodes(instructions: String, builder: TonnetzBuilder, start_node: TonnetzNode) -> Array:
	var actions = []

	if not builder or not start_node:
		return actions

	var current_node = start_node
	var previous_node = null
	var dir = Vector2.UP
	var stack = []

	for c in instructions:
		match c:
			"F":
				var next_node = _get_next_node(builder, current_node, dir, previous_node)
				if next_node:
					actions.append({
						"from": current_node.get_center(),
						"to": next_node.get_center()
					})
					previous_node = current_node
					current_node = next_node

			"+":
				dir = dir.rotated(deg_to_rad(angle))

			"-":
				dir = dir.rotated(deg_to_rad(-angle))

			"[":
				stack.append({
					"anchor": current_node,
					"previous_anchor": previous_node,
					"dir": dir
				})

			"]":
				if stack.size() > 0:
					var state = stack.pop_back()
					var branch_node: TonnetzNode = state["anchor"]
					_append_path(actions, builder.get_shortest_node_path(current_node, branch_node))
					current_node = state["anchor"]
					previous_node = state["previous_anchor"]
					dir = state["dir"]

	return actions

func _get_next_triangle(builder: TonnetzBuilder, current_triangle: TriangleArea, direction: Vector2, previous_triangle):
	var neighbors = builder.get_triangle_neighbors(current_triangle)
	return _get_best_aligned_neighbor(neighbors, current_triangle.get_center(), direction, previous_triangle)

func _get_next_node(builder: TonnetzBuilder, current_node: TonnetzNode, direction: Vector2, previous_node):
	var neighbors = builder.get_node_neighbors(current_node)
	return _get_best_aligned_neighbor(neighbors, current_node.get_center(), direction, previous_node)

func _get_best_aligned_neighbor(neighbors: Array, current_center: Vector2, direction: Vector2, previous_anchor):
	if neighbors.is_empty():
		return null

	var candidate_neighbors = neighbors
	if previous_anchor and neighbors.size() > 1:
		candidate_neighbors = []
		for neighbor in neighbors:
			if neighbor != previous_anchor:
				candidate_neighbors.append(neighbor)
		if candidate_neighbors.is_empty():
			candidate_neighbors = neighbors

	var best_neighbor = null
	var best_dot := -1.0e20

	for neighbor in candidate_neighbors:
		var offset = neighbor.get_center() - current_center
		var alignment = direction.normalized().dot(offset.normalized())
		if alignment > best_dot:
			best_dot = alignment
			best_neighbor = neighbor

	return best_neighbor

func _append_path(actions: Array, anchor_path: Array) -> void:
	if anchor_path.size() < 2:
		return

	for i in range(anchor_path.size() - 1):
		var from_anchor = anchor_path[i]
		var to_anchor = anchor_path[i + 1]
		actions.append({
			"from": from_anchor.get_center(),
			"to": to_anchor.get_center()
		})
