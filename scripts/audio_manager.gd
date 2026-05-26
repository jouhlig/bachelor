extends Node
class_name AudioManager

@onready var sampler 
const BASE_MIDI_NOTE := 60

const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
#const octave: int = 4

@onready var ocarina = get_node("/root/Game/Samplers/SamplerOcarina")
@onready var xylophone = get_node("/root/Game/Samplers/SamplerXylophone")
@onready var piano = get_node("/root/Game/Samplers/SamplerPiano")
@onready var harp = get_node("/root/Game/Samplers/SamplerHarp")
@onready var samplers = [xylophone, ocarina, piano, harp]

func _ready() -> void:
	sampler = xylophone

	
func play_notes(notes: Array, volume: float = 0.8):
	for n in notes:
		var note_name = n.note_name
		var octave = n.octave
		_play_note(note_name, octave, volume)
		#print("Playing ", note_name)

func play_event(event: Dictionary) -> void:
	if event.get("pen_status", 1) == 0:
		return

	var volume := float(event.get("volume", 0.8))

	if volume <= 0.0:
		return

	var anchor = event.get("anchor")

	if anchor is TriangleArea:
		play_notes(anchor.nodes, volume)
	elif anchor is TonnetzNode:
		play_notes([anchor], volume)
		
func _play_note(note_name: String, octave: int, volume: float) -> void:
	if not sampler:
		return

	volume = clamp(volume, 0.0, 1.0)

	if volume <= 0.0:
		return

	var volume_db := linear_to_db(volume)

	if sampler is SamplerInstrument:
		if sampler.samplers.is_empty():
			return

		var child_sampler = sampler.samplers[sampler.next_available]
		child_sampler.volume_db = volume_db
		child_sampler.max_volume = volume_db
		child_sampler.play_note(note_name, octave)
		sampler.next_available = (
			sampler.next_available + 1
		) % sampler.samplers.size()
		sampler.last_sampler_used = child_sampler
	elif sampler is Sampler:
		sampler.volume_db = volume_db
		sampler.max_volume = volume_db
		sampler.play_note(note_name, octave)
	else:
		sampler.volume_db = volume_db
		sampler.play_note(note_name, octave)

func stop_note(pitch: int):
	pass
	
func change_instrument(index: int):
	if sampler:
		sampler.stop() 

	print("signal instr inside AM")
	sampler = samplers[index]
	print(sampler)
	
# --------OLD VERSION BASED ON GODOT SYNTH--------
#extends Node
#class_name AudioManager
#
#var generator := AudioStreamGenerator.new()
#var player := AudioStreamPlayer.new()
#var playback: AudioStreamGeneratorPlayback
#@onready var sampler := %SamplerInstrument
#
#var sample_rate := 44100.0
#var buffer_length := 0.03
#const BASE_MIDI_NOTE := 60
#var voices := {}  # Dictionary<int, Voice>
#var voice_counts := {}  # Dictionary<int, int>
#
#class Voice:
	#var freq: float
	#var phase := 0.0
	#var volume := 0.2
	#
	#func _init(f):
		#freq = f
#
#func _ready():
	#generator.mix_rate = sample_rate
	#generator.buffer_length = buffer_length
	#player.stream = generator
	#add_child(player)
	#player.play()
	#
	#playback = player.get_stream_playback()
	#set_process(true)
#
#func _process(delta):
	#var frames = playback.get_frames_available()
	#
	#for i in range(frames):
		#var sample := 0.0
		#
		#for v in voices.values():
			#sample += sin(v.phase) * v.volume
			#v.phase += TAU * v.freq / sample_rate
		#
		#sample = clamp(sample, -1.0, 1.0)
		#playback.push_frame(Vector2(sample, sample))
#
#func play_notes(pitches: Array[int]):
	#print("Playing note(s) ")
	#for p in pitches:
		#voice_counts[p] = voice_counts.get(p, 0) + 1
		#if voice_counts[p] == 1:
			#voices[p] = Voice.new(pitch_to_freq(p))
		#print(p)
#
#func stop_note(pitch: int):
	#if not voice_counts.has(pitch):
		#return
	#voice_counts[pitch] -= 1
	#if voice_counts[pitch] <= 0:
		#voice_counts.erase(pitch)
		#voices.erase(pitch)
	#print("Stopped note ", pitch)
#
#func pitch_to_freq(pitch_class: int) -> float:
	#var midi_note = BASE_MIDI_NOTE + pitch_class
	#return 440.0 * pow(2.0, (midi_note - 69) / 12.0)
