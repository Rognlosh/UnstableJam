class_name ShelfLayout
extends RefCounted

## Раскладка склада по полкам. Живёт отдельно от стадий, потому что считать
## её нужно дважды и одинаково: закуп должен сказать «не влезет» ещё до заезда,
## а заезд — расставить то же самое телами. Разъедься эти два расчёта, и
## магазин разрешит покупку, которой некуда встать.

## Полезная длина полки и зазор между вещами. Отсюда их берёт и стадия
## перевозки: значения обязаны совпадать.
const WIDTH: float = 380.0
const GAP: float = 10.0
## Сколько полок в стеллаже без прокачек. Дальше их число растёт линией
## SHELVES, поэтому спрашивать вместимость надо через max_levels(),
## а не через эту константу.
const BASE_LEVELS: int = 1


## Вместимость склада с учётом купленных полок. Значение живёт в каталоге
## прокачек, а не здесь: полки — покупка, и цена с числом ступеней правятся
## в инспекторе вместе с остальными линиями.
static func max_levels() -> int:
	return int(UpgradeCatalog.value_of(UpgradeCatalog.SHELVES_ID, float(BASE_LEVELS)))


## Сколько полок занимают эти записи склада. Осколки пропускаются: битое
## сваливают в нишу под стеллажом, к полкам оно отношения не имеет.
static func levels_used(entries: Array) -> int:
	return _pack(_widths(entries))


## Влезет ли ещё одна такая вещь сверх того, что уже лежит.
static func fits(entries: Array, extra: ItemData) -> bool:
	if extra == null:
		return false
	var widths := _widths(entries)
	widths.append(extra.get_bounds().size.x)
	return _pack(widths) <= max_levels()


## Свободные полки — для строки состояния склада.
static func levels_left(entries: Array) -> int:
	return maxi(0, max_levels() - levels_used(entries))


static func _widths(entries: Array) -> PackedFloat32Array:
	var widths := PackedFloat32Array()
	for entry: Dictionary in entries:
		# Непустой piece — это осколок, он в нишу.
		if entry.get("piece", &"") != &"":
			continue
		var data := ItemCatalog.get_by_id(entry.get("id", &""))
		if data == null:
			continue
		widths.append(data.get_bounds().size.x)
	return widths


## Та же жадная укладка, что и в заезде: кладём в ряд, пока влезает по
## ширине, потом переходим ярусом выше. Возвращает число занятых ярусов.
static func _pack(widths: PackedFloat32Array) -> int:
	if widths.is_empty():
		return 0
	var cursor := 0.0
	var level := 0
	for w: float in widths:
		# Условие про непустой ряд спасает от вечного переноса вещи,
		# которая шире всей полки.
		if cursor + w > WIDTH and cursor > 0.0:
			level += 1
			cursor = 0.0
		cursor += w + GAP
	return level + 1
