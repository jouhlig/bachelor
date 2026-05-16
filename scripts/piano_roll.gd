extends Control
class_name PianoRoll

@onready var actions
@onready var game = get_node("/root")
@onready var builder: TonnetzBuilder = get_node("/root/Game/TonnetzBuilder")
var notes: Array[PianoNote] = []

@onready var font = ThemeDB.fallback_font
@onready var config: TonnetzConfig = Config.config
@onready var scroll_parent: ScrollContainer = $ScrollContainer
@onready var content: Control = $ScrollContainer/PianoRollContent
@onready var header: Control = $Header
@onready var sidebar: Control = $Sidebar

var MAX_PITCH = 40
var MIN_PITCH = 0
const CELL_WIDTH = 60
const CELL_HEIGHT = 22
const OFFSET_LEFT = 40
const TOP_OFFSET = 15

func _update_pitch_range() -> void:
	if builder and builder.nodes.size() > 0:
		MIN_PITCH = 9999
		MAX_PITCH = -9999
		for node in builder.nodes.values():
			MIN_PITCH = min(MIN_PITCH, node.pitch)
			MAX_PITCH = max(MAX_PITCH, node.pitch)
		if MAX_PITCH == MIN_PITCH:
			MAX_PITCH += 1
		return

	if notes.is_empty():
		MAX_PITCH = 40
		MIN_PITCH = 0
		return

	MIN_PITCH = notes[0].pitch
	MAX_PITCH = notes[0].pitch
	for note in notes:
		MIN_PITCH = min(MIN_PITCH, note.pitch)
		MAX_PITCH = max(MAX_PITCH, note.pitch)
	if MAX_PITCH == MIN_PITCH:
		MAX_PITCH += 1

var scroll_beat := 0.0
var auto_follow := false
var play_beat := 0.0
var beats_per_bar = 4
var previous_scroll := Vector2.ZERO

func _ready() -> void:
	size = config.pianoroll_size
	position = config.pianoroll_start_pos
	
	_update_pitch_range()
	_resize_children()


func _process(delta):
	play_beat += delta / get_seconds_per_beat()

	if auto_follow and scroll_parent:
		var viewport_width = scroll_parent.size.x
		var visible_beats = viewport_width / CELL_WIDTH
		var target_scroll_beat = CL.time_beat - visible_beats * 0.5
		scroll_beat = target_scroll_beat
		var target_px = int(OFFSET_LEFT + target_scroll_beat * CELL_WIDTH)
		var current_px = scroll_parent.scroll_horizontal
		scroll_parent.scroll_horizontal = int(lerp(current_px, target_px, 0.2))

	if scroll_parent:
		var current_scroll = Vector2(scroll_parent.scroll_horizontal, scroll_parent.scroll_vertical)
		if current_scroll != previous_scroll:
			previous_scroll = current_scroll
			header.refresh_view(scroll_parent.scroll_horizontal)
			sidebar.refresh_view(scroll_parent.scroll_vertical)

	# Redraw content to update playback position indicator
	content.queue_redraw()

func get_seconds_per_beat() -> float:
	return 60.0 / CL.bpm

func pitch_to_name(pitch: int) -> String:
	var names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "H"]
	return names[pitch % 12]

func _resize_children() -> void:
	if scroll_parent == null or header == null or sidebar == null:
		push_warning("PianoRoll _resize_children skipped because a child node is missing: ScrollContainer=%s Header=%s Sidebar=%s" % [scroll_parent, header, sidebar])
		return

	scroll_parent.position = Vector2(OFFSET_LEFT, TOP_OFFSET)
	scroll_parent.size = Vector2(size.x - OFFSET_LEFT, size.y - TOP_OFFSET)

	header.position = Vector2(OFFSET_LEFT, 0)
	header.size = Vector2(size.x-OFFSET_LEFT, TOP_OFFSET)
	header.custom_minimum_size = Vector2(config.length_bars*beats_per_bar*CELL_WIDTH, TOP_OFFSET)

	sidebar.position = Vector2(0, TOP_OFFSET)
	sidebar.size = Vector2(OFFSET_LEFT, size.y - TOP_OFFSET)
	
	content.custom_minimum_size = Vector2(config.length_bars*beats_per_bar*CELL_WIDTH, (MAX_PITCH - MIN_PITCH + 1) * CELL_HEIGHT)


func get_action_length() -> float:
	var time := 0.0
	var step := 1.0
	if actions:
		for action in actions:
			if action.has("pitches"):
				time += step
		return time
	else: return 0.0

func set_actions(new_actions):
	actions = new_actions
	notes.clear()

	for item in actions:
		var note = PianoNote.new()
		note.start_beat = float(item.get("start_beat", 0.0))
		note.duration_beats = float(item.get("duration_beats", 1.0))
		if item.has("node") and item["node"] is TonnetzNode:
			note.pitch = int(item["node"].pitch)
		elif item.has("pitch"):
			note.pitch = int(item["pitch"])
		else:
			note.pitch = 0
		notes.append(note)

	_update_pitch_range()
	_resize_children()
	content.queue_redraw()
	header.queue_redraw()
	sidebar.queue_redraw()

func update_roll(action_list):
	actions = action_list
	notes.clear()

	for item in action_list:
		var note = PianoNote.new()
		note.start_beat = float(item.get("start_beat", 0.0))
		note.duration_beats = float(item.get("duration_beats", 1.0))
		if item.has("node") and item["node"] is TonnetzNode:
			note.pitch = int(item["node"].pitch)
		elif item.has("pitch"):
			note.pitch = int(item["pitch"])
		else:
			note.pitch = 0
		notes.append(note)

	_update_pitch_range()
	_resize_children()
	content.queue_redraw()
	header.queue_redraw()
	sidebar.queue_redraw()
