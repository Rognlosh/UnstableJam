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

## Сцены-куски, из которых собирается трасса. Каждая — с корнем TrackChunk.
@export var chunk_scenes: Array[PackedScene] = []
## Целевая длина трассы в пикселях. ~450 px/с скорости, 20000 ≈ 45 секунд.
@export var target_length: float = 20000.0

@export_group("Сложность")
## Потолок сложности в начале трассы.
@export_range(0, 3) var start_difficulty: int = 0
## Потолок сложности у финиша.
@export_range(0, 3) var end_difficulty: int = 3
## Насколько ниже текущего потолка куски ещё допускаются.
## 1 значит «у финиша ровное место уже не выпадет».
@export_range(0, 3) var difficulty_window: int = 1

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
	var previous: ChunkInfo = null
	# Потолок числа кусков — страховка от куска с нулевой длиной,
	# который иначе крутил бы цикл вечно.
	var guard := 512
	while cursor.x < target_length and guard > 0:
		guard -= 1
		var progress := clampf(cursor.x / target_length, 0.0, 1.0)
		var info := _pick(pool, progress, previous)
		var chunk := info.scene.instantiate() as TrackChunk
		if chunk == null:
			push_warning("TrackBuilder: в chunk_scenes есть сцена, корень которой не TrackChunk.")
			break
		chunk.position = cursor
		add_child(chunk)
		if surface_material != null:
			chunk.apply_physics_material(surface_material)
		_chunks.append(chunk)
		cursor += chunk.get_exit_position()
		previous = info

	_end_point = cursor
	track_built.emit(cursor.x)


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
		pool.append(info)
		# Пробник в дерево не попадал, поэтому free() безопасен и мгновенен.
		probe.free()
	return pool


func _pick(pool: Array[ChunkInfo], progress: float, previous: ChunkInfo) -> ChunkInfo:
	var ceiling := int(round(lerpf(float(start_difficulty), float(end_difficulty), progress)))
	var floor_level := maxi(0, ceiling - difficulty_window)

	var candidates: Array[ChunkInfo] = []
	for info in pool:
		if info.difficulty > ceiling or info.difficulty < floor_level:
			continue
		candidates.append(info)
	# Если окно оказалось пустым, отступаем к «всё, что не тяжелее потолка»,
	# и лишь потом — ко всему пулу. Трасса важнее правила.
	if candidates.is_empty():
		for info in pool:
			if info.difficulty <= ceiling:
				candidates.append(info)
	if candidates.is_empty():
		candidates = pool.duplicate()

	# Два одинаковых куска подряд читаются как один длинный и скучный.
	if previous != null and candidates.size() > 1:
		candidates.erase(previous)

	var total := 0.0
	for info in candidates:
		total += info.weight
	if total <= 0.0:
		return candidates[_rng.randi_range(0, candidates.size() - 1)]

	var roll := _rng.randf() * total
	for info in candidates:
		roll -= info.weight
		if roll <= 0.0:
			return info
	return candidates[candidates.size() - 1]
