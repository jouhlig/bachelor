extends Node
@onready var builder: TonnetzBuilder = get_node("/root/Game/TonnetzBuilder")
@onready var config = Config.config
var action_list = []
var dir: Vector2i
var current_edge : int
enum PenState { UP, DOWN }
var pen_status: int 
enum NoteLength {FULL, HALF, QUARTER, EIGHTH}
var note_length: int


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	note_length = NoteLength.QUARTER
	pen_status = PenState.DOWN
	dir = Vector2i(1,0)
	current_edge = 0
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func set_actions(instructions: String, snapped_pos: Vector2, current_beat: float = -1.0):
	#clear last actions up
	action_list.clear()
	clear_state()
	#decide if we are in triangle or node mode
	var start_anchor = builder.get_nearest_spawn_anchor(snapped_pos)

	#print("start_position: ", start_pos, ", mode: ", mode)
	var current_anchor = start_anchor

	var beat_cursor: float = current_beat
	if beat_cursor < 0.0:
		beat_cursor = CL.get_time_beat()
	#treat the first position as a step already - otherwise missing one step
	action_list.append({
		"anchor": current_anchor,
		"pen_status": pen_status,
		"start_beat": beat_cursor,
		"duration_beats": 0.0,
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
				current_anchor = next_anchor.anchor
				beat_cursor = next_anchor.beat_cursor
			"u": 
				#print("pen up")
				pen_status = PenState.UP
			"d": 
				#print("pen down")
				pen_status = PenState.DOWN
			"1": note_length = NoteLength.FULL
			"2": note_length = NoteLength.HALF
			"4": note_length = NoteLength.QUARTER
			"8": note_length = NoteLength.EIGHTH
	#print("Action list: ", action_list)
	return action_list
func clear_state():
	note_length = NoteLength.QUARTER
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
	var next_anchor
	if current_anchor is TriangleArea:
		next_anchor = current_anchor.get_next(current_edge)
	else:
		next_anchor = current_anchor.get_next(dir)
	#print("NOTE STATES: FULL: ", NoteLength.FULL, ", HALF: ", NoteLength.HALF, ", QUARTER: " , NoteLength.QUARTER, ", EIGHTH: ", NoteLength.EIGHTH)
	#print("Note length: ", note_length)
	var duration = toTime(note_length)
	#print(duration)
	if duration == -1:
		push_error("Error with time duration in interpreter")
	action_list.append({
			"anchor": next_anchor,
			"pen_status": pen_status,
			"start_beat": beat_cursor,
			"duration_beats": duration,
		})
	beat_cursor += duration

	if next_anchor:
		return {"anchor": next_anchor, "beat_cursor": beat_cursor}
	push_error("No Anchor found at %s" % next_anchor)
	return {"anchor": current_anchor, "beat_cursor": beat_cursor}

#func pen_down():
	#pen_status = PenState.DOWN
#
#func pen_up():
	#pen_status = PenState.UP
#
#func next_is_full():
	#note_length = NoteLength.FULL
#
#func next_is_half():
	#note_length = NoteLength.HALF
#
#func next_is_quarter():
	#note_length = NoteLength.QUARTER
#
#func next_is_eighth():
	#note_length = NoteLength.EIGHTH

func toTime(note_length) -> float:
	match note_length:
		NoteLength.FULL:
			return 4.0
		NoteLength.HALF:
			return 2.0
		NoteLength.QUARTER:
			return 1.0
		NoteLength.EIGHTH:
			return 0.5
	return -1
