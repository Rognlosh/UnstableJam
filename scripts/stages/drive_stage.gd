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
## Скорость, с которой вынос камеры догоняет своё расчётное значение.
const CAMERA_LOOK_SMOOTH: float = 3.0

## Зазор между предметами и до бортов при укладке.
const CARGO_GAP: float = 6.0
## Подъём над полом кузова: предмет не должен родиться внутри рамы.
const CARGO_LIFT: float = 2.0

@onready var _track: TrackBuilder = $Track
@onready var _truck: Truck = $Truck
@onready var _camera: Camera2D = $Camera2D
@onready var _cargo_root: Node2D = $CargoRoot
@onready var _status_label: Label = $HUD/StatusPanel/StatusLabel
@onready var _finish_panel: PanelContainer = $HUD/FinishPanel
@onready var _result_label: Label = $HUD/FinishPanel/VBoxContainer/ResultLabel
@onready var _to_shop_button: Button = $HUD/FinishPanel/VBoxContainer/ToShopButton

var _is_finished: bool = false
## Текущий вынос камеры вперёд. Держим отдельно, чтобы сглаживать его
## самим, а не гонять камеру за шумом мгновенной скорости.
var _look_ahead: float = 0.0

## Что было погружено: instance_id → идентификатор предмета. По этому
## списку финиш поймёт, чего недосчитался: живые тела на финише знают
## свой instance_id, а исходный состав груза известен только отсюда.
var _loaded: Dictionary = {}


func _ready() -> void:
	_finish_panel.hide()
	_to_shop_button.pressed.connect(_on_to_shop_pressed)
	_track.finish_reached.connect(_on_finish_reached)
	_build_track()
	_place_truck()
	_load_cargo()


## Камера обновляется в физическом такте, а не в кадровом. Тела двигаются
## ровно раз в физкадр, и если вести камеру по кадрам, машина каждый кадр
## оказывается в чуть другом месте относительно неё — картинка расслаивается,
## особенно на контрастных деталях вроде кабины.
func _physics_process(delta: float) -> void:
	_update_camera(delta)


func _process(_delta: float) -> void:
	_update_status()


func _build_track() -> void:
	_track.randomize_seed_on_build = false
	_track.track_seed = GameState.get_day() * SEED_STEP
	_track.build()


## Грузовик ставится на стартовую площадку до первого шага физики,
## поэтому телепорт не даёт рывка.
func _place_truck() -> void:
	_truck.teleport_to(_track.get_start_position())
	_look_ahead = 0.0
	_update_camera(1.0)


## Погрузка: предметы кладутся рядами вдоль кузова, ряд заполняется слева
## направо, следующий ложится поверх предыдущего.
##
## Шаг укладки считается от габаритов каждого предмета, а не берётся
## постоянным: груз бывает разного размера, и постоянный шаг либо оставит
## дыры, либо посадит крупные вещи друг в друга.
func _load_cargo() -> void:
	_loaded.clear()
	var items := _resolve_cargo()
	if items.is_empty():
		return
	# Крупное вниз: мелочь под крупной вещью работает как каток.
	items.sort_custom(_by_height_desc)

	var bed := _truck.get_bed_bounds()
	var row_end := bed.y - CARGO_GAP
	var cursor_x := bed.x + CARGO_GAP
	var row_top := Truck.BED_FLOOR_Y - CARGO_LIFT
	var row_height := 0.0

	for data: ItemData in items:
		var rect := data.get_bounds()
		# Ряд кончился — начинаем следующий поверх уложенного. Проверка на
		# непустой ряд спасает от вечного переноса вещи шире самого кузова.
		if cursor_x + rect.size.x > row_end and row_height > 0.0:
			cursor_x = bed.x + CARGO_GAP
			row_top -= row_height + CARGO_GAP
			row_height = 0.0
		# Полигон задан относительно начала координат узла, и оно не обязано
		# лежать в центре силуэта. Поэтому ставим не узел, а грани: левую —
		# на курсор, нижнюю — на уровень ряда.
		var local := Vector2(cursor_x - rect.position.x, row_top - rect.end.y)
		var item := Destruction.spawn_item(data, _cargo_root, _truck.chassis.to_global(local))
		_loaded[item.instance_id] = data.id
		cursor_x += rect.size.x + CARGO_GAP
		row_height = maxf(row_height, rect.size.y)


## Идентификаторы груза превращаем в описания предметов один раз на заезд.
func _resolve_cargo() -> Array[ItemData]:
	var items: Array[ItemData] = []
	for id: StringName in GameState.cargo_actual:
		var data := ItemCatalog.get_by_id(id)
		if data != null:
			items.append(data)
	return items


static func _by_height_desc(a: ItemData, b: ItemData) -> bool:
	return a.get_bounds().size.y > b.get_bounds().size.y


func _update_camera(delta: float) -> void:
	if _truck.chassis == null:
		return
	var wanted := clampf(
		_truck.chassis.linear_velocity.x * CAMERA_LOOK_FACTOR,
		-CAMERA_LOOK_AHEAD, CAMERA_LOOK_AHEAD)
	# На кочках мгновенная скорость скачет каждый физкадр. Без сглаживания
	# вынос дёргался бы вслед за этим шумом сильнее, чем едет сама машина.
	_look_ahead = lerpf(_look_ahead, wanted, clampf(delta * CAMERA_LOOK_SMOOTH, 0.0, 1.0))
	var target := _truck.chassis.global_position
	target.x += _look_ahead
	target.y += CAMERA_LIFT
	_camera.global_position = target


func _update_status() -> void:
	# В кузове считаем целые предметы: осколки лежат в той же группе,
	# но местом груза уже не являются.
	var whole := 0
	for node in get_tree().get_nodes_in_group(&"cargo"):
		var item := node as BreakableItem
		if item != null and item.level == 0:
			whole += 1
	_status_label.text = "День %d · Цело: %d из %d · Пройдено: %d%%" % [
		GameState.get_day(),
		whole,
		_loaded.size(),
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
