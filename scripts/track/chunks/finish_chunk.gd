@tool
class_name FinishChunk
extends TrackChunk

## Финишная площадка с зоной пересечения. Геометрия обычная, ровная —
## вся работа в Area2D, которая ловит грузовик и сообщает об этом наверх.
## Само оформление финиша (створ, флаги, здания) добавляется в сцену руками.

signal crossed

## Полная высота ворот вместе с полями холста, в пикселях. Художник заложил
## запас снизу под стойки, поэтому на землю садится низ холста, а не низ
## рисунка: подошва у створа именно там. Видимая часть выходит примерно
## на девять десятых от этого числа.
@export_range(80.0, 800.0, 2.0) var gate_height: float = 282.0:
	set(value):
		gate_height = maxf(20.0, value)
		_place_gate()

## Насколько опустить створ относительно земли куска, в пикселях.
##
## Отдельно от высоты: масштаб и посадка — разные вещи, и подгонять одно
## другим значит каждый раз пересчитывать оба.
@export var gate_offset_y: float = 10.0:
	set(value):
		gate_offset_y = value
		_place_gate()

## Где стоит створ по длине куска. Совпадает с зоной пересечения намеренно:
## разъедься они, и финиш засчитается не там, где его видно.
@export var gate_x: float = 300.0:
	set(value):
		gate_x = value
		_place_gate()

@export_group("Лавка")

## Высота домика лавки в пикселях. Для сравнения: рама грузовика — 400 px
## в длину, так что при 320 постройка выходит вровень с машиной и читается
## как придорожная лавка, а не как город на горизонте.
@export_range(80.0, 900.0, 4.0) var shop_height: float = 320.0:
	set(value):
		shop_height = maxf(20.0, value)
		_place_shop()

## Где стоит лавка по длине куска. Правее створа намеренно: игрок финиширует
## и видит, куда везёт товар, — цель дня становится местом на карте.
@export var shop_x: float = 760.0:
	set(value):
		shop_x = value
		_place_shop()

## Посадка домика по вертикали относительно земли куска.
@export var shop_offset_y: float = 4.0:
	set(value):
		shop_offset_y = value
		_place_shop()

var _zone: Area2D


func _ready() -> void:
	super()
	_place_gate()
	_place_shop()
	_zone = _find_zone()
	if _zone == null:
		return
	if not Engine.is_editor_hint():
		_zone.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	# Шасси и колёса — дети узла Truck, так что проверка по типу родителя
	# ловит любую часть машины и не зависит от имён узлов.
	if body.get_parent() is Truck:
		crossed.emit()
		# Дальше зона не нужна: пересечь финиш можно только один раз.
		_zone.body_entered.disconnect(_on_body_entered)


## Ставит створ на землю, считая масштаб от фактического размера текстуры.
##
## Числом в сцене этот масштаб задавать нельзя: у SVG размеры бывают заданы
## в миллиметрах, и Godot переводит их в пиксели по 96 dpi — текстура выходит
## вчетверо крупнее чисел из viewBox. Ворота от такой ошибки уехали под землю
## целиком, вместе с половиной флага.
func _place_gate() -> void:
	# Сеттеры экспортов срабатывают при загрузке сцены, когда детей ещё нет,
	# поэтому отсутствие узла — обычное дело, а не ошибка.
	if not is_inside_tree():
		return
	var gate := get_node_or_null(^"Gate") as Sprite2D
	if gate == null or gate.texture == null:
		return
	var size := Vector2(gate.texture.get_size())
	if size.y <= 0.0:
		return
	var factor: float = gate_height / size.y
	gate.centered = false
	gate.scale = Vector2(factor, factor)
	# Низ холста — на уровень земли куска, то есть в ноль по Y.
	gate.position = Vector2(gate_x - size.x * factor * 0.5, -gate_height + gate_offset_y)


## Ставит домик лавки на землю. Правило то же, что у створа, и по той же
## причине: масштаб только от фактического размера текстуры, никогда числом
## в сцене — SVG в миллиметрах приезжает вчетверо крупнее своего viewBox.
func _place_shop() -> void:
	if not is_inside_tree():
		return
	var shop := get_node_or_null(^"Shop") as Sprite2D
	if shop == null or shop.texture == null:
		return
	var size := Vector2(shop.texture.get_size())
	if size.y <= 0.0:
		return
	var factor: float = shop_height / size.y
	shop.centered = false
	shop.scale = Vector2(factor, factor)
	shop.position = Vector2(
		shop_x - size.x * factor * 0.5, -shop_height + shop_offset_y)


func _find_zone() -> Area2D:
	for child in get_children():
		if child is Area2D:
			return child
	return null


func _get_configuration_warnings() -> PackedStringArray:
	var issues := super()
	if _find_zone() == null:
		issues.append("Нет дочерней Area2D — финиш некому засечь.")
	return issues
