class_name LSystemPlayback
extends RefCounted

const EXPLORE_ACTION_BUFFER_BEATS := 4.0

var config: TonnetzConfig
var interpreter
var sequencer: Sequencer
var tonnetz_world: Node2D
var turtle_scene: PackedScene
var fallback_turtle: Turtle

var voice_turtles := {}
var lsystem_visuals := {}
var voice_ids := {}
var explore_repeat_counts := {}

func _init(
	new_config: TonnetzConfig,
	new_interpreter,
	new_sequencer: Sequencer,
	new_tonnetz_world: Node2D,
	new_turtle_scene: PackedScene,
	new_fallback_turtle: Turtle
) -> void:
	config = new_config
	interpreter = new_interpreter
	sequencer = new_sequencer
	tonnetz_world = new_tonnetz_world
	turtle_scene = new_turtle_scene
	fallback_turtle = new_fallback_turtle

func play(
	index: int,
	system: LSystem,
	origin,
	initial_dir: Vector2i,
	initial_edge: int,
	start_beat: float,
	beats_per_bar: int
) -> int:
	if system == null or origin == null or not origin.has_method("get_center"):
		return -1

	stop_voice(index)

	var start_pos = origin.get_center()
	var voice_turtle = _get_turtle(index, start_pos, system.color)
	var explore_mode = system.playback_mode == "explore"
	var actions = interpreter.set_actions(
		system.generated_string,
		origin,
		-1.0,
		1,
		explore_mode,
		initial_dir,
		initial_edge
	)

	if actions.size() < 2:
		push_warning("Generated L-system is not playable because it produced fewer than two actions.")
		return -1

	var voice_id = sequencer.add_voice(
		actions,
		start_beat,
		system.volume,
		system.reverb,
		system.distortion,
		not explore_mode
	)

	if voice_id == -1:
		push_warning("Sequencer rejected generated L-system voice.")
		return -1

	voice_turtles[voice_id] = voice_turtle
	voice_ids[index] = voice_id
	if explore_mode:
		explore_repeat_counts[voice_id] = 1
	voice_turtle.clear_path(start_pos)
	voice_turtle.set_voice_color(system.color)
	voice_turtle.set_visual_radius_offset(0.0)
	return voice_id

func register_score_voice(
	index: int,
	voice_id: int,
	voice_turtle: Turtle,
	explore_mode: bool
) -> void:
	voice_turtles[voice_id] = voice_turtle
	voice_ids[index] = voice_id
	if explore_mode:
		explore_repeat_counts[voice_id] = 1

func needs_explore_extension(voice_id: int, current_beat: float) -> bool:
	if not explore_repeat_counts.has(voice_id):
		return false

	var voice = sequencer.get_voice(voice_id)

	if voice.is_empty() or not bool(voice.get("active", true)):
		explore_repeat_counts.erase(voice_id)
		return false

	var remaining = (
		float(voice.get("start_beat", 0.0))
		+ float(voice.get("loop_length", 0.0))
		- current_beat
	)
	return remaining <= EXPLORE_ACTION_BUFFER_BEATS

func get_explore_voice_ids() -> Array:
	return explore_repeat_counts.keys()

func append_explore_loop(
	index: int,
	system: LSystem,
	origin,
	initial_dir: Vector2i,
	initial_edge: int,
	voice_id: int
) -> bool:
	if system == null or system.playback_mode != "explore":
		return false

	if origin == null or not origin.has_method("get_center"):
		return false

	var next_repeat_count = int(explore_repeat_counts.get(voice_id, 1)) + 1
	var actions = interpreter.set_actions(
		system.generated_string,
		origin,
		-1.0,
		next_repeat_count,
		true,
		initial_dir,
		initial_edge
	)

	if actions.size() <= sequencer.get_voice(voice_id).get("score", []).size():
		return false

	if not sequencer.replace_voice_score(voice_id, actions):
		return false

	explore_repeat_counts[voice_id] = next_repeat_count
	return true

func update_explore_repeat_count(voice_id: int) -> void:
	explore_repeat_counts[voice_id] = int(explore_repeat_counts.get(voice_id, 1)) + 1

func stop_voice(index: int) -> void:
	if not voice_ids.has(index):
		_stop_visuals(index)
		return

	var voice_id = voice_ids[index]
	sequencer.remove_voice(voice_id)
	voice_turtles.erase(voice_id)
	explore_repeat_counts.erase(voice_id)
	voice_ids.erase(index)
	_stop_visuals(index)

func request_stop_voice(index: int) -> void:
	if not voice_ids.has(index):
		_stop_visuals(index)
		return

	sequencer.request_stop_voice(voice_ids[index])

func stop_all() -> void:
	sequencer.clear_voices()
	voice_turtles.clear()
	voice_ids.clear()
	explore_repeat_counts.clear()

	for voice_turtle in lsystem_visuals.values():
		if is_instance_valid(voice_turtle) and voice_turtle.has_method("stop_after_current_target"):
			voice_turtle.stop_after_current_target()

func clear_all() -> void:
	for voice_id in voice_turtles:
		var old_turtle = voice_turtles[voice_id]

		if is_instance_valid(old_turtle):
			old_turtle.queue_free()

	for visual_entry in lsystem_visuals.values():
		_free_visual_entry(visual_entry)

	voice_turtles.clear()
	lsystem_visuals.clear()
	voice_ids.clear()
	explore_repeat_counts.clear()

func remove_visual(index: int) -> void:
	if not lsystem_visuals.has(index):
		return

	var removed_visual = lsystem_visuals[index]
	lsystem_visuals.erase(index)
	_free_visual_entry(removed_visual)

func shift_after_removal(removed_index: int) -> void:
	_shift_index_mapping(lsystem_visuals, removed_index)
	_shift_index_mapping(voice_ids, removed_index)

func has_voice(index: int) -> bool:
	return voice_ids.has(index)

func get_voice_id(index: int) -> int:
	return int(voice_ids.get(index, -1))

func get_turtle_for_voice(voice_id: int):
	return voice_turtles.get(voice_id)

func get_index_for_voice(voice_id: int) -> int:
	for lsystem_index in voice_ids:
		if int(voice_ids[lsystem_index]) == voice_id:
			return lsystem_index

	return -1

func get_turtle_for_index(index: int, start_pos: Vector2, color: Color) -> Turtle:
	return _get_turtle(index, start_pos, color)

func erase_explore_voice(voice_id: int) -> void:
	explore_repeat_counts.erase(voice_id)

func _get_turtle(index: int, start_pos: Vector2, color: Color) -> Turtle:
	var existing_turtle = lsystem_visuals.get(index)

	if is_instance_valid(existing_turtle) and existing_turtle.has_method("clear_path"):
		existing_turtle.clear_path(start_pos)
		existing_turtle.set_voice_color(color)
		existing_turtle.set_visual_radius_offset(0.0)
		return existing_turtle

	if is_instance_valid(existing_turtle):
		remove_visual(index)

	var new_turtle = _create_turtle(start_pos, color)
	lsystem_visuals[index] = new_turtle
	return new_turtle

func _create_turtle(
	start_pos: Vector2,
	color: Color,
	add_start_dot: bool = true,
	show_visual: bool = true
) -> Turtle:
	var new_turtle: Turtle
	new_turtle = turtle_scene.instantiate() as Turtle

	if new_turtle == null:
		push_error("Turtle.tscn must use scripts/turtle.gd for multi-voice playback.")
		return fallback_turtle

	tonnetz_world.add_child(new_turtle)
	new_turtle.global_position = start_pos
	new_turtle.clear_path(start_pos, add_start_dot, show_visual)
	new_turtle.set_voice_color(color)
	new_turtle.set_visual_radius_offset(0.0)
	return new_turtle

func _stop_visuals(index: int) -> void:
	var stored_turtles = lsystem_visuals.get(index)

	if is_instance_valid(stored_turtles) and stored_turtles.has_method("stop_after_current_target"):
		stored_turtles.stop_after_current_target()

func _free_visual_entry(visual_entry) -> void:
	if is_instance_valid(visual_entry):
		visual_entry.queue_free()

func _shift_index_mapping(mapping: Dictionary, removed_index: int) -> void:
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
