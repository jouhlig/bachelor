extends Control
class_name PianoRoll

signal bar_selection_changed(selection: Dictionary)

@onready var game = get_node("/root")
@onready var builder: TonnetzBuilder = get_node("/root/Game/UI/TonnetzViewportContainer/TonnetzViewport/TonnetzWorld/TonnetzBuilder")
var notes: Array[PianoNote] = []

@onready var font = ThemeDB.fallback_font
@onready var config: TonnetzConfig = Config.config
@onready var scroll_parent: ScrollContainer = $ScrollContainer
@onready var content: Control = $ScrollContainer/PianoRollContent
@onready var header: Control = $Header
@onready var sidebar: Control = $Sidebar
@onready var note_value: NoteValueCalculator = get_node("/root/NoteValue")

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

var auto_follow := false
var global_paused := false
var beats_per_bar = 4
var previous_scroll := Vector2.ZERO

var cycle_origin_beat := 0.0
var cycle_length_beats := 0.0
var active_lsystem_index := -1
var active_lsystem_color := Color.WHITE
var selected_bar_start := -1
var selected_bar_end := -1
var selection_anchor_bar := -1
var selection_dragging := false

func _ready() -> void:
	size = config.pianoroll_size
	position = config.pianoroll_start_pos
	scroll_parent.mouse_filter = Control.MOUSE_FILTER_PASS
	
	_update_pitch_range()
	_resize_children()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_resize_children()


func _process(_delta):
	if auto_follow and not global_paused and scroll_parent:
		var viewport_width = scroll_parent.size.x
		var visible_beats = viewport_width / CELL_WIDTH
		var target_scroll_beat = CL.time_beat - visible_beats * 0.5
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

func set_global_paused(paused: bool) -> void:
	global_paused = paused

func set_cycle(length_beats: float, origin_beat: float = 0.0) -> void:
	cycle_origin_beat = origin_beat
	cycle_length_beats = max(0.0, length_beats)
	_refresh()

func set_active_lsystem_context(index: int, color: Color) -> void:
	active_lsystem_index = index
	active_lsystem_color = color

func get_cycle_length_beats() -> float:
	return cycle_length_beats

func get_cycle_local_beat(absolute_beat: float) -> float:
	if cycle_length_beats <= 0.0:
		return absolute_beat

	return fposmod(absolute_beat - cycle_origin_beat, cycle_length_beats)

func pitch_to_name(pitch: int) -> String:
	return note_value.get_note_name(pitch)

func _resize_children() -> void:
	if scroll_parent == null or header == null or sidebar == null:
		push_warning("PianoRoll _resize_children skipped because a child node is missing: ScrollContainer=%s Header=%s Sidebar=%s" % [scroll_parent, header, sidebar])
		return

	scroll_parent.position = Vector2(OFFSET_LEFT, TOP_OFFSET)
	scroll_parent.size = Vector2(
		max(0.0, size.x - OFFSET_LEFT),
		max(0.0, size.y - TOP_OFFSET)
	)

	header.position = Vector2(OFFSET_LEFT, 0)
	header.size = Vector2(max(0.0, size.x - OFFSET_LEFT), TOP_OFFSET)
	header.custom_minimum_size = Vector2(get_total_beats() * CELL_WIDTH, TOP_OFFSET)

	sidebar.position = Vector2(0, TOP_OFFSET)
	sidebar.size = Vector2(OFFSET_LEFT, max(0.0, size.y - TOP_OFFSET))
	
	content.custom_minimum_size = Vector2(get_total_beats() * CELL_WIDTH, (MAX_PITCH - MIN_PITCH + 1) * CELL_HEIGHT)

func get_total_beats() -> float:
	var total_beats := float(config.length_bars * beats_per_bar)

	if cycle_length_beats > 0.0:
		return max(total_beats, cycle_length_beats)

	for note in notes:
		total_beats = max(
			total_beats,
			note.start_beat + note.duration_beats + beats_per_bar
		)

	return total_beats

func get_total_bars() -> int:
	return max(
		1,
		int(ceil(get_total_beats() / beats_per_bar))
	)

func has_bar_selection() -> bool:
	return selected_bar_start >= 0 and selected_bar_end >= selected_bar_start

func get_selected_bar_range() -> Vector2i:
	if not has_bar_selection():
		return Vector2i(-1, -1)

	return Vector2i(selected_bar_start, selected_bar_end)

func get_selected_bar_start_beat() -> float:
	if not has_bar_selection():
		return -1.0

	return float(selected_bar_start * beats_per_bar)

func get_selected_bar_end_beat() -> float:
	if not has_bar_selection():
		return -1.0

	return float((selected_bar_end + 1) * beats_per_bar)

func scroll_to_beat(beat: float) -> void:
	if not scroll_parent:
		return

	var viewport_width = scroll_parent.size.x
	var target_scroll_beat = max(0.0, beat - (viewport_width / CELL_WIDTH) * 0.15)
	scroll_parent.scroll_horizontal = int(OFFSET_LEFT + target_scroll_beat * CELL_WIDTH)
	previous_scroll = Vector2(scroll_parent.scroll_horizontal, scroll_parent.scroll_vertical)
	header.refresh_view(scroll_parent.scroll_horizontal)
	sidebar.refresh_view(scroll_parent.scroll_vertical)

func get_selected_bar_rect(view_scroll_x: float = 0.0) -> Rect2:
	if not has_bar_selection():
		return Rect2()

	var start_x = selected_bar_start * beats_per_bar * CELL_WIDTH - view_scroll_x
	var width = (selected_bar_end - selected_bar_start + 1) * beats_per_bar * CELL_WIDTH
	return Rect2(start_x, 0.0, width, content.size.y)

func get_selected_header_rect(view_scroll_x: float = 0.0) -> Rect2:
	if not has_bar_selection():
		return Rect2()

	var start_x = selected_bar_start * beats_per_bar * CELL_WIDTH - view_scroll_x
	var width = (selected_bar_end - selected_bar_start + 1) * beats_per_bar * CELL_WIDTH
	return Rect2(start_x, 0.0, width, header.size.y)

func clear_events() -> void:
	notes.clear()
	_refresh()

func remove_events_for_lsystem(index: int) -> void:
	notes = notes.filter(func(note):
		return note.lsystem_index != index
	)
	_refresh()

func shift_lsystem_indices_after_removal(index: int) -> void:
	for note in notes:
		if note.lsystem_index > index:
			note.lsystem_index -= 1

func add_event(event: Dictionary, color: Color, lsystem_index: int = -1) -> void:
	if float(event.get("duration_beats", 0.0)) <= 0.0:
		return

	var anchor = event.get("anchor")
	var event_notes: Array = []

	if anchor is TriangleArea:
		event_notes = anchor.nodes
	elif anchor is TonnetzNode:
		event_notes = [anchor]
	else:
		return

	for tonnetz_node in event_notes:
		var note = PianoNote.new()
		note.start_beat = float(event.get("start_beat", CL.get_time_beat()))
		note.duration_beats = float(event.get("duration_beats", 1.0))
		note.pitch = int(tonnetz_node.pitch)
		note.color = color
		note.lsystem_index = lsystem_index
		notes.append(note)

	_refresh()

func _refresh() -> void:
	_update_pitch_range()
	_resize_children()
	content.queue_redraw()
	header.queue_redraw()
	sidebar.queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var bar_index = _get_bar_index_from_local_position(event.position)

			if bar_index == -1:
				return

			selected_bar_start = bar_index
			selected_bar_end = bar_index
			selection_anchor_bar = bar_index
			selection_dragging = true
			auto_follow = false
			_refresh()
			accept_event()
			return

		if selection_dragging:
			selection_dragging = false
			_emit_bar_selection()
			_refresh()
			accept_event()
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		clear_bar_selection()
		accept_event()
		return

	if event is InputEventMouseMotion and selection_dragging:
		var bar_index = _get_bar_index_from_local_position(event.position)

		if bar_index == -1:
			bar_index = _get_clamped_bar_index(event.position)

		selected_bar_start = min(selection_anchor_bar, bar_index)
		selected_bar_end = max(selection_anchor_bar, bar_index)
		_refresh()
		accept_event()

func clear_bar_selection() -> void:
	selected_bar_start = -1
	selected_bar_end = -1
	selection_anchor_bar = -1
	selection_dragging = false
	_refresh()
	bar_selection_changed.emit({})

func _get_bar_index_from_local_position(local_position: Vector2) -> int:
	var inside_header = (
		local_position.x >= OFFSET_LEFT
		and local_position.x <= size.x
		and local_position.y >= 0.0
		and local_position.y <= TOP_OFFSET
	)
	var inside_content = (
		local_position.x >= OFFSET_LEFT
		and local_position.x <= size.x
		and local_position.y >= TOP_OFFSET
		and local_position.y <= size.y
	)

	if not inside_header and not inside_content:
		return -1

	var content_x = local_position.x - OFFSET_LEFT + scroll_parent.scroll_horizontal
	return clamp(
		int(floor(content_x / float(beats_per_bar * CELL_WIDTH))),
		0,
		get_total_bars() - 1
	)

func _get_clamped_bar_index(local_position: Vector2) -> int:
	var content_x = local_position.x - OFFSET_LEFT + scroll_parent.scroll_horizontal
	return clamp(
		int(floor(content_x / float(beats_per_bar * CELL_WIDTH))),
		0,
		get_total_bars() - 1
	)

func _emit_bar_selection() -> void:
	if not has_bar_selection():
		return

	bar_selection_changed.emit({
		"start_bar": selected_bar_start,
		"end_bar": selected_bar_end,
		"start_beat": selected_bar_start * beats_per_bar,
		"end_beat": (selected_bar_end + 1) * beats_per_bar,
		"active_lsystem_index": active_lsystem_index,
		"target_color": active_lsystem_color,
		"bar_count": selected_bar_end - selected_bar_start + 1
	})
