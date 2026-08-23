class_name BreakableItem
extends RigidBody2D

## Тело предмета или его осколка. Форма и вид строятся из ItemData при входе
## в дерево, поэтому одна сцена обслуживает оба случая.
##
## Удар ловится не через контакты (в 2D их импульс сообщается ненадёжно),
## а через изменение скорости за физ-кадр с вычетом гравитации.

signal broke(item: BreakableItem, impact: float)

## Кадры после спавна, когда удары игнорируются: осколки рождаются внутри
## друг друга и иначе разлетелись бы в крошку в момент появления.
const GRACE_FRAMES: int = 5

## С какой доли порога разбития удар становится слышен. Ниже — вещь просто
## лежит и подрагивает в кузове, и озвучивать это значит получить непрерывный
## треск на всю дорогу.
const HIT_AUDIBLE: float = 0.22
## Громкость самого слабого слышимого удара, доля от полной. Не ноль:
## иначе порог слышимости выдаёт себя щелчками на грани тишины.
const HIT_QUIET: float = 0.35

## Множитель порога разрушения. Больше единицы — вещь терпит сильнее.
## Нужно фазе погрузки: мышь неточна, и бить игрока по тем же правилам,
## что и на дороге, несправедливо.
var toughness_bonus: float = 1.0

var data: ItemData
var level: int = 0                       # 0 — целое, 1 — осколок
var piece_id: StringName = &""
var instance_id: int = -1                # экземпляр предмета, нужен реставрации
var rest_offset: Vector2 = Vector2.ZERO  # место куска внутри целого предмета

var _polygon: PackedVector2Array = PackedVector2Array()
var _prev_velocity: Vector2 = Vector2.ZERO
var _is_broken: bool = false
var _frames_alive: int = 0
var _quirk: QuirkRuntime = null

@onready var _visual: Polygon2D = $Visual
@onready var _sprite: Sprite2D = $Sprite
@onready var _shape: CollisionPolygon2D = $Shape


## Настройка целого предмета. Вызывать после instantiate(), но до add_child().
func setup_whole(item_data: ItemData, item_instance_id: int) -> void:
	data = item_data
	instance_id = item_instance_id
	level = 0
	piece_id = &""
	rest_offset = Vector2.ZERO
	_polygon = item_data.whole_polygon


## Настройка осколка: полигон куска переносится в собственный центр,
## а смещение относительно центра целого запоминается в rest_offset.
## Именно rest_offset потом скажет, куда кусок надо вернуть при склейке.
func setup_piece(item_data: ItemData, item_instance_id: int, piece: ItemPieceData) -> void:
	data = item_data
	instance_id = item_instance_id
	level = 1
	piece_id = piece.piece_id
	rest_offset = polygon_centroid(piece.polygon)
	_polygon = shift_polygon(piece.polygon, -rest_offset)


func _ready() -> void:
	if data == null or _polygon.size() < 3:
		push_error("BreakableItem: не задан ItemData или полигон слишком мал")
		return
	_visual.polygon = _polygon
	_shape.polygon = _polygon
	_apply_look()
	mass = maxf(0.05, data.mass * area_ratio())
	physics_material_override = data.physics_material
	add_to_group(&"cargo")
	if level > 0:
		add_to_group(&"fragments")
	_setup_quirk()
	_prev_velocity = linear_velocity


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Свободное падение тоже меняет скорость — эту часть вычитаем,
	# иначе предмет «разбивался» бы в воздухе.
	var gravity_step: Vector2 = state.total_gravity * state.step
	var impact: float = (state.linear_velocity - _prev_velocity - gravity_step).length()
	_frames_alive += 1

	# Свойство работает и у помеченного на слом тела: обрывать левитацию
	# на кадр раньше смысла нет, а ветвление добавилось бы.
	if _quirk != null:
		_quirk.physics_step(state)

	# Эталон фиксируем уже после свойства: подъём и снос — наши собственные
	# изменения скорости, ударом они не являются.
	_prev_velocity = state.linear_velocity

	if _is_broken or _frames_alive <= GRACE_FRAMES:
		return

	var threshold: float = break_threshold()
	if impact < threshold:
		_play_hit(impact, threshold)
		return

	_is_broken = true
	broke.emit(self, impact)
	# Удалять тело внутри физического колбэка нельзя — откладываем на кадр.
	Destruction.call_deferred(&"break_item", self, impact)


## Стук груза, не дошедший до разбития. Громкость растёт с силой удара:
## так слышно разницу между «повозку тряхнуло» и «ваза чудом уцелела».
##
## Ограничитель частоты живёт в Audio и общий на все предметы: двадцать вещей
## в кузове бьются о борта в одном кадре, и без окна это сплошной треск.
func _play_hit(impact: float, threshold: float) -> void:
	if threshold <= 0.0 or is_inf(threshold):
		return
	var ratio: float = impact / threshold
	if ratio < HIT_AUDIBLE:
		return
	var loudness: float = remap(ratio, HIT_AUDIBLE, 1.0, HIT_QUIET, 1.0)
	Audio.play(&"cargo_hit", linear_to_db(loudness))


func break_threshold() -> float:
	if data == null:
		return INF
	var base := data.break_speed * (data.piece_toughness if level > 0 else 1.0)
	return base * toughness_bonus


## Вид тела. Три случая: целая вещь со спрайтом, осколок с куском той же
## текстуры и всё остальное — плоской заливкой, как было до появления арта.
##
## Осколок нельзя рисовать спрайтом: Sprite2D не умеет обрезаться по
## произвольному контуру, а кусок вазы обязан показывать ровно свою часть
## картинки. Polygon2D обрезается по своему полигону сам, и это ровно то,
## что нужно. Целую же вещь, наоборот, полигоном рисовать нельзя: контур
## задан под физику и уже вреза́л бы ручки амфоры и пробку вазы.
func _apply_look() -> void:
	# Тернарник тут не годится: у ветвей типы ItemQuirk и null, и парсер
	# считает их несовместимыми — отсюда предупреждение при перезагрузке.
	var quirk_look: ItemQuirk = null
	if _wears_quirk():
		quirk_look = data.quirk
	if data.has_texture():
		if level == 0:
			_apply_sprite(quirk_look)
		else:
			_apply_textured_polygon(quirk_look)
		return
	_sprite.visible = false
	var base_color: Color = data.color if level == 0 else data.color.darkened(0.2)
	_visual.color = quirk_look.tinted(base_color) if quirk_look != null else base_color


func _apply_sprite(quirk_look: ItemQuirk) -> void:
	_visual.visible = false
	_sprite.visible = true
	# Посадку картинки знает ресурс — здесь она не повторяется,
	# иначе тело и превью разъехались бы при первой же правке.
	data.fit_sprite(_sprite)
	_sprite.modulate = quirk_look.tinted(Color.WHITE) if quirk_look != null else Color.WHITE


func _apply_textured_polygon(quirk_look: ItemQuirk) -> void:
	_sprite.visible = false
	_visual.visible = true
	_visual.texture = data.texture
	_visual.uv = _texture_uv()
	# У Polygon2D с текстурой color работает множителем, поэтому серый
	# затемняет осколок ровно так же, как darkened() затемнял заливку.
	var base_color := Color.WHITE.darkened(0.2)
	_visual.color = quirk_look.tinted(base_color) if quirk_look != null else base_color


## Координаты текстуры для каждой вершины полигона — в пикселях картинки,
## а не в долях от единицы.
##
## Полигон осколка сдвинут в собственный центр, и вернуть его в систему
## целого предмета умеет только rest_offset: там и записано, какому месту
## вещи соответствует этот кусок. Без него все осколки показывали бы
## один и тот же участок рисунка — свой центр.
func _texture_uv() -> PackedVector2Array:
	var rect := data.texture_rect
	var texture_size := Vector2(data.texture.get_size())
	var uv := PackedVector2Array()
	uv.resize(_polygon.size())
	for i in _polygon.size():
		var point: Vector2 = _polygon[i] + rest_offset
		uv[i] = (point - rect.position) / rect.size * texture_size
	return uv


## Действует ли свойство на это конкретное тело: у осколка оно может быть
## ослаблено до нуля.
func _wears_quirk() -> bool:
	if data == null or data.quirk == null:
		return false
	return level == 0 or data.quirk.piece_strength > 0.0


func _setup_quirk() -> void:
	if not _wears_quirk():
		return
	# Фабрика отдаёт RefCounted — приводим здесь, на стороне, которая
	# про оба класса и так знает.
	_quirk = data.quirk.create_runtime() as QuirkRuntime
	if _quirk != null:
		_quirk.attach(self, data.quirk, level)


## Зовётся Destruction'ом в момент разрушения — единственный шанс свойства
## сработать напоследок (взрыв, вспышка). Тело в этот момент ещё в дереве:
## queue_free() откладывает удаление до конца кадра.
func notify_broken(impact: float, at: Vector2) -> void:
	if _quirk != null:
		_quirk.on_break(impact, at)


## Задаёт скорость и одновременно объявляет её ожидаемой.
##
## Детектор ловит удар по изменению скорости за физкадр, поэтому вещь,
## которую тащат мышью, разбивалась бы от собственного разгона. Здесь мы
## говорим детектору: это изменение сделали мы, ударом не считать. А вот
## если физика погасит скорость о борт или о соседний груз — расхождение
## останется, и удар засчитается честно.
func drive_velocity(velocity: Vector2) -> void:
	linear_velocity = velocity
	_prev_velocity = velocity


## Переставляет тело вместе с его состоянием в физическом сервере.
##
## Одного присваивания global_transform мало: у RigidBody2D состояние живёт
## в сервере, и он вернёт тело обратно на ближайшем шаге. Заодно гасим
## память о прошлой скорости — иначе обнуление хода при переносе детектор
## примет за удар и разобьёт вещь ровно в момент спасения.
func place_at(xform: Transform2D) -> void:
	global_transform = xform
	var rid := get_rid()
	PhysicsServer2D.body_set_state(rid, PhysicsServer2D.BODY_STATE_TRANSFORM, xform)
	PhysicsServer2D.body_set_state(rid, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2.ZERO)
	PhysicsServer2D.body_set_state(rid, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, 0.0)
	_prev_velocity = Vector2.ZERO


## Габариты именно этого тела: у осколка полигон свой, и брать размеры
## целого предмета для него нельзя.
func get_local_bounds() -> Rect2:
	if _polygon.is_empty():
		return Rect2()
	var rect := Rect2(_polygon[0], Vector2.ZERO)
	for i in range(1, _polygon.size()):
		rect = rect.expand(_polygon[i])
	return rect


## Какую долю цены предмета несёт это тело: целое — всю, осколок — свою.
##
## Именно по этим долям считается выручка за заезд: ваза, потерявшая одно
## донце, доезжает не «разбитой», а на 0.8 своей цены.
func value_ratio() -> float:
	if level == 0:
		return 1.0
	if data == null:
		return 0.0
	var piece := data.get_piece(piece_id)
	return piece.value_share * data.piece_value_factor if piece != null else 0.0


## Доля площади куска от площади целого предмета — из неё считается масса.
func area_ratio() -> float:
	if level == 0:
		return 1.0
	var whole_area := polygon_area(data.whole_polygon)
	if whole_area <= 0.0:
		return 1.0
	return clampf(polygon_area(_polygon) / whole_area, 0.05, 1.0)


static func polygon_area(points: PackedVector2Array) -> float:
	var total := 0.0
	var count := points.size()
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % count]
		total += a.x * b.y - b.x * a.y
	return absf(total) * 0.5


static func polygon_centroid(points: PackedVector2Array) -> Vector2:
	var doubled_area := 0.0
	var centroid := Vector2.ZERO
	var count := points.size()
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % count]
		var cross := a.x * b.y - b.x * a.y
		doubled_area += cross
		centroid += (a + b) * cross
	if is_zero_approx(doubled_area):
		return Vector2.ZERO
	return centroid / (3.0 * doubled_area)


static func shift_polygon(points: PackedVector2Array, delta: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(points.size())
	for i in points.size():
		result[i] = points[i] + delta
	return result
