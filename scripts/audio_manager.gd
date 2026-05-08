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

	
func play_notes(notes: Array[TonnetzNode]):
	for n in notes:
		var note_name = n.note_name
		var octave = n.octave
		sampler.play_note(note_name, octave)
		print("Playing ", note_name)
		

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
