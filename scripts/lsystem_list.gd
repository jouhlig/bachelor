class_name LSystemList
extends RefCounted

# manages the L-system list and its UI state

var config: TonnetzConfig
var playback: LSystemRuntimeHelper

var systems: Array = []
var current_index := -1
var available_colors: Array[Color] = []
var mute_states := {}
var fitness_values := {}
var preview_node_direction_indices := {}
var preview_triangle_edges := {}
var start_labels := {}
var display_numbers := {}
var next_display_number := 1
var solo_index := -1

func _init(new_config: TonnetzConfig, new_playback: LSystemRuntimeHelper) -> void:
	config = new_config
	playback = new_playback
	available_colors = config.VOICE_COLORS.duplicate()
	available_colors.shuffle()

func add_random() -> int:
	var system := LSystemFactory.random(config)
	_configure_system(system)
	return add_system(system, false)

func add_system(system: LSystem, muted: bool) -> int:
	var index: int = systems.size()
	systems.insert(index, system)
	playback.shift_after_insert(index)
	_shift_index_mapping_after_insert(mute_states, index)
	_shift_index_mapping_after_insert(fitness_values, index)
	_shift_index_mapping_after_insert(preview_node_direction_indices, index)
	_shift_index_mapping_after_insert(preview_triangle_edges, index)
	_shift_index_mapping_after_insert(start_labels, index)
	_shift_index_mapping_after_insert(display_numbers, index)
	mute_states[index] = muted
	display_numbers[index] = next_display_number
	next_display_number += 1
	_ensure_preview_start_state(index)
	current_index = index
	return index

func select(index: int) -> bool:
	if not has_index(index):
		return false

	current_index = index
	return true

func randomize(index: int) -> bool:
	var system = get_system(index)
	if not (system is LSystem):
		return false

	system.randomize(config)
	fitness_values.erase(index)
	current_index = index
	return true

func duplicate(index: int) -> int:
	var system = get_system(index)
	if system == null or not system.has_method("duplicate_system"):
		return -1

	var duplicate_system = system.duplicate_system()
	duplicate_system.color = get_next_color()
	var duplicate_index := add_system(
		duplicate_system,
		bool(mute_states.get(index, false))
	)
	preview_node_direction_indices[duplicate_index] = preview_node_direction_indices.get(index, 5)
	preview_triangle_edges[duplicate_index] = preview_triangle_edges.get(index, 0)
	if fitness_values.has(index):
		fitness_values[duplicate_index] = fitness_values[index]
	return duplicate_index

func remove(index: int) -> bool:
	if not has_index(index):
		return false

	return_color(systems[index].color)
	playback.stop_voice(index)
	playback.remove_visual(index)
	systems.remove_at(index)
	playback.shift_after_removal(index)
	_shift_index_mapping(mute_states, index)
	_shift_index_mapping(fitness_values, index)
	_shift_index_mapping(preview_node_direction_indices, index)
	_shift_index_mapping(preview_triangle_edges, index)
	_shift_index_mapping(start_labels, index)
	_shift_index_mapping(display_numbers, index)

	if solo_index == index:
		solo_index = -1
	elif solo_index > index:
		solo_index -= 1

	if systems.is_empty():
		current_index = -1
		return true

	if current_index > index:
		current_index -= 1
	elif current_index >= systems.size():
		current_index = systems.size() - 1

	return true

func set_axiom(index: int, new_axiom: String) -> bool:
	var system = get_system(index)
	if not (system is LSystem) or new_axiom.is_empty():
		return false

	system.set_axiom(new_axiom)
	fitness_values.erase(index)
	current_index = index
	return true

func set_iterations(index: int, iterations: int) -> bool:
	var system = get_system(index)
	if not (system is LSystem):
		return false

	system.set_iterations(iterations)
	fitness_values.erase(index)
	current_index = index
	return true

func set_rule(index: int, symbol: String, production: String) -> bool:
	var system = get_system(index)
	if not (system is LSystem):
		return false

	system.set_rule(symbol, production)
	fitness_values.erase(index)
	current_index = index
	return true

func set_volume(index: int, volume: float) -> bool:
	var system = get_system(index)
	if not (system is LSystem):
		return false

	system.set_volume(volume)
	return true

func set_muted(index: int, muted: bool) -> bool:
	if not has_index(index):
		return false

	mute_states[index] = muted
	return true

func set_all_muted(muted: bool) -> void:
	solo_index = -1

	for index in range(systems.size()):
		mute_states[index] = muted

func set_solo(index: int, solo: bool) -> bool:
	if not has_index(index):
		return false

	solo_index = index if solo else -1

	for voice_index in range(systems.size()):
		mute_states[voice_index] = solo and voice_index != index

	return true

func change_preview_direction(index: int, delta: int) -> bool:
	if not has_index(index):
		return false

	_ensure_preview_start_state(index)

	var direction_index := int(preview_node_direction_indices.get(index, 5))
	preview_node_direction_indices[index] = posmod(
		direction_index - delta,
		TonnetzBuilder.AXIAL_DIRECTIONS.size()
	)

	var edge := int(preview_triangle_edges.get(index, 0))
	preview_triangle_edges[index] = posmod(edge + delta, 3)
	return true

func set_preview_start_state(index: int, initial_dir: Vector2i, initial_edge: int) -> void:
	if not has_index(index):
		return

	var direction_index := TonnetzBuilder.AXIAL_DIRECTIONS.find(initial_dir)
	if direction_index != -1:
		preview_node_direction_indices[index] = direction_index

	preview_triangle_edges[index] = posmod(initial_edge, 3)

func set_start_label(index: int, label: String) -> void:
	if has_index(index):
		start_labels[index] = label

func set_fitness(index: int, fitness: float) -> void:
	if has_index(index):
		fitness_values[index] = fitness

func get_system(index: int):
	if not has_index(index):
		return null

	return systems[index]

func get_current_system():
	return get_system(current_index)

func has_index(index: int) -> bool:
	return index >= 0 and index < systems.size()

func is_lsystem(index: int) -> bool:
	return get_system(index) is LSystem

func get_color(index: int) -> Color:
	var system = get_system(index)
	return system.color if system else Color.WHITE

func get_volume(index: int) -> float:
	var system = get_system(index)
	return system.volume if system else 0.8

func get_colors() -> Array:
	var colors := []

	for index in range(systems.size()):
		colors.append(get_color(index))

	return colors

func get_volumes() -> Array:
	var volumes := []

	for index in range(systems.size()):
		volumes.append(get_volume(index))

	return volumes

func get_info() -> Array:
	var info: Array = []

	for index in range(systems.size()):
		var lsystem_info := {}
		lsystem_info["display_number"] = int(display_numbers.get(index, index + 1))
		lsystem_info["muted"] = bool(mute_states.get(index, false))
		lsystem_info["solo"] = index == solo_index
		lsystem_info["start_label"] = start_labels.get(index, "Not scheduled")
		lsystem_info["node_direction_index"] = preview_node_direction_indices.get(index, 5)
		lsystem_info["triangle_edge"] = preview_triangle_edges.get(index, 0)
		if systems[index] is LSystem:
			lsystem_info["origin_label"] = playback.get_origin_label(index)
		if fitness_values.has(index):
			lsystem_info["fitness"] = fitness_values[index]
		info.append(lsystem_info)

	return info

func take_color(color: Color) -> void:
	available_colors.erase(color)

func assign_next_color(system: LSystem) -> void:
	system.color = get_next_color()

func get_next_color() -> Color:
	if available_colors.is_empty():
		return Color.WHITE

	return available_colors.pop_front()

func return_color(color: Color) -> void:
	if color == Color.WHITE or available_colors.has(color):
		return

	available_colors.append(color)

func _configure_system(system: LSystem) -> void:
	system.color = get_next_color()
	system.set_volume(system.volume)

func _ensure_preview_start_state(index: int) -> void:
	if not preview_node_direction_indices.has(index):
		preview_node_direction_indices[index] = 5

	if not preview_triangle_edges.has(index):
		preview_triangle_edges[index] = 0

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
