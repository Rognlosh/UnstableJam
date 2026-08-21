class_name ItemData
extends Resource

## Описание предмета: как выглядит, сколько весит, когда бьётся, на что.

@export var id: StringName = &""
## Ключ локализации названия, а не готовый текст: строки живут
## в localization/ui.csv. Читать через get_display_name().
@export var name_key: String = ""
@export var base_price: int = 10
## Цена закупа. Отдельным полем, а не наценкой от base_price: у крепкого
## дешёвого товара и у хрупкого дорогого разрыв между покупкой и продажей
## разный, общим коэффициентом это не выражается.
@export var buy_price: int = 10
@export var mass: float = 1.0

## Порог разрушения: насколько сильно должна измениться скорость тела
## за один физ-кадр (px/s), чтобы предмет разбился.
@export var break_speed: float = 420.0
## Во сколько раз осколок прочнее целого предмета.
@export var piece_toughness: float = 1.6

## Во сколько раз осколок дешевле своей доли цены. Доли всех кусков в сумме
## дают единицу, поэтому 0.8 означает: собрал все черепки — получил 80%
## цены целой вещи. Разбить товар должно быть больно, даже если ни один
## кусок не потерялся.
@export_range(0.0, 1.0, 0.05) var piece_value_factor: float = 0.8

@export var whole_polygon: PackedVector2Array = PackedVector2Array()
@export var pieces: Array[ItemPieceData] = []

@export var color: Color = Color(0.72, 0.66, 0.5)
@export var physics_material: PhysicsMaterial

## Нестабильное свойство. null — обычный товар. Ссылка на общий ресурс,
## поэтому одну левитацию можно надеть на любое число предметов.
@export var quirk: ItemQuirk


## Кусок по идентификатору. null, если такого куска нет.
func get_piece(wanted_id: StringName) -> ItemPieceData:
	for piece: ItemPieceData in pieces:
		if piece.piece_id == wanted_id:
			return piece
	return null


## Габариты целого предмета в его собственных координатах.
## Нужны укладке груза: предметы разного размера нельзя раскладывать
## постоянным шагом, отступ считается от фактической ширины и высоты.
func get_bounds() -> Rect2:
	if whole_polygon.is_empty():
		return Rect2()
	# Rect2 стартует нулевым прямоугольником в первой точке,
	# expand() растягивает его до каждой следующей.
	var rect := Rect2(whole_polygon[0], Vector2.ZERO)
	for i in range(1, whole_polygon.size()):
		rect = rect.expand(whole_polygon[i])
	return rect


## Ширина и высота силуэта — короткая запись для укладки.
func get_size() -> Vector2:
	return get_bounds().size


## Переведённое название. tr() зовём здесь, чтобы вызывающая сторона
## не обязана была помнить, что в поле лежит ключ, а не текст.
func get_display_name() -> String:
	return tr(name_key) if not name_key.is_empty() else ""
