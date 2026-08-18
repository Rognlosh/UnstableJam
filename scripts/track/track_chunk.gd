@tool
class_name TrackChunk
extends Node2D

## Кусок трассы — самостоятельная сцена с куском профиля дороги.
##
## Контракт стыковки: контур поверхности начинается ровно в точке (0, 0)
## и обязан содержать точку (length, exit_offset_y). Сборщик ставит вход
## следующего куска ровно в выход предыдущего, поэтому нарушение контракта
## даёт разрыв дороги. Чтобы такое ловилось до запуска, кусок сам проверяет
## себя в редакторе и жалуется значком предупреждения в дереве сцены.
##
## Крайние ~40 px куска держим ровными: стык двух отдельных цепочек сегментов
## на изломе — место, где колесо цепляется за «призрачное» ребро.

## Длина куска по X. На эту величину сборщик сдвигает следующий кусок.
@export var length: float = 800.0:
	set(value):
		length = value
		if is_node_ready():
			update_configuration_warnings()

## Насколько выход выше или ниже входа. Y растёт вниз, поэтому
## отрицательное значение — подъём, положительное — спуск.
@export var exit_offset_y: float = 0.0:
	set(value):
		exit_offset_y = value
		if is_node_ready():
			update_configuration_warnings()

## Насколько кусок злой: 0 — ровное место, 3 — испытание.
## Сборщик пускает тяжёлые куски только ближе к финишу.
@export_range(0, 3) var difficulty: int = 0

## Вес при случайной выборке среди кусков, прошедших отбор по сложности.
@export_range(0.0, 10.0, 0.1) var weight: float = 1.0


## Можно ли растягивать кусок по вертикали. У кочек и ям — да, у моста
## из досок или у куска с точной геометрией стыка масштаб выключается.
@export var allow_height_scale: bool = true

var _body: StaticBody2D
var _outline: CollisionPolygon2D
var _fill: Polygon2D


func _ready() -> void:
	_collect_nodes()
	_sync_fill()
	# Тянуть заливку за контуром нужно только пока его рисуют мышью.
	# В игре это мёртвый груз, поэтому процесс включаем лишь в редакторе.
	set_process(Engine.is_editor_hint())
	update_configuration_warnings()


func _process(_delta: float) -> void:
	_sync_fill()


## Точка выхода в локальных координатах куска.
func get_exit_position() -> Vector2:
	return Vector2(length, exit_offset_y)


## Трение и упругость дороги задаёт сборщик — одним значением на всю трассу,
## чтобы «скользкий дождь» позже менялся в одном месте, а не в двадцати сценах.
func apply_physics_material(surface: PhysicsMaterial) -> void:
	if _body == null:
		_collect_nodes()
	if _body != null:
		_body.physics_material_override = surface
		

## Растягивает профиль по вертикали. Зовёт сборщик, уже добавив кусок
## в дерево: правим точки полигона, а не scale узла — масштаб на теле
## физики Godot переносит плохо, а точки перестраивают форму честно.
func apply_height_scale(factor: float) -> void:
	if not allow_height_scale or is_equal_approx(factor, 1.0):
		return
	if _outline == null:
		_collect_nodes()
	if _outline == null:
		return
	var points := _outline.polygon
	for i in points.size():
		points[i] = Vector2(points[i].x, points[i].y * factor)
	_outline.polygon = points
	# Выход куска тоже уезжает — иначе следующий кусок встанет не туда.
	exit_offset_y *= factor
	_sync_fill()

## Сборщик выдаёт куску зерно перед тем, как растягивать его по высоте.
## Куски с нарисованной геометрией зерно игнорируют, параметрические —
## строят по нему свой профиль.
func apply_seed(_value: int) -> void:
	pass


## Опускает низ куска до общего для всей трассы уровня. Договорённость:
## две последние точки контура — это юбка, у всех кусков одинаково.
## Без этого днища кусков с разной высотой расходятся ступеньками
## и в кадре появляются дырки в толще земли.
func set_skirt_bottom(local_y: float) -> void:
	if _outline == null:
		_collect_nodes()
	if _outline == null:
		return
	var points := _outline.polygon
	var count := points.size()
	if count < 4:
		return
	points[count - 2] = Vector2(points[count - 2].x, local_y)
	points[count - 1] = Vector2(points[count - 1].x, local_y)
	_outline.polygon = points
	_sync_fill()

## Узлы ищем по типу, а не по именам: имена в редакторе меняются,
## смысл — нет. Это общее правило проекта.
func _collect_nodes() -> void:
	_body = null
	_outline = null
	_fill = null
	for child in get_children():
		if child is StaticBody2D:
			_body = child
			break
	if _body == null:
		return
	for child in _body.get_children():
		if child is CollisionPolygon2D and _outline == null:
			_outline = child
		elif child is Polygon2D and _fill == null:
			_fill = child


func _sync_fill() -> void:
	if _outline == null or _fill == null:
		return
	if _fill.polygon != _outline.polygon:
		_fill.polygon = _outline.polygon


## Godot зовёт этот метод сам и рисует жёлтый треугольник у узла в дереве.
## Аналога в C#-мире нет — это редакторная валидация, в игре не выполняется.
func _get_configuration_warnings() -> PackedStringArray:
	var issues := PackedStringArray()
	_collect_nodes()
	if _body == null:
		issues.append("Нет дочернего StaticBody2D — куску не на чем держать коллизию.")
		return issues
	if _outline == null:
		issues.append("Внутри StaticBody2D нет CollisionPolygon2D.")
		return issues
	if _fill == null:
		issues.append("Внутри StaticBody2D нет Polygon2D — кусок будет невидимым.")
	if _outline.build_mode != CollisionPolygon2D.BUILD_SEGMENTS:
		issues.append("CollisionPolygon2D должен быть в режиме «Сегменты» (BUILD_SEGMENTS).")
	var points := _outline.polygon
	if points.size() < 3:
		issues.append("В контуре меньше трёх точек.")
		return issues
	if not points[0].is_equal_approx(Vector2.ZERO):
		issues.append("Первая точка контура — вход куска, она обязана быть ровно (0, 0).")
	var exit_point := get_exit_position()
	if not _has_point(points, exit_point):
		issues.append("В контуре нет точки выхода (%d, %d)." % [int(exit_point.x), int(exit_point.y)])
	# Стык всегда ровный, даже когда кусок кончается на другой высоте:
	# перепад отрабатывается внутри куска, а к выходу профиль обязан
	# выйти на горизонтальную площадку уже на новом уровне.
	if points.size() > 1 and not is_equal_approx(points[1].y, 0.0):
		issues.append("После входа нет ровной площадки: стык встанет на излом.")
	var exit_index := _find_point_index(points, exit_point)
	if exit_index > 0:
		var before_exit := points[exit_index - 1]
		if not is_equal_approx(before_exit.y, exit_point.y):
			issues.append("Перед выходом нет ровной площадки: стык встанет на излом.")
		elif exit_point.x - before_exit.x < 20.0:
			issues.append("Ровная площадка перед выходом короче 20 px.")
	return issues


func _has_point(points: PackedVector2Array, target: Vector2) -> bool:
	for point in points:
		if point.distance_squared_to(target) <= 0.25:
			return true
	return false


func _find_point_index(points: PackedVector2Array, target: Vector2) -> int:
	for i in points.size():
		if points[i].distance_squared_to(target) <= 0.25:
			return i
	return -1
