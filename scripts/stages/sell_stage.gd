## Стадия продажи: превращает итог заезда в деньги и закрывает день.
##
## Строка сводки — это МЕСТО, а не тип товара: каждая погруженная вещь
## получает свою полосу. Ваза, поехавшая целой, остаётся вазой, даже если
## приехала грудой черепков, а черепок со склада — отдельное место со своим
## потенциалом. Иначе обещание строки врёт: четыре черепка и одна ваза
## сулили бы 250 монет при физическом потолке в 90.
extends Control

@export var header_label: Label
@export var rows_container: VBoxContainer
@export var empty_label: Label
@export var gross_label: Label
@export var time_label: Label
@export var total_label: Label
@export var money_label: Label
@export var next_day_button: Button
## Сцена строки сводки. Через @export, а не preload: сцену видно
## в инспекторе и её можно подменить, не открывая скрипт.
@export var row_scene: PackedScene

## Порядок товара в каталоге: id → номер. Нужен сортировке строк и строится
## один раз за показ экрана, чтобы не искать предмет в массиве на каждое
## сравнение — сортировка зовёт компаратор куда чаще, чем есть строк.
var _catalog_order: Dictionary = {}


func _ready() -> void:
	next_day_button.pressed.connect(_on_next_day_pressed)
	_sell_cargo()


## Выручка считается по долям доехавшей ценности, а не по числу ящиков:
## ваза без одного донца стоит дешевле целой, но дороже нуля. Поверх этого
## ложится коэффициент за скорость: за долгую доставку платят меньше.
func _sell_cargo() -> void:
	var gross := _build_rows(_collect_places())

	# Коэффициент применяется один раз к сумме, а не к каждой строке:
	# иначе строки не сходились бы в итог из-за округления, и игрок
	# ловил бы нас на арифметике.
	var payout: float = GameState.run_result.get("payout_factor", 1.0)
	var total := int(round(float(gross) * payout))
	GameState.earn_money(total)

	header_label.text = tr("SELL_HEADER") % GameState.get_day()
	gross_label.text = tr("SELL_GROSS") % gross
	total_label.text = tr("SELL_TOTAL") % total
	money_label.text = tr("SELL_MONEY") % [
		GameState.get_money(), GameState.cargo_actual.size(),
	]

	var run_seconds := int(GameState.run_result.get("run_time", 0.0))
	# Про потерю на опоздании говорим прямо: без этого игрок увидит
	# только меньшее число и не поймёт, за что.
	if payout < 1.0:
		time_label.text = tr("SELL_TIME_LATE") % [
			run_seconds, int(round(payout * 100.0)),
		]
	else:
		time_label.text = tr("SELL_TIME") % run_seconds


## Записи заезда → список мест, готовых к показу. Монеты считаем здесь,
## один раз на место: сортировка идёт уже по готовым числам, и округление
## не зависит от того, в каком порядке строки встали.
func _collect_places() -> Array[Dictionary]:
	# get() со значением по умолчанию — на случай, если стадию открыли
	# в обход перевозки (например, запустив сцену напрямую из редактора).
	var entries: Array = GameState.run_result.get("items", [])
	var places: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var data := ItemCatalog.get_by_id(entry.get("id", &""))
		if data == null:
			continue
		var start: float = entry.get("start", 1.0)
		var price := float(data.base_price)
		places.append({
			"data": data,
			# Стартовая доля меньше единицы бывает только у черепка:
			# целую вещь грузят целиком или не грузят вовсе.
			"pieces": not is_equal_approx(start, 1.0),
			"revenue": int(round(price * float(entry.get("ratio", 0.0)))),
			"potential": int(round(price * start)),
			"order": int(_order_of(data.id)),
		})
	places.sort_custom(_compare_places)
	return places


## Строки в порядке: товар по каталогу → целые перед осколками → дороже
## перед дешевле. Так уцелевшее собирается сверху, а потери сползают вниз
## и читаются одной группой, а не вперемешку.
static func _compare_places(a: Dictionary, b: Dictionary) -> bool:
	if a["order"] != b["order"]:
		return a["order"] < b["order"]
	if a["pieces"] != b["pieces"]:
		return not bool(a["pieces"])
	return int(a["revenue"]) > int(b["revenue"])


## Возвращает выручку до коэффициента за время.
func _build_rows(places: Array[Dictionary]) -> int:
	if row_scene == null:
		push_error("SellStage: не назначена сцена строки сводки")
		return 0
	var gross := 0
	for place: Dictionary in places:
		gross += int(place["revenue"])
		var row := row_scene.instantiate() as SellRow
		if row == null:
			push_error("SellStage: сцена строки сводки — не SellRow")
			return gross
		# Сначала в дерево, потом настройка: узлы строки приходят
		# из @export и резолвятся только при входе в дерево.
		rows_container.add_child(row)
		row.setup(place["data"], place["revenue"], place["potential"],
			place["pieces"])
	# Пустая сводка бывает не только при проигрыше: стадию можно открыть
	# напрямую из редактора, и тогда пустой экран без подписи читается
	# как поломка.
	empty_label.visible = places.is_empty()
	return gross


## Номер товара в каталоге. Индекс строится лениво: экран открывается раз
## в день, и платить за него при загрузке сцены незачем.
func _order_of(id: StringName) -> int:
	if _catalog_order.is_empty():
		var index := 0
		for data: ItemData in ItemCatalog.all_items():
			_catalog_order[data.id] = index
			index += 1
	return int(_catalog_order.get(id, _catalog_order.size()))


func _on_next_day_pressed() -> void:
	GameState.advance_day()
	StageManager.instance.change_stage(StageManager.Stage.SHOP)
