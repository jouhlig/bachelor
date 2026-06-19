extends RefCounted
class_name MidiExporter

const TICKS_PER_BEAT := 480
const DEFAULT_BPM := 120

const PROGRAMS := {
	0: 13, # Xylophone
	1: 79, # Ocarina
	2: 0, # Acoustic Grand Piano
	3: 46 # Orchestral Harp
}

static func export_voices(
	voices: Array,
	path: String,
	bpm: int,
	length_beats: float,
	instrument_index: int,
	muted_voice_ids: Array = []
) -> Dictionary:
	var playable_voices := _get_playable_voices(voices, muted_voice_ids)

	if playable_voices.is_empty():
		return {
			"ok": false,
			"message": "There are no active voices to export."
		}

	var duration_beats : float = max(1.0, length_beats)
	var origin_beat := _get_earliest_voice_start(playable_voices)
	var midi_data := _build_midi_file(
		playable_voices,
		max(1, bpm),
		duration_beats,
		origin_beat,
		instrument_index
	)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"message": "Could not write MIDI file: %s" % FileAccess.get_open_error()
		}

	file.store_buffer(midi_data)
	file.close()

	return {
		"ok": true,
		"message": "Exported MIDI to %s" % path,
		"path": path
	}

static func _get_playable_voices(voices: Array, muted_voice_ids: Array) -> Array:
	var playable := []

	for voice in voices:
		var voice_id := int(voice.get("id", -1))
		var score: Array = voice.get("score", [])

		if muted_voice_ids.has(voice_id):
			continue

		if score.size() < 2:
			continue

		if float(voice.get("loop_length", 0.0)) <= 0.0:
			continue

		if float(voice.get("volume", 0.8)) <= 0.0:
			continue

		playable.append(voice)

	return playable

static func _get_earliest_voice_start(voices: Array) -> float:
	var earliest := INF

	for voice in voices:
		earliest = min(earliest, float(voice.get("start_beat", 0.0)))

	return 0.0 if earliest == INF else earliest

static func _build_midi_file(
	voices: Array,
	bpm: int,
	duration_beats: float,
	origin_beat: float,
	instrument_index: int
) -> PackedByteArray:
	var tracks: Array[PackedByteArray] = [_build_tempo_track(bpm)]
	var program := int(PROGRAMS.get(instrument_index, 0))

	for voice_index in range(voices.size()):
		var channel := voice_index % 16

		if channel == 9:
			channel = (channel + 1) % 16

		tracks.append(
			_build_voice_track(
				voices[voice_index],
				voice_index,
				channel,
				program,
				duration_beats,
				origin_beat
			)
		)

	var data := PackedByteArray()
	_append_ascii(data, "MThd")
	_append_u32(data, 6)
	_append_u16(data, 1)
	_append_u16(data, tracks.size())
	_append_u16(data, TICKS_PER_BEAT)

	for track in tracks:
		_append_ascii(data, "MTrk")
		_append_u32(data, track.size())
		data.append_array(track)

	return data

static func _build_tempo_track(bpm: int) -> PackedByteArray:
	var track := PackedByteArray()
	var microseconds_per_quarter := int(round(60000000.0 / float(max(1, bpm))))

	_append_var_len(track, 0)
	track.append(0xFF)
	track.append(0x51)
	track.append(0x03)
	track.append((microseconds_per_quarter >> 16) & 0xFF)
	track.append((microseconds_per_quarter >> 8) & 0xFF)
	track.append(microseconds_per_quarter & 0xFF)
	_append_end_of_track(track)

	return track

static func _build_voice_track(
	voice: Dictionary,
	voice_index: int,
	channel: int,
	program: int,
	duration_beats: float,
	origin_beat: float
) -> PackedByteArray:
	var track := PackedByteArray()
	var events := _build_note_events(voice, channel, duration_beats, origin_beat)

	_append_track_name(track, "Voice %d" % (voice_index + 1))
	_append_var_len(track, 0)
	track.append(0xC0 | channel)
	track.append(clamp(program, 0, 127))

	var previous_tick := 0

	for event in events:
		var tick := int(event["tick"])
		_append_var_len(track, max(0, tick - previous_tick))
		track.append(int(event["status"]))
		track.append(int(event["note"]))
		track.append(int(event["velocity"]))
		previous_tick = tick

	_append_end_of_track(track)
	return track

static func _build_note_events(
	voice: Dictionary,
	channel: int,
	duration_beats: float,
	origin_beat: float
) -> Array:
	var score: Array = voice.get("score", [])
	var loop_length := float(voice.get("loop_length", 0.0))
	var voice_start := float(voice.get("start_beat", 0.0))
	var voice_volume :float = clamp(float(voice.get("volume", 0.8)), 0.0, 1.0)
	var events := []

	if score.size() < 2 or loop_length <= 0.0 or voice_volume <= 0.0:
		return events

	var first_loop := int(floor((origin_beat - voice_start) / loop_length))
	first_loop = max(0, first_loop)
	var last_loop := int(ceil((origin_beat + duration_beats - voice_start) / loop_length))
	var velocity : float= clamp(int(round(voice_volume * 127.0)), 1, 127)

	for loop_index in range(first_loop, last_loop + 1):
		for event_index in range(score.size() - 1):
			var event: Dictionary = score[event_index]

			if int(event.get("pen_status", 1)) == 0:
				continue

			var notes := _get_event_midi_notes(event)

			if notes.is_empty():
				continue

			var local_start := float(event.get("start_beat", 0.0))
			var duration : float= max(0.05, float(event.get("duration_beats", 1.0)))
			var start_beat := voice_start + loop_index * loop_length + local_start - origin_beat
			var end_beat : float = start_beat + duration

			if start_beat >= duration_beats or end_beat <= 0.0:
				continue

			start_beat = max(0.0, start_beat)
			end_beat = min(duration_beats, end_beat)

			var start_tick := _beat_to_tick(start_beat)
			var end_tick : float = max(start_tick + 1, _beat_to_tick(end_beat))

			for note in notes:
				events.append({
					"tick": start_tick,
					"priority": 1,
					"status": 0x90 | channel,
					"note": note,
					"velocity": velocity
				})
				events.append({
					"tick": end_tick,
					"priority": 0,
					"status": 0x80 | channel,
					"note": note,
					"velocity": 0
				})

	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_tick := int(a["tick"])
		var b_tick := int(b["tick"])

		if a_tick == b_tick:
			return int(a["priority"]) < int(b["priority"])

		return a_tick < b_tick
	)

	return events

static func _get_event_midi_notes(event: Dictionary) -> Array:
	var anchor = event.get("anchor")
	var tonnetz_nodes := []

	if anchor is TriangleArea:
		tonnetz_nodes = anchor.nodes
	elif anchor is TonnetzNode:
		tonnetz_nodes = [anchor]

	var notes := []

	for node in tonnetz_nodes:
		var note : int= clamp(int(node.pitch), 0, 127)

		if not notes.has(note):
			notes.append(note)

	return notes

static func _beat_to_tick(beat: float) -> int:
	return int(round(beat * float(TICKS_PER_BEAT)))

static func _append_track_name(track: PackedByteArray, name: String) -> void:
	var name_bytes := name.to_utf8_buffer()

	_append_var_len(track, 0)
	track.append(0xFF)
	track.append(0x03)
	_append_var_len(track, name_bytes.size())
	track.append_array(name_bytes)

static func _append_end_of_track(track: PackedByteArray) -> void:
	_append_var_len(track, 0)
	track.append(0xFF)
	track.append(0x2F)
	track.append(0x00)

static func _append_ascii(data: PackedByteArray, text: String) -> void:
	data.append_array(text.to_ascii_buffer())

static func _append_u16(data: PackedByteArray, value: int) -> void:
	data.append((value >> 8) & 0xFF)
	data.append(value & 0xFF)

static func _append_u32(data: PackedByteArray, value: int) -> void:
	data.append((value >> 24) & 0xFF)
	data.append((value >> 16) & 0xFF)
	data.append((value >> 8) & 0xFF)
	data.append(value & 0xFF)

static func _append_var_len(data: PackedByteArray, value: int) -> void:
	var buffer := value & 0x7F
	value = value >> 7

	while value > 0:
		buffer = buffer << 8
		buffer = buffer | ((value & 0x7F) | 0x80)
		value = value >> 7

	while true:
		data.append(buffer & 0xFF)

		if (buffer & 0x80) != 0:
			buffer = buffer >> 8
		else:
			break
