## Стадия перевозки — ЗАГЛУШКА этапа 0.
## Здесь на этапе 1 появятся грузовик, трасса и физика груза.
## Сейчас просто имитируем исход заезда и пишем его в GameState.run_result.
extends Control

@onready var _info_label: Label = $VBoxContainer/InfoLabel
@onready var _finish_button: Button = $VBoxContainer/FinishButton


func _ready() -> void:
	_finish_button.pressed.connect(_on_finish_pressed)
	_info_label.text = "ПЕРЕВОЗКА (заглушка)\nВезём: %d шт.\nДень: %d" % [
		GameState.cargo_actual.size(),
		GameState.get_day(),
	]


func _on_finish_pressed() -> void:
	# Имитация исхода: половина груза доезжает целой, остальное бьётся.
	# Формат словаря фиксируем здесь — стадия продажи на него опирается.
	var total: int = GameState.cargo_actual.size()
	var delivered: int = total / 2  # целочисленное деление, дробная часть отбрасывается
	GameState.run_result = {
		"delivered": delivered,
		"broken": total - delivered,
		"lost": 0,
	}
	StageManager.instance.change_stage(StageManager.Stage.SELL)
