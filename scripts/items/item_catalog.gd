class_name ItemCatalog
extends RefCounted

## Единственная точка, через которую груз резолвится из идентификатора.
## Всё, что знает про предметы только по id (склад, стадия перевозки,
## витрина закупа), ходит сюда.
##
## Сами предметы лежат в .tres-ресурсах и правятся в инспекторе: цена, масса,
## порог удара балансируются без единой правки кода. Добавить товар — значит
## скопировать существующий .tres, поправить поля и дописать его в массив
## внутри catalog.tres.
##
## Каталог подключён через preload, а не поиском файлов в папке: при экспорте
## Godot конвертирует текстовые ресурсы в бинарные, и обход папки по маске
## *.tres в веб-сборке нашёл бы пустоту.
const DATABASE: ItemDatabase = preload("res://assets/items/catalog.tres")

## Индекс id → ItemData. Строится один раз за сессию: сам по себе поиск
## по двум предметам ничего не стоит, но индекс заодно ловит дубли id.
## static var — переменная класса, а не экземпляра (аналог static field в C#).
static var _by_id: Dictionary = {}


static func get_by_id(id: StringName) -> ItemData:
	_ensure_index()
	if not _by_id.has(id):
		push_warning("ItemCatalog: неизвестный предмет %s" % id)
		return null
	return _by_id[id]


## Идентификаторы всего, что есть в каталоге, в порядке из catalog.tres.
static func all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for data: ItemData in all_items():
		ids.append(data.id)
	return ids


## Все предметы каталога — этим пользуется витрина закупа.
static func all_items() -> Array[ItemData]:
	if DATABASE == null:
		push_error("ItemCatalog: каталог не загрузился")
		var empty: Array[ItemData] = []
		return empty
	return DATABASE.items


static func _ensure_index() -> void:
	if not _by_id.is_empty():
		return
	for data: ItemData in all_items():
		if data == null:
			push_error("ItemCatalog: в каталоге пустая строка — проверь catalog.tres")
			continue
		if data.id == &"":
			push_error("ItemCatalog: у предмета \"%s\" не заполнен id" % data.name_key)
			continue
		if _by_id.has(data.id):
			# Молчаливый дубль — худший случай: половина игры работает
			# с одним предметом, половина с другим.
			push_error("ItemCatalog: id %s встречается дважды" % data.id)
			continue
		_by_id[data.id] = data
