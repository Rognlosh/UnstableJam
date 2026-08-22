## Пауза. Слой поверх всей игры, живёт в Main.tscn рядом с затемнением
## и не выгружается никогда — стадии приходят и уходят, пауза одна.
##
## Дублировать оверлей в каждой стадии было бы пять мест, которые разъедутся;
## к тому же выход в главное меню нужен на всех экранах, а останавливать
## физику — только на заезде.
##
## Режим обработки узла — «Всегда» (Always), а не «Когда пауза» (When Paused).
## Второе выглядит логичнее, но такой узел не получает ввод, пока пауза
## не включена, и открыть её оказывается нечем.
extends CanvasLayer

## Корень видимой части. Прячем его, а не сам CanvasLayer: так внутри
## сохраняется обычная логика Control'ов, а перехват мыши остаётся на месте.
@export var root: Control
@export var resume_button: Button
@export var exit_button: Button
@export var settings_panel: Node

## Выход в меню подтверждается вторым нажатием той же кнопки. Диалог тут
## был бы лишней сценой ради одного вопроса, а без подтверждения промах
## мышью стоит всей партии — сохранений в игре нет.
var _exit_armed: bool = false


func _ready() -> void:
	root.visible = false
	resume_button.pressed.connect(_close)
	exit_button.pressed.connect(_on_exit_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if root.visible:
		_close()
	elif _can_open():
		_open()
	else:
		return
	get_viewport().set_input_as_handled()


## Паузу пускаем не всегда. В главном меню останавливать нечего, а посреди
## перехода между стадиями дерево вообще в разобранном состоянии: старая
## сцена уже выгружена, твин затемнения ещё играет.
func _can_open() -> bool:
	var manager: StageManager = StageManager.instance
	if manager == null or manager.is_transitioning():
		return false
	return manager.get_current_stage() != StageManager.Stage.MENU


func _open() -> void:
	# Ползунки могли поменяться в главном меню — панель в паузе живёт
	# в дереве всё время, и её _ready() был один раз за всю игру.
	if settings_panel != null and settings_panel.has_method(&"refresh"):
		settings_panel.call(&"refresh")
	_disarm_exit()
	root.visible = true
	get_tree().paused = true
	resume_button.grab_focus()


func _close() -> void:
	root.visible = false
	get_tree().paused = false
	_disarm_exit()


func _on_exit_pressed() -> void:
	if not _exit_armed:
		_exit_armed = true
		exit_button.text = "PAUSE_EXIT_CONFIRM"
		return

	# Снять паузу обязательно ДО смены стадии: твин затемнения создаётся
	# на узле менеджера, а тот стоит вместе с деревом — переход завис бы
	# на середине чёрного экрана, и выйти оттуда было бы уже нечем.
	_close()
	StageManager.instance.change_stage(StageManager.Stage.MENU)


func _disarm_exit() -> void:
	_exit_armed = false
	exit_button.text = "PAUSE_EXIT"
