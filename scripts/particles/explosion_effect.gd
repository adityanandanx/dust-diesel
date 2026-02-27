extends Node3D

## Explosion effect — fire burst + smoke cloud + bright flash.
## Particle materials and draw passes are scene-authored.

@export var flash_enabled: bool = true
@export var auto_free: bool = true

var _scale_factor: float = 1.0

@onready var fire_burst: GPUParticles3D = $FireBurst
@onready var smoke_cloud: GPUParticles3D = $SmokeCloud
@onready var flash: GPUParticles3D = $Flash


func _ready() -> void:
	fire_burst.emitting = false
	smoke_cloud.emitting = false
	flash.emitting = false


## Set overall scale factor before calling explode().
## 0.6 for mines, 1.0 for barrels, 2.5 for gas stations.
func set_scale_factor(factor: float) -> void:
	_scale_factor = factor
	var particle_scale: float = maxf(0.2, factor)
	fire_burst.speed_scale = particle_scale
	smoke_cloud.speed_scale = particle_scale * 0.8
	flash.speed_scale = particle_scale * 1.2
	fire_burst.amount_ratio = minf(1.0, particle_scale)
	smoke_cloud.amount_ratio = minf(1.0, particle_scale)
	flash.amount_ratio = minf(1.0, particle_scale)


## Trigger the full explosion sequence.
func explode() -> void:
	fire_burst.restart()
	fire_burst.emitting = true
	smoke_cloud.restart()
	smoke_cloud.emitting = true
	if flash_enabled:
		flash.restart()
		flash.emitting = true

	if auto_free:
		# Free after longest particle lifetime expires
		var max_life: float = maxf(fire_burst.lifetime, maxf(smoke_cloud.lifetime, flash.lifetime))
		get_tree().create_timer(max_life + 0.5).timeout.connect(queue_free)
