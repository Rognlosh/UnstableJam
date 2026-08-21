## Сюжетный экран: текст и одна кнопка. Обслуживает и вступление, и финал —
## разница между ними только в содержимом сцены и в том, куда ведёт кнопка.
##
## Текста в скрипте нет намеренно. Godot переводит свойство text у Label сам,
## поэтому в метку в редакторе пишется ключ (INTRO_P1, VICTORY_P1 и так далее),
## а сами формулировки живут в localization/ui.csv. Править их можно, не
## открывая ни одного скрипта, и английская версия появляется там же, где
## русская, а не отдельным заходом перед сдачей.
extends Control

## Куда ведёт кнопка. Экспортом, а не константой: сцен две, скрипт один.
@export var next_stage: StageManager.Stage = StageManager.Stage.SHOP
@export var continue_button: Button


func _ready() -> void:
	if continue_button == null:
		push_error("StoryStage: не назначена кнопка продолжения")
		return
	continue_button.pressed.connect(_on_continue_pressed)


func _on_continue_pressed() -> void:
	StageManager.instance.change_stage(next_stage)
