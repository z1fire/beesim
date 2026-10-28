class_name Swarm
extends Node3D
## The swarm: a cloud of bees that follows the player to the new home, moves in,
## and afterwards keeps buzzing around it.

signal settled

const COUNT := 160
const IDLE_COUNT := 24

enum Mode { HIDDEN, FOLLOW, SETTLE, IDLE }

var leader: Bee
var home: Vector3 ## Inside the hollow; settling bees fly here and vanish.
var home_front: Vector3 ## In front of the hollow, where the resident bees hang about.
var rally: Vector3 ## Where the swarm waits if the leader goes inside the hive.
var mode := Mode.HIDDEN

var _mm: MultiMesh
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _offset := PackedVector3Array()
var _phase := PackedFloat32Array()
var _center := Vector3.ZERO
var _settle_t := 0.0
var _buzz: AudioStreamPlayer3D


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in COUNT:
		_offset.append(Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 0.6), rng.randfn(0.0, 1.0)).limit_length(2.5) * 1.5)
		_phase.append(rng.randf() * TAU)
		_pos.append(Vector3.ZERO)
		_vel.append(Vector3.ZERO)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = _bee_mesh()
	_mm.instance_count = COUNT
	_mm.visible_instance_count = 0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/swarm.gdshader")
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_buzz = AudioStreamPlayer3D.new()
	_buzz.stream = AudioSynth.buzz()
	_buzz.pitch_scale = 0.8
	_buzz.unit_size = 8.0
	add_child(_buzz)


## Bees pour out of the hive and start following the leader.
func launch(from: Vector3) -> void:
	mode = Mode.FOLLOW
	_center = from
	for i in COUNT:
		_pos[i] = from + _offset[i] * 0.1
		_vel[i] = Vector3.ZERO
	_mm.visible_instance_count = COUNT
	_buzz.volume_db = 0.0
	_buzz.play()


## The swarm streams into the hollow.
func settle() -> void:
	mode = Mode.SETTLE
	_settle_t = 0.0


## A few residents buzz around the new home for good.
func idle() -> void:
	mode = Mode.IDLE
	_center = home_front
	for i in IDLE_COUNT:
		_pos[i] = home_front + _offset[i] * 0.6
	_mm.visible_instance_count = IDLE_COUNT
	_buzz.volume_db = -10.0
	_buzz.play()


func _process(delta: float) -> void:
	if mode == Mode.HIDDEN:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var target := home_front
	var spread := 0.6
	var shrink := 1.0
	match mode:
		Mode.FOLLOW:
			spread = 1.0
			if leader.global_position.y < -100.0:
				target = rally
			else:
				target = leader.global_position + Vector3(sin(leader.yaw), 0.0, cos(leader.yaw)) * 2.0 + Vector3.UP * 1.5
		Mode.SETTLE:
			_settle_t += delta
			target = home
			spread = maxf(0.0, 1.0 - _settle_t / 4.0)
			shrink = clampf(spread * 2.0, 0.02, 1.0)
			if _settle_t > 5.0:
				idle()
				settled.emit()
				return
	_center = _center.lerp(target, 1.0 - exp(-1.6 * delta))
	for i in _mm.visible_instance_count:
		var ph := _phase[i]
		var wobble := Vector3(sin(t * 1.3 + ph), sin(t * 1.9 + ph * 0.5) * 0.6, cos(t * 1.1 + ph * 1.7)) * 0.8
		var goal := _center + (_offset[i] + wobble) * spread
		var v := _vel[i].lerp((goal - _pos[i]) * 2.2, 1.0 - exp(-3.0 * delta)).limit_length(16.0)
		_vel[i] = v
		_pos[i] += v * delta
		var dir := v.normalized() if v.length() > 0.2 else (goal - _pos[i]).normalized()
		var b := Basis()
		if dir.length() > 0.5 and absf(dir.y) < 0.98:
			b = Basis.looking_at(dir, Vector3.UP)
		_mm.set_instance_transform(i, Transform3D(b.scaled(Vector3.ONE * shrink), _pos[i]))
	_buzz.global_position = _center


static func _bee_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var yellow := MeshKit.lin(Color(0.98, 0.72, 0.12))
	var black := MeshKit.lin(Color(0.08, 0.05, 0.03))
	var brown := MeshKit.lin(Color(0.62, 0.42, 0.16))
	MeshKit.ellipsoid(st, Transform3D(Basis(), Vector3.ZERO), Vector3(0.085, 0.08, 0.09), 5, 8, brown, MeshKit.shade(brown, 0.6))
	MeshKit.ellipsoid(st, Transform3D(Basis(), Vector3(0, 0.01, -0.12)), Vector3(0.06, 0.06, 0.055), 4, 8, black, black)
	var bands := [[0.09, yellow, 0.09], [0.15, black, 0.095], [0.21, yellow, 0.085], [0.27, black, 0.06]]
	for band in bands:
		var r: float = band[2]
		MeshKit.ellipsoid(st, Transform3D(Basis(), Vector3(0, -0.02, band[0])), Vector3(r, r * 0.92, 0.065), 5, 8,
			band[1], MeshKit.shade(band[1], 0.6))
	for side in [-1.0, 1.0]:
		MeshKit.disc(st, Transform3D(Basis(), Vector3(0.12 * side, 0.07, 0.02)), 0.12, 0.045, 10, 1,
			func(_t: float) -> Color: return Color(0.85, 0.92, 1.0, 0.5))
	return st.commit()
