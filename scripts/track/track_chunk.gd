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

## Толщины слоёв грунта сверху вниз, в пикселях: кайма песка, песок,
## кайма песка, дёрн, кайма дёрна. Всё, что глубже, — заливка контура,
## то есть однотонная толща.
##
## Машина едет по ПЕСКУ: дорога здесь грунтовая, и верхний слой обязан
## быть песчаным. Дёрн лежит ниже дороги, а зелень, которую видно над
## горизонтом, — это холмы за дорогой, отдельный фоновый слой.
const SOIL_DEPTHS: Array[float] = [4.0, 30.0, 4.0, 20.0, 3.0]

## Насколько глубокий слой отрывается от микрорельефа, доля на границу.
##
## Настоящие слои залегания не повторяют каждую кочку: чем глубже, тем
## ровнее лежит порода. Без этого пирог копировал изломы поверхности
## один в один, и на вершине уступа полосы сходились острым клином.
## Верхняя граница остаётся точной всегда — иначе между дорогой
## и грунтом появилась бы щель.
const SOIL_RELAX: float = 0.34
## Окно сглаживания в точках профиля.
const SOIL_SMOOTH_WINDOW: int = 9

var _body: StaticBody2D
var _outline: CollisionPolygon2D
var _fill: Polygon2D
var _soil: Node2D


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
	


## Красит землю куска из палитры и настилает поверх неё слои грунта.
## Цвет в сцене куска остаётся превью для редактора, истина — палитра.
##
## Звать строго ПОСЛЕ apply_height_scale(): слои строятся по профилю
## поверхности, а растяжка этот профиль правит.
func apply_ground_style(palette: WorldPalette) -> void:
	if _fill == null:
		_collect_nodes()
	if _fill == null or _body == null:
		return
	_fill.color = palette.ground
	_build_soil(palette)


## Полосы грунта — это тот же профиль поверхности, сдвинутый вниз
## на толщину предыдущих слоёв. Поэтому дёрн повторяет каждую кочку
## и каждую яму, а слоёный пирог виден в разрезе на стенках промоин
## и на уступе рампы, где земля обрывается.
##
## Полосы живут в отдельном узле, а не прямо в теле: _collect_nodes()
## ищет заливку как первый попавшийся Polygon2D среди детей тела,
## и полдюжины новых полигонов рядом с ней сбили бы этот поиск.
func _build_soil(palette: WorldPalette) -> void:
	var surface := _surface_points()
	if surface.size() < 2:
		return
	if _soil != null:
		_soil.free()
	_soil = Node2D.new()
	# Добавляем последним ребёнком тела — значит рисуется поверх заливки.
	_body.add_child(_soil)
	var colors: Array[Color] = [
		palette.soil_sand_edge, palette.soil_sand, palette.soil_sand_edge,
		palette.soil_subturf, palette.soil_subturf_edge,
	]
	var relaxed := _smooth(surface, SOIL_SMOOTH_WINDOW)
	# Границы считаем заранее и по порядку: низ каждой полосы обязан быть
	# ровно верхом следующей, иначе между ними проступит толща.
	var edges: Array[PackedVector2Array] = []
	var depth := 0.0
	for i in SOIL_DEPTHS.size() + 1:
		edges.append(_edge(surface, relaxed, depth, minf(float(i) * SOIL_RELAX, 1.0)))
		if i < SOIL_DEPTHS.size():
			depth += SOIL_DEPTHS[i]
	for i in SOIL_DEPTHS.size():
		var band := Polygon2D.new()
		band.polygon = _band(edges[i], edges[i + 1])
		band.color = colors[i]
		_soil.add_child(band)


## Профиль поверхности: контур без двух последних точек. Юбка в слои
## не идёт — она уходит на километр вниз, и полоса дёрна по ней
## растянулась бы на весь экран.
func _surface_points() -> PackedVector2Array:
	if _outline == null:
		return PackedVector2Array()
	var points := _outline.polygon
	if points.size() < 4:
		return PackedVector2Array()
	return points.slice(0, points.size() - 2)


## Граница слоя: профиль, опущенный на глубину и подтянутый к сглаженному
## тем сильнее, чем глубже лежит.
static func _edge(surface: PackedVector2Array, relaxed: PackedVector2Array,
		depth: float, relax: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in surface.size():
		var y: float = lerpf(surface[i].y, relaxed[i].y, relax) + depth
		points.append(Vector2(surface[i].x, y))
	return points


## Полоса между двумя границами: верхняя как есть, нижняя в обратном
## порядке. Обход замкнутый, поэтому Polygon2D закрашивает ровно ленту.
static func _band(top: PackedVector2Array, bottom: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array(top)
	for i in range(bottom.size() - 1, -1, -1):
		points.append(bottom[i])
	return points


## Скользящее среднее по высоте. Края профиля не трогаем: там стык
## с соседним куском, и разъехавшиеся на пиксель слои дали бы шов
## через всю толщу земли.
static func _smooth(surface: PackedVector2Array, window: int) -> PackedVector2Array:
	var count := surface.size()
	var result := PackedVector2Array(surface)
	if count < window * 2:
		return result
	var half := window / 2
	for i in range(half, count - half):
		var sum := 0.0
		for k in range(i - half, i + half + 1):
			sum += surface[k].y
		# Ближе к краям отпускаем сглаживание, чтобы оно сошло на нет
		# ровно к стыку, а не оборвалось ступенькой.
		var edge_fade: float = minf(float(i), float(count - 1 - i)) / float(window * 2)
		result[i] = Vector2(surface[i].x,
			lerpf(surface[i].y, sum / float(window), minf(edge_fade, 1.0)))
	return result



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


## Самая низкая точка поверхности куска. Две последние точки контура —
## это юбка, они в счёт не идут: нас интересует дно котловин, а не дно
## полигона.
func get_lowest_surface_y() -> float:
	if _outline == null:
		_collect_nodes()
	if _outline == null:
		return 0.0
	var points := _outline.polygon
	var lowest := 0.0
	for i in maxi(points.size() - 2, 0):
		lowest = maxf(lowest, points[i].y)
	return lowest


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
