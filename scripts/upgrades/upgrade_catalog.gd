class_name UpgradeCatalog
extends RefCounted

## Единственная точка резолва прокачки по идентификатору — зеркало
## ItemCatalog, вплоть до причин: preload вместо обхода папки (при экспорте
## текстовые ресурсы становятся бинарными, и поиск по маске *.tres в вебе
## нашёл бы пустоту) и ленивый индекс, который заодно ловит дубли id.
const DATABASE: UpgradeDatabase = preload("res://assets/upgrades/catalog.tres")

## Идентификатор лавки наставника. Единственная прокачка, про которую знает
## код: её покупка — это финал игры, и обработать её как остальные нельзя.
const SHOP_DEED_ID: StringName = &"shop_deed"

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


## Цена лавки — она же цель партии. Спрашивают её в двух местах (шапка закупа
## и строка витрины), и оба должны брать одно число из одного ресурса.
## Ноль означает, что записи в каталоге нет: тогда цель просто не показывается,
## а не показывается нулём.
static func shop_deed_price() -> int:
	var deed := get_by_id(SHOP_DEED_ID)
	return deed.price if deed != null else 0


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
