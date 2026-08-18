class_name TimerBar
extends ProgressBar

## Полоса времени заезда с отметкой бесплатного проезда.
##
## Полоса делится на два участка: пока заполнение не дошло до отметки,
## доставка оплачивается полностью; дальше начинается зона, где доход
## убывает. Границу рисуем сами — так видно не только «сколько прошло»,
## но и «когда начнёт дешеветь».

## Доля полосы, которая проходит без штрафа. Ставится стадией.
@export_range(0.0, 1.0, 0.05) var free_share: float = 0.75:
	set(value):
		free_share = clampf(value, 0.0, 1.0)
		queue_redraw()

## Цвет зоны, в которой доход падает.
@export var late_color: Color = Color(0.75, 0.35, 0.25, 0.55)
## Цвет разделительной черты.
@export var mark_color: Color = Color(1.0, 1.0, 1.0, 0.8)
@export var mark_width: float = 2.0


func _ready() -> void:
	# Проценты на самой полосе не нужны: рядом висит подпись со временем.
	show_percentage = false


func _draw() -> void:
	var mark_x := size.x * free_share
	# Хвост полосы подкрашиваем целиком, а не только пройденную часть:
	# зона штрафа должна быть видна заранее, а не появляться по факту.
	draw_rect(Rect2(mark_x, 0.0, size.x - mark_x, size.y), late_color)
	draw_line(Vector2(mark_x, 0.0), Vector2(mark_x, size.y), mark_color, mark_width)
