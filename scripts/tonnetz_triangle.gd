extends Node2D
class_name TonnetzTriangle

# represents one triangle in the Tonnetz

#nodes are ordered CLOCKWISE
var nodes: Array[TonnetzNode] = []
enum Orientation {UP, DOWN}
var orientation: int
var neighbors := {}

func shares_edge(
	other: TonnetzTriangle,
	edge_index: int
) -> bool:

	var edge = get_edge_nodes(edge_index)

	var a = edge[0]
	var b = edge[1]

	return (
		other.nodes.has(a)
		and other.nodes.has(b)
	)
	
func get_edge_nodes(edge_index: int) -> Array[TonnetzNode]:
	return [
		nodes[edge_index],
		nodes[(edge_index + 1) % 3]
	]
	
func set_nodes(node_array: Array[TonnetzNode]):
	nodes = node_array
	
	# Compute average position
	var avg_pos = Vector2.ZERO
	for n in nodes:
		avg_pos += n.position
	avg_pos /= 3
	position = avg_pos
	
	# Collision is no longer used, notes are triggered by Sequencer events.
	
	# Set collision layer and mask
	# Removed together with the old player collision audio path.
	
func get_pitches()->Array[int]:
	var pitches : Array[int] = []
	for n in nodes:
		pitches.append(n.pitch)
	return pitches
		
func get_center() -> Vector2:
	return global_position

func get_next(edge_index: int) -> TonnetzTriangle:
	return neighbors.get(edge_index)


func get_node_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for n in nodes:
		coords.append(Vector2i(n.q, n.r))
	return coords
