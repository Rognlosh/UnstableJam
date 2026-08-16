class_name ItemCatalog
extends RefCounted

## Временный каталог предметов в коде. На Этапе 3 переедет в .tres-ресурсы.
##
## Ваза — шестиугольник, разрезанный вертикалью x = 0 и горизонталью y = 0
## на четыре куска. Куски стыкуются без зазоров, поэтому из них можно
## собрать исходный силуэт обратно.

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
