class_name WorkerBee
extends Node3D
## A helper bee that shuttles between flowers and the hive on its own.

enum State { REST, TO_FLOWER, FEED, TO_HIVE }

var flowers: FlowerField
var hive: Hive
var terrain: Terrain

var _state := State.REST
var _flower := -1
var _timer := 0.0
var _vel := Vector3.ZERO
var _cargo := Vector2.ZERO
var _phase := 0.0
var _model: BeeModel
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_phase = _rng.randf() * TAU
	_timer = _rng.randf_range(0.5, 3.0)
	_model = BeeModel.new()
	_model.simple = true
	_model.scale = Vector3.ONE * 0.85
	add_child(_model)


func _process(delta: float) -> void:
	_phase += delta
	match _state:
		State.REST:
			var orbit := Vector3(sin(_phase) * 1.5, 0.8 + sin(_phase * 1.3) * 0.3, 1.5 + cos(_phase) * 1.0)
			_fly_to(hive.entrance + orbit, delta, 2.0)
			_timer -= delta
			if _timer <= 0.0:
				_flower = flowers.random_with_nectar(_rng)
				if _flower >= 0:
					_state = State.TO_FLOWER
				else:
					_timer = 3.0
		State.TO_FLOWER:
			if _fly_to(flowers.hover[_flower], delta, 6.0) < 0.4:
				_state = State.FEED
				_timer = _rng.randf_range(2.5, 4.5)
		State.FEED:
			_fly_to(flowers.hover[_flower] + Vector3(0, sin(_phase * 3.0) * 0.05, 0), delta, 1.0)
			_timer -= delta
			if _timer <= 0.0:
				_cargo = flowers.take(_flower, 4.0, 1.5)
				_state = State.TO_HIVE
		State.TO_HIVE:
			if _fly_to(hive.entrance, delta, 6.0) < 0.6:
				Game.hive_nectar += _cargo.x
				Game.hive_pollen += _cargo.y
				_cargo = Vector2.ZERO
				Game.changed.emit()
				_state = State.REST
				_timer = _rng.randf_range(2.0, 5.0)


## Steers toward target with a wobbly arc; returns the remaining distance.
func _fly_to(target: Vector3, delta: float, speed: float) -> float:
	var dist := global_position.distance_to(target)
	var aim := target
	if dist > 8.0:
		aim.y += minf(dist * 0.25, 8.0)
	var desired := (aim - global_position).normalized() * minf(speed, dist * 2.0)
	desired += Vector3(sin(_phase * 3.1), sin(_phase * 4.3) * 0.6, cos(_phase * 2.7)) * 0.5
	_vel = _vel.lerp(desired, 1.0 - exp(-3.0 * delta))
	var p := global_position + _vel * delta
	p.y = maxf(p.y, maxf(terrain.height_at(p.x, p.z), Terrain.WATER_LEVEL) + 0.3)
	global_position = p
	if Vector2(_vel.x, _vel.z).length() > 0.3:
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-_vel.x, -_vel.z), 1.0 - exp(-6.0 * delta))
	return dist
