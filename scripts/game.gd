extends Node2D

const MidiExporterScript = preload("res://scripts/midi_exporter.gd")
const EvolutionScript = preload("res://scripts/evolution/evolution.gd")
const ExperimentRunnerScript = preload("res://scripts/evolution/experiments/experiment_runner.gd")
const TargetScoreStoreScript = preload("res://scripts/evolution/experiments/target_score_store.gd")
const RECORDED_WALK_EXPERIMENT_RESULTS_DIR := "res://scripts/evolution/experiments/results"
const RECORDED_WALK_TARGET_SCORES_PATH := "res://scripts/evolution/experiments/target_scores/random_target_scores.json"
const AUTO_RUN_RECORDED_WALK_EXPERIMENTS := false
const GENERATE_RECORDED_WALK_TARGETS_ARG := "--generate-recorded-walk-targets"
const RUN_RECORDED_WALK_EXPERIMENTS_ARG := "--run-recorded-walk-experiments"
const EXPERIMENT_ARG := "--experiment"
const RESULTS_DIR_ARG := "--results-dir"
const TARGET_SCORES_ARG := "--target-scores"
const TARGET_COUNT_ARG := "--target-count"
const CROSSOVER_RATE_ARG := "--crossover-rate"
const MUTATION_RATE_ARG := "--mutation-rate"
const TOURNAMENT_SIZE_ARG := "--tournament-size"
const PITCH_WEIGHT_ARG := "--pitch-weight"
const DISTANCE_WEIGHT_ARG := "--distance-weight"
const DURATION_MATCH_WEIGHT_ARG := "--duration-match-weight"
const TOTAL_DURATION_WEIGHT_ARG := "--total-duration-weight"
const MISSING_WEIGHT_ARG := "--missing-weight"
const EXTRA_WEIGHT_ARG := "--extra-weight"
const DEBUG_FINAL_SCORES_ARG := "--debug-final-scores"
const DEFAULT_TARGET_SCORE_COUNT := 1000
const PRINT_RECORDED_WALK_FIXTURE_ON_FINISH := false
const RECORDED_WALK_CLICK_SOUND_DURATION := 0.25

##################################################
########## SCENE REFERENCES #############
##################################################
@onready var tonnetz_world: Node2D = $UI/TonnetzViewportContainer/TonnetzViewport/TonnetzWorld
@onready var builder: TonnetzBuilder = $UI/TonnetzViewportContainer/TonnetzViewport/TonnetzWorld/TonnetzBuilder
@onready var interpreter = $Interpreter
@onready var sequencer: Sequencer = $Sequencer
@onready var audio_manager: AudioManager = AM
@onready var ui = $UI
var turtle_scene: PackedScene = preload("res://Turtle.tscn")

##################################################
########## LSYSTEM STATE #############
##################################################
var config: TonnetzConfig
var lsystem
var lsystems: Array = []
var lsystem_spawn_origin_anchor = null
var available_colors: Array[Color] = []
var current_lsystem_index := 0
var lsystem_playback: LSystemPlayback
var midi_exporter: MidiExporter
var walk_recorder: WalkRecorder
var pending_recorded_walk_score: Array = []
var pending_recorded_walk_origin = null
var pending_recorded_walk_color: Color = Color.WHITE
var recorded_walk_reference_score: Array = []
var recorded_walk_reference_origin = null
var recorded_walk_reference_color: Color = Color.WHITE
var recorded_walk_reference_layer: Node2D = null
var lsystem_generation_running: bool = false
var next_recorded_walk_click_voice_id := -1000
var voice_fitness_values := {}
var lsystem_playback_origins := {}
var lsystem_playback_origin_labels := {}
var lsystem_playback_initial_dirs := {}
var lsystem_playback_initial_edges := {}
var lsystem_preview_node_direction_indices := {}
var lsystem_preview_triangle_edges := {}
var voice_start_labels := {}
var voice_display_numbers := {}
var next_voice_display_number := 1
var solo_voice_index := -1

##################################################
########## PLAYBACK STATE #############
##################################################
var voice_mute_states := {}
var global_paused := false
var clock_started_from_lsystem_click := false

func _ready() -> void:
	config = Config.config
	walk_recorder = WalkRecorder.new(config, builder, tonnetz_world, turtle_scene)
	lsystem_playback = LSystemPlayback.new(
		config,
		interpreter,
		sequencer,
		tonnetz_world,
		turtle_scene
	)
	midi_exporter = MidiExporterScript.new(
		config,
		sequencer,
		lsystem_playback,
		voice_mute_states
	)
	available_colors = config.VOICE_COLORS.duplicate()
	available_colors.shuffle()

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
		ui.lsystem_stop_requested.connect(stop_lsystem)
		ui.lsystem_resume_requested.connect(resume_lsystem)
		ui.lsystem_solo_toggled.connect(set_lsystem_solo)
		ui.lsystem_axiom_changed.connect(set_lsystem_axiom)
		ui.lsystem_iterations_changed.connect(set_lsystem_iterations)
		ui.lsystem_rule_changed.connect(set_lsystem_rule)
		ui.lsystem_volume_changed.connect(set_lsystem_volume)
		ui.lsystem_mute_toggled.connect(set_lsystem_muted)
		ui.lsystem_preview_direction_changed.connect(change_lsystem_preview_direction)
		ui.walk_recording_started.connect(start_walk_recording)
		ui.walk_recording_cancelled.connect(cancel_walk_recording)
		ui.walk_recording_undo_requested.connect(undo_walk_recording_step)
		ui.walk_recording_duration_changed.connect(set_walk_recording_duration)
		ui.walk_lsystem_generate_requested.connect(generate_lsystem_from_recording)
		ui.walk_lsystem_regenerate_requested.connect(regenerate_lsystem_from_recording)
		ui.tonnetz_clicked.connect(_on_tonnetz_clicked)
		ui.global_play_pause_toggled.connect(set_global_paused)
		ui.stop_all_lsystems_requested.connect(_on_stop_all_lsystems_requested)
		ui.export_midi_requested.connect(export_midi)
		ui.export_midi_voice_requested.connect(export_lsystem_midi)

	# Build Tonnetz
	await builder.build()
	ui.center_tonnetz_view(builder)

	var target_args := _get_recorded_walk_target_args()
	if not target_args.is_empty():
		if not bool(target_args["ok"]):
			get_tree().quit(1)
			return

		var ok := _generate_recorded_walk_targets(
			str(target_args["target_scores_path"]),
			int(target_args["target_count"])
		)
		get_tree().quit(0 if ok else 1)
		return

	var experiment_args := _get_recorded_walk_experiment_args()
	if not experiment_args.is_empty():
		if not bool(experiment_args["ok"]):
			get_tree().quit(1)
			return

		var ok := _run_recorded_walk_experiments(
			str(experiment_args["experiment"]),
			str(experiment_args["results_dir"]),
			str(experiment_args["target_scores_path"]),
			int(experiment_args["target_count"]),
			float(experiment_args["crossover_rate"]),
			float(experiment_args["mutation_rate"]),
			int(experiment_args["tournament_size"]),
			experiment_args["fitness_weights"],
			bool(experiment_args["debug_final_scores"])
		)
		get_tree().quit(0 if ok else 1)
		return

	# Generate initial L-System
	lsystem = LSystemFactory.random(config)
	_configure_lsystem(lsystem, 0)
	_append_lsystem_voice(lsystem, false)
	_refresh_lsystems_ui()

	if AUTO_RUN_RECORDED_WALK_EXPERIMENTS:
		_run_recorded_walk_experiments(
			ExperimentRunnerScript.DEFAULT_EXPERIMENT_COMBINATION_NAME,
			RECORDED_WALK_EXPERIMENT_RESULTS_DIR,
			RECORDED_WALK_TARGET_SCORES_PATH,
			DEFAULT_TARGET_SCORE_COUNT
		)

func _process(delta: float) -> void:
	_extend_explore_voices_if_needed()

func _generate_recorded_walk_targets(
	target_scores_path: String,
	target_score_count: int
) -> bool:
	var target_scores := walk_recorder.generate_walks(target_score_count)
	if target_scores.is_empty():
		push_warning("No target scores generated.")
		return false

	TargetScoreStoreScript.save_scores(target_scores_path, target_scores)
	print("Generated ", target_scores.size(), " recorded walk targets at ", target_scores_path, ".")
	return true

func _run_recorded_walk_experiments(
	experiment_name: String,
	results_dir: String,
	target_scores_path: String,
	target_score_count: int,
	crossover_rate: float = -1.0,
	mutation_rate: float = -1.0,
	tournament_size: int = 0,
	fitness_weights: Dictionary = {},
	debug_final_scores: bool = false
) -> bool:
	var target_scores := TargetScoreStoreScript.load_scores(
		target_scores_path,
		builder
	)
	if target_scores.size() > target_score_count:
		target_scores = target_scores.slice(0, target_score_count)
	if target_scores.is_empty():
		target_scores = walk_recorder.generate_walks(target_score_count)
		TargetScoreStoreScript.save_scores(
			target_scores_path,
			target_scores
		)

	if target_scores.is_empty():
		push_warning("No target scores available for experiments.")
		return false

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(results_dir))

	var experiment_config := EvolutionScript.create_default_config()
	if crossover_rate >= 0.0:
		experiment_config["crossover_rate"] = crossover_rate
	if mutation_rate >= 0.0:
		experiment_config["mutation_rate"] = mutation_rate
	if tournament_size > 0:
		experiment_config["tournament_size"] = tournament_size
	for key in fitness_weights.keys():
		experiment_config["fitness_weights"][key] = fitness_weights[key]
	experiment_config["debug_final_scores"] = debug_final_scores
	experiment_config["target_scores_path"] = target_scores_path
	experiment_config["target_score_count"] = target_scores.size()
	print("Running recorded walk experiment ", experiment_name, " for ", target_scores.size(), " target scores.")

	if experiment_name == "all":
		ExperimentRunnerScript.test_all_combinations(
			target_scores,
			interpreter,
			experiment_config,
			results_dir
		)
	else:
		ExperimentRunnerScript.test_one_combination(
			target_scores,
			experiment_name,
			interpreter,
			experiment_config,
			results_dir
		)

	print("Recorded walk experiments finished.")
	return true

func _get_recorded_walk_target_args() -> Dictionary:
	var args := OS.get_cmdline_user_args()
	if not args.has(GENERATE_RECORDED_WALK_TARGETS_ARG):
		return {}

	return _get_recorded_walk_target_options(args, GENERATE_RECORDED_WALK_TARGETS_ARG)

func _get_recorded_walk_experiment_args() -> Dictionary:
	var args := OS.get_cmdline_user_args()
	if not args.has(RUN_RECORDED_WALK_EXPERIMENTS_ARG):
		return {}

	var experiment_name := ExperimentRunnerScript.DEFAULT_EXPERIMENT_COMBINATION_NAME
	var results_dir := RECORDED_WALK_EXPERIMENT_RESULTS_DIR
	var target_scores_path := RECORDED_WALK_TARGET_SCORES_PATH
	var target_count := DEFAULT_TARGET_SCORE_COUNT
	var crossover_rate := -1.0
	var mutation_rate := -1.0
	var tournament_size := 0
	var fitness_weights := {}
	var debug_final_scores := false
	var index := 0

	while index < args.size():
		var arg := str(args[index])
		if arg == RUN_RECORDED_WALK_EXPERIMENTS_ARG:
			index += 1
		elif arg == EXPERIMENT_ARG:
			experiment_name = _get_arg_value(args, index)
			index += 2
		elif arg == RESULTS_DIR_ARG:
			results_dir = _get_arg_value(args, index)
			index += 2
		elif arg == TARGET_SCORES_ARG:
			target_scores_path = _get_arg_value(args, index)
			index += 2
		elif arg == TARGET_COUNT_ARG:
			target_count = int(_get_arg_value(args, index))
			index += 2
		elif arg == CROSSOVER_RATE_ARG:
			crossover_rate = float(_get_arg_value(args, index))
			index += 2
		elif arg == MUTATION_RATE_ARG:
			mutation_rate = float(_get_arg_value(args, index))
			index += 2
		elif arg == TOURNAMENT_SIZE_ARG:
			tournament_size = int(_get_arg_value(args, index))
			index += 2
		elif arg == PITCH_WEIGHT_ARG:
			fitness_weights["pitch_weight"] = float(_get_arg_value(args, index))
			index += 2
		elif arg == DISTANCE_WEIGHT_ARG:
			fitness_weights["distance_weight"] = float(_get_arg_value(args, index))
			index += 2
		elif arg == DURATION_MATCH_WEIGHT_ARG:
			fitness_weights["duration_match_weight"] = float(_get_arg_value(args, index))
			index += 2
		elif arg == TOTAL_DURATION_WEIGHT_ARG:
			fitness_weights["total_duration_weight"] = float(_get_arg_value(args, index))
			index += 2
		elif arg == MISSING_WEIGHT_ARG:
			fitness_weights["missing_weight"] = float(_get_arg_value(args, index))
			index += 2
		elif arg == EXTRA_WEIGHT_ARG:
			fitness_weights["extra_weight"] = float(_get_arg_value(args, index))
			index += 2
		elif arg == DEBUG_FINAL_SCORES_ARG:
			debug_final_scores = true
			index += 1
		else:
			push_error("Unknown experiment argument: %s" % arg)
			return {"ok": false}

	if results_dir.is_empty():
		push_error("Experiment results dir is empty.")
		return {"ok": false}

	if target_scores_path.is_empty():
		push_error("Target scores path is empty.")
		return {"ok": false}

	if target_count <= 0:
		push_error("Target score count must be greater than 0.")
		return {"ok": false}

	if experiment_name != "all" and not ExperimentRunnerScript.get_combination_names().has(experiment_name):
		push_error("Unknown experiment combination: %s" % experiment_name)
		print("Available combinations: ", ", ".join(ExperimentRunnerScript.get_combination_names()))
		return {"ok": false}

	return {
		"ok": true,
		"experiment": experiment_name,
		"results_dir": results_dir,
		"target_scores_path": target_scores_path,
		"target_count": target_count,
		"crossover_rate": crossover_rate,
		"mutation_rate": mutation_rate,
		"tournament_size": tournament_size,
		"fitness_weights": fitness_weights,
		"debug_final_scores": debug_final_scores
	}

func _get_recorded_walk_target_options(
	args: PackedStringArray,
	mode_arg: String
) -> Dictionary:
	var target_scores_path := RECORDED_WALK_TARGET_SCORES_PATH
	var target_count := DEFAULT_TARGET_SCORE_COUNT
	var index := 0

	while index < args.size():
		var arg := str(args[index])
		if arg == mode_arg:
			index += 1
		elif arg == TARGET_SCORES_ARG:
			target_scores_path = _get_arg_value(args, index)
			index += 2
		elif arg == TARGET_COUNT_ARG:
			target_count = int(_get_arg_value(args, index))
			index += 2
		else:
			push_error("Unknown target generation argument: %s" % arg)
			return {"ok": false}

	if target_scores_path.is_empty():
		push_error("Target scores path is empty.")
		return {"ok": false}

	if target_count <= 0:
		push_error("Target score count must be greater than 0.")
		return {"ok": false}

	return {
		"ok": true,
		"target_scores_path": target_scores_path,
		"target_count": target_count
	}

func _get_arg_value(args: PackedStringArray, index: int) -> String:
	if index + 1 >= args.size():
		push_error("Missing value for argument: %s" % args[index])
		return ""

	return str(args[index + 1])

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

func _append_lsystem_voice(system, muted: bool) -> int:
	var index: int = lsystems.size()
	lsystems.insert(index, system)
	lsystem_playback.shift_after_insert(index)
	_shift_lsystem_index_mapping_after_insert(voice_mute_states, index)
	_shift_lsystem_index_mapping_after_insert(voice_fitness_values, index)
	_shift_lsystem_index_mapping_after_insert(lsystem_playback_origins, index)
	_shift_lsystem_index_mapping_after_insert(lsystem_playback_origin_labels, index)
	_shift_lsystem_index_mapping_after_insert(lsystem_playback_initial_dirs, index)
	_shift_lsystem_index_mapping_after_insert(lsystem_playback_initial_edges, index)
	_shift_lsystem_index_mapping_after_insert(lsystem_preview_node_direction_indices, index)
	_shift_lsystem_index_mapping_after_insert(lsystem_preview_triangle_edges, index)
	_shift_lsystem_index_mapping_after_insert(voice_start_labels, index)
	_shift_lsystem_index_mapping_after_insert(voice_display_numbers, index)
	voice_mute_states[index] = muted
	voice_display_numbers[index] = next_voice_display_number
	next_voice_display_number += 1
	_ensure_lsystem_preview_start_state(index)
	current_lsystem_index = index
	set_lsystem(system)
	return index

func _get_lsystem(index: int):
	if index < 0 or index >= lsystems.size():
		return null

	return lsystems[index]

func _is_lsystem_voice(index: int) -> bool:
	return _get_lsystem(index) is LSystem

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
	var voice_turtle = lsystem_playback.get_turtle_for_voice(voice_id)

	if not is_instance_valid(voice_turtle):
		return

	var visual_current_event := _get_visual_transition_event(current_event, next_event)

	voice_turtle.start_transition(
		visual_current_event,
		next_event
	)

func _get_visual_transition_event(
	current_event: Dictionary,
	next_event: Dictionary
) -> Dictionary:
	if current_event.has("wrap_transition_target"):
		return current_event

	if not current_event.has("anchor") or not next_event.has("anchor"):
		return current_event

	var current_anchor = current_event["anchor"]
	var next_anchor = next_event["anchor"]

	if not current_anchor or not next_anchor:
		return current_event

	if not current_anchor.has_method("get_center") or not next_anchor.has_method("get_center"):
		return current_event

	var target_position: Vector2 = next_anchor.get_center()
	var visual_target: Vector2 = builder.get_nearest_visual_copy_position(
		next_anchor,
		current_anchor.get_center()
	)
	var tile_offset := visual_target - target_position

	if tile_offset.length_squared() <= 0.001:
		return current_event

	var visual_event := current_event.duplicate(true)
	visual_event["wrap_transition_target"] = visual_target
	visual_event["wrap_tile_offset"] = tile_offset
	visual_event["break_trail_after_transition"] = true
	return visual_event

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

	if lsystem_index < 0 or lsystem_index >= lsystems.size():
		return false

	return bool(voice_mute_states.get(lsystem_index, false))

func play_active_lsystem(start_pos: Vector2) -> void:
	if current_lsystem_index < 0 or current_lsystem_index >= lsystems.size():
		return

	if not _is_lsystem_voice(current_lsystem_index):
		return

	var start_beat = _get_next_grid_beat()
	var start_anchor = builder.get_nearest_spawn_anchor(start_pos)
	var start_state := _get_random_lsystem_start_state(start_anchor)

	if start_state.is_empty():
		return

	_set_lsystem_playback_start(
		current_lsystem_index,
		start_anchor,
		start_state["initial_dir"],
		start_state["initial_edge"]
	)
	if _play_lsystem_from_origin(
		current_lsystem_index,
		start_anchor,
		start_state["initial_dir"],
		start_state["initial_edge"],
		start_beat
	):
		_start_clock_from_lsystem_click()
		_refresh_lsystems_ui()

func _play_lsystem_from_origin(
	index: int,
	origin,
	initial_dir: Vector2i,
	initial_edge: int,
	start_beat: float
) -> bool:
	if index < 0 or index >= lsystems.size():
		return false

	var current_system = lsystems[index]

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
				_get_lsystem(lsystem_index),
				lsystem_playback_origins.get(lsystem_index),
				lsystem_playback_initial_dirs.get(lsystem_index, Vector2i(1, 0)),
				int(lsystem_playback_initial_edges.get(lsystem_index, 0)),
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
	var new_system := LSystemFactory.random(config)

	_configure_lsystem(new_system, lsystems.size())
	_append_lsystem_voice(new_system, false)
	_refresh_lsystems_ui()

func select_lsystem(index: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	current_lsystem_index = index
	lsystem = lsystems[index]
	_refresh_lsystems_ui()

func randomize_lsystem(index: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	if not _is_lsystem_voice(index):
		return

	lsystems[index].randomize(config)
	voice_fitness_values.erase(index)
	select_lsystem(index)

func duplicate_lsystem(index: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	if not lsystems[index].has_method("duplicate_system"):
		return

	var duplicate_system = lsystems[index].duplicate_system()
	duplicate_system.color = _get_next_available_color()

	var duplicate_index := _append_lsystem_voice(
		duplicate_system,
		bool(voice_mute_states.get(index, false))
	)
	lsystem_preview_node_direction_indices[duplicate_index] = lsystem_preview_node_direction_indices.get(index, 5)
	lsystem_preview_triangle_edges[duplicate_index] = lsystem_preview_triangle_edges.get(index, 0)
	if voice_fitness_values.has(index):
		voice_fitness_values[duplicate_index] = voice_fitness_values[index]
	_refresh_lsystems_ui()

func generate_lsystem_from_recording() -> void:
	if lsystem_generation_running:
		push_warning("L-system generation is already running.")
		return

	if walk_recorder.is_recording():
		finish_walk_recording()

	if not _has_recorded_walk_step(pending_recorded_walk_score):
		push_warning("Record a walk before generating an L-system.")
		return

	if pending_recorded_walk_origin == null:
		push_warning("The recorded walk has no origin.")
		return

	await _generate_lsystem_from_recorded_score(
		pending_recorded_walk_score.duplicate(true),
		pending_recorded_walk_origin,
		pending_recorded_walk_color
	)

func regenerate_lsystem_from_recording() -> void:
	if lsystem_generation_running:
		push_warning("L-system generation is already running.")
		return

	if not _has_recorded_walk_step(recorded_walk_reference_score):
		push_warning("Generate from a recorded walk before regenerating.")
		return

	if recorded_walk_reference_origin == null:
		push_warning("The recorded walk has no origin.")
		return

	await _generate_lsystem_from_recorded_score(
		recorded_walk_reference_score.duplicate(true),
		recorded_walk_reference_origin,
		recorded_walk_reference_color
	)

func _generate_lsystem_from_recorded_score(
	score: Array,
	origin,
	color: Color
) -> void:
	lsystem_generation_running = true
	print("Generating L-system...")

	var result: Dictionary = await EvolutionScript.generate_lsystem_from_recording(
		score,
		origin,
		get_tree()
	)

	lsystem_generation_running = false

	if not bool(result.get("ok", false)):
		push_warning(str(result.get("message", "Could not generate an L-system.")))
		return

	var generated_system: LSystem = result["lsystem"]
	generated_system.color = color
	generated_system.set_volume(0.8)
	var initial_dir: Vector2i = result["initial_dir"]
	var initial_edge := int(result["initial_edge"])

	var generated_index := _append_lsystem_voice(generated_system, false)
	_set_lsystem_preview_start_state(generated_index, initial_dir, initial_edge)
	_set_lsystem_playback_start(generated_index, origin, initial_dir, initial_edge)
	voice_fitness_values[generated_index] = float(result["score"])

	var start_beat: float = _get_next_grid_beat()

	if _play_lsystem_from_origin(generated_index, origin, initial_dir, initial_edge, start_beat):
		_start_clock_from_lsystem_click()

	print("Generated L-system score: ", result["score"])
	_show_recorded_walk_reference(
		score,
		origin,
		color
	)
	_clear_pending_recorded_walk()
	_refresh_lsystems_ui()

func remove_lsystem(index: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	_return_color_to_pool(lsystems[index].color)

	lsystem_playback.stop_voice(index)
	lsystem_playback.remove_visual(index)

	lsystems.remove_at(index)

	lsystem_playback.shift_after_removal(index)
	_shift_lsystem_index_mapping(voice_mute_states, index)
	_shift_lsystem_index_mapping(voice_fitness_values, index)
	_shift_lsystem_index_mapping(lsystem_playback_origins, index)
	_shift_lsystem_index_mapping(lsystem_playback_origin_labels, index)
	_shift_lsystem_index_mapping(lsystem_playback_initial_dirs, index)
	_shift_lsystem_index_mapping(lsystem_playback_initial_edges, index)
	_shift_lsystem_index_mapping(lsystem_preview_node_direction_indices, index)
	_shift_lsystem_index_mapping(lsystem_preview_triangle_edges, index)
	_shift_lsystem_index_mapping(voice_start_labels, index)
	_shift_lsystem_index_mapping(voice_display_numbers, index)

	if solo_voice_index == index:
		solo_voice_index = -1
	elif solo_voice_index > index:
		solo_voice_index -= 1

	if lsystems.is_empty():
		current_lsystem_index = -1
		_refresh_lsystems_ui()
		return

	if current_lsystem_index > index:
		current_lsystem_index -= 1
	elif current_lsystem_index >= lsystems.size():
		current_lsystem_index = lsystems.size() - 1

	lsystem = lsystems[current_lsystem_index]
	_refresh_lsystems_ui()

func stop_lsystem(index: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	lsystem_playback.request_stop_voice(index)
	_refresh_lsystems_ui()

func resume_lsystem(index: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	if not lsystem_playback.has_voice(index):
		return

	var start_beat = _get_next_grid_beat()
	var resumed_any := false
	var voice_id = lsystem_playback.get_voice_id(index)
	var voice_turtle = lsystem_playback.get_turtle_for_voice(voice_id)

	if is_instance_valid(voice_turtle):
		voice_turtle.set_voice_color(_get_lsystem_color(index))

	if sequencer.resume_voice(voice_id, start_beat):
		resumed_any = true

	if resumed_any:
		_set_lsystem_start_beat(index, start_beat)
		_start_clock_if_lsystem_click_started()
		_refresh_lsystems_ui()

func set_global_paused(paused: bool) -> void:
	global_paused = paused

	if paused:
		CL.stop_clock()
	else:
		_start_clock_if_lsystem_click_started()

##################################################
########## WALK RECORDER #############
##################################################
func start_walk_recording() -> void:
	if walk_recorder.is_recording():
		_return_color_to_pool(walk_recorder.get_color())

	_clear_recorded_walk_reference()

	if not pending_recorded_walk_score.is_empty():
		_return_color_to_pool(pending_recorded_walk_color)
		_clear_pending_recorded_walk()

	walk_recorder.start(_get_next_available_color())

func cancel_walk_recording() -> void:
	_return_color_to_pool(walk_recorder.get_color())
	walk_recorder.cancel()

func set_walk_recording_duration(duration_beats: float) -> void:
	walk_recorder.set_duration(duration_beats)

func undo_walk_recording_step() -> void:
	walk_recorder.undo_step()

func finish_walk_recording() -> void:
	if not walk_recorder.is_recording():
		return

	if not walk_recorder.has_recorded_step():
		cancel_walk_recording()
		return

	var score: Array = walk_recorder.build_score()

	if not _has_recorded_walk_step(score):
		cancel_walk_recording()
		return

	pending_recorded_walk_score = score
	pending_recorded_walk_origin = walk_recorder.get_origin()
	pending_recorded_walk_color = walk_recorder.get_color()

	walk_recorder.cancel()

	print("Recorded walk ready for L-system generation.")
	if PRINT_RECORDED_WALK_FIXTURE_ON_FINISH:
		print(_format_recorded_walk_fixture("recorded_walk", score))

func _has_recorded_walk_step(score: Array) -> bool:
	if score.size() < 2:
		return false

	var first_anchor = score[0].get("anchor")
	var second_anchor = score[1].get("anchor")
	return first_anchor != null and second_anchor != null and first_anchor != second_anchor

func _format_recorded_walk_fixture(walk_name: String, score: Array) -> String:
	var lines := PackedStringArray()
	lines.append("{")
	lines.append("\t\"name\": \"%s\"," % walk_name)
	lines.append("\t\"events\": [")

	for index in range(score.size()):
		var event: Dictionary = score[index]
		var suffix := "," if index < score.size() - 1 else ""
		lines.append("\t\t{\"anchor\": %s, \"duration_beats\": %.6f}%s" % [
			_format_anchor_fixture(event.get("anchor")),
			float(event.get("duration_beats", 0.0)),
			suffix
		])

	lines.append("\t]")
	lines.append("}")
	return "\n".join(lines)

func _format_anchor_fixture(anchor) -> String:
	if anchor is TonnetzNode:
		return "{\"type\": \"node\", \"q\": %d, \"r\": %d}" % [
			anchor.q,
			anchor.r
		]

	if anchor is TriangleArea:
		var coords: Array[Vector2i] = anchor.get_node_coords()
		coords.sort()
		var parts := PackedStringArray()
		for coord in coords:
			parts.append("[%d, %d]" % [coord.x, coord.y])
		return "{\"type\": \"triangle\", \"nodes\": [%s]}" % ", ".join(parts)

	return "{}"

func _clear_pending_recorded_walk() -> void:
	pending_recorded_walk_score.clear()
	pending_recorded_walk_origin = null
	pending_recorded_walk_color = Color.WHITE

func _show_recorded_walk_reference(
	score: Array,
	origin,
	color: Color
) -> void:
	var copied_score: Array = score.duplicate(true)

	_clear_recorded_walk_reference()
	recorded_walk_reference_score = copied_score
	recorded_walk_reference_origin = origin
	recorded_walk_reference_color = color

	recorded_walk_reference_layer = Node2D.new()
	recorded_walk_reference_layer.name = "RecordedWalkReference"
	recorded_walk_reference_layer.z_index = config.recorded_walk_reference_z_index
	tonnetz_world.add_child(recorded_walk_reference_layer)

	var line_color: Color = color
	line_color.a = config.recorded_walk_reference_alpha

	for event_index in range(max(0, recorded_walk_reference_score.size() - 1)):
		var current_event: Dictionary = recorded_walk_reference_score[event_index]
		var next_event: Dictionary = recorded_walk_reference_score[event_index + 1]

		if not _should_draw_recorded_walk_reference_segment(current_event, next_event):
			continue

		var line: Line2D = Line2D.new()
		line.width = config.recorded_walk_reference_width
		line.default_color = line_color
		line.antialiased = true
		line.add_point(current_event["anchor"].get_center())
		line.add_point(next_event["anchor"].get_center())
		recorded_walk_reference_layer.add_child(line)

func _should_draw_recorded_walk_reference_segment(
	current_event: Dictionary,
	next_event: Dictionary
) -> bool:
	if not bool(current_event.get("draw_trail", true)):
		return false

	if bool(current_event.get("hide_turtle_during_transition", false)):
		return false

	if not current_event.has("anchor") or not next_event.has("anchor"):
		return false

	var current_anchor = current_event["anchor"]
	var next_anchor = next_event["anchor"]

	if current_anchor == null or next_anchor == null:
		return false

	if not current_anchor.has_method("get_center"):
		return false

	if not next_anchor.has_method("get_center"):
		return false

	return true

func _clear_recorded_walk_reference() -> void:
	recorded_walk_reference_score.clear()
	recorded_walk_reference_origin = null
	recorded_walk_reference_color = Color.WHITE

	if is_instance_valid(recorded_walk_reference_layer):
		recorded_walk_reference_layer.queue_free()

	recorded_walk_reference_layer = null

func _handle_walk_recording_click(click_pos: Vector2) -> void:
	var recorded_anchor = walk_recorder.handle_click(click_pos)

	if recorded_anchor:
		_play_recorded_walk_click_sound(recorded_anchor)

func _play_recorded_walk_click_sound(anchor) -> void:
	var voice_id := next_recorded_walk_click_voice_id
	next_recorded_walk_click_voice_id -= 1

	if anchor is TriangleArea:
		audio_manager.play_notes(
			anchor.nodes,
			0.8,
			RECORDED_WALK_CLICK_SOUND_DURATION,
			voice_id
		)
	elif anchor is TonnetzNode:
		audio_manager.play_notes(
			[anchor],
			0.8,
			RECORDED_WALK_CLICK_SOUND_DURATION,
			voice_id
		)

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


##################################################
########## LSYSTEM EDIT CALLBACKS #############
##################################################
func set_lsystem_axiom(index: int, new_axiom: String) -> void:
	if index < 0 or index >= lsystems.size() or new_axiom.is_empty():
		return

	if not _is_lsystem_voice(index):
		return

	lsystems[index].set_axiom(new_axiom)
	voice_fitness_values.erase(index)
	select_lsystem(index)

func set_lsystem_iterations(index: int, iterations: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	if not _is_lsystem_voice(index):
		return

	lsystems[index].set_iterations(iterations)
	voice_fitness_values.erase(index)
	select_lsystem(index)

func set_lsystem_rule(index: int, symbol: String, production: String) -> void:
	if index < 0 or index >= lsystems.size():
		return

	if not _is_lsystem_voice(index):
		return

	lsystems[index].set_rule(symbol, production)
	voice_fitness_values.erase(index)
	select_lsystem(index)

func set_lsystem_volume(index: int, volume: float) -> void:
	if index < 0 or index >= lsystems.size():
		return

	lsystems[index].set_volume(volume)

	if lsystem_playback.has_voice(index):
		sequencer.set_voice_volume(lsystem_playback.get_voice_id(index), lsystems[index].volume)

func set_lsystem_muted(index: int, muted: bool) -> void:
	if index < 0 or index >= lsystems.size():
		return

	voice_mute_states[index] = muted
	_refresh_lsystems_ui()

func set_lsystem_solo(index: int, solo: bool) -> void:
	if index < 0 or index >= lsystems.size():
		return

	solo_voice_index = index if solo else -1

	for voice_index in range(lsystems.size()):
		voice_mute_states[voice_index] = solo and voice_index != index

	_refresh_lsystems_ui()

func change_lsystem_preview_direction(index: int, delta: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	_ensure_lsystem_preview_start_state(index)

	var direction_index := int(lsystem_preview_node_direction_indices.get(index, 5))
	lsystem_preview_node_direction_indices[index] = posmod(
		direction_index - delta,
		TonnetzBuilder.AXIAL_DIRECTIONS.size()
	)

	var edge := int(lsystem_preview_triangle_edges.get(index, 0))
	lsystem_preview_triangle_edges[index] = posmod(edge + delta, 3)

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

##################################################
########## LSYSTEM DISPLAY LABELS #############
##################################################
func _build_lsystem_info() -> Array:
	var info: Array = []

	for index in range(lsystems.size()):
		var lsystem_info := {}
		lsystem_info["display_number"] = int(voice_display_numbers.get(index, index + 1))
		lsystem_info["muted"] = bool(voice_mute_states.get(index, false))
		lsystem_info["solo"] = index == solo_voice_index
		lsystem_info["start_label"] = voice_start_labels.get(index, "Not scheduled")
		lsystem_info["node_direction_index"] = lsystem_preview_node_direction_indices.get(index, 5)
		lsystem_info["triangle_edge"] = lsystem_preview_triangle_edges.get(index, 0)
		if lsystems[index] is LSystem:
			lsystem_info["origin_label"] = lsystem_playback_origin_labels.get(index, "Not set")
		if voice_fitness_values.has(index):
			lsystem_info["fitness"] = voice_fitness_values[index]
		info.append(lsystem_info)

	return info

func _set_lsystem_playback_start(
	index: int,
	origin,
	initial_dir: Vector2i,
	initial_edge: int
) -> void:
	if index < 0 or index >= lsystems.size():
		return

	lsystem_playback_origins[index] = origin
	lsystem_playback_origin_labels[index] = _describe_anchor(origin)
	lsystem_playback_initial_dirs[index] = initial_dir
	lsystem_playback_initial_edges[index] = initial_edge

func _ensure_lsystem_preview_start_state(index: int) -> void:
	if not lsystem_preview_node_direction_indices.has(index):
		lsystem_preview_node_direction_indices[index] = 5

	if not lsystem_preview_triangle_edges.has(index):
		lsystem_preview_triangle_edges[index] = 0

func _set_lsystem_preview_start_state(index: int, initial_dir: Vector2i, initial_edge: int) -> void:
	if index < 0 or index >= lsystems.size():
		return

	var direction_index := TonnetzBuilder.AXIAL_DIRECTIONS.find(initial_dir)

	if direction_index != -1:
		lsystem_preview_node_direction_indices[index] = direction_index

	lsystem_preview_triangle_edges[index] = posmod(initial_edge, 3)

func _set_lsystem_start_beat(index: int, start_beat: float) -> void:
	if index < 0 or index >= lsystems.size():
		return

	voice_start_labels[index] = _format_beat_label(start_beat)

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
func _clear_playing_voices(_start_pos: Vector2) -> void:
	lsystem_playback.clear_all()

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

func _shift_lsystem_index_mapping_after_insert(mapping: Dictionary, inserted_index: int) -> void:
	var shifted_mapping := {}

	for mapping_index in mapping.keys():
		var new_index = int(mapping_index)

		if new_index >= inserted_index:
			new_index += 1

		shifted_mapping[new_index] = mapping[mapping_index]

	mapping.clear()

	for mapping_index in shifted_mapping.keys():
		mapping[mapping_index] = shifted_mapping[mapping_index]

func _stop_all_lsystem_voices() -> void:
	lsystem_playback.stop_all()

func _on_stop_all_lsystems_requested() -> void:
	_stop_all_lsystem_voices()
	_refresh_lsystems_ui()

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
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		var click_pos = _get_tonnetz_world_mouse_position()
		if click_pos == null:
			if not event.pressed:
				lsystem_spawn_origin_anchor = null
			return

		if walk_recorder.is_recording() and event.pressed:
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
	var current_system = _get_lsystem(current_lsystem_index)

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
		_set_lsystem_playback_start(current_lsystem_index, origin_anchor, initial_dir, initial_edge)

		if _play_lsystem_from_origin(current_lsystem_index, origin_anchor, initial_dir, initial_edge, start_beat):
			_start_clock_from_lsystem_click()
			_refresh_lsystems_ui()

func _begin_lsystem_spawn_drag(click_pos: Vector2) -> void:
	if not _is_lsystem_voice(current_lsystem_index):
		return

	lsystem_spawn_origin_anchor = builder.get_nearest_spawn_anchor(click_pos)

func _get_random_lsystem_start_state(origin) -> Dictionary:
	_ensure_lsystem_preview_start_state(current_lsystem_index)

	if origin is TonnetzNode:
		return {
			"initial_dir": TonnetzBuilder.AXIAL_DIRECTIONS[
				int(lsystem_preview_node_direction_indices.get(current_lsystem_index, 5))
			],
			"initial_edge": 0
		}

	if origin is TriangleArea:
		return {
			"initial_dir": Vector2i(1, 0),
			"initial_edge": int(lsystem_preview_triangle_edges.get(current_lsystem_index, 0))
		}

	return {}

func _get_random_node_start_direction() -> Vector2i:
	var direction_index := randi_range(0, TonnetzBuilder.AXIAL_DIRECTIONS.size() - 1)
	return TonnetzBuilder.AXIAL_DIRECTIONS[direction_index]

func _on_tonnetz_clicked(click_pos: Vector2) -> void:
	if walk_recorder.is_recording():
		_handle_walk_recording_click(click_pos)
		return

	_begin_lsystem_spawn_drag(click_pos)


##################################################
########## ACTIVE LSYSTEM ASSIGNMENT #############
##################################################
func set_lsystem(new_lsystem) -> void:
	lsystem = new_lsystem

	if current_lsystem_index >= 0 and current_lsystem_index < lsystems.size():
		lsystems[current_lsystem_index] = new_lsystem
