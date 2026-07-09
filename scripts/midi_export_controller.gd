class_name MidiExportController
extends RefCounted

var config: TonnetzConfig
var sequencer: Sequencer
var piano_roll: PianoRoll
var lsystem_playback: LSystemPlayback
var voice_mute_states: Dictionary
var current_instrument_index := 0

func _init(
	new_config: TonnetzConfig,
	new_sequencer: Sequencer,
	new_piano_roll: PianoRoll,
	new_lsystem_playback: LSystemPlayback,
	new_voice_mute_states: Dictionary
) -> void:
	config = new_config
	sequencer = new_sequencer
	piano_roll = new_piano_roll
	lsystem_playback = new_lsystem_playback
	voice_mute_states = new_voice_mute_states

func set_instrument_index(index: int) -> void:
	current_instrument_index = index

func export(path: String) -> Dictionary:
	var export_length_beats := float(config.length_bars * piano_roll.beats_per_bar)
	return MidiExporter.export_voices(
		sequencer.voices,
		path,
		config.bpm,
		export_length_beats,
		current_instrument_index,
		_get_muted_voice_ids()
	)

func _get_muted_voice_ids() -> Array:
	var muted_voice_ids := []

	for lsystem_index in voice_mute_states.keys():
		if not bool(voice_mute_states.get(lsystem_index, false)):
			continue

		if lsystem_playback.has_voice(lsystem_index):
			muted_voice_ids.append(lsystem_playback.get_voice_id(lsystem_index))

	return muted_voice_ids
