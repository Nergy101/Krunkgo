extends Node
## All sound is synthesised at boot. No asset pipeline, no licensing, and the
## weapon-feedback slice can retune a gunshot by changing numbers.
##
## Krunker's audio identity is short, dry, high-transient cracks with almost no
## tail, plus an unmistakable metallic hitmarker tick.

const RATE := 44100

var _bank: Dictionary = {}
var _pool2d: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _next2d: int = 0
var _next3d: int = 0

func _ready() -> void:
	_bank["crack"] = _gunshot(0.13, 1.0, 0.55)
	_bank["boom"] = _gunshot(0.34, 0.55, 0.85)
	_bank["hit"] = _tick(1350.0, 0.045, 0.35)
	_bank["hit_head"] = _tick(2100.0, 0.055, 0.42)
	_bank["kill"] = _arp([880.0, 1320.0, 1760.0], 0.055, 0.30)
	_bank["hurt"] = _thump(150.0, 0.16, 0.5)
	_bank["land"] = _thump(90.0, 0.13, 0.35)
	_bank["jump"] = _tick(420.0, 0.05, 0.14)
	_bank["step"] = _noise_burst(0.045, 0.10, 5200.0)
	_bank["slide"] = _noise_burst(0.34, 0.16, 1600.0)
	_bank["reload_in"] = _tick(320.0, 0.05, 0.22)
	_bank["reload_out"] = _tick(520.0, 0.04, 0.20)
	_bank["switch"] = _tick(700.0, 0.035, 0.18)
	_bank["impact"] = _noise_burst(0.07, 0.22, 3200.0)
	_bank["spawn"] = _arp([520.0, 780.0], 0.07, 0.22)

	# Per-weapon voices. weapon_defs.gd names these in its `tone` field; an SMG
	# at 800 rpm and a bolt sniper must not be one synth at two pitches.
	# body = low-end weight, bright = high transient, dur = tail length.
	_bank["crack_ar"] = _gunshot(0.15, 1.05, 0.60)
	_bank["buzz_smg"] = _gunshot(0.075, 1.35, 0.30)
	_bank["boom_sniper"] = _gunshot(0.62, 0.60, 1.15)
	_bank["boom_shotgun"] = _gunshot(0.42, 0.75, 1.05)
	_bank["pop_pistol"] = _gunshot(0.12, 1.15, 0.50)
	# Distance versions: the transient is what dies first over air, so these are
	# duller and longer rather than just quieter.
	for k in ["crack_ar", "buzz_smg", "boom_sniper", "boom_shotgun", "pop_pistol"]:
		_bank[k + "_far"] = _distant(_bank[k])

	# Mechanical layers
	_bank["bolt"] = _metal_click(0.13, 0.30)
	_bank["mag_out"] = _metal_click(0.09, 0.22)
	_bank["mag_in"] = _metal_click(0.11, 0.30)
	_bank["dryfire"] = _metal_click(0.05, 0.26)
	_bank["low_ammo"] = _tick(2400.0, 0.03, 0.16)

	for i in 24:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool2d.append(p)
	for i in 24:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 14.0
		p3.max_distance = 90.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_pool3d.append(p3)

func play(key: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not _bank.has(key):
		return
	var p: AudioStreamPlayer = _pool2d[_next2d]
	_next2d = (_next2d + 1) % _pool2d.size()
	p.stream = _bank[key]
	p.pitch_scale = clampf(pitch, 0.05, 4.0)
	p.volume_db = volume_db
	p.play()

func play_at(key: String, pos: Vector3, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not _bank.has(key):
		return
	var p: AudioStreamPlayer3D = _pool3d[_next3d]
	_next3d = (_next3d + 1) % _pool3d.size()
	p.stream = _bank[key]
	p.global_position = pos
	p.pitch_scale = clampf(pitch, 0.05, 4.0)
	p.volume_db = volume_db
	p.play()

# ------------------------------------------------------------------ synthesis
func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v: int = int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w

func _rand() -> float:
	return randf() * 2.0 - 1.0

## Dry gunshot: noise transient over a fast pitch-dropping body.
func _gunshot(dur: float, brightness: float, body: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var env: float = exp(-t * (26.0 / maxf(dur, 0.01)) * 0.35)
		var click: float = exp(-t * 900.0)
		var noise := _rand()
		var cutoff: float = clampf(0.55 * brightness * exp(-t * 18.0) + 0.06, 0.02, 0.95)
		lp += (noise - lp) * cutoff
		var f: float = 120.0 * exp(-t * 12.0) + 42.0
		phase += TAU * f / RATE
		var low := sin(phase) * body * exp(-t * 22.0)
		s[i] = clampf((lp * 1.5 + low + click * 0.9) * env, -1.0, 1.0) * 0.85
	return _wav(s)

func _tick(freq: float, dur: float, amp: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env: float = exp(-t * 55.0)
		var v := sin(TAU * freq * t) * 0.7 + sin(TAU * freq * 2.01 * t) * 0.3
		s[i] = v * env * amp
	return _wav(s)

func _arp(freqs: Array, step: float, amp: float) -> AudioStreamWAV:
	var n := int(step * freqs.size() * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var idx: int = mini(int(t / step), freqs.size() - 1)
		var lt: float = t - idx * step
		var env: float = exp(-lt * 34.0)
		s[i] = sin(TAU * float(freqs[idx]) * lt) * env * amp
	return _wav(s)

func _thump(freq: float, dur: float, amp: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f: float = freq * exp(-t * 9.0)
		phase += TAU * f / RATE
		s[i] = sin(phase) * exp(-t * 16.0) * amp
	return _wav(s)

func _noise_burst(dur: float, amp: float, cutoff_hz: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var a: float = clampf(cutoff_hz / float(RATE) * 4.0, 0.01, 0.99)
	for i in n:
		var t := float(i) / RATE
		lp += (_rand() - lp) * a
		s[i] = lp * exp(-t * (4.0 / maxf(dur, 0.01))) * amp
	return _wav(s)

## Metallic click: a short inharmonic ring, used for bolt, magazine and dryfire.
## Inharmonic partials are what make it read as metal rather than a beep.
func _metal_click(dur: float, amp: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	const PARTIALS := [1.0, 2.37, 3.91, 5.62]
	for i in n:
		var t := float(i) / RATE
		var env: float = exp(-t * 42.0)
		var click: float = exp(-t * 1400.0) * 0.8
		var v := 0.0
		for k in PARTIALS.size():
			v += sin(TAU * 780.0 * float(PARTIALS[k]) * t) / float(k + 2)
		s[i] = (v * 0.5 + click + _rand() * 0.25 * exp(-t * 260.0)) * env * amp
	return _wav(s)

## Same shot heard from across the map: transient stripped, tail extended.
## Over distance the high-frequency crack dies long before the low-end body.
func _distant(src: AudioStreamWAV) -> AudioStreamWAV:
	var raw := src.data
	var count := raw.size() / 2
	var tail := int(0.22 * RATE)
	var out := PackedFloat32Array()
	out.resize(count + tail)
	var lp := 0.0
	for i in count:
		var v := float(raw.decode_s16(i * 2)) / 32767.0
		lp += (v - lp) * 0.045          # heavy low pass
		out[i] = lp * 0.85
	# slap-back off the far walls, which is most of what distant gunfire is
	for i in range(count, count + tail):
		out[i] = 0.0
	for i in range(count + tail):
		var d := i - int(0.055 * RATE)
		if d >= 0 and d < count:
			out[i] += out[d] * 0.34 * exp(-float(i - d) / float(RATE) * 6.0)
	return _wav(out)
