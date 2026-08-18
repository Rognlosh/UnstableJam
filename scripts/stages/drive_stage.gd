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
## Где стоит стеллаж — впереди машины: позади неё стартовая площадка
## кончается почти сразу за задним бортом.
const SHELF_OFFSET_X: float = 420.0
## Полезная длина полки. Узкий стеллаж растёт вверх, а не вширь: так он
## занимает меньше места рядом с машиной и целиком влезает в кадр.
const SHELF_WIDTH: float = 380.0
const SHELF_BOARD_THICKNESS: float = 16.0
## Высота нижней полки над землёй. Подобрана под пол кузова: товар лежит
## на одном уровне с ним, и тащить его надо вбок, а не задирать вверх.
const SHELF_BASE_HEIGHT: float = 100.0
## Зазор между вещью и полкой над ней.
const SHELF_CLEARANCE: float = 48.0
const SHELF_COLOR: Color = Color(0.42, 0.33, 0.24)
## Высота яруса у пустого стеллажа — когда мерить не по чему.
const SHELF_EMPTY_LEVEL: float = 70.0

## Насколько резво вещь догоняет курсор. Больше — цепче хват и сильнее
## удары о борта; меньше — вещь вязнет и отстаёт от мыши.
const DRAG_GAIN: float = 14.0
## Потолок скорости переноски. Без него рывок мышью через полэкрана
## запустил бы вазу сквозь борт быстрее, чем физика успеет заметить.
const DRAG_MAX_SPEED: float = 1400.0
## Скорость поворота на Q/E и стрелках, рад/с.
const ROTATE_SPEED: float = 3.0
## Во сколько раз товар прочнее на погрузке. Швырнуть вазу об борт всё ещё
## можно, а вот уронить её с полки — уже не смертельно.
const LOADING_TOUGHNESS: float = 1.25
## С какой скоростью вещь выпускается из руки: остаток разгона гасим,
## иначе отпущенная на замахе ваза улетает через весь кузов.
const RELEASE_MAX_SPEED: float = 260.0
## Куда смотрит камера при погрузке: середина между кузовом и стеллажом.
const LOADING_CAMERA_OFFSET: Vector2 = Vector2(360.0, -60.0)
## Приближение камеры на погрузке и в заезде. Больше — ближе.
const LOADING_ZOOM: float = 0.85
const DRIVE_ZOOM: float = 0.7
## Сколько длится переход от погрузки к заезду.
const TRANSITION_TIME: float = 0.8
## До какой прозрачности гаснут стеллаж и оставленный товар.
const GHOST_ALPHA: float = 0.3
## Слой, на который они уходят: за всё остальное.
const GHOST_Z: int = -10

## Запас вокруг видимой области, в пределах которого выпавший на финише
## товар всё ещё считается доехавшим: докатившееся до финиша вместе с машиной
## разумно считать привезённым, а не потерянным.
const RECOVERY_MARGIN: float = 1.0
## Запас вокруг стеллажа, в пределах которого вещь считается прибранной.
const SHELF_ZONE_MARGIN: float = 60.0
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
@onready var _hint_label: Label = $HUD/StartPanel/VBoxContainer/HintLabel
@onready var _restart_button: HoldButton = $HUD/RestartButton

var _phase: Phase = Phase.LOADING
## Текущий вынос камеры вперёд. Держим отдельно, чтобы сглаживать его
## самим, а не гонять камеру за шумом мгновенной скорости.
var _look_ahead: float = 0.0

## Что было погружено: instance_id → идентификатор предмета. По этому
## списку финиш поймёт, чего недосчитался: живые тела на финише знают
## свой instance_id, а исходный состав груза известен только отсюда.
var _loaded: Dictionary = {}

## Стеллаж существует только на время погрузки: заезд идёт сквозь то место,
## где он стоит, поэтому на старте он уезжает вместе с непогруженным товаром.
var _shelf: Node2D = null

## Вещь в руке и точка, за которую её держат, в её собственных координатах.
## Держим именно за точку захвата, а не за центр: иначе вещь прыгает
## центром под курсор в момент клика.
var _dragged: BreakableItem = null
var _grab_offset: Vector2 = Vector2.ZERO

## Переход камеры от погрузки к заезду: 0 — стоит и смотрит на стеллаж,
## 1 — едет за машиной. Твинится при старте, поэтому смена ракурса
## и приближения идёт одним плавным движением.
var _camera_blend: float = 0.0

## Погасшие декорации прошлой погрузки. Держим список, чтобы снести их
## при сбросе: машина возвращается ровно туда, где они лежат.
var _ghosts: Array[Node2D] = []

## Курсор укладки на стеллаж. Живёт в полях, потому что на стеллаж кладут
## дважды: сперва товар со склада, потом то, что вернулось из кузова.
var _shelf_left: float = 0.0
var _shelf_ground: float = 0.0
var _shelf_cursor: float = 0.0
var _shelf_level: int = 0
var _shelf_level_height: float = 0.0


func _ready() -> void:
	_finish_panel.hide()
	_to_shop_button.pressed.connect(_on_to_shop_pressed)
	_start_button.pressed.connect(_start_run)
	_restart_button.hold_completed.connect(_restart_run)
	_restart_button.hide()
	_track.finish_reached.connect(_on_finish_reached)
	_build_track()
	_place_truck()
	_unload_to_shelf()
	_enter_loading()


## Камера обновляется в физическом такте, а не в кадровом. Тела двигаются
## ровно раз в физкадр, и если вести камеру по кадрам, машина каждый кадр
## оказывается в чуть другом месте относительно неё — картинка расслаивается,
## особенно на контрастных деталях вроде кабины.
func _physics_process(delta: float) -> void:
	if _phase == Phase.LOADING:
		_update_drag()
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


## Выкладка на стеллаж перед машиной: сперва товар со склада, следом то,
## что вернулось из кузова при сбросе. На полу ряд быстро упёрся бы в длину
## площадки, поэтому стеллаж растёт ярусами вверх.
func _unload_to_shelf(returned: Array[BreakableItem] = []) -> void:
	var items := _resolve_cargo()

	# Шаг яруса считаем по самой высокой вещи партии: единый шаг читается
	# лучше, чем полки на разной высоте, и мелочь не теряется под нависшей
	# доской.
	var level_height := 0.0
	for data: ItemData in items:
		level_height = maxf(level_height, data.get_bounds().size.y)
	for item: BreakableItem in returned:
		level_height = maxf(level_height, item.get_local_bounds().size.y)
	# Пустой стеллаж всё равно строим: на него нужно класть осколки,
	# иначе с разбитой вазой на руках заезд будет не начать.
	if level_height <= 0.0:
		level_height = SHELF_EMPTY_LEVEL

	_shelf_begin(level_height + SHELF_CLEARANCE)

	for data: ItemData in items:
		var rect := data.get_bounds()
		var slot := _shelf_reserve(rect.size)
		# Полигон задан относительно начала координат узла, и оно не обязано
		# лежать в центре силуэта. Поэтому ставим не узел, а грани: левую —
		# на курсор, нижнюю — на полку.
		var at := Vector2(slot.x - rect.position.x, slot.y - CARGO_LIFT - rect.end.y)
		var item := Destruction.spawn_item(data, _cargo_root, at)
		item.toughness_bonus = LOADING_TOUGHNESS

	for item: BreakableItem in returned:
		# Ставим ровно: вещь на полке лежит как товар, а не как её бросили.
		item.rotation = 0.0
		var rect := item.get_local_bounds()
		var slot := _shelf_reserve(rect.size)
		item.place_at(Transform2D(0.0, Vector2(
			slot.x - rect.position.x,
			slot.y - CARGO_LIFT - rect.end.y)))
		item.toughness_bonus = LOADING_TOUGHNESS

	_add_posts(_shelf_left, _shelf_ground, _shelf_level, _shelf_level_height)


func _shelf_begin(level_height: float) -> void:
	_shelf = Node2D.new()
	add_child(_shelf)
	_shelf_ground = _track.global_position.y
	_shelf_left = _track.get_start_position().x + SHELF_OFFSET_X
	_shelf_cursor = _shelf_left
	_shelf_level = 0
	_shelf_level_height = level_height
	_add_board(_shelf_left, _level_y(_shelf_ground, 0, _shelf_level_height))


## Отводит место под вещь указанного размера и возвращает левый нижний угол
## этого места. Когда ряд кончился, поднимается ярусом выше и кладёт доску.
func _shelf_reserve(item_size: Vector2) -> Vector2:
	# Условие про непустой ряд спасает от вечного переноса вещи,
	# которая шире всей полки.
	if _shelf_cursor + item_size.x > _shelf_left + SHELF_WIDTH and _shelf_cursor > _shelf_left:
		_shelf_level += 1
		_shelf_cursor = _shelf_left
		_add_board(_shelf_left, _level_y(_shelf_ground, _shelf_level, _shelf_level_height))
	var slot := Vector2(_shelf_cursor, _level_y(_shelf_ground, _shelf_level, _shelf_level_height))
	_shelf_cursor += item_size.x + CARGO_GAP
	return slot


## Высота верхней грани полки указанного яруса.
static func _level_y(ground_y: float, level: int, level_height: float) -> float:
	return ground_y - SHELF_BASE_HEIGHT - float(level) * level_height


## Доска яруса: настоящее статическое тело, товар на ней именно лежит.
func _add_board(left_x: float, top_y: float) -> void:
	var board := StaticBody2D.new()
	board.position = Vector2(
		left_x + SHELF_WIDTH * 0.5,
		top_y + SHELF_BOARD_THICKNESS * 0.5)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(SHELF_WIDTH, SHELF_BOARD_THICKNESS)
	shape.shape = rect
	board.add_child(shape)

	var visual := Polygon2D.new()
	visual.polygon = _rect_polygon(rect.size)
	visual.color = SHELF_COLOR
	board.add_child(visual)

	_shelf.add_child(board)


## Боковые стойки — только вид. Коллизии у них нет намеренно: они бы
## мешали вытаскивать вещи с крайних мест.
func _add_posts(left_x: float, ground_y: float, levels: int, level_height: float) -> void:
	var height := SHELF_BASE_HEIGHT + float(levels) * level_height + SHELF_BOARD_THICKNESS
	for x: float in [left_x - 8.0, left_x + SHELF_WIDTH + 8.0]:
		var post := Polygon2D.new()
		post.polygon = _rect_polygon(Vector2(12.0, height))
		post.color = SHELF_COLOR
		post.position = Vector2(x, ground_y - height * 0.5)
		_shelf.add_child(post)


## Прямоугольник вокруг начала координат — форма и для полок, и для стоек.
static func _rect_polygon(size: Vector2) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])


## Клик мышью в фазе погрузки — взять или отпустить вещь.
func _unhandled_input(event: InputEvent) -> void:
	if _phase != Phase.LOADING:
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_grab_at(get_global_mouse_position())
	else:
		_release()


## Ищем тело точно под курсором. Запрос к физике, а не перебор детей:
## попадание считается по настоящей форме, поэтому щель между вазами
## не считается попаданием ни в одну из них.
func _grab_at(at: Vector2) -> void:
	var params := PhysicsPointQueryParameters2D.new()
	params.position = at
	params.collide_with_bodies = true
	for hit in get_world_2d().direct_space_state.intersect_point(params, 8):
		var item := hit.get("collider") as BreakableItem
		if item == null:
			continue
		_dragged = item
		_grab_offset = item.to_local(at)
		# В руке вещь не падает: гравитация тянула бы её вниз, и курсор
		# всё время держал бы её с перекосом.
		item.gravity_scale = 0.0
		# Непрерывная проверка столкновений — страховка от проскакивания
		# сквозь борт на быстром движении мыши.
		item.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
		return


func _release() -> void:
	if _dragged == null:
		return
	if is_instance_valid(_dragged):
		_dragged.gravity_scale = 1.0
		_dragged.continuous_cd = RigidBody2D.CCD_MODE_DISABLED
		_dragged.linear_velocity = _dragged.linear_velocity.limit_length(RELEASE_MAX_SPEED)
		_dragged.angular_velocity = 0.0
	_dragged = null


## Вещь тянется к курсору скоростью, а не телепортом: так она честно
## упирается в борта и в соседний груз, вместо того чтобы проходить сквозь.
func _update_drag() -> void:
	if _dragged == null:
		return
	if not is_instance_valid(_dragged) or not _dragged.is_inside_tree():
		_dragged = null
		return
	var held := _dragged.to_global(_grab_offset)
	var pull := (get_global_mouse_position() - held) * DRAG_GAIN
	# Через drive_velocity, а не напрямую: наш собственный разгон не должен
	# засчитываться вещи как удар, а гашение о борт — должно.
	_dragged.drive_velocity(pull.limit_length(DRAG_MAX_SPEED))
	_dragged.angular_velocity = Input.get_axis(&"rotate_ccw", &"rotate_cw") * ROTATE_SPEED


func _enter_loading() -> void:
	_phase = Phase.LOADING
	_camera_blend = 0.0
	_restart_button.hide()
	_truck.controls_enabled = false
	_truck.set_frozen(true)
	_finish_panel.hide()
	_start_panel.show()


## Старт заезда: то, что лежит в кузове, едет; остальное возвращается
## на склад и ждёт следующего дня.
func _start_run() -> void:
	if _phase != Phase.LOADING:
		return
	if _count_stray() > 0:
		return
	_release()
	_loaded.clear()
	var left_behind: Array[StringName] = []
	for node in _cargo_root.get_children():
		var item := node as BreakableItem
		if item == null:
			continue
		if _is_in_bed(item):
			# С этого момента поблажка кончается — заезд начался.
			item.toughness_bonus = 1.0
			_loaded[item.instance_id] = item.data.id
		elif item.level == 0:
			# На склад возвращается только целая вещь. У осколка тот же
			# идентификатор, что у целой вазы, и запись его в склад
			# размножала бы товар: разбил на четыре куска — получил
			# четыре вазы.
			left_behind.append(item.data.id)
			# Из группы убираем сразу: иначе оставленный товар продолжал бы
			# считаться грузом в счётчике заезда.
			item.remove_from_group(&"cargo")
			_make_ghost(item)
		else:
			# Осколкам места на складе нет: хранить их негде, представления
			# для битого товара в состоянии игры пока не существует.
			item.remove_from_group(&"cargo")
			_make_ghost(item)
	GameState.cargo_actual = left_behind

	if _shelf != null:
		_make_ghost(_shelf)
		_shelf = null

	_camera_blend = 0.0
	var tween := create_tween()
	tween.tween_property(self, "_camera_blend", 1.0, TRANSITION_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_phase = Phase.DRIVING
	_truck.set_frozen(false)
	_truck.controls_enabled = true
	_truck.auto_brake = false
	_start_panel.hide()
	_restart_button.show()


## Сброс заезда: машина и всё, что осталось при ней, возвращаются на старт,
## и снова открывается погрузка.
##
## Груз не пересоздаётся, а переносится вместе с машиной тем же сдвигом:
## уложенное остаётся уложенным, а осколки не приходится собирать заново
## из каталога. Что не попало в кадр — то отстало и списывается.
func _restart_run() -> void:
	if _phase != Phase.DRIVING:
		return
	_release()

	# Запоминаем положение рамы ДО телепорта: груз поедет тем же
	# преобразованием, что и она.
	var was := _truck.chassis.global_transform
	# Уложенное едет с машиной как есть, выпавшее возвращается на стеллаж —
	# осколки в том числе, иначе они остались бы валяться у старта.
	var in_bed: Array[BreakableItem] = []
	var returned: Array[BreakableItem] = []
	for node in _cargo_root.get_children():
		var item := node as BreakableItem
		if item == null:
			continue
		if _is_in_bed(item):
			in_bed.append(item)
		elif _is_recovered(item):
			returned.append(item)
		else:
			item.queue_free()

	# Декорации прошлой погрузки лежат ровно там, куда мы возвращаемся.
	for ghost: Node2D in _ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	_ghosts.clear()

	# Зерно то же, поэтому дорога та же — но разгребённая галька
	# и раскиданные препятствия встают на место.
	_track.build()
	_truck.teleport_to(_track.get_start_position())

	# Не сдвиг, а полное преобразование: если машина лежала на боку, груз
	# обязан выпрямиться вместе с ней, иначе он окажется поперёк кузова
	# и распихает борта изнутри.
	var relocate := _truck.chassis.global_transform * was.affine_inverse()
	for item: BreakableItem in in_bed:
		item.place_at(relocate * item.global_transform)
		item.toughness_bonus = LOADING_TOUGHNESS

	# Склад снова под рукой: непогруженное можно доложить.
	_unload_to_shelf(returned)
	_enter_loading()


## Стеллаж и брошенный товар не исчезают в момент старта — это читалось бы
## как сбой. Вместо этого они гаснут, уходят на дальний слой и остаются
## декорацией, сквозь которую машина спокойно проезжает.
func _make_ghost(node: Node2D) -> void:
	_ghosts.append(node)
	node.z_index = GHOST_Z
	_disable_collisions(node)
	var tween := create_tween()
	tween.tween_property(node, "modulate:a", GHOST_ALPHA, TRANSITION_TIME)


## Снимает тело с учёта физики целиком, вместе с детьми: обнулённые слои
## гарантируют, что машина не заденет призрак, даже задев его геометрию.
func _disable_collisions(node: Node) -> void:
	var body := node as CollisionObject2D
	if body != null:
		body.collision_layer = 0
		body.collision_mask = 0
		var rigid := node as RigidBody2D
		if rigid != null:
			rigid.freeze = true
	for child in node.get_children():
		_disable_collisions(child)


## Зона стеллажа: сами полки и пол под ними. Вещь, оставленная здесь,
## считается прибранной — в отличие от той, что валяется посреди площадки.
func _is_on_shelf(item: Node2D) -> bool:
	if _shelf == null:
		return false
	var pos := item.global_position
	if pos.x < _shelf_left - SHELF_ZONE_MARGIN:
		return false
	if pos.x > _shelf_left + SHELF_WIDTH + SHELF_ZONE_MARGIN:
		return false
	var top := _level_y(_shelf_ground, _shelf_level, _shelf_level_height) - _shelf_level_height
	return pos.y >= top and pos.y <= _shelf_ground + SHELF_ZONE_MARGIN


## Сколько вещей брошено мимо кузова и мимо стеллажа.
func _count_stray() -> int:
	var stray := 0
	for node in _cargo_root.get_children():
		var item := node as BreakableItem
		if item == null:
			continue
		if not _is_in_bed(item) and not _is_on_shelf(item):
			stray += 1
	return stray


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
	var wanted := clampf(
		_truck.chassis.linear_velocity.x * CAMERA_LOOK_FACTOR,
		-CAMERA_LOOK_AHEAD, CAMERA_LOOK_AHEAD)
	# На кочках мгновенная скорость скачет каждый физкадр. Без сглаживания
	# вынос дёргался бы вслед за этим шумом сильнее, чем едет сама машина.
	_look_ahead = lerpf(_look_ahead, wanted, clampf(delta * CAMERA_LOOK_SMOOTH, 0.0, 1.0))

	# Обе точки считаем всегда и смешиваем: на старте заезда это даёт
	# плавный отъезд вместо мгновенной смены ракурса.
	var chassis_at := _truck.chassis.global_position
	var loading_at := chassis_at + LOADING_CAMERA_OFFSET
	var driving_at := chassis_at + Vector2(_look_ahead, CAMERA_LIFT)
	_camera.global_position = loading_at.lerp(driving_at, _camera_blend)
	var zoom := lerpf(LOADING_ZOOM, DRIVE_ZOOM, _camera_blend)
	_camera.zoom = Vector2(zoom, zoom)


func _update_status() -> void:
	if _phase == Phase.LOADING:
		var in_bed := 0
		var on_shelf := 0
		var stray := 0
		for node in _cargo_root.get_children():
			var item := node as BreakableItem
			if item == null:
				continue
			if _is_in_bed(item):
				in_bed += 1
			elif _is_on_shelf(item):
				on_shelf += 1
			else:
				stray += 1
		# Пока что-то валяется мимо кузова и мимо стеллажа, выехать нельзя:
		# брошенная вещь всё равно никуда не денется, а решать её судьбу
		# молча за игрока — хуже, чем попросить прибраться.
		_start_button.disabled = stray > 0
		_hint_label.text = (
			"Убери с земли: %d" % stray if stray > 0
			else "Тащи мышью · Q/E или стрелки — поворот")
		_status_label.text = "День %d · Погрузка\nВ кузове: %d · На стеллаже: %d" % [
			GameState.get_day(), in_bed, on_shelf,
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
	# Руль отбираем сразу, и машина сама гасит ход: накатом она уехала бы
	# за кадр, пока игрок читает итог.
	_truck.controls_enabled = false
	_truck.auto_brake = true
	_restart_button.hide()
	GameState.run_result = _collect_result()
	_result_label.text = "ФИНИШ\nДоехало целыми: %d\nПовреждено: %d\nПотеряно: %d" % [
		GameState.run_result["delivered"],
		GameState.run_result["damaged"],
		GameState.run_result["lost"],
	]
	_finish_panel.show()


## Итог заезда: сколько ценности доехало.
##
## Считаем по тому, что реально приехало, а не по журналу потерь: обходим
## живые тела и складываем их доли цены в копилку своего предмета. Целое
## тело даёт единицу, осколок — свою долю со скидкой. Чего не хватило —
## то и потеряно, отдельно это отслеживать не нужно.
func _collect_result() -> Dictionary:
	var ratios: Dictionary = {}
	for node in _cargo_root.get_children():
		var item := node as BreakableItem
		if item == null or not _loaded.has(item.instance_id):
			continue
		if not _is_recovered(item):
			continue
		var current: float = ratios.get(item.instance_id, 0.0)
		ratios[item.instance_id] = current + item.value_ratio()

	var items: Array = []
	var delivered := 0
	var damaged := 0
	var lost := 0
	var total_ratio := 0.0
	for instance_id: int in _loaded:
		var ratio: float = clampf(ratios.get(instance_id, 0.0), 0.0, 1.0)
		total_ratio += ratio
		var state := &"lost"
		if is_equal_approx(ratio, 1.0):
			state = &"delivered"
			delivered += 1
		elif ratio > 0.0:
			state = &"damaged"
			damaged += 1
		else:
			lost += 1
		items.append({
			"id": _loaded[instance_id],
			"ratio": ratio,
			"state": state,
		})

	return {
		"items": items,
		"delivered": delivered,
		"damaged": damaged,
		"lost": lost,
		"total": _loaded.size(),
		"value_ratio": total_ratio,
	}


## Доехавшим считается то, что лежит в кузове или хотя бы осталось в кадре
## вместе с машиной: вазу, вывалившуюся у самого финиша, честнее подобрать,
## чем списать.
func _is_recovered(item: BreakableItem) -> bool:
	if _is_in_bed(item):
		return true
	var half := get_viewport_rect().size * 0.5 / _camera.zoom * RECOVERY_MARGIN
	var offset := item.global_position - _camera.global_position
	return absf(offset.x) <= half.x and absf(offset.y) <= half.y


func _on_to_shop_pressed() -> void:
	StageManager.instance.change_stage(StageManager.Stage.SELL)
