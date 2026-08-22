## Стадия закупа: витрина товаров, лавка наставника и склад.
##
## Единственное место в игре, где тратятся деньги, — теперь на двух вкладках.
## Товар и прокачки разведены не по смыслу «покупок двух сортов», а по частоте:
## товар берут каждый день, прокачку — считаное число раз за партию, и мешать
## их в один список значит топить витрину строками, которые почти всегда
## недоступны.
##
## Строки про деньги не знают: витрине сообщают, хватает ли, а решение
## принимает стадия. Разделение нужно ради будущего аукциона — у него другой
## источник лотов, но та же покупка.
extends Control

@export var header_label: Label
@export var tabs: TabContainer
@export var lots_container: VBoxContainer
@export var upgrades_container: VBoxContainer
@export var stock_label: Label
@export var go_button: Button
## Сцена строки витрины. Через @export, а не preload: сцену видно
## в инспекторе и её можно подменить, не открывая скрипт.
@export var lot_scene: PackedScene
## Сцена строки-предложения — ею рисуются и прокачки, и бесплатный ящик.
@export var offer_lot_scene: PackedScene
## Набор подачки. Ресурсом, а не константой: состав ящика балансируется
## в инспекторе вместе с ценами предметов.
@export var handout: HandoutData

## Строка витрины → её товар. Словарь, а не два параллельных массива:
## параллельные массивы разъезжаются ровно тогда, когда про них забываешь.
var _lots: Dictionary = {}
## Строка лавки → её прокачка.
var _upgrade_lots: Dictionary = {}
## Строка бесплатного ящика. Живёт на вкладке товара и прячется целиком,
## пока игрок не на дне.
var _handout_lot: OfferLot = null
## Самый дешёвый закуп в каталоге — порог, ниже которого игрок считается
## неспособным купить хоть что-нибудь. Считается один раз: каталог за время
## работы игры не меняется.
var _cheapest_price: int = -1


func _ready() -> void:
	go_button.pressed.connect(_on_go_pressed)
	GameState.money_changed.connect(_on_money_changed)
	_setup_tabs()
	_build_handout()
	_build_lots()
	_build_upgrades()
	_refresh()


## Заголовки вкладок ставим кодом, а не именами узлов: имя узла — это ещё
## и путь в NodePath, и переименовывать его ради перевода нельзя.
func _setup_tabs() -> void:
	if tabs == null:
		return
	tabs.set_tab_title(0, tr("SHOP_TAB_GOODS"))
	tabs.set_tab_title(1, tr("SHOP_TAB_UPGRADES"))


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


## Лавка наставника. Пустой каталог прокачек — не ошибка: вкладка просто
## останется пустой, и это верное поведение, если прокачки вырежут из скоупа.
func _build_upgrades() -> void:
	if offer_lot_scene == null or upgrades_container == null:
		return
	for upgrade: UpgradeData in UpgradeCatalog.all_upgrades():
		if upgrade == null:
			continue
		var lot := _make_offer(upgrades_container)
		if lot == null:
			return
		lot.setup(upgrade.get_display_name(), upgrade.get_hint())
		# bind() докладывает аргумент к вызову обработчика — сам по себе
		# сигнал не знает, какой строке он принадлежит.
		lot.action_pressed.connect(_on_upgrade_pressed.bind(upgrade))
		_upgrade_lots[lot] = upgrade


## Бесплатный ящик стоит первым на вкладке товара, до всех лотов: когда он
## виден, покупать всё равно нечего, и прятать его под шестью недоступными
## строками было бы издевательством.
func _build_handout() -> void:
	if offer_lot_scene == null or handout == null or handout.items.is_empty():
		return
	_handout_lot = _make_offer(lots_container)
	if _handout_lot == null:
		return
	_handout_lot.setup(tr(handout.name_key), tr(handout.hint_key))
	_handout_lot.action_pressed.connect(_on_handout_pressed)


func _make_offer(parent: VBoxContainer) -> OfferLot:
	var lot := offer_lot_scene.instantiate() as OfferLot
	if lot == null:
		push_error("ShopStage: сцена строки-предложения — не OfferLot")
		return null
	parent.add_child(lot)
	return lot


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


## Покупка следующей ступени. Что именно куплено, стадия не разбирает: она
## поднимает уровень линии, а значение с него читают те, кому оно нужно —
## заезд и раскладка склада. Особый случай здесь ровно один, и он не про
## эффект: покупка лавки заканчивает партию.
func _on_upgrade_pressed(upgrade: UpgradeData) -> void:
	if upgrade == null:
		return
	var level := GameState.upgrade_level(upgrade.id)
	if level >= upgrade.level_count():
		return
	# Проверка и списание — одной операцией: spend_money() возвращает false,
	# если не хватило, и тогда состояние не меняется вовсе.
	if not GameState.spend_money(upgrade.price_at(level + 1)):
		return
	GameState.set_upgrade_level(upgrade.id, level + 1)
	if upgrade.id == UpgradeCatalog.SHOP_DEED_ID:
		# Смена стадии сама перерисует всё, что нужно; обновлять витрину,
		# которую сейчас снесут, незачем. А вот записать партию надо здесь:
		# _refresh() с его сохранением на этой ветке не случится.
		GameState.save_game()
		StageManager.instance.change_stage(StageManager.Stage.VICTORY)
		return
	_refresh()


## Ящик от наставника. Условие выдачи проверяем ещё раз, а не полагаемся
## на спрятанную строку: между показом и нажатием состояние измениться
## не может, но правило важнее, чем текущая невозможность его нарушить.
func _on_handout_pressed() -> void:
	if not _handout_available():
		return
	for item: ItemData in handout.items:
		if item == null:
			continue
		GameState.cargo_actual.append(GameState.cargo_entry(item.id))
	_refresh()


## Игрок на дне: купить не может ничего и везти нечего. Оба условия
## обязательны. По одним деньгам ящик выдавался бы поверх полного склада,
## по одному пустому складу — богатому игроку, который просто ещё не начал
## закупаться.
func _handout_available() -> bool:
	if handout == null or handout.items.is_empty():
		return false
	if not GameState.cargo_actual.is_empty():
		return false
	return GameState.get_money() < _get_cheapest_price()


func _get_cheapest_price() -> int:
	if _cheapest_price >= 0:
		return _cheapest_price
	_cheapest_price = 0
	for item: ItemData in ItemCatalog.all_items():
		if item == null:
			continue
		if _cheapest_price == 0 or item.buy_price < _cheapest_price:
			_cheapest_price = item.buy_price
	return _cheapest_price


func _on_go_pressed() -> void:
	StageManager.instance.change_stage(StageManager.Stage.DRIVE)


func _refresh() -> void:
	var money := GameState.get_money()
	_refresh_header(money)

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

	# Единственная точка сохранения партии. Здесь потому, что через _refresh()
	# проходит любое изменение состояния в закупе — покупка, прокачка, ящик
	# от наставника, — и отдельные вызовы по обработчикам пришлось бы держать
	# в голове при добавлении следующей кнопки.
	GameState.save_game()


## Шапка держит и состояние дня, и цель партии: без неё непонятно, к чему
## копить. После выкупа цель уходит — строка «до лавки: 0» висела бы
## напоминанием о задаче, которой больше нет.
func _refresh_header(money: int) -> void:
	var day := GameState.get_day()
	var deed_price := UpgradeCatalog.shop_deed_price()
	if deed_price > 0 and not GameState.has_upgrade(UpgradeCatalog.SHOP_DEED_ID):
		header_label.text = tr("SHOP_HEADER_GOAL") % [
			day, money, maxi(0, deed_price - money),
		]
	else:
		header_label.text = tr("SHOP_HEADER") % [day, money]


## Строка лавки показывает, где линия сейчас стоит, и цену одного шага
## вперёд. Полную стоимость линии не показываем: копить игрок будет
## на ближайшую ступень, а сумма всех четырёх только отпугнёт.
func _refresh_upgrades(money: int) -> void:
	for lot: OfferLot in _upgrade_lots:
		var upgrade: UpgradeData = _upgrade_lots[lot]
		var level := GameState.upgrade_level(upgrade.id)
		var total := upgrade.level_count()
		lot.set_title(_upgrade_title(upgrade, level, total))
		if level >= total:
			# У линии из одной ступени «уровень 1 из 1» звучит как недоделка:
			# лавку покупают, а не прокачивают.
			lot.set_action(tr("UPGRADE_OWNED" if total <= 1 else "UPGRADE_MAXED"), false)
			continue
		var price := upgrade.price_at(level + 1)
		if money < price:
			# Показываем недостачу, а не цену: цену игрок уже прочёл выше,
			# а вопрос у него один — сколько ещё возить.
			lot.set_action(tr("UPGRADE_SHORT") % (price - money), false)
		else:
			lot.set_action(tr("UPGRADE_BUY") % price, true)


## Заголовок строки. Ступень дописывается к названию, а не отдельной меткой:
## иначе пришлось бы править сцену строки ради одного числа, а строка
## обслуживает ещё и бесплатный ящик, которому ступени не нужны.
func _upgrade_title(upgrade: UpgradeData, level: int, total: int) -> String:
	var title := upgrade.get_display_name()
	if total <= 1:
		return title
	return tr("UPGRADE_LEVEL") % [title, level, total]


func _refresh_handout() -> void:
	if _handout_lot == null:
		return
	var available := _handout_available()
	_handout_lot.visible = available
	if available:
		_handout_lot.set_action(tr("SHOP_HANDOUT_TAKE"), true)


## Строка склада. Числа пишем как «Ваза × 2», а не «2 вазы»: склонения
## пришлось бы хранить у каждого предмета, а выигрыш нулевой.
func _stock_text(whole: Dictionary, fragments: int) -> String:
	var used := ShelfLayout.levels_used(GameState.cargo_actual)
	var total := ShelfLayout.max_levels()
	var parts: PackedStringArray = PackedStringArray()
	# Идём по каталогу, а не по ключам словаря: так порядок в строке склада
	# совпадает с порядком витрины и не прыгает от покупки к покупке.
	for item: ItemData in ItemCatalog.all_items():
		var count: int = int(whole.get(item.id, 0))
		if count > 0:
			parts.append(tr("SHOP_STOCK_ITEM") % [item.get_display_name(), count])
	if fragments > 0:
		parts.append(tr("SHOP_STOCK_FRAGMENTS") % fragments)
	if parts.is_empty():
		return tr("SHOP_FOOTER_EMPTY") % [used, total]
	return tr("SHOP_FOOTER") % [used, total, ", ".join(parts)]
