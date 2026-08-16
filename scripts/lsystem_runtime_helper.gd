class_name LSystemRuntimeHelper
extends RefCounted

#play and repeat L-systems

const EXPLORE_ACTION_BUFFER_BEATS := 4.0

var config: TonnetzConfig
var interpreter
var sequencer: Sequencer
var tonnetz_world: Node2D
var turtle_scene: PackedScene

var voice_turtles := {}
var lsystem_visuals := {}
var voice_ids := {}
var explore_repeat_counts := {}
var origins := {}
var origin_labels := {}
var initial_dirs := {}
var initial_edges := {}
var start_beats := {}

func _init(
	new_config: TonnetzConfig,
	new_interpreter,
	new_sequencer: Sequencer,
	new_tonnetz_world: Node2D,
	new_turtle_scene: PackedScene
) -> void:
	config = new_config
	interpreter = new_interpreter
	sequencer = new_sequencer
	tonnetz_world = new_tonnetz_world
	turtle_scene = new_turtle_scene

func play(
	index: int,
	system: LSystem,
	origin,
	initial_dir: Vector2i,
	initial_edge: int,
	start_beat: float
) -> int:
	if system == null or origin == null or not origin.has_method("get_center"):
		return -1

	stop_voice(index)

	var start_pos = origin.get_center()
	var voice_turtle = _get_turtle(index, start_pos, system.color)

	if voice_turtle == null:
		return -1

	var actions = interpreter.set_actions(
		system.generated_string,
		origin,
		-1.0,
		1,
		true,
		initial_dir,
		initial_edge
	)

	if actions.size() < 2:
		push_warning("Generated L-system is not playable because it produced fewer than two actions.")
		return -1

	var voice_id = sequencer.add_voice(
		actions,
		start_beat,
		system.volume
	)

	if voice_id == -1:
		push_warning("Sequencer rejected generated L-system voice.")
		return -1

	voice_turtles[voice_id] = voice_turtle
	voice_ids[index] = voice_id
	explore_repeat_counts[voice_id] = 1
	voice_turtle.clear_path(start_pos)
	voice_turtle.set_voice_color(system.color)
	return voice_id

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
	if system == null:
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

func remove_visual(index: int) -> void:
	if not lsystem_visuals.has(index):
		return

	var removed_visual = lsystem_visuals[index]
	lsystem_visuals.erase(index)
	_free_visual_entry(removed_visual)

func shift_after_removal(removed_index: int) -> void:
	_shift_index_mapping(lsystem_visuals, removed_index)
	_shift_index_mapping(voice_ids, removed_index)
	_shift_index_mapping(origins, removed_index)
	_shift_index_mapping(origin_labels, removed_index)
	_shift_index_mapping(initial_dirs, removed_index)
	_shift_index_mapping(initial_edges, removed_index)
	_shift_index_mapping(start_beats, removed_index)

func shift_after_insert(inserted_index: int) -> void:
	_shift_index_mapping_after_insert(lsystem_visuals, inserted_index)
	_shift_index_mapping_after_insert(voice_ids, inserted_index)
	_shift_index_mapping_after_insert(origins, inserted_index)
	_shift_index_mapping_after_insert(origin_labels, inserted_index)
	_shift_index_mapping_after_insert(initial_dirs, inserted_index)
	_shift_index_mapping_after_insert(initial_edges, inserted_index)
	_shift_index_mapping_after_insert(start_beats, inserted_index)

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

func erase_explore_voice(voice_id: int) -> void:
	explore_repeat_counts.erase(voice_id)

func set_start(index: int, origin, origin_label: String, initial_dir: Vector2i, initial_edge: int) -> void:
	origins[index] = origin
	origin_labels[index] = origin_label
	initial_dirs[index] = initial_dir
	initial_edges[index] = initial_edge

func get_origin(index: int):
	return origins.get(index)

func get_origin_label(index: int) -> String:
	return str(origin_labels.get(index, "Not set"))

func get_initial_dir(index: int) -> Vector2i:
	return initial_dirs.get(index, Vector2i(1, 0))

func get_initial_edge(index: int) -> int:
	return int(initial_edges.get(index, 0))

func set_start_beat(index: int, start_beat: float) -> void:
	start_beats[index] = start_beat

func get_start_beat(index: int) -> float:
	return float(start_beats.get(index, -1.0))

func get_first_start_beat(indices: Array = [], lsystem_count: int = 0) -> float:
	var first_start_beat := -1.0
	var export_indices := indices

	if export_indices.is_empty():
		export_indices = range(lsystem_count)

	for index in export_indices:
		var start_beat := get_start_beat(index)

		if start_beat >= 0.0 and (first_start_beat < 0.0 or start_beat < first_start_beat):
			first_start_beat = start_beat

	return first_start_beat

func _get_turtle(index: int, start_pos: Vector2, color: Color) -> Turtle:
	var existing_turtle = lsystem_visuals.get(index)

	if is_instance_valid(existing_turtle) and existing_turtle.has_method("clear_path"):
		existing_turtle.clear_path(start_pos)
		existing_turtle.set_voice_color(color)
		return existing_turtle

	if is_instance_valid(existing_turtle):
		remove_visual(index)

	var new_turtle = _create_turtle(start_pos, color)
	lsystem_visuals[index] = new_turtle
	return new_turtle

func _create_turtle(
	start_pos: Vector2,
	color: Color,
	add_start_dot: bool = true
) -> Turtle:
	var new_turtle: Turtle
	new_turtle = turtle_scene.instantiate() as Turtle

	if new_turtle == null:
		push_error("scenes/Turtle.tscn must use scripts/turtle.gd for multi-voice playback.")
		return null

	tonnetz_world.add_child(new_turtle)
	new_turtle.global_position = start_pos
	new_turtle.clear_path(start_pos, add_start_dot)
	new_turtle.set_voice_color(color)
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

func _shift_index_mapping_after_insert(mapping: Dictionary, inserted_index: int) -> void:
	var shifted_mapping := {}

	for mapping_index in mapping.keys():
		var new_index = int(mapping_index)

		if new_index >= inserted_index:
			new_index += 1

		shifted_mapping[new_index] = mapping[mapping_index]

	mapping.clear()

	for mapping_index in shifted_mapping.keys():
		mapping[mapping_index] = shifted_mapping[mapping_index]
