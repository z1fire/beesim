class_name AudioSynth
extends RefCounted
## Generates the game's sounds at startup, so the project needs no audio files.

const RATE := 22050


static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


## Wing buzz. One second long and every frequency is a whole number of Hz, so it loops seamlessly.
static func buzz() -> AudioStreamWAV:
	var s := PackedFloat32Array()
	s.resize(RATE)
	for i in RATE:
		var t := float(i) / RATE
		var v := 0.0
		for k in range(1, 9):
			v += sin(TAU * 150.0 * k * t) / k
		v *= 0.75 + 0.25 * sin(TAU * 25.0 * t)
		s[i] = v * 0.16
	return _wav(s, true)


## A short run of bell-like notes.
static func chime(notes: Array, note_len := 0.1) -> AudioStreamWAV:
	var total := int(RATE * (note_len * notes.size() + 0.6))
	var s := PackedFloat32Array()
	s.resize(total)
	for k in notes.size():
		var f: float = notes[k]
		var start := int(RATE * note_len * k)
		for i in range(start, total):
			var t := float(i - start) / RATE
			var env := exp(-t * 6.0) * minf(t * 300.0, 1.0)
			s[i] += (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * env * 0.22
	return _wav(s)


## Soft looping breeze (brown noise with slow gusts).
static func wind() -> AudioStreamWAV:
	var n := RATE * 4
	var fade := RATE / 2
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var b := 0.0
	for i in n:
		b = (b + rng.randf_range(-1.0, 1.0) * 0.02) * 0.997
		s[i] = b * (0.6 + 0.4 * sin(TAU * 2.0 * i / n)) * 1.6
	# Blend the tail into the head so the loop seam is inaudible.
	for i in fade:
		var t := float(i) / fade
		s[i] = s[i] * t + s[n - fade + i] * (1.0 - t)
	return _wav(s.slice(0, n - fade), true)


## A little bird call: three quick rising chirps.
static func chirp() -> AudioStreamWAV:
	var n := int(RATE * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	for syl in 3:
		var start := int(RATE * 0.14 * syl)
		var length := int(RATE * 0.08)
		var phase := 0.0
		for i in length:
			var t := float(i) / length
			var f := lerpf(2800.0, 4300.0, t) + sin(t * 40.0) * 150.0
			phase += TAU * f / RATE
			s[start + i] += sin(phase) * sin(PI * t) * 0.18
	return _wav(s)
