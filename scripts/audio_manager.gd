extends Node
class_name AudioManager

const SYNTH_SAMPLE_RATE := 44100.0
const SYNTH_BUFFER_LENGTH := 0.12
const SYNTH_ATTACK_SECONDS := 0.02
const SYNTH_RELEASE_SECONDS := 0.25
const SYNTH_DEFAULT_DURATION := 0.35
const SYNTH_VOLUME := 0.1
const SYNTH_POLYPHONY_HEADROOM := 0.5
const SYNTH_MAX_VOICES := 18
const HIGH_PITCH_ATTENUATION_START := 72
const HIGH_PITCH_ATTENUATION_END := 96
const HIGH_PITCH_MIN_VOLUME_FACTOR := 0.45
#const octave: int = 4

var synth_generator: AudioStreamGenerator
var synth_player: AudioStreamPlayer
var synth_voices := []

class SynthVoice:
	var voice_id: int
	var pitch: int
	var freq: float
	var phase_step: float
	var phase := 0.0
	var volume := 0.2
	var age := 0.0
	var duration := SYNTH_DEFAULT_DURATION
	
	func _init(
		new_voice_id: int,
		new_pitch: int,
		new_freq: float,
		new_volume: float,
		new_duration: float
	) -> void:
		voice_id = new_voice_id
		pitch = new_pitch
		freq = new_freq
		phase_step = TAU * freq / SYNTH_SAMPLE_RATE
		volume = new_volume
		duration = new_duration

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return

	_setup_synth_player()


func _exit_tree() -> void:
	synth_voices.clear()
	if synth_player:
		synth_player.stop()

	
func _process(_delta: float) -> void:
	_fill_synth_buffer()


func play_notes(
	notes: Array,
	volume: float = 0.8,
	duration: float = SYNTH_DEFAULT_DURATION,
	voice_id: int = -1
) -> void:
	var pitches := []

	for n in notes:
		pitches.append(n.pitch)

	for pitch in pitches:
		_play_note(pitch, volume, duration, voice_id)

func play_event(event: Dictionary) -> void:
	var duration := float(event.get("duration_sec", 0.0))
	if duration <= 0.0:
		return

	var volume := float(event.get("volume", 0.8))

	if volume <= 0.0:
		return

	var anchor = event.get("anchor")
	var voice_id := int(event.get("voice_id", -1))

	if anchor is TriangleArea:
		play_notes(anchor.nodes, volume, duration, voice_id)
	elif anchor is TonnetzNode:
		play_notes([anchor], volume, duration, voice_id)
		
func _play_note(
	pitch: int,
	volume: float,
	duration: float,
	voice_id: int
) -> void:
	volume = clamp(volume, 0.0, 1.0)

	if volume <= 0.0:
		return

	var synth_volume := volume * SYNTH_VOLUME * _get_pitch_volume_factor(pitch)
	var voice: SynthVoice = _get_voice_for_pitch(pitch, voice_id)

	if voice:
		voice.volume = max(voice.volume, synth_volume)
		voice.duration = max(voice.duration, voice.age + duration)
		return

	synth_voices.append(SynthVoice.new(
		voice_id,
		pitch,
		_pitch_to_freq(pitch),
		synth_volume,
		duration
	))
	_limit_synth_voices()

func stop_note(pitch: int):
	pass


func _setup_synth_player() -> void:
	synth_generator = AudioStreamGenerator.new()
	synth_player = AudioStreamPlayer.new()
	synth_generator.mix_rate = SYNTH_SAMPLE_RATE
	synth_generator.buffer_length = SYNTH_BUFFER_LENGTH
	synth_player.stream = synth_generator
	add_child(synth_player)
	synth_player.play()


func _fill_synth_buffer() -> void:
	if not synth_player:
		return

	var synth_playback: AudioStreamGeneratorPlayback = synth_player.get_stream_playback()
	if not synth_playback:
		return

	var frames := synth_playback.get_frames_available()
	# var mix_scale := 1.0
	# if synth_voices.size() > 1:
	# 	mix_scale = SYNTH_POLYPHONY_HEADROOM / sqrt(float(synth_voices.size()))
	var mix_scale := SYNTH_POLYPHONY_HEADROOM
	for i in range(frames):
		var sample := 0.0

		for v in synth_voices:
			var envelope := 1.0
			if v.age < SYNTH_ATTACK_SECONDS:
				envelope = v.age / SYNTH_ATTACK_SECONDS
			elif v.age > v.duration:
				envelope = 1.0 - clamp((v.age - v.duration) / SYNTH_RELEASE_SECONDS, 0.0, 1.0)

			var voice_sample: float = sin(v.phase) * v.volume * envelope

			sample += voice_sample
			v.phase += v.phase_step
			if v.phase > TAU:
				v.phase -= TAU
			v.age += 1.0 / SYNTH_SAMPLE_RATE

		sample *= mix_scale
		sample = clamp(sample, -0.95, 0.95)
		synth_playback.push_frame(Vector2(sample, sample))

	for i in range(synth_voices.size() - 1, -1, -1):
		if synth_voices[i].age >= synth_voices[i].duration + SYNTH_RELEASE_SECONDS:
			synth_voices.remove_at(i)


func _get_voice_for_pitch(pitch: int, voice_id: int) -> SynthVoice:
	for voice in synth_voices:
		if voice.pitch == pitch and voice.voice_id == voice_id:
			return voice

	return null


func _limit_synth_voices() -> void:
	while synth_voices.size() > SYNTH_MAX_VOICES:
		synth_voices.remove_at(0)


func _pitch_to_freq(pitch: int) -> float:
	return 440.0 * pow(2.0, (pitch - 69) / 12.0)

func _get_pitch_volume_factor(pitch: int) -> float:
	if pitch <= HIGH_PITCH_ATTENUATION_START:
		return 1.0

	var progress: float = clampf(
		float(pitch - HIGH_PITCH_ATTENUATION_START)
		/ float(HIGH_PITCH_ATTENUATION_END - HIGH_PITCH_ATTENUATION_START),
		0.0,
		1.0
	)
	return lerpf(1.0, HIGH_PITCH_MIN_VOLUME_FACTOR, progress)
