extends Node
@onready var builder: TonnetzBuilder = get_node("/root/Game/UI/TonnetzViewportContainer/TonnetzViewport/TonnetzWorld/TonnetzBuilder")
@onready var config = Config.config

var action_list = []
var dir: Vector2i
var current_edge : int

enum PenState { UP, DOWN }
var pen_status: int 

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
	pen_status = PenState.DOWN
	dir = Vector2i(1,0)
	current_edge = 0


func set_actions(instructions: String, snapped_pos: Vector2, current_beat: float = -1.0):
	#clear last actions up
	action_list.clear()
	clear_state()
	#decide if we are in triangle or node mode
	var start_anchor = builder.get_nearest_spawn_anchor(snapped_pos)
	if not start_anchor:
		return []

	#print("start_position: ", start_pos, ", mode: ", mode)
	var current_anchor = start_anchor

	var beat_cursor: float = 0.0

	#treat the first position as a step already - otherwise missing one step
	action_list.append({
		"anchor": current_anchor,
		"pen_status": pen_status,
		"start_beat": beat_cursor,
		"draw_trail": true,
	})
	#print("Instructions: ", instructions)

	for char in instructions:
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
				current_anchor = next_anchor["anchor"]
				beat_cursor = next_anchor["start_beat"]
			"u": 
				#print("pen up")
				pen_status = PenState.UP
			"d": 
				#print("pen down")
				pen_status = PenState.DOWN
			"1": note_length = note_lengths["full"]
			"2": note_length = note_lengths["half"]
			"4": note_length = note_lengths["quarter"]
			"8": note_length = note_lengths["eighth"]
	print("Action list: ", action_list)
	#close loop by connecting last element to first element
	if action_list.size() > 1:
		action_list[-1]["draw_trail"] = false

		action_list.append({
			"anchor": action_list[0]["anchor"],
			"pen_status": action_list[0]["pen_status"],
			"start_beat": beat_cursor + note_length,
			"draw_trail": false,
		})

	for i in range(action_list.size() - 1):
		action_list[i]["duration_beats"] = (
			action_list[i + 1]["start_beat"]
			- action_list[i]["start_beat"]
		)

	if not action_list.is_empty():
		action_list[-1]["duration_beats"] = note_length

	return action_list.duplicate(true)

func clear_state():
	note_length = note_lengths["quarter"]
	pen_status = PenState.DOWN
	dir = Vector2i(1,0)
	current_edge = 0
	
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
	
func step(current_anchor, beat_cursor: float) -> Dictionary:
	var next_anchor = get_next_anchor(current_anchor)
	var new_time = beat_cursor + note_length

	if not next_anchor:
		next_anchor = current_anchor

	action_list.append({
			"anchor": next_anchor,
			"pen_status": pen_status,
			#store time as beat counter, eg anchor A has time 0 and duration is supposed to be a quarter note, then B should have time 4.0
			"start_beat": new_time,
			"draw_trail": true,
		})

	return {"anchor": next_anchor, "start_beat": new_time}

func get_next_anchor(current_anchor):
	if current_anchor is TriangleArea:
		return get_next_triangle_anchor(current_anchor)

	if current_anchor is TonnetzNode:
		return get_next_node_anchor(current_anchor)

	return null

func get_next_triangle_anchor(current_anchor: TriangleArea):
	var next_anchor = current_anchor.get_next(current_edge)

	if next_anchor:
		return next_anchor

	for offset in range(1, 3):
		var fallback_edge = (current_edge + offset) % 3
		next_anchor = current_anchor.get_next(fallback_edge)

		if next_anchor:
			current_edge = fallback_edge
			return next_anchor

	return null

func get_next_node_anchor(current_anchor: TonnetzNode):
	var next_anchor = current_anchor.get_next(dir)

	if next_anchor:
		return next_anchor

	for fallback_dir in current_anchor.neighbors.keys():
		next_anchor = current_anchor.get_next(fallback_dir)

		if next_anchor:
			dir = fallback_dir
			return next_anchor

	return null
