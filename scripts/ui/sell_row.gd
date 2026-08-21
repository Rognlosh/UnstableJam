class_name SellRow
extends Control

## Строка сводки продажи: полоса во всю ширину — то, сколько товар стоил бы
## целым; заливка — то, что он дал на самом деле. Разрыв между ними и есть
## цена дороги, поэтому строка показывает именно его, а не число штук.
##
## Анимацией управляет стадия: строка лишь выставляет наружу два свойства,
## которые можно гнать твином, и сама пересчитывает вид при их изменении.

## Подпись вместо чисел, когда товар не доехал вовсе: «0 / 250» на пустой
## полосе читается как сбой расчёта, а не как потеря.
const LOST_KEY: String = "SELL_ROW_LOST"

## Заголовок строки осколков. Отдельным ключом с подстановкой, а не склейкой
## из двух слов: в других языках порядок слов другой, и «Ваза» + « осколки»
## переводчику не собрать.
const PIECES_KEY: String = "SELL_ROW_PIECES"

@export var track: ColorRect
@export var fill: ColorRect
@export var name_label: Label
@export var value_label: Label

## Цвет незаполненной части. Заливка красится цветом товара из каталога,
## поэтому её здесь нет.
@export var track_color: Color = Color(0.15, 0.14, 0.13, 0.85)

var _title: String = ""
var _revenue: int = 0
var _potential: int = 0
var _fill_color: Color = Color.WHITE


## Доля заливки, 0..1. Ширина задаётся якорем, а не размером: строка живёт
## в контейнере, и выставленный руками size.x он перетрёт на ближайшей
## пересортировке — при изменении окна в том числе.
var fill_ratio: float = 0.0:
	set(value):
		fill_ratio = clampf(value, 0.0, 1.0)
		if is_node_ready():
			_apply_fill()

## Число, которое сейчас показано слева от дроби. Отдельным свойством,
## чтобы твин гнал его от нуля синхронно с полосой. Хранится float:
## твин работает с дробными значениями, округляем только при выводе.
var shown_revenue: float = 0.0:
	set(value):
		shown_revenue = value
		if is_node_ready():
			_apply_text()


func _ready() -> void:
	_apply_all()


## Товар строки и её числа. Вызывается один раз при создании: за время
## показа экрана итог заезда уже не меняется.
##
## pieces — строка про черепки, а не про целые вещи. Различие чисто
## показное: у осколков свой заголовок и приглушённый цвет, ровно как
## у самих осколков в кузове.
func setup(item: ItemData, gained: int, full_price: int, pieces: bool = false) -> void:
	# Развёрнутое ветвление вместо тернарника: tr() % ... отдаёт Variant,
	# и парсер справедливо ругается на несовместимость веток.
	if pieces:
		_title = str(tr(PIECES_KEY) % item.get_display_name())
		# Осколки на полке темнее целого товара — строка держит то же правило.
		_fill_color = item.color.darkened(0.2)
	else:
		_title = item.get_display_name()
		_fill_color = item.color
	_revenue = maxi(gained, 0)
	_potential = maxi(full_price, 0)
	# Строка сразу показывает итог, а не ноль: анимация — надстройка,
	# и без неё экран обязан быть верным. Кто собирается анимировать,
	# сам отматывает строку в начало через rewind().
	fill_ratio = target_ratio()
	shown_revenue = float(_revenue)
	# is_node_ready() отсекает случай, когда строку настроили сразу после
	# instantiate(): узлы из @export резолвятся только при входе в дерево.
	if is_node_ready():
		_apply_all()


## Отмотка строки в начало — точка входа для анимации: пустая полоса
## и ноль в счётчике. Отдельным методом, а не состоянием по умолчанию,
## чтобы строка без анимации оставалась осмысленной.
func rewind() -> void:
	fill_ratio = 0.0
	shown_revenue = 0.0


## Доля, до которой стадии надо докрутить полосу.
func target_ratio() -> float:
	if _potential <= 0:
		return 0.0
	return clampf(float(_revenue) / float(_potential), 0.0, 1.0)


func revenue() -> int:
	return _revenue


func potential() -> int:
	return _potential


func _apply_all() -> void:
	track.color = track_color
	fill.color = _fill_color
	name_label.text = _title
	_apply_fill()
	_apply_text()


func _apply_fill() -> void:
	# keep_offset = true здесь обязателен. По умолчанию Godot, меняя якорь,
	# пересчитывает отступы так, чтобы прямоугольник остался на месте —
	# то есть якорь не изменил бы ровным счётом ничего.
	fill.set_anchor(SIDE_RIGHT, fill_ratio, true)


func _apply_text() -> void:
	if _revenue <= 0:
		value_label.text = tr(LOST_KEY)
		return
	value_label.text = "%d / %d" % [int(round(shown_revenue)), _potential]
