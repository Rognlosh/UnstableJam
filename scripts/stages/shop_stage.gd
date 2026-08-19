## Стадия закупа: витрина товаров и склад.
##
## Единственное место в игре, где тратятся деньги. Строки витрины про деньги
## не знают — они лишь сообщают, что кнопку нажали. Разделение нужно ради
## будущего аукциона: у него другой источник лотов, но та же покупка.
extends Control

@export var header_label: Label
@export var lots_container: VBoxContainer
@export var stock_label: Label
@export var go_button: Button
## Сцена строки витрины. Через @export, а не preload: сцену видно
## в инспекторе и её можно подменить, не открывая скрипт.
@export var lot_scene: PackedScene

## Строка витрины → её товар. Словарь, а не два параллельных массива:
## параллельные массивы разъезжаются ровно тогда, когда про них забываешь.
var _lots: Dictionary = {}


func _ready() -> void:
	go_button.pressed.connect(_on_go_pressed)
	GameState.money_changed.connect(_on_money_changed)
	_build_lots()
	_refresh()


## Витрина строится один раз: состав каталога за время закупа не меняется.
func _build_lots() -> void:
	if lot_scene == null:
		push_error("ShopStage: не назначена сцена строки витрины")
		return
	for item: ItemData in ItemCatalog.all_items():
		var lot := lot_scene.instantiate() as ShopLot
		if lot == null:
			push_error("ShopStage: сцена строки витрины — не ShopLot")
			return
		# Сначала в дерево, потом настройка: узлы строки приходят
		# из @export и резолвятся только при входе в дерево.
		lots_container.add_child(lot)
		lot.setup(item)
		lot.buy_pressed.connect(_on_buy_pressed)
		_lots[lot] = item


func _on_money_changed(_new_amount: int) -> void:
	_refresh()


func _on_buy_pressed(item: ItemData) -> void:
	# Витрина гасит кнопку сама, но полагаться на состояние UI нельзя:
	# решение о месте принимает раскладка.
	if not ShelfLayout.fits(GameState.cargo_actual, item):
		return
	# Проверка и списание — одной операцией: spend_money() возвращает false,
	# если не хватило, и тогда состояние не меняется вовсе.
	if not GameState.spend_money(item.buy_price):
		return
	GameState.cargo_actual.append(GameState.cargo_entry(item.id))
	_refresh()


func _on_go_pressed() -> void:
	StageManager.instance.change_stage(StageManager.Stage.DRIVE)


func _refresh() -> void:
	var money := GameState.get_money()
	header_label.text = "ЗАКУП   —   день %d   —   деньги: %d" % [
		GameState.get_day(), money,
	]

	# Склад считаем один раз на всю витрину, а не по разу на строку.
	var whole: Dictionary = {}
	var fragments := 0
	for entry: Dictionary in GameState.cargo_actual:
		if entry.get("piece", &"") == &"":
			var id: StringName = entry.get("id", &"")
			whole[id] = int(whole.get(id, 0)) + 1
		else:
			fragments += 1

	for lot: ShopLot in _lots:
		var item: ItemData = _lots[lot]
		lot.refresh(int(whole.get(item.id, 0)), money,
			ShelfLayout.fits(GameState.cargo_actual, item))

	stock_label.text = _stock_text(whole, fragments)
	# Ехать пустым бессмысленно: заезд закончится итогом из одних нулей.
	go_button.disabled = GameState.cargo_actual.is_empty()


## Строка склада. Числа пишем как «Ваза × 2», а не «2 вазы»: склонения
## пришлось бы хранить у каждого предмета, а выигрыш нулевой.
func _stock_text(whole: Dictionary, fragments: int) -> String:
	var shelves := "Полки: %d / %d" % [
		ShelfLayout.levels_used(GameState.cargo_actual), ShelfLayout.MAX_LEVELS,
	]
	var parts: PackedStringArray = PackedStringArray()
	# Идём по каталогу, а не по ключам словаря: так порядок в строке склада
	# совпадает с порядком витрины и не прыгает от покупки к покупке.
	for item: ItemData in ItemCatalog.all_items():
		var count: int = int(whole.get(item.id, 0))
		if count > 0:
			parts.append("%s × %d" % [item.display_name, count])
	if fragments > 0:
		parts.append("осколки × %d" % fragments)
	if parts.is_empty():
		return shelves + "   •   склад пуст"
	return shelves + "   •   " + ", ".join(parts)
