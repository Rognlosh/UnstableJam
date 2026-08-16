class_name Truck
extends Node2D

## Грузовик: рама (Chassis) и два ведущих колеса на пружинной подвеске.
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
@export_range(200.0, 8000.0, 10.0) var suspension_stiffness: float = 2300.0:
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
@export_range(20000.0, 1500000.0, 10000.0) var motor_torque: float = 350000.0
## Момент при торможении (газ против текущего вращения) — сильнее тяги.
@export_range(20000.0, 1500000.0, 10000.0) var brake_torque: float = 500000.0
## Потолок раскрутки колеса, рад/с. При радиусе 28 px даёт ~24 * 28 px/с.
@export_range(4.0, 60.0, 0.5) var max_wheel_speed: float = 24.0

@export_group("Наклон")

## Момент, которым A/D крутят раму.
@export_range(50000.0, 3000000.0, 10000.0) var lean_torque: float = 900000.0

## Запас паза на отбой: чтобы колесо не упиралось в конец направляющей,
## когда машина в воздухе и пружина полностью разжата.
const REBOUND_SLACK: float = 4.0

var chassis: RigidBody2D
var _wheels: Array[RigidBody2D] = []
var _springs: Array[DampedSpringJoint2D] = []
var _grooves: Array[GrooveJoint2D] = []


func _ready() -> void:
	_collect_parts()
	_push_spring_params()
	
## Ищем части грузовика по типу, а не по именам: узлы в сцене можно
## переименовывать и переставлять, скрипт от этого не сломается.
func _collect_parts() -> void:
	chassis = null
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


func _physics_process(_delta: float) -> void:
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


## Текущее сжатие пружин в пикселях: x — заднее колесо, y — переднее.
func get_compression() -> Vector2:
	var values := Vector2.ZERO
	for i in _springs.size():
		var distance := _springs[i].global_position.distance_to(_wheels[i].global_position)
		values[i] = suspension_rest_length - distance
	return values


func get_speed() -> float:
	return chassis.linear_velocity.length()


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


## Телепорт без физических артефактов — для кнопки «сброс» на стенде.
func teleport_to(target: Vector2) -> void:
	var delta := target - chassis.global_position
	chassis.rotation = 0.0
	chassis.global_position += delta
	chassis.linear_velocity = Vector2.ZERO
	chassis.angular_velocity = 0.0
	for wheel: RigidBody2D in _wheels:
		wheel.global_position += delta
		wheel.linear_velocity = Vector2.ZERO
		wheel.angular_velocity = 0.0


func _push_spring_params() -> void:
	if _springs.is_empty():
		return
	for spring: DampedSpringJoint2D in _springs:
		spring.stiffness = suspension_stiffness
		spring.damping = suspension_damping
		spring.rest_length = suspension_rest_length
