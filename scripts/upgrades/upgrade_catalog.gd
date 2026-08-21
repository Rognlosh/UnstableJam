class_name UpgradeCatalog
extends RefCounted

## Единственная точка резолва прокачки по идентификатору — зеркало
## ItemCatalog, вплоть до причин: preload вместо обхода папки (при экспорте
## текстовые ресурсы становятся бинарными, и поиск по маске *.tres в вебе
## нашёл бы пустоту) и ленивый индекс, который заодно ловит дубли id.
##
## Здесь же живут идентификаторы линий. Код о прокачках знать вынужден:
## значение надо куда-то приложить, а высоту борта от числа полок не отличит
## никакая система эффектов. Но знание собрано в одном месте и сведено
## к именам — что означает число, решает применяющая сторона.
const DATABASE: UpgradeDatabase = preload("res://assets/upgrades/catalog.tres")

## Лавка наставника. Единственная линия, про которую код знает не только имя:
## её покупка — это финал игры, и обработать её как остальные нельзя.
const SHOP_DEED_ID: StringName = &"shop_deed"
## Число полок на складе — читает ShelfLayout.
const SHELVES_ID: StringName = &"shelves"
## Высота бортов кузова в пикселях.
const BED_WALLS_ID: StringName = &"bed_walls"
## Множитель момента мотора.
const ENGINE_ID: StringName = &"engine"
## Радиус колеса в пикселях.
const WHEELS_ID: StringName = &"wheels"
## Множитель прочности груза.
const PADDING_ID: StringName = &"padding"

static var _by_id: Dictionary = {}


static func get_by_id(id: StringName) -> UpgradeData:
	_ensure_index()
	if not _by_id.has(id):
		push_warning("UpgradeCatalog: неизвестная прокачка %s" % id)
		return null
	return _by_id[id]


static func all_upgrades() -> Array[UpgradeData]:
	if DATABASE == null:
		push_error("UpgradeCatalog: каталог не загрузился")
		var empty: Array[UpgradeData] = []
		return empty
	return DATABASE.upgrades


## Текущее значение параметра с учётом купленных ступеней. Главный метод
## всего каталога: стадии зовут именно его и не спрашивают, куплено ли
## что-нибудь вообще — без покупок вернётся база из ресурса.
##
## fallback нужен на случай, когда линии в каталоге нет вовсе: прокачку
## должно быть можно вырезать из catalog.tres, не роняя игру.
static func value_of(id: StringName, fallback: float) -> float:
	_ensure_index()
	if not _by_id.has(id):
		return fallback
	var data: UpgradeData = _by_id[id]
	return data.value_at(GameState.upgrade_level(id))


## Цена следующей ступени. Ноль означает, что покупать больше нечего.
static func next_price(data: UpgradeData) -> int:
	if data == null:
		return 0
	return data.price_at(GameState.upgrade_level(data.id) + 1)


## Цена лавки — она же цель партии. Спрашивают её в двух местах (шапка закупа
## и строка витрины), и оба должны брать одно число из одного ресурса.
## Ноль означает, что записи в каталоге нет: тогда цель просто не показывается,
## а не показывается нулём.
static func shop_deed_price() -> int:
	var deed := get_by_id(SHOP_DEED_ID)
	return deed.price_at(1) if deed != null else 0


static func _ensure_index() -> void:
	if not _by_id.is_empty():
		return
	for data: UpgradeData in all_upgrades():
		if data == null:
			push_error("UpgradeCatalog: в каталоге пустая строка — проверь catalog.tres")
			continue
		if data.id == &"":
			push_error("UpgradeCatalog: у прокачки \"%s\" не заполнен id" % data.name_key)
			continue
		if _by_id.has(data.id):
			push_error("UpgradeCatalog: id %s встречается дважды" % data.id)
			continue
		_by_id[data.id] = data
