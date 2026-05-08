extends Control
class_name PianoRoll

@onready var actions
@onready var game = get_node("/root")
var notes: Array[PianoNote] = []

@onready var font = ThemeDB.fallback_font


var MAX_PITCH = 11
var MIN_PITCH = 0
const CELL_WIDTH = 60
const CELL_HEIGHT = 22
const OFFSET_LEFT = 30

var scroll_beat := 0.0
var auto_follow := false
var play_beat := 0.0
var beats_per_bar = 4

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	queue_redraw()
func _process(delta):
	play_beat += delta / get_seconds_per_beat()

	
	if auto_follow:
		var visible_beats = (size.x - OFFSET_LEFT) / CELL_WIDTH
		scroll_beat = CL.time_beat - visible_beats * 0.5
	queue_redraw()
func get_seconds_per_beat() -> float:
	return 60.0 / CL.bpm

func pitch_to_name(pitch: int) -> String:
	var names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "H"]
	var note = names[pitch % 12]
	return note
	
func get_required_size() -> Vector2i:
	return Vector2i(1920, CELL_HEIGHT * MAX_PITCH)
	
func set_actions(actions):
	notes.clear()

	var time := 0.0
	var step := 1.0  

	for action in actions:
		if action.has("pitches"):
			#print(pitches)
			for pitch in action["pitches"]:   
				var note = PianoNote.new()
				note.start_beat = time
				note.duration_beats = step
				note.pitch = pitch
				notes.append(note)
				#print("added action in piano roll: ", note.pitch)
			time += step
	queue_redraw()
func _draw():
	var seconds_per_beat = get_seconds_per_beat()
	
	var visible_time_span = (size.x - OFFSET_LEFT) / CELL_WIDTH
	var start_time = scroll_beat
	var end_time = scroll_beat + visible_time_span

	# draw grid
	var first_step = floor(start_time / seconds_per_beat)

	for i in range(2000):
		var t = (first_step + i) * seconds_per_beat
		if t > end_time:
			break

		var x = OFFSET_LEFT + (t - scroll_beat) * CELL_WIDTH 

		var beat_index = int(round(t / seconds_per_beat))
		var is_beat = abs(t - beat_index * seconds_per_beat) < 0.0001
		var is_bar = beat_index % beats_per_bar == 0

		var color = Color(0.2, 0.2, 0.2)

		if is_bar:
			color = Color(0.8, 0.8, 0.8)
		elif is_beat:
			color = Color(0.5, 0.5, 0.5)

		draw_line(Vector2(x, 0), Vector2(x, size.y), color, 1)

	# --- DRAW NOTES ---
	for note in notes:
		var note_start_seconds = note.start_beat * get_seconds_per_beat()
		var note_end_seconds = (note.start_beat + note.duration_beats) * get_seconds_per_beat()

		var x = OFFSET_LEFT + (note_start_seconds - scroll_beat) * CELL_WIDTH
		var w = (note_end_seconds - note_start_seconds) * CELL_WIDTH

		var y = (MAX_PITCH - note.pitch) * CELL_HEIGHT
		var h = CELL_HEIGHT

		draw_rect(Rect2(x, y, w, h), Color.SKY_BLUE)

	# --- DRAW NOTE LABELS ---
	draw_rect(Rect2(0, 0, OFFSET_LEFT, 12*CELL_HEIGHT), Color.BLACK)
	for pitch in range(MIN_PITCH, MAX_PITCH + 1):
		var y = (MAX_PITCH - pitch) * CELL_HEIGHT

		draw_string(
			font,
			Vector2(5, y + CELL_HEIGHT - 4),
			pitch_to_name(pitch)
		)
