## Фон главного меню: силуэты товара, медленно падающие полосами сверху вниз.
##
## Берёт формы и цвета прямо из каталога предметов, а не из отдельных
## декоративных ресурсов. Появятся спрайты — здесь меняется один метод
## (Polygon2D на Sprite2D), а список того, что летает, не трогается вовсе:
## добавили товар в catalog.tres — он сам залетел в меню.
##
## Физики тут нет и не нужно: это заставка, а не сцена. Тела дали бы
## столкновения, сон, разбитие — всё, что на статичном экране только
## ест время в вебе.
extends Control

## Сколько полос по ширине экрана и сколько предметов держим в каждой.
## Двадцать восемь узлов на экран: плотно, но это по-прежнему рисовка
## тридцати полигонов за кадр, а не тридцати тел в физике.
const LANE_COUNT: int = 7
const PER_LANE: int = 4

## Разброс скорости падения (px/с). Скорость постоянна для предмета,
## а не для полосы: одинаково падающая колонка читается как сетка.
const FALL_SPEED_MIN: float = 26.0
const FALL_SPEED_MAX: float = 62.0

## Вращение (рад/с). Маленькое: быстрая крутёжка тянет взгляд на себя
## и мешает читать кнопки.
const SPIN_MAX: float = 0.32

## Предметы в игре мелкие (от 20×26 до 64×86 px) и на фоне 1280×720
## теряются, поэтому на заставке они крупнее натуральной величины.
const ITEM_SCALE: float = 1.7

## Запас за краями экрана, в котором предмет ещё живёт: половина самой
## крупной вещи с учётом масштаба и поворота на 45°.
const MARGIN: float = 160.0


## Одна летящая вещь. Внутренний класс — аналог вложенного класса в C#;
## нужен, чтобы не держать три параллельных массива и не гадать,
## какой индекс какому узлу соответствует.
class Drifter:
	var node: Polygon2D
	var lane: int
	var speed: float
	var spin: float


var _drifters: Array[Drifter] = []
var _items: Array[ItemData] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Клики сквозь фон: без этого прозрачный Control перехватывал бы мышь
	# и кнопки меню перестали бы нажиматься.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_rng.randomize()
	_add_background()
	_collect_items()
	if _items.is_empty():
		# Каталог пуст или без полигонов — фон просто не появится.
		# Меню от этого работать не перестаёт.
		set_process(false)
		return

	for lane in LANE_COUNT:
		for i in PER_LANE:
			var drifter := _make_drifter(lane)
			# Стартовая раскладка по всей высоте, а не над экраном: иначе
			# первые несколько секунд меню показывает пустоту.
			drifter.node.position.y = _rng.randf_range(-MARGIN, size.y)
			_drifters.append(drifter)


## Подложка. Создаётся кодом, а не кладётся в сцену цветным прямоугольником,
## потому что цвет обязан приходить из палитры: ровно ради этого палитра
## и заводилась — иначе оттенок разъедется с остальной игрой при первой правке.
func _add_background() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.WORLD.backdrop
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _process(delta: float) -> void:
	for drifter: Drifter in _drifters:
		drifter.node.position.y += drifter.speed * delta
		drifter.node.rotation += drifter.spin * delta
		if drifter.node.position.y > size.y + MARGIN:
			_respawn(drifter)


## Только предметы с нарисованным силуэтом. Пустой полигон дал бы
## невидимый узел, который честно летит и ничего не показывает.
func _collect_items() -> void:
	for data: ItemData in ItemCatalog.all_items():
		if data != null and not data.whole_polygon.is_empty():
			_items.append(data)


func _make_drifter(lane: int) -> Drifter:
	var drifter := Drifter.new()
	drifter.lane = lane
	drifter.node = Polygon2D.new()
	drifter.node.scale = Vector2.ONE * ITEM_SCALE
	add_child(drifter.node)
	_respawn(drifter)
	return drifter


## Выдать вещи новый предмет, новую полосу по горизонтали и вернуть наверх.
## Тот же метод обслуживает и первое появление, и переиспользование:
## узлы не создаются и не удаляются в процессе — их ровно LANE_COUNT × PER_LANE
## за всё время работы меню.
func _respawn(drifter: Drifter) -> void:
	var data: ItemData = _items[_rng.randi_range(0, _items.size() - 1)]

	# Полигон рисуем вокруг центра силуэта, а не вокруг его начала координат:
	# иначе вещь вращалась бы вокруг угла и гуляла по экрану полумесяцем.
	var offset: Vector2 = -data.get_bounds().get_center()
	var points := PackedVector2Array()
	for point: Vector2 in data.whole_polygon:
		points.append(point + offset)
	drifter.node.polygon = points

	# Цвет ровно тот же, что у вещи в кузове: фон — это тот товар,
	# который игрок сейчас пойдёт возить, а не абстрактный узор.
	drifter.node.color = data.color

	# Ширина полосы считается при каждом появлении, а не при старте:
	# так фон переживает изменение размера окна без единого сигнала.
	var lane_width: float = size.x / float(LANE_COUNT)
	var lane_center: float = (float(drifter.lane) + 0.5) * lane_width
	# Разброс внутри полосы — треть её ширины: полосы должны читаться
	# как полосы, но не выстраиваться в идеальную колонну.
	drifter.node.position = Vector2(
		lane_center + _rng.randf_range(-lane_width, lane_width) / 3.0,
		-MARGIN
	)
	drifter.node.rotation = _rng.randf_range(0.0, TAU)
	drifter.speed = _rng.randf_range(FALL_SPEED_MIN, FALL_SPEED_MAX)
	drifter.spin = _rng.randf_range(-SPIN_MAX, SPIN_MAX)
