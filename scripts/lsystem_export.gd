class_name LSystemExport
extends RefCounted

#imports and exports L-systems as json files

static func export_file(
	path: String,
	lsystems: Array,
	voice_display_numbers: Dictionary,
	voice_mute_states: Dictionary,
	lsystem_playback: LSystemRuntimeHelper,
	bpm: int,
	indices: Array = []
) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		return {
			"ok": false,
			"message": "L-system export failed: %s" % error_string(FileAccess.get_open_error())
		}

	file.store_string(JSON.stringify(
		_build_lsystems_export_data(
			lsystems,
			voice_display_numbers,
			voice_mute_states,
			lsystem_playback,
			bpm,
			indices
		),
		"\t"
	))
	file.close()
	return {
		"ok": true,
		"message": "L-system export complete: %s" % path
	}

static func import_file(path: String, builder: TonnetzBuilder) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		return {
			"ok": false,
			"message": "L-system import failed: %s" % error_string(FileAccess.get_open_error())
		}

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if not (parsed is Dictionary) or not parsed.has("lsystems"):
		return {
			"ok": false,
			"message": "L-system import failed: invalid JSON structure."
		}

	var imported_entries := []

	for entry in parsed["lsystems"]:
		if not (entry is Dictionary):
			continue

		var imported_entry := _parse_lsystem_entry(entry, builder)
		if not imported_entry.is_empty():
			imported_entries.append(imported_entry)

	return {
		"ok": true,
		"entries": imported_entries,
		"message": "Imported %d L-systems from %s" % [imported_entries.size(), path]
	}

static func _parse_lsystem_entry(entry: Dictionary, builder: TonnetzBuilder) -> Dictionary:
	if not entry.has("axiom") or not entry.has("rules"):
		return {}

	var iterations := int(entry.get("iterations", LSystemFactory.DEFAULT_ITERATIONS))
	var rules: Dictionary = entry["rules"]
	var generated_string := str(entry.get(
		"generated_string",
		LSystem.generate_string(str(entry["axiom"]), rules, iterations)
	))
	var imported_system := LSystem.new(
		str(entry["axiom"]),
		rules,
		generated_string,
		iterations
	)
	imported_system.set_volume(float(entry.get("volume", 0.8)))

	var has_color := entry.has("color")
	if has_color:
		imported_system.color = Color.html(str(entry["color"]))

	var start_data := {}
	if entry.has("start") and entry["start"] is Dictionary:
		start_data = _parse_lsystem_start(entry["start"], builder)

	return {
		"system": imported_system,
		"muted": bool(entry.get("muted", false)),
		"has_color": has_color,
		"start": start_data
	}

static func _parse_lsystem_start(start_data: Dictionary, builder: TonnetzBuilder) -> Dictionary:
	return {
		"origin": _get_anchor_from_export_data(start_data.get("origin", {}), builder),
		"initial_dir": _get_vector2i_from_export_data(
			start_data.get("initial_direction", {}),
			Vector2i(1, 0)
		),
		"initial_edge": int(start_data.get("initial_edge", 0)),
		"start_beat": float(start_data.get("start_beat", -1.0))
	}

static func _build_lsystems_export_data(
	lsystems: Array,
	voice_display_numbers: Dictionary,
	voice_mute_states: Dictionary,
	lsystem_playback: LSystemRuntimeHelper,
	bpm: int,
	indices: Array = []
) -> Dictionary:
	var exported_lsystems := []
	var export_indices := indices
	var first_start_beat := lsystem_playback.get_first_start_beat(
		export_indices,
		lsystems.size()
	)

	if export_indices.is_empty():
		export_indices = range(lsystems.size())

	for index in export_indices:
		var system: LSystem = lsystems[index]
		exported_lsystems.append({
			"index": index,
			"display_number": int(voice_display_numbers.get(index, index + 1)),
			"axiom": system.axiom,
			"rules": system.rules,
			"iterations": system.iterations,
			"generated_string": system.generated_string,
			"volume": system.volume,
			"muted": bool(voice_mute_states.get(index, false)),
			"color": system.color.to_html(true),
			"start": _build_lsystem_start_export_data(index, first_start_beat, lsystem_playback)
		})

	return {
		"exported_at": Time.get_datetime_string_from_system(false, true),
		"bpm": bpm,
		"lsystems": exported_lsystems
	}

static func _build_lsystem_start_export_data(
	index: int,
	first_start_beat: float,
	lsystem_playback: LSystemRuntimeHelper
) -> Dictionary:
	var initial_dir: Vector2i = lsystem_playback.get_initial_dir(index)
	var start_beat := lsystem_playback.get_start_beat(index)

	if first_start_beat >= 0.0 and start_beat >= 0.0:
		start_beat = max(0.0, start_beat - first_start_beat)

	return {
		"origin": _build_anchor_export_data(lsystem_playback.get_origin(index)),
		"initial_direction": {
			"x": initial_dir.x,
			"y": initial_dir.y
		},
		"initial_edge": lsystem_playback.get_initial_edge(index),
		"start_beat": start_beat
	}

static func _build_anchor_export_data(anchor) -> Dictionary:
	if anchor is TonnetzNode:
		return {
			"type": "node",
			"coord": _vector2i_to_export_dict(Vector2i(anchor.q, anchor.r)),
			"label": _describe_anchor(anchor)
		}

	if anchor is TonnetzTriangle:
		var coords := []

		for coord in anchor.get_node_coords():
			coords.append(_vector2i_to_export_dict(coord))

		return {
			"type": "triangle",
			"orientation": int(anchor.orientation),
			"node_coords": coords,
			"label": _describe_anchor(anchor)
		}

	return {
		"type": "none",
		"label": "Not set"
	}

static func _get_anchor_from_export_data(anchor_data, builder: TonnetzBuilder):
	if not (anchor_data is Dictionary):
		return null

	if anchor_data.get("type", "") == "node":
		var coord := _get_vector2i_from_export_data(anchor_data.get("coord", {}), Vector2i.ZERO)
		return builder.nodes.get(builder.get_wrapped_coord(coord))

	if anchor_data.get("type", "") == "triangle":
		var wanted_key := _get_triangle_export_key(anchor_data.get("node_coords", []), builder)
		var wanted_orientation := int(anchor_data.get("orientation", -1))

		for triangle in builder.triangles:
			if wanted_orientation != -1 and int(triangle.orientation) != wanted_orientation:
				continue

			if _get_triangle_export_key(triangle.get_node_coords(), builder) == wanted_key:
				return triangle

	return null

static func _get_triangle_export_key(coords, builder: TonnetzBuilder) -> String:
	var parts := []

	for coord_data in coords:
		var coord := Vector2i.ZERO
		if coord_data is Vector2i:
			coord = coord_data
		else:
			coord = _get_vector2i_from_export_data(coord_data, Vector2i.ZERO)
		coord = builder.get_wrapped_coord(coord)
		parts.append("%d:%d" % [coord.x, coord.y])

	parts.sort()
	return "|".join(parts)

static func _describe_anchor(anchor) -> String:
	if anchor is TonnetzNode:
		return "Node %s%d" % [anchor.note_name, int(anchor.octave)]

	if anchor is TonnetzTriangle:
		var note_names: Array[String] = []

		for node in anchor.nodes:
			if node is TonnetzNode:
				note_names.append("%s%d" % [node.note_name, int(node.octave)])

		return "Triangle %s" % "-".join(note_names)

	return "Not set"

static func _vector2i_to_export_dict(value: Vector2i) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y
	}

static func _get_vector2i_from_export_data(value, default_value: Vector2i) -> Vector2i:
	if not (value is Dictionary):
		return default_value

	return Vector2i(
		int(value.get("x", default_value.x)),
		int(value.get("y", default_value.y))
	)
