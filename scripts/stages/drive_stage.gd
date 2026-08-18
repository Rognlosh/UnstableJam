## Стадия перевозки — ядро игры. Собирает трассу дня, ставит на неё грузовик
## и ведёт заезд до финиша.
##
## Трасса воспроизводима в пределах дня: зерно считается от номера дня,
## поэтому рестарт возвращает игрока на ту же дорогу, а не разыгрывает
## новую. Дневная кривая сложности появится позже — она будет подкручивать
## параметры сборщика, а не трогать эту стадию.
extends Node2D

## Множитель зерна. Простое число, чтобы соседние дни давали
## непохожие трассы, а не сдвинутые версии одной.
const SEED_STEP: int = 7919

## Насколько камера уходит вперёд по ходу движения на полном ходу.
const CAMERA_LOOK_AHEAD: float = 240.0
## Доля скорости, которая превращается в этот вынос камеры.
const CAMERA_LOOK_FACTOR: float = 0.35
## Подъём камеры над рамой: смотреть интереснее на дорогу, а не на кабину.
const CAMERA_LIFT: float = -80.0

@onready var _track: TrackBuilder = $Track
@onready var _truck: Truck = $Truck
@onready var _camera: Camera2D = $Camera2D
@onready var _cargo_root: Node2D = $CargoRoot
@onready var _status_label: Label = $HUD/StatusPanel/StatusLabel
@onready var _finish_panel: PanelContainer = $HUD/FinishPanel
@onready var _result_label: Label = $HUD/FinishPanel/VBoxContainer/ResultLabel
@onready var _to_shop_button: Button = $HUD/FinishPanel/VBoxContainer/ToShopButton

var _is_finished: bool = false


func _ready() -> void:
	_finish_panel.hide()
	_to_shop_button.pressed.connect(_on_to_shop_pressed)
	_track.finish_reached.connect(_on_finish_reached)
	_build_track()
	_place_truck()


func _process(_delta: float) -> void:
	_update_camera()
	_update_status()


func _build_track() -> void:
	_track.randomize_seed_on_build = false
	_track.track_seed = GameState.get_day() * SEED_STEP
	_track.build()


## Грузовик ставится на стартовую площадку до первого шага физики,
## поэтому телепорт не даёт рывка.
func _place_truck() -> void:
	_truck.teleport_to(_track.get_start_position())
	_update_camera()
	# Сглаживание камеры хорошо в движении и мешает на старте: без сброса
	# первый кадр камера едет из начала координат к грузовику.
	_camera.reset_smoothing()


func _update_camera() -> void:
	if _truck.chassis == null:
		return
	var target := _truck.chassis.global_position
	var look_ahead := _truck.chassis.linear_velocity.x * CAMERA_LOOK_FACTOR
	target.x += clampf(look_ahead, -CAMERA_LOOK_AHEAD, CAMERA_LOOK_AHEAD)
	target.y += CAMERA_LIFT
	_camera.global_position = target


func _update_status() -> void:
	_status_label.text = "День %d · Груз: %d · Пройдено: %d%%" % [
		GameState.get_day(),
		GameState.cargo_actual.size(),
		int(round(get_progress() * 100.0)),
	]


## Доля пройденной трассы, 0..1. Считается по X рамы между стартовой
## точкой и выходом последнего куска.
func get_progress() -> float:
	if _truck.chassis == null:
		return 0.0
	var start_x := _track.get_start_position().x
	var span := _track.get_end_position().x - start_x
	if span <= 0.0:
		return 0.0
	return clampf((_truck.chassis.global_position.x - start_x) / span, 0.0, 1.0)


func _on_finish_reached() -> void:
	if _is_finished:
		return
	_is_finished = true
	_result_label.text = "ФИНИШ\nПодсчёт груза появится следующим шагом."
	_finish_panel.show()


func _on_to_shop_pressed() -> void:
	# Формат результата заезда пока прежний — его переберём вместе
	# с подсчётом довезённой ценности.
	GameState.run_result = {
		"delivered": 0,
		"broken": 0,
		"lost": 0,
	}
	StageManager.instance.change_stage(StageManager.Stage.SELL)
