class_name Bee
extends CharacterBody3D
## The player: flight, cameras, feeding on flowers and delivering to the hive.

const BASE_SPEED := 7.5
const BOOST := 1.9
const CLIMB := 4.5
const CLEARANCE := 0.28
const MAX_ALTITUDE := 45.0
const FEED_RADIUS := 1.5
const HIVE_RADIUS := 2.8
const THIRD_DIST := 2.6

var world: World
var hud: Hud
var hive: Hive
var flowers: FlowerField
var terrain: Terrain
var camera: Camera3D
var model: BeeModel
var yaw := 0.0
var pitch := -0.15
var at_hive := false
var feeding := -1

var _cam_dist := THIRD_DIST
var _model_yaw := 0.0
var _roll := 0.0
var _t := 0.0
var _pollen_species := -1
var _pollen_source := -1
var _last_flower := -1
var _warn_cooldown := 0.0
var _full_warned := false
var _sipped_flower := -1
var _portal_cooldown := 0.0
var _particles: CPUParticles3D
var _buzz: AudioStreamPlayer
var _chime: AudioStreamPlayer
var _deliver_sound: AudioStreamWAV
var _pollinate_sound: AudioStreamWAV


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.15
	shape.shape = sphere
	add_child(shape)

	model = BeeModel.new()
	add_child(model)

	camera = Camera3D.new()
	camera.top_level = true
	camera.near = 0.02
	camera.far = 700.0
	camera.fov = 72.0
	add_child(camera)
	camera.make_current()

	_particles = CPUParticles3D.new()
	_particles.amount = 24
	_particles.lifetime = 0.9
	_particles.emitting = false
	_particles.local_coords = false
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_particles.emission_sphere_radius = 0.25
	_particles.direction = Vector3.DOWN
	_particles.spread = 70.0
	_particles.gravity = Vector3(0, -0.6, 0)
	_particles.initial_velocity_min = 0.1
	_particles.initial_velocity_max = 0.5
	_particles.mesh = Fx.glow_mesh(0.035, Color(1.4, 1.1, 0.3))
	_particles.color_ramp = Fx.fade_ramp()
	add_child(_particles)

	_buzz = AudioStreamPlayer.new()
	_buzz.stream = AudioSynth.buzz()
	_buzz.volume_db = -17.0
	_buzz.autoplay = true
	add_child(_buzz)
	_chime = AudioStreamPlayer.new()
	_chime.volume_db = -6.0
	add_child(_chime)
	_deliver_sound = AudioSynth.chime([523.25, 659.25, 783.99, 1046.5])
	_pollinate_sound = AudioSynth.chime([880.0, 1318.5], 0.08)
	_model_yaw = yaw


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look((event as InputEventMouseMotion).relative * 0.0022)
	elif event is InputEventMouseButton and event.pressed and not DisplayServer.is_touchscreen_available() \
			and hud and not hud.menu_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _look(d: Vector2) -> void:
	d *= Game.look_sensitivity
	yaw -= d.x
	pitch += d.y if Game.invert_y else -d.y
	pitch = clampf(pitch, -1.35, 1.25)


func _process(delta: float) -> void:
	_t += delta
	_warn_cooldown -= delta
	_portal_cooldown -= delta
	var controls := not (hud and hud.menu_open)
	var mv := Vector2.ZERO
	var vert := 0.0
	var boosting := false
	if controls:
		if hud:
			_look(hud.take_look() * 0.0045)
		mv = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		if hud:
			mv += Vector2(hud.joy.x, -hud.joy.y)
		mv = mv.limit_length(1.0)
		vert = Input.get_axis("descend", "ascend")
		boosting = Input.is_action_pressed("boost") and mv.length() > 0.2 and Game.energy > 0.0

	# Fly toward where the camera is looking.
	var view := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var speed := BASE_SPEED * Game.speed_multiplier() * (BOOST if boosting else 1.0)
	var exhausted := Game.energy <= 0.0
	if exhausted:
		speed *= 0.45
	var desired := (-view.z * mv.y + view.x * mv.x) * speed + Vector3.UP * vert * CLIMB
	if exhausted and vert <= 0.0:
		desired.y -= 1.0
	if feeding >= 0 and mv.length() < 0.1 and absf(vert) < 0.1:
		desired = (flowers.hover[feeding] - global_position) * 2.5 # settle onto the flower
	velocity = velocity.lerp(desired, 1.0 - exp(-4.0 * delta))
	move_and_slide()
	_constrain()

	_update_energy(delta, mv.length() > 0.1 or absf(vert) > 0.1, boosting)
	_update_feeding(delta)
	_update_hive()
	_update_model(delta)
	_update_camera(delta, boosting)
	_buzz.pitch_scale = 0.85 + velocity.length() * 0.035 + (0.15 if boosting else 0.0)
	if hud:
		hud.set_prompt(_prompt())


## Moves the bee instantly (used when going in or out of the hive).
func teleport(pos: Vector3, new_yaw: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	yaw = new_yaw
	pitch = -0.1
	_model_yaw = new_yaw
	_portal_cooldown = 1.5
	_stop_feeding()


## What the interact button would do right now: "enter", "exit", "talk" or "".
func interaction() -> String:
	if world.inside:
		if global_position.distance_to(world.interior.queen_position()) < 2.6:
			return "talk"
		if global_position.distance_to(world.interior.exit_point) < 2.5:
			return "exit"
		return ""
	return "enter" if at_hive else ""


func interact() -> void:
	match interaction():
		"enter":
			world.enter_hive()
		"exit":
			world.exit_hive()
		"talk":
			hud.open_queen()


func _constrain() -> void:
	if world.inside:
		global_position = world.interior.constrain(global_position, 0.2)
		return
	var p := global_position
	var ground := terrain.height_at(p.x, p.z)
	var floor_y := maxf(ground, Terrain.WATER_LEVEL) + CLEARANCE
	if p.y < floor_y:
		p.y = floor_y
		velocity.y = maxf(velocity.y, 0.0)
	if p.y > ground + MAX_ALTITUDE:
		p.y = ground + MAX_ALTITUDE
		velocity.y = minf(velocity.y, 0.0)
	var flat := Vector2(p.x, p.z)
	if flat.length() > Terrain.WORLD_RADIUS:
		flat = flat.limit_length(Terrain.WORLD_RADIUS)
		p.x = flat.x
		p.z = flat.y
		var out := Vector3(p.x, 0.0, p.z).normalized()
		velocity -= out * maxf(velocity.dot(out), 0.0)
		_warn("The deep woods are no place for a bee. Head back to the meadow!")
	global_position = p


func _update_energy(delta: float, moving: bool, boosting: bool) -> void:
	var drain := 0.25
	if moving:
		drain = 0.7
	if boosting:
		drain = 3.0
	if feeding >= 0:
		drain = -4.0
	if at_hive:
		drain = -45.0
	Game.energy = clampf(Game.energy - drain * delta, 0.0, Game.max_energy())
	if Game.energy <= 0.0 and Game.nectar >= 2.0:
		Game.nectar -= 2.0
		Game.energy += 20.0
		_warn("Out of energy! You sipped some of the nectar you were carrying.")
	elif Game.energy <= 0.0:
		_warn("Exhausted! Rest on a flower or fly back to the hive.")
	elif Game.energy < Game.max_energy() * 0.15 and drain > 0.0:
		_warn("Energy low. Rest on a flower or visit the hive.")


func _update_feeding(delta: float) -> void:
	flowers.set_highlight(flowers.nearest(global_position, 7.0))
	var idx := flowers.nearest(global_position, FEED_RADIUS)
	if idx < 0:
		_last_flower = -1
		_stop_feeding()
		return
	if velocity.length() > 4.5:
		_stop_feeding()
		return
	if idx != _last_flower:
		_last_flower = idx
		_try_pollinate(idx)
	var room_n := Game.nectar_capacity() - Game.nectar
	var room_p := Game.pollen_capacity() - Game.pollen
	if room_n < 0.01 and room_p < 0.01:
		_stop_feeding()
		if not _full_warned:
			_full_warned = true
			Game.message.emit("Your pouch is full! Follow the golden marker back to the hive.")
		return
	var got := flowers.take(idx, minf(room_n, 3.5 * delta), minf(room_p, 2.2 * delta))
	if got.x + got.y <= 0.0:
		_stop_feeding()
		_warn("This %s is empty. It will refill soon." % flowers.species_name(idx))
		return
	Game.nectar += got.x
	Game.pollen += got.y
	if got.x > 0.0 and idx != _sipped_flower:
		_sipped_flower = idx
		Game.quest_flower(flowers.species[idx])
	feeding = idx
	_particles.emitting = true
	if got.y > 0.0:
		_pollen_species = flowers.species[idx]
		_pollen_source = idx


func _try_pollinate(idx: int) -> void:
	if Game.pollen < 0.5 or _pollen_species != flowers.species[idx] or _pollen_source == idx:
		return
	var result := flowers.pollinate(idx)
	if result == 0:
		return
	Game.pollinated += 1
	Game.quest_event("pollinate", 1.0)
	Fx.burst(get_parent(), flowers.hover[idx], Color(2.0, 1.6, 0.5), 50, 2.5)
	_chime.stream = _pollinate_sound
	_chime.play()
	var flower := flowers.species_name(idx)
	if result == 2:
		Game.message.emit("You pollinated a %s, and a new one is sprouting nearby!" % flower)
	else:
		Game.message.emit("You pollinated a %s! It's brimming with fresh nectar." % flower)


func _stop_feeding() -> void:
	feeding = -1
	_particles.emitting = false


func _update_hive() -> void:
	if world.inside:
		at_hive = true
		if _portal_cooldown <= 0.0 and global_position.distance_to(world.interior.exit_point) < 0.9:
			world.exit_hive()
		return
	# Flying right into the entrance hole takes you inside.
	if _portal_cooldown <= 0.0 and global_position.distance_to(hive.hole) < 0.75:
		world.enter_hive()
	var dist := global_position.distance_to(hive.entrance)
	if dist < HIVE_RADIUS and not at_hive:
		at_hive = true
		_full_warned = false
		if Game.nectar + Game.pollen > 0.05:
			var d := Game.deposit()
			Game.message.emit("Delivered %d nectar and %d pollen to the hive!" % [roundi(d.x), roundi(d.y)])
			Fx.burst(get_parent(), hive.entrance, Color(2.0, 1.4, 0.3), 60, 3.0)
			_chime.stream = _deliver_sound
			_chime.play()
		else:
			Game.message.emit("Home sweet hive. Fly into the entrance to go inside.")
	elif dist > HIVE_RADIUS + 1.0 and at_hive:
		at_hive = false


func _update_model(delta: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var target := yaw
	if Game.third_person and hv.length() > 0.6:
		target = atan2(-hv.x, -hv.z)
	var prev := _model_yaw
	_model_yaw = lerp_angle(_model_yaw, target, 1.0 - exp(-7.0 * delta))
	var turn := angle_difference(prev, _model_yaw) / maxf(delta, 0.001)
	_roll = lerpf(_roll, clampf(turn * 0.18, -0.6, 0.6), 1.0 - exp(-6.0 * delta))
	var tilt := clampf(velocity.y * 0.06, -0.45, 0.45) - clampf(hv.length() * 0.025, 0.0, 0.3)
	model.rotation = Vector3(tilt, _model_yaw, _roll)
	model.position = Vector3(0.0, sin(_t * 2.6) * 0.025, 0.0)
	model.pollen_amount = Game.pollen / Game.pollen_capacity()


func _update_camera(delta: float, boosting: bool) -> void:
	var target_dist := THIRD_DIST if Game.third_person else 0.0
	_cam_dist = lerpf(_cam_dist, target_dist, 1.0 - exp(-6.0 * delta))
	var k := _cam_dist / THIRD_DIST
	var view := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var pivot := global_position + Vector3.UP * 0.18 * k
	var pos := pivot + view.z * _cam_dist + Vector3.UP * 0.25 * k
	if world.inside:
		pos = world.interior.constrain(pos, 0.1)
	if _cam_dist > 0.2:
		var query := PhysicsRayQueryParameters3D.create(pivot, pos, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			pos = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.15
	if not world.inside:
		pos.y = maxf(pos.y, maxf(terrain.height_at(pos.x, pos.z) + 0.15, Terrain.WATER_LEVEL + 0.1))
	camera.global_position = pos
	camera.global_basis = view
	var fov := (72.0 if Game.third_person else 80.0) + (10.0 if boosting else 0.0)
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-4.0 * delta))
	model.visible = _cam_dist > 0.5


func _prompt() -> String:
	if feeding >= 0:
		return "Sipping nectar from a %s..." % flowers.species_name(feeding)
	var touch := DisplayServer.is_touchscreen_available()
	match interaction():
		"talk":
			return "Queen Melissa. Tap TALK." if touch else "Queen Melissa. Press F to talk."
		"exit":
			return "Fly into the light to go outside."
		"enter":
			return "Fly into the entrance (or tap ENTER) to go inside." if touch \
				else "Fly into the entrance (or press F) to go inside. H for upgrades."
	if world.inside:
		return "Inside the hive. The Queen is in the middle."
	if Game.nectar >= Game.nectar_capacity() - 0.01:
		return "Pouch full! Follow the golden marker home."
	return ""


func _warn(text: String) -> void:
	if _warn_cooldown <= 0.0:
		_warn_cooldown = 6.0
		Game.message.emit(text)
