class_name HoldButton
extends Button

## Кнопка, которую надо удерживать. Вокруг неё рисуется кольцо прогресса,
## и только когда оно замкнётся, действие срабатывает.
##
## Смысл в защите от случайного нажатия: сброс заезда стирает всё, что
## игрок проехал, и промах мышью не должен этого делать.

signal hold_completed

## Сколько держать до срабатывания.
@export var hold_time: float = 0.9
## Радиус кольца. Считается от центра кнопки.
@export var ring_radius: float = 30.0
@export var ring_width: float = 5.0
@export var ring_color: Color = Color(1.0, 1.0, 1.0, 0.9)
## Как быстро кольцо откатывается назад, если кнопку отпустили раньше.
@export var release_speed: float = 3.0

var _holding: bool = false
var _progress: float = 0.0


func _ready() -> void:
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	# Мышь могла уйти с кнопки с зажатой клавишей — тогда button_up
	# не придёт, и без этого кольцо застыло бы заполненным.
	mouse_exited.connect(_on_button_up)


func _process(delta: float) -> void:
	var previous := _progress
	if _holding:
		_progress = minf(_progress + delta / maxf(hold_time, 0.01), 1.0)
		if _progress >= 1.0:
			_holding = false
			_progress = 0.0
			hold_completed.emit()
	else:
		_progress = maxf(_progress - delta * release_speed, 0.0)
	# Перерисовываем только когда есть что показывать.
	if not is_equal_approx(previous, _progress):
		queue_redraw()


func _draw() -> void:
	if _progress <= 0.0:
		return
	var center := size * 0.5
	# Отсчёт от верхней точки по часовой стрелке — так читается как таймер.
	var from := -PI * 0.5
	draw_arc(center, ring_radius, from, from + TAU * _progress, 48, ring_color, ring_width, true)


func _on_button_down() -> void:
	_holding = true


func _on_button_up() -> void:
	_holding = false
