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

@onready var _visual: Polygon2D = $Visual
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
	_visual.color = data.color if level == 0 else data.color.darkened(0.2)
	_shape.polygon = _polygon
	mass = maxf(0.05, data.mass * area_ratio())
	physics_material_override = data.physics_material
	add_to_group(&"cargo")
	if level > 0:
		add_to_group(&"fragments")
	_prev_velocity = linear_velocity


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Свободное падение тоже меняет скорость — эту часть вычитаем,
	# иначе предмет «разбивался» бы в воздухе.
	var gravity_step: Vector2 = state.total_gravity * state.step
	var impact: float = (state.linear_velocity - _prev_velocity - gravity_step).length()
	_prev_velocity = state.linear_velocity
	_frames_alive += 1

	if _is_broken or _frames_alive <= GRACE_FRAMES:
		return
	if impact < break_threshold():
		return

	_is_broken = true
	broke.emit(self, impact)
	# Удалять тело внутри физического колбэка нельзя — откладываем на кадр.
	Destruction.call_deferred(&"break_item", self, impact)


func break_threshold() -> float:
	if data == null:
		return INF
	var base := data.break_speed * (data.piece_toughness if level > 0 else 1.0)
	return base * toughness_bonus


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
