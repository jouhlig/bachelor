extends Node2D

##################################################
########## SCENE REFERENCES #############
##################################################
@onready var tonnetz_world: Node2D = $UI/TonnetzViewportContainer/TonnetzViewport/TonnetzWorld
@onready var builder: TonnetzBuilder = $UI/TonnetzViewportContainer/TonnetzViewport/TonnetzWorld/TonnetzBuilder
@onready var piano_roll: PianoRoll = $UI/PianoRoll
@onready var interpreter = $Interpreter
@onready var sequencer: Sequencer = $Sequencer
@onready var turtle: Turtle = $UI/TonnetzViewportContainer/TonnetzViewport/TonnetzWorld/Turtle
@onready var audio_manager: AudioManager = $AudioManager
@onready var ui = $UI
var turtle_scene: PackedScene = preload("res://Turtle.tscn")
var evolution := Evolution.new()

##################################################
########## LSYSTEM STATE #############
##################################################
var config: TonnetzConfig
var lsystem: LSystem
var lsystems: Array[LSystem] = []
var available_colors: Array[Color] = []
var last_piano_roll_selection := {}
var current_lsystem_index := 0
var pending_evolution_candidate := {}
var mutation_preview_voice_id := -1
var mutation_preview_turtle: Turtle = null
var mutation_comparison_side := "candidate"
var current_instrument_index := 0

##################################################
########## PLAYBACK STATE #############
##################################################
var voice_turtles := {}
var lsystem_turtles := {}
var lsystem_voice_ids := {}
var voice_mute_states := {}
var global_paused := false
var clock_started_from_lsystem_click := false
var repeat_selection_enabled := false
var repeat_selection_pending_jump := false
var repeat_selection_jump_beat := -1.0
var repeat_selection_start_beat := -1.0
var repeat_selection_end_beat := -1.0

func _ready() -> void:
	config = Config.config
	turtle.hide_turtle()

	available_colors = config.VOICE_COLORS.duplicate()

	# connect sequencer -> turtle/audio/ui
	sequencer.transition_started.connect(_on_transition_started)
	sequencer.event_entered.connect(_on_sequencer_event_entered)
	sequencer.note_entered.connect(_on_sequencer_note_entered)
	sequencer.voice_paused.connect(_on_voice_paused)
	sequencer.voice_reentered.connect(_on_voice_reentered)
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
		ui.lsystem_mute_toggled.connect(set_lsystem_muted)
		ui.tonnetz_clicked.connect(_on_tonnetz_clicked)
		ui.global_play_pause_toggled.connect(set_global_paused)
		ui.play_selected_bar_requested.connect(play_from_selected_bar)
		ui.repeat_selected_bar_toggled.connect(set_repeat_selected_bar)
		ui.mutate_selection_requested.connect(mutate_selected_bar_rules)
		ui.mutation_side_selected.connect(set_mutation_comparison_side)
		ui.mutation_apply_requested.connect(apply_pending_mutation)
		ui.mutation_cancel_requested.connect(cancel_pending_mutation)
		ui.export_midi_requested.connect(export_midi)
		ui.master_reverb_changed.connect(audio_manager.set_master_reverb)
		ui.master_delay_changed.connect(audio_manager.set_master_delay)
		ui.master_distortion_changed.connect(audio_manager.set_master_distortion)

	if ui.has_signal("instrument_changed"):
		ui.instrument_changed.connect(audio_manager.change_instrument)
		ui.instrument_changed.connect(_on_instrument_changed)

	# Build Tonnetz
	await builder.build()

	# Generate initial L-System
	lsystem = LSystemFactory.random(config)
	_configure_lsystem(lsystem, 0)
	lsystems.append(lsystem)
	voice_mute_states[0] = false
	_update_piano_roll_context()
	_refresh_lsystems_ui()

func _process(delta: float) -> void:
	if not repeat_selection_enabled:
		return

	if repeat_selection_start_beat < 0.0 or repeat_selection_end_beat <= repeat_selection_start_beat:
		return

	if repeat_selection_pending_jump:
		if CL.get_time_beat() >= repeat_selection_jump_beat:
			repeat_selection_pending_jump = false
			_jump_to_repeat_selection_start()
		return

	if CL.get_time_beat() >= repeat_selection_end_beat:
		_jump_to_repeat_selection_start()

##################################################
########## LSYSTEM ACCESS HELPERS #############
##################################################
func _get_next_available_color() -> Color:
	if available_colors.is_empty():
		return Color.WHITE

	return available_colors.pop_front()

func _return_color_to_pool(color: Color) -> void:
	if color == Color.WHITE or available_colors.has(color):
		return

	available_colors.append(color)

func _configure_lsystem(system: LSystem, _index: int) -> void:
	system.color = _get_next_available_color()
	system.set_volume(system.volume)

func _get_lsystem(index: int) -> LSystem:
	if index < 0 or index >= lsystems.size():
		return null

	return lsystems[index]

func _get_lsystem_color(index: int) -> Color:
	var system = _get_lsystem(index)
	return system.color if system else Color.WHITE

func _get_lsystem_volume(index: int) -> float:
	var system = _get_lsystem(index)
	return system.volume if system else 0.8

##################################################
########## SEQUENCER CALLBACKS #############
##################################################
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
	if _is_voice_muted(voice_id):
		return

	audio_manager.play_event(event)

func _on_sequencer_note_entered(voice_id: int, event: Dictionary) -> void:
	var lsystem_index = _get_lsystem_index_for_voice(voice_id)

	if lsystem_index == -1:
		return

	piano_roll.add_event(event, _get_lsystem_color(lsystem_index), lsystem_index)

func _on_voice_paused(voice_id: int, event: Dictionary) -> void:
	var voice_turtle = voice_turtles.get(voice_id)

	if is_instance_valid(voice_turtle):
		voice_turtle.pause_at_event(event)

func _on_voice_reentered(voice_id: int, event: Dictionary) -> void:
	var voice_turtle = voice_turtles.get(voice_id)

	if is_instance_valid(voice_turtle):
		voice_turtle.pause_at_event(event)

func _is_voice_muted(voice_id: int) -> bool:
	if voice_id == mutation_preview_voice_id:
		return false

	var lsystem_index = _get_lsystem_index_for_voice(voice_id)

	if lsystem_index < 0 or lsystem_index >= lsystems.size():
		return false

	return bool(voice_mute_states.get(lsystem_index, false))

##################################################
########## LSYSTEM PLAYBACK #############
##################################################
func play_lsystem(
	lsystem_index: int,
	lsystem_string: String,
	lsystem_final_nodes,
	start_pos: Vector2,
	voice_turtle: Turtle,
	start_beat: float
) -> int:
	var actions = interpreter.set_actions(lsystem_string, lsystem_final_nodes, start_pos)
	var voice_id = sequencer.add_voice(
		actions,
		start_beat,
		_get_lsystem_volume(lsystem_index)
	)

	if voice_id == -1:
		return -1

	voice_turtles[voice_id] = voice_turtle
	lsystem_voice_ids[lsystem_index] = voice_id
	voice_turtle.clear_path(start_pos)
	voice_turtle.set_voice_color(_get_lsystem_color(lsystem_index))
	voice_turtle.set_visual_radius_offset(0.0)

	return voice_id

func play_active_lsystem(start_pos: Vector2) -> void:
	if current_lsystem_index < 0 or current_lsystem_index >= lsystems.size():
		return

	var start_beat = _get_next_grid_beat()
	var start_anchor = builder.get_nearest_spawn_anchor(start_pos)

	_set_lsystem_origin(current_lsystem_index, start_anchor)
	if _play_lsystem_from_origin(current_lsystem_index, start_beat):
		_start_clock_from_lsystem_click()
		_refresh_lsystems_ui()

	piano_roll.auto_follow = true

func _play_lsystem_from_origin(index: int, start_beat: float) -> bool:
	if index < 0 or index >= lsystems.size():
		return false

	var current_system = lsystems[index]

	if not current_system.origin or not current_system.origin.has_method("get_center"):
		return false

	var origin_pos = current_system.origin.get_center()

	_stop_lsystem_voice(index)
	var voice_turtle = _get_turtle_for_lsystem(index, origin_pos)
	_set_lsystem_start_beat(index, start_beat)
	var voice_id = play_lsystem(
		index,
		current_system.generated_string,
		current_system.final_nodes,
		origin_pos,
		voice_turtle,
		start_beat
	)

	return voice_id != -1

##################################################
########## LSYSTEM LIST ACTIONS #############
##################################################
func add_lsystem() -> void:
	var new_system := LSystemFactory.random(config)

	_configure_lsystem(new_system, lsystems.size())
	lsystems.append(new_system)
	voice_mute_states[lsystems.size() - 1] = false
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

	_stop_mutation_preview()
	pending_evolution_candidate.clear()
	lsystems[index].randomize(config)
	select_lsystem(index)

func duplicate_lsystem(index: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	var duplicate_system := lsystems[index].duplicate_system()
	duplicate_system.color = _get_next_available_color()
	duplicate_system.set_origin(null, "Not set")
	duplicate_system.set_start_beat(null, "Not scheduled")

	lsystems.append(duplicate_system)
	voice_mute_states[lsystems.size() - 1] = bool(voice_mute_states.get(index, false))
	current_lsystem_index = lsystems.size() - 1
	set_lsystem(duplicate_system)
	_update_piano_roll_context()
	_refresh_lsystems_ui()

func remove_lsystem(index: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	_stop_mutation_preview()
	pending_evolution_candidate.clear()
	_return_color_to_pool(lsystems[index].color)

	_stop_lsystem_voice(index)
	_remove_lsystem_turtle(index)
	piano_roll.remove_events_for_lsystem(index)

	lsystems.remove_at(index)

	_shift_lsystem_index_mapping(lsystem_turtles, index)
	_shift_lsystem_index_mapping(lsystem_voice_ids, index)
	_shift_lsystem_index_mapping(voice_mute_states, index)
	piano_roll.shift_lsystem_indices_after_removal(index)

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

	voice_turtle.set_voice_color(_get_lsystem_color(index))
	voice_turtles[voice_id] = voice_turtle

	var start_beat = _get_next_grid_beat()

	if sequencer.resume_voice(voice_id, start_beat):
		_set_lsystem_start_beat(index, start_beat)
		_start_clock_if_lsystem_click_started()
		_refresh_lsystems_ui()

func set_global_paused(paused: bool) -> void:
	global_paused = paused
	piano_roll.set_global_paused(paused)

	if paused:
		CL.stop_clock()
	else:
		_start_clock_if_lsystem_click_started()

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
	sequencer.seek_to_beat(start_beat)
	set_repeat_selected_bar(true)
	_start_clock_if_lsystem_click_started()

func set_repeat_selected_bar(enabled: bool) -> void:
	if not enabled:
		repeat_selection_enabled = false
		repeat_selection_pending_jump = false
		return

	if not _update_repeat_selection_range():
		repeat_selection_enabled = false
		repeat_selection_pending_jump = false
		ui.set_repeat_selected_bar_visual(false)
		return

	repeat_selection_enabled = true
	repeat_selection_pending_jump = true
	repeat_selection_jump_beat = _get_next_bar_boundary_beat(CL.get_time_beat())
	global_paused = false
	piano_roll.set_global_paused(false)
	ui.set_global_paused_visual(false)
	piano_roll.auto_follow = true
	_start_clock_if_lsystem_click_started()

func _update_repeat_selection_range() -> bool:
	var start_beat := piano_roll.get_selected_bar_start_beat()
	var end_beat := piano_roll.get_selected_bar_end_beat()

	if start_beat < 0.0 or end_beat <= start_beat:
		return false

	repeat_selection_start_beat = start_beat
	repeat_selection_end_beat = end_beat
	return true

func _jump_to_repeat_selection_start() -> void:
	CL.seek_to_beat(repeat_selection_start_beat)
	sequencer.seek_to_beat(repeat_selection_start_beat)
	piano_roll.scroll_to_beat(repeat_selection_start_beat)

func _get_next_bar_boundary_beat(beat: float) -> float:
	var beats_per_bar = float(piano_roll.beats_per_bar)

	if beats_per_bar <= 0.0:
		return beat

	var current_bar_start = floor(beat / beats_per_bar) * beats_per_bar
	return current_bar_start + beats_per_bar

##################################################
########## MIDI EXPORT #############
##################################################
func export_midi(path: String) -> void:
	var export_length_beats := float(config.length_bars * piano_roll.beats_per_bar)
	var result := MidiExporter.export_voices(
		sequencer.voices,
		path,
		config.bpm,
		export_length_beats,
		current_instrument_index,
		_get_muted_voice_ids()
	)

	if bool(result.get("ok", false)):
		print(result.get("message", "MIDI export complete."))
	else:
		push_error(str(result.get("message", "MIDI export failed.")))


func _get_muted_voice_ids() -> Array:
	var muted_voice_ids := []

	for lsystem_index in voice_mute_states.keys():
		if not bool(voice_mute_states.get(lsystem_index, false)):
			continue

		if lsystem_voice_ids.has(lsystem_index):
			muted_voice_ids.append(int(lsystem_voice_ids[lsystem_index]))

	return muted_voice_ids


func _on_instrument_changed(index: int) -> void:
	current_instrument_index = index

##################################################
########## LSYSTEM EDIT CALLBACKS #############
##################################################
func set_lsystem_axiom(index: int, new_axiom: String) -> void:
	if index < 0 or index >= lsystems.size() or new_axiom.is_empty():
		return

	_stop_mutation_preview()
	pending_evolution_candidate.clear()
	lsystems[index].set_axiom(new_axiom)
	select_lsystem(index)

func set_lsystem_iterations(index: int, iterations: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	_stop_mutation_preview()
	pending_evolution_candidate.clear()
	lsystems[index].set_iterations(iterations)
	select_lsystem(index)

func set_lsystem_rule(index: int, symbol: String, production: String) -> void:
	if index < 0 or index >= lsystems.size():
		return

	_stop_mutation_preview()
	pending_evolution_candidate.clear()
	lsystems[index].set_rule(symbol, production)
	select_lsystem(index)

func set_lsystem_volume(index: int, volume: float) -> void:
	if index < 0 or index >= lsystems.size():
		return

	lsystems[index].set_volume(volume)

	if lsystem_voice_ids.has(index):
		sequencer.set_voice_volume(lsystem_voice_ids[index], lsystems[index].volume)

	_apply_mutation_comparison_volumes()

func set_lsystem_muted(index: int, muted: bool) -> void:
	if index < 0 or index >= lsystems.size():
		return

	voice_mute_states[index] = muted
	_refresh_lsystems_ui()

##################################################
########## LSYSTEM UI DATA #############
##################################################
func _refresh_lsystems_ui() -> void:
	ui.update_lsystems_ui(
		lsystems,
		current_lsystem_index,
		_build_lsystem_color_array(),
		_build_lsystem_volume_array(),
		_build_lsystem_info()
	)

func _build_lsystem_color_array() -> Array:
	var colors := []

	for index in range(lsystems.size()):
		colors.append(_get_lsystem_color(index))

	return colors

func _build_lsystem_volume_array() -> Array:
	var volumes := []

	for index in range(lsystems.size()):
		volumes.append(_get_lsystem_volume(index))

	return volumes

func _update_piano_roll_context() -> void:
	var color := Color.WHITE

	if current_lsystem_index >= 0 and current_lsystem_index < lsystems.size():
		color = _get_lsystem_color(current_lsystem_index)

	piano_roll.set_active_lsystem_context(current_lsystem_index, color)

##################################################
########## PIANO ROLL SELECTION #############
##################################################
func _on_piano_roll_bar_selection_changed(selection: Dictionary) -> void:
	if selection.is_empty():
		last_piano_roll_selection.clear()
		_stop_mutation_preview()
		pending_evolution_candidate.clear()
		repeat_selection_enabled = false
		repeat_selection_pending_jump = false
		ui.set_repeat_selected_bar_visual(false)
		ui.hide_mutation_prompt()
		return

	last_piano_roll_selection = selection.duplicate(true)
	_stop_mutation_preview()
	pending_evolution_candidate.clear()
	var selected_actions = _print_actions_for_bar_selection(selection)
	ui.show_mutation_prompt(
		_build_lsystem_color_array(),
		evolution.build_selection_debug_text(selection, selected_actions),
		int(selection.get("active_lsystem_index", current_lsystem_index))
	)

	if _update_repeat_selection_range():
		repeat_selection_enabled = true
		repeat_selection_pending_jump = true
		repeat_selection_jump_beat = _get_next_bar_boundary_beat(CL.get_time_beat())
		ui.set_repeat_selected_bar_visual(true)
		global_paused = false
		piano_roll.set_global_paused(false)
		ui.set_global_paused_visual(false)
		piano_roll.auto_follow = true
		_start_clock_if_lsystem_click_started()
	else:
		repeat_selection_enabled = false
		repeat_selection_pending_jump = false
		ui.set_repeat_selected_bar_visual(false)

func mutate_selected_bar_rules(lsystem_index: int) -> void:
	if last_piano_roll_selection.is_empty():
		return

	var selection = last_piano_roll_selection.duplicate(true)
	selection["active_lsystem_index"] = lsystem_index
	var selected_actions = _print_actions_for_bar_selection(selection)
	ui.show_mutation_prompt(
		_build_lsystem_color_array(),
		evolution.build_selection_debug_text(selection, selected_actions),
		lsystem_index
	)
	_propose_selected_bar_rules_mutation(selection, selected_actions)

##################################################
########## SELECTED ACTIONS #############
##################################################
func _print_actions_for_bar_selection(selection: Dictionary) -> Array:
	var lsystem_index := int(selection.get("active_lsystem_index", current_lsystem_index))

	if lsystem_index < 0 or lsystem_index >= lsystems.size():
		return []


	if not lsystem_voice_ids.has(lsystem_index):
		return []

	var voice = _get_sequencer_voice(lsystem_voice_ids[lsystem_index])

	if voice.is_empty():
		return []

	var selected_actions = _get_voice_actions_in_beat_range(
		voice,
		float(selection.get("start_beat", 0.0)),
		float(selection.get("end_beat", 0.0))
	)

	return selected_actions

##################################################
########## LSYSTEM EVOLUTION #############
##################################################
func _propose_selected_bar_rules_mutation(selection: Dictionary, selected_actions: Array) -> void:
	_stop_mutation_preview()
	pending_evolution_candidate.clear()
	mutation_comparison_side = "candidate"

	var lsystem_index := int(selection.get("active_lsystem_index", current_lsystem_index))

	if lsystem_index < 0 or lsystem_index >= lsystems.size():
		_show_mutation_proposal_failure("The selected voice does not exist anymore.")
		return

	if not lsystem_voice_ids.has(lsystem_index):
		_show_mutation_proposal_failure("This voice is not currently playing, so there is no score to mutate yet.")
		return

	var voice = _get_sequencer_voice(lsystem_voice_ids[lsystem_index])

	if voice.is_empty():
		_show_mutation_proposal_failure("Could not find the playing score for this voice.")
		return

	var current_system = lsystems[lsystem_index]
	var result = evolution.create_mutation_proposal(
		selection,
		selected_actions,
		current_system,
		voice,
		interpreter
	)

	if not bool(result.get("ok", false)):
		_show_mutation_proposal_failure(str(result.get("message", "No mutation proposal could be created.")))
		return

	pending_evolution_candidate = result["candidate"]
	pending_evolution_candidate["lsystem_index"] = lsystem_index
	ui.show_mutation_proposition(evolution.build_mutation_proposition_text(pending_evolution_candidate))
	_start_mutation_preview(pending_evolution_candidate)
	set_mutation_comparison_side("candidate")

func _show_mutation_proposal_failure(reason: String) -> void:
	_stop_mutation_preview()
	ui.show_mutation_proposition(evolution.build_failure_text(reason), false)

func apply_pending_mutation() -> void:
	if pending_evolution_candidate.is_empty():
		return

	var lsystem_index := int(pending_evolution_candidate.get("lsystem_index", -1))

	if lsystem_index < 0 or lsystem_index >= lsystems.size():
		_stop_mutation_preview()
		pending_evolution_candidate.clear()
		return

	_stop_mutation_preview()
	var current_system = lsystems[lsystem_index]

	current_system.apply_generated_state(
		pending_evolution_candidate["axiom"],
		pending_evolution_candidate["rules"],
		pending_evolution_candidate["generated_string"],
		pending_evolution_candidate["final_nodes"]
	)

	print("Evolution applied to L-system %d with fitness %.2f" % [
		lsystem_index,
		float(pending_evolution_candidate.get("fitness", 0.0))
	])
	print("Private mutation symbols: ", pending_evolution_candidate.get("mutation_symbols", []))
	print("New generated string: ", current_system.generated_string)

	var start_position: Vector2 = pending_evolution_candidate.get("start_position", Vector2.ZERO)
	var old_start_beat := float(pending_evolution_candidate.get("old_start_beat", CL.get_time_beat()))
	var voice_turtle = _get_turtle_for_lsystem(lsystem_index, start_position)

	_stop_lsystem_voice(lsystem_index)
	play_lsystem(
		lsystem_index,
		current_system.generated_string,
		current_system.final_nodes,
		start_position,
		voice_turtle,
		old_start_beat
	)
	_refresh_lsystems_ui()
	pending_evolution_candidate.clear()
	piano_roll.clear_bar_selection()

func cancel_pending_mutation() -> void:
	_stop_mutation_preview()
	pending_evolution_candidate.clear()
	piano_roll.clear_bar_selection()

func _start_mutation_preview(candidate: Dictionary) -> void:
	var lsystem_index := int(candidate.get("lsystem_index", -1))

	if lsystem_index < 0 or lsystem_index >= lsystems.size():
		return

	var start_position: Vector2 = candidate.get("start_position", Vector2.ZERO)
	var preview_turtle = turtle_scene.instantiate() as Turtle

	if not preview_turtle:
		push_error("Turtle.tscn must use scripts/turtle.gd for mutation preview.")
		return

	tonnetz_world.add_child(preview_turtle)
	preview_turtle.global_position = start_position
	preview_turtle.clear_path(start_position)
	preview_turtle.set_voice_color(_get_lsystem_color(lsystem_index))

	var actions = interpreter.set_actions(
		str(candidate.get("generated_string", "")),
		candidate.get("final_nodes", []),
		start_position
	)
	var voice_id = sequencer.add_voice(
		actions,
		float(candidate.get("old_start_beat", CL.get_time_beat())),
		_get_lsystem_volume(lsystem_index)
	)

	if voice_id == -1:
		preview_turtle.queue_free()
		return

	mutation_preview_voice_id = voice_id
	mutation_preview_turtle = preview_turtle
	voice_turtles[voice_id] = preview_turtle
	_apply_mutation_comparison_volumes()
	_apply_mutation_comparison_turtle_colors()

func _stop_mutation_preview() -> void:
	_restore_original_mutation_voice_volume()
	_restore_original_mutation_turtle_color()

	if mutation_preview_voice_id != -1:
		sequencer.remove_voice(mutation_preview_voice_id)
		voice_turtles.erase(mutation_preview_voice_id)
		mutation_preview_voice_id = -1

	if is_instance_valid(mutation_preview_turtle):
		mutation_preview_turtle.queue_free()

	mutation_preview_turtle = null

func set_mutation_comparison_side(side: String) -> void:
	if side != "original" and side != "candidate":
		return

	mutation_comparison_side = side

	if ui.has_method("set_mutation_side_visual"):
		ui.set_mutation_side_visual(side)

	_apply_mutation_comparison_volumes()
	_apply_mutation_comparison_turtle_colors()

func _apply_mutation_comparison_volumes() -> void:
	if pending_evolution_candidate.is_empty():
		return

	var lsystem_index := int(pending_evolution_candidate.get("lsystem_index", -1))
	var original_voice_id := -1

	if lsystem_voice_ids.has(lsystem_index):
		original_voice_id = int(lsystem_voice_ids[lsystem_index])

	if original_voice_id != -1:
		var original_volume := _get_lsystem_volume(lsystem_index)
		sequencer.set_voice_volume(original_voice_id, original_volume if mutation_comparison_side == "original" else 0.0)

	if mutation_preview_voice_id != -1:
		var candidate_volume := _get_lsystem_volume(lsystem_index)
		sequencer.set_voice_volume(mutation_preview_voice_id, candidate_volume if mutation_comparison_side == "candidate" else 0.0)

func _restore_original_mutation_voice_volume() -> void:
	if pending_evolution_candidate.is_empty():
		return

	var lsystem_index := int(pending_evolution_candidate.get("lsystem_index", -1))

	if not lsystem_voice_ids.has(lsystem_index):
		return

	sequencer.set_voice_volume(
		int(lsystem_voice_ids[lsystem_index]),
		_get_lsystem_volume(lsystem_index)
	)

func _apply_mutation_comparison_turtle_colors() -> void:
	if pending_evolution_candidate.is_empty():
		return

	var lsystem_index := int(pending_evolution_candidate.get("lsystem_index", -1))
	var inactive_color := Color(0.48, 0.48, 0.48, 1.0)
	var original_turtle = lsystem_turtles.get(lsystem_index)
	var selected_color := _get_lsystem_color(lsystem_index)

	for index in lsystem_turtles.keys():
		var current_turtle = lsystem_turtles[index]

		if not is_instance_valid(current_turtle):
			continue

		current_turtle.set_visual_radius_offset(0.0)

		if int(index) == lsystem_index:
			continue

		current_turtle.set_voice_color(inactive_color)

	if is_instance_valid(original_turtle):
		original_turtle.set_voice_color(selected_color if mutation_comparison_side == "original" else inactive_color)
		original_turtle.set_visual_radius_offset(5.0 if mutation_comparison_side == "original" else 0.0)

	if is_instance_valid(mutation_preview_turtle):
		mutation_preview_turtle.set_voice_color(selected_color if mutation_comparison_side == "candidate" else inactive_color)
		mutation_preview_turtle.set_visual_radius_offset(5.0 if mutation_comparison_side == "candidate" else 0.0)

func _restore_original_mutation_turtle_color() -> void:
	for index in lsystem_turtles.keys():
		var current_turtle = lsystem_turtles[index]

		if not is_instance_valid(current_turtle):
			continue

		current_turtle.set_voice_color(_get_lsystem_color(int(index)))
		current_turtle.set_visual_radius_offset(0.0)

	if is_instance_valid(mutation_preview_turtle):
		mutation_preview_turtle.set_visual_radius_offset(0.0)

func _refresh_mutation_prompt_debug() -> void:
	if last_piano_roll_selection.is_empty():
		return

	var selected_actions = _print_actions_for_bar_selection(last_piano_roll_selection)
	ui.show_mutation_prompt(
		_build_lsystem_color_array(),
		evolution.build_selection_debug_text(last_piano_roll_selection, selected_actions),
		int(last_piano_roll_selection.get("active_lsystem_index", current_lsystem_index))
	)

##################################################
########## SEQUENCER LOOKUP HELPERS #############
##################################################
func _get_sequencer_voice(voice_id: int) -> Dictionary:
	for voice in sequencer.voices:
		if int(voice.get("id", -1)) == voice_id:
			return voice

	return {}

func _get_voice_actions_in_beat_range(
	voice: Dictionary,
	range_start_beat: float,
	range_end_beat: float
) -> Array:
	var selected_actions := []
	var score: Array = voice.get("score", [])
	var loop_length := float(voice.get("loop_length", 0.0))
	var voice_start_beat := float(voice.get("start_beat", 0.0))

	if score.is_empty() or loop_length <= 0.0 or range_end_beat <= range_start_beat:
		return selected_actions

	var first_loop : float = max(0, int(floor((range_start_beat - voice_start_beat) / loop_length)))
	var last_loop : float = max(first_loop, int(floor((range_end_beat - voice_start_beat) / loop_length)))

	for loop_index in range(first_loop, last_loop + 1):
		for action in score:
			var local_start := float(action.get("start_beat", 0.0))
			var duration := float(action.get("duration_beats", 0.0))
			var absolute_start := voice_start_beat + loop_index * loop_length + local_start
			var absolute_end := absolute_start + duration

			if absolute_start >= range_end_beat or absolute_end <= range_start_beat:
				continue

			var printable_action = action.duplicate()
			printable_action["absolute_start_beat"] = absolute_start
			printable_action["absolute_end_beat"] = absolute_end
			printable_action["loop_index"] = loop_index
			selected_actions.append(printable_action)

	return selected_actions

##################################################
########## LSYSTEM DISPLAY LABELS #############
##################################################
func _build_lsystem_info() -> Array:
	var info: Array = []

	for index in range(lsystems.size()):
		var lsystem_info = lsystems[index].get_info()
		lsystem_info["muted"] = bool(voice_mute_states.get(index, false))
		info.append(lsystem_info)

	return info

func _set_lsystem_origin(index: int, anchor) -> void:
	if index < 0 or index >= lsystems.size():
		return

	lsystems[index].set_origin(anchor, _describe_anchor(anchor))

func _set_lsystem_start_beat(index: int, start_beat: float) -> void:
	if index < 0 or index >= lsystems.size():
		return

	lsystems[index].set_start_beat(start_beat, _format_beat_label(start_beat))

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

##################################################
########## VOICE AND TURTLE CLEANUP #############
##################################################
func _clear_playing_voices(start_pos: Vector2) -> void:
	sequencer.clear_voices()

	for voice_id in voice_turtles:
		var old_turtle = voice_turtles[voice_id]

		if is_instance_valid(old_turtle):
			old_turtle.queue_free()

	voice_turtles.clear()
	lsystem_turtles.clear()
	lsystem_voice_ids.clear()
	mutation_preview_voice_id = -1
	mutation_preview_turtle = null
	turtle.hide_turtle()
	piano_roll.clear_events()

func _remove_lsystem_turtle(index: int) -> void:
	if not lsystem_turtles.has(index):
		return

	var removed_turtle = lsystem_turtles[index]
	lsystem_turtles.erase(index)

	if not is_instance_valid(removed_turtle):
		return

	removed_turtle.queue_free()

func _shift_lsystem_index_mapping(mapping: Dictionary, removed_index: int) -> void:
	var shifted_mapping := {}

	for mapping_index in mapping.keys():
		var new_index = int(mapping_index)

		if new_index == removed_index:
			continue

		if new_index > removed_index:
			new_index -= 1

		shifted_mapping[new_index] = mapping[mapping_index]

	mapping.clear()

	for mapping_index in shifted_mapping.keys():
		mapping[mapping_index] = shifted_mapping[mapping_index]

##################################################
########## TURTLE ASSIGNMENT #############
##################################################
func _get_turtle_for_lsystem(index: int, start_pos: Vector2) -> Turtle:
	var existing_turtle = lsystem_turtles.get(index)

	if is_instance_valid(existing_turtle):
		existing_turtle.clear_path(start_pos)
		existing_turtle.set_voice_color(_get_lsystem_color(index))
		existing_turtle.set_visual_radius_offset(0.0)
		return existing_turtle

	var new_turtle: Turtle
	new_turtle = turtle_scene.instantiate() as Turtle

	if not new_turtle:
		push_error("Turtle.tscn must use scripts/turtle.gd for multi-voice playback.")
		return turtle

	tonnetz_world.add_child(new_turtle)

	new_turtle.global_position = start_pos
	new_turtle.clear_path(start_pos)
	new_turtle.set_voice_color(_get_lsystem_color(index))
	new_turtle.set_visual_radius_offset(0.0)
	lsystem_turtles[index] = new_turtle

	return new_turtle

##################################################
########## VOICE STOPPING #############
##################################################
func _stop_lsystem_voice(index: int) -> void:
	if not lsystem_voice_ids.has(index):
		var idle_turtle = lsystem_turtles.get(index)

		if is_instance_valid(idle_turtle):
			idle_turtle.stop_after_current_target()

		return

	var voice_id = lsystem_voice_ids[index]

	sequencer.remove_voice(voice_id)
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
	_stop_mutation_preview()
	sequencer.clear_voices()
	voice_turtles.clear()
	lsystem_voice_ids.clear()

	for voice_turtle in lsystem_turtles.values():
		if is_instance_valid(voice_turtle):
			voice_turtle.stop_after_current_target()

##################################################
########## GENERAL HELPERS #############
##################################################

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

func _start_clock_from_lsystem_click() -> void:
	clock_started_from_lsystem_click = true

	if not global_paused:
		CL.start_clock()

func _start_clock_if_lsystem_click_started() -> void:
	if clock_started_from_lsystem_click and not global_paused:
		CL.start_clock()

##################################################
########## TONNETZ INPUT #############
##################################################
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


	play_active_lsystem(snapped_pos)


##################################################
########## ACTIVE LSYSTEM ASSIGNMENT #############
##################################################
func set_lsystem(new_lsystem: LSystem) -> void:
	lsystem = new_lsystem

	if current_lsystem_index >= 0 and current_lsystem_index < lsystems.size():
		lsystems[current_lsystem_index] = new_lsystem
