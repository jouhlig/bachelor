class_name MidiExportController
extends RefCounted

var config: TonnetzConfig
var sequencer: Sequencer
var lsystem_playback: LSystemPlayback
var voice_mute_states: Dictionary

func _init(
	new_config: TonnetzConfig,
	new_sequencer: Sequencer,
	new_lsystem_playback: LSystemPlayback,
	new_voice_mute_states: Dictionary
) -> void:
	config = new_config
	sequencer = new_sequencer
	lsystem_playback = new_lsystem_playback
	voice_mute_states = new_voice_mute_states

func export(path: String) -> Dictionary:
	var export_length_beats := _get_export_length_beats(sequencer.voices)
	return MidiExporter.export_voices(
		sequencer.voices,
		path,
		config.bpm,
		export_length_beats,
		_get_muted_voice_ids()
	)

func export_voice(lsystem_index: int, path: String) -> Dictionary:
	if not lsystem_playback.has_voice(lsystem_index):
		return {
			"ok": false,
			"message": "This voice is not playing yet."
		}

	var voice_id := lsystem_playback.get_voice_id(lsystem_index)
	var voice := sequencer.get_voice(voice_id)

	if voice.is_empty():
		return {
			"ok": false,
			"message": "This voice has no sequencer data to export."
		}

	var export_length_beats := _get_export_length_beats([voice])
	return MidiExporter.export_voices(
		[voice],
		path,
		config.bpm,
		export_length_beats
	)

func _get_muted_voice_ids() -> Array:
	var muted_voice_ids := []

	for lsystem_index in voice_mute_states.keys():
		if not bool(voice_mute_states.get(lsystem_index, false)):
			continue

		if lsystem_playback.has_voice(lsystem_index):
			muted_voice_ids.append(lsystem_playback.get_voice_id(lsystem_index))

	return muted_voice_ids

func _get_export_length_beats(voices: Array) -> float:
	var earliest_start := INF
	var latest_end := 0.0

	for voice in voices:
		var score: Array = voice.get("score", [])

		if score.size() < 2:
			continue

		var loop_length := float(voice.get("loop_length", 0.0))

		if loop_length <= 0.0:
			continue

		var start_beat := float(voice.get("start_beat", 0.0))
		earliest_start = min(earliest_start, start_beat)
		latest_end = max(latest_end, start_beat + loop_length)

	if earliest_start == INF:
		return 1.0

	return max(1.0, latest_end - earliest_start)
