class_name Truck
extends Node2D

## Грузовик: рама (Chassis) с кабиной и бортами кузова, два ведущих колеса
## на пружинной подвеске.
##
## На каждое колесо — пара суставов:
##   GrooveJoint2D       — направляющая: задаёт ход и держит колесо на линии;
##   DampedSpringJoint2D — собственно пружина с демпфером.
##
## ВАЖНО ПРО ЯКОРЯ. Оба сустава вычисляют точку крепления на колесе как
## «начало координат узла + length вдоль его локальной оси Y», и делают это
## один раз, в момент создания сустава. Отсюда два следствия:
##   1) В сцене колесо стоит ровно на расстоянии length от своего сустава,
##      иначе пружина зацепится не за центр колеса, а за точку рядом с ним.
##   2) Суставы лежат ДЕТЬМИ Chassis, чтобы их трансформ ездил вместе с рамой
##      и повторная сборка якорей оставалась корректной.
##
## Что можно крутить на ходу: stiffness, damping, rest_length — они уходят
## прямо в физический сервер и якоря не трогают.
## Что нельзя: length сустава и длину паза — они пересобирают якоря по текущему
## положению узлов, а на ходу колесо сжато. Для апгрейдов есть
## rebuild_suspension(), её зовут между заездами, когда машина стоит.

@export_group("Подвеска")

## Сила пружины на пиксель сжатия. Свою массу грузовик держит
## на просадке ~12 px, поэтому счёт идёт на тысячи, а не на дефолтные 20.
@export_range(200.0, 8000.0, 10.0) var suspension_stiffness: float = 2900.0:
	set(value):
		suspension_stiffness = maxf(0.0, value)
		_push_spring_params()

## Гашение колебаний. 0 — пружина скачет бесконечно.
@export_range(0.0, 8.0, 0.1) var suspension_damping: float = 1.5:
	set(value):
		suspension_damping = maxf(0.0, value)
		_push_spring_params()

## Свободная длина пружины: расстояние «крепление на раме — центр колеса»,
## при котором пружина не давит вообще.
@export_range(24.0, 80.0, 0.5) var suspension_rest_length: float = 46.0:
	set(value):
		suspension_rest_length = maxf(1.0, value)
		_push_spring_params()

## Ход сжатия в пикселях: насколько колесо может подняться к раме.
@export_range(8.0, 60.0, 1.0) var suspension_travel: float = 30.0:
	set(value):
		suspension_travel = maxf(1.0, value)

@export_group("Мотор")

## Момент на каждое колесо при газе.
@export_range(20000.0, 2000000.0, 10000.0) var motor_torque: float = 450000.0
## Момент при торможении (газ против текущего вращения) — сильнее тяги.
@export_range(20000.0, 2000000.0, 10000.0) var brake_torque: float = 600000.0
## Потолок раскрутки колеса, рад/с. При радиусе 28 px даёт ~24 * 28 px/с.
@export_range(4.0, 60.0, 0.5) var max_wheel_speed: float = 24.0

@export_group("Наклон")

## Момент, которым A/D крутят раму.
@export_range(50000.0, 4000000.0, 10000.0) var lean_torque: float = 1800000.0

@export_group("Кузов")

## Высота бортов над полом кузова. Прокачиваемый параметр:
## 64 — первый уровень, дальше выше.
@export_range(24.0, 200.0, 2.0) var bed_wall_height: float = 64.0:
	set(value):
		bed_wall_height = maxf(8.0, value)
		_apply_bed_walls()

## Коллизии бортов. Визуал каждого борта берётся из его же детей,
## поэтому перетащить надо только сами коллизии. Порядок неважен.
@export var bed_walls: Array[CollisionShape2D] = []

## Уровень пола кузова в координатах рамы — верхняя грань рамы.
const BED_FLOOR_Y: float = -18.0
## Толщина борта.
const BED_WALL_THICKNESS: float = 8.0

## Запас паза на отбой: чтобы колесо не упиралось в конец направляющей,
## когда машина в воздухе и пружина полностью разжата.
const REBOUND_SLACK: float = 4.0

## Пока выключено, грузовик не реагирует на клавиши. Нужно фазе погрузки:
## машина обязана стоять, пока игрок укладывает груз.
var controls_enabled: bool = true

## Машина сама гасит ход. Нужно финишу: отобрать руль мало, накатом
## грузовик уедет за кадр, пока игрок читает итог.
var auto_brake: bool = false

## Шаг гашения скорости за физкадр. Мягкий: резкая остановка швырнула бы
## груз в передний борт уже после того, как он честно доехал.
const BRAKE_LINEAR_STEP: float = 14.0
const BRAKE_SPIN_STEP: float = 0.6

var chassis: RigidBody2D
var _wheels: Array[RigidBody2D] = []
var _springs: Array[DampedSpringJoint2D] = []
var _grooves: Array[GrooveJoint2D] = []


func _ready() -> void:
	_collect_parts()
	_push_spring_params()
	_apply_bed_walls()


func _physics_process(_delta: float) -> void:
	if chassis == null:
		return
	if auto_brake:
		_brake_to_stop()
		return
	if not controls_enabled:
		return
	# get_axis(отрицательное_действие, положительное_действие) → -1..1.
	# W даёт +1, S даёт -1; A даёт -1, D даёт +1.
	var throttle := Input.get_axis(&"brake", &"accelerate")
	var lean := Input.get_axis(&"lean_left", &"lean_right")

	_drive(throttle)
	if not is_zero_approx(lean):
		chassis.apply_torque(lean * lean_torque)


func _drive(throttle: float) -> void:
	if is_zero_approx(throttle):
		return
	for wheel: RigidBody2D in _wheels:
		var spin := wheel.angular_velocity
		# За потолком скорости момент не подаём: иначе колесо просто буксует.
		if absf(spin) >= max_wheel_speed and spin * throttle > 0.0:
			continue
		# Газ против текущего вращения — это торможение, оно резче тяги.
		var is_braking := spin * throttle < 0.0
		wheel.apply_torque(throttle * (brake_torque if is_braking else motor_torque))


## Плавная остановка: скорость и вращение сводим к нулю шагами, а не
## обнулением. Груз в кузове воспринимает это как обычное торможение.
func _brake_to_stop() -> void:
	chassis.linear_velocity = chassis.linear_velocity.move_toward(
		Vector2.ZERO, BRAKE_LINEAR_STEP)
	chassis.angular_velocity = move_toward(chassis.angular_velocity, 0.0, 0.1)
	for wheel: RigidBody2D in _wheels:
		wheel.angular_velocity = move_toward(wheel.angular_velocity, 0.0, BRAKE_SPIN_STEP)
		wheel.linear_velocity = wheel.linear_velocity.move_toward(
			Vector2.ZERO, BRAKE_LINEAR_STEP)


## Ищем части грузовика по типу, а не по именам: узлы в сцене можно
## переименовывать и переставлять, скрипт от этого не сломается.
func _collect_parts() -> void:
	chassis = null
	_wheels.clear()
	_springs.clear()
	_grooves.clear()

	for child in get_children():
		var body := child as RigidBody2D
		if body == null:
			continue
		# Рама — та, внутри которой висят суставы подвески.
		if _has_joints(body):
			chassis = body
		else:
			_wheels.append(body)

	if chassis == null:
		push_error("Truck: не найдена рама — RigidBody2D с суставами подвески внутри")
		return

	for child in chassis.get_children():
		if child is DampedSpringJoint2D:
			_springs.append(child)
		elif child is GrooveJoint2D:
			_grooves.append(child)

	# Единый порядок для всех трёх массивов: сначала заднее колесо
	# (меньший X), потом переднее. По нему get_compression() и сопоставляет
	# пружину с её колесом.
	_wheels.sort_custom(_by_x)
	_springs.sort_custom(_by_x)
	_grooves.sort_custom(_by_x)

	if _wheels.size() != 2 or _springs.size() != 2 or _grooves.size() != 2:
		push_error(
			"Truck: ожидались 2 колеса, 2 DampedSpringJoint2D и 2 GrooveJoint2D, "
			+ "найдено %d / %d / %d" % [_wheels.size(), _springs.size(), _grooves.size()]
		)


func _has_joints(body: RigidBody2D) -> bool:
	for child in body.get_children():
		if child is Joint2D:
			return true
	return false


## sort_custom принимает Callable, возвращающий true, если a должно идти раньше b.
static func _by_x(a: Node2D, b: Node2D) -> bool:
	return a.position.x < b.position.x


## Перестраивает борта под текущую высоту: обе стенки растут от пола кузова
## вверх, поэтому правило одинаковое для задней и передней.
## Передняя стенка стоит внутри габарита кабины — так кузов не теряет длину,
## а при высоте больше кабины над крышей появляется «шапка», как у настоящих
## грузовиков с высоким передком.
func _apply_bed_walls() -> void:
	if bed_walls.is_empty():
		return

	for wall: CollisionShape2D in bed_walls:
		if wall == null:
			continue
		# Форма создаётся заново, а не правится на месте: если борт копировали
		# дублированием узла, RectangleShape2D у обоих общий, и правка одного
		# молча меняла бы второй.
		var rect := RectangleShape2D.new()
		rect.size = Vector2(BED_WALL_THICKNESS, bed_wall_height)
		wall.shape = rect
		wall.position.y = BED_FLOOR_Y - bed_wall_height * 0.5

		# Визуал — ребёнок самой коллизии, поэтому едет за ней и координаты
		# задаются в одном месте.
		for child in wall.get_children():
			var visual := child as DebugShape
			if visual == null:
				continue
			visual.kind = DebugShape.Kind.RECTANGLE
			visual.size = rect.size
			visual.position = Vector2.ZERO


## Внутренние границы кузова по X, в координатах рамы: x — задняя стенка,
## y — передняя. Отсюда стадия погрузки узнает, куда класть товар.
func get_bed_bounds() -> Vector2:
	var xs: Array[float] = []
	for wall: CollisionShape2D in bed_walls:
		if wall != null:
			xs.append(wall.position.x)
	if xs.size() < 2:
		return Vector2.ZERO
	xs.sort()
	var half := BED_WALL_THICKNESS * 0.5
	return Vector2(xs[0] + half, xs[xs.size() - 1] - half)


## Текущее сжатие пружин в пикселях: x — заднее колесо, y — переднее.
func get_compression() -> Vector2:
	var values := Vector2.ZERO
	for i in mini(_springs.size(), 2):
		var distance := _springs[i].global_position.distance_to(_wheels[i].global_position)
		values[i] = suspension_rest_length - distance
	return values


func get_speed() -> float:
	return chassis.linear_velocity.length() if chassis != null else 0.0


## Пересобирает геометрию направляющих под текущие rest_length и travel.
## Звать ТОЛЬКО когда грузовик стоит (между заездами, после апгрейда):
## сустав заново считает якоря по текущему положению узлов.
func rebuild_suspension() -> void:
	for i in _grooves.size():
		# Точка крепления на раме — это позиция пружинного сустава.
		var anchor: Vector2 = _springs[i].position
		_grooves[i].position = anchor + Vector2(
			0.0, suspension_rest_length - suspension_travel
		)
		_grooves[i].length = suspension_travel + REBOUND_SLACK
		_grooves[i].initial_offset = suspension_travel


## Замораживает машину целиком. Нужно фазе погрузки: незамороженную раму
## груз растолкает, и она уедет со стартовой площадки сама.
## Замороженное тело ведёт себя как статическое, поэтому груз на нём лежит.
func set_frozen(value: bool) -> void:
	if chassis == null:
		return
	chassis.freeze = value
	for wheel: RigidBody2D in _wheels:
		wheel.freeze = value
	if value:
		return
	# После разморозки гасим скорости: за время погрузки в них могло
	# накопиться то, чего игрок не делал.
	chassis.linear_velocity = Vector2.ZERO
	chassis.angular_velocity = 0.0
	for wheel: RigidBody2D in _wheels:
		wheel.linear_velocity = Vector2.ZERO
		wheel.angular_velocity = 0.0


## Телепорт без физических артефактов: рама встаёт ровно в указанную точку,
## колёса — в своё проектное положение под пружинами.
##
## Двигать колёса тем же сдвигом, что и раму, нельзя. Если машина была
## наклонена, их «прежнее место» относительно выпрямленной рамы оказывается
## сбоку от неё: подвеска растягивается на пол-экрана, и машина разваливается.
## Поэтому колесо ставится не «как было», а туда, где ему положено быть —
## на длину свободной пружины ниже своего сустава.
func teleport_to(target: Vector2) -> void:
	if chassis == null:
		return
	_place_body(chassis, target)

	for i in _wheels.size():
		var wheel := _wheels[i]
		# Считаем от целевой точки, а не через chassis.to_global(): позицию
		# рамы мы задали прямо сейчас, и читать её обратно в этом же кадре
		# нельзя — вернулось бы место, где машина была до телепорта.
		var at := target + Vector2(0.0, suspension_rest_length)
		if i < _springs.size():
			at = target + _springs[i].position + Vector2(0.0, suspension_rest_length)
		elif i < _grooves.size():
			at = target + _grooves[i].position + Vector2(0.0, suspension_rest_length)
		_place_body(wheel, at)
	# Пазы здесь НЕ пересобираем. rebuild_suspension() заставляет суставы
	# заново считать якоря по положению тел в физическом сервере, а оно
	# в этом кадре ещё старое: якоря встанут по воздуху, машина развалится
	# на месте и выстрелит вверх, когда пружина разожмётся.


## Переставляет тело и в дереве, и в физическом сервере.
##
## Одного присваивания global_position мало: у RigidBody2D состояние живёт
## в сервере, и он вернёт тело обратно на ближайшем шаге. Рама этого не
## показывала только потому, что её сразу замораживали, а колёса оставались
## там, откуда уехали.
static func _place_body(body: RigidBody2D, at: Vector2) -> void:
	var xform := Transform2D(0.0, at)
	body.global_transform = xform
	var rid := body.get_rid()
	PhysicsServer2D.body_set_state(rid, PhysicsServer2D.BODY_STATE_TRANSFORM, xform)
	PhysicsServer2D.body_set_state(rid, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2.ZERO)
	PhysicsServer2D.body_set_state(rid, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, 0.0)


func _push_spring_params() -> void:
	if _springs.is_empty():
		return
	for spring: DampedSpringJoint2D in _springs:
		spring.stiffness = suspension_stiffness
		spring.damping = suspension_damping
		spring.rest_length = suspension_rest_length
