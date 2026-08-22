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

## Рисунок предмета. null — вещь рисуется плоской заливкой, как раньше.
@export var texture: Texture2D
## Куда ложится текстура целиком, в координатах предмета.
##
## Это прямоугольник холста, а не габарит рисунка: у SVG вокруг картинки
## есть прозрачные поля, и они, как правило, несимметричны. Задавать
## приходится именно холст — только так центр рисунка встаёт туда,
## куда задумано, а не сползает на ширину поля.
@export var texture_rect: Rect2 = Rect2()

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


## Есть ли у предмета рисунок и задано ли, куда его класть. Пустой
## прямоугольник считаем отсутствием посадки: растянуть текстуру в ноль
## всё равно нечем.
func has_texture() -> bool:
	if texture == null:
		return false
	return texture_rect.size.x > 0.0 and texture_rect.size.y > 0.0


## Кладёт текстуру в texture_rect: после вызова спрайт занимает ровно этот
## прямоугольник в координатах предмета.
##
## Единственное место, где записано, как рисунок соотносится с вещью.
## Тело предмета, витрина закупа и фон меню зовут его же — иначе правка
## посадки чинилась бы в трёх файлах, и один из трёх забылся бы.
func fit_sprite(sprite: Sprite2D) -> void:
	if not has_texture():
		return
	sprite.texture = texture
	# centered = false переносит якорь в левый верхний угол холста —
	# только тогда позиция и масштаб однозначно кладут текстуру
	# в заданный прямоугольник, без поправки на половину размера.
	sprite.centered = false
	sprite.position = texture_rect.position
	sprite.scale = texture_rect.size / Vector2(texture.get_size())


## Готовый узел вида для превью: спрайт, если рисунок есть, полигон
## с заливкой, если нет.
##
## Центр вещи оказывается в начале координат узла — так предмет
## с несимметричным силуэтом не съезжает в угол рамки и вращается
## вокруг себя, а не вокруг своего угла.
##
## box — сторона квадрата, в который вещь вписывается целиком. Ноль
## означает натуральный размер: вызывающая сторона масштабирует сама.
func make_visual(box: float = 0.0) -> Node2D:
	var bounds := get_bounds()
	var center := bounds.get_center()
	var side := maxf(bounds.size.x, bounds.size.y)
	var factor := 1.0
	if box > 0.0 and side > 0.0:
		factor = box / side
	if has_texture():
		var sprite := Sprite2D.new()
		fit_sprite(sprite)
		# Подгонку под коробку домножаем на масштаб текстуры, а не заменяем:
		# в scale уже лежит перевод пикселей картинки в единицы предмета.
		sprite.position = (sprite.position - center) * factor
		sprite.scale *= factor
		return sprite
	var polygon_node := Polygon2D.new()
	polygon_node.polygon = whole_polygon
	polygon_node.color = color
	# offset сдвигает точки до масштабирования, поэтому центрирование
	# и подгонка размера не мешают друг другу.
	polygon_node.offset = -center
	polygon_node.scale = Vector2.ONE * factor
	return polygon_node


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
