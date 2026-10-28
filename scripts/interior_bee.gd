class_name InteriorBee
extends Node3D
## A bee living inside the hive: crawling over the comb, flying about, or
## attending the queen.

enum Mode { CRAWL, FLY, ATTEND }

var interior: HiveInterior
var mode := Mode.CRAWL
var surface := 0 ## Comb surface to crawl on, see HiveInterior.surface_point().
var angle := 0.0 ## Position around the queen, for attendants.

var _model: BeeModel
var _rng := RandomNumberGenerator.new()
var _uv := Vector2.ZERO
var _target_uv := Vector2.ZERO
var _wait := 0.0
var _heading := Vector3.FORWARD
var _vel := Vector3.ZERO
var _target := Vector3.ZERO
var _phase := 0.0


func _ready() -> void:
	_rng.randomize()
	_phase = _rng.randf() * TAU
	_model = BeeModel.new()
	_model.simple = mode != Mode.ATTEND
	_model.flying = mode == Mode.FLY
	add_child(_model)
	match mode:
		Mode.CRAWL:
			_uv = _random_uv()
			_target_uv = _uv
		Mode.FLY:
			position = interior.random_air_point()
			_target = interior.random_air_point()


func _process(delta: float) -> void:
	_phase += delta
	match mode:
		Mode.CRAWL:
			_crawl(delta)
		Mode.FLY:
			_fly(delta)
		Mode.ATTEND:
			_attend(delta)


func _crawl(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
	else:
		# The wall's u is an angle, so scale it to metres when measuring.
		var scale := Vector2(HiveInterior.RING if surface == 0 else 1.0, 1.0)
		var to := (_target_uv - _uv) * scale
		if to.length() < 0.03:
			_target_uv = (_uv + Vector2(_rng.randf_range(-1.2, 1.2) / scale.x, _rng.randf_range(-0.8, 0.8))).clamp(_uv_min(), _uv_max())
			_wait = _rng.randf_range(0.5, 3.0)
		else:
			_uv += to.normalized() * minf(0.3 * delta, to.length()) / scale
	var sp := interior.surface_point(surface, _uv)
	var normal: Vector3 = sp[1]
	var ahead: Array = interior.surface_point(surface, _uv + (_target_uv - _uv).limit_length(0.05))
	var dir: Vector3 = (ahead[0] as Vector3) - (sp[0] as Vector3)
	if dir.length() > 0.001:
		_heading = dir.normalized()
	position = (sp[0] as Vector3) + normal * 0.13
	basis = Basis.looking_at(_heading - normal * _heading.dot(normal), normal)


func _fly(delta: float) -> void:
	var to := _target - position
	if to.length() < 0.4:
		_target = interior.random_air_point()
	var desired := to.normalized() * 1.4 + Vector3(sin(_phase * 3.0), sin(_phase * 4.1) * 0.5, cos(_phase * 2.6)) * 0.4
	_vel = _vel.lerp(desired, 1.0 - exp(-2.5 * delta))
	position = interior.constrain(position + _vel * delta + HiveInterior.ORIGIN, 0.3) - HiveInterior.ORIGIN
	if Vector2(_vel.x, _vel.z).length() > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(-_vel.x, -_vel.z), 1.0 - exp(-5.0 * delta))


func _attend(delta: float) -> void:
	angle += delta * 0.12
	var q := interior.queen.position
	var r := 0.95 + 0.05 * sin(_phase * 1.7)
	position = Vector3(q.x + cos(angle) * r, HiveInterior.PLATFORM_Y + 0.13, q.z + sin(angle) * r)
	var look := Vector3(q.x, position.y, q.z) - position
	if look.length() > 0.01:
		basis = Basis.looking_at(look.normalized(), Vector3.UP)


func _random_uv() -> Vector2:
	return Vector2(_rng.randf_range(_uv_min().x, _uv_max().x), _rng.randf_range(_uv_min().y, _uv_max().y))


func _uv_min() -> Vector2:
	return Vector2(-PI, 0.6) if surface == 0 else Vector2(-3.6, 2.9)


func _uv_max() -> Vector2:
	return Vector2(PI, 5.8) if surface == 0 else Vector2(3.6, 7.0)
