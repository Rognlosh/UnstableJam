## Стадия продажи: превращает итог заезда в деньги и закрывает день.
##
## Сводка идёт по типам МЕСТА, а не по типам товара: ваза, поехавшая целой,
## остаётся вазой, даже если приехала грудой черепков, а черепок со склада —
## отдельная строка. Иначе потенциал строки врёт: четыре черепка и одна ваза
## обещали бы 250 монет при физическом потолке в 90.
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


func _ready() -> void:
	next_day_button.pressed.connect(_on_next_day_pressed)
	_sell_cargo()


## Выручка считается по долям доехавшей ценности, а не по числу ящиков:
## ваза без одного донца стоит дешевле целой, но дороже нуля. Поверх этого
## ложится коэффициент за скорость: за долгую доставку платят меньше.
func _sell_cargo() -> void:
	var groups := _group_run()
	var gross := _build_rows(groups)

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


## Сведение записей заезда в группы. Ключ — идентификатор товара плюс
## признак осколка; в значении копятся две суммы долей: доехавшая
## и стартовая. Считаем в долях, а не в монетах, чтобы округлять
## один раз на группу, а не на каждое место.
func _group_run() -> Dictionary:
	# get() со значением по умолчанию — на случай, если стадию открыли
	# в обход перевозки (например, запустив сцену напрямую из редактора).
	var items: Array = GameState.run_result.get("items", [])
	var groups: Dictionary = {}
	for entry: Dictionary in items:
		var data := ItemCatalog.get_by_id(entry.get("id", &""))
		if data == null:
			continue
		var start: float = entry.get("start", 1.0)
		# Стартовая доля меньше единицы бывает только у черепка:
		# целую вещь грузят целиком или не грузят вовсе.
		var pieces := not is_equal_approx(start, 1.0)
		var key := _group_key(data.id, pieces)
		if not groups.has(key):
			groups[key] = {"data": data, "pieces": pieces, "ratio": 0.0, "start": 0.0}
		var group: Dictionary = groups[key]
		group["ratio"] = float(group["ratio"]) + float(entry.get("ratio", 0.0))
		group["start"] = float(group["start"]) + start
	return groups


## Строки строятся в порядке каталога, а не в порядке словаря: так позиция
## товара на экране не прыгает от дня ко дню. Возвращает выручку до
## коэффициента за время.
func _build_rows(groups: Dictionary) -> int:
	if row_scene == null:
		push_error("SellStage: не назначена сцена строки сводки")
		return 0
	var gross := 0
	for data: ItemData in ItemCatalog.all_items():
		for pieces: bool in [false, true]:
			var key := _group_key(data.id, pieces)
			if not groups.has(key):
				continue
			var group: Dictionary = groups[key]
			var revenue := int(round(float(data.base_price) * float(group["ratio"])))
			var potential := int(round(float(data.base_price) * float(group["start"])))
			gross += revenue
			var row := row_scene.instantiate() as SellRow
			if row == null:
				push_error("SellStage: сцена строки сводки — не SellRow")
				return gross
			# Сначала в дерево, потом настройка: узлы строки приходят
			# из @export и резолвятся только при входе в дерево.
			rows_container.add_child(row)
			row.setup(data, revenue, potential, pieces)
	# Пустая сводка бывает не только при проигрыше: стадию можно открыть
	# напрямую из редактора, и тогда пустой экран без подписи читается
	# как поломка.
	empty_label.visible = rows_container.get_child_count() == 0
	return gross


## Ключ группы. Строкой, а не вложенными словарями: словарь словарей
## пришлось бы разбирать в двух местах вместо одного.
static func _group_key(id: StringName, pieces: bool) -> String:
	return "%s|%d" % [id, int(pieces)]


func _on_next_day_pressed() -> void:
	GameState.advance_day()
	StageManager.instance.change_stage(StageManager.Stage.SHOP)
