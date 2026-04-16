extends Node
class_name AudioManager

var generator := AudioStreamGenerator.new()
var player := AudioStreamPlayer.new()
var playback: AudioStreamGeneratorPlayback

var sample_rate := 44100.0
var buffer_length := 0.03
const BASE_MIDI_NOTE := 60
var voices := {}  # Dictionary<int, Voice>
var voice_counts := {}  # Dictionary<int, int>

class Voice:
	var freq: float
	var phase := 0.0
	var volume := 0.2
	
	func _init(f):
		freq = f

func _ready():
	generator.mix_rate = sample_rate
	generator.buffer_length = buffer_length
	player.stream = generator
	add_child(player)
	player.play()
	
	playback = player.get_stream_playback()
	set_process(true)

func _process(delta):
	var frames = playback.get_frames_available()
	
	for i in range(frames):
		var sample := 0.0
		
		for v in voices.values():
			sample += sin(v.phase) * v.volume
			v.phase += TAU * v.freq / sample_rate
		
		sample = clamp(sample, -1.0, 1.0)
		playback.push_frame(Vector2(sample, sample))

func play_notes(pitches: Array[int]):
	print("Playing note(s) ")
	for p in pitches:
		voice_counts[p] = voice_counts.get(p, 0) + 1
		if voice_counts[p] == 1:
			voices[p] = Voice.new(pitch_to_freq(p))
		print(p)

func stop_note(pitch: int):
	if not voice_counts.has(pitch):
		return
	voice_counts[pitch] -= 1
	if voice_counts[pitch] <= 0:
		voice_counts.erase(pitch)
		voices.erase(pitch)
	print("Stopped note ", pitch)

func pitch_to_freq(pitch_class: int) -> float:
	var midi_note = BASE_MIDI_NOTE + pitch_class
	return 440.0 * pow(2.0, (midi_note - 69) / 12.0)
