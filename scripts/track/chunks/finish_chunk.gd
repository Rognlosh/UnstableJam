@tool
class_name FinishChunk
extends TrackChunk

## Финишная площадка с зоной пересечения. Геометрия обычная, ровная —
## вся работа в Area2D, которая ловит грузовик и сообщает об этом наверх.
## Само оформление финиша (створ, флаги, здания) добавляется в сцену руками.

signal crossed

## Полная высота ворот вместе с полями холста, в пикселях. Художник заложил
## запас снизу под стойки, поэтому на землю садится низ холста, а не низ
## рисунка: подошва у створа именно там.
const GATE_HEIGHT: float = 282.0
## Где стоит створ. Совпадает с зоной пересечения намеренно: разъедься они,
## и финиш засчитается не там, где его видно.
const GATE_X: float = 300.0

var _zone: Area2D


func _ready() -> void:
	super()
	_place_gate()
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
	var gate := get_node_or_null(^"Gate") as Sprite2D
	if gate == null or gate.texture == null:
		return
	var size := Vector2(gate.texture.get_size())
	if size.y <= 0.0:
		return
	var factor: float = GATE_HEIGHT / size.y
	gate.centered = false
	gate.scale = Vector2(factor, factor)
	# Низ холста — на уровень земли куска, то есть в ноль по Y.
	gate.position = Vector2(GATE_X - size.x * factor * 0.5, -GATE_HEIGHT)


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
