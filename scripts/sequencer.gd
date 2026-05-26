extends Node
class_name Sequencer

signal transition_started(voice_id, current_event, next_event)
signal note_entered(voice_id, event)
signal event_entered(voice_id, event)
signal state_changed(voice_id, event)
signal voice_paused(voice_id, event)

var voices: Array = []
var loop := true

var next_voice_id := 0

func add_voice(
	score: Array,
	start_beat: float = -1.0,
	volume: float = 0.8
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
		"loop_length": score[-1]["start_beat"],
		"start_beat": start_beat,
		"loop_index": -1,
		"last_transition_index": -1,
		"stop_requested": false,
		"stop_target_index": -1,
		"volume": clamp(volume, 0.0, 1.0),
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

func stop_voice(voice_id: int) -> void:
	for voice in voices:
		if voice["id"] == voice_id:
			voice["active"] = false
			voice["stop_requested"] = false
			voice["stop_target_index"] = -1
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

		if index >= score.size() - 1:
			index = 0
			voice["index"] = index

		voice["start_beat"] = (
			start_beat
			- score[index].get("start_beat", 0.0)
		)
		voice["loop_index"] = 0
		voice["last_transition_index"] = -1
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

func _advance_voice(v: Dictionary, beat: float) -> void:
	var score = v["score"]
	if score.size() < 2:
		return

	var loop_length = v["loop_length"]
	if loop_length <= 0.0:
		return

	var elapsed = beat - v["start_beat"]
	if elapsed < 0.0:
		return

	var loop_index := 0
	var local_t : float = elapsed

	if loop:
		loop_index = int(floor(elapsed / loop_length))
		local_t = fposmod(elapsed, loop_length)
	else:
		local_t = min(elapsed, loop_length)

	if loop_index != v["loop_index"]:
		v["loop_index"] = loop_index
		v["index"] = 0
		v["last_transition_index"] = -1
		_emit_event_entered(v, score[0], loop_index)

	var index = v["index"]

	while index < score.size() - 1 and local_t >= score[index + 1]["start_beat"]:
		index += 1
		_emit_event_entered(v, score[index], loop_index)

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
		var next_event = _event_with_absolute_time(score[index + 1], v, loop_index)

		transition_started.emit(v["id"], current_event, next_event)
		v["last_transition_index"] = index

func _emit_event_entered(v: Dictionary, event: Dictionary, loop_index: int) -> void:
	var absolute_event = _event_with_absolute_time(event, v, loop_index)

	event_entered.emit(v["id"], absolute_event)
	note_entered.emit(v["id"], absolute_event)

func _event_with_absolute_time(event: Dictionary, v: Dictionary, loop_index: int) -> Dictionary:
	var absolute_event = event.duplicate()

	absolute_event["voice_id"] = v["id"]
	absolute_event["volume"] = v.get("volume", 0.8)
	absolute_event["local_start_beat"] = event.get("start_beat", 0.0)
	absolute_event["start_beat"] = (
		v["start_beat"]
		+ loop_index * v["loop_length"]
		+ event.get("start_beat", 0.0)
	)

	return absolute_event
