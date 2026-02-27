extends Resource
class_name VehicleData

## Metadata for a single driveable vehicle.

@export var id: String = ""
@export var display_name: String = ""

## Used to spawn the car in the game
@export var scene_path: String = ""

## Used ONLY for the rotating 3D preview in the selection menu
@export var preview_model_path: String = ""
@export var wheel_path: String = "res://assets/models/cars/wheel-default.glb"

## Base stats used ONLY for rendering the UI bars in VehicleSelection
@export_group("UI Stats")
@export var ui_speed: float = 50.0
@export var ui_armor: float = 50.0
@export var ui_weight: float = 50.0
