class_name World
extends Node3D
## Builds the world, runs the day/night cycle and ambience, and moves the bee
## between the meadow and the inside of the hive.

const DAY_LENGTH := 600.0 # seconds for a full day (nights pass three times faster)

const DAY_TOP := Color(0.26, 0.48, 0.86)
const DAY_HORIZON := Color(0.72, 0.84, 0.95)
const SUNSET_TOP := Color(0.28, 0.32, 0.62)
const SUNSET_HORIZON := Color(1.0, 0.62, 0.36)
const NIGHT_TOP := Color(0.015, 0.025, 0.07)
const NIGHT_HORIZON := Color(0.07, 0.09, 0.17)

var terrain: Terrain
var vegetation: Vegetation
var flowers: FlowerField
var hive: Hive
var bee: Bee
var hud: Hud
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var interior: HiveInterior
var home: NewHome
var swarm: Swarm
var time_of_day := 0.3
var night := 0.0
var inside := false

var _outside: Node3D
var _transition := false
var _wind: AudioStreamPlayer

var _workers: Array[WorkerBee] = []
var _water_mat: ShaderMaterial
var _motes: CPUParticles3D
var _fireflies: CPUParticles3D
var _sky_timer := 0.0
var _cloud_offset := 0.0
var _bird: AudioStreamPlayer
var _bird_timer := 4.0
var _shot_path := ""
var _shot_timer := 0.0


func _ready() -> void:
	var view := _parse_args()
	_setup_environment()

	_outside = Node3D.new()
	add_child(_outside)
	terrain = Terrain.new()
	_outside.add_child(terrain)
	_build_water()
	vegetation = Vegetation.new()
	vegetation.terrain = terrain
	_outside.add_child(vegetation)
	flowers = FlowerField.new()
	flowers.terrain = terrain
	flowers.vegetation = vegetation
	_outside.add_child(flowers)
	hive = Hive.new()
	hive.terrain = terrain
	_outside.add_child(hive)
	home = NewHome.new()
	home.terrain = terrain
	_outside.add_child(home)
	interior = HiveInterior.new()
	add_child(interior)

	bee = Bee.new()
	bee.world = self
	bee.terrain = terrain
	bee.flowers = flowers
	bee.hive = hive
	bee.position = hive.entrance + Vector3(1.8, 0.9, 5.5)
	bee.yaw = 0.3
	if view.has("pos"):
		bee.position = view["pos"]
	if view.has("yaw"):
		bee.yaw = view["yaw"]
	if view.has("pitch"):
		bee.pitch = view["pitch"]
	add_child(bee)

	swarm = Swarm.new()
	swarm.leader = bee
	swarm.home = home.hole
	swarm.home_front = home.front
	swarm.rally = hive.entrance + Vector3(0.0, 3.0, 2.0)
	_outside.add_child(swarm)
	swarm.settled.connect(_on_swarm_settled)
	if Game.swarms > 0:
		swarm.idle()

	hud = Hud.new()
	hud.bee = bee
	hud.hive = hive
	add_child(hud)
	bee.hud = hud

	_build_ambience()
	Game.changed.connect(_sync_workers)
	Game.settings_changed.connect(apply_quality)
	Game.season_started.connect(_on_season_started)
	_sync_workers()
	apply_quality()
	_update_day(0.0)
	if view.has("inside"):
		_go_inside()
		if view.has("pos"):
			bee.teleport(view["pos"], view.get("yaw", 0.0))
			bee.pitch = view.get("pitch", -0.1)


func enter_hive() -> void:
	if inside or _transition:
		return
	_transition = true
	hud.fade(func() -> void:
		_go_inside()
		_transition = false)


func exit_hive() -> void:
	if not inside or _transition:
		return
	_transition = true
	hud.fade(func() -> void:
		inside = false
		interior.set_active(false)
		_outside.visible = true
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.fog_enabled = true
		_wind.volume_db = -22.0
		bee.teleport(hive.entrance + Vector3(0.0, 0.2, 1.6), PI)
		_sky_timer = 0.0
		_update_day(0.0)
		_transition = false)


func _go_inside() -> void:
	inside = true
	_outside.visible = false
	interior.set_active(true)
	sun.visible = false
	moon.visible = false
	_fireflies.emitting = false
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.025, 0.01)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.85, 0.65)
	env.ambient_light_energy = 0.4
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = false
	_wind.volume_db = -40.0
	bee.teleport(interior.spawn_point, 0.0)
	Game.message.emit("Welcome home! Queen Melissa is waiting in the middle of the hive.")


func _process(delta: float) -> void:
	_update_day(delta)
	_update_swarm()
	_motes.global_position = bee.camera.global_position
	var bp := bee.global_position
	_fireflies.global_position = Vector3(bp.x, terrain.height_at(bp.x, bp.z) + 1.5, bp.z)
	vegetation.grass_material.set_shader_parameter("bee_position", bp)

	_bird_timer -= delta
	if _bird_timer <= 0.0:
		_bird_timer = randf_range(4.0, 11.0)
		if night < 0.3 and not inside:
			_bird.pitch_scale = randf_range(0.8, 1.25)
			_bird.volume_db = randf_range(-26.0, -18.0)
			_bird.play()

	if _shot_path != "":
		_shot_timer += delta
		if _shot_timer > 4.0:
			get_viewport().get_texture().get_image().save_png(_shot_path)
			get_tree().quit()


func _update_swarm() -> void:
	home.set_beacon(Game.swarm_phase == Game.Swarm.SCOUT or Game.swarm_phase == Game.Swarm.LEAD)
	if inside:
		return
	var p := bee.global_position
	match Game.swarm_phase:
		Game.Swarm.SCOUT:
			if p.distance_to(home.front) < 8.0:
				Game.swarm_phase = Game.Swarm.GATHER
				Game.message.emit("What a perfect home! Fly back to the hive and the swarm will follow you here.")
				Game.save_game()
		Game.Swarm.GATHER:
			if p.distance_to(hive.entrance) < 7.0:
				Game.swarm_phase = Game.Swarm.LEAD
				swarm.launch(hive.entrance)
				Game.message.emit("Here comes the swarm! Lead them to the hollow oak.")
		Game.Swarm.LEAD:
			if p.distance_to(home.front) < 8.0:
				Game.swarm_phase = Game.Swarm.SETTLE
				swarm.settle()
				Game.message.emit("The swarm is moving into its new home...")


func _on_swarm_settled() -> void:
	Game.swarm_phase = Game.Swarm.DONE
	Game.swarms += 1
	Game.save_game()
	Fx.burst(self, home.front, Color(2.0, 1.6, 0.5), 80, 4.0)
	hud.show_win()


func _on_season_started() -> void:
	for w in _workers:
		w.queue_free()
	_workers.clear()


func apply_quality() -> void:
	var hq := Game.high_quality
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_2X if hq else Viewport.MSAA_DISABLED
	vp.scaling_3d_scale = 1.0 if hq else 0.75
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if hq \
		else DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0 if hq else 40.0
	vegetation.set_density(1.0 if hq else 0.5)
	flowers.set_shadows(hq)


func _sync_workers() -> void:
	while _workers.size() < int(Game.levels["workers"]):
		var w := WorkerBee.new()
		w.flowers = flowers
		w.hive = hive
		w.terrain = terrain
		w.position = hive.entrance + Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(0.5, 2.0))
		_outside.add_child(w)
		_workers.append(w)


## Optional command-line flags (after --) used to grab screenshots while developing.
func _parse_args() -> Dictionary:
	var view := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=")
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"--shot":
				_shot_path = value
				Game.seen_intro = true
			"--time":
				time_of_day = value.to_float()
			"--first-person":
				Game.third_person = false
			"--pos":
				var v := value.split_floats(",")
				view["pos"] = Vector3(v[0], v[1], v[2])
			"--yaw":
				view["yaw"] = value.to_float()
			"--pitch":
				view["pitch"] = value.to_float()
			"--inside":
				view["inside"] = true
			"--swarm":
				Game.stage = Game.STAGES.size()
				Game.swarm_phase = value.to_int()
			"--honey":
				Game.honey = value.to_float()
				Game.hive_pollen = value.to_float() * 0.4
	return view


func _setup_environment() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("cloud_noise", Fx.noise_texture(0.012, 512, false, 11))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 35.0
	env.fog_depth_end = 250.0
	env.fog_depth_curve = 1.4
	env.fog_density = 1.0
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.05
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.shadow_enabled = false
	add_child(moon)


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * Terrain.POND_RADIUS * 2.8
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://shaders/water.gdshader")
	_water_mat.set_shader_parameter("wave_a", Fx.noise_texture(0.02, 256, true, 3))
	_water_mat.set_shader_parameter("wave_b", Fx.noise_texture(0.035, 256, true, 8))
	_water_mat.set_shader_parameter("pond_center", Terrain.POND_CENTER)
	_water_mat.set_shader_parameter("pond_radius", Terrain.POND_RADIUS)
	var water := MeshInstance3D.new()
	water.mesh = plane
	water.material_override = _water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(Terrain.POND_CENTER.x, Terrain.WATER_LEVEL, Terrain.POND_CENTER.y)
	_outside.add_child(water)


func _build_ambience() -> void:
	# Drifting specks of pollen in the air around the camera.
	_motes = CPUParticles3D.new()
	_motes.amount = 70
	_motes.lifetime = 9.0
	_motes.preprocess = 9.0
	_motes.local_coords = false
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(14, 6, 14)
	_motes.direction = Vector3(1, 0.2, 0)
	_motes.spread = 180.0
	_motes.gravity = Vector3(0, 0.02, 0)
	_motes.initial_velocity_min = 0.05
	_motes.initial_velocity_max = 0.25
	_motes.scale_amount_min = 0.5
	_motes.scale_amount_max = 1.2
	_motes.mesh = Fx.glow_mesh(0.04, Color(1.0, 0.95, 0.75, 0.6))
	_motes.color_ramp = Fx.fade_ramp()
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_motes)

	# Fireflies come out at night.
	_fireflies = CPUParticles3D.new()
	_fireflies.amount = 50
	_fireflies.lifetime = 6.0
	_fireflies.local_coords = false
	_fireflies.emitting = false
	_fireflies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_fireflies.emission_box_extents = Vector3(24, 2.5, 24)
	_fireflies.spread = 180.0
	_fireflies.gravity = Vector3.ZERO
	_fireflies.initial_velocity_min = 0.1
	_fireflies.initial_velocity_max = 0.5
	_fireflies.mesh = Fx.glow_mesh(0.14, Color(1.8, 2.2, 0.6))
	_fireflies.color_ramp = Fx.fade_ramp()
	_fireflies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fireflies)

	_wind = AudioStreamPlayer.new()
	_wind.stream = AudioSynth.wind()
	_wind.volume_db = -22.0
	_wind.autoplay = true
	add_child(_wind)
	_bird = AudioStreamPlayer.new()
	_bird.stream = AudioSynth.chirp()
	add_child(_bird)


func _update_day(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / DAY_LENGTH * (3.0 if night > 0.5 else 1.0), 1.0)
	var ang := (time_of_day - 0.25) * TAU
	var sun_dir := Vector3(cos(ang), sin(ang), 0.35).normalized().rotated(Vector3.UP, 0.6)
	var elev := sun_dir.y
	var day := smoothstep(-0.12, 0.2, elev)
	night = 1.0 - day
	var golden := (1.0 - smoothstep(0.05, 0.4, elev)) * smoothstep(-0.15, 0.02, elev)
	if inside:
		return

	sun.basis = Basis.looking_at(-sun_dir, Vector3.UP)
	sun.light_energy = 1.7 * smoothstep(-0.05, 0.15, elev)
	sun.light_color = Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.55, 0.3), golden)
	sun.visible = elev > -0.05
	moon.basis = Basis.looking_at(sun_dir, Vector3.UP)
	moon.light_energy = 0.35 * night
	moon.visible = night > 0.02

	var top := DAY_TOP.lerp(SUNSET_TOP, golden).lerp(NIGHT_TOP, night)
	var horizon := DAY_HORIZON.lerp(SUNSET_HORIZON, golden).lerp(NIGHT_HORIZON, night)
	env.fog_light_color = horizon
	env.ambient_light_energy = lerpf(0.35, 1.0, day)

	_fireflies.emitting = night > 0.35
	flowers.set_night(night)
	hive.set_night(night)

	_cloud_offset += delta * 0.0015
	_sky_timer -= delta
	if _sky_timer <= 0.0:
		_sky_timer = 0.25
		sky_mat.set_shader_parameter("top_color", top)
		sky_mat.set_shader_parameter("horizon_color", horizon)
		sky_mat.set_shader_parameter("ground_color", horizon.lerp(Color(0.3, 0.35, 0.25), 0.5) * day)
		sky_mat.set_shader_parameter("sun_dir", sun_dir)
		sky_mat.set_shader_parameter("sun_color", sun.light_color)
		sky_mat.set_shader_parameter("night", night)
		sky_mat.set_shader_parameter("cloud_offset", _cloud_offset)
		sky_mat.set_shader_parameter("cloud_light", Color(1, 1, 1).lerp(Color(1.0, 0.75, 0.55), golden).lerp(Color(0.12, 0.13, 0.2), night))
		sky_mat.set_shader_parameter("cloud_shade", Color(0.62, 0.68, 0.8).lerp(Color(0.6, 0.42, 0.45), golden).lerp(Color(0.05, 0.06, 0.1), night))
		_water_mat.set_shader_parameter("sky_color", horizon)
