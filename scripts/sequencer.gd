extends Node
class_name Sequencer

signal transition_started(voice_id, current_event, next_event)
signal note_entered(voice_id, event)
signal event_entered(voice_id, event)
signal state_changed(voice_id, event)
signal voice_paused(voice_id, event)
signal voice_reentered(voice_id, event)

var voices: Array = []
var loop := true

var next_voice_id := 0

func add_voice(
	score: Array,
	start_beat: float = -1.0,
	volume: float = 0.8,
	loop_voice: bool = true
) -> int:
	if score.size() < 2:
		return -1

	if start_beat < 0.0:
		start_beat = CL.get_time_beat()

	var voice_id := next_voice_id
	next_voice_id += 1

	var voice = {
		"id": voice_id,
		"score": score.duplicate(true),
		"index": 0,
		"loop_length": _get_score_loop_length(score),
		"start_beat": start_beat,
		"loop_index": -1,
		"last_transition_index": -1,
		"last_clock_beat": start_beat,
		"stop_requested": false,
		"stop_target_index": -1,
		"volume": clamp(volume, 0.0, 1.0),
		"loop": loop_voice,
		"active": true
	}

	voices.append(voice)
	return voice_id

func clear_voices() -> void:
	voices.clear()

func set_voice_volume(voice_id: int, volume: float) -> void:
	for voice in voices:
		if voice["id"] == voice_id:
			voice["volume"] = clamp(volume, 0.0, 1.0)
			return

func replace_voice_score(voice_id: int, score: Array) -> bool:
	if score.size() < 2:
		return false

	for voice in voices:
		if voice["id"] == voice_id:
			voice["score"] = score.duplicate(true)
			voice["loop_length"] = _get_score_loop_length(score)
			voice["index"] = min(int(voice["index"]), score.size() - 1)
			return true

	return false

func get_voice(voice_id: int) -> Dictionary:
	for voice in voices:
		if voice["id"] == voice_id:
			return voice

	return {}

func stop_voice(voice_id: int) -> void:
	for voice in voices:
		if voice["id"] == voice_id:
			voice["active"] = false
			voice["stop_requested"] = false
			voice["stop_target_index"] = -1
			return

func remove_voice(voice_id: int) -> void:
	for index in range(voices.size() - 1, -1, -1):
		if voices[index]["id"] == voice_id:
			voices.remove_at(index)
			return

func request_stop_voice(voice_id: int) -> void:
	for voice in voices:
		if voice["id"] == voice_id:
			if not voice.get("active", true):
				return

			var next_index = min(
				int(voice["index"]) + 1,
				voice["score"].size() - 1
			)

			voice["stop_requested"] = true
			voice["stop_target_index"] = next_index
			return

func resume_voice(voice_id: int, start_beat: float = -1.0) -> bool:
	for voice in voices:
		if voice["id"] != voice_id:
			continue

		if start_beat < 0.0:
			start_beat = CL.get_time_beat()

		if voice.get("active", true):
			if voice.get("stop_requested", false):
				voice["stop_requested"] = false
				voice["stop_target_index"] = -1
				return true

			return false

		var score = voice["score"]
		var index = int(voice["index"])

		if index >= score.size():
			index = 0
			voice["index"] = index

		voice["start_beat"] = (
			start_beat
			- _get_event_local_start(score, index)
		)
		voice["loop_index"] = 0
		voice["last_transition_index"] = -1
		voice["last_clock_beat"] = start_beat
		voice["stop_requested"] = false
		voice["stop_target_index"] = -1
		voice["active"] = true

		return true

	return false

func _process(delta: float) -> void:
	if voices.is_empty():
		return

	var beat = CL.get_time_beat()

	for v in voices:
		if v.get("active", true):
			_advance_voice(v, beat)

func seek_to_beat(beat: float) -> void:
	for v in voices:
		v["active"] = true
		v["stop_requested"] = false
		v["stop_target_index"] = -1
		_advance_voice(v, beat, true, true)

func _advance_voice(
	v: Dictionary,
	beat: float,
	force_reentry: bool = false,
	emit_reentry_event: bool = false
) -> void:
	var score = v["score"]
	if score.size() < 2:
		return

	var loop_length = v["loop_length"]
	if loop_length <= 0.0:
		return

	var elapsed = beat - v["start_beat"]
	if elapsed < 0.0:
		v["index"] = 0
		v["loop_index"] = -1
		v["last_transition_index"] = -1
		v["last_clock_beat"] = beat
		return

	var loop_index := 0
	var local_t : float = elapsed

	if bool(v.get("loop", loop)):
		loop_index = int(floor(elapsed / loop_length))
		local_t = fposmod(elapsed, loop_length)
	else:
		local_t = min(elapsed, loop_length)

	var clock_rewound := beat < float(v.get("last_clock_beat", beat))
	var loop_changed := loop_index != int(v["loop_index"])

	if clock_rewound or force_reentry:
		v["loop_index"] = loop_index
		var reentry_index := _get_score_index_at_local_beat(score, local_t)
		v["index"] = reentry_index
		v["last_transition_index"] = -1
		var reentry_event = _event_with_absolute_time(score[reentry_index], v, loop_index)
		voice_reentered.emit(v["id"], reentry_event)

		if emit_reentry_event and _event_starts_at_local_beat(score, reentry_index, local_t):
			_emit_event_entered(v, score[reentry_index], loop_index, reentry_index)
	elif loop_changed:
		v["loop_index"] = loop_index
		v["index"] = 0
		v["last_transition_index"] = -1
		_emit_event_entered(v, score[0], loop_index, 0)

	var index = v["index"]

	while index < score.size() - 1 and local_t >= _get_event_local_start(score, index + 1):
		index += 1
		_emit_event_entered(v, score[index], loop_index, index)

	v["index"] = index
	state_changed.emit(v["id"], _event_with_absolute_time(score[index], v, loop_index))

	if (
		v.get("stop_requested", false)
		and index >= int(v.get("stop_target_index", -1))
	):
		var pause_event = _event_with_absolute_time(score[index], v, loop_index)

		v["active"] = false
		v["stop_requested"] = false
		v["stop_target_index"] = -1
		v["last_transition_index"] = -1
		voice_paused.emit(v["id"], pause_event)
		return

	if index < score.size() - 1 and v["last_transition_index"] != index:
		var current_event = _event_with_absolute_time(score[index], v, loop_index)
		var next_event = _event_with_absolute_time(score[index + 1], v, loop_index, index + 1)

		transition_started.emit(v["id"], current_event, next_event)
		v["last_transition_index"] = index
	elif bool(v.get("loop", loop)) and index == score.size() - 1 and v["last_transition_index"] != index:
		var current_event = _event_with_absolute_time(score[index], v, loop_index)
		var next_event = _event_with_absolute_time(score[0], v, loop_index + 1, 0)

		transition_started.emit(v["id"], current_event, next_event)
		v["last_transition_index"] = index

	v["last_clock_beat"] = beat

func _get_score_index_at_local_beat(score: Array, local_beat: float) -> int:
	var index := 0

	while index < score.size() - 1 and local_beat >= _get_event_local_start(score, index + 1):
		index += 1

	return index

func _event_starts_at_local_beat(score: Array, index: int, local_beat: float) -> bool:
	return is_equal_approx(_get_event_local_start(score, index), local_beat)

func _emit_event_entered(
	v: Dictionary,
	event: Dictionary,
	loop_index: int,
	event_index: int = -1
) -> void:
	var absolute_event = _event_with_absolute_time(event, v, loop_index, event_index)

	event_entered.emit(v["id"], absolute_event)
	note_entered.emit(v["id"], absolute_event)

func _event_with_absolute_time(
	event: Dictionary,
	v: Dictionary,
	loop_index: int,
	event_index: int = -1
) -> Dictionary:
	var absolute_event = event.duplicate()
	var score: Array = v["score"]
	if event_index < 0:
		event_index = int(v.get("index", 0))
	var local_start_beat := _get_event_local_start(score, event_index)

	absolute_event["voice_id"] = v["id"]
	absolute_event["volume"] = v.get("volume", 0.8)
	absolute_event["local_start_beat"] = local_start_beat
	absolute_event["start_beat"] = (
		v["start_beat"]
		+ loop_index * v["loop_length"]
		+ local_start_beat
	)

	return absolute_event

func _get_score_loop_length(score: Array) -> float:
	var length := 0.0

	for index in range(score.size()):
		length += _get_event_duration(score[index])

	return length

func _get_event_local_start(score: Array, event_index: int) -> float:
	var local_start := 0.0

	for index in range(min(event_index, score.size())):
		local_start += _get_event_duration(score[index])

	return local_start

func _get_event_duration(event: Dictionary) -> float:
	return max(0.0, float(event.get("duration_beats", 0.0)))
