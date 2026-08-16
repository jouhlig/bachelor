extends Node2D

# This class is the main controller for the game and UI.

const MidiExporterScript = preload("res://scripts/midi_exporter.gd")
const LSystemExportScript = preload("res://scripts/lsystem_export.gd")
const LSystemListScript = preload("res://scripts/lsystem_list.gd")
const RecordedWalkHelperScript = preload("res://scripts/recorded_walk_helper.gd")
const RecordedWalkExperimentHelperScript = preload("res://scripts/evolution/experiments/recorded_walk_experiment_helper.gd")
const EvolutionScript = preload("res://scripts/evolution/evolution.gd")

##################################################
########## SCENE REFERENCES #############
##################################################
@onready var tonnetz_world: Node2D = $UI/TonnetzViewportContainer/TonnetzViewport/TonnetzWorld
@onready var builder: TonnetzBuilder = $UI/TonnetzViewportContainer/TonnetzViewport/TonnetzWorld/TonnetzBuilder
@onready var interpreter = $Interpreter
@onready var sequencer: Sequencer = $Sequencer
@onready var audio_manager: AudioManager = AM
@onready var ui = $UI
var turtle_scene: PackedScene = preload("res://scenes/Turtle.tscn")

##################################################
########## LSYSTEM STATE #############
##################################################
var config: TonnetzConfig
var lsystem_list
var lsystem_spawn_origin_anchor = null
var lsystem_playback: LSystemRuntimeHelper
var midi_exporter: MidiExporter
var walk_recorder: WalkRecorder
var recorded_walk_helper
var lsystem_generation_running: bool = false

##################################################
########## PLAYBACK STATE #############
##################################################

func _ready() -> void:
	config = Config.config
	walk_recorder = WalkRecorder.new(config, builder, tonnetz_world)
	lsystem_playback = LSystemRuntimeHelper.new(
		config,
		interpreter,
		sequencer,
		tonnetz_world,
		turtle_scene
	)
	lsystem_list = LSystemListScript.new(config, lsystem_playback)
	recorded_walk_helper = RecordedWalkHelperScript.new(
		walk_recorder,
		lsystem_list,
		audio_manager
	)
	midi_exporter = MidiExporterScript.new(
		config,
		sequencer,
		lsystem_playback,
		lsystem_list.mute_states
	)

	# connect sequencer -> turtle/audio/ui
	sequencer.transition_started.connect(_on_transition_started)
	sequencer.event_entered.connect(_on_sequencer_event_entered)
	sequencer.note_entered.connect(_on_sequencer_note_entered)
	sequencer.voice_paused.connect(_on_voice_paused)
	sequencer.voice_reentered.connect(_on_voice_reentered)

	if ui.has_signal("lsystem_selected"):
		ui.add_random_lsystem_requested.connect(add_random_lsystem)
		ui.lsystem_selected.connect(select_lsystem)
		ui.lsystem_randomize_requested.connect(randomize_lsystem)
		ui.lsystem_duplicate_requested.connect(duplicate_lsystem)
		ui.lsystem_remove_requested.connect(remove_lsystem)
		ui.lsystem_solo_toggled.connect(set_lsystem_solo)
		ui.lsystem_axiom_changed.connect(set_lsystem_axiom)
		ui.lsystem_iterations_changed.connect(set_lsystem_iterations)
		ui.lsystem_rule_changed.connect(set_lsystem_rule)
		ui.lsystem_volume_changed.connect(set_lsystem_volume)
		ui.trail_length_changed.connect(set_trail_length)
		ui.lsystem_mute_toggled.connect(set_lsystem_muted)
		ui.all_lsystems_mute_toggled.connect(set_all_lsystems_muted)
		ui.master_volume_changed.connect(set_master_volume)
		ui.lsystem_preview_direction_changed.connect(change_lsystem_preview_direction)
		ui.walk_recording_started.connect(start_walk_recording)
		ui.walk_recording_cancelled.connect(cancel_walk_recording)
		ui.walk_recording_undo_requested.connect(undo_walk_recording_step)
		ui.walk_recording_duration_changed.connect(set_walk_recording_duration)
		ui.walk_lsystem_generate_requested.connect(generate_lsystem_from_recorded_score)
		ui.tonnetz_clicked.connect(_on_tonnetz_clicked)
		ui.export_midi_requested.connect(export_midi)
		ui.export_midi_voice_requested.connect(export_lsystem_midi)
		ui.export_lsystems_requested.connect(export_lsystems)
		ui.export_lsystem_requested.connect(export_lsystem)
		ui.import_lsystems_requested.connect(import_lsystems)

	# Build Tonnetz
	await builder.build()
	ui.center_tonnetz_view(builder)

	var experiment_result := RecordedWalkExperimentHelperScript.new(
		walk_recorder,
		builder,
		interpreter
	).run_from_command_line()
	if bool(experiment_result["handled"]):
		get_tree().quit(0 if bool(experiment_result["ok"]) else 1)
		return

	# Generate initial L-System
	lsystem_list.add_random()
	_refresh_lsystems_ui()

func _process(delta: float) -> void:
	_extend_explore_voices_if_needed()

func _is_lsystem_voice(index: int) -> bool:
	return lsystem_list.is_lsystem(index)

##################################################
########## SEQUENCER CALLBACKS #############
##################################################
func _on_transition_started(
	voice_id: int,
	current_event: Dictionary,
	next_event: Dictionary
) -> void:
	var voice_turtle = lsystem_playback.get_turtle_for_voice(voice_id)

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
	pass

func _on_voice_paused(voice_id: int, event: Dictionary) -> void:
	var voice_turtle = lsystem_playback.get_turtle_for_voice(voice_id)

	if is_instance_valid(voice_turtle):
		voice_turtle.pause_at_event(event)

func _on_voice_reentered(voice_id: int, event: Dictionary) -> void:
	var voice_turtle = lsystem_playback.get_turtle_for_voice(voice_id)

	if is_instance_valid(voice_turtle):
		voice_turtle.pause_at_event(event)

func _is_voice_muted(voice_id: int) -> bool:
	var lsystem_index = _get_lsystem_index_for_voice(voice_id)

	if not lsystem_list.has_index(lsystem_index):
		return false

	return bool(lsystem_list.mute_states.get(lsystem_index, false))

func play_active_lsystem(start_pos: Vector2) -> void:
	if not lsystem_list.has_index(lsystem_list.current_index):
		return

	if not _is_lsystem_voice(lsystem_list.current_index):
		return

	var start_beat = _get_next_grid_beat()
	var start_anchor = builder.get_nearest_spawn_anchor(start_pos)
	var start_state := _get_random_lsystem_start_state(start_anchor)

	if start_state.is_empty():
		return

	_set_lsystem_playback_start(
		lsystem_list.current_index,
		start_anchor,
		start_state["initial_dir"],
		start_state["initial_edge"]
	)
	if _play_lsystem_from_origin(
		lsystem_list.current_index,
		start_anchor,
		start_state["initial_dir"],
		start_state["initial_edge"],
		start_beat
	):
		CL.start_clock()
		_refresh_lsystems_ui()

func _play_lsystem_from_origin(
	index: int,
	origin,
	initial_dir: Vector2i,
	initial_edge: int,
	start_beat: float
) -> bool:
	if not lsystem_list.has_index(index):
		return false

	var current_system = lsystem_list.systems[index]

	if not (current_system is LSystem):
		return false

	if origin == null or not origin.has_method("get_center"):
		return false

	_set_lsystem_start_beat(index, start_beat)
	var voice_id = lsystem_playback.play(
		index,
		current_system,
		origin,
		initial_dir,
		initial_edge,
		start_beat
	)

	return voice_id != -1

func _extend_explore_voices_if_needed() -> void:
	var voice_ids := lsystem_playback.get_explore_voice_ids()

	if voice_ids.is_empty():
		return

	var current_beat : float = CL.get_time_beat()

	for voice_id in voice_ids:
		var voice = sequencer.get_voice(voice_id)

		if voice.is_empty() or not bool(voice.get("active", true)):
			lsystem_playback.erase_explore_voice(voice_id)
			continue

		if not lsystem_playback.needs_explore_extension(voice_id, current_beat):
			continue

		var lsystem_index = _get_lsystem_index_for_voice(voice_id)

		if lsystem_index == -1:
			lsystem_playback.erase_explore_voice(voice_id)
			continue

		var extended := false

		if _is_lsystem_voice(lsystem_index):
			extended = lsystem_playback.append_explore_loop(
				lsystem_index,
				lsystem_list.get_system(lsystem_index),
				lsystem_playback.get_origin(lsystem_index),
				lsystem_playback.get_initial_dir(lsystem_index),
				lsystem_playback.get_initial_edge(lsystem_index),
				voice_id
			)

		if not extended:
			push_warning("Explore voice hit the Tonnetz border and stopped.")
			sequencer.request_stop_voice(voice_id)
			lsystem_playback.erase_explore_voice(voice_id)

##################################################
########## LSYSTEM LIST ACTIONS #############
##################################################
func add_random_lsystem() -> void:
	lsystem_list.add_random()
	_refresh_lsystems_ui()

func select_lsystem(index: int) -> void:
	if lsystem_list.select(index):
		_refresh_lsystems_ui()

func randomize_lsystem(index: int) -> void:
	if lsystem_list.randomize(index):
		_refresh_lsystems_ui()

func duplicate_lsystem(index: int) -> void:
	if lsystem_list.duplicate(index) >= 0:
		_refresh_lsystems_ui()

func generate_lsystem_from_recorded_score() -> void:
	if lsystem_generation_running:
		push_warning("L-system generation is already running.")
		return

	if recorded_walk_helper.is_recording():
		recorded_walk_helper.finish_recording()

	var source: Dictionary = recorded_walk_helper.get_generation_source()
	if not bool(source.get("ok", false)):
		push_warning(str(source.get("message", "Record a walk before generating an L-system.")))
		return

	# Generate from the recorded score and keep the captured start data
	lsystem_generation_running = true
	print("Generating L-system...")

	var result: Dictionary = await EvolutionScript.generate_lsystem_from_score(
		source["score"],
		source["origin"],
		interpreter
	)

	lsystem_generation_running = false

	if not bool(result.get("ok", false)):
		push_warning(str(result.get("message", "Could not generate an L-system.")))
		return

	var generated_system: LSystem = result["lsystem"]
	generated_system.color = source["color"]
	generated_system.set_volume(0.8)
	var initial_dir: Vector2i = result["initial_dir"]
	var initial_edge := int(result["initial_edge"])

	var generated_index: int = lsystem_list.add_system(generated_system, false)
	_set_lsystem_preview_start_state(generated_index, initial_dir, initial_edge)
	_set_lsystem_playback_start(generated_index, source["origin"], initial_dir, initial_edge)
	lsystem_list.set_fitness(generated_index, float(result["score"]))

	var start_beat: float = _get_next_grid_beat()

	if _play_lsystem_from_origin(generated_index, source["origin"], initial_dir, initial_edge, start_beat):
		CL.start_clock()

	print("Generated L-system score: ", result["score"])
	recorded_walk_helper.store_reference(source["score"], source["origin"], source["color"])
	recorded_walk_helper.clear_pending()
	_refresh_lsystems_ui()

func remove_lsystem(index: int) -> void:
	if lsystem_list.remove(index):
		_refresh_lsystems_ui()

##################################################
########## WALK RECORDER #############
##################################################
func start_walk_recording() -> void:
	recorded_walk_helper.start_recording()

func cancel_walk_recording() -> void:
	recorded_walk_helper.cancel_recording()

func set_walk_recording_duration(duration_beats: float) -> void:
	recorded_walk_helper.set_duration(duration_beats)

func undo_walk_recording_step() -> void:
	recorded_walk_helper.undo_step()

func finish_walk_recording() -> void:
	recorded_walk_helper.finish_recording()

##################################################
########## MIDI EXPORT #############
##################################################
func export_midi(path: String) -> void:
	var result: Dictionary = midi_exporter.export(path)

	if bool(result.get("ok", false)):
		print(result.get("message", "MIDI export complete."))
	else:
		push_error(str(result.get("message", "MIDI export failed.")))

func export_lsystem_midi(index: int, path: String) -> void:
	var result: Dictionary = midi_exporter.export_voice(index, path)

	if bool(result.get("ok", false)):
		print(result.get("message", "MIDI export complete."))
	else:
		push_error(str(result.get("message", "MIDI export failed.")))

func export_lsystems(path: String) -> void:
	var result: Dictionary = LSystemExportScript.export_file(
		path,
		lsystem_list.systems,
		lsystem_list.display_numbers,
		lsystem_list.mute_states,
		lsystem_playback,
		CL.bpm
	)
	_print_export_result(result)

func export_lsystem(index: int, path: String) -> void:
	if not lsystem_list.has_index(index):
		push_error("L-system export failed: invalid voice index %d." % index)
		return

	var result: Dictionary = LSystemExportScript.export_file(
		path,
		lsystem_list.systems,
		lsystem_list.display_numbers,
		lsystem_list.mute_states,
		lsystem_playback,
		CL.bpm,
		[index]
	)
	_print_export_result(result)

func import_lsystems(path: String) -> void:
	var result: Dictionary = LSystemExportScript.import_file(path, builder)

	if not bool(result.get("ok", false)):
		push_error(str(result.get("message", "L-system import failed.")))
		return

	var imported_entries := []

	for entry in result.get("entries", []):
		var imported_index: int = _import_lsystem_entry(entry)
		if imported_index < 0:
			continue

		imported_entries.append({
			"index": imported_index,
			"start": entry.get("start", {})
		})

	_start_imported_lsystems(imported_entries)
	_refresh_lsystems_ui()
	print(result.get("message", "L-system import complete."))

func _import_lsystem_entry(entry: Dictionary) -> int:
	if not entry.has("system"):
		return -1

	var imported_system: LSystem = entry["system"]

	if bool(entry.get("has_color", false)):
		lsystem_list.take_color(imported_system.color)
	else:
		lsystem_list.assign_next_color(imported_system)

	var imported_index: int = lsystem_list.add_system(imported_system, bool(entry.get("muted", false)))

	if entry.has("start") and entry["start"] is Dictionary:
		_import_lsystem_start(imported_index, entry["start"])

	return imported_index

func _print_export_result(result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		print(result.get("message", "L-system export complete."))
	else:
		push_error(str(result.get("message", "L-system export failed.")))

func _start_imported_lsystems(imported_entries: Array) -> void:
	if imported_entries.is_empty():
		return

	# Recreate imported voices on the next grid beat
	var base_start_beat := _get_next_grid_beat()
	var played_any := false

	for imported_entry in imported_entries:
		var index := int(imported_entry["index"])
		var start_data = imported_entry.get("start", {})

		if not (start_data is Dictionary):
			continue

		var origin = lsystem_playback.get_origin(index)

		if origin == null:
			continue

		var relative_start_beat := float(start_data.get("start_beat", -1.0))

		if relative_start_beat < 0.0:
			continue

		var start_beat := base_start_beat + relative_start_beat

		if _play_lsystem_from_origin(
			index,
			origin,
			lsystem_playback.get_initial_dir(index),
			lsystem_playback.get_initial_edge(index),
			start_beat
		):
			played_any = true

	if played_any:
		CL.start_clock()

func _import_lsystem_start(index: int, start_data: Dictionary) -> void:
	var origin = start_data.get("origin")
	var initial_dir: Vector2i = start_data.get("initial_dir", Vector2i(1, 0))
	var initial_edge := int(start_data.get("initial_edge", 0))
	var start_beat := float(start_data.get("start_beat", -1.0))

	_set_lsystem_preview_start_state(index, initial_dir, initial_edge)

	if origin != null:
		_set_lsystem_playback_start(index, origin, initial_dir, initial_edge)

	if start_beat >= 0.0:
		_set_lsystem_start_beat(index, start_beat)


##################################################
########## LSYSTEM EDIT CALLBACKS #############
##################################################
func set_lsystem_axiom(index: int, new_axiom: String) -> void:
	if lsystem_list.set_axiom(index, new_axiom):
		_refresh_lsystems_ui()

func set_lsystem_iterations(index: int, iterations: int) -> void:
	if lsystem_list.set_iterations(index, iterations):
		_refresh_lsystems_ui()

func set_lsystem_rule(index: int, symbol: String, production: String) -> void:
	if lsystem_list.set_rule(index, symbol, production):
		_refresh_lsystems_ui()

func set_lsystem_volume(index: int, volume: float) -> void:
	if not lsystem_list.set_volume(index, volume):
		return

	if lsystem_playback.has_voice(index):
		sequencer.set_voice_volume(lsystem_playback.get_voice_id(index), lsystem_list.get_volume(index))

func set_lsystem_muted(index: int, muted: bool) -> void:
	if lsystem_list.set_muted(index, muted):
		_refresh_lsystems_ui()

func set_master_volume(volume: float) -> void:
	audio_manager.set_master_volume(volume)

func set_trail_length(length_steps: int) -> void:
	config.turtle_trail_max_steps = max(1, length_steps)

func set_all_lsystems_muted(muted: bool) -> void:
	lsystem_list.set_all_muted(muted)
	_refresh_lsystems_ui()

func set_lsystem_solo(index: int, solo: bool) -> void:
	if lsystem_list.set_solo(index, solo):
		_refresh_lsystems_ui()

func change_lsystem_preview_direction(index: int, delta: int) -> void:
	if lsystem_list.change_preview_direction(index, delta):
		_refresh_lsystems_ui()

##################################################
########## LSYSTEM UI DATA #############
##################################################
func _refresh_lsystems_ui() -> void:
	ui.update_lsystems_ui(
		lsystem_list.systems,
		lsystem_list.current_index,
		lsystem_list.get_colors(),
		lsystem_list.get_volumes(),
		lsystem_list.get_info()
	)

func _set_lsystem_playback_start(
	index: int,
	origin,
	initial_dir: Vector2i,
	initial_edge: int
) -> void:
	if not lsystem_list.has_index(index):
		return

	lsystem_playback.set_start(
		index,
		origin,
		_describe_anchor(origin),
		initial_dir,
		initial_edge
	)

func _set_lsystem_preview_start_state(index: int, initial_dir: Vector2i, initial_edge: int) -> void:
	lsystem_list.set_preview_start_state(index, initial_dir, initial_edge)

func _set_lsystem_start_beat(index: int, start_beat: float) -> void:
	if not lsystem_list.has_index(index):
		return

	lsystem_playback.set_start_beat(index, start_beat)
	lsystem_list.set_start_label(index, _format_beat_label(start_beat))

func _describe_anchor(anchor) -> String:
	if anchor is TonnetzNode:
		return "Node %s%d" % [anchor.note_name, int(anchor.octave)]

	if anchor is TonnetzTriangle:
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
########## GENERAL HELPERS #############
##################################################

func _get_lsystem_index_for_voice(voice_id: int) -> int:
	return lsystem_playback.get_index_for_voice(voice_id)

func _get_next_grid_beat() -> float:
	var beat : float= CL.get_time_beat()

	if is_equal_approx(beat, round(beat)):
		return round(beat)

	return ceil(beat)

##################################################
########## TONNETZ INPUT #############
##################################################
func _unhandled_input(event) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		var click_pos = _get_tonnetz_world_mouse_position()
		if click_pos == null:
			if not event.pressed:
				lsystem_spawn_origin_anchor = null
			return

		if recorded_walk_helper.is_recording() and event.pressed:
			_on_tonnetz_clicked(click_pos)
			return

		if event.pressed:
			_begin_lsystem_spawn_drag(click_pos)
			return

		_handle_lsystem_spawn_release(click_pos)

func _get_tonnetz_world_mouse_position():
	var click_pos := get_global_mouse_position()

	if ui.has_method("is_position_in_tonnetz_area") and not ui.is_position_in_tonnetz_area(click_pos):
		return null

	if ui.has_method("get_tonnetz_world_position"):
		click_pos = ui.get_tonnetz_world_position(click_pos)

	return click_pos

func _handle_lsystem_spawn_release(_click_pos: Vector2) -> void:
	var current_system = lsystem_list.get_current_system()

	if not (current_system is LSystem):
		lsystem_spawn_origin_anchor = null
		return

	var origin_anchor = lsystem_spawn_origin_anchor
	lsystem_spawn_origin_anchor = null

	if origin_anchor:
		var start_state := _get_random_lsystem_start_state(origin_anchor)

		if start_state.is_empty():
			return

		var initial_dir: Vector2i = start_state["initial_dir"]
		var initial_edge: int = start_state["initial_edge"]
		var start_beat := _get_next_grid_beat()
		_set_lsystem_playback_start(lsystem_list.current_index, origin_anchor, initial_dir, initial_edge)

		if _play_lsystem_from_origin(lsystem_list.current_index, origin_anchor, initial_dir, initial_edge, start_beat):
			CL.start_clock()
			_refresh_lsystems_ui()

func _begin_lsystem_spawn_drag(click_pos: Vector2) -> void:
	if not _is_lsystem_voice(lsystem_list.current_index):
		return

	lsystem_spawn_origin_anchor = builder.get_nearest_spawn_anchor(click_pos)

func _get_random_lsystem_start_state(origin) -> Dictionary:
	# Pick the default direction for the clicked anchor type
	if origin is TonnetzNode:
		return {
			"initial_dir": TonnetzBuilder.AXIAL_DIRECTIONS[
				int(lsystem_list.preview_node_direction_indices.get(lsystem_list.current_index, 5))
			],
			"initial_edge": 0
		}

	if origin is TonnetzTriangle:
		return {
			"initial_dir": Vector2i(1, 0),
			"initial_edge": int(lsystem_list.preview_triangle_edges.get(lsystem_list.current_index, 0))
		}

	return {}

func _on_tonnetz_clicked(click_pos: Vector2) -> void:
	if recorded_walk_helper.is_recording():
		recorded_walk_helper.handle_click(click_pos)
		return

	_begin_lsystem_spawn_drag(click_pos)
