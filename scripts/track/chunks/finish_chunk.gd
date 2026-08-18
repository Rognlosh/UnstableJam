@tool
class_name FinishChunk
extends TrackChunk

## Финишная площадка с зоной пересечения. Геометрия обычная, ровная —
## вся работа в Area2D, которая ловит грузовик и сообщает об этом наверх.
## Само оформление финиша (створ, флаги, здания) добавляется в сцену руками.

signal crossed

var _zone: Area2D


func _ready() -> void:
	super()
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
