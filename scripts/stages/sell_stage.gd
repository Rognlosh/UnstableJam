## Стадия продажи — ЗАГЛУШКА этапа 0.
## Читает GameState.run_result, начисляет выручку, закрывает день.
extends Control

## Цена продажи одного доехавшего предмета-заглушки.
## Выше закупочной (20) — иначе игра математически непроходима.
const DUMMY_ITEM_PRICE: int = 50

@onready var _info_label: Label = $VBoxContainer/InfoLabel
@onready var _next_day_button: Button = $VBoxContainer/NextDayButton


func _ready() -> void:
	_next_day_button.pressed.connect(_on_next_day_pressed)
	_sell_cargo()


## Продаём то, что доехало, и показываем итог дня.
func _sell_cargo() -> void:
	# get() со значением по умолчанию — на случай, если стадию открыли
	# в обход перевозки (например, запустив сцену напрямую из редактора).
	var delivered: int = GameState.run_result.get("delivered", 0)
	var broken: int = GameState.run_result.get("broken", 0)

	var revenue: int = delivered * DUMMY_ITEM_PRICE
	GameState.earn_money(revenue)

	_info_label.text = "ПРОДАЖА — итог дня %d\nДоехало: %d\nРазбито: %d\nВыручка: %d\nВсего денег: %d" % [
		GameState.get_day(),
		delivered,
		broken,
		revenue,
		GameState.get_money(),
	]


func _on_next_day_pressed() -> void:
	GameState.advance_day()
	StageManager.instance.change_stage(StageManager.Stage.SHOP)
