class_name ShopLot
extends PanelContainer

## Строка витрины: силуэт товара, его числа и кнопка покупки.
## Про деньги не знает ничего, кроме того, хватает их или нет.

signal buy_pressed(item: ItemData)

## Сторона квадрата, в который вписывается силуэт товара.
const PREVIEW_BOX: float = 72.0

@export var silhouette: Polygon2D
@export var name_label: Label
@export var stats_label: Label
## Строка нестабильного свойства. У обычного товара прячется целиком,
## иначе под каждой вазой болталась бы пустая полоса.
@export var quirk_label: Label
@export var buy_button: Button

var _data: ItemData = null
var _stock: int = 0
var _money: int = 0
var _has_room: bool = true


## Товар строки. Назначается один раз при создании.
func setup(item: ItemData) -> void:
	_data = item
	# is_node_ready() отсекает случай, когда строку настроили сразу после
	# instantiate(): узлы из @export резолвятся только при входе в дерево,
	# и до этого момента трогать их нельзя. Всё, что не успели показать,
	# покажет _ready().
	if is_node_ready():
		_refresh()


## Пересчёт того, что меняется по ходу закупа.
func refresh(stock: int, money: int, has_room: bool) -> void:
	_stock = stock
	_money = money
	_has_room = has_room
	if is_node_ready():
		_refresh()


func _ready() -> void:
	buy_button.pressed.connect(_on_buy_pressed)
	_refresh()


func _on_buy_pressed() -> void:
	if _data != null:
		buy_pressed.emit(_data)


func _refresh() -> void:
	if _data == null:
		return
	name_label.text = _data.get_display_name()
	var stock_note := "" if _stock <= 0 else "   •   на складе: %d" % _stock
	stats_label.text = "Продажа: %d   •   прочность: %s   •   вес: %s%s" % [
		_data.base_price,
		_toughness_word(_data.break_speed),
		_format_mass(_data.mass),
		stock_note,
	]
	# Про нехватку места говорим прямо на кнопке: серая кнопка без причины
	# читается как поломка.
	if not _has_room:
		buy_button.text = "Нет места"
		buy_button.disabled = true
	else:
		buy_button.text = "Купить · %d" % _data.buy_price
		buy_button.disabled = _money < _data.buy_price
	_refresh_quirk()
	_draw_silhouette()


## Свойство подаётся тем же цветом, которым метит вещь: строка витрины
## и силуэт в кузове читаются как одно и то же, без легенды.
func _refresh_quirk() -> void:
	if quirk_label == null:
		return
	var quirk := _data.quirk
	quirk_label.visible = quirk != null
	if quirk == null:
		return
	quirk_label.text = "%s — %s" % [quirk.get_display_name(), quirk.get_hint()]
	# Оттенок берём в полную силу, а не через tint_amount: на силуэте он
	# лишь подкрашивает вещь, а тексту нужна читаемая заливка.
	quirk_label.add_theme_color_override(&"font_color", quirk.tint)


## Силуэт вписывается в квадрат постоянной стороны: иначе высокая ваза
## и приземистый ларец нарисовались бы в одном масштабе только случайно.
func _draw_silhouette() -> void:
	silhouette.polygon = _data.whole_polygon
	silhouette.color = _data.color
	var rect := _data.get_bounds()
	var side := maxf(rect.size.x, rect.size.y)
	if side <= 0.0:
		return
	# Смещение уводит центр силуэта в начало координат узла, а сам узел
	# стоит в середине рамки — так предмет с несимметричным полигоном
	# не съезжает в угол.
	silhouette.offset = -rect.get_center()
	var factor := PREVIEW_BOX / side
	silhouette.scale = Vector2(factor, factor)


## Порог удара в пикселях в секунду игроку не говорит ничего, поэтому
## переводим его в слово. Слова согласованы с «прочность», а не с названием
## товара: иначе пришлось бы хранить род у каждого предмета.
static func _toughness_word(break_speed: float) -> String:
	if break_speed < 350.0:
		return "очень низкая"
	if break_speed < 550.0:
		return "низкая"
	if break_speed < 900.0:
		return "высокая"
	return "очень высокая"


## Целый вес показываем без десятичной части: «2» вместо «2.0».
static func _format_mass(mass: float) -> String:
	if is_equal_approx(mass, roundf(mass)):
		return str(int(round(mass)))
	return "%.1f" % mass
