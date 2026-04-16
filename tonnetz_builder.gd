extends Node
class_name TonnetzBuilder

@export var config: TonnetzConfig
var nodes: Dictionary[Vector2i, TonnetzNode] = {}
var triangles: Array[TriangleArea] = []
var triangle_neighbors: Dictionary = {}
var node_neighbors: Dictionary = {}

const axial_directions = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)
]

func _ready() -> void:
	if not config:
		config = TonnetzConfig.new()

func build(radius: int):
	triangles.clear()
	triangle_neighbors.clear()
	node_neighbors.clear()

	# Spawn nodes
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			var node = TonnetzNode.new()
			node.q = q
			node.r = r
			node.pitch = (config.base_note + 7 * q + 4 * r) % 12
			node.config = config
			add_child(node)
			nodes[Vector2i(q, r)] = node
	
	# Generate triangles
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			# Triangle 1: (q,r), (q+1,r), (q,r+1)
			var n1 = get_tonnetz_node(q, r)
			var n2 = get_tonnetz_node(q + 1, r)
			var n3 = get_tonnetz_node(q, r + 1)
			if n1 and n2 and n3:
				var tri = TriangleArea.new()
				tri.config = config
				tri.set_nodes([n1, n2, n3])
				add_child(tri)
				triangles.append(tri)
			
			# Triangle 2: (q+1,r), (q+1,r-1), (q,r)
			var n4 = get_tonnetz_node(q + 1, r)
			var n5 = get_tonnetz_node(q + 1, r - 1)
			var n6 = get_tonnetz_node(q, r)
			if n4 and n5 and n6:
				var tri2 = TriangleArea.new()
				tri2.config = config
				tri2.set_nodes([n4, n5, n6])
				add_child(tri2)
				triangles.append(tri2)
	
	center_on_canvas()
	_build_triangle_graph()
	_build_node_graph()

func center_on_canvas() -> void:
	var tonnetz_nodes = nodes.values()
	if tonnetz_nodes.is_empty():
		return
	
	var first_node: TonnetzNode = tonnetz_nodes[0]
	var min_pos = first_node.position
	var max_pos = first_node.position
	
	for tonnetz_node: TonnetzNode in tonnetz_nodes:
		min_pos.x = min(min_pos.x, tonnetz_node.position.x)
		min_pos.y = min(min_pos.y, tonnetz_node.position.y)
		max_pos.x = max(max_pos.x, tonnetz_node.position.x)
		max_pos.y = max(max_pos.y, tonnetz_node.position.y)
	
	var tonnetz_center = (min_pos + max_pos) * 0.5
	var canvas_center = get_viewport().get_visible_rect().size * 0.5
	var offset = canvas_center - tonnetz_center
	
	for child in get_children():
		if child is Node2D:
			child.position += offset

func get_tonnetz_node(q: int, r: int) -> TonnetzNode:
	return nodes.get(Vector2i(q, r))

func get_nearest_triangle(world_pos: Vector2) -> TriangleArea:
	if triangles.is_empty():
		return null

	var nearest := triangles[0]
	var nearest_distance := world_pos.distance_squared_to(nearest.get_center())

	for triangle in triangles:
		var distance := world_pos.distance_squared_to(triangle.get_center())
		if distance < nearest_distance:
			nearest = triangle
			nearest_distance = distance

	return nearest

func get_nearest_triangle_center(world_pos: Vector2) -> Vector2:
	var triangle = get_nearest_triangle(world_pos)
	if triangle:
		return triangle.get_center()
	return world_pos

func get_triangle_neighbors(triangle: TriangleArea) -> Array:
	return triangle_neighbors.get(triangle, [])

func get_shortest_triangle_path(start_triangle: TriangleArea, end_triangle: TriangleArea) -> Array:
	if not start_triangle or not end_triangle:
		return []

	if start_triangle == end_triangle:
		return [start_triangle]

	var frontier: Array[TriangleArea] = [start_triangle]
	var visited := {start_triangle: true}
	var previous := {}

	while not frontier.is_empty():
		var current = frontier.pop_front()

		for neighbor in get_triangle_neighbors(current):
			if visited.has(neighbor):
				continue

			visited[neighbor] = true
			previous[neighbor] = current

			if neighbor == end_triangle:
				return _reconstruct_triangle_path(previous, start_triangle, end_triangle)

			frontier.append(neighbor)

	return []

func get_nearest_node(world_pos: Vector2) -> TonnetzNode:
	var tonnetz_nodes = nodes.values()
	if tonnetz_nodes.is_empty():
		return null

	var nearest: TonnetzNode = tonnetz_nodes[0]
	var nearest_distance := world_pos.distance_squared_to(nearest.get_center())

	for node in tonnetz_nodes:
		var distance := world_pos.distance_squared_to(node.get_center())
		if distance < nearest_distance:
			nearest = node
			nearest_distance = distance

	return nearest

func get_nearest_spawn_anchor(world_pos: Vector2):
	var nearest_triangle = get_nearest_triangle(world_pos)
	var nearest_node = get_nearest_node(world_pos)

	if not nearest_triangle:
		return nearest_node
	if not nearest_node:
		return nearest_triangle

	var triangle_distance := world_pos.distance_squared_to(nearest_triangle.get_center())
	var node_distance := world_pos.distance_squared_to(nearest_node.get_center())

	if node_distance < triangle_distance:
		return nearest_node

	return nearest_triangle

func get_node_neighbors(node: TonnetzNode) -> Array:
	return node_neighbors.get(node, [])

func get_shortest_node_path(start_node: TonnetzNode, end_node: TonnetzNode) -> Array:
	if not start_node or not end_node:
		return []

	if start_node == end_node:
		return [start_node]

	var frontier: Array[TonnetzNode] = [start_node]
	var visited := {start_node: true}
	var previous := {}

	while not frontier.is_empty():
		var current = frontier.pop_front()

		for neighbor in get_node_neighbors(current):
			if visited.has(neighbor):
				continue

			visited[neighbor] = true
			previous[neighbor] = current

			if neighbor == end_node:
				return _reconstruct_node_path(previous, start_node, end_node)

			frontier.append(neighbor)

	return []

func _build_triangle_graph() -> void:
	for triangle in triangles:
		triangle_neighbors[triangle] = []

	for i in range(triangles.size()):
		for j in range(i + 1, triangles.size()):
			var first = triangles[i]
			var second = triangles[j]
			if _shared_node_count(first, second) >= 2:
				triangle_neighbors[first].append(second)
				triangle_neighbors[second].append(first)

func _build_node_graph() -> void:
	node_neighbors.clear()

	for node in nodes.values():
		node_neighbors[node] = []

	for coord in nodes.keys():
		var node = nodes[coord]
		for direction in axial_directions:
			var neighbor = nodes.get(coord + direction)
			if neighbor and not node_neighbors[node].has(neighbor):
				node_neighbors[node].append(neighbor)

func _shared_node_count(first: TriangleArea, second: TriangleArea) -> int:
	var first_coords = first.get_node_coords()
	var second_lookup := {}

	for coord in second.get_node_coords():
		second_lookup[coord] = true

	var shared := 0
	for coord in first_coords:
		if second_lookup.has(coord):
			shared += 1

	return shared

func _reconstruct_triangle_path(previous: Dictionary, start_triangle: TriangleArea, end_triangle: TriangleArea) -> Array:
	var path: Array = [end_triangle]
	var current = end_triangle

	while current != start_triangle:
		current = previous.get(current)
		if current == null:
			return []
		path.push_front(current)

	return path

func _reconstruct_node_path(previous: Dictionary, start_node: TonnetzNode, end_node: TonnetzNode) -> Array:
	var path: Array = [end_node]
	var current = end_node

	while current != start_node:
		current = previous.get(current)
		if current == null:
			return []
		path.push_front(current)

	return path
