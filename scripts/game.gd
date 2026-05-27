extends Node2D

@onready var tonnetz_world: Node2D = $UI/TonnetzViewportContainer/TonnetzViewport/TonnetzWorld
@onready var builder: TonnetzBuilder = $UI/TonnetzViewportContainer/TonnetzViewport/TonnetzWorld/TonnetzBuilder
@onready var piano_roll: PianoRoll = $UI/PianoRoll
@onready var interpreter = $Interpreter
@onready var sequencer: Sequencer = $Sequencer
@onready var turtle: Turtle = $UI/TonnetzViewportContainer/TonnetzViewport/TonnetzWorld/Turtle
@onready var audio_manager: AudioManager = $AudioManager

var turtle_scene: PackedScene = preload("res://Turtle.tscn")

@export var animations_on := false
@export var lsystem_on := true

var config: TonnetzConfig
var lsystem: LSystem
var lsystems: Array[LSystem] = []
var lsystem_colors: Array[Color] = []
var lsystem_volumes: Array[float] = []
var lsystem_origin_labels: Array[String] = []
var lsystem_start_labels: Array[String] = []
var last_piano_roll_selection := {}
var current_lsystem_index := 0
var voice_turtles := {}
var lsystem_turtles := {}
var lsystem_voice_ids := {}
var global_paused := false
@onready var ui = $UI

const VOICE_COLORS := [
	Color(0.1, 0.74, 0.61),
	Color(0.93, 0.32, 0.27),
	Color(0.2, 0.45, 0.9),
	Color(0.95, 0.72, 0.18),
	Color(0.64, 0.34, 0.83),
	Color(0.95, 0.45, 0.13),
	Color(0.28, 0.76, 0.34),
	Color(0.88, 0.25, 0.55)
]

func _ready() -> void:
	config = Config.config

	builder.animation_on = animations_on

	# connect sequencer -> turtle/audio/ui
	sequencer.transition_started.connect(_on_transition_started)
	sequencer.event_entered.connect(_on_sequencer_event_entered)
	sequencer.note_entered.connect(_on_sequencer_note_entered)
	sequencer.voice_paused.connect(_on_voice_paused)
	piano_roll.bar_selection_changed.connect(_on_piano_roll_bar_selection_changed)

	if ui.has_signal("lsystem_selected"):
		ui.add_lsystem_requested.connect(add_lsystem)
		ui.lsystem_selected.connect(select_lsystem)
		ui.lsystem_randomize_requested.connect(randomize_lsystem)
		ui.lsystem_duplicate_requested.connect(duplicate_lsystem)
		ui.lsystem_remove_requested.connect(remove_lsystem)
		ui.lsystem_play_requested.connect(resume_lsystem)
		ui.lsystem_stop_requested.connect(stop_lsystem)
		ui.lsystem_axiom_changed.connect(set_lsystem_axiom)
		ui.lsystem_iterations_changed.connect(set_lsystem_iterations)
		ui.lsystem_rule_changed.connect(set_lsystem_rule)
		ui.lsystem_volume_changed.connect(set_lsystem_volume)
		ui.tonnetz_clicked.connect(_on_tonnetz_clicked)
		ui.global_play_pause_toggled.connect(set_global_paused)
		ui.play_selected_bar_requested.connect(play_from_selected_bar)

	if ui.has_signal("instrument_changed"):
		ui.instrument_changed.connect(audio_manager.change_instrument)

	# Build Tonnetz
	await builder.build()

	# Generate initial L-System
	lsystem = LSystemFactory.random(config)
	lsystems.append(lsystem)
	lsystem_colors.append(_get_voice_color(0))
	lsystem_volumes.append(0.8)
	lsystem_origin_labels.append("Not set")
	lsystem_start_labels.append("Not scheduled")
	_update_piano_roll_context()
	_refresh_lsystems_ui()

func _on_transition_started(
	voice_id: int,
	current_event: Dictionary,
	next_event: Dictionary
) -> void:
	var voice_turtle = voice_turtles.get(voice_id)

	if not is_instance_valid(voice_turtle):
		return

	voice_turtle.start_transition(
		current_event,
		next_event
	)

func _on_sequencer_event_entered(voice_id: int, event: Dictionary) -> void:
	audio_manager.play_event(event)

func _on_sequencer_note_entered(voice_id: int, event: Dictionary) -> void:
	var lsystem_index = _get_lsystem_index_for_voice(voice_id)

	if lsystem_index == -1:
		return

	piano_roll.add_event(event, lsystem_colors[lsystem_index])

func _on_voice_paused(voice_id: int, event: Dictionary) -> void:
	var voice_turtle = voice_turtles.get(voice_id)

	if is_instance_valid(voice_turtle):
		voice_turtle.pause_at_event(event)

func play_lsystem(
	lsystem_index: int,
	lsystem_string: String,
	start_pos: Vector2,
	voice_turtle: Turtle,
	start_beat: float
) -> int:
	var actions = interpreter.set_actions(lsystem_string, start_pos)
	var voice_id = sequencer.add_voice(
		actions,
		start_beat,
		lsystem_volumes[lsystem_index]
	)

	if voice_id == -1:
		return -1

	voice_turtles[voice_id] = voice_turtle
	lsystem_voice_ids[lsystem_index] = voice_id
	voice_turtle.clear_path(start_pos)
	voice_turtle.set_voice_color(lsystem_colors[lsystem_index])

	if not global_paused:
		CL.start_clock()

	return voice_id

func play_active_lsystem(start_pos: Vector2) -> void:
	if current_lsystem_index < 0 or current_lsystem_index >= lsystems.size():
		return

	var start_beat = _get_next_grid_beat()
	var start_anchor = builder.get_nearest_spawn_anchor(start_pos)
	var voice_turtle = _get_turtle_for_lsystem(current_lsystem_index, start_pos)

	_stop_lsystem_voice(current_lsystem_index)
	_set_lsystem_origin_label(current_lsystem_index, start_anchor)
	_set_lsystem_start_label(current_lsystem_index, start_beat)

	var voice_id = play_lsystem(
		current_lsystem_index,
		lsystems[current_lsystem_index].generated_string,
		start_pos,
		voice_turtle,
		start_beat
	)

	if voice_id != -1:
		_refresh_lsystems_ui()

	piano_roll.auto_follow = true

func add_lsystem() -> void:
	var new_system := LSystemFactory.random(config)

	lsystems.append(new_system)
	lsystem_colors.append(_get_voice_color(lsystems.size() - 1))
	lsystem_volumes.append(0.8)
	lsystem_origin_labels.append("Not set")
	lsystem_start_labels.append("Not scheduled")
	current_lsystem_index = lsystems.size() - 1
	set_lsystem(new_system)
	_update_piano_roll_context()
	_refresh_lsystems_ui()

func select_lsystem(index: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	current_lsystem_index = index
	lsystem = lsystems[index]
	_update_piano_roll_context()
	_refresh_lsystems_ui()

func randomize_lsystem(index: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	lsystems[index] = LSystemFactory.random(config)
	select_lsystem(index)

func duplicate_lsystem(index: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	var source = lsystems[index]
	var duplicate_system := LSystem.new(
		source.axiom,
		source.rules.duplicate(true),
		source.generated_string,
		source.iterations
	)

	lsystems.append(duplicate_system)
	lsystem_colors.append(_get_voice_color(lsystems.size() - 1))
	lsystem_volumes.append(lsystem_volumes[index])
	lsystem_origin_labels.append("Not set")
	lsystem_start_labels.append("Not scheduled")
	current_lsystem_index = lsystems.size() - 1
	set_lsystem(duplicate_system)
	_update_piano_roll_context()
	_refresh_lsystems_ui()

func remove_lsystem(index: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	_stop_lsystem_voice(index)
	_remove_lsystem_turtle(index)

	lsystems.remove_at(index)
	lsystem_colors.remove_at(index)
	lsystem_volumes.remove_at(index)
	lsystem_origin_labels.remove_at(index)
	lsystem_start_labels.remove_at(index)

	_shift_lsystem_index_mapping(lsystem_turtles, index)
	_shift_lsystem_index_mapping(lsystem_voice_ids, index)

	if lsystems.is_empty():
		current_lsystem_index = -1
		_update_piano_roll_context()
		_refresh_lsystems_ui()
		return

	if current_lsystem_index > index:
		current_lsystem_index -= 1
	elif current_lsystem_index >= lsystems.size():
		current_lsystem_index = lsystems.size() - 1

	lsystem = lsystems[current_lsystem_index]
	_update_piano_roll_context()
	_refresh_lsystems_ui()

func stop_lsystem(index: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	_request_stop_lsystem_voice(index)
	_refresh_lsystems_ui()

func resume_lsystem(index: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	if not lsystem_voice_ids.has(index):
		return

	var voice_id = lsystem_voice_ids[index]
	var voice_turtle = lsystem_turtles.get(index)

	if not is_instance_valid(voice_turtle):
		return

	voice_turtle.set_voice_color(lsystem_colors[index])
	voice_turtles[voice_id] = voice_turtle

	var start_beat = _get_next_grid_beat()

	if sequencer.resume_voice(voice_id, start_beat):
		_set_lsystem_start_label(index, start_beat)
		if not global_paused:
			CL.start_clock()
		_refresh_lsystems_ui()

func set_global_paused(paused: bool) -> void:
	global_paused = paused
	piano_roll.set_global_paused(paused)

	if paused:
		CL.stop_clock()
	else:
		CL.start_clock()

func play_from_selected_bar() -> void:
	var start_beat := piano_roll.get_selected_bar_start_beat()

	if start_beat < 0.0:
		return

	global_paused = false
	piano_roll.set_global_paused(false)
	ui.set_global_paused_visual(false)
	piano_roll.scroll_to_beat(start_beat)
	piano_roll.auto_follow = true
	CL.seek_to_beat(start_beat)
	CL.start_clock()

func set_lsystem_axiom(index: int, new_axiom: String) -> void:
	if index < 0 or index >= lsystems.size() or new_axiom.is_empty():
		return

	lsystems[index].axiom = new_axiom[0]
	LSystemFactory.regenerate_string(lsystems[index], lsystems[index].iterations)
	select_lsystem(index)

func set_lsystem_iterations(index: int, iterations: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	lsystems[index].iterations = iterations
	LSystemFactory.regenerate_string(lsystems[index], iterations)
	select_lsystem(index)

func set_lsystem_rule(index: int, symbol: String, production: String) -> void:
	if index < 0 or index >= lsystems.size():
		return

	LSystemFactory.regenerate_rules(
		lsystems[index],
		symbol,
		production,
		config
	)
	select_lsystem(index)

func set_lsystem_volume(index: int, volume: float) -> void:
	if index < 0 or index >= lsystems.size():
		return

	volume = clamp(volume, 0.0, 1.0)

	while lsystem_volumes.size() <= index:
		lsystem_volumes.append(0.8)

	lsystem_volumes[index] = volume

	if lsystem_voice_ids.has(index):
		sequencer.set_voice_volume(lsystem_voice_ids[index], volume)

func _refresh_lsystems_ui() -> void:
	ui.update_lsystems_ui(
		lsystems,
		current_lsystem_index,
		lsystem_colors,
		lsystem_volumes,
		_build_lsystem_info()
	)

func _update_piano_roll_context() -> void:
	var color := Color.WHITE

	if current_lsystem_index >= 0 and current_lsystem_index < lsystem_colors.size():
		color = lsystem_colors[current_lsystem_index]

	piano_roll.set_active_lsystem_context(current_lsystem_index, color)

func _on_piano_roll_bar_selection_changed(selection: Dictionary) -> void:
	last_piano_roll_selection = selection.duplicate(true)

func _build_lsystem_info() -> Array:
	var info: Array = []

	for index in range(lsystems.size()):
		_ensure_lsystem_ui_state(index)
		info.append({
			"origin_label": lsystem_origin_labels[index],
			"start_label": lsystem_start_labels[index]
		})

	return info

func _ensure_lsystem_ui_state(index: int) -> void:
	while lsystem_origin_labels.size() <= index:
		lsystem_origin_labels.append("Not set")

	while lsystem_start_labels.size() <= index:
		lsystem_start_labels.append("Not scheduled")

func _set_lsystem_origin_label(index: int, anchor) -> void:
	_ensure_lsystem_ui_state(index)
	lsystem_origin_labels[index] = _describe_anchor(anchor)

func _set_lsystem_start_label(index: int, start_beat: float) -> void:
	_ensure_lsystem_ui_state(index)
	lsystem_start_labels[index] = _format_beat_label(start_beat)

func _describe_anchor(anchor) -> String:
	if anchor is TonnetzNode:
		return "Node %s%d" % [anchor.note_name, int(anchor.octave)]

	if anchor is TriangleArea:
		var note_names: Array[String] = []

		for node in anchor.nodes:
			note_names.append("%s%d" % [node.note_name, int(node.octave)])

		return "Triangle %s" % "-".join(note_names)

	return "Not set"

func _format_beat_label(start_beat: float) -> String:
	var rounded_beat = snappedf(start_beat, 0.01)

	if is_equal_approx(rounded_beat, round(rounded_beat)):
		return "Beat %d" % int(round(rounded_beat))

	return "Beat %.2f" % rounded_beat

func _clear_playing_voices(start_pos: Vector2) -> void:
	sequencer.clear_voices()

	for voice_id in voice_turtles:
		var old_turtle = voice_turtles[voice_id]

		if is_instance_valid(old_turtle) and old_turtle != turtle:
			old_turtle.queue_free()

	voice_turtles.clear()
	lsystem_turtles.clear()
	lsystem_voice_ids.clear()
	turtle.clear_path(start_pos)
	piano_roll.clear_events()

func _remove_lsystem_turtle(index: int) -> void:
	if not lsystem_turtles.has(index):
		return

	var removed_turtle = lsystem_turtles[index]
	lsystem_turtles.erase(index)

	if not is_instance_valid(removed_turtle):
		return

	removed_turtle.stop_after_current_target()

	if removed_turtle == turtle:
		removed_turtle.clear_path(removed_turtle.global_position)
		return

	removed_turtle.queue_free()

func _shift_lsystem_index_mapping(mapping: Dictionary, removed_index: int) -> void:
	var shifted_mapping := {}

	for mapping_index in mapping.keys():
		var new_index = int(mapping_index)

		if new_index > removed_index:
			new_index -= 1

		shifted_mapping[new_index] = mapping[mapping_index]

	mapping.clear()

	for mapping_index in shifted_mapping.keys():
		mapping[mapping_index] = shifted_mapping[mapping_index]

func _get_turtle_for_lsystem(index: int, start_pos: Vector2) -> Turtle:
	var existing_turtle = lsystem_turtles.get(index)

	if is_instance_valid(existing_turtle):
		existing_turtle.clear_path(start_pos)
		existing_turtle.set_voice_color(lsystem_colors[index])
		return existing_turtle

	var new_turtle: Turtle

	if lsystem_turtles.is_empty():
		turtle.clear_path(start_pos)
		new_turtle = turtle
	else:
		new_turtle = turtle_scene.instantiate() as Turtle

		if not new_turtle:
			push_error("Turtle.tscn must use scripts/turtle.gd for multi-voice playback.")
			return turtle

		tonnetz_world.add_child(new_turtle)

	new_turtle.global_position = start_pos
	new_turtle.set_voice_color(lsystem_colors[index])
	lsystem_turtles[index] = new_turtle

	return new_turtle

func _stop_lsystem_voice(index: int) -> void:
	if not lsystem_voice_ids.has(index):
		var idle_turtle = lsystem_turtles.get(index)

		if is_instance_valid(idle_turtle):
			idle_turtle.stop_after_current_target()

		return

	var voice_id = lsystem_voice_ids[index]

	sequencer.stop_voice(voice_id)
	voice_turtles.erase(voice_id)
	lsystem_voice_ids.erase(index)

	var voice_turtle = lsystem_turtles.get(index)

	if is_instance_valid(voice_turtle):
		voice_turtle.stop_after_current_target()

func _request_stop_lsystem_voice(index: int) -> void:
	if not lsystem_voice_ids.has(index):
		var idle_turtle = lsystem_turtles.get(index)

		if is_instance_valid(idle_turtle):
			idle_turtle.stop_after_current_target()

		return

	var voice_id = lsystem_voice_ids[index]
	sequencer.request_stop_voice(voice_id)

func _stop_all_lsystem_voices() -> void:
	sequencer.clear_voices()
	voice_turtles.clear()
	lsystem_voice_ids.clear()

	for voice_turtle in lsystem_turtles.values():
		if is_instance_valid(voice_turtle):
			voice_turtle.stop_after_current_target()

func _get_voice_color(index: int) -> Color:
	if index < VOICE_COLORS.size():
		return VOICE_COLORS[index]

	var hue = fposmod(float(index) * 0.137, 1.0)
	return Color.from_hsv(hue, 0.72, 0.92)

func _get_lsystem_index_for_voice(voice_id: int) -> int:
	for lsystem_index in lsystem_voice_ids:
		if lsystem_voice_ids[lsystem_index] == voice_id:
			return lsystem_index

	return -1

func _get_next_grid_beat() -> float:
	var beat : float= CL.get_time_beat()

	if is_equal_approx(beat, round(beat)):
		return round(beat)

	return ceil(beat)

func _unhandled_input(event) -> void:
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		var click_pos := get_global_mouse_position()

		if ui.has_method("is_position_in_tonnetz_area") and not ui.is_position_in_tonnetz_area(click_pos):
			return

		if ui.has_method("get_tonnetz_world_position"):
			click_pos = ui.get_tonnetz_world_position(click_pos)

		_on_tonnetz_clicked(click_pos)


func _on_tonnetz_clicked(click_pos: Vector2) -> void:
	var start_anchor = builder.get_nearest_spawn_anchor(click_pos)

	if not start_anchor:
		return

	var snapped_pos = start_anchor.get_center()

	if not lsystem_on:
		_clear_playing_voices(snapped_pos)

		return

	play_active_lsystem(snapped_pos)


func set_lsystem(new_lsystem: LSystem) -> void:
	lsystem = new_lsystem

	if current_lsystem_index >= 0 and current_lsystem_index < lsystems.size():
		lsystems[current_lsystem_index] = new_lsystem

	#print("New LSystem assigned.")


func on_lsystem_toggled(toggled_state: bool) -> void:
	lsystem_on = toggled_state

	if not lsystem_on and turtle:
		_stop_all_lsystem_voices()


func on_bpm_changed(new_value: int) -> void:
	CL.bpm = new_value

	#piano_roll.refresh_view()


func on_animation_toggled(toggled_state: bool) -> void:
	animations_on = toggled_state

	builder._on_ui_toggle_animation()
