@tool
class_name DebugShape
extends Node2D

## Временный визуал вместо арта: прямоугольник или круг, настраивается
## в инспекторе. Когда появятся рисованные спрайты — узлы этого типа
## заменяются на Sprite2D и скрипт удаляется.
##
## @tool означает «скрипт работает и в редакторе»: фигура рисуется прямо
## в окне сцены, поэтому грузовик можно собирать глазами, а не вслепую.

enum Kind {
	RECTANGLE,
	CIRCLE,
}

@export var kind: Kind = Kind.RECTANGLE:
	set(value):
		kind = value
		queue_redraw()

## Размер для прямоугольника (центр — в начале координат узла).
@export var size: Vector2 = Vector2(64.0, 32.0):
	set(value):
		size = value
		queue_redraw()

## Радиус для круга.
@export var radius: float = 24.0:
	set(value):
		radius = value
		queue_redraw()

@export var color: Color = Color(0.62, 0.52, 0.38):
	set(value):
		color = value
		queue_redraw()

@export var outline_color: Color = Color(0.13, 0.11, 0.1):
	set(value):
		outline_color = value
		queue_redraw()

@export var outline_width: float = 2.0:
	set(value):
		outline_width = value
		queue_redraw()


func _draw() -> void:
	match kind:
		Kind.RECTANGLE:
			var rect := Rect2(-size * 0.5, size)
			draw_rect(rect, color)
			if outline_width > 0.0:
				draw_rect(rect, outline_color, false, outline_width)
		Kind.CIRCLE:
			draw_circle(Vector2.ZERO, radius, color)
			if outline_width > 0.0:
				draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, outline_color, outline_width)
				# Спица: без неё вращение колеса на однотонном круге не видно.
				draw_line(Vector2.ZERO, Vector2(radius * 0.8, 0.0), outline_color, outline_width)
