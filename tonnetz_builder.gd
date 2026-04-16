extends Node
class_name TonnetzBuilder

@export var config: TonnetzConfig
var nodes: Dictionary[Vector2i, TonnetzNode] = {}

const axial_directions = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)
]

func _ready() -> void:
	if not config:
		config = TonnetzConfig.new()

func build(radius: int):
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
			
			# Triangle 2: (q+1,r), (q+1,r-1), (q,r)
			var n4 = get_tonnetz_node(q + 1, r)
			var n5 = get_tonnetz_node(q + 1, r - 1)
			var n6 = get_tonnetz_node(q, r)
			if n4 and n5 and n6:
				var tri2 = TriangleArea.new()
				tri2.config = config
				tri2.set_nodes([n4, n5, n6])
				add_child(tri2)
	
	center_on_canvas()

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
