extends Node2D
class_name TonnetzBuilder
@onready var config: TonnetzConfig = Config.config

var node_positions: Array[Vector2i] = []
var nodes: Dictionary[Vector2i, TonnetzNode] = {}
var logical_nodes: Dictionary[Vector2i, Array] = {}
var triangles: Array[TriangleArea] = []
var line_segments: Array = []
var wrapped_triangle_edges := {}

const AXIAL_DIRECTIONS = [
	Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 0)
]
@onready var base_note = config.base_note

func _ready() -> void:
	pass

func build():
	_clear_existing_graph()
	nodes.clear()
	logical_nodes.clear()
	triangles.clear()
	line_segments.clear()
	wrapped_triangle_edges.clear()

	for row in range(config.row_count):
		for column in range(config.column_count):
			var pos = _coord_from_row_column(row, column)
			#var pitch = (base_note + column * 7 + row * 4) % 12
			var pitch = (base_note + column * 7 + row * 4) 
			_create_node_at(pos, pitch)

	for row in range(config.row_count):
		for column in range(config.column_count):
			var coord = _coord_from_row_column(row, column)
			var this_node: TonnetzNode = nodes[coord]

			# Create line to right neighbor, except if last in line.
			if column < config.column_count - 1:
				var right_node: TonnetzNode = nodes.get(_coord_from_row_column(row, column + 1))
				if right_node:
					var right_points = _get_line_endpoints(this_node.global_position, right_node.global_position)
					_create_line_from_to(right_points[0], right_points[1], config.line_color)

			# Create line to the top left, except if first row.
			if row > 0:
				var up_left_node: TonnetzNode = nodes.get(coord + Vector2i(-1, 0))
				if up_left_node:
					var up_left_points = _get_line_endpoints(this_node.global_position, up_left_node.global_position)
					_create_line_from_to(up_left_points[0], up_left_points[1], config.line_color)

			# Create line to the top right, except if first row or last column.
			if row > 0:
				var up_right_node: TonnetzNode = nodes.get(coord + Vector2i(0, -1))
				if up_right_node:
					var up_right_points = _get_line_endpoints(this_node.global_position, up_right_node.global_position)
					_create_line_from_to(up_right_points[0], up_right_points[1], config.line_color)
	_build_triangles()
	_build_wrapped_triangle_edge_index()
	_build_triangle_graph()
	_build_node_graph()

func _clear_existing_graph() -> void:
	for child in get_children():
		child.queue_free()
	line_segments.clear()
	queue_redraw()

func _draw() -> void:
	for segment in line_segments:
		draw_line(segment["start"], segment["end"], segment["color"], config.line_width, true)

func _build_triangles() -> void:
	for coord in nodes.keys():
		var base_node: TonnetzNode = nodes[coord]
		var right_node: TonnetzNode = nodes.get(coord + Vector2i(1, -1))
		var up_right_node: TonnetzNode = nodes.get(coord + Vector2i(0, -1))
		var up_left_node: TonnetzNode = nodes.get(coord + Vector2i(-1,0))

		if right_node and up_right_node:
			#ordering is important here as we use this info to compute directions later - needs to be clockwise
			_add_triangle([base_node, up_right_node, right_node], TriangleArea.Orientation.UP)

		if up_right_node and up_left_node:
			#ordering is important here as we use this info to compute directions later - needs to be clockwise
			_add_triangle([base_node, up_left_node, up_right_node], TriangleArea.Orientation.DOWN)

func _add_triangle(triangle_nodes: Array[TonnetzNode], orientation: int) -> void:
	var triangle = TriangleArea.new()
	triangle.orientation = orientation
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
	return node

func _create_line_from_to(start: Vector2, end: Vector2, color: Color):
	line_segments.append({
		"start": start,
		"end": end,
		"color": color
	})
	queue_redraw()

#only used for computing lines
func _get_line_endpoints(center: Vector2, neighbor_center: Vector2) -> Array[Vector2]:
	var unit = (neighbor_center - center).normalized()
	var radius_offset = unit * config.note_radius
	return [
		center + radius_offset,
		neighbor_center - radius_offset
	]

func get_logical_coord(coord: Vector2i) -> Vector2i:
	var row_column := _get_row_column(coord)
	var row = posmod(row_column.x, _get_wrap_row_period())
	var column = posmod(row_column.y, config.column_count)
	return _coord_from_row_column(row, column)

func get_node_logical_coord(node: TonnetzNode) -> Vector2i:
	return get_logical_coord(Vector2i(node.q, node.r))

func get_equivalent_nodes(node: TonnetzNode) -> Array:
	if not node:
		return []
	return logical_nodes.get(get_node_logical_coord(node), [])

func get_wrapped_coord(coord: Vector2i) -> Vector2i:
	var row_period = _get_wrap_row_period()
	var row_column := _get_row_column(coord)
	var row = posmod(row_column.x, row_period)
	var column = posmod(row_column.y, config.column_count)
	return _coord_from_row_column(row, column)

func _get_wrap_row_period() -> int:
	return max(1, min(int(config.row_count), int(config.wrap_row_count)))

func get_wrapped_node_neighbor(node: TonnetzNode, direction: Vector2i) -> TonnetzNode:
	if not node:
		return null

	var target_coord = Vector2i(node.q, node.r) + direction
	var direct_neighbor = nodes.get(target_coord)

	if direct_neighbor:
		return direct_neighbor

	return nodes.get(get_wrapped_coord(target_coord))

func get_wrapped_triangle_neighbor(triangle: TriangleArea, edge_index: int) -> TriangleArea:
	if not triangle:
		return null

	var direct_neighbor = triangle.neighbors.get(edge_index)

	if direct_neighbor:
		return direct_neighbor

	var edge_nodes = triangle.get_edge_nodes(edge_index)
	var edge_key := _get_wrapped_edge_key(edge_nodes)
	var candidates: Array = wrapped_triangle_edges.get(edge_key, [])

	for candidate in candidates:
		if candidate == triangle:
			continue

		if candidate.orientation != triangle.orientation:
			return candidate

	var center_candidate = _get_wrapped_triangle_neighbor_by_center(triangle, edge_index)

	if center_candidate:
		return center_candidate

	return null

func _build_wrapped_triangle_edge_index() -> void:
	wrapped_triangle_edges.clear()

	for triangle in triangles:
		for edge_index in range(3):
			var physical_edge_key := _get_edge_key_from_nodes(triangle.get_edge_nodes(edge_index))
			var edge_key := _get_wrapped_edge_key(triangle.get_edge_nodes(edge_index))

			_add_triangle_edge_index_entry(physical_edge_key, triangle)
			_add_triangle_edge_index_entry(edge_key, triangle)

func _add_triangle_edge_index_entry(edge_key: String, triangle: TriangleArea) -> void:
	if not wrapped_triangle_edges.has(edge_key):
		wrapped_triangle_edges[edge_key] = []

	if not wrapped_triangle_edges[edge_key].has(triangle):
		wrapped_triangle_edges[edge_key].append(triangle)

func _get_wrapped_edge_key(edge_nodes: Array[TonnetzNode]) -> String:
	var coords: Array[Vector2i] = []

	for node in edge_nodes:
		coords.append(_get_corresponding_wrapped_edge_coord(
			Vector2i(node.q, node.r),
			edge_nodes
		))

	return _get_edge_key_from_coords(coords)

func _get_edge_key_from_nodes(edge_nodes: Array[TonnetzNode]) -> String:
	var coords: Array[Vector2i] = []

	for node in edge_nodes:
		coords.append(Vector2i(node.q, node.r))

	return _get_edge_key_from_coords(coords)

func _get_edge_key_from_coords(edge_coords: Array[Vector2i]) -> String:
	var coords := PackedStringArray()

	for coord in edge_coords:
		coords.append("%d,%d" % [coord.x, coord.y])

	coords.sort()
	return "|".join(coords)

func _get_corresponding_wrapped_edge_coord(
	coord: Vector2i,
	edge_nodes: Array[TonnetzNode]
) -> Vector2i:
	var row_period := _get_wrap_row_period()
	var column_count := int(config.column_count)
	var row_column := _get_row_column(coord)
	var row := row_column.x
	var column := row_column.y

	if _edge_is_on_row(edge_nodes, 0):
		row = row_period - 1
	elif _edge_is_on_row(edge_nodes, row_period - 1):
		row = 0

	if _edge_is_on_column(edge_nodes, 0):
		column = column_count - 1
	elif _edge_is_on_column(edge_nodes, column_count - 1):
		column = 0

	return _coord_from_row_column(row, column)

func _edge_is_on_row(edge_nodes: Array[TonnetzNode], row: int) -> bool:
	for node in edge_nodes:
		if _get_row_column(Vector2i(node.q, node.r)).x != row:
			return false

	return true

func _edge_is_on_column(edge_nodes: Array[TonnetzNode], column: int) -> bool:
	for node in edge_nodes:
		if _get_row_column(Vector2i(node.q, node.r)).y != column:
			return false

	return true

func _get_row_column(coord: Vector2i) -> Vector2i:
	var row := coord.x + coord.y
	return Vector2i(row, -coord.y - _get_row_start_offset(row))

func _coord_from_row_column(row: int, column: int) -> Vector2i:
	var row_start_offset := _get_row_start_offset(row)
	return Vector2i(column + row + row_start_offset, -column - row_start_offset)

func _get_row_start_offset(row: int) -> int:
	return -ceili(float(row) / 2.0)

func _get_wrapped_triangle_neighbor_by_center(
	triangle: TriangleArea,
	edge_index: int
) -> TriangleArea:
	var target_key := _get_wrapped_target_triangle_center_key(triangle, edge_index)

	if target_key.is_empty():
		return null

	for candidate in triangles:
		if candidate == triangle:
			continue

		if candidate.orientation == triangle.orientation:
			continue

		if _get_wrapped_triangle_center_key(candidate) == target_key:
			return candidate

	return null

func _get_wrapped_target_triangle_center_key(
	triangle: TriangleArea,
	edge_index: int
) -> String:
	var edge_nodes = triangle.get_edge_nodes(edge_index)

	if edge_nodes.size() != 2 or triangle.nodes.size() != 3:
		return ""

	var opposite_node = null

	for node in triangle.nodes:
		if not edge_nodes.has(node):
			opposite_node = node
			break

	if not opposite_node:
		return ""

	var q3 = (
		2 * int(edge_nodes[0].q)
		+ 2 * int(edge_nodes[1].q)
		- int(opposite_node.q)
	)
	var r3 = (
		2 * int(edge_nodes[0].r)
		+ 2 * int(edge_nodes[1].r)
		- int(opposite_node.r)
	)
	return _get_wrapped_center3_key(q3, r3)

func _get_wrapped_triangle_center_key(triangle: TriangleArea) -> String:
	var q3 := 0
	var r3 := 0

	for node in triangle.nodes:
		q3 += int(node.q)
		r3 += int(node.r)

	return _get_wrapped_center3_key(q3, r3)

func _get_wrapped_center3_key(q3: int, r3: int) -> String:
	var row_period3 = _get_wrap_row_period() * 3
	var column_period3 = int(config.column_count) * 3
	var row3 = posmod(q3 + r3, row_period3)
	var column3 = posmod(-r3, column_period3)
	var wrapped_q3 = column3 + row3
	var wrapped_r3 = -column3
	return "%d,%d" % [wrapped_q3, wrapped_r3]

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

func get_tonnetz():
	return logical_nodes
	
func _build_triangle_graph() -> void:
	for triangle in triangles:
		triangle.neighbors.clear()

	for i in range(triangles.size()):
		for j in range(i + 1, triangles.size()):

			var first: TriangleArea = triangles[i]
			var second: TriangleArea = triangles[j]

			for edge_index in range(3):

				if first.shares_edge(second, edge_index):

					first.neighbors[edge_index] = second

			for edge_index in range(3):

				if second.shares_edge(first, edge_index):

					second.neighbors[edge_index] = first
					
func _build_node_graph() -> void:
	for node in nodes.values():
		node.neighbors.clear()

	for coord in nodes.keys():
		var node = nodes[coord]
		for direction in AXIAL_DIRECTIONS:
			var neighbor = nodes.get(coord + direction)
			if neighbor:
				node.neighbors[direction] = neighbor
