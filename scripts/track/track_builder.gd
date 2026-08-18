class_name TrackBuilder
extends Node2D

## Сборщик трассы: ставит куски встык слева направо, пока не наберётся
## нужная длина. Позиция самого узла — это точка входа первого куска,
## то есть уровень дороги на старте.
##
## Сложность нарастает по ходу трассы: потолок допустимой злости кусков
## тянется от start_difficulty к end_difficulty, а окно снизу отсекает
## слишком лёгкие куски ближе к финишу. Дневная кривая сложности позже
## будет просто подкручивать эти три числа.

signal track_built(total_length: float)
## Грузовик пересёк финишную черту.
signal finish_reached

## Сцены-куски, из которых собирается трасса. Каждая — с корнем TrackChunk.
@export var chunk_scenes: Array[PackedScene] = []
## Целевая длина трассы в пикселях. Замер на пустой трассе: 20000 px
## проезжаются за 30 секунд, то есть около 670 px/с. С препятствиями
## темп падает, поэтому 30000 — это примерно минута заезда.
@export var target_length: float = 30000.0

@export_group("Сложность")
## Потолок сложности в начале трассы. Ноль означает, что первые тысячи
## пикселей доступен только ровный кусок — это ощущается как пустой пролог.
## Роль разгонной площадки отдана служебному стартовому куску.
@export_range(0, 3) var start_difficulty: int = 1
## Потолок сложности у финиша.
@export_range(0, 3) var end_difficulty: int = 3
## Насколько ниже текущего потолка куски ещё допускаются.
## 1 значит «у финиша ровное место уже не выпадет».
@export_range(0, 3) var difficulty_window: int = 2

@export_group("Разброс высоты")
## Во сколько раз растягивается профиль в начале трассы: (минимум, максимум).
@export var height_scale_start: Vector2 = Vector2(0.8, 1.0)
## То же у финиша. Верхняя граница ползёт вверх — кочки к концу выше.
@export var height_scale_end: Vector2 = Vector2(1.0, 1.5)

@export_group("Перепады высоты")
## Коридор, за который не выходит накопленная высота трассы, отсчёт
## от уровня старта. Y растёт вниз: x — потолок, y — дно.
@export var height_band: Vector2 = Vector2(-1200.0, 1200.0)
## Насколько сильнее тянет к нулю кусок, возвращающий трассу к уровню
## старта. 1.0 — без предпочтений, 3.0 — почти всегда возвращаемся.
@export_range(1.0, 4.0, 0.1) var return_bias: float = 2.0
## Насколько глубоко под самой низкой точкой трассы лежит общее дно.
@export var skirt_below: float = 1200.0

@export_group("Служебные куски")
## Стартовая площадка. Ставится первой вне случайной выборки: на ней
## грузовик появляется и разгоняется, туда же вешается оформление старта.
@export var start_scene: PackedScene
## Финишная площадка с зоной пересечения. Ставится последней.
@export var finish_scene: PackedScene

@export_group("Прочее")
## Зерно генерации. Одно и то же зерно даёт одну и ту же трассу,
## иначе настройки подвески нельзя сравнивать между запусками.
@export var track_seed: int = 1
## Если включено, build() берёт новое зерно вместо сохранённого.
@export var randomize_seed_on_build: bool = false
## Трение и упругость дороги — одно на всю трассу.
@export var surface_material: PhysicsMaterial

const START_MARGIN: float = 200.0
const START_HEIGHT: float = 80.0

var _rng := RandomNumberGenerator.new()
var _chunks: Array[TrackChunk] = []
var _end_point: Vector2 = Vector2.ZERO


## Описание куска, вытащенное из сцены один раз. Вложенный класс —
## аналог вложенного class в C#, экземпляры создаются через ChunkInfo.new().
class ChunkInfo:
	var scene: PackedScene
	var length: float
	var difficulty: int
	var weight: float
	var exit_offset_y: float


func build() -> void:
	_clear()
	if randomize_seed_on_build:
		track_seed = int(Time.get_ticks_usec())
	_rng.seed = track_seed

	var pool := _load_pool()
	if pool.is_empty():
		push_warning("TrackBuilder: список chunk_scenes пуст, трасса не собрана.")
		return

	var cursor := Vector2.ZERO
	if start_scene != null:
		var start_chunk := _place_chunk(start_scene, cursor, 0.0)
		if start_chunk != null:
			cursor += start_chunk.get_exit_position()

	var previous: ChunkInfo = null
	# Потолок числа кусков — страховка от куска с нулевой длиной,
	# который иначе крутил бы цикл вечно.
	var guard := 512
	while cursor.x < target_length and guard > 0:
		guard -= 1
		var progress := clampf(cursor.x / target_length, 0.0, 1.0)
		var info := _pick(pool, progress, previous, cursor.y)
		var chunk := _place_chunk(info.scene, cursor, progress)
		if chunk == null:
			break
		cursor += chunk.get_exit_position()
		previous = info

	if finish_scene != null:
		var finish_chunk := _place_chunk(finish_scene, cursor, 1.0)
		if finish_chunk != null:
			if finish_chunk is FinishChunk:
				(finish_chunk as FinishChunk).crossed.connect(_on_finish_crossed)
			cursor += finish_chunk.get_exit_position()

	_level_skirts()
	_end_point = cursor
	track_built.emit(cursor.x)


## Ставит кусок в указанную точку и приводит его в рабочий вид.
## Порядок важен: сначала кусок строит профиль по зерну, потом профиль
## растягивается по высоте, и только после этого вызывающий снимает точку
## выхода — иначе стык уедет на растянутую величину.
func _place_chunk(scene: PackedScene, at: Vector2, progress: float) -> TrackChunk:
	var chunk := scene.instantiate() as TrackChunk
	if chunk == null:
		push_warning("TrackBuilder: сцена %s не является TrackChunk." % scene.resource_path)
		return null
	chunk.position = at
	add_child(chunk)
	chunk.apply_seed(_rng.randi())
	var low := lerpf(height_scale_start.x, height_scale_end.x, progress)
	var high := lerpf(height_scale_start.y, height_scale_end.y, progress)
	chunk.apply_height_scale(_rng.randf_range(low, high))
	if surface_material != null:
		chunk.apply_physics_material(surface_material)
	_chunks.append(chunk)
	return chunk


func _on_finish_crossed() -> void:
	finish_reached.emit()


## Глобальная точка, куда ставить грузовик перед стартом.
func get_start_position() -> Vector2:
	return to_global(Vector2(START_MARGIN, -START_HEIGHT))


## Глобальная точка выхода последнего куска — сюда позже встанет финиш.
func get_end_position() -> Vector2:
	return to_global(_end_point)


func get_total_length() -> float:
	return _end_point.x


func get_chunk_count() -> int:
	return _chunks.size()


func _clear() -> void:
	for chunk in _chunks:
		if is_instance_valid(chunk):
			# Сначала выводим из дерева, потом освобождаем: queue_free()
			# отложенный, и без remove_child старые куски прожили бы
			# ещё кадр поверх новых.
			remove_child(chunk)
			chunk.queue_free()
	_chunks.clear()
	_end_point = Vector2.ZERO


## Читаем длину и сложность каждой сцены один раз, на пробном экземпляре.
func _load_pool() -> Array[ChunkInfo]:
	var pool: Array[ChunkInfo] = []
	for scene in chunk_scenes:
		if scene == null:
			continue
		var probe := scene.instantiate() as TrackChunk
		if probe == null:
			push_warning("TrackBuilder: сцена %s не является TrackChunk." % scene.resource_path)
			continue
		var info := ChunkInfo.new()
		info.scene = scene
		info.length = probe.length
		info.difficulty = probe.difficulty
		info.weight = maxf(probe.weight, 0.0)
		info.exit_offset_y = probe.exit_offset_y
		pool.append(info)
		# Пробник в дерево не попадал, поэтому free() безопасен и мгновенен.
		probe.free()
	return pool


## Второй проход по собранной трассе: выравнивает низ всех кусков.
func _level_skirts() -> void:
	var lowest := 0.0
	for chunk in _chunks:
		lowest = maxf(lowest, chunk.position.y + chunk.get_lowest_surface_y())
	for chunk in _chunks:
		chunk.set_skirt_bottom(lowest + skirt_below - chunk.position.y)


func _pick(
	pool: Array[ChunkInfo], progress: float,
	previous: ChunkInfo, current_y: float
) -> ChunkInfo:
	var ceiling := int(round(lerpf(float(start_difficulty), float(end_difficulty), progress)))
	var floor_level := maxi(0, ceiling - difficulty_window)

	var candidates: Array[ChunkInfo] = []
	for info in pool:
		if info.difficulty > ceiling or info.difficulty < floor_level:
			continue
		if not _fits_band(info, current_y):
			continue
		candidates.append(info)
	# Если окно оказалось пустым, отступаем к «всё, что не тяжелее потолка»,
	# потом к плоским кускам, и лишь в самом конце — ко всему пулу.
	# Трасса важнее правила, но коридор высот сдаём последним.
	if candidates.is_empty():
		for info in pool:
			if info.difficulty <= ceiling and _fits_band(info, current_y):
				candidates.append(info)
	if candidates.is_empty():
		for info in pool:
			if is_zero_approx(info.exit_offset_y):
				candidates.append(info)
	if candidates.is_empty():
		candidates = pool.duplicate()

	# Два одинаковых куска подряд читаются как один длинный и скучный.
	if previous != null and candidates.size() > 1:
		candidates.erase(previous)

	var weights: Array[float] = []
	var total := 0.0
	for info in candidates:
		var w := info.weight * _return_factor(info, current_y)
		weights.append(w)
		total += w
	if total <= 0.0:
		return candidates[_rng.randi_range(0, candidates.size() - 1)]

	var roll := _rng.randf() * total
	for i in candidates.size():
		roll -= weights[i]
		if roll <= 0.0:
			return candidates[i]
	return candidates[candidates.size() - 1]


## Не выведет ли кусок трассу за коридор высот. Считаем по худшему случаю:
## растяжка ещё умножит перепад, и проверять надо по её верхней границе.
func _fits_band(info: ChunkInfo, current_y: float) -> bool:
	if is_zero_approx(info.exit_offset_y):
		return true
	var worst := current_y + info.exit_offset_y * maxf(height_scale_end.y, 1.0)
	return worst >= height_band.x and worst <= height_band.y


## Чем дальше трасса ушла от уровня старта, тем охотнее берём кусок,
## возвращающий её обратно. Без этого случайное блуждание упирается
## в стенку коридора и там залипает.
func _return_factor(info: ChunkInfo, current_y: float) -> float:
	if is_zero_approx(info.exit_offset_y) or is_zero_approx(current_y):
		return 1.0
	var limit := height_band.y if current_y > 0.0 else height_band.x
	var drift := clampf(absf(current_y / limit), 0.0, 1.0)
	# signf даёт -1, 0 или 1 — знаки совпали, значит кусок уводит дальше.
	if signf(info.exit_offset_y) == signf(current_y):
		return lerpf(1.0, 1.0 / return_bias, drift)
	return lerpf(1.0, return_bias, drift)
