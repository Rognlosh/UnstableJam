## Стадия закупа: витрина товаров, лавка наставника и склад.
##
## Единственное место в игре, где тратятся деньги, — и поэтому же
## единственное, где живут прокачки. Строки витрины про деньги не знают,
## они лишь сообщают, что кнопку нажали: разделение нужно ради будущего
## аукциона, у которого другой источник лотов, но та же покупка.
extends Control

@export var header_label: Label
@export var tabs: TabContainer
@export var lots_container: VBoxContainer
@export var stock_label: Label
@export var go_button: Button
## Сцена строки витрины. Через @export, а не preload: сцену видно
## в инспекторе и её можно подменить, не открывая скрипт.
@export var lot_scene: PackedScene

@export_group("Лавка наставника")
@export var upgrades_container: VBoxContainer
@export var upgrade_lot_scene: PackedScene
## Строка подачки стоит в сцене готовой, а не создаётся кодом: она одна,
## её место на вкладке товара фиксировано, и прятать готовый узел дешевле,
## чем каждый раз пересобирать.
@export var handout_lot: UpgradeLot
@export var handout: HandoutData

## Строка витрины → её товар. Словарь, а не два параллельных массива:
## параллельные массивы разъезжаются ровно тогда, когда про них забываешь.
var _lots: Dictionary = {}
## Строка лавки → её прокачка.
var _upgrade_lots: Dictionary = {}


func _ready() -> void:
	go_button.pressed.connect(_on_go_pressed)
	GameState.money_changed.connect(_on_money_changed)
	# Заголовки вкладок в коде, а не именами узлов: имя узла ключом
	# локализации быть не может, а вкладки должны переводиться вместе
	# со всем остальным.
	if tabs != null:
		tabs.set_tab_title(0, tr("SHOP_TAB_GOODS"))
		tabs.set_tab_title(1, tr("SHOP_TAB_UPGRADES"))
	if handout_lot != null:
		handout_lot.activated.connect(_on_handout_pressed)
	_build_lots()
	_build_upgrades()
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


## Лавка наставника. Купленные прокачки со вкладки не убираются, а гаснут:
## список — это ещё и напоминание, что уже сделано.
func _build_upgrades() -> void:
	if upgrades_container == null or upgrade_lot_scene == null:
		return
	for data: UpgradeData in UpgradeCatalog.all_upgrades():
		var lot := upgrade_lot_scene.instantiate() as UpgradeLot
		if lot == null:
			push_error("ShopStage: сцена строки прокачки — не UpgradeLot")
			return
		upgrades_container.add_child(lot)
		lot.setup(data.get_display_name(), data.get_hint())
		# bind() докладывает аргумент к сигналу: activated приходит пустым,
		# а обработчику нужна прокачка, по которой кликнули.
		lot.activated.connect(_on_upgrade_pressed.bind(data))
		_upgrade_lots[lot] = data


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


## Покупка прокачки. Лавка обрабатывается здесь же особым случаем — их одна
## на игру, и заводить ради неё систему эффектов на день до фриза незачем.
func _on_upgrade_pressed(data: UpgradeData) -> void:
	if data == null or GameState.has_upgrade(data.id):
		return
	if not GameState.spend_money(data.price):
		return
	GameState.purchased_upgrades.append(data.id)
	if data.id == UpgradeCatalog.SHOP_DEED_ID:
		# Финал показывается ровно здесь и ровно один раз: повторно купить
		# лавку нельзя, поэтому отдельный флаг «победу видели» не нужен.
		StageManager.instance.change_stage(StageManager.Stage.VICTORY)
		return
	_refresh()


## Ящик от наставника. Кладётся на склад целиком, деньги не трогает.
func _on_handout_pressed() -> void:
	if not _handout_available():
		return
	for item: ItemData in handout.items:
		if item != null:
			GameState.cargo_actual.append(GameState.cargo_entry(item.id))
	_refresh()


## Условие выдачи — факт нищеты, а не остаток места на полке. Проверяй мы
## место, бесплатным товаром выгодно было бы затыкать щели каждый день,
## и аварийная механика превратилась бы в ежедневную рутину.
func _handout_available() -> bool:
	if handout == null or handout.items.is_empty():
		return false
	if not GameState.cargo_actual.is_empty():
		return false
	return GameState.get_money() < _cheapest_buy_price()


## Самый дешёвый лот витрины. Порог считается от каталога, а не константой:
## подешевей товар — и подачка перестала бы выдаваться там, где надо.
func _cheapest_buy_price() -> int:
	var cheapest := -1
	for item: ItemData in ItemCatalog.all_items():
		if cheapest < 0 or item.buy_price < cheapest:
			cheapest = item.buy_price
	return maxi(cheapest, 0)


func _on_go_pressed() -> void:
	StageManager.instance.change_stage(StageManager.Stage.DRIVE)


func _refresh() -> void:
	var money := GameState.get_money()
	header_label.text = _header_text(money)

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

	_refresh_upgrades(money)
	_refresh_handout()

	stock_label.text = _stock_text(whole, fragments)
	# Ехать пустым бессмысленно: заезд закончится итогом из одних нулей.
	go_button.disabled = GameState.cargo_actual.is_empty()


## Шапка. Цель показывается, пока лавка не выкуплена: без неё непонятно,
## к чему копить, а после покупки строка превратилась бы в напоминание
## о том, что копить больше не на что.
func _header_text(money: int) -> String:
	var day := GameState.get_day()
	var price := UpgradeCatalog.shop_deed_price()
	if price <= 0 or GameState.has_upgrade(UpgradeCatalog.SHOP_DEED_ID):
		return tr("SHOP_HEADER") % [day, money]
	return tr("SHOP_HEADER_GOAL") % [day, money, maxi(price - money, 0)]


## Кнопка прокачки говорит, чего не хватает: серая кнопка без причины
## читается как поломка. Та же логика, что у «Нет места» на витрине.
func _refresh_upgrades(money: int) -> void:
	for lot: UpgradeLot in _upgrade_lots:
		var data: UpgradeData = _upgrade_lots[lot]
		if GameState.has_upgrade(data.id):
			lot.set_action(tr("UPGRADE_OWNED"), false)
		elif money >= data.price:
			lot.set_action("%s · %d" % [tr("UPGRADE_BUY"), data.price], true)
		else:
			lot.set_action(tr("UPGRADE_SHORT") % (data.price - money), false)


func _refresh_handout() -> void:
	if handout_lot == null:
		return
	var available := _handout_available()
	handout_lot.visible = available
	if available:
		handout_lot.setup(tr(handout.name_key), tr(handout.hint_key))
		handout_lot.set_action(tr("SHOP_HANDOUT_TAKE"), true)


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
			parts.append("%s × %d" % [item.get_display_name(), count])
	if fragments > 0:
		parts.append("осколки × %d" % fragments)
	if parts.is_empty():
		return shelves + "   •   склад пуст"
	return shelves + "   •   " + ", ".join(parts)
