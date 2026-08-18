## Стадия перевозки — ядро игры. Собирает трассу дня, ставит на неё грузовик
## и ведёт заезд до финиша.
##
## Трасса воспроизводима в пределах дня: зерно считается от номера дня,
## поэтому рестарт возвращает игрока на ту же дорогу, а не разыгрывает
## новую. Дневная кривая сложности появится позже — она будет подкручивать
## параметры сборщика, а не трогать эту стадию.
extends Node2D

## Заезд идёт по фазам: сперва игрок грузит машину руками, потом едет,
## потом смотрит итог. Управление, камера и интерфейс смотрят на фазу.
enum Phase {
	LOADING,   ## товар лежит на земле, машина стоит
	DRIVING,   ## заезд
	FINISHED,  ## финиш пройден
}

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

## Зазор между предметами при выкладке товара на землю.
const CARGO_GAP: float = 10.0
## Подъём над опорой при спавне: тело не должно родиться внутри геометрии.
const CARGO_LIFT: float = 2.0
## Откуда начинается выкладка товара — впереди машины, чтобы не упираться
## в левый край стартовой площадки.
const GROUND_OFFSET_X: float = 240.0
## Куда смотрит камера при погрузке: середина между кузовом и товаром.
const LOADING_CAMERA_OFFSET: Vector2 = Vector2(320.0, -100.0)
## Насколько высоко над полом кузова вещь ещё считается погруженной.
## Щедро: стопка выше бортов — это перегруз, а не «мимо кузова».
const BED_CAPACITY_HEIGHT: float = 400.0

@onready var _track: TrackBuilder = $Track
@onready var _truck: Truck = $Truck
@onready var _camera: Camera2D = $Camera2D
@onready var _cargo_root: Node2D = $CargoRoot
@onready var _status_label: Label = $HUD/StatusPanel/StatusLabel
@onready var _finish_panel: PanelContainer = $HUD/FinishPanel
@onready var _result_label: Label = $HUD/FinishPanel/VBoxContainer/ResultLabel
@onready var _to_shop_button: Button = $HUD/FinishPanel/VBoxContainer/ToShopButton
@onready var _start_panel: PanelContainer = $HUD/StartPanel
@onready var _start_button: Button = $HUD/StartPanel/VBoxContainer/StartButton

var _phase: Phase = Phase.LOADING
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
	_start_button.pressed.connect(_start_run)
	_track.finish_reached.connect(_on_finish_reached)
	_build_track()
	_place_truck()
	_unload_to_ground()
	_enter_loading()


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


## Выкладка товара со склада на землю перед машиной. Класть позади нельзя:
## задний борт стоит почти вплотную к левому краю стартовой площадки.
## Ряд уезжает вправо — туда, куда грузовик поедет уже без этих вещей.
func _unload_to_ground() -> void:
	var items := _resolve_cargo()
	if items.is_empty():
		return
	var start := _track.get_start_position()
	# Земля стартовой площадки — уровень входа трассы, а машина стоит
	# приподнятой над ним на высоту подвески.
	var ground_y := _track.global_position.y
	var cursor_x := start.x + GROUND_OFFSET_X
	for data: ItemData in items:
		var rect := data.get_bounds()
		# Полигон задан относительно начала координат узла, и оно не обязано
		# лежать в центре силуэта. Поэтому ставим не узел, а грани: левую —
		# на курсор, нижнюю — на землю.
		var at := Vector2(
			cursor_x - rect.position.x,
			ground_y - CARGO_LIFT - rect.end.y)
		Destruction.spawn_item(data, _cargo_root, at)
		cursor_x += rect.size.x + CARGO_GAP


func _enter_loading() -> void:
	_phase = Phase.LOADING
	_truck.controls_enabled = false
	_finish_panel.hide()
	_start_panel.show()


## Старт заезда: то, что лежит в кузове, едет; остальное возвращается
## на склад и ждёт следующего дня.
func _start_run() -> void:
	if _phase != Phase.LOADING:
		return
	_loaded.clear()
	var left_behind: Array[StringName] = []
	for node in _cargo_root.get_children():
		var item := node as BreakableItem
		if item == null:
			continue
		if _is_in_bed(item):
			_loaded[item.instance_id] = item.data.id
		else:
			left_behind.append(item.data.id)
			item.queue_free()
	GameState.cargo_actual = left_behind

	_phase = Phase.DRIVING
	_truck.controls_enabled = true
	_start_panel.hide()


## Вещь считается погруженной, если её центр внутри кузова по длине
## и выше пола. Проверяем в координатах рамы, поэтому наклон машины
## на подвеске ответа не меняет.
func _is_in_bed(item: Node2D) -> bool:
	if _truck.chassis == null:
		return false
	var local := _truck.chassis.to_local(item.global_position)
	var bed := _truck.get_bed_bounds()
	if local.x < bed.x or local.x > bed.y:
		return false
	return local.y <= Truck.BED_FLOOR_Y and local.y >= Truck.BED_FLOOR_Y - BED_CAPACITY_HEIGHT


## Идентификаторы груза превращаем в описания предметов один раз на заезд.
func _resolve_cargo() -> Array[ItemData]:
	var items: Array[ItemData] = []
	for id: StringName in GameState.cargo_actual:
		var data := ItemCatalog.get_by_id(id)
		if data != null:
			items.append(data)
	return items


func _update_camera(delta: float) -> void:
	if _truck.chassis == null:
		return
	if _phase == Phase.LOADING:
		# При погрузке камера стоит: в кадре и кузов, и разложенный товар.
		_camera.global_position = _truck.chassis.global_position + LOADING_CAMERA_OFFSET
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
	if _phase == Phase.LOADING:
		var in_bed := 0
		var on_ground := 0
		for node in _cargo_root.get_children():
			var item := node as BreakableItem
			if item == null:
				continue
			if _is_in_bed(item):
				in_bed += 1
			else:
				on_ground += 1
		_status_label.text = "День %d · Погрузка\nВ кузове: %d · На земле: %d" % [
			GameState.get_day(), in_bed, on_ground,
		]
		return
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
	if _phase != Phase.DRIVING:
		return
	_phase = Phase.FINISHED
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
