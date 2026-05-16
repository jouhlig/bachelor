extends Node
@onready var builder: TonnetzBuilder = get_node("/root/Game/TonnetzBuilder")
@onready var config = Config.config
var action_list = []
var dir = Vector2i(1,0)
enum PenState { UP, DOWN }
var pen_status: int = PenState.DOWN
enum NoteLength {HALF, QUARTER, EIGHTH}
var note_length: int = NoteLength.QUARTER

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func set_actions(instructions: String, snapped_pos: Vector2, current_beat: float = -1.0):
	var start_node = builder.get_nearest_spawn_anchor(snapped_pos)
	var current_node = start_node
	var beat_cursor: float = current_beat
	if beat_cursor < 0.0:
		beat_cursor = CL.get_time_beat()

	for char in instructions:
		match char:
			"l": turn_left()
			"r": turn_right()
			"s":
				var res = step(current_node, beat_cursor)
				current_node = res.node
				beat_cursor = res.beat_cursor
			"u": pen_up()
			"d": pen_down()
			"2": next_is_half()
			"4": next_is_quarter()
			"8": next_is_eigth()

	# optionally return the final node or action path
	return action_list

func turn_left():
	var q = dir.x
	var r = dir.y
	var s = -q - r
	dir = Vector2i(-s, -q)

func turn_right():
	var q = dir.x
	var r = dir.y
	var s = -q - r
	dir = Vector2i(-r, -s)

func step(current_node: TonnetzNode, beat_cursor: float) -> Dictionary:
	var current_coord = Vector2i(current_node.q, current_node.r)
	var next_coord = current_coord + dir
	var next_node: TonnetzNode = builder.nodes.get(next_coord)

	if next_node:
		var duration = _note_length_beats()
		action_list.append({
			"node": next_node,
			"pen_status": pen_status,
			"start_beat": beat_cursor,
			"duration_beats": duration,
		})
		beat_cursor += duration
		return {"node": next_node, "beat_cursor": beat_cursor}

	push_warning("No Tonnetz node found at %s" % next_coord)
	return {"node": current_node, "beat_cursor": beat_cursor}

func pen_down():
	pen_status = PenState.DOWN

func pen_up():
	pen_status = PenState.UP

func next_is_half():
	note_length = NoteLength.HALF

func next_is_quarter():
	note_length = NoteLength.QUARTER

func next_is_eigth():
	note_length = NoteLength.EIGHTH

func _note_length_beats() -> float:
	match note_length:
		NoteLength.HALF:
			return 2.0
		NoteLength.QUARTER:
			return 1.0
		NoteLength.EIGHTH:
			return 0.5
	return 1.0
