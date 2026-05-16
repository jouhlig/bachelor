extends Node
class_name TonnetzBuilder
@onready var config: TonnetzConfig = Config.config

var node_positions: Array[Vector2i] = []
var nodes: Dictionary[Vector2i, TonnetzNode] = {}
var logical_nodes: Dictionary[Vector2i, Array] = {}
var triangles: Array[TriangleArea] = []
var triangle_neighbors: Dictionary = {}
var node_neighbors: Dictionary = {}

@export var animation_on: bool = false
const AXIAL_DIRECTIONS = [
	Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 0)
]
#only used for computing lines
@onready var right = Vector2(config.offset, 0)
@onready var up_right = Vector2(config.offset * 0.5, -config.offset * 0.866)
@onready var up_left = Vector2(-config.offset * 0.5, -config.offset * 0.866)

@onready var base_note = config.base_note

func _ready() -> void:
	pass

func build():
	_clear_existing_graph()
	nodes.clear()
	logical_nodes.clear()
	triangles.clear()
	triangle_neighbors.clear()
	node_neighbors.clear()

	for row in range(config.row_count):
		for column in range(config.column_count):
			var pos = Vector2i(column + row, -column)
			#var pitch = (base_note + column * 7 + row * 4) % 12
			var pitch = (base_note + column * 7 + row * 4) 
			var this_node = await _create_node_at(pos, pitch)

			# Create line to right neighbor, except if last in line.
			if column < config.column_count - 1:
				var right_points = _get_line_endpoints(this_node.global_position, right)
				if !animation_on:
					_create_line_from_to(right_points[0], right_points[1], Color.YELLOW)
				else:
					await _create_line_from_to(right_points[0], right_points[1], Color.YELLOW)

			# Create line to the top left, except if first row.
			if row > 0:
				var up_left_points = _get_line_endpoints(this_node.global_position, up_left)
				if !animation_on:
					_create_line_from_to(up_left_points[0], up_left_points[1], Color.RED)
				else:
					await _create_line_from_to(up_left_points[0], up_left_points[1], Color.RED)

			# Create line to the top right, except if first row or last column.
			if row > 0 and column < config.column_count - 1:
				var up_right_points = _get_line_endpoints(this_node.global_position, up_right)
				if !animation_on:
					_create_line_from_to(up_right_points[0], up_right_points[1], Color.GREEN)
				else:
					await _create_line_from_to(up_right_points[0], up_right_points[1], Color.GREEN)
	_build_triangles()
	_build_triangle_graph()
	_build_node_graph()

func _clear_existing_graph() -> void:
	for child in get_children():
		child.queue_free()

func _build_triangles() -> void:
	for coord in nodes.keys():
		var base_node: TonnetzNode = nodes[coord]
		var right_node: TonnetzNode = nodes.get(coord + Vector2i(1, -1))
		var up_right_node: TonnetzNode = nodes.get(coord + Vector2i(0, -1))
		var up_left_node: TonnetzNode = nodes.get(coord + Vector2i(-1,0))

		if right_node and up_right_node:
			_add_triangle([base_node, right_node, up_right_node])

		if up_right_node and up_left_node:
			_add_triangle([base_node, up_right_node, up_left_node])

func _add_triangle(triangle_nodes: Array[TonnetzNode]) -> void:
	var triangle = TriangleArea.new()
	triangle.z_index = 1
	add_child(triangle)
	triangle.set_nodes(triangle_nodes)
	triangles.append(triangle)

func _create_node_at(node_pos: Vector2i, pitch: int):
	var node = TonnetzNode.new()
	node.q = node_pos.x
	node.r = node_pos.y
	node.s = -node_pos.x - node_pos.y
	node.pitch = pitch
	nodes[Vector2i(node.q, node.r)] = node
	var logical_coord = get_logical_coord(Vector2i(node.q, node.r))
	node.set_meta("logical_coord", logical_coord)
	if not logical_nodes.has(logical_coord):
		logical_nodes[logical_coord] = []
	logical_nodes[logical_coord].append(node)
	add_child(node)
	if !animation_on:
		get_tree().create_timer(config.delay).timeout
	else:
		await get_tree().create_timer(config.delay).timeout
	return node

func _create_line_from_to(start: Vector2, end: Vector2, color: Color):
	var line = AnimatedLine.new()
	line.start = start
	line.end = end
	line.color = color
	add_child(line)
	if animation_on:
		await line.finished

func _get_line_endpoints(center: Vector2, direction: Vector2) -> Array[Vector2]:
	var unit = direction.normalized()
	var neighbor_center = center + direction
	var radius_offset = unit * config.note_radius
	return [
		center + radius_offset,
		neighbor_center - radius_offset
	]

func get_logical_coord(coord: Vector2i) -> Vector2i:
	var row = posmod(coord.x + coord.y, config.row_count)
	var column = posmod(-coord.y, config.column_count)
	return Vector2i(
		column + row,
		-column
	)

func get_node_logical_coord(node: TonnetzNode) -> Vector2i:
	return get_logical_coord(Vector2i(node.q, node.r))

func get_equivalent_nodes(node: TonnetzNode) -> Array:
	if not node:
		return []
	return logical_nodes.get(get_node_logical_coord(node), [])

func get_nearest_triangle(world_pos: Vector2) -> TriangleArea:
	#if there are no triangles return
	if triangles.is_empty():
		return null
	#set first triangle as nearest, compute distance to player pos
	var nearest := triangles[0]
	var nearest_distance := world_pos.distance_squared_to(nearest.get_center())
	#for every triangle: measure distance to player, if it is smaller then "nearest" then update nearest 
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

	if (not nearest_node && not nearest_triangle):
		push_error("No spawn anchor available")
		
	#if there is only one candidate, return the candidate
	if not nearest_triangle:
		return nearest_node
	if not nearest_node:
		return nearest_triangle
	#else compute which is better fit and return that one
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
func get_tonnetz():
	return logical_nodes
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
		for direction in AXIAL_DIRECTIONS:
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
	
#is used to navigate branching in the l-system
func _reconstruct_triangle_path(previous: Dictionary, start_triangle: TriangleArea, end_triangle: TriangleArea) -> Array:
	var path: Array = [end_triangle]
	var current = end_triangle

	while current != start_triangle:
		current = previous.get(current)
		if current == null:
			return []
		path.push_front(current)

	return path
	
#is used to navigate branching in the l-system
func _reconstruct_node_path(previous: Dictionary, start_node: TonnetzNode, end_node: TonnetzNode) -> Array:
	var path: Array = [end_node]
	var current = end_node

	while current != start_node:
		current = previous.get(current)
		if current == null:
			return []
		path.push_front(current)

	return path


func _on_ui_toggle_animation() -> void:
	animation_on = !animation_on
