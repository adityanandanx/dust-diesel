extends GPUParticles3D

## Collision sparks — short burst of bright orange/yellow sparks on impact.
## Call emit_at(position) to trigger at a world position.

@export var auto_free: bool = false
const SCRAPE_AMOUNT: int = 70
const SCRAPE_LIFETIME: float = 0.22
const SCRAPE_EXPLOSIVENESS: float = 0.0
const SCRAPE_RANDOMNESS: float = 0.65
const SCRAPE_DIRECTION: Vector3 = Vector3(0, 0.6, 0)
const SCRAPE_SPREAD: float = 28.0
const SCRAPE_VELOCITY_MIN: float = 5.0
const SCRAPE_VELOCITY_MAX: float = 10.0
const SCRAPE_DAMPING_MIN: float = 1.5
const SCRAPE_DAMPING_MAX: float = 3.2
const SCRAPE_MIN_SPEED: float = 2.0
const SCRAPE_MAX_SPEED: float = 35.0
const SCRAPE_INTENSITY_MIN: float = 0.35
const SCRAPE_INTENSITY_MAX: float = 1.0

var _burst_amount: int
var _burst_lifetime: float
var _burst_explosiveness: float
var _burst_randomness: float
var _burst_direction: Vector3
var _burst_spread: float
var _burst_velocity_min: float
var _burst_velocity_max: float
var _burst_damping_min: float
var _burst_damping_max: float
var _burst_one_shot: bool
var _is_scrape_mode: bool = false
var _scrape_direction: Vector3 = Vector3(0, 0.6, 0)
var _scrape_intensity: float = 0.6


func _ready() -> void:
	emitting = false
	_cache_burst_state()
	_apply_burst_mode()


func _cache_burst_state() -> void:
	_burst_amount = amount
	_burst_lifetime = lifetime
	_burst_explosiveness = explosiveness
	_burst_randomness = randomness
	_burst_one_shot = one_shot
	var mat: ParticleProcessMaterial = process_material as ParticleProcessMaterial
	if mat:
		_burst_direction = mat.direction
		_burst_spread = mat.spread
		_burst_velocity_min = mat.initial_velocity_min
		_burst_velocity_max = mat.initial_velocity_max
		_burst_damping_min = mat.damping_min
		_burst_damping_max = mat.damping_max


func _apply_burst_mode() -> void:
	if not _is_scrape_mode:
		return
	amount = _burst_amount
	lifetime = _burst_lifetime
	one_shot = _burst_one_shot
	explosiveness = _burst_explosiveness
	randomness = _burst_randomness
	var mat: ParticleProcessMaterial = process_material as ParticleProcessMaterial
	if mat:
		mat.direction = _burst_direction
		mat.spread = _burst_spread
		mat.initial_velocity_min = _burst_velocity_min
		mat.initial_velocity_max = _burst_velocity_max
		mat.damping_min = _burst_damping_min
		mat.damping_max = _burst_damping_max
	_is_scrape_mode = false


func _apply_scrape_mode() -> void:
	if _is_scrape_mode:
		_apply_scrape_motion_to_material()
		return
	amount = SCRAPE_AMOUNT
	lifetime = SCRAPE_LIFETIME
	one_shot = false
	explosiveness = SCRAPE_EXPLOSIVENESS
	randomness = SCRAPE_RANDOMNESS
	_apply_scrape_motion_to_material()
	_is_scrape_mode = true


func _apply_scrape_motion_to_material() -> void:
	var mat: ParticleProcessMaterial = process_material as ParticleProcessMaterial
	if not mat:
		return
	mat.direction = _scrape_direction
	mat.spread = lerpf(SCRAPE_SPREAD + 8.0, SCRAPE_SPREAD - 8.0, _scrape_intensity)
	mat.initial_velocity_min = lerpf(SCRAPE_VELOCITY_MIN * 0.7, SCRAPE_VELOCITY_MIN * 1.4, _scrape_intensity)
	mat.initial_velocity_max = lerpf(SCRAPE_VELOCITY_MAX * 0.7, SCRAPE_VELOCITY_MAX * 1.35, _scrape_intensity)
	mat.damping_min = SCRAPE_DAMPING_MIN
	mat.damping_max = SCRAPE_DAMPING_MAX


## Position and trigger spark burst at the given world position.
func emit_at(pos: Vector3) -> void:
	_apply_burst_mode()
	global_position = pos
	restart()
	emitting = true
	if auto_free:
		get_tree().create_timer(lifetime + 0.2).timeout.connect(queue_free)


func set_scrape_active(active: bool, pos: Vector3 = Vector3.ZERO) -> void:
	if not active:
		emitting = false
		return
	_apply_scrape_mode()
	global_position = pos
	if not emitting:
		restart()
		emitting = true


func set_scrape_position(pos: Vector3) -> void:
	global_position = pos


func set_scrape_motion(trail_direction: Vector3, relative_speed: float) -> void:
	var dir_world: Vector3 = trail_direction.normalized()
	var dir: Vector3 = (global_basis.inverse() * dir_world).normalized()
	if dir.length() < 0.01:
		dir = SCRAPE_DIRECTION
	_scrape_direction = dir
	var t: float = inverse_lerp(SCRAPE_MIN_SPEED, SCRAPE_MAX_SPEED, maxf(relative_speed, 0.0))
	_scrape_intensity = lerpf(SCRAPE_INTENSITY_MIN, SCRAPE_INTENSITY_MAX, clampf(t, 0.0, 1.0))
	if _is_scrape_mode:
		_apply_scrape_motion_to_material()
