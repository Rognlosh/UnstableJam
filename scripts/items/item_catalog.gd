class_name ItemCatalog
extends RefCounted

## Временный каталог предметов в коде. На Этапе 3 переедет в .tres-ресурсы.
##
## Ваза — шестиугольник, разрезанный вертикалью x = 0 и горизонталью y = 0
## на четыре куска. Куски стыкуются без зазоров, поэтому из них можно
## собрать исходный силуэт обратно.

## Каталог, собранный один раз за сессию: id → готовый ItemData.
## Кэш нужен не ради скорости, а ради одинаковости: без него каждая
## погруженная ваза получала бы собственную копию ItemData вместе
## с собственным PhysicsMaterial.
## static var — переменная класса, а не экземпляра (аналог static field в C#).
static var _cache: Dictionary = {}


## Единственная точка, через которую груз резолвится из идентификатора.
## Всё, что знает про предметы только по id (GameState, стадия перевозки),
## ходит сюда. Когда каталог переедет в .tres, поменяется только тело _build().
static func get_by_id(id: StringName) -> ItemData:
	if _cache.has(id):
		return _cache[id]
	var data := _build(id)
	if data != null:
		_cache[id] = data
	return data


## Идентификаторы всего, что вообще существует. Пригодится экрану закупа.
static func all_ids() -> Array[StringName]:
	# Литерал приводится к типизированному массиву через переменную:
	# в return нетипизированный [] к Array[StringName] сам не сводится.
	var ids: Array[StringName] = [&"vase"]
	return ids


## Сборка предмета по идентификатору. match — аналог switch в C#,
## но без проваливания между ветками.
static func _build(id: StringName) -> ItemData:
	match id:
		&"vase":
			return vase()
	push_warning("ItemCatalog: неизвестный предмет %s" % id)
	return null


static func vase() -> ItemData:
	var data := ItemData.new()
	data.id = &"vase"
	data.display_name = "Ваза"
	data.base_price = 50
	data.mass = 2.0
	data.break_speed = 420.0
	data.piece_toughness = 1.6
	data.color = Color(0.55, 0.72, 0.78)
	data.whole_polygon = PackedVector2Array([
		Vector2(0.0, -30.0),
		Vector2(18.0, -14.0),
		Vector2(14.0, 26.0),
		Vector2(0.0, 32.0),
		Vector2(-14.0, 26.0),
		Vector2(-18.0, -14.0),
	])
	data.pieces = [
		_piece(&"right_top", [
			Vector2(0.0, -30.0), Vector2(18.0, -14.0),
			Vector2(16.6, 0.0), Vector2(0.0, 0.0),
		], 0.3),
		_piece(&"right_bottom", [
			Vector2(0.0, 0.0), Vector2(16.6, 0.0),
			Vector2(14.0, 26.0), Vector2(0.0, 32.0),
		], 0.2),
		_piece(&"left_top", [
			Vector2(0.0, -30.0), Vector2(0.0, 0.0),
			Vector2(-16.6, 0.0), Vector2(-18.0, -14.0),
		], 0.3),
		_piece(&"left_bottom", [
			Vector2(0.0, 0.0), Vector2(0.0, 32.0),
			Vector2(-14.0, 26.0), Vector2(-16.6, 0.0),
		], 0.2),
	]
	data.physics_material = _material(0.85, 0.05)
	return data


static func _piece(id: StringName, points: Array, share: float) -> ItemPieceData:
	var piece := ItemPieceData.new()
	piece.piece_id = id
	piece.polygon = PackedVector2Array(points)
	piece.value_share = share
	return piece


static func _material(friction: float, bounce: float) -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = bounce
	return material
