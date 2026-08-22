## Фон главного меню: силуэты товара, падающие полосами сверху вниз.
##
## Берёт вид прямо из каталога предметов, а не из отдельных декоративных
## ресурсов: узел вещи выдаёт сама ItemData через make_visual(), поэтому
## спрайт или заливка — вопрос, который здесь не решается. Список того,
## что летает, тоже не задан вручную: добавили товар в catalog.tres —
## он сам залетел в меню.
##
## Физики тут нет и не нужно: это заставка, а не сцена. Тела дали бы
## столкновения, сон, разбитие — всё, что на статичном экране только
## ест время в вебе.
extends Control

## Полосы по ширине экрана и число предметов в каждой.
## Тридцать пять узлов на экран — это по-прежнему рисовка тридцати
## полигонов за кадр, а не тридцать тел в физике.
const LANE_COUNT: int = 7
const PER_LANE: int = 5

## Разброс скорости падения (px/с). Скорость принадлежит ПОЛОСЕ, а не
## отдельной вещи: при своей скорости у каждого предмета соседи по полосе
## догоняют друг друга, слипаются в кучки и оставляют за собой дыры —
## ровно то, из-за чего фон выглядел рваным.
const FALL_SPEED_MIN: float = 26.0
const FALL_SPEED_MAX: float = 62.0

## Вращение (рад/с). Маленькое: быстрая крутёжка тянет взгляд на себя
## и мешает читать кнопки.
const SPIN_MAX: float = 0.32

## К какому размеру подтягивать силуэт по большей стороне.
## Предметы в игре различаются втрое (флакон 20×26 против амфоры 64×86),
## и в натуральных пропорциях мелочь на фоне читается как пустое место.
## Масштаб зажат, чтобы разница между вещами осталась заметной,
## но перестала быть провалом.
const TARGET_SIZE: float = 110.0
const SCALE_MIN: float = 1.2
const SCALE_MAX: float = 2.6

## Запас за краями экрана, в котором предмет ещё живёт: половина самой
## крупной вещи с учётом масштаба и поворота на 45°.
const MARGIN: float = 160.0


## Одна летящая вещь. Внутренний класс — аналог вложенного класса в C#;
## нужен, чтобы не держать параллельные массивы и не гадать, какой индекс
## какому узлу соответствует.
class Drifter:
	## Узел-носитель: он живёт всё время работы меню, на нём висят
	## положение, поворот и масштаб. Меняется при переиспользовании
	## только его единственный ребёнок — картинка нового предмета.
	var node: Node2D
	var visual: Node2D
	var lane: int
	var spin: float


var _drifters: Array[Drifter] = []
var _items: Array[ItemData] = []
## Скорость каждой полосы, индекс = номер полосы.
var _lane_speeds: PackedFloat32Array = PackedFloat32Array()
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

	var span: float = _span()
	var step: float = span / float(PER_LANE)
	for lane in LANE_COUNT:
		_lane_speeds.append(_rng.randf_range(FALL_SPEED_MIN, FALL_SPEED_MAX))
		# Своя фаза у каждой полосы: без неё предметы соседних полос
		# выстроились бы в ряды и фон читался бы таблицей.
		var phase: float = _rng.randf() * step
		for i in PER_LANE:
			var drifter := _make_drifter(lane)
			# Фиксированный шаг вместо случайной высоты. Вместе с общей
			# скоростью полосы это и держит равномерность: интервал между
			# соседями задан один раз и дальше не может разъехаться.
			drifter.node.position.y = -MARGIN + step * float(i) + phase


func _process(delta: float) -> void:
	var span: float = _span()
	for drifter: Drifter in _drifters:
		drifter.node.position.y += _lane_speeds[drifter.lane] * delta
		drifter.node.rotation += drifter.spin * delta
		if drifter.node.position.y > size.y + MARGIN:
			# Перенос ровно на длину круга, а не «поставить наверх»:
			# так шаг между соседями по полосе сохраняется навсегда.
			# Присвоение сбросило бы накопленный остаток, и за десяток
			# кругов равномерность растворилась бы обратно в кучки.
			drifter.node.position.y -= span
			_respawn(drifter)


## Полная длина круга: экран плюс запас сверху и снизу.
func _span() -> float:
	return size.y + MARGIN * 2.0


## Подложка. Создаётся кодом, а не кладётся в сцену цветным прямоугольником,
## потому что цвет обязан приходить из палитры: ровно ради этого палитра
## и заводилась — иначе оттенок разъедется с остальной игрой при первой правке.
func _add_background() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.WORLD.backdrop
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


## Только предметы, у которых есть чем себя нарисовать. Пустой полигон
## дал бы невидимый узел, который честно летит и ничего не показывает.
func _collect_items() -> void:
	for data: ItemData in ItemCatalog.all_items():
		if data != null and not data.whole_polygon.is_empty():
			_items.append(data)


func _make_drifter(lane: int) -> Drifter:
	var drifter := Drifter.new()
	drifter.lane = lane
	drifter.node = Node2D.new()
	add_child(drifter.node)
	_drifters.append(drifter)
	_respawn(drifter)
	return drifter


## Выдать вещи новый предмет, новое место по горизонтали и новый поворот.
## Высоту метод не трогает: ею распоряжается вызывающая сторона, потому что
## при переиспользовании важно не поставить предмет наверх, а сдвинуть его
## на длину круга. Узлов-носителей при этом ровно LANE_COUNT × PER_LANE
## за всё время работы меню; пересоздаётся только картинка внутри, и лишь
## тогда, когда вещь ушла за нижний край — раз в несколько секунд на вещь.
func _respawn(drifter: Drifter) -> void:
	var data: ItemData = _items[_rng.randi_range(0, _items.size() - 1)]
	var bounds: Rect2 = data.get_bounds()

	# Вид ровно тот же, что у вещи в кузове: фон — это тот товар, который
	# игрок сейчас пойдёт возить, а не абстрактный узор. Центрирование
	# внутри make_visual(), поэтому вещь вращается вокруг себя, а не вокруг
	# своего угла и не гуляет по экрану полумесяцем.
	if drifter.visual != null:
		drifter.visual.queue_free()
	drifter.visual = data.make_visual()
	drifter.node.add_child(drifter.visual)

	var longest: float = maxf(bounds.size.x, bounds.size.y)
	var scale_factor: float = SCALE_MIN
	if longest > 0.0:
		scale_factor = clampf(TARGET_SIZE / longest, SCALE_MIN, SCALE_MAX)
	drifter.node.scale = Vector2.ONE * scale_factor

	# Ширина полосы считается при каждом появлении, а не при старте:
	# так фон переживает изменение размера окна без единого сигнала.
	var lane_width: float = size.x / float(LANE_COUNT)
	var lane_center: float = (float(drifter.lane) + 0.5) * lane_width
	# Разброс внутри полосы — четверть её ширины. Больше — и полосы
	# перестают читаться, начинают перекрываться и снова копить пустоты.
	drifter.node.position.x = lane_center + _rng.randf_range(-lane_width, lane_width) / 4.0
	drifter.node.rotation = _rng.randf_range(0.0, TAU)
	drifter.spin = _rng.randf_range(-SPIN_MAX, SPIN_MAX)
