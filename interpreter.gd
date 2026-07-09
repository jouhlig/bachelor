extends Node
@onready var builder: TonnetzBuilder = get_node("/root/Game/UI/TonnetzViewportContainer/TonnetzViewport/TonnetzWorld/TonnetzBuilder")
@onready var config = Config.config

var action_list = []
var dir: Vector2i
var current_edge : int
var last_step_wrapped := false

#enum NoteLength {FULL, HALF, QUARTER, EIGHTH}
var note_lengths := {
	"full": 4.0,
	"half": 2.0,
	"quarter": 1.0,
	"eighth": 0.5
}
var note_length: float


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	note_length = note_lengths["quarter"]
	dir = Vector2i(1,0)
	current_edge = 0


func set_actions(
	instructions: String,
	start_anchor,
	current_beat: float,
	repeat_count: int,
	explore_mode: bool,
	initial_dir: Vector2i,
	initial_edge: int
):
	#clear last actions up
	action_list.clear()
	clear_state()
	set_initial_direction(initial_dir, initial_edge)
	if not start_anchor:
		return []

	#print("start_position: ", start_pos, ", mode: ", mode)
	var current_anchor = start_anchor

	var beat_cursor: float = 0.0
	var hit_border := false
	#treat the first position as a step already - otherwise missing one step
	action_list.append({
		"anchor": current_anchor,
		"draw_trail": true,
	})
	#print("Instructions: ", instructions)
	
	for repetition in range(repeat_count):
		if hit_border:
			break

		for i in instructions.length():
			if hit_border:
				break

			var char = instructions [i]
		#for char in instructions:
			match char:
				"l":
					if current_anchor is TriangleArea:
						turn_left_triangle()
					else:
						turn_left_node()
				"r":
					if current_anchor is TriangleArea:
						turn_right_triangle()
					else:
						turn_right_node()
				"s":
					#print("step")
					var next_anchor = step(current_anchor, beat_cursor)
					if bool(next_anchor.get("blocked", false)):
						hit_border = true
						break

					current_anchor = next_anchor["anchor"]
					beat_cursor = next_anchor["beat_cursor"]
				"1":
					note_length = note_lengths["full"]
				"2":
					note_length = note_lengths["half"]
				"4":
					note_length = note_lengths["quarter"]
				"8":
					note_length = note_lengths["eighth"]
	if action_list.size() > 1:
		action_list[-1]["duration_beats"] = note_length
		if not explore_mode:
			action_list[-1]["draw_trail"] = false

	return action_list.duplicate(true)

func clear_state():
	note_length = note_lengths["quarter"]
	dir = Vector2i(1,0)
	current_edge = 0

func set_initial_direction(new_dir: Vector2i, new_edge: int) -> void:
	dir = new_dir
	current_edge = new_edge

func turn_left_node():
	var q = dir.x
	var r = dir.y
	var s = -q - r
	dir = Vector2i(-s, -q)
func turn_left_triangle():
	current_edge = (current_edge+1)%3
	
func turn_right_node():
	var q = dir.x
	var r = dir.y
	var s = -q - r
	dir = Vector2i(-r, -s)
	
func turn_right_triangle():
	#have to use +2 instead of -1 here to prevent bugs in context of negative modulo operations
	current_edge = (current_edge+2)%3
	
func step(
	current_anchor,
	beat_cursor: float
	) -> Dictionary:
	last_step_wrapped = false
	var next_anchor = get_next_anchor(current_anchor)
	var new_time = beat_cursor + note_length

	if not next_anchor:
		push_warning("L-system turtle hit the Tonnetz border and stopped.")
		return {
			"anchor": current_anchor,
			"beat_cursor": beat_cursor,
			"blocked": true
		}

	if last_step_wrapped and not action_list.is_empty():
		var current_event = action_list[-1]
		current_event["duration_beats"] = note_length
		current_event["hide_turtle_during_transition"] = true
		current_event["draw_trail"] = false
		action_list[-1] = current_event
	elif not action_list.is_empty():
		var current_event = action_list[-1]
		current_event["duration_beats"] = note_length
		action_list[-1] = current_event

	action_list.append({
			"anchor": next_anchor,
			"draw_trail": true,
		})
	
	return {"anchor": next_anchor, "beat_cursor": new_time}

func get_next_anchor(current_anchor):
	if current_anchor is TriangleArea:
		return get_next_triangle_anchor(current_anchor)

	if current_anchor is TonnetzNode:
		return get_next_node_anchor(current_anchor)

	return null

func get_next_triangle_anchor(current_anchor: TriangleArea):
	var next_anchor = current_anchor.get_next(current_edge)

	if next_anchor:
		current_edge = get_edge_between_triangles(next_anchor, current_anchor)
		return next_anchor

	next_anchor = builder.get_wrapped_triangle_neighbor(current_anchor, current_edge)

	if next_anchor:
		last_step_wrapped = true
		current_edge = get_edge_between_triangles(next_anchor, current_anchor)
		return next_anchor

	return null

func get_edge_between_triangles(from_triangle: TriangleArea, target_triangle: TriangleArea) -> int:
	for edge_index in range(3):
		if from_triangle.get_next(edge_index) == target_triangle:
			return edge_index

		if builder.get_wrapped_triangle_neighbor(from_triangle, edge_index) == target_triangle:
			return edge_index

	return current_edge

func get_next_node_anchor(current_anchor: TonnetzNode):
	var next_anchor = current_anchor.get_next(dir)

	if next_anchor:
		return next_anchor

	next_anchor = builder.get_wrapped_node_neighbor(current_anchor, dir)

	if next_anchor:
		last_step_wrapped = true

	return next_anchor
